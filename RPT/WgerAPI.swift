import Foundation
import Combine

/// Wger Workout Manager API Client
/// Provides workout routines, exercises, and training plans
/// API Docs: https://wger.de/en/software/api
@MainActor
class WgerAPI: ObservableObject {
    static let shared = WgerAPI()

    private let baseURL = "https://wger.de/api/v2"
    private let apiKey: String

    @Published var isLoading = false
    @Published var error: WgerError?

    private init() {
        self.apiKey = Secrets.wgerAPIKey
    }

    // MARK: - Exercises

    /// Fetch exercises with optional filters
    func fetchExercises(
        language: String = "en",
        category: Int? = nil, // 10=Arms, 8=Legs, 9=Back, 11=Chest, 12=Shoulders, 13=Calves
        equipment: Int? = nil,
        muscles: Int? = nil,
        limit: Int = 20
    ) async throws -> [WgerExercise] {
        var components = URLComponents(string: "\(baseURL)/exercise/")!
        var queryItems = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: String(category)))
        }
        if let equipment = equipment {
            queryItems.append(URLQueryItem(name: "equipment", value: String(equipment)))
        }
        if let muscles = muscles {
            queryItems.append(URLQueryItem(name: "muscles", value: String(muscles)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw WgerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WgerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WgerError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(WgerExerciseResponse.self, from: data)
        return result.results
    }

    // MARK: - Workout Plans

    /// Fetch workout plans/routines
    func fetchWorkoutPlans(limit: Int = 20) async throws -> [WgerWorkoutPlan] {
        var components = URLComponents(string: "\(baseURL)/workout/")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw WgerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WgerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WgerError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WgerWorkoutPlanResponse.self, from: data)
        return result.results
    }

    // MARK: - Exercise Categories

    /// Get exercise categories (e.g., Arms, Legs, Back, Chest)
    func fetchExerciseCategories() async throws -> [WgerCategory] {
        guard let url = URL(string: "\(baseURL)/exercisecategory/") else {
            throw WgerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WgerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WgerError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(WgerCategoryResponse.self, from: data)
        return result.results
    }
}

// MARK: - Models

struct WgerExercise: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String
    let category: Int
    let muscles: [Int]
    let musclesSecondary: [Int]
    let equipment: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, muscles, equipment
        case musclesSecondary = "muscles_secondary"
    }
}

struct WgerExerciseResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [WgerExercise]
}

struct WgerWorkoutPlan: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String?
    let creationDate: String

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case creationDate = "creation_date"
    }
}

struct WgerWorkoutPlanResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [WgerWorkoutPlan]
}

struct WgerCategory: Identifiable, Codable {
    let id: Int
    let name: String
}

struct WgerCategoryResponse: Codable {
    let count: Int
    let results: [WgerCategory]
}

// MARK: - Error Types

enum WgerError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Exercise Category Constants

extension WgerAPI {
    enum ExerciseCategory: Int, CaseIterable {
        case abs = 10
        case arms = 8
        case back = 12
        case calves = 14
        case chest = 11
        case legs = 9
        case shoulders = 13

        var name: String {
            switch self {
            case .abs: return "Abs"
            case .arms: return "Arms"
            case .back: return "Back"
            case .calves: return "Calves"
            case .chest: return "Chest"
            case .legs: return "Legs"
            case .shoulders: return "Shoulders"
            }
        }

        var icon: String {
            switch self {
            case .abs: return "rectangle.grid.1x2.fill"
            case .arms: return "dumbbell.fill"
            case .back: return "figure.strengthtraining.functional"
            case .calves: return "figure.walk"
            case .chest: return "figure.strengthtraining.traditional"
            case .legs: return "figure.run"
            case .shoulders: return "figure.arms.open"
            }
        }
    }
}
