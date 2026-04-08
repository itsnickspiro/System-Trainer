import Combine
import Foundation
import SwiftUI
import CloudKit

// MARK: - LeaderboardService
//
// Manages the Supabase-backed leaderboard via the leaderboard-proxy Edge Function.
//
// Replaces the CloudKit public-database leaderboard while keeping the CloudKit
// user ID as the stable player identifier (other services still use it).
//
// Usage:
//   await LeaderboardService.shared.refresh()         // upsert + fetch global page 1
//   LeaderboardService.shared.globalEntries           // ranked global list
//   LeaderboardService.shared.weeklyEntries           // this week's leaders
//   LeaderboardService.shared.friendEntries           // friends list
//   LeaderboardService.shared.playerGlobalRank        // current player's rank (or nil)
//   LeaderboardService.shared.currentUserID           // CloudKit user ID (for all services)

@MainActor
final class LeaderboardService: ObservableObject {

    static let shared = LeaderboardService()

    // MARK: - Published state

    @Published private(set) var isLoading        = false
    @Published private(set) var isFriendsLoading = false
    @Published private(set) var lastError: String?      = nil
    @Published private(set) var friendsError: String?   = nil

    @Published private(set) var globalEntries:  [LeaderboardEntry] = []
    @Published private(set) var weeklyEntries:  [LeaderboardEntry] = []
    @Published private(set) var friendEntries:  [LeaderboardEntry] = []

    /// The current player's position in the global leaderboard (nil if unranked).
    @Published private(set) var playerGlobalRank: Int? = nil

    // MARK: - CloudKit user ID (stable identifier, shared by all services)

    /// Returns the cached CloudKit record ID string, or nil before first resolution.
    var currentUserID: String? { _cachedCloudKitUserID }

    private var _cachedCloudKitUserID: String?

    // MARK: - Disk cache URLs

    private static let cacheDir: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }()
    private static let globalCacheURL  = cacheDir.appendingPathComponent("leaderboard_global_cache.json")
    private static let weeklyCacheURL  = cacheDir.appendingPathComponent("leaderboard_weekly_cache.json")
    private static let friendCacheURL  = cacheDir.appendingPathComponent("leaderboard_friends_cache.json")

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/leaderboard-proxy"

    // MARK: - Init

    private init() {
        // Load cached data so the leaderboard tab populates immediately on launch.
        globalEntries = (try? JSONDecoder().decode([LeaderboardEntry].self,
                                                   from: Data(contentsOf: Self.globalCacheURL))) ?? []
        weeklyEntries = (try? JSONDecoder().decode([LeaderboardEntry].self,
                                                   from: Data(contentsOf: Self.weeklyCacheURL))) ?? []
        friendEntries = (try? JSONDecoder().decode([LeaderboardEntry].self,
                                                   from: Data(contentsOf: Self.friendCacheURL))) ?? []
    }

    // MARK: - Public API

    /// Upserts the current player's stats, then fetches the first page of global + weekly entries.
    func refresh() async {
        await resolveCloudKitUserIDIfNeeded()
        await upsertEntry()
        await fetchGlobal(page: 1)
        await fetchWeekly(page: 1)
    }

    /// Pushes the current player's stats to the leaderboard.
    ///
    /// IMPORTANT: bails if the profile hasn't loaded yet. This used to send
    /// "Warrior" / level 1 / 0 XP placeholders before SwiftData populated the
    /// profile, and those placeholders would persist on the row until the user
    /// gained a level (since level-up was the only other trigger). Result:
    /// every leaderboard row looked identical and testers couldn't tell each
    /// other apart. Now we wait for real data.
    func upsertEntry() async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }
        guard let profile = DataManager.shared.currentProfile,
              !profile.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("[LeaderboardService] upsertEntry skipped — profile not yet loaded")
            return
        }

        // Total workout count lives in UserDefaults (incremented by
        // DataManager.completeQuest for workout quests). Sending it lets
        // the leaderboard-proxy compute weekly_workouts as a server-side
        // delta the same way it now computes weekly_xp.
        let totalWorkouts = UserDefaults.standard.integer(forKey: "rpt_total_workouts_logged")

        // The DB columns are `total_xp` and `current_streak`; sending `xp`
        // / `streak` alone resulted in zero values being persisted.
        // weekly_xp, weekly_workouts, and week_start_date are computed
        // server-side by leaderboard-proxy — do NOT send them from here.
        let body: [String: Any] = [
            "action":           "upsert_entry",
            "cloudkit_user_id": cloudKitID,
            "display_name":     profile.name,
            "level":            profile.level,
            "total_xp":         profile.totalXPEarned,
            "current_streak":   profile.currentStreak,
            "total_workouts":   totalWorkouts,
            "player_id":        PlayerProfileService.shared.playerId
        ]

        do {
            try await postToProxy(body: body)
        } catch {
            // Non-critical — leaderboard upsert failures don't block the player
            print("[LeaderboardService] upsertEntry failed: \(error.localizedDescription)")
        }
    }

    /// Fetches a page of global rankings (50 entries per page).
    func fetchGlobal(page: Int = 1) async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let body: [String: Any] = [
            "action":           "get_global",
            "cloudkit_user_id": cloudKitID,
            "page":             page
        ]
        do {
            let data = try await postToProxy(body: body)
            let payload = try JSONDecoder().decode(LeaderboardGlobalPayload.self, from: data)
            globalEntries = payload.entries
            playerGlobalRank = payload.playerRank
            try? JSONEncoder().encode(payload.entries).write(to: Self.globalCacheURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            print("[LeaderboardService] fetchGlobal failed (non-fatal): \(error.localizedDescription)")
            // Keep existing cached entries on failure
        }
    }

    /// Fetches a page of weekly rankings (sorted by this week's XP earned).
    func fetchWeekly(page: Int = 1) async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }

        let body: [String: Any] = [
            "action":           "get_weekly",
            "cloudkit_user_id": cloudKitID,
            "page":             page
        ]
        do {
            let data = try await postToProxy(body: body)
            let payload = try JSONDecoder().decode(LeaderboardWeeklyPayload.self, from: data)
            weeklyEntries = payload.entries
            try? JSONEncoder().encode(payload.entries).write(to: Self.weeklyCacheURL, options: .atomic)
        } catch {
            // Non-fatal — weekly board may not be populated yet
            print("[LeaderboardService] fetchWeekly failed: \(error.localizedDescription)")
        }
    }

    /// Fetches the current player's friends list from Supabase.
    func fetchFriends() async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }
        isFriendsLoading = true
        friendsError = nil
        defer { isFriendsLoading = false }

        let body: [String: Any] = [
            "action":           "get_friends",
            "cloudkit_user_id": cloudKitID
        ]
        do {
            let data = try await postToProxy(body: body)
            let payload = try JSONDecoder().decode(LeaderboardFriendsPayload.self, from: data)
            friendEntries = payload.entries
            try? JSONEncoder().encode(payload.entries).write(to: Self.friendCacheURL, options: .atomic)
        } catch {
            friendsError = error.localizedDescription
            print("[LeaderboardService] fetchFriends failed (non-fatal): \(error.localizedDescription)")
            // Keep existing cached entries on failure
        }
    }

    /// Sends a friend request using an RPT-XXXXX player ID code.
    func addFriend(playerID: String) async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }
        let normalized = playerID.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return }

        let body: [String: Any] = [
            "action":           "add_friend",
            "cloudkit_user_id": cloudKitID,
            "friend_player_id": normalized
        ]
        do {
            try await postToProxy(body: body)
            await fetchFriends()
        } catch {
            friendsError = "Could not add friend: \(error.localizedDescription)"
        }
    }

    /// Removes a friend by their RPT-XXXXX player ID.
    func removeFriend(playerID: String) async {
        guard let cloudKitID = currentUserID, !cloudKitID.isEmpty else { return }
        let body: [String: Any] = [
            "action":           "remove_friend",
            "cloudkit_user_id": cloudKitID,
            "friend_player_id": playerID
        ]
        do {
            try await postToProxy(body: body)
            friendEntries.removeAll { $0.playerId == playerID }
        } catch {
            print("[LeaderboardService] removeFriend failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Rival System
    //
    // The player picks one leaderboard friend as their rival. We store a
    // snapshot (CloudKit ID + display name) on the local Profile, and the
    // Home screen Versus banner reads the latest stats from cached
    // leaderboard entries when available.

    @MainActor
    func setRival(entry: LeaderboardEntry) {
        guard let rivalID = entry.playerId, !rivalID.isEmpty else { return }
        DataManager.shared.updateProfile { profile in
            profile.rivalCloudKitUserID = rivalID
            profile.rivalDisplayName = entry.displayName
        }
    }

    @MainActor
    func clearRival() {
        DataManager.shared.updateProfile { profile in
            profile.rivalCloudKitUserID = ""
            profile.rivalDisplayName = ""
        }
    }

    /// Returns the rival's most recent leaderboard row from the cached
    /// globalEntries / friendEntries / weeklyEntries lists if it's there.
    /// Falls back to a stub built from the snapshot fields on the local profile.
    func currentRivalEntry(for profile: Profile) -> LeaderboardEntry? {
        let id = profile.rivalCloudKitUserID
        guard !id.isEmpty else { return nil }
        if let cached = (globalEntries + friendEntries + weeklyEntries).first(where: { $0.playerId == id }) {
            return cached
        }
        return LeaderboardEntry(
            playerId: id,
            displayName: profile.rivalDisplayName,
            level: nil, totalXP: nil, weeklyXP: nil, weeklyWorkouts: nil,
            rank: nil, currentStreak: nil, avatarKey: nil, isCurrentUser: false
        )
    }

    // MARK: - CloudKit user ID resolution

    /// Resolves the CloudKit user record ID the first time it is needed.
    /// Caches the result in UserDefaults so subsequent launches don't make a network call.
    /// Uses a 10-second timeout to prevent hanging on TestFlight/poor connectivity.
    func resolveCloudKitUserIDIfNeeded() async {
        if _cachedCloudKitUserID != nil { return }
        if let persisted = UserDefaults.standard.string(forKey: "cloudKitUserRecordID"),
           !persisted.isEmpty {
            _cachedCloudKitUserID = persisted
            return
        }
        do {
            // Wrap in a timeout so a slow/unavailable iCloud account never blocks the app.
            let idString = try await withTimeout(seconds: 10) {
                let recordID = try await CKContainer.default().userRecordID()
                return recordID.recordName
            }
            _cachedCloudKitUserID = idString
            UserDefaults.standard.set(idString, forKey: "cloudKitUserRecordID")
        } catch {
            print("[LeaderboardService] CloudKit user ID resolution failed: \(error.localizedDescription)")
            // Fall back to a locally-generated anonymous UUID so all Supabase services
            // that depend on currentUserID continue to work without an iCloud account.
            let anonKey = "st_anonymous_user_id"
            let anonID: String
            if let existing = UserDefaults.standard.string(forKey: anonKey), !existing.isEmpty {
                anonID = existing
            } else {
                anonID = UUID().uuidString
                UserDefaults.standard.set(anonID, forKey: anonKey)
            }
            _cachedCloudKitUserID = anonID
            print("[LeaderboardService] Using anonymous fallback ID (no iCloud account): \(anonID)")
        }
    }

    /// Runs an async throwing closure with a wall-clock timeout.
    /// Throws `CancellationError` if the timeout expires first.
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Network

    @discardableResult
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
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return data
    }
}

// MARK: - Public Models

struct LeaderboardEntry: Codable, Identifiable {
    // id uses playerId when available; falls back to displayName+rank to avoid collisions
    var id: String { playerId ?? "\(displayName)-\(rank ?? 0)" }

    let playerId:        String?
    let displayName:     String
    let level:           Int?
    let totalXP:         Int?
    let weeklyXP:        Int?
    let weeklyWorkouts:  Int?
    let rank:            Int?
    let currentStreak:   Int?
    let avatarKey:       String?
    let isCurrentUser:   Bool?

    enum CodingKeys: String, CodingKey {
        case playerId       = "player_id"
        case displayName    = "display_name"
        case level
        case totalXP        = "total_xp"
        case weeklyXP       = "weekly_xp"
        case weeklyWorkouts = "weekly_workouts"
        case rank
        case currentStreak  = "current_streak"
        case avatarKey      = "avatar_key"
        case isCurrentUser  = "is_current_user"
    }

    // Memberwise init for constructing placeholder entries in code.
    init(playerId: String?, displayName: String, level: Int?, totalXP: Int?,
         weeklyXP: Int?, weeklyWorkouts: Int?, rank: Int?, currentStreak: Int?,
         avatarKey: String?, isCurrentUser: Bool?) {
        self.playerId       = playerId
        self.displayName    = displayName
        self.level          = level
        self.totalXP        = totalXP
        self.weeklyXP       = weeklyXP
        self.weeklyWorkouts = weeklyWorkouts
        self.rank           = rank
        self.currentStreak  = currentStreak
        self.avatarKey      = avatarKey
        self.isCurrentUser  = isCurrentUser
    }

    // Custom decoder: every field is optional so no response shape can cause a missing-key crash.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId       = try? c.decodeIfPresent(String.self, forKey: .playerId)
        displayName    = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? "Unknown"
        level          = try? c.decodeIfPresent(Int.self,    forKey: .level)
        totalXP        = try? c.decodeIfPresent(Int.self,    forKey: .totalXP)
        weeklyXP       = try? c.decodeIfPresent(Int.self,    forKey: .weeklyXP)
        weeklyWorkouts = try? c.decodeIfPresent(Int.self,    forKey: .weeklyWorkouts)
        rank           = try? c.decodeIfPresent(Int.self,    forKey: .rank)
        currentStreak  = try? c.decodeIfPresent(Int.self,    forKey: .currentStreak)
        avatarKey      = try? c.decodeIfPresent(String.self, forKey: .avatarKey)
        isCurrentUser  = try? c.decodeIfPresent(Bool.self,   forKey: .isCurrentUser)
    }
}

// MARK: - Wire Payloads (private)

private struct LeaderboardGlobalPayload: Decodable {
    let entries:    [LeaderboardEntry]
    let playerRank: Int?

    enum CodingKeys: String, CodingKey {
        case entries
        case playerRank = "player_rank"
    }
}

private struct LeaderboardWeeklyPayload: Decodable {
    let entries: [LeaderboardEntry]
}

private struct LeaderboardFriendsPayload: Decodable {
    let entries: [LeaderboardEntry]
}
