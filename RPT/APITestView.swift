import SwiftUI

struct APITestView: View {
    @State private var apiNinjaStatus = "Not tested"
    @State private var openAIStatus = "Not tested"
    @State private var nutritionStatus = "Not tested"
    @State private var recipeStatus = "Not tested"
    @State private var isTestingNinja = false
    @State private var isTestingOpenAI = false
    @State private var isTestingNutrition = false
    @State private var isTestingRecipe = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("API Key Status")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 16) {
                    // API-Ninja Exercises Test
                    HStack {
                        VStack(alignment: .leading) {
                            Text("API-Ninja Exercises")
                                .fontWeight(.medium)
                            Text(apiNinjaStatus)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Test") {
                            testAPINinja()
                        }
                        .disabled(isTestingNinja)
                        .buttonStyle(.borderedProminent)
                        
                        if isTestingNinja {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Nutrition API Test
                    HStack {
                        VStack(alignment: .leading) {
                            Text("API-Ninja Nutrition")
                                .fontWeight(.medium)
                            Text(nutritionStatus)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Test") {
                            testNutrition()
                        }
                        .disabled(isTestingNutrition)
                        .buttonStyle(.borderedProminent)
                        
                        if isTestingNutrition {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Recipe API Test
                    HStack {
                        VStack(alignment: .leading) {
                            Text("API-Ninja Recipes")
                                .fontWeight(.medium)
                            Text(recipeStatus)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Test") {
                            testRecipe()
                        }
                        .disabled(isTestingRecipe)
                        .buttonStyle(.borderedProminent)
                        
                        if isTestingRecipe {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // OpenAI Test
                    HStack {
                        VStack(alignment: .leading) {
                            Text("OpenAI/ChatGPT")
                                .fontWeight(.medium)
                            Text(openAIStatus)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Test") {
                            testOpenAI()
                        }
                        .disabled(isTestingOpenAI)
                        .buttonStyle(.borderedProminent)
                        
                        if isTestingOpenAI {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("API Key Configuration")
                        .font(.headline)
                    Text("Keys are loaded from Info.plist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text("API_NINJAS_KEY:")
                        Text(hasAPINinjaKey ? "✅ Present" : "❌ Missing")
                            .foregroundStyle(hasAPINinjaKey ? .green : .red)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("AIAPIKey:")
                        Text(hasOpenAIKey ? "✅ Present" : "❌ Missing")
                            .foregroundStyle(hasOpenAIKey ? .green : .red)
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .navigationTitle("API Tests")
        }
    }
    
    private var hasAPINinjaKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "API_NINJAS_KEY") as? String else { return false }
        return !key.isEmpty
    }
    
    private var hasOpenAIKey: Bool {
        return !Secrets.aiAPIKey.isEmpty
    }
    
    private func testAPINinja() {
        isTestingNinja = true
        apiNinjaStatus = "Testing..."
        
        Task {
            do {
                let exercises = try await ExercisesAPI.shared.fetchExercises(muscle: "biceps", limit: 1)
                await MainActor.run {
                    if !exercises.isEmpty {
                        apiNinjaStatus = "✅ Success - Found \(exercises.count) exercise(s)"
                    } else {
                        apiNinjaStatus = "⚠️ No results returned"
                    }
                    isTestingNinja = false
                }
            } catch ExercisesAPI.APIError.missingAPIKey {
                await MainActor.run {
                    apiNinjaStatus = "❌ Missing API Key"
                    isTestingNinja = false
                }
            } catch ExercisesAPI.APIError.http(let code) {
                await MainActor.run {
                    apiNinjaStatus = "❌ HTTP Error: \(code)"
                    isTestingNinja = false
                }
            } catch {
                await MainActor.run {
                    apiNinjaStatus = "❌ Error: \(error.localizedDescription)"
                    isTestingNinja = false
                }
            }
        }
    }
    
    private func testOpenAI() {
        isTestingOpenAI = true
        openAIStatus = "Testing..."
        
        Task {
            do {
                let testMessages = [
                    AIClient.ChatMessage(role: "user", content: "Say 'API test successful' if you can read this.")
                ]
                
                let response = try await AIClient.send(
                    messages: testMessages,
                    model: "gpt-3.5-turbo",
                    endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!
                )
                
                await MainActor.run {
                    if let message = response.choices.first?.message.content, !message.isEmpty {
                        openAIStatus = "✅ Success - Got response"
                    } else {
                        openAIStatus = "⚠️ Empty response"
                    }
                    isTestingOpenAI = false
                }
            } catch {
                await MainActor.run {
                    openAIStatus = "❌ Error: \(error.localizedDescription)"
                    isTestingOpenAI = false
                }
            }
        }
    }
    
    private func testNutrition() {
        isTestingNutrition = true
        nutritionStatus = "Testing..."
        
        Task {
            do {
                let nutrition = try await NutritionAPI.shared.fetchNutrition(for: "1 apple")
                await MainActor.run {
                    if !nutrition.isEmpty {
                        nutritionStatus = "✅ Success - Found \(nutrition.count) item(s)"
                    } else {
                        nutritionStatus = "⚠️ No results returned"
                    }
                    isTestingNutrition = false
                }
            } catch {
                await MainActor.run {
                    nutritionStatus = "❌ Error: \(error.localizedDescription)"
                    isTestingNutrition = false
                }
            }
        }
    }
    
    private func testRecipe() {
        isTestingRecipe = true
        recipeStatus = "Testing..."
        
        Task {
            do {
                let recipes = try await RecipeAPI.shared.fetchRecipes(query: "pasta", limit: 1)
                await MainActor.run {
                    if !recipes.isEmpty {
                        recipeStatus = "✅ Success - Found \(recipes.count) recipe(s)"
                    } else {
                        recipeStatus = "⚠️ No results returned"
                    }
                    isTestingRecipe = false
                }
            } catch {
                await MainActor.run {
                    recipeStatus = "❌ Error: \(error.localizedDescription)"
                    isTestingRecipe = false
                }
            }
        }
    }
}

#Preview {
    APITestView()
}
