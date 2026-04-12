import Foundation
import Combine

// MARK: - GuildWarService
//
// Manages guild wars via guild-war-proxy Edge Function.
// Standard singleton pattern.

@MainActor
final class GuildWarService: ObservableObject {

    static let shared = GuildWarService()

    @Published private(set) var activeWars: [GuildWar] = []
    @Published private(set) var myGuildID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/guild-war-proxy"

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await postToProxy(body: [
                "action": "get_active_wars",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(WarsResponse.self, from: data)
            activeWars = response.wars ?? []
            myGuildID = response.myGuildId
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Declare War

    func declareWar(targetGuildID: String, metricType: String = "xp_total", durationDays: Int = 3) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }
        do {
            let data = try await postToProxy(body: [
                "action": "declare_war",
                "cloudkit_user_id": cloudKitID,
                "target_guild_id": targetGuildID,
                "metric_type": metricType,
                "duration_days": durationDays
            ])
            let resp = try JSONDecoder().decode(GenericSuccess.self, from: data)
            if resp.success == true {
                await refresh()
                return true
            }
            lastError = resp.error
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Accept / Decline

    func acceptWar(_ warID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }
        do {
            _ = try await postToProxy(body: [
                "action": "accept_war",
                "cloudkit_user_id": cloudKitID,
                "war_id": warID
            ])
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func declineWar(_ warID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }
        do {
            _ = try await postToProxy(body: [
                "action": "decline_war",
                "cloudkit_user_id": cloudKitID,
                "war_id": warID
            ])
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - War Detail

    func fetchWarDetail(_ warID: String) async -> GuildWarDetail? {
        do {
            let data = try await postToProxy(body: [
                "action": "get_war_detail",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "war_id": warID
            ])
            return try JSONDecoder().decode(GuildWarDetail.self, from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Claim Reward

    func claimReward(_ warID: String) async -> Int {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return 0 }
        do {
            let data = try await postToProxy(body: [
                "action": "claim_war_reward",
                "cloudkit_user_id": cloudKitID,
                "war_id": warID
            ])
            let resp = try JSONDecoder().decode(ClaimResponse.self, from: data)
            if resp.success == true {
                await StoreService.shared.refresh(force: true)
            }
            return resp.prizeGp ?? 0
        } catch {
            lastError = error.localizedDescription
            return 0
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
                throw NSError(domain: "GuildWarService", code: code,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

struct GuildWar: Codable, Identifiable {
    let id: String
    let challengerGuildId: String
    let challengedGuildId: String
    let challengerGuildName: String?
    let challengedGuildName: String?
    let metricType: String
    let durationDays: Int
    let status: String
    let startsAt: String?
    let endsAt: String?
    let acceptedAt: String?
    let resolvedAt: String?
    let winnerGuildId: String?
    let isDraw: Bool?
    let challengerTotal: Int?
    let challengedTotal: Int?
    let prizeGpPerMember: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case challengerGuildId = "challenger_guild_id"
        case challengedGuildId = "challenged_guild_id"
        case challengerGuildName = "challenger_guild_name"
        case challengedGuildName = "challenged_guild_name"
        case metricType = "metric_type"
        case durationDays = "duration_days"
        case status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case acceptedAt = "accepted_at"
        case resolvedAt = "resolved_at"
        case winnerGuildId = "winner_guild_id"
        case isDraw = "is_draw"
        case challengerTotal = "challenger_total"
        case challengedTotal = "challenged_total"
        case prizeGpPerMember = "prize_gp_per_member"
    }

    var statusLabel: String {
        switch status {
        case "pending_acceptance": return "Pending"
        case "active": return "Active"
        case "completed": return "Completed"
        case "declined": return "Declined"
        default: return status.capitalized
        }
    }
}

struct GuildWarParticipant: Codable, Identifiable {
    let id: String
    let warId: String
    let guildId: String
    let cloudkitUserId: String
    let displayName: String?
    let startingValue: Int?
    let currentValue: Int?

    var delta: Int { max(0, (currentValue ?? 0) - (startingValue ?? 0)) }

    enum CodingKeys: String, CodingKey {
        case id
        case warId = "war_id"
        case guildId = "guild_id"
        case cloudkitUserId = "cloudkit_user_id"
        case displayName = "display_name"
        case startingValue = "starting_value"
        case currentValue = "current_value"
    }
}

struct GuildWarDetail: Codable {
    let war: GuildWar
    let challengerMembers: [GuildWarParticipant]
    let challengedMembers: [GuildWarParticipant]
    let challengerTotal: Int?
    let challengedTotal: Int?

    enum CodingKeys: String, CodingKey {
        case war
        case challengerMembers = "challenger_members"
        case challengedMembers = "challenged_members"
        case challengerTotal = "challenger_total"
        case challengedTotal = "challenged_total"
    }
}

// MARK: - Response types

private struct WarsResponse: Decodable {
    let wars: [GuildWar]?
    let myGuildId: String?

    enum CodingKeys: String, CodingKey {
        case wars
        case myGuildId = "my_guild_id"
    }
}

private struct GenericSuccess: Decodable {
    let success: Bool?
    let error: String?
}

private struct ClaimResponse: Decodable {
    let success: Bool?
    let prizeGp: Int?
    let alreadyClaimed: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case prizeGp = "prize_gp"
        case alreadyClaimed = "already_claimed"
    }
}

private struct ErrorBody: Decodable {
    let error: String?
}
