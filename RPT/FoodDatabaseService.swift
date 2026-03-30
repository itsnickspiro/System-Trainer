import Foundation
import SwiftData
import Combine

// MARK: - Food Database Service
//
// Three-tier nutrition database — all external calls go through Edge Functions:
//   1. foods-proxy  → Supabase curated foods table (searched first)
//   2. usda-proxy   → USDA FoodData Central (300k+ verified foods)
//   3. foods-proxy  → Open Food Facts via off_search / off_barcode keys
//
// No third-party API is called directly from the app.
// Source tagging: FoodItem.dataSource = "rpt" | "USDA" | "OpenFoodFacts" | "User"
// Results are deduplicated by name. Supabase results appear first.

@MainActor
class FoodDatabaseService: ObservableObject {

    static let shared = FoodDatabaseService()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "SystemTrainer/1.0 (iOS; contact@rpt.app)"]
        return URLSession(configuration: config)
    }()

    // MARK: Supabase foods-proxy
    private static let foodsProxyURL = "\(Secrets.supabaseURL)/functions/v1/foods-proxy"

    // MARK: USDA FoodData Central (via usda-proxy Edge Function)
    private static let usdaProxyURL = "\(Secrets.supabaseURL)/functions/v1/usda-proxy"

    private init() {}

    // MARK: - Public API

    /// Look up a product by barcode.
    /// Checks Supabase curated database first, then falls back to Open Food Facts.
    func searchFoodByBarcode(_ barcode: String) async throws -> FoodItem? {
        isLoading = true
        defer { isLoading = false }

        // 1. Check Supabase curated database
        if let supabaseItem = try? await fetchSupabaseFood(barcode: barcode) {
            return supabaseItem
        }

        // 2. Fall back to Open Food Facts via foods-proxy
        return try await fetchOFFBarcode(barcode)
    }

    /// Search for foods by name.
    /// Queries Supabase curated DB first, then USDA + Open Food Facts in parallel.
    /// Supabase results appear first (curated quality). Deduplicates by normalized name.
    func searchFood(query: String, limit: Int = 20) async throws -> [FoodItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        isLoading = true
        defer { isLoading = false }

        // 1. Supabase curated database (fast, no API key needed)
        let supabaseResults = (try? await fetchSupabaseFoods(query: query, limit: 10)) ?? []

        // 2. USDA + Open Food Facts in parallel for additional breadth
        async let usdaResults = fetchUSDAFoods(query: query, limit: limit / 2 + 5)
        async let offResults  = fetchOFFFoods(query: query, limit: limit / 2 + 5)

        let (usda, off) = await (
            (try? usdaResults) ?? [],
            (try? offResults)  ?? []
        )

        // Merge: Supabase first, then USDA, then OFF — deduplicating by normalized name
        var merged    = supabaseResults
        var seenNames = Set(supabaseResults.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })

        for item in usda + off {
            let key = item.name.lowercased().trimmingCharacters(in: .whitespaces)
            if !seenNames.contains(key) {
                seenNames.insert(key)
                merged.append(item)
            }
        }

        return Array(merged.prefix(limit))
    }

    // MARK: - Supabase Foods Proxy

    /// Search curated Supabase foods table by query string.
    private func fetchSupabaseFoods(query: String, limit: Int) async throws -> [FoodItem] {
        guard let url = URL(string: Self.foodsProxyURL) else { throw OFFFoodError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",          forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,           forHTTPHeaderField: "X-App-Secret")

        let body: [String: Any] = ["query": query, "limit": limit]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let rows = try JSONDecoder().decode([SupabaseFoodRow].self, from: data)
        return rows.compactMap { $0.toFoodItem() }
    }

    /// Look up a single food by barcode in the Supabase curated database.
    private func fetchSupabaseFood(barcode: String) async throws -> FoodItem? {
        guard let url = URL(string: Self.foodsProxyURL) else { throw OFFFoodError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",          forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,           forHTTPHeaderField: "X-App-Secret")

        let body: [String: Any] = ["barcode": barcode, "limit": 1]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let rows = try JSONDecoder().decode([SupabaseFoodRow].self, from: data)
        return rows.first?.toFoodItem()
    }

    // MARK: - USDA FoodData Central

    private func fetchUSDAFoods(query: String, limit: Int) async throws -> [FoodItem] {
        guard let url = URL(string: Self.usdaProxyURL) else { throw OFFFoodError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",                  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,                   forHTTPHeaderField: "X-App-Secret")
        req.timeoutInterval = 15

        let body: [String: Any] = [
            "query": query,
            "limit": limit,
            "dataType": "Foundation,SR Legacy,Branded"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let decoded = try decode(USDASearchResponse.self, from: data)
        return decoded.foods.compactMap { $0.toFoodItem() }
    }

    // MARK: - Open Food Facts (via foods-proxy Edge Function)

    private func fetchOFFFoods(query: String, limit: Int) async throws -> [FoodItem] {
        guard let url = URL(string: Self.foodsProxyURL) else { throw OFFFoodError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",                  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,                   forHTTPHeaderField: "X-App-Secret")
        req.timeoutInterval = 15

        let body: [String: Any] = ["off_search": query, "limit": limit]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let rows = try JSONDecoder().decode([SupabaseFoodRow].self, from: data)
        return rows.compactMap { $0.toFoodItem() }
    }

    private func fetchOFFBarcode(_ barcode: String) async throws -> FoodItem? {
        guard let url = URL(string: Self.foodsProxyURL) else { throw OFFFoodError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",                  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,                   forHTTPHeaderField: "X-App-Secret")
        req.timeoutInterval = 15

        let body: [String: Any] = ["off_barcode": barcode]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        // Proxy returns a single FoodItem object or null
        if let row = try? JSONDecoder().decode(SupabaseFoodRow.self, from: data) {
            return row.toFoodItem()
        }
        return nil
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

// MARK: - USDA FoodData Central Wire Models

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let brandName: String?
    let brandOwner: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [USDAFoodNutrient]
    let dataType: String?

    /// USDA nutrient numbers for the values we care about.
    private enum NID: Int {
        case calories   = 1008
        case protein    = 1003
        case fat        = 1004
        case carbs      = 1005
        case fiber      = 1079
        case sugar      = 2000
        case sodium     = 1093
        case potassium  = 1092
        case calcium    = 1087
        case iron       = 1089
        case vitC       = 1162
        case vitD       = 1110
        case vitB12     = 1178
        case magnesium  = 1090
        case zinc       = 1095
        case saturatedFat = 1258
        case cholesterol  = 1253
    }

    private func nutrientValue(_ id: NID) -> Double {
        foodNutrients.first(where: { $0.nutrientId == id.rawValue })?.value ?? 0.0
    }

    /// Serving size in grams (USDA may report in g, ml, oz…)
    private var servingGrams: Double {
        guard let size = servingSize, size > 0 else { return 100.0 }
        let unit = servingSizeUnit?.lowercased() ?? "g"
        switch unit {
        case "oz":  return size * 28.35
        case "ml":  return size             // close enough for calorie purposes
        case "lb":  return size * 453.6
        default:    return size             // assume grams
        }
    }

    func toFoodItem() -> FoodItem? {
        let name = description.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let cal100g = nutrientValue(.calories)
        let serving = servingGrams

        let item = FoodItem(
            name: name,
            brand: brandName ?? brandOwner,
            barcode: nil,
            caloriesPer100g: cal100g,
            servingSize: serving,
            carbohydrates: nutrientValue(.carbs),
            protein: nutrientValue(.protein),
            fat: nutrientValue(.fat),
            fiber: nutrientValue(.fiber),
            sugar: nutrientValue(.sugar),
            sodium: nutrientValue(.sodium),    // USDA reports in mg
            category: .other,
            isCustom: false
        )
        item.potassiumMg    = nutrientValue(.potassium)
        item.calciumMg      = nutrientValue(.calcium)
        item.ironMg         = nutrientValue(.iron)
        item.vitaminCMg     = nutrientValue(.vitC)
        item.vitaminDMcg    = nutrientValue(.vitD)
        item.vitaminB12Mcg  = nutrientValue(.vitB12)
        item.magnesiumMg    = nutrientValue(.magnesium)
        item.zincMg         = nutrientValue(.zinc)
        item.saturatedFatG  = nutrientValue(.saturatedFat)
        item.cholesterolMg  = nutrientValue(.cholesterol)
        item.dataSource     = "USDA"
        item.isVerified     = true
        return item
    }
}

private struct USDAFoodNutrient: Decodable {
    let nutrientId: Int
    let value: Double

    private enum CodingKeys: String, CodingKey {
        case nutrientId = "nutrientId"
        case value
    }
}

// MARK: - Supabase foods-proxy Wire Model

/// JSON row returned by the foods-proxy Edge Function.
/// Field names match the camelCase keys the function produces.
private struct SupabaseFoodRow: Decodable {
    let id: String?
    let name: String
    let brand: String?
    let barcode: String?
    let caloriesPer100g: Double
    let servingSize: Double
    let carbohydrates: Double
    let protein: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double       // already in mg from the Edge Function
    let potassiumMg: Double?
    let calciumMg: Double?
    let ironMg: Double?
    let vitaminCMg: Double?
    let vitaminDMcg: Double?
    let vitaminAMcg: Double?
    let saturatedFat: Double?
    let cholesterolMg: Double?
    let category: String?
    let isVerified: Bool?
    let dataSource: String?

    func toFoodItem() -> FoodItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }

        let foodCategory = mapCategory(category)
        let item = FoodItem(
            name:            trimmedName,
            brand:           brand,
            barcode:         barcode,
            caloriesPer100g: caloriesPer100g,
            servingSize:     servingSize,
            carbohydrates:   carbohydrates,
            protein:         protein,
            fat:             fat,
            fiber:           fiber,
            sugar:           sugar,
            sodium:          sodium,
            category:        foodCategory,
            isCustom:        false
        )
        item.potassiumMg   = potassiumMg   ?? 0
        item.calciumMg     = calciumMg     ?? 0
        item.ironMg        = ironMg        ?? 0
        item.vitaminCMg    = vitaminCMg    ?? 0
        item.vitaminDMcg   = vitaminDMcg   ?? 0
        item.saturatedFatG = saturatedFat  ?? 0
        item.cholesterolMg = cholesterolMg ?? 0
        item.isVerified    = isVerified ?? true
        item.dataSource    = dataSource ?? "rpt"
        return item
    }

    private func mapCategory(_ raw: String?) -> FoodCategory {
        switch raw?.lowercased() {
        case "proteins":    return .protein
        case "grains":      return .grains
        case "vegetables":  return .vegetables
        case "fruits":      return .fruits
        case "dairy":       return .dairy
        case "nuts_seeds":  return .fats
        case "oils":        return .fats
        case "fats":        return .fats
        case "condiments":  return .condiments
        case "beverages":   return .beverages
        case "snacks":      return .snacks
        case "prepared":    return .snacks
        case "supplements": return .other
        default:            return .other
        }
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
