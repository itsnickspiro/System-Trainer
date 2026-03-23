import Foundation
import Combine

// MARK: - Recipe API Service
// Note: Recipe model is defined in Models.swift
final class RecipeAPI: ObservableObject {
    static let shared = RecipeAPI()
    private init() {}
    
    enum APIError: Error {
        case badURL
        case requestFailed
        case decodingFailed
        case http(Int)
        case noData
        
        var localizedDescription: String {
            switch self {
            case .badURL:
                return "Invalid URL"
            case .requestFailed:
                return "Network request failed"
            case .decodingFailed:
                return "Failed to decode response"
            case .http(let code):
                return "HTTP error: \(code)"
            case .noData:
                return "No recipes found"
            }
        }
    }
    
    @MainActor
    func fetchRecipes(query: String? = nil, limit: Int = 10) async throws -> [Recipe] {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/recipe-proxy") else {
            throw APIError.badURL
        }

        var body: [String: String] = [:]
        if let query, !query.isEmpty { body["query"] = query }
        body["limit"] = String(limit)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        request.timeoutInterval = 30
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw APIError.http(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let recipes = try decoder.decode([Recipe].self, from: data)
            return recipes
        } catch is DecodingError {
            throw APIError.decodingFailed
        } catch {
            throw APIError.requestFailed
        }
    }
}

// MARK: - Recipe Extensions (Additional computed properties)
extension Recipe {
    var estimatedCookingTime: String {
        // Simple heuristic based on instruction length and complexity
        let instructionWords = instructions.components(separatedBy: .whitespacesAndNewlines).count
        let ingredientCount = ingredientsList.count
        
        let estimatedMinutes = max(15, min(120, (instructionWords / 10) + (ingredientCount * 2)))
        return "\(estimatedMinutes) mins"
    }
    
    var difficulty: String {
        let ingredientCount = ingredientsList.count
        let instructionLength = instructions.count
        
        if ingredientCount <= 5 && instructionLength < 500 {
            return "Easy"
        } else if ingredientCount <= 10 && instructionLength < 1000 {
            return "Medium"
        } else {
            return "Hard"
        }
    }
}
