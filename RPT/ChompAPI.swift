import Foundation
import Combine

/// Chomp Food & Grocery Database API Client
/// Provides comprehensive food data including branded products and nutrition
/// API Docs: https://chompthis.com/api/
@MainActor
class ChompAPI: ObservableObject {
    static let shared = ChompAPI()

    private let baseURL = "https://chompthis.com/api/v2"
    private let apiKey: String

    @Published var isLoading = false
    @Published var error: ChompError?

    private init() {
        self.apiKey = Secrets.chompAPIKey
    }

    // MARK: - Food Search

    /// Search for food by query string
    func searchFood(
        query: String,
        branded: Bool = true,
        limit: Int = 20
    ) async throws -> [ChompFood] {
        var components = URLComponents(string: "\(baseURL)/food/branded/search.php")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw ChompError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChompError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ChompError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(ChompSearchResponse.self, from: data)
        return result.items
    }

    // MARK: - Barcode Lookup

    /// Lookup food by UPC/EAN barcode
    func lookupByBarcode(_ barcode: String) async throws -> ChompFood {
        var components = URLComponents(string: "\(baseURL)/food/branded/barcode.php")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "code", value: barcode)
        ]

        guard let url = components.url else {
            throw ChompError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChompError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ChompError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(ChompBarcodeResponse.self, from: data)

        guard let items = result.items, !items.isEmpty else {
            throw ChompError.notFound
        }

        return items[0]
    }

    // MARK: - Food Details

    /// Get detailed information about a specific food item
    func getFoodDetails(id: String) async throws -> ChompFood {
        var components = URLComponents(string: "\(baseURL)/food/branded/name.php")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "code", value: id)
        ]

        guard let url = components.url else {
            throw ChompError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChompError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ChompError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(ChompBarcodeResponse.self, from: data)

        guard let items = result.items, !items.isEmpty else {
            throw ChompError.notFound
        }

        return items[0]
    }
}

// MARK: - Models

struct ChompFood: Identifiable, Codable {
    let id: String
    let name: String
    let brandName: String?
    let servingSize: String?
    let servingUnit: String?
    let calories: Double?
    let caloriesFromFat: Double?
    let totalFat: Double?
    let saturatedFat: Double?
    let transFat: Double?
    let cholesterol: Double?
    let sodium: Double?
    let totalCarbohydrate: Double?
    let dietaryFiber: Double?
    let sugars: Double?
    let protein: Double?
    let vitaminA: Double?
    let vitaminC: Double?
    let calcium: Double?
    let iron: Double?
    let ingredients: String?
    let allergenInfo: String?

    enum CodingKeys: String, CodingKey {
        case id = "ean"
        case name
        case brandName = "brand"
        case servingSize = "serving_size"
        case servingUnit = "serving_size_unit"
        case calories
        case caloriesFromFat = "calories_from_fat"
        case totalFat = "fat"
        case saturatedFat = "saturated_fat"
        case transFat = "trans_fat"
        case cholesterol
        case sodium
        case totalCarbohydrate = "carbohydrates"
        case dietaryFiber = "fiber"
        case sugars
        case protein
        case vitaminA = "vitamin_a"
        case vitaminC = "vitamin_c"
        case calcium
        case iron
        case ingredients
        case allergenInfo = "allergen_warning"
    }

    // Convert to FoodItem model
    func toFoodItem() -> FoodItem {
        let servingSizeValue = Double(servingSize ?? "100") ?? 100.0
        let caloriesPer100g = if let cal = calories {
            (cal / servingSizeValue) * 100
        } else {
            0.0
        }

        return FoodItem(
            name: name,
            brand: brandName,
            caloriesPer100g: caloriesPer100g,
            servingSize: servingSizeValue,
            carbohydrates: totalCarbohydrate ?? 0,
            protein: protein ?? 0,
            fat: totalFat ?? 0,
            fiber: dietaryFiber ?? 0,
            sugar: sugars ?? 0,
            sodium: sodium ?? 0,
            isCustom: false
        )
    }
}

struct ChompSearchResponse: Codable {
    let items: [ChompFood]
}

struct ChompBarcodeResponse: Codable {
    let items: [ChompFood]?
}

// MARK: - Error Types

enum ChompError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    case notFound

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
        case .notFound:
            return "Food item not found"
        }
    }
}
