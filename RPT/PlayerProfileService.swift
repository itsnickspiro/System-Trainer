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
        return try? JSONDecoder().decode(PlayerProfilePayload.self, from: data)
    }

    private func upsertProfile(cloudKitUserID: String) async throws {
        guard let profile = DataManager.shared.currentProfile else { return }
        let body: [String: Any] = [
            "action": "upsert_profile",
            "cloudkit_user_id": cloudKitUserID,
            "level": profile.level,
            "xp": profile.xp,
            "current_streak": profile.currentStreak,
            "best_streak": profile.bestStreak,
            "player_name": profile.name
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
            "xp": profile.xp,
            "current_streak": profile.currentStreak,
            "best_streak": profile.bestStreak
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
            return Data()
        }
        return data
    }
}

// MARK: - Wire Models (private)

private struct PlayerProfilePayload: Decodable {
    let playerId:             String
    let level:                Int
    let xp:                   Int
    let currentStreak:        Int?
    let bestStreak:           Int?
    let systemCredits:        Int?
    let lifetimeCreditsEarned: Int?
    let activeOverride:       PlayerOverridePayload?

    enum CodingKeys: String, CodingKey {
        case playerId              = "player_id"
        case level, xp
        case currentStreak         = "current_streak"
        case bestStreak            = "best_streak"
        case systemCredits         = "system_credits"
        case lifetimeCreditsEarned = "lifetime_credits_earned"
        case activeOverride        = "active_override"
    }
}

private struct PlayerOverridePayload: Decodable {
    let level:         Int?
    let xp:            Int?
    let currentStreak: Int?
    let bestStreak:    Int?
    let systemCredits: Int?

    enum CodingKeys: String, CodingKey {
        case level, xp
        case currentStreak = "current_streak"
        case bestStreak    = "best_streak"
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
