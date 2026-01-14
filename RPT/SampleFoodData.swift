import Foundation
import SwiftData

// MARK: - Sample Food Data

class SampleFoodData {
    static func createSampleFoods(context: ModelContext) {
        // Check if we already have foods
        let descriptor = FetchDescriptor<FoodItem>()
        let existingFoods = (try? context.fetch(descriptor)) ?? []
        
        if !existingFoods.isEmpty {
            return // Already have sample data
        }
        
        // Common breakfast foods
        let oatmeal = FoodItem(
            name: "Steel Cut Oats",
            brand: "Quaker",
            caloriesPer100g: 379,
            servingSize: 40,
            carbohydrates: 67.7,
            protein: 13.2,
            fat: 6.5,
            fiber: 10.1,
            sugar: 1.1,
            sodium: 2,
            category: .grains
        )
        
        let greekYogurt = FoodItem(
            name: "Greek Yogurt, Plain",
            brand: "Fage",
            caloriesPer100g: 97,
            servingSize: 170,
            carbohydrates: 4.0,
            protein: 18.0,
            fat: 0.4,
            fiber: 0,
            sugar: 4.0,
            sodium: 36,
            category: .dairy
        )
        
        let banana = FoodItem(
            name: "Banana",
            brand: nil,
            caloriesPer100g: 89,
            servingSize: 118,
            carbohydrates: 22.8,
            protein: 1.1,
            fat: 0.3,
            fiber: 2.6,
            sugar: 12.2,
            sodium: 1,
            category: .fruits
        )
        
        let almonds = FoodItem(
            name: "Almonds, Raw",
            brand: "Blue Diamond",
            caloriesPer100g: 579,
            servingSize: 28,
            carbohydrates: 21.6,
            protein: 21.2,
            fat: 49.9,
            fiber: 12.5,
            sugar: 4.4,
            sodium: 1,
            category: .protein
        )
        
        // Lunch foods
        let chickenBreast = FoodItem(
            name: "Chicken Breast, Grilled",
            brand: nil,
            caloriesPer100g: 165,
            servingSize: 85,
            carbohydrates: 0,
            protein: 31.0,
            fat: 3.6,
            fiber: 0,
            sugar: 0,
            sodium: 74,
            category: .protein
        )
        
        let brownRice = FoodItem(
            name: "Brown Rice, Cooked",
            brand: "Uncle Ben's",
            caloriesPer100g: 111,
            servingSize: 125,
            carbohydrates: 23.0,
            protein: 2.6,
            fat: 0.9,
            fiber: 1.8,
            sugar: 0.4,
            sodium: 5,
            category: .grains
        )
        
        let broccoli = FoodItem(
            name: "Broccoli, Steamed",
            brand: nil,
            caloriesPer100g: 35,
            servingSize: 85,
            carbohydrates: 7.0,
            protein: 2.8,
            fat: 0.4,
            fiber: 2.6,
            sugar: 1.5,
            sodium: 33,
            category: .vegetables
        )
        
        // Dinner foods
        let salmon = FoodItem(
            name: "Atlantic Salmon, Baked",
            brand: nil,
            caloriesPer100g: 206,
            servingSize: 100,
            carbohydrates: 0,
            protein: 22.1,
            fat: 12.4,
            fiber: 0,
            sugar: 0,
            sodium: 59,
            category: .protein
        )
        
        let sweetPotato = FoodItem(
            name: "Sweet Potato, Baked",
            brand: nil,
            caloriesPer100g: 86,
            servingSize: 128,
            carbohydrates: 20.1,
            protein: 1.6,
            fat: 0.1,
            fiber: 3.0,
            sugar: 4.2,
            sodium: 4,
            category: .vegetables
        )
        
        let spinach = FoodItem(
            name: "Spinach, Fresh",
            brand: nil,
            caloriesPer100g: 23,
            servingSize: 30,
            carbohydrates: 3.6,
            protein: 2.9,
            fat: 0.4,
            fiber: 2.2,
            sugar: 0.4,
            sodium: 79,
            category: .vegetables
        )
        
        // Snacks
        let apple = FoodItem(
            name: "Apple, Medium",
            brand: nil,
            caloriesPer100g: 52,
            servingSize: 182,
            carbohydrates: 13.8,
            protein: 0.3,
            fat: 0.2,
            fiber: 2.4,
            sugar: 10.4,
            sodium: 1,
            category: .fruits
        )
        
        let peanutButter = FoodItem(
            name: "Peanut Butter, Natural",
            brand: "Skippy",
            caloriesPer100g: 588,
            servingSize: 32,
            carbohydrates: 20.0,
            protein: 25.8,
            fat: 50.0,
            fiber: 6.0,
            sugar: 9.2,
            sodium: 17,
            category: .fats
        )
        
        let wholeWheatBread = FoodItem(
            name: "Whole Wheat Bread",
            brand: "Dave's Killer Bread",
            caloriesPer100g: 247,
            servingSize: 28,
            carbohydrates: 43.3,
            protein: 13.4,
            fat: 4.2,
            fiber: 7.0,
            sugar: 5.6,
            sodium: 491,
            category: .grains
        )
        
        // Beverages
        let coffee = FoodItem(
            name: "Coffee, Black",
            brand: "Starbucks",
            caloriesPer100g: 1,
            servingSize: 240,
            carbohydrates: 0,
            protein: 0.1,
            fat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 5,
            category: .beverages
        )
        
        let greenTea = FoodItem(
            name: "Green Tea",
            brand: "Lipton",
            caloriesPer100g: 1,
            servingSize: 240,
            carbohydrates: 0,
            protein: 0,
            fat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 1,
            category: .beverages
        )
        
        // Add sample foods with popular barcodes for testing
        let cocaCola = FoodItem(
            name: "Coca-Cola Classic",
            brand: "Coca-Cola",
            barcode: "049000028913", // Real Coca-Cola barcode
            caloriesPer100g: 42,
            servingSize: 355,
            carbohydrates: 10.6,
            protein: 0,
            fat: 0,
            fiber: 0,
            sugar: 10.6,
            sodium: 9,
            category: .beverages
        )
        
        let cheerios = FoodItem(
            name: "Cheerios Original",
            brand: "General Mills",
            barcode: "016000275263", // Real Cheerios barcode
            caloriesPer100g: 367,
            servingSize: 28,
            carbohydrates: 73.3,
            protein: 10.0,
            fat: 6.7,
            fiber: 10.0,
            sugar: 3.3,
            sodium: 500,
            category: .grains
        )
        
        let kindBar = FoodItem(
            name: "KIND Bar, Dark Chocolate Nuts",
            brand: "KIND",
            barcode: "602652171215", // Real KIND bar barcode
            caloriesPer100g: 500,
            servingSize: 40,
            carbohydrates: 35.0,
            protein: 15.0,
            fat: 35.0,
            fiber: 7.5,
            sugar: 12.5,
            sodium: 375,
            category: .snacks
        )
        
        // Insert all sample foods
        let sampleFoods = [
            oatmeal, greekYogurt, banana, almonds,
            chickenBreast, brownRice, broccoli,
            salmon, sweetPotato, spinach,
            apple, peanutButter, wholeWheatBread,
            coffee, greenTea,
            cocaCola, cheerios, kindBar
        ]
        
        for food in sampleFoods {
            context.insert(food)
        }
        
        // Create some sample custom meals
        createSampleMeals(context: context, foods: sampleFoods)
        
        try? context.save()
        print("✅ Created \(sampleFoods.count) sample foods and meals")
    }
    
    private static func createSampleMeals(context: ModelContext, foods: [FoodItem]) {
        // Healthy Breakfast Bowl
        if let oats = foods.first(where: { $0.name.contains("Oats") }),
           let yogurt = foods.first(where: { $0.name.contains("Greek Yogurt") }),
           let banana = foods.first(where: { $0.name.contains("Banana") }),
           let almonds = foods.first(where: { $0.name.contains("Almonds") }) {
            
            let breakfastBowl = CustomMeal(
                name: "Protein Power Breakfast Bowl",
                details: "Steel cut oats with Greek yogurt, fresh banana, and almonds",
                foodItems: [
                    CustomMealItem(foodItem: oats, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: yogurt, quantity: 0.5, unit: .servings),
                    CustomMealItem(foodItem: banana, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: almonds, quantity: 0.5, unit: .servings)
                ],
                category: .breakfast
            )
            breakfastBowl.isFavorite = true
            context.insert(breakfastBowl)
        }
        
        // Balanced Lunch
        if let chicken = foods.first(where: { $0.name.contains("Chicken") }),
           let rice = foods.first(where: { $0.name.contains("Rice") }),
           let broccoli = foods.first(where: { $0.name.contains("Broccoli") }) {
            
            let balancedLunch = CustomMeal(
                name: "Lean & Green Lunch",
                details: "Grilled chicken breast with brown rice and steamed broccoli",
                foodItems: [
                    CustomMealItem(foodItem: chicken, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: rice, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: broccoli, quantity: 1.5, unit: .servings)
                ],
                category: .lunch
            )
            context.insert(balancedLunch)
        }
        
        // Salmon Dinner
        if let salmon = foods.first(where: { $0.name.contains("Salmon") }),
           let sweetPotato = foods.first(where: { $0.name.contains("Sweet Potato") }),
           let spinach = foods.first(where: { $0.name.contains("Spinach") }) {
            
            let salmonDinner = CustomMeal(
                name: "Omega-3 Salmon Dinner",
                details: "Baked Atlantic salmon with roasted sweet potato and fresh spinach",
                foodItems: [
                    CustomMealItem(foodItem: salmon, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: sweetPotato, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: spinach, quantity: 2, unit: .servings)
                ],
                category: .dinner
            )
            salmonDinner.isFavorite = true
            context.insert(salmonDinner)
        }
        
        // Healthy Snack
        if let apple = foods.first(where: { $0.name.contains("Apple") }),
           let peanutButter = foods.first(where: { $0.name.contains("Peanut Butter") }) {
            
            let healthySnack = CustomMeal(
                name: "Apple & PB Power Snack",
                details: "Fresh apple slices with natural peanut butter",
                foodItems: [
                    CustomMealItem(foodItem: apple, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: peanutButter, quantity: 0.5, unit: .servings)
                ],
                category: .snacks
            )
            context.insert(healthySnack)
        }
    }
}
