import Foundation

enum AIClient {
    struct ChatMessage: Codable {
        let role: String // e.g., "user", "assistant", "system"
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
    }

    struct ChatResponse: Codable {
        struct Choice: Codable {
            let message: ChatMessage
        }
        let id: String
        let choices: [Choice]
    }

    static func send(messages: [ChatMessage], model: String, endpoint: URL) async throws -> ChatResponse {
        let apiKey = Secrets.aiAPIKey
        precondition(!apiKey.isEmpty, "No API key for Debug build. Configure AIAPIKey -> $(AI_API_KEY).")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(model: model, messages: messages)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }
}
