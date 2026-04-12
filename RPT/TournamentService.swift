import Foundation
import Combine

// MARK: - TournamentService
//
// Manages tournaments via tournament-proxy Edge Function.
// Standard singleton pattern matching EventsService / SeasonService.

@MainActor
final class TournamentService: ObservableObject {

    static let shared = TournamentService()

    @Published private(set) var activeTournaments: [Tournament] = []
    @Published private(set) var myTournaments: [TournamentParticipation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/tournament-proxy"

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTournaments() }
            group.addTask { await self.fetchMyTournaments() }
        }
    }

    func fetchTournaments() async {
        do {
            let data = try await postToProxy(body: [
                "action": "list_tournaments"
            ])
            let response = try JSONDecoder().decode(TournamentListResponse.self, from: data)
            activeTournaments = response.tournaments ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchMyTournaments() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }
        do {
            let data = try await postToProxy(body: [
                "action": "get_my_tournaments",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(MyTournamentsResponse.self, from: data)
            myTournaments = response.entries ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Tournament Detail

    func fetchTournamentDetail(_ tournamentID: String) async -> TournamentDetail? {
        do {
            let data = try await postToProxy(body: [
                "action": "get_tournament",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "tournament_id": tournamentID
            ])
            return try JSONDecoder().decode(TournamentDetail.self, from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Register

    func register(tournamentID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return false }
        do {
            let data = try await postToProxy(body: [
                "action": "register",
                "cloudkit_user_id": cloudKitID,
                "tournament_id": tournamentID
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

    // MARK: - Claim Prize

    func claimPrize(tournamentID: String) async -> Int {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return 0 }
        do {
            let data = try await postToProxy(body: [
                "action": "claim_prize",
                "cloudkit_user_id": cloudKitID,
                "tournament_id": tournamentID
            ])
            let resp = try JSONDecoder().decode(ClaimPrizeResponse.self, from: data)
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
                throw NSError(domain: "TournamentService", code: code,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

struct Tournament: Codable, Identifiable {
    let id: String
    let key: String?
    let title: String
    let description: String?
    let bracketSize: Int
    let entryGpCost: Int?
    let isFree: Bool?
    let registrationOpensAt: String?
    let registrationClosesAt: String?
    let startsAt: String?
    let endsAt: String?
    let status: String
    let prizePoolGp: Int?
    let minLevel: Int?
    let maxParticipants: Int?
    let isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, key, title, description, status
        case bracketSize = "bracket_size"
        case entryGpCost = "entry_gp_cost"
        case isFree = "is_free"
        case registrationOpensAt = "registration_opens_at"
        case registrationClosesAt = "registration_closes_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case prizePoolGp = "prize_pool_gp"
        case minLevel = "min_level"
        case maxParticipants = "max_participants"
        case isEnabled = "is_enabled"
    }

    var statusLabel: String {
        switch status {
        case "upcoming": return "Coming Soon"
        case "registering": return "Open"
        case "active": return "In Progress"
        case "completed": return "Completed"
        case "cancelled": return "Cancelled"
        default: return status.capitalized
        }
    }

    var statusColor: String {
        switch status {
        case "registering": return "green"
        case "active": return "cyan"
        case "completed": return "orange"
        default: return "gray"
        }
    }
}

struct TournamentParticipant: Codable, Identifiable {
    let cloudkitUserId: String?
    let displayName: String
    let avatarKey: String?
    let level: Int?
    let seed: Int?
    let currentXpDelta: Int?
    let eliminatedAtRound: Int?
    let finalPlacement: Int?

    var id: String { cloudkitUserId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case cloudkitUserId = "cloudkit_user_id"
        case displayName = "display_name"
        case avatarKey = "avatar_key"
        case level, seed
        case currentXpDelta = "current_xp_delta"
        case eliminatedAtRound = "eliminated_at_round"
        case finalPlacement = "final_placement"
    }
}

struct TournamentBracketMatch: Codable, Identifiable {
    let id: String
    let tournamentId: String
    let round: Int
    let matchIndex: Int
    let playerACloudkitUserId: String?
    let playerBCloudkitUserId: String?
    let playerADisplayName: String?
    let playerBDisplayName: String?
    let playerAXpDelta: Int?
    let playerBXpDelta: Int?
    let winnerCloudkitUserId: String?
    let resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentId = "tournament_id"
        case round
        case matchIndex = "match_index"
        case playerACloudkitUserId = "player_a_cloudkit_user_id"
        case playerBCloudkitUserId = "player_b_cloudkit_user_id"
        case playerADisplayName = "player_a_display_name"
        case playerBDisplayName = "player_b_display_name"
        case playerAXpDelta = "player_a_xp_delta"
        case playerBXpDelta = "player_b_xp_delta"
        case winnerCloudkitUserId = "winner_cloudkit_user_id"
        case resolvedAt = "resolved_at"
    }
}

struct TournamentDetail: Codable {
    let tournament: Tournament
    let participants: [TournamentParticipant]
    let brackets: [TournamentBracketMatch]
    let myParticipation: TournamentParticipation?

    enum CodingKeys: String, CodingKey {
        case tournament, participants, brackets
        case myParticipation = "my_participation"
    }
}

struct TournamentParticipation: Codable, Identifiable {
    let id: String?
    let tournamentId: String?
    let cloudkitUserId: String?
    let displayName: String?
    let seed: Int?
    let currentXpDelta: Int?
    let eliminatedAtRound: Int?
    let finalPlacement: Int?
    let prizeClaimedAt: String?
    let tournaments: Tournament?

    enum CodingKeys: String, CodingKey {
        case id
        case tournamentId = "tournament_id"
        case cloudkitUserId = "cloudkit_user_id"
        case displayName = "display_name"
        case seed
        case currentXpDelta = "current_xp_delta"
        case eliminatedAtRound = "eliminated_at_round"
        case finalPlacement = "final_placement"
        case prizeClaimedAt = "prize_claimed_at"
        case tournaments
    }
}

// MARK: - Response types

private struct TournamentListResponse: Decodable {
    let tournaments: [Tournament]?
}

private struct MyTournamentsResponse: Decodable {
    let entries: [TournamentParticipation]?
}

private struct GenericSuccess: Decodable {
    let success: Bool?
    let error: String?
}

private struct ClaimPrizeResponse: Decodable {
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
