import SwiftUI
import SwiftData

struct DietInfoView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]

    @State private var selectedDiet: DietType = .none

    private var profile: Profile? { profiles.first }

    private var compatibleFoods: [FoodItem] {
        guard selectedDiet != .none else { return [] }
        return allFoods
            .filter {
                if case .compliant = $0.dietCompliance(for: selectedDiet) { return true }
                return false
            }
            .sorted { $0.nutritionScore > $1.nutritionScore }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    dietPicker
                    if selectedDiet != .none {
                        dietDescriptionCard
                        suggestedFoodsSection
                    } else {
                        emptyStateCard
                    }
                }
                .padding()
            }
            .navigationTitle("Diet Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                selectedDiet = profile?.dietType ?? .none
            }
        }
    }

    private var dietPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BROWSE DIETS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DietType.allCases, id: \.self) { diet in
                        Button {
                            withAnimation { selectedDiet = diet }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: diet.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                Text(diet.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .frame(width: 88, height: 84)
                            .foregroundColor(selectedDiet == diet ? .white : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedDiet == diet ? Color.cyan : Color.gray.opacity(0.15))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dietDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: selectedDiet.icon)
                    .font(.system(size: 22))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDiet.displayName).font(.headline)
                    Text(selectedDiet.tagline).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if profile?.dietType == selectedDiet {
                    Text("YOUR PLAN")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.green.opacity(0.15), in: Capsule())
                }
            }
            Divider()
            Text(longDescription(for: selectedDiet))
                .font(.subheadline)
                .foregroundColor(.primary)
            includesSection
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var includesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INCLUDES").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.green).tracking(1)
            ForEach(includes(for: selectedDiet), id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.primary)
            }
            Text("EXCLUDES").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.red).tracking(1).padding(.top, 4)
            ForEach(excludes(for: selectedDiet), id: \.self) { item in
                Label(item, systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.primary)
            }
        }
    }

    private var suggestedFoodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP-RATED FOODS FOR THIS DIET")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary).tracking(2)
            if compatibleFoods.isEmpty {
                Text("No compatible foods in your local database yet — search and log a few items first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(compatibleFoods, id: \.id) { food in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.subheadline.weight(.semibold))
                                Text("\(Int(food.caloriesPer100g)) kcal/100g · \(Int(food.protein))g protein").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            NutritionGradeBadge(grade: food.nutritionGrade, score: food.nutritionScore)
                        }
                        .padding(10)
                        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle").font(.system(size: 48)).foregroundColor(.cyan)
            Text("Pick a diet above to learn what's in and what's out, plus the top-rated foods that fit it.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Static copy

    private func longDescription(for diet: DietType) -> String {
        switch diet {
        case .none:        return "No restrictions. Eat what works for your goals."
        case .vegetarian:  return "Excludes meat and seafood. Dairy, eggs, and honey are typically OK. Build meals around legumes, whole grains, dairy, eggs, nuts, and a wide range of vegetables and fruits."
        case .vegan:       return "Excludes all animal products: meat, fish, dairy, eggs, honey, and animal-derived ingredients. Focus on legumes, whole grains, nuts, seeds, soy, and fortified plant milks for B12 and calcium."
        case .pescatarian: return "Vegetarian + fish and seafood. A flexible middle ground that brings in lean protein and omega-3s while still cutting out land-animal meat."
        case .keto:        return "Very low carb (typically under 20-50g per day), high fat, moderate protein. Forces the body into ketosis where fat becomes the primary fuel. Avoid grains, sugar, most fruit, and starchy vegetables."
        case .halal:       return "Permitted under Islamic dietary law. Meat must come from halal-certified sources (no pork, no alcohol, slaughter must follow zabiha rules). When in doubt, look for certified halal labeling."
        case .glutenFree:  return "No wheat, barley, rye, or their derivatives. Essential for celiac disease and helpful for gluten sensitivity. Naturally gluten-free foods include rice, quinoa, corn, potatoes, all unprocessed meats and vegetables."
        case .lactoseFree: return "Excludes milk-derived dairy that contains lactose. Hard cheeses (parmesan, aged cheddar) and yogurt may be tolerated by some people due to lower lactose content. Plant milks and lactose-free dairy alternatives work well."
        }
    }

    private func includes(for diet: DietType) -> [String] {
        switch diet {
        case .none:        return ["Anything goes"]
        case .vegetarian:  return ["Vegetables", "Fruits", "Whole grains", "Legumes", "Dairy", "Eggs", "Nuts and seeds"]
        case .vegan:       return ["Vegetables", "Fruits", "Whole grains", "Legumes", "Tofu and tempeh", "Plant milks", "Nuts and seeds"]
        case .pescatarian: return ["All vegetarian foods", "Fish", "Shellfish", "Seafood"]
        case .keto:        return ["Meat and poultry", "Fish and seafood", "Eggs", "Cheese and butter", "Avocado", "Nuts and seeds", "Low-carb vegetables"]
        case .halal:       return ["Halal-certified meat", "Fish and seafood", "Vegetables and fruits", "Grains", "Dairy and eggs"]
        case .glutenFree:  return ["Rice", "Quinoa", "Corn", "Potatoes", "All unprocessed meat and produce", "Gluten-free oats"]
        case .lactoseFree: return ["All meat and produce", "Plant milks (almond, oat, soy)", "Lactose-free dairy", "Hard aged cheeses (often OK)"]
        }
    }

    private func excludes(for diet: DietType) -> [String] {
        switch diet {
        case .none:        return ["Nothing"]
        case .vegetarian:  return ["Meat", "Fish and seafood"]
        case .vegan:       return ["Meat", "Fish and seafood", "Dairy", "Eggs", "Honey"]
        case .pescatarian: return ["Beef, pork, poultry, and other land-animal meat"]
        case .keto:        return ["Bread, pasta, rice", "Sugar and sweets", "Most fruits", "Starchy vegetables", "Beans and lentils"]
        case .halal:       return ["Pork and pork derivatives", "Alcohol", "Non-halal-certified meat"]
        case .glutenFree:  return ["Wheat, barley, rye", "Most breads and pastas", "Beer", "Many sauces and dressings"]
        case .lactoseFree: return ["Milk", "Soft cheeses", "Cream", "Ice cream"]
        }
    }
}
