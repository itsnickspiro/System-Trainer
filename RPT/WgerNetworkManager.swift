import Foundation
import SwiftData
import Combine
import UniformTypeIdentifiers

// MARK: - Environment Configuration

/// Swap `.public` for `.selfHosted` (passing your Docker host URL) to avoid
/// wger's public rate limits during development or production self-hosting.
enum WgerEnvironment {
    case `public`
    case selfHosted(baseURL: URL)

    var baseURL: URL {
        switch self {
        case .public:
            return URL(string: "https://wger.de/api/v2")!
        case .selfHosted(let url):
            return url
        }
    }
}

// MARK: - Response Models (Codable, not @Model — decoded from wire, then mapped)

/// Top-level paginated response wrapper from wger.
private struct WgerPage<T: Decodable>: Decodable {
    let count: Int
    let results: [T]
}

/// Raw exercise info from `/api/v2/exerciseinfo/`.
/// This endpoint returns richer data than `/exercise/` in a single call.
private struct WgerExerciseInfo: Decodable {
    struct Translation: Decodable {
        let language: Int   // wger language ID; 2 = English
        let name: String
        let description: String
    }
    struct Muscle: Decodable {
        let nameEn: String
        enum CodingKeys: String, CodingKey { case nameEn = "name_en" }
    }
    struct Equipment: Decodable {
        let nameEn: String
        enum CodingKeys: String, CodingKey { case nameEn = "name_en" }
    }
    struct Category: Decodable {
        let name: String
    }

    let id: Int
    let category: Category
    let muscles: [Muscle]
    let musclesSecondary: [Muscle]
    let equipment: [Equipment]
    let translations: [Translation]

    enum CodingKeys: String, CodingKey {
        case id, category, muscles, equipment, translations
        case musclesSecondary = "muscles_secondary"
    }

    /// English name, falling back to first available.
    var englishName: String {
        translations.first(where: { $0.language == 2 })?.name
            ?? translations.first?.name
            ?? "Unknown Exercise"
    }

    var englishDescription: String {
        translations.first(where: { $0.language == 2 })?.description
            ?? translations.first?.description
            ?? ""
    }
}

// MARK: - Network Manager

/// Fetches exercise data from the wger REST API and caches it in SwiftData.
/// No API key required — the public `/exerciseinfo/` endpoint is open.
///
/// Usage:
/// ```swift
/// let manager = WgerNetworkManager()          // public wger
/// let manager = WgerNetworkManager(environment: .selfHosted(baseURL: dockerURL))
/// let exercises = try await manager.fetchExercises(category: .legs, limit: 20)
/// ```
@MainActor
final class WgerNetworkManager: ObservableObject {
    static let shared = WgerNetworkManager()

    @Published var isLoading = false
    @Published var error: WgerNetworkError?

    private let environment: WgerEnvironment
    private let session: URLSession

    init(environment: WgerEnvironment = .public) {
        self.environment = environment
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            // wger public API prefers a User-Agent for rate-limit fairness
            "User-Agent": "RPT-FitnessApp/1.0 (iOS)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetches exercises for a given muscle-group category, maps them to `ExerciseItem`,
    /// and upserts them into the local SwiftData context.
    ///
    /// - Parameters:
    ///   - category: Filter by muscle group (optional — nil fetches all)
    ///   - limit: Max results per page (wger default 20, max 100)
    ///   - context: The SwiftData context for local caching
    /// - Returns: Array of `ExerciseItem` values (also persisted locally)
    @discardableResult
    func fetchExercises(
        category: ExerciseMuscleGroup? = nil,
        limit: Int = 20,
        context: ModelContext
    ) async throws -> [ExerciseItem] {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let url = try buildURL(path: "/exerciseinfo/", queryItems: [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: "2"), // English
            URLQueryItem(name: "limit", value: String(min(limit, 100))),
            category.map { URLQueryItem(name: "category", value: String($0.wgerID)) }
        ].compactMap { $0 })

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try JSONDecoder().decode(WgerPage<WgerExerciseInfo>.self, from: data)
        let items = decoded.results.map { info in
            ExerciseItem(
                wgerID: info.id,
                name: info.englishName,
                exerciseDescription: info.englishDescription,
                category: info.category.name,
                equipment: info.equipment.map(\.nameEn),
                primaryMuscles: info.muscles.map(\.nameEn),
                secondaryMuscles: info.musclesSecondary.map(\.nameEn),
                workoutType: WorkoutType(wgerCategory: info.category.name)
            )
        }

        upsert(items, into: context)
        return items
    }

    /// Fetches a single exercise by its wger ID.
    func fetchExercise(id: Int) async throws -> ExerciseItem {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let url = try buildURL(path: "/exerciseinfo/\(id)/", queryItems: [
            URLQueryItem(name: "format", value: "json")
        ])

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let info = try JSONDecoder().decode(WgerExerciseInfo.self, from: data)
        return ExerciseItem(
            wgerID: info.id,
            name: info.englishName,
            exerciseDescription: info.englishDescription,
            category: info.category.name,
            equipment: info.equipment.map(\.nameEn),
            primaryMuscles: info.muscles.map(\.nameEn),
            secondaryMuscles: info.musclesSecondary.map(\.nameEn),
            workoutType: WorkoutType(wgerCategory: info.category.name)
        )
    }

    // MARK: - Private Helpers

    private func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: environment.baseURL.appendingPathComponent(path, conformingTo: .url), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw WgerNetworkError.invalidURL }
        return url
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WgerNetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WgerNetworkError.httpError(statusCode: http.statusCode)
        }
    }

    /// Insert new exercises; update name/description/cachedAt for existing ones.
    private func upsert(_ items: [ExerciseItem], into context: ModelContext) {
        for item in items {
            let id = item.wgerID
            let descriptor = FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.wgerID == id }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.name = item.name
                existing.exerciseDescription = item.exerciseDescription
                existing.category = item.category
                existing.equipment = item.equipment
                existing.primaryMuscles = item.primaryMuscles
                existing.secondaryMuscles = item.secondaryMuscles
                existing.workoutType = item.workoutType
                existing.cachedAt = Date()
            } else {
                context.insert(item)
            }
        }
        try? context.save()
    }
}

// MARK: - Muscle Group Enum

/// wger exercise category IDs.
/// To add more, inspect `/api/v2/exercisecategory/` on the target server.
enum ExerciseMuscleGroup: Int, CaseIterable, Identifiable {
    case abs      = 10
    case arms     = 8
    case back     = 12
    case calves   = 14
    case chest    = 11
    case legs     = 9
    case shoulders = 13

    var id: Int { rawValue }
    /// wger category ID sent as a query param
    var wgerID: Int { rawValue }

    var displayName: String {
        switch self {
        case .abs:       return "Abs"
        case .arms:      return "Arms"
        case .back:      return "Back"
        case .calves:    return "Calves"
        case .chest:     return "Chest"
        case .legs:      return "Legs"
        case .shoulders: return "Shoulders"
        }
    }

    var icon: String {
        switch self {
        case .abs:       return "rectangle.grid.1x2.fill"
        case .arms:      return "dumbbell.fill"
        case .back:      return "figure.strengthtraining.functional"
        case .calves:    return "figure.walk"
        case .chest:     return "figure.strengthtraining.traditional"
        case .legs:      return "figure.run"
        case .shoulders: return "figure.arms.open"
        }
    }
}

// MARK: - WorkoutType extension

extension WorkoutType {
    /// Maps a wger category name to the app's WorkoutType for stat integration.
    init(wgerCategory: String) {
        switch wgerCategory.lowercased() {
        case "abs", "back", "chest", "arms", "shoulders":
            self = .strength
        case "legs", "calves":
            self = .strength  // leg day is strength training
        default:
            self = .mixed
        }
    }
}

// MARK: - Errors

enum WgerNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid wger API URL"
        case .invalidResponse:         return "Invalid response from wger"
        case .httpError(let code):     return "wger returned HTTP \(code)"
        case .decodingError(let err):  return "Decode error: \(err.localizedDescription)"
        }
    }
}
