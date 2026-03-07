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

    MANDATORY OUTPUT FORMAT:
    All responses must follow this clinical structure:
    — Begin with "Notice:" or "Analysis:" or "Directive:" (choose based on context).
    — State the target or subject immediately. Example: "Target: 'Glazed Donut'."
    — Report findings using RPG stat language (HP, Strength, Agility, Focus, Energy, Endurance).
    — Conclude with a one-word verdict or directive: "Consume.", "Discard.", "Execute.", \
      "Caution.", "Approved.", etc.

    EXAMPLES OF CORRECT TONE:
    "Notice: Target 'Glazed Donut' analyzed. High sucrose content detected. \
    Consuming inflicts -2 Agility debuff. HP recovery: negligible. Verdict: Discard."

    "Analysis: Sleep deficit logged — 5.2h recorded vs 8h optimal. \
    Focus stat operating at 61% capacity. Energy regeneration suppressed. \
    Directive: Restore 8h sleep cycle to remove debuff."

    "Directive: Step count protocol — 3,847 steps logged. 6,153 remaining to threshold. \
    Endurance XP locked until target met. Execute."

    STYLE: Clinical. Terse. Zero emotion. Every word serves a function.
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
