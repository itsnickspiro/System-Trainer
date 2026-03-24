import Foundation
import SwiftData
import Combine

// MARK: - Food Database Service
//
// Three-tier nutrition database:
//   1. Supabase foods table (curated ~200 baseline foods, searched first via foods-proxy)
//   2. USDA FoodData Central (300k+ verified foods, primary fallback)
//   3. Open Food Facts (3M+ products, secondary fallback / barcode lookup)
//
// USDA FoodData Central
//   API docs: https://fdc.nal.usda.gov/api-guide.html
//   Key stored in Info.plist as USDAFoodApiKey. Falls back to DEMO_KEY (30 req/hr).
//
// Open Food Facts — completely free, no key required
//   API docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
//
// Supabase foods-proxy Edge Function
//   POST /functions/v1/foods-proxy  { query, barcode, category, limit, offset }
//   Returns array of FoodItem-shaped JSON.
//
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
        config.httpAdditionalHeaders = ["User-Agent": "RPT-FitnessApp/1.0 (iOS; contact@rpt.app)"]
        return URLSession(configuration: config)
    }()

    // MARK: Supabase foods-proxy
    private static let foodsProxyURL = "\(Secrets.supabaseURL)/functions/v1/foods-proxy"

    // MARK: USDA FoodData Central
    private static let usdaBaseURL = "https://api.nal.usda.gov/fdc/v1"
    private var usdaApiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "USDAFoodApiKey") as? String ?? "DEMO_KEY"
    }

    // MARK: Open Food Facts
    private static let offBaseURL = "https://world.openfoodfacts.org/api/v2"
    private static let offSearchURL = "https://search.openfoodfacts.org/search"
    private static let offFields = [
        "code", "product_name", "brands", "categories_tags",
        "serving_size", "serving_quantity", "nutriments",
        "nova_group", "additives_tags"
    ].joined(separator: ",")

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

        // 2. Fall back to Open Food Facts for barcode lookup
        let urlString = "\(Self.offBaseURL)/product/\(barcode)?fields=\(Self.offFields)"
        guard let url = URL(string: urlString) else { throw OFFFoodError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try decode(OFFProductResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else { return nil }

        let item = product.toFoodItem(barcode: barcode)
        item?.dataSource = "OpenFoodFacts"
        return item
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
        var components = URLComponents(string: "\(Self.usdaBaseURL)/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(limit)),
            // Prefer Foundation and SR Legacy data types — most complete nutrients
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
            URLQueryItem(name: "api_key", value: usdaApiKey)
        ]
        guard let url = components.url else { throw OFFFoodError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try decode(USDASearchResponse.self, from: data)
        return decoded.foods.compactMap { $0.toFoodItem() }
    }

    // MARK: - Open Food Facts

    private func fetchOFFFoods(query: String, limit: Int) async throws -> [FoodItem] {
        var components = URLComponents(string: Self.offSearchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: Self.offFields),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "json", value: "true")
        ]
        guard let url = components.url else { throw OFFFoodError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validate(response)

        let decoded = try decode(OFFSearchResponse.self, from: data)
        return decoded.hits.compactMap {
            let item = $0.toFoodItem(barcode: nil)
            item?.dataSource = "OpenFoodFacts"
            return item
        }
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
    let nova_group: Int?
    let additives_tags: [String]?

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

        let item = FoodItem(
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
        item.dataSource = "OpenFoodFacts"
        item.novaGroup = nova_group ?? 0
        item.additiveRiskLevel = computeAdditiveRisk(from: additives_tags)
        return item
    }

    /// Compute additive risk level (0–3) from OFF additives_tags array.
    /// 0 = none, 1 = low (1–2 additives), 2 = moderate (3–5), 3 = high (6+)
    private func computeAdditiveRisk(from tags: [String]?) -> Int {
        guard let tags, !tags.isEmpty else { return 0 }
        let count = tags.count
        switch count {
        case 0: return 0
        case 1...2: return 1
        case 3...5: return 2
        default: return 3
        }
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
