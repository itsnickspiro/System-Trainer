import Foundation
import Combine

// MARK: - Nutrition Models
struct NutritionInfo: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Double
    let servingSizeG: Double?
    let fatTotalG: Double?
    let fatSaturatedG: Double?
    let proteinG: Double?
    let sodiumMg: Double?
    let potassiumMg: Double?
    let cholesterolMg: Double?
    let carbohydratesTotalG: Double?
    let fiberG: Double?
    let sugarG: Double?
    
    init(id: UUID = UUID(), name: String, calories: Double, servingSizeG: Double?, fatTotalG: Double?, fatSaturatedG: Double?, proteinG: Double?, sodiumMg: Double?, potassiumMg: Double?, cholesterolMg: Double?, carbohydratesTotalG: Double?, fiberG: Double?, sugarG: Double?) {
        self.id = id
        self.name = name
        self.calories = calories
        self.servingSizeG = servingSizeG
        self.fatTotalG = fatTotalG
        self.fatSaturatedG = fatSaturatedG
        self.proteinG = proteinG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.cholesterolMg = cholesterolMg
        self.carbohydratesTotalG = carbohydratesTotalG
        self.fiberG = fiberG
        self.sugarG = sugarG
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case calories
        case servingSizeG = "serving_size_g"
        case fatTotalG = "fat_total_g"
        case fatSaturatedG = "fat_saturated_g"
        case proteinG = "protein_g"
        case sodiumMg = "sodium_mg"
        case potassiumMg = "potassium_mg"
        case cholesterolMg = "cholesterol_mg"
        case carbohydratesTotalG = "carbohydrates_total_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.calories = try container.decode(Double.self, forKey: .calories)
        self.servingSizeG = try container.decodeIfPresent(Double.self, forKey: .servingSizeG)
        self.fatTotalG = try container.decodeIfPresent(Double.self, forKey: .fatTotalG)
        self.fatSaturatedG = try container.decodeIfPresent(Double.self, forKey: .fatSaturatedG)
        self.proteinG = try container.decodeIfPresent(Double.self, forKey: .proteinG)
        self.sodiumMg = try container.decodeIfPresent(Double.self, forKey: .sodiumMg)
        self.potassiumMg = try container.decodeIfPresent(Double.self, forKey: .potassiumMg)
        self.cholesterolMg = try container.decodeIfPresent(Double.self, forKey: .cholesterolMg)
        self.carbohydratesTotalG = try container.decodeIfPresent(Double.self, forKey: .carbohydratesTotalG)
        self.fiberG = try container.decodeIfPresent(Double.self, forKey: .fiberG)
        self.sugarG = try container.decodeIfPresent(Double.self, forKey: .sugarG)
    }
}

// MARK: - Nutrition API Service
final class NutritionAPI: ObservableObject {
    static let shared = NutritionAPI()
    private init() {}
    
    enum APIError: Error {
        case missingAPIKey
        case badURL
        case requestFailed
        case decodingFailed
        case http(Int)
        case noData
        
        var localizedDescription: String {
            switch self {
            case .missingAPIKey:
                return "API key is missing"
            case .badURL:
                return "Invalid URL"
            case .requestFailed:
                return "Network request failed"
            case .decodingFailed:
                return "Failed to decode response"
            case .http(let code):
                return "HTTP error: \(code)"
            case .noData:
                return "No nutrition data found"
            }
        }
    }
    
    @MainActor
    func fetchNutrition(for query: String) async throws -> [NutritionInfo] {
        let apiKey = Secrets.apiNinjasKey
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        guard !query.isEmpty else { throw APIError.noData }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.api-ninjas.com/v1/nutrition?query=\(encodedQuery)") else {
            throw APIError.badURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw APIError.http(httpResponse.statusCode)
            }
            
            // The API returns an array of nutrition objects
            let decoder = JSONDecoder()
            let nutritionItems = try decoder.decode([NutritionInfo].self, from: data)
            
            return nutritionItems
        } catch is DecodingError {
            throw APIError.decodingFailed
        } catch {
            throw APIError.requestFailed
        }
    }
}

// MARK: - Nutrition Extensions
extension NutritionInfo {
    var macroSummary: String {
        let protein = proteinG ?? 0
        let carbs = carbohydratesTotalG ?? 0
        let fat = fatTotalG ?? 0
        return "P: \(String(format: "%.1f", protein))g • C: \(String(format: "%.1f", carbs))g • F: \(String(format: "%.1f", fat))g"
    }
    
    var caloriesSummary: String {
        return "\(String(format: "%.0f", calories)) cal"
    }
}
