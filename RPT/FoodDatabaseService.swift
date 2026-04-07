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

        let serving = servingGrams
        // USDA Branded foods report nutrients per serving, not per 100g.
        // Foundation/SR Legacy report per 100g. Convert branded to per-100g.
        let isBranded = dataType == "Branded"
        let scale = isBranded && serving > 0 ? 100.0 / serving : 1.0

        let item = FoodItem(
            name: name,
            brand: brandName ?? brandOwner,
            barcode: nil,
            caloriesPer100g: nutrientValue(.calories) * scale,
            servingSize: serving,
            carbohydrates: nutrientValue(.carbs) * scale,
            protein: nutrientValue(.protein) * scale,
            fat: nutrientValue(.fat) * scale,
            fiber: nutrientValue(.fiber) * scale,
            sugar: nutrientValue(.sugar) * scale,
            sodium: nutrientValue(.sodium) * scale,
            category: .other,
            isCustom: false
        )
        item.potassiumMg    = nutrientValue(.potassium) * scale
        item.calciumMg      = nutrientValue(.calcium) * scale
        item.ironMg         = nutrientValue(.iron) * scale
        item.vitaminCMg     = nutrientValue(.vitC) * scale
        item.vitaminDMcg    = nutrientValue(.vitD) * scale
        item.vitaminB12Mcg  = nutrientValue(.vitB12) * scale
        item.magnesiumMg    = nutrientValue(.magnesium) * scale
        item.zincMg         = nutrientValue(.zinc) * scale
        item.saturatedFatG  = nutrientValue(.saturatedFat) * scale
        item.cholesterolMg  = nutrientValue(.cholesterol) * scale
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
    // Diet tags (Phase D1)
    let containsMeat: Bool?
    let containsFish: Bool?
    let containsDairy: Bool?
    let containsEggs: Bool?
    let containsGluten: Bool?
    let containsAlcohol: Bool?
    let isHalalCertified: Bool?
    // Yuka-style ingredient grading (Phase D session 7)
    let ingredientText: String?

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
        item.containsMeat     = containsMeat ?? false
        item.containsFish     = containsFish ?? false
        item.containsDairy    = containsDairy ?? false
        item.containsEggs     = containsEggs ?? false
        item.containsGluten   = containsGluten ?? false
        item.containsAlcohol  = containsAlcohol ?? false
        item.isHalalCertified = isHalalCertified ?? false

        // Yuka-style: stash ingredient text and parse out additives/allergens
        // so the post-scan verdict and row indicators have data immediately.
        item.ingredientText = ingredientText ?? ""
        let parsed = IngredientGrader.parse(ingredientText: item.ingredientText)
        item.detectedAdditives = parsed.additives.map { $0.id }
        item.detectedAllergens = parsed.allergens

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
        case "restaurant":  return .restaurant
        case "restaurants": return .restaurant
        case "fast_food":   return .restaurant
        case "supplements": return .other
        default:            return .other
        }
    }
}

// MARK: - Community Food Submissions (foods_pending)
//
// All four community endpoints hit Supabase PostgREST directly using the
// anon key. RLS protects writes (INSERTs require a valid cloudkit_user_id)
// and the database trigger auto-promotes to the main `foods` table once
// `vote_count` reaches the threshold — iOS does nothing extra for that.

extension FoodDatabaseService {

    // Endpoints
    private static var pendingTableURL:    String { "\(Secrets.supabaseURL)/rest/v1/foods_pending" }
    private static var pendingSummaryURL:  String { "\(Secrets.supabaseURL)/rest/v1/foods_pending_summary" }
    private static var votesTableURL:      String { "\(Secrets.supabaseURL)/rest/v1/food_votes" }

    /// Strip the leading zero from a 13-digit EAN-13 to produce a 12-digit UPC-A
    /// when possible — the foods table stores UPC-A. Returns the original code
    /// for any other length so non-UPC formats still pass through.
    static func normalizeBarcode(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 13, digits.first == "0" { return String(digits.dropFirst()) }
        return digits.isEmpty ? raw : digits
    }

    // MARK: PostgREST request helper

    private func postgrestRequest(_ url: URL, method: String, body: Data? = nil, prefer: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json",                  forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabaseAnonKey,             forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        return req
    }

    // MARK: Public community API

    /// Look up a pending submission by barcode. Returns nil if there is no
    /// pending entry for that code.
    func lookupPendingFood(barcode: String) async throws -> PendingFood? {
        let normalized = Self.normalizeBarcode(barcode)
        guard let escaped = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.pendingSummaryURL)?barcode=eq.\(escaped)&status=eq.pending&select=*&limit=1")
        else { throw OFFFoodError.invalidURL }

        let req = postgrestRequest(url, method: "GET")
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let rows = try JSONDecoder().decode([PendingFood].self, from: data)
        return rows.first
    }

    /// Full-text search across pending submissions for the supplied query.
    /// Uses the `fts` tsvector column populated by the database trigger.
    func searchPendingFoods(query: String, limit: Int = 10) async throws -> [PendingFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        // PostgREST `plfts` operator → plainto_tsquery. Encode the search term.
        guard let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.pendingSummaryURL)?status=eq.pending&fts=plfts.\(q)&select=*&order=vote_count.desc&limit=\(limit)")
        else { throw OFFFoodError.invalidURL }

        let req = postgrestRequest(url, method: "GET")
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return (try? JSONDecoder().decode([PendingFood].self, from: data)) ?? []
    }

    /// Submit a new pending food. The submitter is auto-counted as the first
    /// `confirm` vote on the server side, so we don't need to insert a vote here.
    /// Requires a non-nil CloudKit user id — `submitted_by` is NOT NULL on the table.
    @discardableResult
    func submitPendingFood(_ submission: PendingFoodSubmission) async throws -> PendingFood? {
        guard !submission.submitted_by.isEmpty else { throw OFFFoodError.invalidResponse }
        guard let url = URL(string: Self.pendingTableURL) else { throw OFFFoodError.invalidURL }
        let body = try JSONEncoder().encode([submission])
        let req = postgrestRequest(url, method: "POST", body: body, prefer: "return=representation")
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let rows = (try? JSONDecoder().decode([PendingFood].self, from: data)) ?? []
        return rows.first
    }

    /// Cast (or update) the current user's vote on a pending food. The DB
    /// trigger updates `vote_count` automatically. The unique constraint on
    /// (pending_food_id, cloudkit_user_id) is handled via merge-duplicates.
    func castVote(pendingFoodID: String, voteType: PendingFoodVoteType, notes: String? = nil) async throws {
        guard let userID = Self.currentCloudKitUserID() else {
            throw OFFFoodError.invalidResponse // can't vote anonymously without a user id
        }
        guard let url = URL(string: Self.votesTableURL) else { throw OFFFoodError.invalidURL }

        let payload = PendingFoodVotePayload(
            pending_food_id: pendingFoodID,
            cloudkit_user_id: userID,
            vote_type: voteType.rawValue,
            notes: notes
        )
        let body = try JSONEncoder().encode([payload])
        let req = postgrestRequest(
            url,
            method: "POST",
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    // MARK: Identity helpers

    /// Best-effort CloudKit user id pulled from LeaderboardService. Nil only
    /// if the device has no resolved id at all (extremely rare — even no-iCloud
    /// devices get an anonymous UUID fallback).
    static func currentCloudKitUserID() -> String? {
        LeaderboardService.shared.currentUserID
    }

    static func currentDisplayName() -> String {
        DataManager.shared.currentProfile?.name ?? "Anonymous"
    }
}

// MARK: - Community Wire Models

/// Mirrors a row in the `foods_pending_summary` view. Numeric vote counters
/// come from the view's grouped joins.
struct PendingFood: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let brand: String?
    let barcode: String?
    let calories_per_100g: Double?
    let serving_size: Double?
    let carbohydrates: Double?
    let protein: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
    let category: String?
    let status: String?
    let vote_count: Int?
    let confirm_votes: Int?
    let dispute_votes: Int?
    let source_type: String?
    let submitted_by: String?
    let submitted_by_display_name: String?

    var displayConfirms: Int { confirm_votes ?? vote_count ?? 0 }
    var displayDisputes: Int { dispute_votes ?? 0 }

    /// Build a transient FoodItem (NOT inserted into SwiftData) so existing
    /// row/sheet UI can render this submission. dataSource is "community".
    func toFoodItem() -> FoodItem {
        let cat: FoodCategory = FoodCategory(rawValue: (category ?? "other").lowercased()) ?? .other
        let item = FoodItem(
            name:            name,
            brand:           brand,
            barcode:         barcode,
            caloriesPer100g: calories_per_100g ?? 0,
            servingSize:     serving_size ?? 100,
            carbohydrates:   carbohydrates ?? 0,
            protein:         protein ?? 0,
            fat:             fat ?? 0,
            fiber:           fiber ?? 0,
            sugar:           sugar ?? 0,
            sodium:          sodium ?? 0,
            category:        cat,
            isCustom:        false
        )
        item.isVerified = false
        item.dataSource = "community"
        return item
    }
}

/// Payload posted to `foods_pending` when a user submits a new product.
/// Field names use snake_case to match the table columns directly.
/// Important: the table uses `serving_size_g` and `sodium_mg`, not the
/// shorter names used elsewhere in the codebase. `submitted_by` is NOT NULL.
struct PendingFoodSubmission: Codable {
    let name: String
    let brand: String?
    let barcode: String?
    let calories_per_100g: Double
    let serving_size_g: Double
    let carbohydrates: Double
    let protein: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium_mg: Double
    let category: String
    let status: String                  // always "pending" from the client
    let source_type: String             // "barcode_scan" or "manual_entry"
    let submitted_by: String            // CloudKit user id, required by NOT NULL
    let submitted_by_display_name: String?
    let vote_count: Int                 // 1 — submitter counts as first confirm
}

enum PendingFoodVoteType: String {
    case confirm
    case dispute
}

private struct PendingFoodVotePayload: Codable {
    let pending_food_id: String
    let cloudkit_user_id: String
    let vote_type: String
    let notes: String?
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
