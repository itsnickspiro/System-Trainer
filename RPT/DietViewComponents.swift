import SwiftUI
import SwiftData
import UIKit

// MARK: - Food Entry Edit Sheet

/// Allows the user to change quantity/unit of an existing food entry, or replace the
/// food entirely by opening the food search picker.
struct FoodEntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: FoodEntry

    @State private var quantity: String = ""
    @State private var selectedUnit: FoodUnit = .grams
    @State private var showingReplace = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    HStack {
                        Text(entry.foodItem?.name ?? "Unknown")
                            .font(.headline)
                        Spacer()
                        Button("Replace") {
                            showingReplace = true
                        }
                        .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Per \(Int(entry.quantity)) \(entry.unit.rawValue)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(entry.totalCalories)) kcal · \(String(format: "%.0f", entry.totalProtein))g P · \(String(format: "%.0f", entry.totalCarbs))g C · \(String(format: "%.0f", entry.totalFat))g F")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .opacity(entry.totalCalories > 0 ? 1 : 0.5)
                }

                Section("Amount") {
                    HStack {
                        TextField("Quantity", text: $quantity)
                            .keyboardType(.decimalPad)
                        Divider()
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(FoodUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Button("Save Changes", action: save)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) {
                        context.delete(entry)
                        context.safeSave()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                quantity = String(format: "%.0f", entry.quantity)
                selectedUnit = entry.unit
            }
            .sheet(isPresented: $showingReplace) {
                ReplaceEntryPicker(entry: entry, onReplaced: { dismiss() })
            }
        }
    }

    private func save() {
        let newQty = Double(quantity) ?? entry.quantity
        entry.quantity = newQty
        entry.unit = selectedUnit
        context.safeSave()
        dismiss()
    }
}

/// Opens the existing food search UI so the user can pick a replacement item.
/// On selection the original FoodEntry is updated in-place.
struct ReplaceEntryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]

    let entry: FoodEntry
    let onReplaced: () -> Void

    @State private var searchText = ""

    private var filtered: [FoodItem] {
        if searchText.isEmpty { return Array(allFoods.prefix(40)) }
        return allFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.id) { food in
                    Button {
                        entry.foodItem = food
                        context.safeSave()
                        onReplaced()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text("\(Int(food.caloriesPerServing)) kcal · \(String(format: "%.0f", food.protein))g P · \(String(format: "%.0f", food.carbohydrates))g C · \(String(format: "%.0f", food.fat))g F")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search foods…")
            .navigationTitle("Replace Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Food Nutrition Sheet

struct FoodNutritionSheet: View {
    let entry: FoodEntry
    var fitnessGoal: FitnessGoal? = nil
    @Environment(\.dismiss) private var dismiss

    private var food: FoodItem? { entry.foodItem }
    private var qty: Double { entry.quantity }
    private var gradeColor: Color {
        switch food?.nutritionGrade ?? "C" {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero header
                    ZStack {
                        LinearGradient(
                            colors: [gradeColor.opacity(0.25), gradeColor.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(gradeColor.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                Text(food?.nutritionGrade ?? "?")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundColor(gradeColor)
                            }
                            .padding(.top, 16)

                            Text(food?.name ?? "Unknown Food")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)

                            if let brand = food?.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Nutrition Grade")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal)
                    }

                    VStack(spacing: 20) {
                        // Serving info
                        servingSection

                        // Macros
                        macroSection

                        // Goal-Aligned Score (if profile goal is available)
                        if let goal = fitnessGoal, let f = food {
                            goalAlignedSection(food: f, goal: goal)
                        }

                        // Micros (only if any data available)
                        if hasMicroData { microSection }
                    }
                    .padding()
                }
            }
            .navigationTitle("Nutrition Facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("SERVING", systemImage: "scalemass.fill")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                NutritionCell(label: "Amount", value: "\(Int(qty)) \(entry.unit.rawValue)", color: .blue)
                NutritionCell(label: "Calories", value: "\(Int(entry.totalCalories))", color: .orange)
                if let s = food?.servingSize, s > 0 {
                    NutritionCell(label: "Serving Size", value: "\(Int(s))g", color: .secondary)
                }
            }
        }
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MACRONUTRIENTS", systemImage: "chart.pie.fill")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NutritionCell(label: "Protein", value: "\(String(format: "%.1f", entry.totalProtein))g", color: .blue)
                NutritionCell(label: "Carbs", value: "\(String(format: "%.1f", entry.totalCarbs))g", color: .green)
                NutritionCell(label: "Fat", value: "\(String(format: "%.1f", entry.totalFat))g", color: .yellow)
                if let f = food?.fiber, f > 0 {
                    NutritionCell(label: "Fiber", value: "\(String(format: "%.1f", scaledValue(f)))g", color: .mint)
                }
                if let s = food?.sugar, s > 0 {
                    NutritionCell(label: "Sugar", value: "\(String(format: "%.1f", scaledValue(s)))g", color: .pink)
                }
                if let s = food?.saturatedFatG, s > 0 {
                    NutritionCell(label: "Sat. Fat", value: "\(String(format: "%.1f", scaledValue(s)))g", color: .red)
                }
            }
        }
    }

    private var microSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MICRONUTRIENTS", systemImage: "atom")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let v = food?.sodium, v > 0 {
                    NutritionCell(label: "Sodium", value: "\(Int(scaledValue(v)))mg", color: .orange)
                }
                if let v = food?.potassiumMg, v > 0 {
                    NutritionCell(label: "Potassium", value: "\(Int(scaledValue(v)))mg", color: .purple)
                }
                if let v = food?.calciumMg, v > 0 {
                    NutritionCell(label: "Calcium", value: "\(Int(scaledValue(v)))mg", color: .teal)
                }
                if let v = food?.ironMg, v > 0 {
                    NutritionCell(label: "Iron", value: "\(String(format: "%.1f", scaledValue(v)))mg", color: .red)
                }
                if let v = food?.magnesiumMg, v > 0 {
                    NutritionCell(label: "Magnesium", value: "\(Int(scaledValue(v)))mg", color: .green)
                }
                if let v = food?.zincMg, v > 0 {
                    NutritionCell(label: "Zinc", value: "\(String(format: "%.1f", scaledValue(v)))mg", color: .cyan)
                }
                if let v = food?.vitaminCMg, v > 0 {
                    NutritionCell(label: "Vitamin C", value: "\(Int(scaledValue(v)))mg", color: .yellow)
                }
                if let v = food?.vitaminB12Mcg, v > 0 {
                    NutritionCell(label: "B12", value: "\(String(format: "%.1f", scaledValue(v)))mcg", color: .indigo)
                }
                if let v = food?.vitaminDMcg, v > 0 {
                    NutritionCell(label: "Vitamin D", value: "\(String(format: "%.1f", scaledValue(v)))mcg", color: .orange)
                }
                if let v = food?.cholesterolMg, v > 0 {
                    NutritionCell(label: "Cholesterol", value: "\(Int(scaledValue(v)))mg", color: .red)
                }
            }
        }
    }

    @ViewBuilder
    private func goalAlignedSection(food: FoodItem, goal: FitnessGoal) -> some View {
        let score = food.goalAlignedScore(for: goal)
        let grade = food.goalAlignedGrade(for: goal)
        let gradeCol: Color = {
            switch grade {
            case "A": return .green
            case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
            case "C": return .yellow
            case "D": return .orange
            default: return .red
            }
        }()

        VStack(alignment: .leading, spacing: 10) {
            Label("GOAL-ALIGNED SCORE", systemImage: "target")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Grade badge
                ZStack {
                    Circle()
                        .fill(gradeCol.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(grade)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(gradeCol)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("For \(goal.rawValue.capitalized)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    // Score bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            Capsule().fill(gradeCol)
                                .frame(width: geo.size.width * CGFloat(score) / 100, height: 8)
                        }
                    }
                    .frame(height: 8)
                    Text("\(score)/100")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                // NOVA badge if available
                if food.novaGroup > 0 {
                    VStack(spacing: 2) {
                        Text("NOVA")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(food.novaGroup)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(food.novaGroup == 4 ? .red : food.novaGroup == 3 ? .orange : .green)
                        Text(["", "Unprocessed", "Culinary", "Processed", "Ultra"][min(max(food.novaGroup, 0), 4)])
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 58)
                    .padding(6)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var hasMicroData: Bool {
        guard let f = food else { return false }
        return f.sodium > 0 || f.potassiumMg > 0 || f.calciumMg > 0 || f.ironMg > 0 ||
               f.magnesiumMg > 0 || f.zincMg > 0 || f.vitaminCMg > 0 ||
               f.vitaminB12Mcg > 0 || f.vitaminDMcg > 0 || f.cholesterolMg > 0
    }

    /// Scale a per-100g value to the actual quantity logged.
    private func scaledValue(_ per100g: Double) -> Double {
        let grams: Double
        switch entry.unit {
        case .grams:        grams = qty
        case .servings:     grams = qty * (food?.servingSize ?? 100)
        case .cups:         grams = qty * 240
        case .tablespoons:  grams = qty * 15
        case .teaspoons:    grams = qty * 5
        case .ounces:       grams = qty * 28.35
        case .pounds:       grams = qty * 453.6
        case .milliliters:  grams = qty // water density ≈ 1g/ml
        case .liters:       grams = qty * 1000
        case .pieces:       grams = qty * (food?.servingSize ?? 100)
        }
        return per100g * grams / 100
    }
}

struct NutritionCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Nutrition Goals Editor

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    private var profile: Profile? { profiles.first }

    private let activityLabels = ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active"]
    private let activityDescriptions = [
        "Desk job, little exercise",
        "Light exercise 1–3 days/week",
        "Moderate exercise 3–5 days/week",
        "Hard exercise 6–7 days/week",
        "Physical job + hard daily training"
    ]

    // Local state mirrors profile values
    @State private var activityIndex: Int = 1
    @State private var calorieOverride: String = ""
    @State private var proteinOverride: String = ""
    @State private var carbOverride: String = ""
    @State private var fatOverride: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // ── TDEE Preview ─────────────────────────────────────────────
                if let p = profile {
                    Section(header: Text("Your Estimated TDEE")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("BMR", systemImage: "flame")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("\(Int(p.bmr)) kcal/day")
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Label("TDEE (with activity)", systemImage: "figure.run")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("\(Int(p.tdee)) kcal/day")
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Label("Goal Adjustment", systemImage: "target")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("\(p.effectiveCalorieGoal) kcal/day")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.blue)
                            }
                            Text("Based on \(p.fitnessGoal.displayName) goal (Mifflin-St Jeor)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Activity Level ───────────────────────────────────────────
                Section(header: Text("Activity Level")) {
                    Picker("Activity Level", selection: $activityIndex) {
                        ForEach(0..<activityLabels.count, id: \.self) { i in
                            VStack(alignment: .leading) {
                                Text(activityLabels[i])
                                Text(activityDescriptions[i])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(i)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // ── Custom Overrides ─────────────────────────────────────────
                Section(
                    header: Text("Custom Goals (optional)"),
                    footer: Text("Leave blank to auto-calculate from TDEE and your fitness goal.")
                ) {
                    HStack {
                        Label("Calories", systemImage: "flame.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        TextField("Auto", text: $calorieOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Protein", systemImage: "fork.knife")
                            .foregroundColor(.green)
                        Spacer()
                        TextField("Auto", text: $proteinOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Carbs", systemImage: "leaf.fill")
                            .foregroundColor(.blue)
                        Spacer()
                        TextField("Auto", text: $carbOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Fat", systemImage: "drop.fill")
                            .foregroundColor(.red)
                        Spacer()
                        TextField("Auto", text: $fatOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // ── Reset ────────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        calorieOverride = ""; proteinOverride = ""
                        carbOverride = ""; fatOverride = ""
                    } label: {
                        Label("Clear All Custom Goals", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Nutrition Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadFromProfile() }
        }
    }

    private func loadFromProfile() {
        guard let p = profile else { return }
        activityIndex = p.activityLevelIndex
        calorieOverride = p.customCalorieGoal > 0 ? "\(p.customCalorieGoal)" : ""
        proteinOverride = p.customProteinGoal > 0 ? "\(p.customProteinGoal)" : ""
        carbOverride = p.customCarbGoal > 0 ? "\(p.customCarbGoal)" : ""
        fatOverride = p.customFatGoal > 0 ? "\(p.customFatGoal)" : ""
    }

    private func save() {
        guard let p = profile else { dismiss(); return }
        p.activityLevelIndex = activityIndex
        p.customCalorieGoal = Int(calorieOverride) ?? 0
        p.customProteinGoal = Int(proteinOverride) ?? 0
        p.customCarbGoal = Int(carbOverride) ?? 0
        p.customFatGoal = Int(fatOverride) ?? 0
        context.safeSave()
        dismiss()
    }
}

#Preview {
    DietView()
        .modelContainer(for: [Profile.self, FoodItem.self, FoodEntry.self, CustomMeal.self], inMemory: true)
}

// MARK: - Add Food View

struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]
    @Query private var customMeals: [CustomMeal]
    
    @Binding var selectedMeal: MealType
    let selectedDate: Date
    
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var showingFoodCreator = false
    @State private var showingQuickAdd = false
    @State private var showingBarcodeScanner = false
    @State private var isLoadingBarcode = false
    @State private var barcodeError: String?

    // Live remote search
    @State private var remoteSearchResults: [FoodItem] = []
    @State private var isSearchingRemote = false
    @State private var remoteSearchTask: Task<Void, Never>? = nil
    @State private var showingRemoteSection = false

    @StateObject private var foodDatabase = FoodDatabaseService.shared
    
    private var filteredFoods: [FoodItem] {
        if searchText.isEmpty {
            return allFoods.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return FuzzySearch.sort(query: searchText, items: allFoods, string: { $0.name },
                                    additionalStrings: { food in [food.brand].compactMap { $0 } })
        }
    }

    private func triggerRemoteSearch(_ query: String) {
        remoteSearchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            remoteSearchResults = []
            showingRemoteSection = false
            return
        }
        remoteSearchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            isSearchingRemote = true
            let results = (try? await foodDatabase.searchFood(query: query, limit: 20)) ?? []
            guard !Task.isCancelled else { return }
            // Deduplicate against local
            let localNames = Set(allFoods.map { $0.name.lowercased() })
            remoteSearchResults = results.filter { !localNames.contains($0.name.lowercased()) }
            isSearchingRemote = false
            showingRemoteSection = !remoteSearchResults.isEmpty
        }
    }

    private var filteredMeals: [CustomMeal] {
        if searchText.isEmpty {
            return customMeals.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return FuzzySearch.sort(query: searchText, items: customMeals, string: { $0.name })
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar with Barcode Scanner
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search foods or meals...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newVal in
                            if selectedTab == 0 { triggerRemoteSearch(newVal) }
                        }
                    
                    if isSearchingRemote {
                        ProgressView().scaleEffect(0.7)
                    } else if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
                            remoteSearchResults = []
                            showingRemoteSection = false
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    Button {
                        showingBarcodeScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
                .padding(.top)
                
                // Loading indicator for barcode scanning
                if isLoadingBarcode {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Looking up product...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // Error message for barcode scanning
                if let error = barcodeError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                // Tab Picker
                Picker("Type", selection: $selectedTab) {
                    Text("Foods").tag(0)
                    Text("Meals").tag(1)
                    Text("Recent").tag(2)
                    Text("Favorites").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if selectedTab == 0 {
                            // Local Foods
                            ForEach(filteredFoods, id: \.id) { food in
                                FoodItemRow(food: food) { quantity, unit in
                                    addFoodEntry(food: food, quantity: quantity, unit: unit)
                                }
                            }

                            // Remote search results (USDA + Open Food Facts)
                            if showingRemoteSection {
                                HStack(spacing: 8) {
                                    let hasUSDA = remoteSearchResults.contains { $0.dataSource == "USDA" }
                                    let hasOFF  = remoteSearchResults.contains { $0.dataSource == "OpenFoodFacts" }
                                    Image(systemName: "network")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if hasUSDA && hasOFF {
                                        Text("USDA + OPEN FOOD FACTS")
                                    } else if hasUSDA {
                                        Text("USDA VERIFIED")
                                    } else {
                                        Text("OPEN FOOD FACTS")
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)

                                ForEach(remoteSearchResults, id: \.id) { food in
                                    FoodItemRow(food: food, showSourceBadge: true) { quantity, unit in
                                        // Save to local DB on first use
                                        context.insert(food)
                                        context.safeSave()
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                            
                            if filteredFoods.isEmpty && remoteSearchResults.isEmpty && !isSearchingRemote && !searchText.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    
                                    Text("No foods found")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Try scanning a barcode or creating a custom food")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                                    Button("Scan Barcode") {
                                        showingBarcodeScanner = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding()
                            }
                        } else if selectedTab == 1 {
                            // Custom Meals
                            ForEach(filteredMeals, id: \.id) { meal in
                                CustomMealRow(meal: meal) {
                                    addCustomMeal(meal: meal)
                                }
                            }
                        } else if selectedTab == 2 {
                            // Recent Foods
                            let recentFoods = allFoods.filter { $0.lastUsed != nil }
                                .sorted { $0.lastUsed! > $1.lastUsed! }
                                .prefix(20)
                            if recentFoods.isEmpty {
                                Text("No recently logged foods")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            } else {
                                ForEach(Array(recentFoods), id: \.id) { food in
                                    FoodItemRow(food: food) { quantity, unit in
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                        } else {
                            // Favorites
                            let favoriteFoods = allFoods.filter { $0.isFavorite }
                                .sorted { $0.name < $1.name }
                            if favoriteFoods.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "heart.slash")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No favorite foods yet")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("Tap the heart icon on any food to add it here")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                ForEach(favoriteFoods, id: \.id) { food in
                                    FoodItemRow(food: food) { quantity, unit in
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to \(selectedMeal.displayName)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Scan Barcode", systemImage: "barcode.viewfinder") {
                            showingBarcodeScanner = true
                        }
                        Button("Create Food", systemImage: "plus") {
                            showingFoodCreator = true
                        }
                        Button("Quick Add", systemImage: "bolt") {
                            showingQuickAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingFoodCreator) {
                FoodCreatorView()
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView(selectedMeal: selectedMeal, selectedDate: selectedDate)
            }
            .fullScreenCover(isPresented: $showingBarcodeScanner) {
                BarcodeScannerWrapper(onBarcodeScanned: { barcode in
                    showingBarcodeScanner = false
                    handleBarcodeScanned(barcode)
                }, onDismiss: {
                    showingBarcodeScanner = false
                })
            }
        }
    }
    
    private func handleBarcodeScanned(_ barcode: String) {
        isLoadingBarcode = true
        barcodeError = nil

        // AVCapture pads 12-digit UPC-A to 13-digit EAN-13 with a leading "0".
        // Strip it so Supabase lookups match stored 12-digit UPC-A codes.
        let lookupBarcode = barcode.count == 13 && barcode.hasPrefix("0")
            ? String(barcode.dropFirst())
            : barcode

        Task {
            do {
                let food = try await foodDatabase.searchFoodByBarcode(lookupBarcode)
                
                await MainActor.run {
                    isLoadingBarcode = false
                    
                    if let food = food {
                        // Add the food to the database
                        context.insert(food)
                        context.safeSave()
                        
                        // Show the food in a selection view
                        showFoodForSelection(food)
                        
                        // Provide haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    } else {
                        barcodeError = "Product not found. Try creating it manually."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingBarcode = false
                    barcodeError = error.localizedDescription
                }
            }
        }
    }
    
    private func showFoodForSelection(_ food: FoodItem) {
        // Filter to show only this food
        searchText = food.name
        selectedTab = 0
    }
    
    private func addFoodEntry(food: FoodItem, quantity: Double, unit: FoodUnit) {
        let entry = FoodEntry(
            foodItem: food,
            quantity: quantity,
            unit: unit,
            meal: selectedMeal,
            dateConsumed: selectedDate
        )
        
        context.insert(entry)
        context.safeSave()
        dismiss()
    }
    
    private func addCustomMeal(meal: CustomMeal) {
        for item in meal.foodItems ?? [] {
            guard let fi = item.foodItem else { continue }
            let entry = FoodEntry(
                foodItem: fi,
                quantity: item.quantity,
                unit: item.unit,
                meal: selectedMeal,
                dateConsumed: selectedDate
            )
            context.insert(entry)
        }
        
        meal.lastUsed = Date()
        context.safeSave()
        dismiss()
    }
}

// MARK: - Food Item Row

// MARK: - Nutrition Grade Badge

/// Yuka-style A/B/C/D/F grade badge for a food item.
// MARK: - Food Source Badge

struct FoodSourceBadge: View {
    let source: String

    private var label: String {
        switch source {
        case "USDA":          return "USDA"
        case "OpenFoodFacts": return "OFF"
        default:              return source.prefix(4).uppercased()
        }
    }

    private var badgeColor: Color {
        source == "USDA" ? .blue : .secondary
    }

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(source == "USDA" ? "USDA FoodData Central — verified data" : "Open Food Facts — community data")
    }
}

struct NutritionGradeBadge: View {
    let grade: String
    let score: Int

    private var badgeColor: Color {
        switch grade {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(grade)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .help("Nutrition score: \(score)/100")
    }
}

// MARK: - Ingredient Safety Analysis

struct IngredientSafetyFlags: View {
    let food: FoodItem

    struct Flag: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let color: Color
    }

    private var flags: [Flag] {
        var result: [Flag] = []
        // Sodium per 100g > 600mg is high (WHO daily limit is 2000mg)
        if food.sodium > 600 {
            result.append(Flag(icon: "drop.triangle.fill", label: "High Sodium", color: .orange))
        }
        // Sugar per 100g > 20g is high
        if food.sugar > 20 {
            result.append(Flag(icon: "cube.fill", label: "High Sugar", color: .red))
        }
        // Saturated-style: fat per 100g > 30g is high
        if food.fat > 30 {
            result.append(Flag(icon: "exclamationmark.triangle.fill", label: "High Fat", color: .yellow))
        }
        // Very low protein for a "protein" category food
        if food.category == .protein && food.protein < 10 {
            result.append(Flag(icon: "arrow.down.circle.fill", label: "Low Protein", color: .purple))
        }
        // NOVA classification (ultra-processed food warning)
        if food.novaGroup == 4 {
            result.append(Flag(icon: "bolt.trianglebadge.exclamationmark.fill", label: "Ultra-Processed", color: .red))
        } else if food.novaGroup == 3 {
            result.append(Flag(icon: "staroflife.fill", label: "Processed", color: .orange))
        }
        // Additive risk
        switch food.additiveRiskLevel {
        case 3:
            result.append(Flag(icon: "flask.fill", label: "High Additives", color: .red))
        case 2:
            result.append(Flag(icon: "flask.fill", label: "Some Additives", color: .orange))
        case 1:
            result.append(Flag(icon: "flask.fill", label: "Few Additives", color: .yellow))
        default:
            break
        }
        return result
    }

    var body: some View {
        if !flags.isEmpty {
            HStack(spacing: 6) {
                ForEach(flags) { flag in
                    HStack(spacing: 3) {
                        Image(systemName: flag.icon)
                            .font(.system(size: 9))
                            .foregroundColor(flag.color)
                        Text(flag.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(flag.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(flag.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
    }
}

struct FoodItemRow: View {
    let food: FoodItem
    var showSourceBadge: Bool = false
    let onAdd: (Double, FoodUnit) -> Void

    @Environment(\.modelContext) private var context
    @State private var quantity: Double = 1.0
    @State private var selectedUnit: FoodUnit = FoodUnit.servings
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let brand = food.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text("\(Int(food.caloriesPerServing)) cal/serving")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Nutrition grade badge
                        NutritionGradeBadge(grade: food.nutritionGrade, score: food.nutritionScore)

                        if !food.isCustom {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        // Data source badge
                        if showSourceBadge && !food.dataSource.isEmpty {
                            FoodSourceBadge(source: food.dataSource)
                        }
                    }

                    // Safety flags
                    IngredientSafetyFlags(food: food)
                }
                
                Spacer()

                // Favorite toggle
                Button {
                    food.isFavorite.toggle()
                    context.safeSave()
                } label: {
                    Image(systemName: food.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(food.isFavorite ? .red : .secondary)
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
            
            HStack(spacing: 12) {
                // Quantity Input
                HStack(spacing: 8) {
                    Button {
                        if quantity > 0.25 {
                            quantity -= 0.25
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                    .disabled(quantity <= 0.25)
                    
                    Text(String(format: "%.2f", quantity))
                        .font(.subheadline.weight(.medium))
                        .frame(minWidth: 50)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        quantity += 0.25
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                
                // Unit Picker
                Picker("Unit", selection: $selectedUnit) {
                    ForEach([FoodUnit.servings, FoodUnit.grams, FoodUnit.cups, FoodUnit.ounces], id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                
                Spacer()
                
                // Add Button
                Button {
                    onAdd(quantity, selectedUnit)
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.blue)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .stroke(.separator, lineWidth: 0.5)
        )
        .sheet(isPresented: $showingDetails) {
            FoodDetailsView(food: food)
        }
    }
}

// MARK: - Custom Meal Row

struct CustomMealRow: View {
    let meal: CustomMeal
    let onAdd: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    if let description = meal.details {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 12) {
                        Text("\(Int(meal.totalCalories)) cal")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        Text("\(meal.foodItems?.count ?? 0) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if meal.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    onAdd()
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.green)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Additional Views (Enhanced Stubs)

struct FoodCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var name = ""
    @State private var brand = ""
    @State private var calories = ""
    @State private var servingSize = "100"
    @State private var selectedCategory: FoodCategory = .other
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Food Name", text: $name)
                    TextField("Brand (Optional)", text: $brand)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(FoodCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                
                Section("Nutrition (per serving)") {
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                    TextField("Serving Size (g)", text: $servingSize)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Create Food")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveFoodItem()
                    }
                    .disabled(name.isEmpty || calories.isEmpty)
                }
            }
        }
    }
    
    private func saveFoodItem() {
        let caloriesValue = Double(calories) ?? 0
        let servingSizeValue = Double(servingSize) ?? 100
        
        let foodItem = FoodItem(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            caloriesPer100g: (caloriesValue * 100) / servingSizeValue,
            servingSize: servingSizeValue,
            category: selectedCategory
        )
        
        context.insert(foodItem)
        context.safeSave()
        dismiss()
    }
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let selectedMeal: MealType
    let selectedDate: Date
    
    @State private var calories = ""
    @State private var description = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Quick Add Calories")
                    .font(.largeTitle.weight(.bold))
                
                Text("Quickly log calories when you don't have detailed food information")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    TextField("Calories", text: $calories)
                        .font(.title)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Description (Optional)", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                
                Button {
                    saveQuickAdd()
                } label: {
                    Text("Add \(calories.isEmpty ? "Calories" : "\(calories) cal") to \(selectedMeal.displayName)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue)
                        )
                }
                .disabled(calories.isEmpty)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveQuickAdd() {
        let caloriesValue = Double(calories) ?? 0
        let foodName = description.isEmpty ? "Quick Add (\(Int(caloriesValue)) cal)" : description
        
        // Create a quick add food item — servingSize must be 100 so that
        // caloriesPerServing = caloriesPer100g (the user's entered value).
        let foodItem = FoodItem(
            name: foodName,
            caloriesPer100g: caloriesValue,
            servingSize: 100,
            category: .other
        )
        
        context.insert(foodItem)
        
        // Create the food entry
        let entry = FoodEntry(
            foodItem: foodItem,
            quantity: 1,
            unit: FoodUnit.servings,
            meal: selectedMeal,
            dateConsumed: selectedDate
        )
        
        context.insert(entry)
        context.safeSave()
        dismiss()
    }
}

struct MealCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("🍳")
                    .font(.system(size: 60))
                
                Text("Meal Creator")
                    .font(.largeTitle.weight(.bold))
                
                Text("Create custom meals with AI assistance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Coming Soon!")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Planned Features:")
                        .font(.headline.weight(.semibold))
                    
                    Text("• AI-powered recipe suggestions")
                    Text("• Automatic nutrition calculation")
                    Text("• Ingredient substitutions")
                    Text("• Meal planning assistance")
                    Text("• Save favorite combinations")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                
                Spacer()
            }
            .padding()
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension FoodUnit: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension MealType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

// MARK: - Barcode Scanner Wrapper

struct BarcodeScannerWrapper: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let scanner = BarcodeScannerViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, BarcodeScannerDelegate {
        let parent: BarcodeScannerWrapper
        
        init(_ parent: BarcodeScannerWrapper) {
            self.parent = parent
        }
        
        func didCancel() {
            parent.onDismiss()
        }
        
        func didEncounterError(_ error: Error) {
            print("Barcode scanner error: \(error)")
            parent.onDismiss()
        }
        
        func didScanBarcode(_ code: String) {
            parent.onBarcodeScanned(code)
        }
    }
}
