import Foundation
import Combine

// MARK: - ModerationService
//
// Handles player reporting via moderation-proxy Edge Function.
// Player-facing only — admin actions are done via Supabase Studio SQL.

@MainActor
final class ModerationService: ObservableObject {

    static let shared = ModerationService()

    @Published private(set) var isSubmitting = false
    @Published private(set) var lastError: String?

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/moderation-proxy"

    private init() {}

    // MARK: - Report Player

    func reportPlayer(
        reportedCloudKitID: String,
        reportedPlayerID: String? = nil,
        reason: ReportReason,
        description: String? = nil
    ) async -> ReportResult {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            return .error("Not signed in")
        }

        isSubmitting = true
        defer { isSubmitting = false }

        var body: [String: Any] = [
            "action": "report_player",
            "cloudkit_user_id": cloudKitID,
            "reported_cloudkit_user_id": reportedCloudKitID,
            "reason": reason.rawValue
        ]
        if let pid = reportedPlayerID { body["reported_player_id"] = pid }
        if let desc = description, !desc.isEmpty { body["description"] = String(desc.prefix(1000)) }

        do {
            let data = try await postToProxy(body: body)
            let response = try JSONDecoder().decode(ReportResponse.self, from: data)
            if response.alreadyReported == true {
                return .alreadyReported
            }
            return .success
        } catch {
            lastError = error.localizedDescription
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Get My Reports

    func fetchMyReports() async -> [MyReport] {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return [] }

        do {
            let data = try await postToProxy(body: [
                "action": "get_my_reports",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(MyReportsResponse.self, from: data)
            return response.reports ?? []
        } catch {
            lastError = error.localizedDescription
            return []
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
            if code == 429 {
                throw NSError(domain: "ModerationService", code: 429,
                              userInfo: [NSLocalizedDescriptionKey: "You've reached the report limit for today. Try again tomorrow."])
            }
            if let errResp = try? JSONDecoder().decode(ErrorBody.self, from: data),
               let msg = errResp.error {
                throw NSError(domain: "ModerationService", code: code,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Models

enum ReportReason: String, CaseIterable, Identifiable {
    case cheating
    case harassment
    case impersonation
    case inappropriateName = "inappropriate_name"
    case inappropriateAvatar = "inappropriate_avatar"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cheating: return "Cheating"
        case .harassment: return "Harassment"
        case .impersonation: return "Impersonation"
        case .inappropriateName: return "Inappropriate Name"
        case .inappropriateAvatar: return "Inappropriate Avatar"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .cheating: return "exclamationmark.shield"
        case .harassment: return "hand.raised"
        case .impersonation: return "person.2.slash"
        case .inappropriateName: return "textformat.abc.dottedunderline"
        case .inappropriateAvatar: return "photo.badge.exclamationmark"
        case .other: return "ellipsis.circle"
        }
    }
}

enum ReportResult {
    case success
    case alreadyReported
    case error(String)
}

private struct ReportResponse: Decodable {
    let success: Bool?
    let alreadyReported: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyReported = "already_reported"
    }
}

struct MyReport: Decodable, Identifiable {
    let id: String
    let reportedCloudkitUserId: String
    let reason: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportedCloudkitUserId = "reported_cloudkit_user_id"
        case reason
        case status
        case createdAt = "created_at"
    }
}

private struct MyReportsResponse: Decodable {
    let reports: [MyReport]?
}

private struct ErrorBody: Decodable {
    let error: String?
}
