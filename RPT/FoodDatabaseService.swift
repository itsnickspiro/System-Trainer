import Foundation
import SwiftUI
import Combine

// MARK: - Food Database Service
@MainActor
class FoodDatabaseService: ObservableObject {

    static let shared = FoodDatabaseService()

    @Published var isLoading = false
    @Published var error: Error?

    private init() {}

    func searchFoodByBarcode(_ barcode: String) async throws -> FoodItem? {
        // First try Open Food Facts API (free)
        if let food = try? await searchOpenFoodFacts(barcode: barcode) {
            return food
        }

        // Fallback to USDA database search
        return try await searchUSDAByBarcode(barcode)
    }

    private func searchOpenFoodFacts(barcode: String) async throws -> FoodItem? {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            throw FoodDatabaseError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)

        guard response.status == 1, let product = response.product else {
            throw FoodDatabaseError.productNotFound
        }

        return createFoodItem(from: product, barcode: barcode)
    }

    private func searchUSDAByBarcode(_ barcode: String) async throws -> FoodItem? {
        // USDA doesn't directly support barcode lookup, so this would require
        // a more sophisticated matching system or a paid API like Nutritionix
        throw FoodDatabaseError.productNotFound
    }

    private func createFoodItem(from product: OpenFoodFactsProduct, barcode: String) -> FoodItem {
        let name = product.product_name ?? "Unknown Product"
        let brand = product.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)

        // Extract nutrition per 100g
        // Since 'nutriments' may be nil, provide defaults
        let nutrition = product.nutriments ?? OpenFoodFactsNutrition(
            energy_kcal_100g: nil,
            carbohydrates_100g: nil,
            proteins_100g: nil,
            fat_100g: nil,
            fiber_100g: nil,
            sugars_100g: nil,
            sodium_100g: nil,
            salt_100g: nil
        )

        return FoodItem(
            name: name,
            brand: brand,
            barcode: barcode,
            caloriesPer100g: nutrition.energy_kcal_100g ?? 0,
            servingSize: 100, // Default to 100g
            carbohydrates: nutrition.carbohydrates_100g ?? 0,
            protein: nutrition.proteins_100g ?? 0,
            fat: nutrition.fat_100g ?? 0,
            fiber: nutrition.fiber_100g ?? 0,
            sugar: nutrition.sugars_100g ?? 0,
            sodium: (nutrition.sodium_100g ?? 0) * 1000, // Convert g to mg
            category: .other,
            isCustom: false
        )
    }

    func searchFoodByName(_ query: String) async throws -> [FoodItem] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)

        // Mock implementation - replace with actual API call
        return []
    }
}

// MARK: - Open Food Facts API Models

struct OpenFoodFactsResponse: Codable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

struct OpenFoodFactsProduct: Codable {
    let product_name: String?
    let brands: String?
    let nutriments: OpenFoodFactsNutrition?
    let categories: String?
    let image_url: String?
}

struct OpenFoodFactsNutrition: Codable {
    let energy_kcal_100g: Double?
    let carbohydrates_100g: Double?
    let proteins_100g: Double?
    let fat_100g: Double?
    let fiber_100g: Double?
    let sugars_100g: Double?
    let sodium_100g: Double?
    let salt_100g: Double?
}

// MARK: - Food Database Errors

enum FoodDatabaseError: LocalizedError {
    case invalidURL
    case productNotFound
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for food database."
        case .productNotFound:
            return "Product not found in database."
        case .networkError:
            return "Network error while fetching product data."
        case .decodingError:
            return "Failed to decode product data."
        }
    }
}
