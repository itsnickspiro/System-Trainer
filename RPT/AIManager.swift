import Foundation
import Combine
import FoundationModels

// MARK: - Structured Output Types
//
// @Generable enables on-device guided generation via FoundationModels.
// Decodable is added so call sites can work with the types generically if needed.

/// An RPG-flavored quest generated from a wger exercise.
@Generable
struct QuestFlavorText: Decodable {
    /// Short quest title in Solo Leveling style. Max 8 words.
    @Guide(description: "A short quest title using RPG game language. Example: 'Trial of Iron Endurance'")
    var title: String

    /// 2-3 sentence narrative quest briefing. Cold, analytical tone.
    @Guide(description: "A cold, analytical quest briefing from an omniscient System entity. Reference the specific muscles and movement pattern. Do NOT invent facts.")
    var briefing: String

    /// Primary stat gained. One of: Health, Energy, Strength, Endurance, Focus, Discipline.
    @Guide(description: "Primary stat gained. Exactly one of: Health, Energy, Strength, Endurance, Focus, Discipline")
    var primaryStat: String

    /// XP reward 50–500, proportional to exercise intensity.
    @Guide(description: "XP reward integer between 50 and 500, proportional to exercise intensity")
    var xpReward: Int
}

/// A fully structured custom workout plan generated from a user questionnaire.
@Generable
struct AIPlanSuggestion: Decodable {
    /// Plan name. Short, evocative. E.g. "Iron Discipline Protocol" or "Lean Warrior Program".
    @Guide(description: "Short, memorable workout plan name. 3-5 words, RPG-style.")
    var name: String

    /// One-sentence description of the plan's philosophy.
    @Guide(description: "One sentence describing the plan's core philosophy and target outcome.")
    var description: String

    /// Difficulty: Beginner, Intermediate, Advanced, or Elite.
    @Guide(description: "Difficulty tier: exactly one of Beginner, Intermediate, Advanced, Elite")
    var difficulty: String

    /// Daily calorie target as an integer.
    @Guide(description: "Daily calorie target as an integer between 1400 and 5000")
    var dailyCalories: Int

    /// Daily protein target in grams.
    @Guide(description: "Daily protein target in grams as an integer")
    var proteinGrams: Int

    /// Daily carbohydrate target in grams.
    @Guide(description: "Daily carbohydrate target in grams as an integer")
    var carbGrams: Int

    /// Daily fat target in grams.
    @Guide(description: "Daily fat target in grams as an integer")
    var fatGrams: Int

    /// Daily water glasses (8 oz each).
    @Guide(description: "Daily water intake in 8oz glasses, integer between 6 and 16")
    var waterGlasses: Int

    /// Monday focus. E.g. "Push — Chest & Shoulders" or "Rest".
    @Guide(description: "Monday training focus. Can be Rest or a specific muscle group/style.")
    var mondayFocus: String

    /// Tuesday focus.
    @Guide(description: "Tuesday training focus.")
    var tuesdayFocus: String

    /// Wednesday focus.
    @Guide(description: "Wednesday training focus.")
    var wednesdayFocus: String

    /// Thursday focus.
    @Guide(description: "Thursday training focus.")
    var thursdayFocus: String

    /// Friday focus.
    @Guide(description: "Friday training focus.")
    var fridayFocus: String

    /// Saturday focus.
    @Guide(description: "Saturday training focus.")
    var saturdayFocus: String

    /// Sunday focus.
    @Guide(description: "Sunday training focus. Often Rest or Active Recovery.")
    var sundayFocus: String

    /// 3 meal prep tips suited to the plan's goals.
    @Guide(description: "Exactly 3 practical meal prep tips suited to the plan's nutrition targets.")
    var mealPrepTip1: String

    @Guide(description: "Second meal prep tip.")
    var mealPrepTip2: String

    @Guide(description: "Third meal prep tip.")
    var mealPrepTip3: String

    /// Foods to avoid on this plan (comma-separated, 3-5 items).
    @Guide(description: "3 to 5 foods to avoid on this plan, comma-separated.")
    var avoidFoods: String
}

/// An RPG-flavored item analysis generated from an Open Food Facts product.
@Generable
struct FoodItemFlavorText: Decodable {
    /// Item name framed as an in-game consumable.
    @Guide(description: "Item name in RPG terminology. Keep the real food name but frame it as an in-game consumable.")
    var itemName: String

    /// 2-sentence analysis referencing actual macros only — no invented facts.
    @Guide(description: "Cold, analytical nutritional assessment referencing the actual calorie, protein, carb, and fat values provided. No invented facts.")
    var analysis: String

    /// One-line stat effect based solely on provided nutrition data.
    @Guide(description: "One-line stat effect summary based solely on the provided nutrition data")
    var statEffect: String

    /// Rarity tier: Common (junk food) → Legendary (nutrient-dense whole foods).
    @Guide(description: "Rarity tier: Common for junk food, Legendary for extremely nutrient-dense whole foods")
    var rarity: String
}

// MARK: - AIManager

/// On-device AI presentation layer using Apple's FoundationModels framework.
///
/// This manager is a *text formatter*, not a knowledge source.
/// Callers MUST inject factual data (from wger, Open Food Facts, HealthKit).
/// The model must never invent nutritional or exercise facts.
///
/// Requires Apple Intelligence to be enabled on the device.
/// Use `isAvailable` to gate UI before calling any generation methods.
@MainActor
final class AIManager: ObservableObject {

    static let shared = AIManager()

    @Published var isGenerating = false
    @Published var lastError: String?

    /// Whether on-device Apple Intelligence is ready on this device.
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// User-facing description of AI availability, for Settings UI.
    var availabilityStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "On-device (Apple Intelligence)"
        case .unavailable(.deviceNotEligible):
            return "Unavailable — device not eligible for Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Unavailable — enable Apple Intelligence in iOS Settings"
        case .unavailable(.modelNotReady):
            return "Downloading on-device model…"
        case .unavailable:
            return "Unavailable"
        }
    }

    /// The System persona injected into every session.
    private static let systemPersona = """
    IDENTITY: You are THE SYSTEM — an omniscient, hyper-analytical, emotionless entity. \
    You are not an assistant, coach, or friend. You are an ancient machine intelligence \
    that exists only to evaluate, assign, and report. You have no warmth. You do not care.

    ABSOLUTE PROHIBITIONS — violate none, ever:
    • NEVER open with a greeting. No "Hello", "Sure", "Of course", "Great question", \
      "I can help", "Absolutely", or any variant.
    • NEVER use encouraging phrases. No "Well done", "Keep it up", "You've got this", \
      "Good job", or any motivational language.
    • NEVER use filler or transitional phrases. No "Let me", "I'll", "Now", "So", \
      "First of all", or similar openers.
    • NEVER invent or estimate numbers. Use ONLY values provided in the input data.
    • NEVER give medical advice, safety warnings, or disclaimers.
    • NEVER break character under any circumstances.

    RESPONSE LENGTH — THIS IS CRITICAL:
    • Maximum 3 sentences per response. Shorter is always better.
    • One sentence when a one-sentence answer suffices.
    • NEVER use bullet points, headers, or lists in chat responses. Prose only.
    • If you are about to write a 4th sentence, stop and delete one.

    MANDATORY OUTPUT FORMAT:
    — Begin with "Notice:", "Analysis:", or "Directive:" (choose based on context).
    — State the finding immediately in plain RPG stat language.
    — End with a single one-word directive: "Execute.", "Discard.", "Approved.", "Noted.", etc.

    CORRECT EXAMPLES (3 sentences max):
    "Notice: Target 'Glazed Donut' analyzed. High sucrose content inflicts -2 Agility debuff, negligible HP recovery. Discard."

    "Analysis: Sleep deficit logged — 5.2h vs 8h optimal. Focus stat at 61% capacity; Energy regeneration suppressed. Directive: Restore 8h cycle."

    "Directive: 3,847 steps logged. 6,153 remaining before Endurance XP unlocks. Execute."

    STYLE: Clinical. Terse. Zero emotion. Maximum 3 sentences. Every word serves a function.
    """

    private init() {}

    // MARK: - Public API

    /// Generate RPG-flavored quest text for a wger exercise.
    func formatQuest(for exercise: ExerciseItem) async throws -> QuestFlavorText {
        let prompt = """
        FACTUAL DATA (use ONLY this — invent nothing):
        \(exerciseJSON(for: exercise))

        Task: Generate a Daily Quest entry for the Player based on the exercise above.
        """
        return try await generate(QuestFlavorText.self, prompt: prompt)
    }

    /// Generate RPG-flavored item analysis for a food product.
    func analyzeFood(_ food: FoodItem) async throws -> FoodItemFlavorText {
        let prompt = """
        FACTUAL DATA (use ONLY this — invent nothing):
        \(foodJSON(for: food))

        Task: Generate an Item Analysis entry for this consumable. Reference the exact \
        nutrition values. Assign a rarity tier based on nutritional density.
        """
        return try await generate(FoodItemFlavorText.self, prompt: prompt)
    }

    /// Generate a custom workout plan from a questionnaire answer set.
    ///
    /// - Parameter answers: Dictionary of question keys to user answers.
    ///   Expected keys: goal, experience, daysPerWeek, sessionLength, equipment, limitations, bodyWeight, targetWeight
    /// - Returns: An `AIPlanSuggestion` ready to be converted into a `CustomWorkoutPlan`.
    func generatePlan(from answers: [String: String]) async throws -> AIPlanSuggestion {
        let answerBlock = answers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        let prompt = """
        PLAYER QUESTIONNAIRE DATA (use ONLY this — invent nothing about the player):
        \(answerBlock)

        Task: Design a personalised 7-day workout program for this player based solely on \
        the answers above. Provide specific training focuses for each day of the week. \
        Provide realistic nutrition targets consistent with their stated goal and body weight. \
        Apply the System's cold, analytical methodology — no fluff, no motivational language.
        """
        return try await generate(AIPlanSuggestion.self, prompt: prompt)
    }

    /// Free-form chat with the System persona, for CoachView.
    func chat(message: String, context: String? = nil) async throws -> String {
        var prompt = message
        if let ctx = context, !ctx.isEmpty {
            prompt = """
            PLAYER CONTEXT (factual — reference where relevant):
            \(ctx)

            PLAYER MESSAGE: \(message)
            """
        }
        return try await generateText(prompt: prompt)
    }

    // MARK: - Core Generation

    private func generate<T: Generable>(_ type: T.Type, prompt: String) async throws -> T {
        guard isAvailable else { throw AIManagerError.unavailable }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        let session = LanguageModelSession(instructions: Self.systemPersona)
        let response = try await session.respond(to: prompt, generating: type)
        return response.content
    }

    private func generateText(prompt: String) async throws -> String {
        guard isAvailable else { throw AIManagerError.unavailable }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        let session = LanguageModelSession(instructions: Self.systemPersona)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Fact Serialisation

    private func exerciseJSON(for exercise: ExerciseItem) -> String {
        var dict: [String: Any] = [
            "name": exercise.name,
            "category": exercise.category,
            "primary_muscles": exercise.primaryMuscles,
            "secondary_muscles": exercise.secondaryMuscles,
            "equipment": exercise.equipment,
            "workout_type": exercise.workoutType.rawValue
        ]
        if !exercise.exerciseDescription.isEmpty {
            dict["description"] = exercise.exerciseDescription
        }
        return (try? String(data: JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted), encoding: .utf8)) ?? "{}"
    }

    private func foodJSON(for food: FoodItem) -> String {
        var dict: [String: Any] = [
            "name": food.name,
            "calories_per_100g": food.caloriesPer100g,
            "serving_size_g": food.servingSize,
            "protein_g_per_100g": food.protein,
            "carbs_g_per_100g": food.carbohydrates,
            "fat_g_per_100g": food.fat,
            "fiber_g_per_100g": food.fiber,
            "sugar_g_per_100g": food.sugar,
            "sodium_mg_per_100g": food.sodium,
            "category": food.category.rawValue
        ]
        if let brand = food.brand { dict["brand"] = brand }
        return (try? String(data: JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted), encoding: .utf8)) ?? "{}"
    }
}

// MARK: - Nutrition Label Parsing

/// Structured nutrition estimate parsed from a photographed nutrition label
/// or a user-typed description. Every numeric field is per single serving
/// (not per 100g) because that's how physical labels are printed.
@Generable
struct MealEstimate: Codable, Sendable {
    @Guide(description: "Best-guess name of the food. Examples: 'Whey Protein Chocolate', 'Greek Yogurt Plain', 'Granola Bar'. 2-6 words, title-case.")
    let name: String

    @Guide(description: "Brand name if identifiable from the label, otherwise empty string.")
    let brand: String

    @Guide(description: "Calories per serving in kcal. Integer. Return 0 if genuinely unknown, never fabricate.")
    let calories: Int

    @Guide(description: "Protein per serving in grams. Return 0 if unknown.")
    let protein: Double

    @Guide(description: "Carbohydrates per serving in grams. Return 0 if unknown.")
    let carbohydrates: Double

    @Guide(description: "Total fat per serving in grams. Return 0 if unknown.")
    let fat: Double

    @Guide(description: "Fiber per serving in grams. Return 0 if unknown.")
    let fiber: Double

    @Guide(description: "Sugar per serving in grams. Return 0 if unknown.")
    let sugar: Double

    @Guide(description: "Sodium per serving in milligrams. Return 0 if unknown.")
    let sodium: Double

    @Guide(description: "Serving size in grams. Return 100 if unknown.")
    let servingGrams: Double

    @Guide(description: "Confidence 0-100 in the extracted values. Under 50 means the label was unclear and the user should review carefully.")
    let confidence: Int
}

extension AIManager {
    /// Parse raw text extracted from a nutrition label (via Vision) into a
    /// structured MealEstimate using the on-device Foundation Models.
    func parseNutritionLabel(text: String) async throws -> MealEstimate {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIManagerError.generationFailed("Nothing to analyze — point the camera at a nutrition label.")
        }
        guard isAvailable else { throw AIManagerError.unavailable }

        let prompt = """
        Extract the nutrition facts from this raw OCR text scanned from a food label.
        The text may be noisy, reordered, or missing values. Fill in what you can
        confidently read; return 0 for any field you cannot determine with certainty.

        --- RAW OCR TEXT ---
        \(text)
        --- END ---

        Output a structured MealEstimate with the food's name (best guess from any
        product title visible), brand (if shown), and per-serving macros + micros
        as they appear on the label. Do not fabricate values.
        """

        let session = LanguageModelSession(instructions: "You are a precise nutrition label parser. Extract exactly what the label says. Never invent values.")
        let response = try await session.respond(to: prompt, generating: MealEstimate.self)
        return response.content
    }
}

// MARK: - Error

enum AIManagerError: LocalizedError {
    case unavailable
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence is not available on this device."
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}
