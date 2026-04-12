import Foundation
import Combine

// MARK: - ChallengeService
//
// Manages 1v1 challenges between players via challenge-proxy Edge Function.
// Fetches active/pending challenges, sends new challenges, responds to
// incoming ones, and auto-updates progress when the player earns XP or
// completes workouts.

@MainActor
final class ChallengeService: ObservableObject {

    static let shared = ChallengeService()

    @Published private(set) var challenges: [Challenge] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/challenge-proxy"

    private init() {}

    /// Active challenges where this user is a participant.
    var activeChallenges: [Challenge] {
        challenges.filter { $0.status == "active" }
    }

    /// Incoming pending challenges awaiting response.
    var pendingIncoming: [Challenge] {
        let myID = LeaderboardService.shared.currentUserID ?? ""
        return challenges.filter { $0.status == "pending" && $0.challengedCloudkitUserId == myID }
    }

    /// Outgoing pending challenges waiting for opponent.
    var pendingSent: [Challenge] {
        let myID = LeaderboardService.shared.currentUserID ?? ""
        return challenges.filter { $0.status == "pending" && $0.challengerCloudkitUserId == myID }
    }

    /// Completed challenges (recent).
    var completedChallenges: [Challenge] {
        challenges.filter { $0.status == "completed" }
    }

    // MARK: - Fetch

    func refresh() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await postToProxy(body: [
                "action": "get_my_challenges",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(ChallengesResponse.self, from: data)
            challenges = response.challenges ?? []
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Send Challenge

    func sendChallenge(
        targetCloudKitID: String,
        targetDisplayName: String,
        type: ChallengeType,
        targetValue: Int?,
        durationDays: Int = 7,
        wagerGP: Int = 0
    ) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return false }
        let myName = DataManager.shared.currentProfile?.name ?? "Player"

        var body: [String: Any] = [
            "action": "send_challenge",
            "cloudkit_user_id": cloudKitID,
            "target_cloudkit_user_id": targetCloudKitID,
            "challenger_display_name": myName,
            "challenged_display_name": targetDisplayName,
            "challenge_type": type.rawValue,
            "duration_days": durationDays
        ]
        if let target = targetValue { body["target_value"] = target }
        // F2 v1: optional GP wager. Server clamps to pvp_max_wager_gp and
        // debits the sender's system_credits via credit_transactions.
        if wagerGP > 0 { body["wager_gp"] = wagerGP }

        do {
            _ = try await postToProxy(body: body)
            await refresh()
            if wagerGP > 0 {
                // Pull the post-debit GP balance from the server.
                await StoreService.shared.refresh(force: true)
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Respond

    func acceptChallenge(_ challengeID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }
        do {
            _ = try await postToProxy(body: [
                "action": "respond_challenge",
                "cloudkit_user_id": cloudKitID,
                "challenge_id": challengeID,
                "response": "accept"
            ])
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func declineChallenge(_ challengeID: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID else { return false }
        do {
            _ = try await postToProxy(body: [
                "action": "respond_challenge",
                "cloudkit_user_id": cloudKitID,
                "challenge_id": challengeID,
                "response": "decline"
            ])
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Progress Update

    /// Called automatically when the player earns XP or completes a workout.
    /// Sends a progress delta to all active challenges.
    func reportProgress(xpEarned: Int = 0, workoutsCompleted: Int = 0) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty,
              !activeChallenges.isEmpty else { return }

        // Determine which delta to send based on active challenge types
        let delta = max(xpEarned, workoutsCompleted)
        guard delta > 0 else { return }

        do {
            _ = try await postToProxy(body: [
                "action": "update_progress",
                "cloudkit_user_id": cloudKitID,
                "progress_delta": delta
            ])
            await refresh()
        } catch {
            print("[ChallengeService] reportProgress failed: \(error.localizedDescription)")
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
               let msg = errResp.error { throw NSError(domain: "ChallengeService", code: code, userInfo: [NSLocalizedDescriptionKey: msg]) }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

enum ChallengeType: String, CaseIterable {
    case xpRace = "xp_race"
    case streakDuel = "streak_duel"
    case workoutCount = "workout_count"

    var displayName: String {
        switch self {
        case .xpRace: return "XP Race"
        case .streakDuel: return "Streak Duel"
        case .workoutCount: return "Workout Count"
        }
    }

    var icon: String {
        switch self {
        case .xpRace: return "bolt.fill"
        case .streakDuel: return "flame.fill"
        case .workoutCount: return "dumbbell.fill"
        }
    }

    var color: String {
        switch self {
        case .xpRace: return "cyan"
        case .streakDuel: return "orange"
        case .workoutCount: return "green"
        }
    }
}

struct Challenge: Codable, Identifiable {
    let id: String
    let challengerCloudkitUserId: String
    let challengerDisplayName: String
    let challengedCloudkitUserId: String
    let challengedDisplayName: String
    let challengeType: String
    let targetValue: Int?
    let durationDays: Int?
    let status: String
    let winnerCloudkitUserId: String?
    let challengerProgress: Int?
    let challengedProgress: Int?
    let createdAt: String?
    let acceptedAt: String?
    let expiresAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengerCloudkitUserId = "challenger_cloudkit_user_id"
        case challengerDisplayName = "challenger_display_name"
        case challengedCloudkitUserId = "challenged_cloudkit_user_id"
        case challengedDisplayName = "challenged_display_name"
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case durationDays = "duration_days"
        case status
        case winnerCloudkitUserId = "winner_cloudkit_user_id"
        case challengerProgress = "challenger_progress"
        case challengedProgress = "challenged_progress"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case expiresAt = "expires_at"
        case completedAt = "completed_at"
    }

    var type: ChallengeType? { ChallengeType(rawValue: challengeType) }

    func isChallenger(_ cloudKitID: String) -> Bool {
        challengerCloudkitUserId == cloudKitID
    }

    func myProgress(_ cloudKitID: String) -> Int {
        isChallenger(cloudKitID) ? (challengerProgress ?? 0) : (challengedProgress ?? 0)
    }

    func opponentProgress(_ cloudKitID: String) -> Int {
        isChallenger(cloudKitID) ? (challengedProgress ?? 0) : (challengerProgress ?? 0)
    }

    func opponentName(_ cloudKitID: String) -> String {
        isChallenger(cloudKitID) ? challengedDisplayName : challengerDisplayName
    }

    var isWon: Bool { status == "completed" && winnerCloudkitUserId != nil }
}

private struct ChallengesResponse: Decodable {
    let challenges: [Challenge]?
}

private struct ErrorBody: Decodable {
    let error: String?
}
