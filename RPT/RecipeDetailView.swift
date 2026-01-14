import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recipe.title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 12) {
                            Label(recipe.servings, systemImage: "person.2")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Label(recipe.estimatedCookingTime, systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(recipe.difficulty)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(recipe.difficulty == "Easy" ? .green : recipe.difficulty == "Medium" ? .orange : .red)
                                )
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Ingredients Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.green)
                            Text("Ingredients")
                                .font(.title2.bold())
                        }
                        .padding(.horizontal)
                        
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(recipe.ingredientsList.enumerated()), id: \.offset) { index, ingredient in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1).")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.green)
                                        .frame(width: 24, alignment: .trailing)
                                    
                                    Text(ingredient)
                                        .font(.subheadline)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
                        )
                        .padding(.horizontal)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Instructions Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "text.document")
                                .foregroundStyle(.blue)
                            Text("Instructions")
                                .font(.title2.bold())
                        }
                        .padding(.horizontal)
                        
                        Text(recipe.instructions)
                            .font(.body)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
                            )
                            .padding(.horizontal)
                    }
                    
                    // Bottom Spacing
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
}

#Preview {
    RecipeDetailView(recipe: Recipe(
        title: "Healthy Chicken Pasta",
        ingredients: "2 chicken breasts|1 cup pasta|2 tbsp olive oil|1 onion|2 garlic cloves|1 can diced tomatoes|Salt and pepper|Fresh basil",
        servings: "4",
        instructions: "1. Cook pasta according to package directions.\n2. Season chicken with salt and pepper, then cook in olive oil until done.\n3. Sauté onion and garlic until fragrant.\n4. Add tomatoes and simmer.\n5. Combine pasta, chicken, and sauce.\n6. Garnish with fresh basil and serve."
    ))
}
