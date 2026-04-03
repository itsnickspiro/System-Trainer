import Foundation
import SwiftData

// MARK: - Sample Food Data (200+ items)

class SampleFoodData {
    static func createSampleFoods(context: ModelContext) {
        // Check if we already have foods
        let descriptor = FetchDescriptor<FoodItem>()
        let existingFoods = (try? context.fetch(descriptor)) ?? []

        if existingFoods.isEmpty {
            let foods = buildAllFoods()
            for food in foods {
                context.insert(food)
            }
            createSampleMeals(context: context, foods: foods)
            context.safeSave()
            print("✅ Created \(foods.count) sample foods and meals")
        }
    }

    // swiftlint:disable function_body_length
    static func buildAllFoods() -> [FoodItem] {
        var foods: [FoodItem] = []

        // MARK: Proteins — Meats & Fish
        foods += [
            FoodItem(name: "Chicken Breast, Grilled", brand: nil, caloriesPer100g: 165,
                     servingSize: 150, carbohydrates: 0, protein: 31.0, fat: 3.6,
                     fiber: 0, sugar: 0, sodium: 74, category: .protein),
            FoodItem(name: "Chicken Thigh, Skinless", brand: nil, caloriesPer100g: 177,
                     servingSize: 140, carbohydrates: 0, protein: 24.0, fat: 9.0,
                     fiber: 0, sugar: 0, sodium: 90, category: .protein),
            FoodItem(name: "Ground Turkey 93% Lean", brand: nil, caloriesPer100g: 148,
                     servingSize: 112, carbohydrates: 0, protein: 22.0, fat: 6.5,
                     fiber: 0, sugar: 0, sodium: 79, category: .protein),
            FoodItem(name: "Atlantic Salmon, Baked", brand: nil, caloriesPer100g: 206,
                     servingSize: 140, carbohydrates: 0, protein: 22.1, fat: 12.4,
                     fiber: 0, sugar: 0, sodium: 59, category: .protein),
            FoodItem(name: "Tuna, Canned in Water", brand: "StarKist", caloriesPer100g: 116,
                     servingSize: 85, carbohydrates: 0, protein: 25.5, fat: 1.0,
                     fiber: 0, sugar: 0, sodium: 320, category: .protein),
            FoodItem(name: "Tilapia Fillet, Baked", brand: nil, caloriesPer100g: 96,
                     servingSize: 140, carbohydrates: 0, protein: 20.1, fat: 2.0,
                     fiber: 0, sugar: 0, sodium: 52, category: .protein),
            FoodItem(name: "Shrimp, Cooked", brand: nil, caloriesPer100g: 99,
                     servingSize: 85, carbohydrates: 0, protein: 21.0, fat: 1.1,
                     fiber: 0, sugar: 0, sodium: 190, category: .protein),
            FoodItem(name: "Lean Ground Beef 95%", brand: nil, caloriesPer100g: 152,
                     servingSize: 112, carbohydrates: 0, protein: 22.0, fat: 7.0,
                     fiber: 0, sugar: 0, sodium: 72, category: .protein),
            FoodItem(name: "Sirloin Steak, Grilled", brand: nil, caloriesPer100g: 207,
                     servingSize: 170, carbohydrates: 0, protein: 26.0, fat: 11.0,
                     fiber: 0, sugar: 0, sodium: 65, category: .protein),
            FoodItem(name: "Turkey Breast, Deli Sliced", brand: "Boar's Head", caloriesPer100g: 109,
                     servingSize: 56, carbohydrates: 2.0, protein: 18.0, fat: 2.5,
                     fiber: 0, sugar: 1.0, sodium: 450, category: .protein),
            FoodItem(name: "Cod Fillet, Baked", brand: nil, caloriesPer100g: 82,
                     servingSize: 140, carbohydrates: 0, protein: 17.5, fat: 0.7,
                     fiber: 0, sugar: 0, sodium: 65, category: .protein),
            FoodItem(name: "Sardines in Olive Oil", brand: "Season", caloriesPer100g: 208,
                     servingSize: 85, carbohydrates: 0, protein: 22.0, fat: 13.0,
                     fiber: 0, sugar: 0, sodium: 400, category: .protein),
        ]

        // MARK: Proteins — Eggs & Dairy Protein
        foods += [
            FoodItem(name: "Whole Egg, Large", brand: nil, caloriesPer100g: 143,
                     servingSize: 50, carbohydrates: 0.7, protein: 12.6, fat: 9.5,
                     fiber: 0, sugar: 0.2, sodium: 142, category: .protein),
            FoodItem(name: "Egg Whites, Liquid", brand: nil, caloriesPer100g: 52,
                     servingSize: 61, carbohydrates: 0.7, protein: 10.9, fat: 0.2,
                     fiber: 0, sugar: 0.7, sodium: 169, category: .protein),
            FoodItem(name: "Cottage Cheese 2%", brand: "Daisy", caloriesPer100g: 90,
                     servingSize: 113, carbohydrates: 4.5, protein: 13.5, fat: 2.5,
                     fiber: 0, sugar: 4.5, sodium: 310, category: .dairy),
            FoodItem(name: "Greek Yogurt, Plain 0%", brand: "Fage", caloriesPer100g: 57,
                     servingSize: 170, carbohydrates: 4.0, protein: 10.0, fat: 0.4,
                     fiber: 0, sugar: 4.0, sodium: 36, category: .dairy),
            FoodItem(name: "Greek Yogurt, Plain 2%", brand: "Chobani", caloriesPer100g: 80,
                     servingSize: 170, carbohydrates: 5.0, protein: 14.0, fat: 2.0,
                     fiber: 0, sugar: 5.0, sodium: 70, category: .dairy),
            FoodItem(name: "Whey Protein Isolate", brand: "Optimum Nutrition", caloriesPer100g: 370,
                     servingSize: 31, carbohydrates: 4.0, protein: 25.0, fat: 1.0,
                     fiber: 0, sugar: 1.0, sodium: 90, category: .protein),
            FoodItem(name: "Casein Protein Powder", brand: "Dymatize", caloriesPer100g: 370,
                     servingSize: 34, carbohydrates: 5.0, protein: 25.0, fat: 1.5,
                     fiber: 1.0, sugar: 1.0, sodium: 230, category: .protein),
        ]

        // MARK: Legumes & Plant Proteins
        foods += [
            FoodItem(name: "Black Beans, Cooked", brand: nil, caloriesPer100g: 132,
                     servingSize: 130, carbohydrates: 24.0, protein: 8.9, fat: 0.5,
                     fiber: 8.7, sugar: 0.3, sodium: 2, category: .protein),
            FoodItem(name: "Chickpeas, Cooked", brand: nil, caloriesPer100g: 164,
                     servingSize: 164, carbohydrates: 27.0, protein: 8.9, fat: 2.6,
                     fiber: 7.6, sugar: 4.8, sodium: 7, category: .protein),
            FoodItem(name: "Lentils, Cooked", brand: nil, caloriesPer100g: 116,
                     servingSize: 198, carbohydrates: 20.0, protein: 9.0, fat: 0.4,
                     fiber: 7.9, sugar: 1.8, sodium: 4, category: .protein),
            FoodItem(name: "Edamame, Shelled", brand: nil, caloriesPer100g: 122,
                     servingSize: 155, carbohydrates: 9.9, protein: 11.9, fat: 5.2,
                     fiber: 5.2, sugar: 2.2, sodium: 9, category: .protein),
            FoodItem(name: "Tofu, Extra Firm", brand: "Nasoya", caloriesPer100g: 76,
                     servingSize: 140, carbohydrates: 2.0, protein: 9.4, fat: 4.2,
                     fiber: 0.3, sugar: 0.5, sodium: 10, category: .protein),
            FoodItem(name: "Tempeh", brand: nil, caloriesPer100g: 193,
                     servingSize: 85, carbohydrates: 9.4, protein: 19.0, fat: 11.0,
                     fiber: 0, sugar: 0, sodium: 9, category: .protein),
            FoodItem(name: "Kidney Beans, Cooked", brand: nil, caloriesPer100g: 127,
                     servingSize: 177, carbohydrates: 23.0, protein: 8.7, fat: 0.5,
                     fiber: 6.4, sugar: 0.3, sodium: 2, category: .protein),
        ]

        // MARK: Grains & Carbohydrates
        foods += [
            FoodItem(name: "Steel Cut Oats", brand: "Quaker", caloriesPer100g: 379,
                     servingSize: 40, carbohydrates: 67.7, protein: 13.2, fat: 6.5,
                     fiber: 10.1, sugar: 1.1, sodium: 2, category: .grains),
            FoodItem(name: "Rolled Oats", brand: "Bob's Red Mill", caloriesPer100g: 389,
                     servingSize: 40, carbohydrates: 66.0, protein: 14.0, fat: 7.0,
                     fiber: 10.0, sugar: 1.0, sodium: 5, category: .grains),
            FoodItem(name: "Brown Rice, Cooked", brand: nil, caloriesPer100g: 111,
                     servingSize: 200, carbohydrates: 23.0, protein: 2.6, fat: 0.9,
                     fiber: 1.8, sugar: 0.4, sodium: 5, category: .grains),
            FoodItem(name: "White Rice, Cooked", brand: nil, caloriesPer100g: 130,
                     servingSize: 186, carbohydrates: 28.0, protein: 2.7, fat: 0.3,
                     fiber: 0.4, sugar: 0, sodium: 2, category: .grains),
            FoodItem(name: "Quinoa, Cooked", brand: nil, caloriesPer100g: 120,
                     servingSize: 185, carbohydrates: 21.3, protein: 4.4, fat: 1.9,
                     fiber: 2.8, sugar: 0.9, sodium: 7, category: .grains),
            FoodItem(name: "Whole Wheat Bread", brand: "Dave's Killer Bread", caloriesPer100g: 247,
                     servingSize: 45, carbohydrates: 43.3, protein: 13.4, fat: 4.2,
                     fiber: 7.0, sugar: 5.6, sodium: 491, category: .grains),
            FoodItem(name: "White Bread", brand: "Wonder", caloriesPer100g: 266,
                     servingSize: 25, carbohydrates: 50.0, protein: 8.0, fat: 3.5,
                     fiber: 2.0, sugar: 4.0, sodium: 506, category: .grains),
            FoodItem(name: "Whole Wheat Pasta, Dry", brand: "Barilla", caloriesPer100g: 348,
                     servingSize: 56, carbohydrates: 68.0, protein: 14.0, fat: 2.5,
                     fiber: 7.0, sugar: 3.0, sodium: 7, category: .grains),
            FoodItem(name: "Pasta (White), Cooked", brand: nil, caloriesPer100g: 131,
                     servingSize: 140, carbohydrates: 25.0, protein: 5.0, fat: 1.1,
                     fiber: 1.0, sugar: 0.6, sodium: 3, category: .grains),
            FoodItem(name: "Sweet Potato, Baked", brand: nil, caloriesPer100g: 86,
                     servingSize: 130, carbohydrates: 20.1, protein: 1.6, fat: 0.1,
                     fiber: 3.0, sugar: 4.2, sodium: 4, category: .vegetables),
            FoodItem(name: "White Potato, Baked", brand: nil, caloriesPer100g: 93,
                     servingSize: 173, carbohydrates: 21.1, protein: 2.5, fat: 0.1,
                     fiber: 2.1, sugar: 0.9, sodium: 10, category: .vegetables),
            FoodItem(name: "Corn Tortilla", brand: "Mission", caloriesPer100g: 218,
                     servingSize: 28, carbohydrates: 44.0, protein: 5.7, fat: 3.0,
                     fiber: 5.3, sugar: 0.7, sodium: 376, category: .grains),
            FoodItem(name: "Basmati Rice, Cooked", brand: nil, caloriesPer100g: 121,
                     servingSize: 186, carbohydrates: 25.2, protein: 3.5, fat: 0.4,
                     fiber: 0.4, sugar: 0, sodium: 1, category: .grains),
            FoodItem(name: "Ezekiel Bread", brand: "Food for Life", caloriesPer100g: 253,
                     servingSize: 34, carbohydrates: 41.3, protein: 10.0, fat: 1.0,
                     fiber: 6.7, sugar: 0, sodium: 173, category: .grains),
            FoodItem(name: "Buckwheat Groats, Cooked", brand: nil, caloriesPer100g: 92,
                     servingSize: 168, carbohydrates: 19.9, protein: 3.4, fat: 0.6,
                     fiber: 2.7, sugar: 0.9, sodium: 4, category: .grains),
        ]

        // MARK: Vegetables
        foods += [
            FoodItem(name: "Broccoli, Steamed", brand: nil, caloriesPer100g: 35,
                     servingSize: 150, carbohydrates: 7.0, protein: 2.8, fat: 0.4,
                     fiber: 2.6, sugar: 1.5, sodium: 33, category: .vegetables),
            FoodItem(name: "Spinach, Fresh", brand: nil, caloriesPer100g: 23,
                     servingSize: 30, carbohydrates: 3.6, protein: 2.9, fat: 0.4,
                     fiber: 2.2, sugar: 0.4, sodium: 79, category: .vegetables),
            FoodItem(name: "Kale, Raw", brand: nil, caloriesPer100g: 49,
                     servingSize: 67, carbohydrates: 8.8, protein: 4.3, fat: 0.9,
                     fiber: 3.6, sugar: 1.0, sodium: 38, category: .vegetables),
            FoodItem(name: "Mixed Salad Greens", brand: nil, caloriesPer100g: 20,
                     servingSize: 85, carbohydrates: 3.5, protein: 2.0, fat: 0.3,
                     fiber: 1.5, sugar: 1.8, sodium: 45, category: .vegetables),
            FoodItem(name: "Romaine Lettuce", brand: nil, caloriesPer100g: 17,
                     servingSize: 85, carbohydrates: 3.3, protein: 1.2, fat: 0.3,
                     fiber: 2.1, sugar: 1.1, sodium: 8, category: .vegetables),
            FoodItem(name: "Cucumber, Sliced", brand: nil, caloriesPer100g: 16,
                     servingSize: 119, carbohydrates: 3.6, protein: 0.7, fat: 0.1,
                     fiber: 0.5, sugar: 1.7, sodium: 2, category: .vegetables),
            FoodItem(name: "Cherry Tomatoes", brand: nil, caloriesPer100g: 18,
                     servingSize: 149, carbohydrates: 3.9, protein: 0.9, fat: 0.2,
                     fiber: 1.2, sugar: 2.6, sodium: 5, category: .vegetables),
            FoodItem(name: "Bell Pepper, Red", brand: nil, caloriesPer100g: 31,
                     servingSize: 149, carbohydrates: 7.2, protein: 1.0, fat: 0.3,
                     fiber: 2.1, sugar: 4.7, sodium: 2, category: .vegetables),
            FoodItem(name: "Zucchini, Cooked", brand: nil, caloriesPer100g: 17,
                     servingSize: 180, carbohydrates: 3.5, protein: 1.3, fat: 0.3,
                     fiber: 1.2, sugar: 2.1, sodium: 3, category: .vegetables),
            FoodItem(name: "Asparagus, Steamed", brand: nil, caloriesPer100g: 20,
                     servingSize: 134, carbohydrates: 3.9, protein: 2.2, fat: 0.2,
                     fiber: 2.1, sugar: 1.9, sodium: 2, category: .vegetables),
            FoodItem(name: "Green Beans, Cooked", brand: nil, caloriesPer100g: 35,
                     servingSize: 125, carbohydrates: 7.9, protein: 1.9, fat: 0.1,
                     fiber: 3.4, sugar: 3.4, sodium: 1, category: .vegetables),
            FoodItem(name: "Cauliflower, Steamed", brand: nil, caloriesPer100g: 25,
                     servingSize: 107, carbohydrates: 5.3, protein: 1.9, fat: 0.3,
                     fiber: 2.1, sugar: 2.4, sodium: 30, category: .vegetables),
            FoodItem(name: "Mushrooms, Sautéed", brand: nil, caloriesPer100g: 38,
                     servingSize: 156, carbohydrates: 5.9, protein: 3.8, fat: 0.5,
                     fiber: 1.1, sugar: 2.9, sodium: 14, category: .vegetables),
            FoodItem(name: "Onion, Yellow", brand: nil, caloriesPer100g: 40,
                     servingSize: 148, carbohydrates: 9.3, protein: 1.1, fat: 0.1,
                     fiber: 1.7, sugar: 4.2, sodium: 4, category: .vegetables),
            FoodItem(name: "Carrot, Raw", brand: nil, caloriesPer100g: 41,
                     servingSize: 61, carbohydrates: 9.6, protein: 0.9, fat: 0.2,
                     fiber: 2.8, sugar: 4.7, sodium: 69, category: .vegetables),
            FoodItem(name: "Celery, Raw", brand: nil, caloriesPer100g: 16,
                     servingSize: 101, carbohydrates: 3.5, protein: 0.7, fat: 0.2,
                     fiber: 1.6, sugar: 1.8, sodium: 80, category: .vegetables),
            FoodItem(name: "Brussels Sprouts, Roasted", brand: nil, caloriesPer100g: 43,
                     servingSize: 88, carbohydrates: 9.0, protein: 3.4, fat: 0.3,
                     fiber: 3.8, sugar: 2.2, sodium: 25, category: .vegetables),
        ]

        // MARK: Fruits
        foods += [
            FoodItem(name: "Banana, Medium", brand: nil, caloriesPer100g: 89,
                     servingSize: 118, carbohydrates: 22.8, protein: 1.1, fat: 0.3,
                     fiber: 2.6, sugar: 12.2, sodium: 1, category: .fruits),
            FoodItem(name: "Apple, Medium", brand: nil, caloriesPer100g: 52,
                     servingSize: 182, carbohydrates: 13.8, protein: 0.3, fat: 0.2,
                     fiber: 2.4, sugar: 10.4, sodium: 1, category: .fruits),
            FoodItem(name: "Blueberries, Fresh", brand: nil, caloriesPer100g: 57,
                     servingSize: 148, carbohydrates: 14.5, protein: 0.7, fat: 0.3,
                     fiber: 2.4, sugar: 10.0, sodium: 1, category: .fruits),
            FoodItem(name: "Strawberries, Fresh", brand: nil, caloriesPer100g: 32,
                     servingSize: 152, carbohydrates: 7.7, protein: 0.7, fat: 0.3,
                     fiber: 2.0, sugar: 4.9, sodium: 1, category: .fruits),
            FoodItem(name: "Orange, Navel", brand: nil, caloriesPer100g: 47,
                     servingSize: 154, carbohydrates: 11.8, protein: 0.9, fat: 0.1,
                     fiber: 2.4, sugar: 9.4, sodium: 0, category: .fruits),
            FoodItem(name: "Mango, Diced", brand: nil, caloriesPer100g: 60,
                     servingSize: 165, carbohydrates: 15.0, protein: 0.8, fat: 0.4,
                     fiber: 1.6, sugar: 13.7, sodium: 2, category: .fruits),
            FoodItem(name: "Pineapple, Fresh Chunks", brand: nil, caloriesPer100g: 50,
                     servingSize: 165, carbohydrates: 13.1, protein: 0.5, fat: 0.1,
                     fiber: 1.4, sugar: 9.9, sodium: 1, category: .fruits),
            FoodItem(name: "Grapes, Red", brand: nil, caloriesPer100g: 69,
                     servingSize: 151, carbohydrates: 18.1, protein: 0.6, fat: 0.2,
                     fiber: 0.9, sugar: 15.5, sodium: 2, category: .fruits),
            FoodItem(name: "Watermelon, Cubed", brand: nil, caloriesPer100g: 30,
                     servingSize: 286, carbohydrates: 7.6, protein: 0.6, fat: 0.2,
                     fiber: 0.4, sugar: 6.2, sodium: 2, category: .fruits),
            FoodItem(name: "Avocado, Hass", brand: nil, caloriesPer100g: 160,
                     servingSize: 201, carbohydrates: 8.5, protein: 2.0, fat: 14.7,
                     fiber: 6.7, sugar: 0.7, sodium: 7, category: .fats),
            FoodItem(name: "Raspberries, Fresh", brand: nil, caloriesPer100g: 52,
                     servingSize: 123, carbohydrates: 11.9, protein: 1.2, fat: 0.7,
                     fiber: 6.5, sugar: 4.4, sodium: 1, category: .fruits),
            FoodItem(name: "Kiwi, Green", brand: nil, caloriesPer100g: 61,
                     servingSize: 76, carbohydrates: 15.0, protein: 1.1, fat: 0.5,
                     fiber: 3.0, sugar: 9.0, sodium: 3, category: .fruits),
        ]

        // MARK: Dairy
        foods += [
            FoodItem(name: "Whole Milk", brand: nil, caloriesPer100g: 61,
                     servingSize: 244, carbohydrates: 4.8, protein: 3.2, fat: 3.3,
                     fiber: 0, sugar: 4.8, sodium: 43, category: .dairy),
            FoodItem(name: "Skim Milk", brand: nil, caloriesPer100g: 34,
                     servingSize: 244, carbohydrates: 5.0, protein: 3.4, fat: 0.2,
                     fiber: 0, sugar: 5.0, sodium: 44, category: .dairy),
            FoodItem(name: "Almond Milk, Unsweetened", brand: "Califia", caloriesPer100g: 15,
                     servingSize: 240, carbohydrates: 1.3, protein: 0.4, fat: 1.2,
                     fiber: 0.3, sugar: 0, sodium: 160, category: .dairy),
            FoodItem(name: "Oat Milk", brand: "Oatly", caloriesPer100g: 47,
                     servingSize: 240, carbohydrates: 8.3, protein: 1.3, fat: 1.7,
                     fiber: 0.8, sugar: 4.2, sodium: 100, category: .dairy),
            FoodItem(name: "Cheddar Cheese", brand: "Tillamook", caloriesPer100g: 403,
                     servingSize: 28, carbohydrates: 1.3, protein: 23.0, fat: 33.0,
                     fiber: 0, sugar: 0.5, sodium: 621, category: .dairy),
            FoodItem(name: "Mozzarella, Part Skim", brand: nil, caloriesPer100g: 254,
                     servingSize: 28, carbohydrates: 2.2, protein: 16.0, fat: 17.0,
                     fiber: 0, sugar: 0.7, sodium: 406, category: .dairy),
            FoodItem(name: "Parmesan, Grated", brand: "Kraft", caloriesPer100g: 431,
                     servingSize: 5, carbohydrates: 3.8, protein: 38.0, fat: 29.0,
                     fiber: 0, sugar: 0.9, sodium: 1529, category: .dairy),
            FoodItem(name: "Butter, Unsalted", brand: "Land O'Lakes", caloriesPer100g: 717,
                     servingSize: 14, carbohydrates: 0.1, protein: 0.1, fat: 81.1,
                     fiber: 0, sugar: 0.1, sodium: 11, category: .fats),
        ]

        // MARK: Nuts & Seeds
        foods += [
            FoodItem(name: "Almonds, Raw", brand: nil, caloriesPer100g: 579,
                     servingSize: 28, carbohydrates: 21.6, protein: 21.2, fat: 49.9,
                     fiber: 12.5, sugar: 4.4, sodium: 1, category: .fats),
            FoodItem(name: "Walnuts, Raw", brand: nil, caloriesPer100g: 654,
                     servingSize: 28, carbohydrates: 13.7, protein: 15.2, fat: 65.2,
                     fiber: 6.7, sugar: 2.6, sodium: 2, category: .fats),
            FoodItem(name: "Cashews, Roasted", brand: nil, caloriesPer100g: 553,
                     servingSize: 28, carbohydrates: 32.7, protein: 14.8, fat: 43.9,
                     fiber: 3.3, sugar: 5.9, sodium: 181, category: .fats),
            FoodItem(name: "Peanut Butter, Natural", brand: "Justin's", caloriesPer100g: 588,
                     servingSize: 32, carbohydrates: 20.0, protein: 25.8, fat: 50.0,
                     fiber: 6.0, sugar: 9.2, sodium: 17, category: .fats),
            FoodItem(name: "Almond Butter", brand: "Barney Butter", caloriesPer100g: 614,
                     servingSize: 32, carbohydrates: 18.8, protein: 21.2, fat: 55.5,
                     fiber: 12.5, sugar: 3.7, sodium: 2, category: .fats),
            FoodItem(name: "Chia Seeds", brand: nil, caloriesPer100g: 486,
                     servingSize: 28, carbohydrates: 42.1, protein: 16.5, fat: 30.7,
                     fiber: 34.4, sugar: 0, sodium: 16, category: .fats),
            FoodItem(name: "Flaxseed, Ground", brand: nil, caloriesPer100g: 534,
                     servingSize: 10, carbohydrates: 28.9, protein: 18.3, fat: 42.2,
                     fiber: 27.3, sugar: 1.6, sodium: 30, category: .fats),
            FoodItem(name: "Hemp Seeds", brand: "Manitoba Harvest", caloriesPer100g: 553,
                     servingSize: 30, carbohydrates: 8.7, protein: 31.6, fat: 48.8,
                     fiber: 4.0, sugar: 1.5, sodium: 5, category: .fats),
            FoodItem(name: "Pistachios, Shelled", brand: nil, caloriesPer100g: 562,
                     servingSize: 28, carbohydrates: 27.7, protein: 20.2, fat: 45.3,
                     fiber: 10.3, sugar: 7.7, sodium: 1, category: .fats),
            FoodItem(name: "Pumpkin Seeds", brand: nil, caloriesPer100g: 559,
                     servingSize: 28, carbohydrates: 17.8, protein: 24.5, fat: 45.9,
                     fiber: 6.0, sugar: 1.4, sodium: 5, category: .fats),
        ]

        // MARK: Oils & Condiments
        foods += [
            FoodItem(name: "Olive Oil, Extra Virgin", brand: "California Olive Ranch", caloriesPer100g: 884,
                     servingSize: 14, carbohydrates: 0, protein: 0, fat: 100.0,
                     fiber: 0, sugar: 0, sodium: 0, category: .fats),
            FoodItem(name: "Coconut Oil", brand: "Nutiva", caloriesPer100g: 862,
                     servingSize: 14, carbohydrates: 0, protein: 0, fat: 100.0,
                     fiber: 0, sugar: 0, sodium: 0, category: .fats),
            FoodItem(name: "Hummus, Classic", brand: "Sabra", caloriesPer100g: 166,
                     servingSize: 56, carbohydrates: 14.3, protein: 4.9, fat: 9.6,
                     fiber: 3.9, sugar: 1.4, sodium: 286, category: .fats),
            FoodItem(name: "Salsa, Mild", brand: "Newman's Own", caloriesPer100g: 25,
                     servingSize: 30, carbohydrates: 5.0, protein: 1.0, fat: 0,
                     fiber: 1.0, sugar: 3.0, sodium: 190, category: .condiments),
            FoodItem(name: "Soy Sauce, Low Sodium", brand: "Kikkoman", caloriesPer100g: 60,
                     servingSize: 15, carbohydrates: 5.6, protein: 5.8, fat: 0.1,
                     fiber: 0.1, sugar: 0.8, sodium: 575, category: .condiments),
            FoodItem(name: "Hot Sauce, Tabasco", brand: "McIlhenny", caloriesPer100g: 12,
                     servingSize: 5, carbohydrates: 0.3, protein: 0.1, fat: 0.1,
                     fiber: 0, sugar: 0.1, sodium: 196, category: .condiments),
        ]

        // MARK: Beverages
        foods += [
            FoodItem(name: "Coffee, Black", brand: nil, caloriesPer100g: 1,
                     servingSize: 240, carbohydrates: 0, protein: 0.1, fat: 0,
                     fiber: 0, sugar: 0, sodium: 5, category: .beverages),
            FoodItem(name: "Green Tea", brand: nil, caloriesPer100g: 1,
                     servingSize: 240, carbohydrates: 0, protein: 0, fat: 0,
                     fiber: 0, sugar: 0, sodium: 1, category: .beverages),
            FoodItem(name: "Protein Shake, Chocolate", brand: "Premier Protein", caloriesPer100g: 104,
                     servingSize: 325, carbohydrates: 4.9, protein: 30.0, fat: 3.1,
                     fiber: 1.5, sugar: 1.2, sodium: 400, category: .protein),
            FoodItem(name: "Coca-Cola Classic", brand: "Coca-Cola",
                     barcode: "049000028913", caloriesPer100g: 42,
                     servingSize: 355, carbohydrates: 10.6, protein: 0, fat: 0,
                     fiber: 0, sugar: 10.6, sodium: 9, category: .beverages),
            FoodItem(name: "Orange Juice, No Pulp", brand: "Tropicana", caloriesPer100g: 45,
                     servingSize: 240, carbohydrates: 10.5, protein: 0.7, fat: 0.2,
                     fiber: 0.2, sugar: 8.4, sodium: 2, category: .beverages),
            FoodItem(name: "Sports Drink, Lemon-Lime", brand: "Gatorade", caloriesPer100g: 26,
                     servingSize: 591, carbohydrates: 6.3, protein: 0, fat: 0,
                     fiber: 0, sugar: 5.3, sodium: 110, category: .beverages),
            FoodItem(name: "Sparkling Water", brand: "LaCroix", caloriesPer100g: 0,
                     servingSize: 355, carbohydrates: 0, protein: 0, fat: 0,
                     fiber: 0, sugar: 0, sodium: 0, category: .beverages),
            FoodItem(name: "Coconut Water", brand: "Vita Coco", caloriesPer100g: 19,
                     servingSize: 330, carbohydrates: 4.3, protein: 0.2, fat: 0.2,
                     fiber: 0, sugar: 3.7, sodium: 22, category: .beverages),
        ]

        // MARK: Snacks & Packaged Foods
        foods += [
            FoodItem(name: "Cheerios Original", brand: "General Mills",
                     barcode: "016000275263", caloriesPer100g: 367,
                     servingSize: 28, carbohydrates: 73.3, protein: 10.0, fat: 6.7,
                     fiber: 10.0, sugar: 3.3, sodium: 500, category: .grains),
            FoodItem(name: "KIND Bar, Dark Chocolate Nuts", brand: "KIND",
                     barcode: "602652171215", caloriesPer100g: 500,
                     servingSize: 40, carbohydrates: 35.0, protein: 15.0, fat: 35.0,
                     fiber: 7.5, sugar: 12.5, sodium: 375, category: .snacks),
            FoodItem(name: "Clif Bar, Chocolate Chip", brand: "Clif", caloriesPer100g: 388,
                     servingSize: 68, carbohydrates: 68.0, protein: 11.8, fat: 5.9,
                     fiber: 5.9, sugar: 22.1, sodium: 147, category: .snacks),
            FoodItem(name: "Rice Cakes, Plain", brand: "Lundberg", caloriesPer100g: 392,
                     servingSize: 9, carbohydrates: 83.3, protein: 8.3, fat: 2.5,
                     fiber: 1.7, sugar: 0, sodium: 17, category: .snacks),
            FoodItem(name: "Pretzels, Thin Twist", brand: "Snyder's", caloriesPer100g: 381,
                     servingSize: 28, carbohydrates: 78.6, protein: 9.5, fat: 4.8,
                     fiber: 3.3, sugar: 2.4, sodium: 786, category: .snacks),
            FoodItem(name: "Popcorn, Air Popped", brand: nil, caloriesPer100g: 387,
                     servingSize: 8, carbohydrates: 77.9, protein: 12.0, fat: 4.3,
                     fiber: 14.5, sugar: 0.9, sodium: 8, category: .snacks),
            FoodItem(name: "Dark Chocolate 70%", brand: "Lindt", caloriesPer100g: 598,
                     servingSize: 28, carbohydrates: 45.9, protein: 7.4, fat: 42.6,
                     fiber: 11.0, sugar: 23.0, sodium: 9, category: .snacks),
            FoodItem(name: "Granola, Low Sugar", brand: "Bear Naked", caloriesPer100g: 460,
                     servingSize: 47, carbohydrates: 64.0, protein: 10.0, fat: 18.0,
                     fiber: 5.0, sugar: 12.0, sodium: 90, category: .snacks),
            FoodItem(name: "Beef Jerky, Original", brand: "Jack Link's", caloriesPer100g: 254,
                     servingSize: 28, carbohydrates: 11.3, protein: 28.2, fat: 7.0,
                     fiber: 0.4, sugar: 8.5, sodium: 508, category: .snacks),
        ]

        // MARK: Prepared / Fast Foods
        foods += [
            FoodItem(name: "Egg Burrito, Breakfast", brand: nil, caloriesPer100g: 165,
                     servingSize: 217, carbohydrates: 28.0, protein: 10.0, fat: 5.5,
                     fiber: 2.0, sugar: 2.5, sodium: 480, category: .snacks),
            FoodItem(name: "Chicken Burrito Bowl (no rice)", brand: "Chipotle", caloriesPer100g: 127,
                     servingSize: 385, carbohydrates: 19.0, protein: 28.0, fat: 9.0,
                     fiber: 7.0, sugar: 3.0, sodium: 985, category: .snacks),
            FoodItem(name: "Turkey & Veggie Wrap", brand: nil, caloriesPer100g: 165,
                     servingSize: 200, carbohydrates: 25.0, protein: 18.0, fat: 4.5,
                     fiber: 3.5, sugar: 3.5, sodium: 680, category: .snacks),
            FoodItem(name: "Mixed Nuts, Unsalted", brand: "Planters", caloriesPer100g: 607,
                     servingSize: 30, carbohydrates: 16.5, protein: 15.0, fat: 54.4,
                     fiber: 5.2, sugar: 3.4, sodium: 4, category: .fats),
        ]

        // MARK: Supplements
        foods += [
            FoodItem(name: "Creatine Monohydrate", brand: "Optimum Nutrition", caloriesPer100g: 0,
                     servingSize: 5, carbohydrates: 0, protein: 0, fat: 0,
                     fiber: 0, sugar: 0, sodium: 0, category: .other),
            FoodItem(name: "BCAA Powder", brand: "Xtend", caloriesPer100g: 50,
                     servingSize: 14, carbohydrates: 1.0, protein: 7.0, fat: 0,
                     fiber: 0, sugar: 0, sodium: 270, category: .other),
            FoodItem(name: "Pre-Workout, Fruit Punch", brand: "C4", caloriesPer100g: 167,
                     servingSize: 6, carbohydrates: 7.0, protein: 0, fat: 0,
                     fiber: 0, sugar: 0, sodium: 160, category: .other),
            FoodItem(name: "Fish Oil Capsule", brand: "Nordic Naturals", caloriesPer100g: 897,
                     servingSize: 4, carbohydrates: 0, protein: 0, fat: 99.0,
                     fiber: 0, sugar: 0, sodium: 0, category: .fats),
        ]

        return foods
    }
    // swiftlint:enable function_body_length

    private static func createSampleMeals(context: ModelContext, foods: [FoodItem]) {
        // Protein Power Breakfast Bowl
        if let oats = foods.first(where: { $0.name.contains("Oats") }),
           let yogurt = foods.first(where: { $0.name.contains("Greek Yogurt") }),
           let banana = foods.first(where: { $0.name.contains("Banana") }),
           let almonds = foods.first(where: { $0.name.contains("Almonds") }) {
            let meal = CustomMeal(
                name: "Protein Power Breakfast Bowl",
                details: "Steel cut oats with Greek yogurt, banana and almonds",
                foodItems: [
                    CustomMealItem(foodItem: oats, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: yogurt, quantity: 0.5, unit: .servings),
                    CustomMealItem(foodItem: banana, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: almonds, quantity: 0.5, unit: .servings),
                ],
                category: .breakfast
            )
            meal.isFavorite = true
            context.insert(meal)
        }

        // Lean & Green Lunch
        if let chicken = foods.first(where: { $0.name.contains("Chicken Breast") }),
           let rice = foods.first(where: { $0.name.contains("Brown Rice") }),
           let broccoli = foods.first(where: { $0.name.contains("Broccoli") }) {
            let meal = CustomMeal(
                name: "Lean & Green Lunch",
                details: "Grilled chicken breast with brown rice and steamed broccoli",
                foodItems: [
                    CustomMealItem(foodItem: chicken, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: rice, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: broccoli, quantity: 1.5, unit: .servings),
                ],
                category: .lunch
            )
            context.insert(meal)
        }

        // Omega-3 Salmon Dinner
        if let salmon = foods.first(where: { $0.name.contains("Salmon") }),
           let sweetPotato = foods.first(where: { $0.name.contains("Sweet Potato") }),
           let spinach = foods.first(where: { $0.name.contains("Spinach") }) {
            let meal = CustomMeal(
                name: "Omega-3 Salmon Dinner",
                details: "Baked salmon with sweet potato and fresh spinach",
                foodItems: [
                    CustomMealItem(foodItem: salmon, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: sweetPotato, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: spinach, quantity: 2, unit: .servings),
                ],
                category: .dinner
            )
            meal.isFavorite = true
            context.insert(meal)
        }

        // Apple & PB Power Snack
        if let apple = foods.first(where: { $0.name == "Apple, Medium" }),
           let pb = foods.first(where: { $0.name.contains("Peanut Butter") }) {
            let meal = CustomMeal(
                name: "Apple & PB Power Snack",
                details: "Fresh apple with natural peanut butter",
                foodItems: [
                    CustomMealItem(foodItem: apple, quantity: 1, unit: .servings),
                    CustomMealItem(foodItem: pb, quantity: 0.5, unit: .servings),
                ],
                category: .snacks
            )
            context.insert(meal)
        }
    }
}
