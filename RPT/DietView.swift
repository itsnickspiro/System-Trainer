import SwiftUI
import SwiftData
import UIKit

struct DietView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var foodEntries: [FoodEntry]
    @State private var selectedDate = Date()
    
    private var profile: Profile {
        profiles.first ?? Profile(name: "Default User")
    }
    
    private var todaysFoodEntries: [FoodEntry] {
        let calendar = Calendar.current
        return foodEntries.filter { entry in
            calendar.isDate(entry.dateConsumed, inSameDayAs: selectedDate)
        }
    }
    
    private var actualConsumedCalories: Int {
        Int(todaysFoodEntries.reduce(0) { $0 + $1.totalCalories })
    }
    
    private var todaysCarbs: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalCarbs }
    }
    
    private var todaysProtein: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalProtein }
    }
    
    private var todaysFat: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalFat }
    }
    
    // Daily goals and tracking
    @State private var dailyCalorieGoal: Int = 2000
    @State private var waterGoal: Int = 8
    
    // Add food sheet
    @State private var showingAddFood = false
    @State private var selectedMealForAdding: MealType = .breakfast
    
    private var waterGlasses: Int {
        profile.waterIntake
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date Selector
                    dateSelectorView
                    
                    // Daily Calorie Summary
                    dailyCalorieSummaryView
                    
                    // Macro Breakdown
                    macroBreakdownView
                    
                    // Meals Section
                    mealsSection
                    
                    // Water Tracking
                    waterTrackingView
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Diary")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddFood) {
                AddFoodView(selectedMeal: $selectedMealForAdding, selectedDate: selectedDate)
            }
        }
    }
    
    // MARK: - Date Selector
    private var dateSelectorView: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text(selectedDate, style: .date)
                .font(.headline.weight(.medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
    
    // MARK: - Daily Calorie Summary
    private var dailyCalorieSummaryView: some View {
        VStack(spacing: 16) {
            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: min(Double(actualConsumedCalories) / Double(dailyCalorieGoal), 1.0))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(dailyCalorieGoal - actualConsumedCalories)")
                        .font(.title.weight(.bold))
                        .foregroundColor(.primary)
                    
                    Text("remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Calorie breakdown
            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    Text("\(dailyCalorieGoal)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.green)
                    Text("Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(actualConsumedCalories)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text("Food")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("0")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
    
    // MARK: - Macro Breakdown
    private var macroBreakdownView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macronutrients")
                .font(.headline.weight(.semibold))
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                macroRow(name: "Carbs", consumed: Int(todaysCarbs), goal: 250, color: .blue)
                macroRow(name: "Fat", consumed: Int(todaysFat), goal: 67, color: .red)
                macroRow(name: "Protein", consumed: Int(todaysProtein), goal: 125, color: .green)
            }
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
    
    private func macroRow(name: String, consumed: Int, goal: Int, color: Color) -> some View {
        HStack {
            Text(name)
                .font(.subheadline.weight(.medium))
                .frame(width: 60, alignment: .leading)
            
            ProgressView(value: Double(consumed) / Double(goal))
                .progressViewStyle(LinearProgressViewStyle(tint: color))
            
            Text("\(consumed)g / \(goal)g")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }
    
    // MARK: - Meals Section
    private var mealsSection: some View {
        VStack(spacing: 12) {
            mealSection(title: "Breakfast", mealType: .breakfast, color: .orange)
            mealSection(title: "Lunch", mealType: .lunch, color: .blue)
            mealSection(title: "Dinner", mealType: .dinner, color: .purple)
            mealSection(title: "Snacks", mealType: .snacks, color: .green)
        }
    }
    
    private func mealSection(title: String, mealType: MealType, color: Color) -> some View {
        let mealEntries = todaysFoodEntries.filter { $0.meal == mealType }
        let calories = Int(mealEntries.reduce(0) { $0 + $1.totalCalories })
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                
                Spacer()
                
                if calories > 0 {
                    Text("\(calories) cal")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            
            if !mealEntries.isEmpty {
                // Show actual foods
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mealEntries.prefix(3), id: \.id) { entry in
                        foodEntryRow(entry: entry)
                    }
                    if mealEntries.count > 3 {
                        Text("+ \(mealEntries.count - 3) more items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Add Food") {
                    selectedMealForAdding = mealType
                    showingAddFood = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            } else {
                Button("Add Food") {
                    selectedMealForAdding = mealType
                    showingAddFood = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.1))
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
    
    private func foodEntryRow(entry: FoodEntry) -> some View {
        HStack {
            Text(entry.foodItem?.name ?? "Unknown")
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(Int(entry.totalCalories)) cal")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Water Tracking
    private var waterTrackingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Water")
                    .font(.headline.weight(.semibold))
                
                Spacer()
                
                Text("\(waterGlasses) / \(waterGoal) glasses")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            HStack {
                ForEach(0..<waterGoal, id: \.self) { index in
                    Button {
                        if index < waterGlasses {
                            // Remove water
                            profile.waterIntake = index
                        } else {
                            // Add water
                            profile.waterIntake = index + 1
                            profile.recordWaterIntake()
                        }
                        try? context.save()
                    } label: {
                        Image(systemName: "drop.fill")
                            .foregroundColor(index < waterGlasses ? .blue : .gray.opacity(0.3))
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
        .onAppear {
            // Update profile nutrition from today's food entries
            profile.updateNutritionFromFoodEntries(todaysFoodEntries)
        }
        .onChange(of: todaysFoodEntries.count) { _, _ in
            // Update nutrition when food entries change
            profile.updateNutritionFromFoodEntries(todaysFoodEntries)
            try? context.save()
        }
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
    
    @StateObject private var foodDatabase = FoodDatabaseService.shared
    
    private var filteredFoods: [FoodItem] {
        if searchText.isEmpty {
            return allFoods.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return allFoods.filter { food in
                food.name.localizedCaseInsensitiveContains(searchText) ||
                food.brand?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    private var filteredMeals: [CustomMeal] {
        if searchText.isEmpty {
            return customMeals.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return customMeals.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    
                    if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
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
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if selectedTab == 0 {
                            // Foods
                            ForEach(filteredFoods, id: \.id) { food in
                                FoodItemRow(food: food) { quantity, unit in
                                    addFoodEntry(food: food, quantity: quantity, unit: unit)
                                }
                            }
                            
                            if filteredFoods.isEmpty && !searchText.isEmpty {
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
                        } else {
                            // Recent Foods
                            let recentFoods = allFoods.filter { $0.lastUsed != nil }
                                .sorted { $0.lastUsed! > $1.lastUsed! }
                                .prefix(10)
                            
                            ForEach(Array(recentFoods), id: \.id) { food in
                                FoodItemRow(food: food) { quantity, unit in
                                    addFoodEntry(food: food, quantity: quantity, unit: unit)
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
        
        Task {
            do {
                let food = try await foodDatabase.searchFoodByBarcode(barcode)
                
                await MainActor.run {
                    isLoadingBarcode = false
                    
                    if let food = food {
                        // Add the food to the database
                        context.insert(food)
                        try? context.save()
                        
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
        try? context.save()
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
        try? context.save()
        dismiss()
    }
}

// MARK: - Food Item Row

struct FoodItemRow: View {
    let food: FoodItem
    let onAdd: (Double, FoodUnit) -> Void
    
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
                        
                        if !food.isCustom {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
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
        try? context.save()
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
        
        // Create a quick add food item
        let foodItem = FoodItem(
            name: foodName,
            caloriesPer100g: caloriesValue,
            servingSize: 1,
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
        try? context.save()
        dismiss()
    }
}

struct FoodDetailsView: View {
    let food: FoodItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(food.name)
                            .font(.largeTitle.weight(.bold))
                        
                        if let brand = food.brand {
                            Text(brand)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Nutrition Facts
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nutrition Facts")
                            .font(.title2.weight(.semibold))
                        
                        VStack(spacing: 8) {
                            nutritionRow("Calories", "\(Int(food.caloriesPerServing))")
                            nutritionRow("Carbohydrates", "\(String(format: "%.1f", food.carbohydrates))g")
                            nutritionRow("Protein", "\(String(format: "%.1f", food.protein))g")
                            nutritionRow("Fat", "\(String(format: "%.1f", food.fat))g")
                            nutritionRow("Fiber", "\(String(format: "%.1f", food.fiber))g")
                            nutritionRow("Sugar", "\(String(format: "%.1f", food.sugar))g")
                            nutritionRow("Sodium", "\(String(format: "%.0f", food.sodium))mg")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    
                    // Additional Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional Information")
                            .font(.headline.weight(.semibold))
                        
                        HStack {
                            Text("Category:")
                            Text(food.category.displayName)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Source:")
                            Text(food.isCustom ? "Custom" : "Database")
                                .foregroundColor(.secondary)
                        }
                        
                        if let barcode = food.barcode {
                            HStack {
                                Text("Barcode:")
                                Text(barcode)
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Food Details")
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
    
    private func nutritionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
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
