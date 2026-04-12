import Foundation
import Combine

// MARK: - SeasonService
//
// Manages leaderboard seasons via season-proxy Edge Function.
// Fetches the active season, season leaderboard, history, and rewards.
// Standard singleton pattern matching EventsService / StoreService.

@MainActor
final class SeasonService: ObservableObject {

    static let shared = SeasonService()

    @Published private(set) var activeSeason: Season?
    @Published private(set) var mySeasonXP: Int = 0
    @Published private(set) var myRank: Int?
    @Published private(set) var topPlayers: [SeasonLeaderboardEntry] = []
    @Published private(set) var remainingDays: Int = 0
    @Published private(set) var seasonHistory: [Season] = []
    @Published private(set) var myRewards: [SeasonReward] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    var hasUnclaimedRewards: Bool {
        myRewards.contains { $0.claimedAt == nil }
    }

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/season-proxy"

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await fetchActiveSeason()
        await fetchMyRewards()
    }

    func fetchActiveSeason() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return }

        do {
            let data = try await postToProxy(body: [
                "action": "get_active_season",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(ActiveSeasonResponse.self, from: data)
            activeSeason = response.season
            mySeasonXP = response.mySeasonXP ?? 0
            myRank = response.myRank
            topPlayers = response.top10 ?? []
            remainingDays = response.remainingDays ?? 0
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchSeasonLeaderboard(page: Int = 1) async -> [SeasonLeaderboardEntry] {
        do {
            let data = try await postToProxy(body: [
                "action": "get_season_leaderboard",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "page": page
            ])
            let response = try JSONDecoder().decode(SeasonLeaderboardResponse.self, from: data)
            return response.entries ?? []
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func fetchSeasonHistory() async {
        do {
            let data = try await postToProxy(body: [
                "action": "get_season_history"
            ])
            let response = try JSONDecoder().decode(SeasonHistoryResponse.self, from: data)
            seasonHistory = response.seasons ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchMyRewards() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }

        do {
            let data = try await postToProxy(body: [
                "action": "get_my_rewards",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(MyRewardsResponse.self, from: data)
            myRewards = response.rewards ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    func claimReward(_ rewardID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }

        do {
            let data = try await postToProxy(body: [
                "action": "claim_reward",
                "cloudkit_user_id": cloudKitID,
                "reward_id": rewardID
            ])
            let response = try JSONDecoder().decode(ClaimResponse.self, from: data)
            if response.success == true {
                await fetchMyRewards()
                await StoreService.shared.refresh(force: true)
                return true
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Network

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
            if let errResp = try? JSONDecoder().decode(ErrorBody.self, from: data),
               let msg = errResp.error {
                throw NSError(domain: "SeasonService", code: code,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

struct Season: Codable, Identifiable {
    let id: String
    let seasonNumber: Int
    let label: String
    let startsAt: String?
    let endsAt: String?
    let status: String
    let rewardGpFirst: Int?
    let rewardGpTop10: Int?
    let rewardGpTop50: Int?
    let rewardGpTop100: Int?
    let rewardAvatarKey: String?
    let rewardTitleKey: String?
    let finalizedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case label
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case rewardGpFirst = "reward_gp_first"
        case rewardGpTop10 = "reward_gp_top10"
        case rewardGpTop50 = "reward_gp_top50"
        case rewardGpTop100 = "reward_gp_top100"
        case rewardAvatarKey = "reward_avatar_key"
        case rewardTitleKey = "reward_title_key"
        case finalizedAt = "finalized_at"
    }
}

struct SeasonLeaderboardEntry: Codable, Identifiable {
    let cloudkitUserId: String?
    let playerId: String?
    let displayName: String
    let level: Int?
    let seasonXp: Int?
    let totalXp: Int?
    let avatarKey: String?
    var rank: Int?

    var id: String { cloudkitUserId ?? playerId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case cloudkitUserId = "cloudkit_user_id"
        case playerId = "player_id"
        case displayName = "display_name"
        case level
        case seasonXp = "season_xp"
        case totalXp = "total_xp"
        case avatarKey = "avatar_key"
        case rank
    }
}

struct SeasonReward: Codable, Identifiable {
    let id: String
    let seasonId: String
    let cloudkitUserId: String
    let displayName: String?
    let finalRank: Int
    let seasonXp: Int?
    let rewardGp: Int
    let rewardAvatarKey: String?
    let rewardTitleKey: String?
    let claimedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case seasonId = "season_id"
        case cloudkitUserId = "cloudkit_user_id"
        case displayName = "display_name"
        case finalRank = "final_rank"
        case seasonXp = "season_xp"
        case rewardGp = "reward_gp"
        case rewardAvatarKey = "reward_avatar_key"
        case rewardTitleKey = "reward_title_key"
        case claimedAt = "claimed_at"
    }
}

// MARK: - Response types

private struct ActiveSeasonResponse: Decodable {
    let season: Season?
    let mySeasonXP: Int?
    let myRank: Int?
    let top10: [SeasonLeaderboardEntry]?
    let remainingDays: Int?

    enum CodingKeys: String, CodingKey {
        case season
        case mySeasonXP = "my_season_xp"
        case myRank = "my_rank"
        case top10 = "top_10"
        case remainingDays = "remaining_days"
    }
}

private struct SeasonLeaderboardResponse: Decodable {
    let entries: [SeasonLeaderboardEntry]?
    let total: Int?
    let page: Int?
}

private struct SeasonHistoryResponse: Decodable {
    let seasons: [Season]?
}

private struct MyRewardsResponse: Decodable {
    let rewards: [SeasonReward]?
}

private struct ClaimResponse: Decodable {
    let success: Bool?
    let alreadyClaimed: Bool?
    let rewardGp: Int?
    let rewardTitleKey: String?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyClaimed = "already_claimed"
        case rewardGp = "reward_gp"
        case rewardTitleKey = "reward_title_key"
    }
}

private struct ErrorBody: Decodable {
    let error: String?
}
