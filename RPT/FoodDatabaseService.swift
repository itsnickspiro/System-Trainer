import Foundation
import SwiftData
import Combine

// MARK: - Open Food Facts Service
//
// Primary nutrition data source — completely free, no API key required.
// API docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
//
// Endpoints used:
//   Barcode: GET https://world.openfoodfacts.org/api/v2/product/{barcode}
//   Search:  GET https://search.openfoodfacts.org/search?q={query}&fields=...

@MainActor
class FoodDatabaseService: ObservableObject {

    static let shared = FoodDatabaseService()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "RPT-FitnessApp/1.0 (iOS; contact@rpt.app)"]
        return URLSession(configuration: config)
    }()

    private static let baseURL = "https://world.openfoodfacts.org/api/v2"
    private static let searchURL = "https://search.openfoodfacts.org/search"

    // Nutritional fields to request — keeps response size small
    private static let nutritionFields = [
        "code", "product_name", "brands", "categories_tags",
        "serving_size", "serving_quantity",
        "nutriments", "image_front_url"
    ].joined(separator: ",")

    private init() {}

    // MARK: - Public API

    /// Look up a product by barcode (UPC/EAN). Returns nil if not found.
    func searchFoodByBarcode(_ barcode: String) async throws -> FoodItem? {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(Self.baseURL)/product/\(barcode)?fields=\(Self.nutritionFields)"
        guard let url = URL(string: urlString) else {
            throw OFFFoodError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try decode(OFFProductResponse.self, from: data)

        // status 0 = product not found; 1 = found
        guard decoded.status == 1, let product = decoded.product else {
            return nil
        }

        return product.toFoodItem(barcode: barcode)
    }

    /// Search for foods by name. Returns up to `limit` results.
    func searchFood(query: String, limit: Int = 20) async throws -> [FoodItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        isLoading = true
        defer { isLoading = false }

        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: Self.nutritionFields),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "json", value: "true")
        ]

        guard let url = components.url else {
            throw OFFFoodError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try decode(OFFSearchResponse.self, from: data)
        return decoded.hits.compactMap { $0.toFoodItem(barcode: nil) }
    }

    // MARK: - Helpers

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OFFFoodError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OFFFoodError.httpError(statusCode: http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OFFFoodError.decodingError(error)
        }
    }
}

// MARK: - Open Food Facts Wire Models

/// Response for /api/v2/product/{barcode}
private struct OFFProductResponse: Decodable {
    let status: Int          // 1 = found, 0 = not found
    let product: OFFProduct?
}

/// Response for search.openfoodfacts.org/search
private struct OFFSearchResponse: Decodable {
    let hits: [OFFProduct]
}

/// Full product record from either endpoint.
private struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let brands: String?
    let serving_size: String?
    let serving_quantity: Double?
    let nutriments: OFFNutriments?
    let categories_tags: [String]?

    /// Map wire model → SwiftData FoodItem
    func toFoodItem(barcode: String?) -> FoodItem? {
        // Must have at least a name
        guard let rawName = product_name, !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        let n = nutriments ?? OFFNutriments()

        // Open Food Facts stores macros per 100g natively
        let cal100g = n.energy_kcal_100g
            ?? n.energyKcal100g
            ?? n.energy_100g.map { $0 / 4.184 }  // kJ → kcal fallback
            ?? 0.0

        let servingGrams: Double
        if let sq = serving_quantity, sq > 0 {
            servingGrams = sq
        } else if let ss = serving_size, let parsed = parseServingGrams(ss) {
            servingGrams = parsed
        } else {
            servingGrams = 100.0
        }

        let brand = brands?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespaces)

        let category = detectCategory(from: categories_tags)

        return FoodItem(
            name: rawName.trimmingCharacters(in: .whitespaces),
            brand: brand,
            barcode: barcode ?? code,
            caloriesPer100g: cal100g,
            servingSize: servingGrams,
            carbohydrates: n.carbohydrates_100g ?? 0,
            protein: n.proteins_100g ?? 0,
            fat: n.fat_100g ?? 0,
            fiber: n.fiber_100g ?? 0,
            sugar: n.sugars_100g ?? 0,
            sodium: (n.sodium_100g ?? 0) * 1000, // g → mg
            category: category,
            isCustom: false
        )
    }

    /// Parse a serving size string like "30g", "1 oz (28g)", "250 mL" → grams
    private func parseServingGrams(_ raw: String) -> Double? {
        // Look for a number directly followed by 'g' or 'gram'
        let lower = raw.lowercased()
        // Pattern: digits optionally with decimal, then optional space, then 'g'
        let pattern = #"(\d+(?:\.\d+)?)\s*g(?:ram)?"#
        if let range = lower.range(of: pattern, options: .regularExpression) {
            let match = String(lower[range])
            // Extract leading number
            let digits = match.prefix(while: { $0.isNumber || $0 == "." })
            return Double(digits)
        }
        // Fallback: first number in string
        let numberPattern = #"(\d+(?:\.\d+)?)"#
        if let range = lower.range(of: numberPattern, options: .regularExpression) {
            return Double(lower[range])
        }
        return nil
    }

    /// Map OFF category tags to the app's FoodCategory enum
    private func detectCategory(from tags: [String]?) -> FoodCategory {
        guard let tags else { return .other }
        for tag in tags {
            let t = tag.lowercased()
            if t.contains("protein") || t.contains("meat") || t.contains("fish") || t.contains("poultry") || t.contains("egg") { return .protein }
            if t.contains("fruit") || t.contains("vegetable") { return .vegetables }
            if t.contains("grain") || t.contains("bread") || t.contains("cereal") || t.contains("pasta") || t.contains("rice") { return .grains }
            if t.contains("dairy") || t.contains("milk") || t.contains("cheese") || t.contains("yogurt") { return .dairy }
            if t.contains("snack") || t.contains("sweet") || t.contains("chocolate") || t.contains("candy") { return .snacks }
            if t.contains("beverage") || t.contains("drink") || t.contains("juice") { return .beverages }
            if t.contains("fat") || t.contains("oil") || t.contains("butter") { return .fats }
        }
        return .other
    }
}

/// Nutritional values from Open Food Facts `nutriments` object.
/// OFF uses snake_case with `_100g` suffix for per-100g values.
private struct OFFNutriments: Decodable {
    // Calories — OFF may report as kcal or kJ; prefer kcal
    let energy_kcal_100g: Double?
    let energy_100g: Double?         // kJ when kcal key is absent

    // Macros per 100g
    let carbohydrates_100g: Double?
    let proteins_100g: Double?
    let fat_100g: Double?
    let fiber_100g: Double?
    let sugars_100g: Double?
    let sodium_100g: Double?         // stored in grams by OFF

    // Alternative key (some products use camelCase via search endpoint)
    let energyKcal100g: Double?

    init(
        energy_kcal_100g: Double? = nil,
        energy_100g: Double? = nil,
        carbohydrates_100g: Double? = nil,
        proteins_100g: Double? = nil,
        fat_100g: Double? = nil,
        fiber_100g: Double? = nil,
        sugars_100g: Double? = nil,
        sodium_100g: Double? = nil,
        energyKcal100g: Double? = nil
    ) {
        self.energy_kcal_100g = energy_kcal_100g
        self.energy_100g = energy_100g
        self.carbohydrates_100g = carbohydrates_100g
        self.proteins_100g = proteins_100g
        self.fat_100g = fat_100g
        self.fiber_100g = fiber_100g
        self.sugars_100g = sugars_100g
        self.sodium_100g = sodium_100g
        self.energyKcal100g = energyKcal100g
    }

    // Custom keys to handle OFF's snake_case field names with hyphens/underscores
    enum CodingKeys: String, CodingKey {
        case energy_kcal_100g = "energy-kcal_100g"
        case energy_100g = "energy_100g"
        case carbohydrates_100g = "carbohydrates_100g"
        case proteins_100g = "proteins_100g"
        case fat_100g = "fat_100g"
        case fiber_100g = "fiber_100g"
        case sugars_100g = "sugars_100g"
        case sodium_100g = "sodium_100g"
        case energyKcal100g = "energy_kcal_100g"
    }
}

// MARK: - Error Types

enum OFFFoodError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .invalidResponse:     return "Invalid server response"
        case .httpError(let code): return "HTTP \(code)"
        case .decodingError(let e): return "Decode failed: \(e.localizedDescription)"
        case .notFound:            return "Product not found"
        }
    }
}

// MARK: - FoodDatabaseError (kept for backwards compatibility)

enum FoodDatabaseError: LocalizedError {
    case invalidURL
    case productNotFound
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "Invalid URL for food database."
        case .productNotFound: return "Product not found in database."
        case .networkError:    return "Network error while fetching product data."
        case .decodingError:   return "Failed to decode product data."
        }
    }
}
