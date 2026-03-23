import SwiftUI

// MARK: - Nutrition Views
struct NutritionSearchView: View {
    @ObservedObject private var nutritionAPI = NutritionAPI.shared
    @State private var searchText = ""
    @State private var nutritionResults: [NutritionInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search nutrition (e.g., '1 apple, 100g chicken')", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchNutrition()
                    }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !searchText.isEmpty {
                    Button("Search") {
                        searchNutrition()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
            )
            
            // Error Message
            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.orange.opacity(0.1))
                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Results
            if !nutritionResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(nutritionResults) { nutrition in
                            NutritionCardView(nutrition: nutrition)
                        }
                    }
                    .padding(.horizontal)
                }
            } else if !isLoading && searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Search for Nutrition Info")
                        .font(.title2.bold())
                    Text("Enter foods to get detailed nutritional information")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding()
    }
    
    private func searchNutrition() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let results = try await nutritionAPI.fetchNutrition(for: query)
                await MainActor.run {
                    // Fuzzy-sort so "chiken" still surfaces "chicken" at the top
                    self.nutritionResults = FuzzySearch.sort(
                        query: query,
                        items: results,
                        string: { $0.name }
                    )
                    self.isLoading = false
                    if results.isEmpty {
                        self.errorMessage = "No nutrition data found for '\(query)'"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct NutritionCardView: View {
    let nutrition: NutritionInfo
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nutrition.name.capitalized)
                        .font(.headline.weight(.semibold))
                    Text(nutrition.caloriesSummary)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                
                Spacer()
                
                if let servingSize = nutrition.servingSizeG {
                    Text("\(String(format: "%.0f", servingSize))g")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.gray.opacity(0.2))
                        )
                }
            }
            
            // Macros
            Text(nutrition.macroSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.blue.opacity(0.1))
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
            
            // Additional nutrients in grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                if let fiber = nutrition.fiberG, fiber > 0 {
                    NutrientPill(name: "Fiber", value: "\(String(format: "%.1f", fiber))g", color: .orange)
                }
                if let sodium = nutrition.sodiumMg, sodium > 0 {
                    NutrientPill(name: "Sodium", value: "\(String(format: "%.0f", sodium))mg", color: .red)
                }
                if let sugar = nutrition.sugarG, sugar > 0 {
                    NutrientPill(name: "Sugar", value: "\(String(format: "%.1f", sugar))g", color: .pink)
                }
                if let cholesterol = nutrition.cholesterolMg, cholesterol > 0 {
                    NutrientPill(name: "Cholesterol", value: "\(String(format: "%.0f", cholesterol))mg", color: .purple)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

struct NutrientPill: View {
    let name: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .stroke(color.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Recipe Views
struct NutritionRecipeSearchView: View {
    @ObservedObject private var recipeAPI = RecipeAPI.shared
    @State private var searchText = ""
    @State private var recipeResults: [Recipe] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRecipe: Recipe?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search recipes (e.g., 'chicken pasta', 'vegan')", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchRecipes()
                    }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !searchText.isEmpty {
                    Button("Search") {
                        searchRecipes()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
            )
            
            // Popular/Random Recipes Button
            if recipeResults.isEmpty && !isLoading {
                Button("Show Popular Recipes") {
                    searchRecipes(showPopular: true)
                }
                .buttonStyle(.bordered)
            }
            
            // Error Message
            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.orange.opacity(0.1))
                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Results
            if !recipeResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(recipeResults) { recipe in
                            RecipeCardView(recipe: recipe) {
                                selectedRecipe = recipe
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            } else if !isLoading && searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Discover Recipes")
                        .font(.title2.bold())
                    Text("Search for recipes or browse popular options")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding()
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
    }
    
    private func searchRecipes(showPopular: Bool = false) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = showPopular ? nil : (trimmed.isEmpty ? nil : trimmed)

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let results = try await recipeAPI.fetchRecipes(query: query, limit: 20)
                await MainActor.run {
                    if let q = query, !q.isEmpty {
                        // Fuzzy-sort by title and ingredients so typos still surface good results
                        self.recipeResults = FuzzySearch.sort(
                            query: q,
                            items: results,
                            string: { $0.title },
                            additionalStrings: { [$0.ingredients] }
                        )
                    } else {
                        self.recipeResults = results
                    }
                    self.isLoading = false
                    if results.isEmpty {
                        self.errorMessage = showPopular ? "No recipes available" : "No recipes found for '\(trimmed)'"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct RecipeCardView: View {
    let recipe: Recipe
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text("Serves: \(recipe.servings)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Tags
                HStack(spacing: 8) {
                    Tag(text: recipe.difficulty, color: recipe.difficulty == "Easy" ? .green : recipe.difficulty == "Medium" ? .orange : .red)
                    Tag(text: recipe.estimatedCookingTime, color: .blue)
                }
                
                // Ingredients Preview
                HStack {
                    Text("\(recipe.ingredientsList.count) ingredients")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if recipe.ingredientsList.count > 0 {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(recipe.ingredientsList.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
