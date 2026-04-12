import Combine
import Foundation
import SwiftUI

// MARK: - PlayerProfileService
//
// Manages cloud-synced player profile via the player-proxy Edge Function.
//
// On launch: fetches profile from Supabase. If none exists, creates one from
// local DataManager values. If an active admin override exists, applies it
// immediately and shows a toast, then acknowledges it to the server.
//
// Gold Pieces (GP):
//   • systemCredits — the player's current GP balance (server-authoritative)
//   • lifetimeCreditsEarned — total GP ever awarded
//   • addCredits(amount:type:referenceKey:) — awards GP and refreshes the balance
//   • getCreditHistory() — returns recent transactions for CreditHistoryView
//
// Sync triggers:
//   • Every level up (call syncProfile())
//   • App goes to background (scenePhase .background)
//   • Once per day (UserDefaults date gate)
//   • Streak milestones: 7, 14, 30 days
//
// Usage:
//   await PlayerProfileService.shared.refresh()
//   let id = PlayerProfileService.shared.playerId   // "RPT-XXXXX"
//   let gp = PlayerProfileService.shared.systemCredits

@MainActor
final class PlayerProfileService: ObservableObject {

    static let shared = PlayerProfileService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    /// The stable RPT-XXXXX player identifier, empty until first successful fetch.
    @Published private(set) var playerId: String = ""

    /// Current Gold Pieces balance (server-authoritative).
    @Published private(set) var systemCredits: Int = 0

    /// Total GP ever awarded (informational).
    @Published private(set) var lifetimeCreditsEarned: Int = 0

    /// Whether the current player has admin privileges (server-authoritative, session-only).
    @Published private(set) var isAdmin: Bool = false

    /// Set to true briefly when a progress-restore override is applied.
    @Published var showRestoreToast = false

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/player-proxy"
    private static let dailySyncKey = "rpt_player_profile_last_sync_date"

    private init() {
        // Load cached values so they're available synchronously before network
        let cached = UserDefaults.standard.string(forKey: "rpt_player_id") ?? ""
        if cached.isEmpty {
            // Generate a stable local ID so UI never shows "Loading…"
            let suffix = String(format: "%05X", Int.random(in: 0..<1_048_576))
            let local = "ST-\(suffix)"
            UserDefaults.standard.set(local, forKey: "rpt_player_id")
            playerId = local
        } else {
            playerId = cached
        }
        systemCredits = UserDefaults.standard.integer(forKey: "rpt_system_credits")
    }

    // MARK: - Public API

    /// Fetches/creates the cloud profile on launch. Safe to call on every launch.
    func refresh() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        // If the user has previously signed in with Apple, ensure the profile is
        // linked to their current cloudkit_user_id (cheap idempotent call). This
        // also handles the cross-device case where they signed in here for the
        // first time on a new device — the proxy will return the existing profile
        // and we adopt it.
        if let cachedAppleID = UserDefaults.standard.string(forKey: "rpt_linked_apple_user_id"),
           !cachedAppleID.isEmpty {
            let displayName = KeychainHelper.load(account: "com.SpiroTechnologies.RPT.appleDisplayName")
            _ = await linkAppleID(appleUserID: cachedAppleID, displayName: displayName)
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let profile = try await fetchProfile(cloudKitUserID: cloudKitID)

            if let profile {
                applyRemoteProfile(profile)
                // Explicit admin hydration — ensure isAdmin is set even if
                // applyRemoteProfile has a subtle decode issue
                if profile.is_admin == true { isAdmin = true }
                if let override = profile.active_override {
                    applyOverride(override)
                    try? await markOverrideApplied(cloudKitUserID: cloudKitID)
                }
            } else {
                await upsertProfile()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves a backup and upserts the profile. Call after level-up, streaks, etc.
    /// Does NOT touch `onboarding_completed` — that's only set from the explicit
    /// onboarding completion path via `upsertProfile(onboardingCompleted: true)`.
    func syncProfile() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else {
            // Visibility: previously this returned silently and the UI had no
            // indication sync was blocked on CloudKit resolution. That's how
            // a user could finish onboarding but have level=1 / "Warrior"
            // persist server-side for 24 hours until the daily gate retried.
            lastError = "sync_skipped_no_cloudkit_id"
            print("[PlayerProfileService] syncProfile skipped — CloudKit user ID not yet resolved")
            return
        }
        do {
            try await saveBackup(cloudKitUserID: cloudKitID)
            await upsertProfile()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Call from streak milestones (7, 14, 30 days) and level-ups.
    func syncIfStreakMilestone(_ streak: Int) async {
        guard [7, 14, 30].contains(streak) else { return }
        await syncProfile()
    }

    /// Legacy once-per-day sync gate. Retained for backwards compat but
    /// `PlayerSyncManager.syncOnLaunchIfStale(hours: 1)` is the preferred
    /// entry point — it retries far more aggressively than this gate did.
    func syncIfNewDay() async {
        let today = Calendar.current.startOfDay(for: Date())
        let lastSync = UserDefaults.standard.object(forKey: Self.dailySyncKey) as? Date ?? .distantPast
        guard !Calendar.current.isDate(lastSync, inSameDayAs: today) else { return }
        UserDefaults.standard.set(today, forKey: Self.dailySyncKey)
        await syncProfile()
    }

    // MARK: - Gold Pieces

    /// Awards Gold Pieces to the player via the server.
    /// - Parameters:
    ///   - amount: GP amount to award (positive = credit, negative = debit).
    ///   - type: Transaction type string (e.g. "quest_reward", "level_up_bonus").
    ///   - referenceKey: Optional stable key linking the transaction to a source record.
    func addCredits(amount: Int, type: String, referenceKey: String? = nil) async {
        guard amount != 0 else { return }
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        var body: [String: Any] = [
            "action": "add_credits",
            "cloudkit_user_id": cloudKitID,
            "amount": amount,
            "transaction_type": type
        ]
        if let key = referenceKey { body["reference_key"] = key }

        do {
            let data = try await postToProxy(body: body)
            if let result = try? JSONDecoder().decode(CreditUpdatePayload.self, from: data) {
                systemCredits         = result.systemCredits
                lifetimeCreditsEarned = result.lifetimeCreditsEarned
                UserDefaults.standard.set(systemCredits, forKey: "rpt_system_credits")
            }
            ActivityLogManager.shared.log(.gp, "\(amount > 0 ? "+" : "")\(amount) GP (\(type))")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetches recent GP transaction history. Returns transactions newest-first.
    func getCreditHistory() async -> [CreditTransaction] {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return [] }

        let body: [String: Any] = [
            "action": "get_credit_history",
            "cloudkit_user_id": cloudKitID
        ]

        do {
            let data = try await postToProxy(body: body)
            // Proxy returns `{ transactions: [...] }` — the previous decode
            // tried to read the response as a bare array which silently
            // failed, so the credit history screen always appeared empty.
            struct CreditHistoryResponse: Decodable {
                let transactions: [CreditTransaction]
            }
            if let response = try? JSONDecoder().decode(CreditHistoryResponse.self, from: data) {
                return response.transactions
            }
            return []
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Sign in with Apple

    /// Links the provided Apple user ID to the current device's player profile.
    /// Handles all three response cases from the player-proxy `link_apple_id`
    /// action, including cross-device matches where another device's profile is
    /// returned and adopted locally.
    ///
    /// `authorizationCode` is the one-time SIWA code captured from the original
    /// ASAuthorizationAppleIDCredential. When present, it's stored server-side
    /// so player-proxy can later call Apple's /auth/revoke REST API on
    /// Delete Account (App Store Guideline 5.1.1(v)). Callers should pass
    /// `AppleAuthService.shared.currentAuthorizationCode` — nil on re-sign-ins
    /// where the credential came from Keychain instead of a fresh flow.
    /// Result of a SIWA link attempt. Distinguishes "fully recovered an
    /// existing player who has finished onboarding" from "linked but the
    /// remote profile is empty / unfinished" from "the call failed entirely".
    /// Onboarding navigation must use this signal — NOT the local SwiftData
    /// Profile, which always has hardcoded defaults (age=25, height=170,
    /// weight=70) the moment ensureProfileExists() runs and therefore
    /// always looks "complete" to a naive > 0 check.
    enum LinkAppleIDOutcome {
        /// Server returned a profile that has finished onboarding before
        /// (onboarding_completed == true). Caller should skip onboarding.
        case recoveredCompleted
        /// Server linked successfully but the remote profile is brand new
        /// or partially filled. Caller should run the full onboarding flow.
        case linkedNewOrIncomplete
        /// The link attempt failed (CloudKit id not resolved, network error,
        /// server rejected the request). Caller should still allow onboarding
        /// to proceed — the SIWA credential is valid in Keychain and
        /// PlayerProfileService.refresh() will retry on the next launch.
        case failed
    }

    func linkAppleID(
        appleUserID: String,
        displayName: String?,
        authorizationCode: String? = nil
    ) async -> LinkAppleIDOutcome {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            print("[PlayerProfileService] linkAppleID skipped — CloudKit user id not yet resolved")
            return .failed
        }
        guard !appleUserID.isEmpty else {
            print("[PlayerProfileService] linkAppleID skipped — empty appleUserID")
            return .failed
        }

        var body: [String: Any] = [
            "action":           "link_apple_id",
            "cloudkit_user_id": cloudKitID,
            "apple_user_id":    appleUserID
        ]
        if let displayName, !displayName.isEmpty {
            body["display_name"] = displayName
        }
        // Pipe the one-time auth code through to the server on fresh
        // sign-ins. The proxy writes it to player_profiles.apple_authorization_code
        // so delete_account → revoke_siwa can use it later.
        if let authorizationCode, !authorizationCode.isEmpty {
            body["authorization_code"] = authorizationCode
        }

        do {
            let data = try await postToProxy(body: body)
            struct LinkResponse: Decodable {
                let success: Bool?
                let linked: Bool?
                let profile: PlayerProfilePayload?
                let message: String?
                let created: Bool?
            }
            let response = try JSONDecoder().decode(LinkResponse.self, from: data)
            guard response.success == true, let payload = response.profile else {
                return .failed
            }

            // Apply the returned profile to the local SwiftData Profile so the
            // device immediately shows the cross-device data.
            applyRemoteProfile(payload)

            // Persist the apple user id locally so future launches know the
            // user is signed in even before AppleAuthService re-checks.
            UserDefaults.standard.set(appleUserID, forKey: "rpt_linked_apple_user_id")

            // The server is the only authoritative source for "has this
            // player finished onboarding before". The local Profile model has
            // CloudKit-required defaults that make every fresh row look like
            // a complete profile, so we MUST gate onboarding-skip on the
            // server flag, never on local SwiftData state.
            if payload.onboarding_completed == true {
                return .recoveredCompleted
            }
            return .linkedNewOrIncomplete
        } catch {
            print("[PlayerProfileService] linkAppleID failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Looks up a player profile by Apple ID without linking. Idempotent.
    fileprivate func lookupByAppleID(_ appleUserID: String) async -> PlayerProfilePayload? {
        guard !appleUserID.isEmpty else { return nil }
        let body: [String: Any] = [
            "action":        "lookup_by_apple_id",
            "apple_user_id": appleUserID
        ]
        do {
            let data = try await postToProxy(body: body)
            struct LookupResponse: Decodable {
                let found: Bool?
                let profile: PlayerProfilePayload?
            }
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            return response.profile
        } catch {
            print("[PlayerProfileService] lookupByAppleID failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func applyRemoteProfile(_ remote: PlayerProfilePayload) {
        // Admin status (session-only, never cached)
        let adminValue = remote.is_admin
        isAdmin = adminValue ?? false
        #if DEBUG
        print("[PlayerProfileService] applyRemoteProfile: is_admin raw=\(String(describing: adminValue)) → isAdmin=\(isAdmin)")
        #endif

        // Player ID + credits (service-level state)
        if let pid = remote.player_id, !pid.isEmpty {
            playerId = pid
            UserDefaults.standard.set(pid, forKey: "rpt_player_id")
        }

        // Ensure a local Profile exists before hydrating
        if DataManager.shared.currentProfile == nil {
            DataManager.shared.ensureProfileExists()
        }
        guard let profile = DataManager.shared.currentProfile else {
            print("[PlayerProfileService] applyRemoteProfile: failed to materialize local profile")
            return
        }

        // Identity — remote wins when non-empty and not the default "Player"
        if let name = remote.display_name, !name.isEmpty, name != "Player" {
            profile.name = name
        }
        // F6: hydrate friend_code from server. Server generates this on
        // first insert; client is read-only. The local Profile.friendCode
        // field has existed since early builds but was never populated
        // — this closes that gap so QR share + rpt://addfriend/{CODE}
        // deep links can resolve on the local device.
        if let code = remote.friend_code, !code.isEmpty {
            profile.friendCode = code
        }

        // Demographics
        if let w = remote.weight_kg, w > 0 { profile.weight = w }
        if let h = remote.height_cm, h > 0 { profile.height = h }
        if let dob = remote.date_of_birth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dob) {
                let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
                if years > 0 { profile.age = years }
            }
        }
        if let sex = remote.biological_sex, !sex.isEmpty,
           let gender = PlayerGender(rawValue: sex) {
            profile.gender = gender
        }
        if let useMetric = remote.use_metric { profile.useMetric = useMetric }
        if let act = remote.activity_level_index { profile.activityLevelIndex = act }

        // Goals + class + diet
        if let fg = remote.fitness_goal, !fg.isEmpty,
           let goal = FitnessGoal(rawValue: fg) {
            profile.fitnessGoal = goal
        }
        if let dt = remote.diet_type, !dt.isEmpty {
            profile.dietTypeRaw = dt
        }
        if let pc = remote.player_class, !pc.isEmpty {
            profile.playerClassRaw = pc
        }
        if let gym = remote.gym_environment, !gym.isEmpty,
           let env = GymEnvironment(rawValue: gym) {
            profile.gymEnvironment = env
        }
        if let plan = remote.active_anime_plan_key, !plan.isEmpty {
            profile.activePlanID = plan
        }

        // Goal survey — only restore when remote says it's completed
        if let completed = remote.goal_survey_completed, completed {
            profile.goalSurveyCompleted = true
            if let days = remote.goal_survey_days_per_week { profile.goalSurveyDaysPerWeek = days }
            if let split = remote.goal_survey_split_raw, !split.isEmpty { profile.goalSurveySplitRaw = split }
            if let mins = remote.goal_survey_session_minutes { profile.goalSurveySessionMinutes = mins }
            if let intensity = remote.goal_survey_intensity_raw, !intensity.isEmpty { profile.goalSurveyIntensityRaw = intensity }
            if let focus = remote.goal_survey_focus_areas_raw { profile.goalSurveyFocusAreasRaw = focus }
            if let cardio = remote.goal_survey_cardio_raw, !cardio.isEmpty { profile.goalSurveyCardioRaw = cardio }
        }

        // Social
        if let rivalID = remote.rival_cloudkit_user_id { profile.rivalCloudKitUserID = rivalID }
        if let rivalName = remote.rival_display_name { profile.rivalDisplayName = rivalName }
        if let gid = remote.guild_id { profile.guildID = gid }
        if let gname = remote.guild_name { profile.guildName = gname }
        if let grole = remote.guild_role { profile.guildRole = grole }

        // Progression — max wins (monotonic)
        if let level = remote.level, level > profile.level { profile.level = level }
        if let xp = remote.total_xp, xp > profile.totalXPEarned {
            profile.totalXPEarned = xp
            if xp > profile.xp { profile.xp = xp }
        }
        if let streak = remote.current_streak, streak > profile.currentStreak { profile.currentStreak = streak }
        if let best = remote.longest_streak, best > profile.bestStreak { profile.bestStreak = best }

        // Credits
        if let credits = remote.system_credits {
            self.systemCredits = max(self.systemCredits, credits)
            UserDefaults.standard.set(self.systemCredits, forKey: "rpt_system_credits")
        }
        if let lifetime = remote.lifetime_credits_earned {
            self.lifetimeCreditsEarned = max(self.lifetimeCreditsEarned, lifetime)
        }

        // Persist
        try? DataManager.shared.saveContext()
    }

    private func applyOverride(_ override: PlayerOverridePayload) {
        guard let profile = DataManager.shared.currentProfile else { return }
        if let level     = override.level        { profile.level        = level     }
        if let xp        = override.xp           { profile.xp           = xp        }
        if let streak    = override.currentStreak { profile.currentStreak = streak   }
        if let best      = override.bestStreak   { profile.bestStreak   = best      }
        if let credits   = override.systemCredits {
            systemCredits = credits
            UserDefaults.standard.set(credits, forKey: "rpt_system_credits")
        }
        showRestoreToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.showRestoreToast = false
        }
    }

    // MARK: - Network

    private func fetchProfile(cloudKitUserID: String) async throws -> PlayerProfilePayload? {
        let body: [String: Any] = [
            "action": "get_profile",
            "cloudkit_user_id": cloudKitUserID
        ]
        let data = try await postToProxy(body: body)
        if let nullCheck = try? JSONDecoder().decode(NullPayload.self, from: data), nullCheck.isNull {
            return nil
        }
        // New contract: flat top-level fields. An error response has
        // { success: false, error: "not_found" } — treat that as nil.
        struct ErrorEnvelope: Decodable { let success: Bool?; let error: String? }
        if let err = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           err.success == false {
            return nil
        }
        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("[PlayerProfileService] fetchProfile raw is_admin = \(json["is_admin"] ?? "nil")")
        }
        #endif
        return try? JSONDecoder().decode(PlayerProfilePayload.self, from: data)
    }

    /// Upserts the full local Profile to the backend using the flat
    /// top-level snake_case contract. Nil/empty fields are skipped so we don't
    /// clobber existing remote data with empty values.
    ///
    /// - Parameter onboardingCompleted: `nil` (default) means DO NOT send the
    ///   `onboarding_completed` field — the server preserves its existing
    ///   value. Only the explicit onboarding completion path should pass
    ///   `true` here. This was the F8 bug: the old code sent `= true` on
    ///   every upsert, so a daily sync during a half-finished onboarding
    ///   would flip the server flag prematurely.
    func upsertProfile(onboardingCompleted: Bool? = nil) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            lastError = "upsert_skipped_no_cloudkit_id"
            print("[PlayerProfileService] upsertProfile skipped — CloudKit user ID not yet resolved")
            return
        }
        guard let profile = DataManager.shared.currentProfile else {
            lastError = "upsert_skipped_no_local_profile"
            print("[PlayerProfileService] upsertProfile skipped — no local SwiftData profile")
            return
        }

        var body: [String: Any] = [
            "action": "upsert_profile",
            "cloudkit_user_id": cloudKitID
        ]

        // Identity
        if !profile.name.isEmpty { body["display_name"] = profile.name }
        body["level"] = profile.level
        body["total_xp"] = profile.totalXPEarned
        body["current_streak"] = profile.currentStreak
        body["longest_streak"] = profile.bestStreak

        // Character stats — the Profile stores these as Doubles (0–100 game
        // bar scale), the DB stores as integer columns. Round before sending.
        // F8 fix: these fields were missing from the body entirely until now,
        // so player_profiles had default values for all 6 stats regardless of
        // what the user actually had. Swift `health` maps to DB `vitality`.
        body["strength"]   = Int(profile.strength.rounded())
        body["endurance"]  = Int(profile.endurance.rounded())
        body["focus"]      = Int(profile.focus.rounded())
        body["discipline"] = Int(profile.discipline.rounded())
        body["vitality"]   = Int(profile.health.rounded())
        body["energy"]     = Int(profile.energy.rounded())

        // Demographics
        if profile.weight > 0 { body["weight_kg"] = profile.weight }
        if profile.height > 0 { body["height_cm"] = profile.height }
        if profile.age > 0 {
            let year = Calendar.current.component(.year, from: Date()) - profile.age
            body["date_of_birth"] = "\(year)-01-01"
        }
        body["biological_sex"] = profile.gender.rawValue
        body["use_metric"] = profile.useMetric
        body["activity_level_index"] = profile.activityLevelIndex

        // Goals + class + diet
        body["fitness_goal"] = profile.fitnessGoal.rawValue
        body["diet_type"] = profile.dietTypeRaw
        body["player_class"] = profile.playerClassRaw
        body["gym_environment"] = profile.gymEnvironment.rawValue
        if !profile.activePlanID.isEmpty { body["active_anime_plan_key"] = profile.activePlanID }

        // Goal survey
        body["goal_survey_completed"] = profile.goalSurveyCompleted
        body["goal_survey_days_per_week"] = profile.goalSurveyDaysPerWeek
        body["goal_survey_split_raw"] = profile.goalSurveySplitRaw
        body["goal_survey_session_minutes"] = profile.goalSurveySessionMinutes
        body["goal_survey_intensity_raw"] = profile.goalSurveyIntensityRaw
        body["goal_survey_focus_areas_raw"] = profile.goalSurveyFocusAreasRaw
        body["goal_survey_cardio_raw"] = profile.goalSurveyCardioRaw

        // Social
        body["rival_cloudkit_user_id"] = profile.rivalCloudKitUserID
        body["rival_display_name"] = profile.rivalDisplayName
        body["guild_id"] = profile.guildID
        body["guild_name"] = profile.guildName
        body["guild_role"] = profile.guildRole

        // F8 FIX: only set onboarding_completed when the caller explicitly
        // asks for it. The server treats missing fields as "don't change",
        // so this preserves whatever value is already in the row.
        if let onboardingCompleted {
            body["onboarding_completed"] = onboardingCompleted
        }

        // Client-written timestamp for diagnostics. Used by the launch-time
        // stale-sync gate to decide whether to force a flush.
        body["last_synced_at"] = ISO8601DateFormatter().string(from: Date())

        // Reinforce the avatar selection so upsert never nulls avatar_key
        if let avatarKey = AvatarService.shared.current?.key {
            body["avatar_key"] = avatarKey
        }

        // Sync privacy and achievement showcase
        body["is_profile_public"] = UserDefaults.standard.object(forKey: "rpt_is_profile_public") as? Bool ?? true
        let showcaseKeys = UserDefaults.standard.stringArray(forKey: "rpt_showcase_achievement_keys") ?? []
        if !showcaseKeys.isEmpty {
            body["showcase_achievement_keys"] = showcaseKeys
        }

        do {
            let data = try await postToProxy(body: body)
            // The proxy wraps the upserted row in `{ success, profile }` —
            // previously we tried to decode the entire response as a flat
            // PlayerProfilePayload, which silently failed and meant playerId
            // and systemCredits were never updated after an upsert. Decode
            // through the wrapper struct instead.
            struct UpsertResponse: Decodable {
                let success: Bool?
                let profile: PlayerProfilePayload?
            }
            if let response = try? JSONDecoder().decode(UpsertResponse.self, from: data),
               let result = response.profile {
                if let pid = result.player_id, !pid.isEmpty {
                    playerId = pid
                    UserDefaults.standard.set(pid, forKey: "rpt_player_id")
                }
                if let credits = result.system_credits {
                    systemCredits = credits
                    UserDefaults.standard.set(credits, forKey: "rpt_system_credits")
                }
            }
            // Record successful sync time for the 1-hour launch-stale gate
            UserDefaults.standard.set(Date(), forKey: "rpt_last_profile_sync_at")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[PlayerProfileService] upsertProfile failed: \(error.localizedDescription)")
        }
    }

    /// Syncs showcase achievement keys to the server immediately.
    func syncShowcaseKeys(_ keys: [String]) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }
        let body: [String: Any] = [
            "action": "upsert_profile",
            "cloudkit_user_id": cloudKitID,
            "showcase_achievement_keys": keys
        ]
        do {
            _ = try await postToProxy(body: body)
        } catch {
            print("[PlayerProfileService] syncShowcaseKeys failed: \(error.localizedDescription)")
        }
    }

    private func saveBackup(cloudKitUserID: String) async throws {
        guard let profile = DataManager.shared.currentProfile else { return }
        let body: [String: Any] = [
            "action": "save_backup",
            "cloudkit_user_id": cloudKitUserID,
            "level": profile.level,
            "total_xp": profile.totalXPEarned,
            "current_streak": profile.currentStreak,
            "longest_streak": profile.bestStreak
        ]
        _ = try await postToProxy(body: body)
    }

    private func markOverrideApplied(cloudKitUserID: String) async throws {
        let body: [String: Any] = [
            "action": "mark_override_applied",
            "cloudkit_user_id": cloudKitUserID
        ]
        _ = try await postToProxy(body: body)
    }

    private func postToProxy(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.proxyURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await PinnedURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Wire Models (private)

private struct PlayerProfilePayload: Decodable {
    // Identity
    let cloudkit_user_id: String?
    let player_id: String?
    let friend_code: String?
    let display_name: String?
    let avatar_key: String?

    // Progression
    let level: Int?
    let total_xp: Int?
    let current_streak: Int?
    let longest_streak: Int?
    let rank: String?

    // Demographics
    let weight_kg: Double?
    let height_cm: Double?
    let date_of_birth: String?
    let biological_sex: String?
    let use_metric: Bool?
    let activity_level_index: Int?

    // Goals + class + diet
    let fitness_goal: String?
    let diet_type: String?
    let player_class: String?
    let gym_environment: String?
    let active_anime_plan_key: String?

    // Goal survey
    let goal_survey_completed: Bool?
    let goal_survey_days_per_week: Int?
    let goal_survey_split_raw: String?
    let goal_survey_session_minutes: Int?
    let goal_survey_intensity_raw: String?
    let goal_survey_focus_areas_raw: [String]?
    let goal_survey_cardio_raw: String?

    // Social
    let rival_cloudkit_user_id: String?
    let rival_display_name: String?
    let guild_id: String?
    let guild_name: String?
    let guild_role: String?

    // Credits + lifetime stats
    let system_credits: Int?
    let lifetime_credits_earned: Int?
    let total_workouts_logged: Int?
    let total_quests_completed: Int?
    let total_days_active: Int?
    let onboarding_completed: Bool?
    let is_admin: Bool?

    // Admin override (optional top-level)
    var active_override: PlayerOverridePayload?
}

private struct PlayerOverridePayload: Decodable {
    let level:         Int?
    let xp:            Int?
    let currentStreak: Int?
    let bestStreak:    Int?
    let systemCredits: Int?

    enum CodingKeys: String, CodingKey {
        case level
        case xp            = "total_xp"
        case currentStreak = "current_streak"
        case bestStreak    = "longest_streak"
        case systemCredits = "system_credits"
    }
}

private struct CreditUpdatePayload: Decodable {
    let systemCredits:        Int
    let lifetimeCreditsEarned: Int

    enum CodingKeys: String, CodingKey {
        case systemCredits         = "system_credits"
        case lifetimeCreditsEarned = "lifetime_credits_earned"
    }
}

private struct NullPayload: Decodable {
    let isNull: Bool
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        isNull = container.decodeNil()
    }
}

// MARK: - Public Model: Credit Transaction

public struct CreditTransaction: Decodable, Identifiable {
    public var id: String { "\(createdAt.timeIntervalSince1970)-\(transactionType)" }

    public let amount:          Int
    public let transactionType: String
    public let referenceKey:    String?
    public let balanceAfter:    Int
    public let createdAt:       Date

    enum CodingKeys: String, CodingKey {
        case amount
        case transactionType = "transaction_type"
        case referenceKey    = "reference_key"
        case balanceAfter    = "balance_after"
        case createdAt       = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount          = try c.decode(Int.self, forKey: .amount)
        transactionType = try c.decode(String.self, forKey: .transactionType)
        referenceKey    = try c.decodeIfPresent(String.self, forKey: .referenceKey)
        balanceAfter    = try c.decode(Int.self, forKey: .balanceAfter)
        let dateStr     = try c.decode(String.self, forKey: .createdAt)
        let iso         = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = iso.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr) ?? Date()
    }
}

// MARK: - Restore Toast View

/// A toast overlay that slides in from the top when progress is restored.
/// Drop into HomeView with `.overlay(alignment: .top)`.
struct RestoreProgressToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Your progress has been restored")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
