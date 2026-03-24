import SwiftUI
import SwiftData

// MARK: - Recipe Nutrition Calculator

/// Lets the user build a recipe from food-database ingredients and see the total macro/micro breakdown.
struct RecipeNutritionCalculatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allFoods: [FoodItem]

    @State private var recipeName: String = ""
    @State private var servings: Int = 4
    @State private var ingredients: [RecipeIngredient] = []
    @State private var showingIngredientSearch = false
    @State private var searchText: String = ""
    @State private var selectedIngredientIndex: Int? = nil

    // MARK: Totals

    private var totalCalories: Double { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double  { ingredients.reduce(0) { $0 + $1.protein } }
    private var totalCarbs: Double    { ingredients.reduce(0) { $0 + $1.carbs } }
    private var totalFat: Double      { ingredients.reduce(0) { $0 + $1.fat } }
    private var totalFiber: Double    { ingredients.reduce(0) { $0 + $1.fiber } }
    private var totalSodium: Double   { ingredients.reduce(0) { $0 + $1.sodium } }

    private var perServingCalories: Double { totalCalories / Double(max(1, servings)) }
    private var perServingProtein: Double  { totalProtein  / Double(max(1, servings)) }
    private var perServingCarbs: Double    { totalCarbs    / Double(max(1, servings)) }
    private var perServingFat: Double      { totalFat      / Double(max(1, servings)) }

    var body: some View {
        NavigationStack {
            List {
                // Recipe info
                Section {
                    TextField("Recipe name", text: $recipeName)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...50)
                }

                // Ingredients
                Section(header: Text("Ingredients")) {
                    ForEach($ingredients) { $ing in
                        IngredientRowEditor(ingredient: $ing)
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }

                    Button {
                        showingIngredientSearch = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                // Nutrition summary
                if !ingredients.isEmpty {
                    Section(header: Text("Nutrition Summary")) {
                        totalsCard
                    }

                    Section(header: Text("Per Serving (\(servings) servings)")) {
                        perServingCard
                    }

                    Section(header: Text("Macros Breakdown")) {
                        macrosPieRow
                    }
                }
            }
            .navigationTitle("Recipe Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                if !ingredients.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Log Total") {
                            logRecipe()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingIngredientSearch) {
                IngredientSearchSheet(allFoods: allFoods) { food, grams in
                    let ing = RecipeIngredient(food: food, grams: grams)
                    ingredients.append(ing)
                }
            }
        }
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Whole Recipe")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(totalCalories)) kcal")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
            }
            nutritionRow("Protein", value: totalProtein, unit: "g", color: .green)
            nutritionRow("Carbs",   value: totalCarbs,   unit: "g", color: .blue)
            nutritionRow("Fat",     value: totalFat,     unit: "g", color: .red)
            nutritionRow("Fiber",   value: totalFiber,   unit: "g", color: .purple)
            if totalSodium > 0 {
                nutritionRow("Sodium", value: totalSodium, unit: "mg", color: .yellow)
            }
        }
    }

    private var perServingCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Per Serving")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(perServingCalories)) kcal")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.orange)
            }
            nutritionRow("Protein", value: perServingProtein, unit: "g", color: .green)
            nutritionRow("Carbs",   value: perServingCarbs,   unit: "g", color: .blue)
            nutritionRow("Fat",     value: perServingFat,     unit: "g", color: .red)
        }
    }

    // MARK: - Macros Breakdown (visual bar)

    private var macrosPieRow: some View {
        let proteinCals = perServingProtein * 4
        let carbsCals   = perServingCarbs * 4
        let fatCals     = perServingFat * 9
        let total       = max(1, proteinCals + carbsCals + fatCals)

        return VStack(spacing: 8) {
            // Stacked horizontal bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * proteinCals / total)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * carbsCals / total)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * fatCals / total)
                }
                .cornerRadius(4)
            }
            .frame(height: 14)

            // Legend
            HStack(spacing: 16) {
                legendDot(color: .green, label: "Protein \(Int(proteinCals / total * 100))%")
                legendDot(color: .blue,  label: "Carbs \(Int(carbsCals / total * 100))%")
                legendDot(color: .red,   label: "Fat \(Int(fatCals / total * 100))%")
            }
            .font(.caption2)
        }
    }

    // MARK: - Actions

    private func logRecipe() {
        let name = recipeName.isEmpty ? "Recipe (\(ingredients.count) items)" : recipeName
        // Store per-serving values as per-100g equivalents with servingSize = 100
        let foodItem = FoodItem(
            name: name,
            brand: "Recipe",
            caloriesPer100g: perServingCalories,
            servingSize: 100,
            carbohydrates: perServingCarbs,
            protein: perServingProtein,
            fat: perServingFat,
            fiber: totalFiber / Double(max(1, servings)),
            sodium: totalSodium / Double(max(1, servings)),
            isCustom: true
        )
        context.insert(foodItem)
        let entry = FoodEntry(foodItem: foodItem, quantity: 100, unit: .grams, meal: .lunch)
        context.insert(entry)
        try? context.save()
        dismiss()
    }

    // MARK: - Helpers

    private func nutritionRow(_ name: String, value: Double, unit: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value < 1 ? String(format: "%.1f\(unit)", value) : "\(Int(value))\(unit)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - Recipe Ingredient Model (in-memory, not persisted)

struct RecipeIngredient: Identifiable {
    var id = UUID()
    var foodName: String
    var grams: Double
    // Scaled nutrition values
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sodium: Double

    init(food: FoodItem, grams: Double) {
        self.id = UUID()
        self.foodName = food.name
        self.grams = grams
        let m = grams / 100.0
        self.calories = food.caloriesPer100g * m
        self.protein  = food.protein * m
        self.carbs    = food.carbohydrates * m
        self.fat      = food.fat * m
        self.fiber    = food.fiber * m
        self.sodium   = food.sodium * m
    }
}

// MARK: - Ingredient Row Editor

struct IngredientRowEditor: View {
    @Binding var ingredient: RecipeIngredient

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.foodName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(Int(ingredient.calories)) kcal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("g", value: Binding(
                    get: { ingredient.grams },
                    set: { ingredient.grams = max(1, $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 55)
                .textFieldStyle(.roundedBorder)
                Text("g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Ingredient Search Sheet

struct IngredientSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    var allFoods: [FoodItem]
    var onAdd: (FoodItem, Double) -> Void

    @State private var searchText: String = ""
    @State private var grams: Double = 100

    private var filtered: [FoodItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(allFoods.prefix(30)) }
        return allFoods.filter { $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false) }
            .prefix(30).map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Grams picker at top
                HStack {
                    Text("Amount:")
                        .font(.subheadline)
                    Spacer()
                    TextField("100", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                    Text("g")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

                Divider()

                List(filtered, id: \.id) { food in
                    Button {
                        onAdd(food, max(1, grams))
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if let brand = food.brand {
                                    Text(brand)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Int(food.caloriesPer100g)) kcal/100g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search foods…")
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    RecipeNutritionCalculatorView()
        .modelContainer(for: [FoodItem.self, FoodEntry.self], inMemory: true)
}
