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
            let displayName = UserDefaults.standard.string(forKey: "rpt_apple_display_name")
            _ = await linkAppleID(appleUserID: cachedAppleID, displayName: displayName)
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let profile = try await fetchProfile(cloudKitUserID: cloudKitID)

            if let profile {
                applyRemoteProfile(profile)
                if let override = profile.activeOverride {
                    applyOverride(override)
                    try? await markOverrideApplied(cloudKitUserID: cloudKitID)
                }
            } else {
                try await upsertProfile(cloudKitUserID: cloudKitID)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves a backup and upserts the profile. Call after level-up, streaks, etc.
    func syncProfile() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }
        do {
            try await saveBackup(cloudKitUserID: cloudKitID)
            try await upsertProfile(cloudKitUserID: cloudKitID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Call from streak milestones (7, 14, 30 days) and level-ups.
    func syncIfStreakMilestone(_ streak: Int) async {
        guard [7, 14, 30].contains(streak) else { return }
        await syncProfile()
    }

    /// Once-per-day sync gate — call on app foreground.
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
            return (try? JSONDecoder().decode([CreditTransaction].self, from: data)) ?? []
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
    func linkAppleID(appleUserID: String, displayName: String?) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            print("[PlayerProfileService] linkAppleID skipped — CloudKit user id not yet resolved")
            return false
        }
        guard !appleUserID.isEmpty else {
            print("[PlayerProfileService] linkAppleID skipped — empty appleUserID")
            return false
        }

        var body: [String: Any] = [
            "action":           "link_apple_id",
            "cloudkit_user_id": cloudKitID,
            "apple_user_id":    appleUserID
        ]
        if let displayName, !displayName.isEmpty {
            body["display_name"] = displayName
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
                return false
            }

            // Apply the returned profile to the local SwiftData Profile so the
            // device immediately shows the cross-device data.
            applyRemoteProfile(payload)

            // Persist the apple user id locally so future launches know the
            // user is signed in even before AppleAuthService re-checks.
            UserDefaults.standard.set(appleUserID, forKey: "rpt_linked_apple_user_id")

            return true
        } catch {
            print("[PlayerProfileService] linkAppleID failed: \(error.localizedDescription)")
            return false
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
        if !remote.playerId.isEmpty {
            playerId = remote.playerId
            UserDefaults.standard.set(remote.playerId, forKey: "rpt_player_id")
        }

        systemCredits         = remote.systemCredits ?? systemCredits
        lifetimeCreditsEarned = remote.lifetimeCreditsEarned ?? lifetimeCreditsEarned
        UserDefaults.standard.set(systemCredits, forKey: "rpt_system_credits")

        guard let profile = DataManager.shared.currentProfile else { return }
        if remote.level > profile.level { profile.level = remote.level }
        if remote.xp > profile.xp      { profile.xp    = remote.xp    }
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
        if let envelope = try? JSONDecoder().decode(ProfileEnvelope.self, from: data) {
            if var profile = envelope.profile {
                profile.activeOverride = envelope.override
                return profile
            }
        }
        return try? JSONDecoder().decode(PlayerProfilePayload.self, from: data)
    }

    private func upsertProfile(cloudKitUserID: String) async throws {
        guard let profile = DataManager.shared.currentProfile else { return }
        let body: [String: Any] = [
            "action": "upsert_profile",
            "cloudkit_user_id": cloudKitUserID,
            "level": profile.level,
            "total_xp": profile.xp,
            "current_streak": profile.currentStreak,
            "longest_streak": profile.bestStreak,
            "display_name": profile.name
        ]
        let data = try await postToProxy(body: body)
        if let result = try? JSONDecoder().decode(PlayerProfilePayload.self, from: data) {
            if !result.playerId.isEmpty {
                playerId = result.playerId
                UserDefaults.standard.set(result.playerId, forKey: "rpt_player_id")
            }
            if let credits = result.systemCredits {
                systemCredits = credits
                UserDefaults.standard.set(credits, forKey: "rpt_system_credits")
            }
        }
    }

    private func saveBackup(cloudKitUserID: String) async throws {
        guard let profile = DataManager.shared.currentProfile else { return }
        let body: [String: Any] = [
            "action": "save_backup",
            "cloudkit_user_id": cloudKitUserID,
            "level": profile.level,
            "total_xp": profile.xp,
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

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Wire Models (private)

private struct ProfileEnvelope: Decodable {
    let profile: PlayerProfilePayload?
    let override: PlayerOverridePayload?
}

private struct PlayerProfilePayload: Decodable {
    let playerId:             String
    let level:                Int
    let xp:                   Int
    let currentStreak:        Int?
    let bestStreak:           Int?
    let systemCredits:        Int?
    let lifetimeCreditsEarned: Int?
    var activeOverride:       PlayerOverridePayload?

    enum CodingKeys: String, CodingKey {
        case playerId              = "player_id"
        case level
        case xp                    = "total_xp"
        case currentStreak         = "current_streak"
        case bestStreak            = "longest_streak"
        case systemCredits         = "system_credits"
        case lifetimeCreditsEarned = "lifetime_credits_earned"
        case activeOverride        = "active_override"
        case displayName           = "display_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId              = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        level                 = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? 1
        xp                    = (try? c.decodeIfPresent(Int.self, forKey: .xp)) ?? 0
        currentStreak         = try? c.decodeIfPresent(Int.self, forKey: .currentStreak)
        bestStreak            = try? c.decodeIfPresent(Int.self, forKey: .bestStreak)
        systemCredits         = try? c.decodeIfPresent(Int.self, forKey: .systemCredits)
        lifetimeCreditsEarned = try? c.decodeIfPresent(Int.self, forKey: .lifetimeCreditsEarned)
        activeOverride        = try? c.decodeIfPresent(PlayerOverridePayload.self, forKey: .activeOverride)
    }
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
