import Foundation
import SwiftUI

/// Ingredient-aware food grader. Parses raw ingredient text into
/// detected additives, computes a risk score, and returns a verdict
/// the post-scan UI can render.
///
/// The additives database is curated and bundled — no network calls,
/// no external dependencies. Sourced from public food-safety lists
/// (EFSA, NOVA classification, common-knowledge consumer guides).
///
/// NOTE: NOT @MainActor isolated. Pure value-type computation, safe to
/// call from any thread (e.g. from background decoders).
struct IngredientGrader {

    /// The verdict shown to the user after scanning. Combines macro grade,
    /// additive risk, and allergen warnings into one structured result.
    struct Verdict {
        let overallGrade: String          // "A" / "B" / "C" / "D" / "F"
        let overallColor: Color
        let nutritionScore: Int           // 0-100 from existing nutritionGrade logic
        let additiveScore: Int            // 0-100, higher = safer
        let highRiskAdditives: [Additive]
        let moderateRiskAdditives: [Additive]
        let lowRiskAdditives: [Additive]
        let allergens: [String]
        let summary: String               // 1-2 sentence narrative for the verdict screen
        let suggestion: String            // One actionable swap recommendation
    }

    struct Additive: Identifiable, Hashable {
        let id: String                    // E-number or canonical name
        let displayName: String
        let riskLevel: RiskLevel
        let reason: String                // Why it's flagged
    }

    enum RiskLevel: String {
        case low      // Generally recognized as safe
        case moderate // Some studies suggest concerns; consume in moderation
        case high     // Strongly linked to health risks; avoid
    }

    /// Set of high-risk additive IDs — used by row indicators to flag foods
    /// that contain anything in this set without recomputing the full verdict.
    static let highRiskAdditiveIDs: Set<String> = [
        "E102", "E110", "E122", "E124", "E129", "E131", "E150d",
        "E211", "E220", "E249", "E250", "E951", "E952",
        "BHA", "BHT", "PHO", "HFCS",
        "RedDye", "Yellow5", "Aspartame"
    ]

    // MARK: - Public API

    /// Parses raw ingredient text and returns the unique set of detected
    /// additives plus a sorted list of allergens. Case-insensitive substring
    /// match against the bundled markers tables.
    static func parse(ingredientText: String) -> (additives: [Additive], allergens: [String]) {
        guard !ingredientText.isEmpty else { return ([], []) }
        let lower = ingredientText.lowercased()
        var foundIDs: Set<String> = []
        var foundAdditives: [Additive] = []
        var foundAllergens: Set<String> = []

        for additive in additivesDatabase {
            if foundIDs.contains(additive.id) { continue }
            let markers = additiveMarkers[additive.id] ?? []
            for marker in markers {
                if lower.contains(marker) {
                    foundAdditives.append(additive)
                    foundIDs.insert(additive.id)
                    break
                }
            }
        }

        for allergen in commonAllergens {
            for marker in allergen.markers {
                if lower.contains(marker) {
                    foundAllergens.insert(allergen.label)
                    break
                }
            }
        }

        return (foundAdditives, Array(foundAllergens).sorted())
    }

    /// Generate a complete verdict for a FoodItem. Uses the existing
    /// `nutritionScore` from the FoodItem extension, then layers in the
    /// additive risk computed from `ingredientText`.
    static func verdict(for food: FoodItem) -> Verdict {
        let parsed = parse(ingredientText: food.ingredientText)

        let highRisk = parsed.additives.filter { $0.riskLevel == .high }
        let moderateRisk = parsed.additives.filter { $0.riskLevel == .moderate }
        let lowRisk = parsed.additives.filter { $0.riskLevel == .low }

        // Additive score: 100 = perfectly clean, deductions per high/moderate
        var addScore = 100
        addScore -= highRisk.count * 20
        addScore -= moderateRisk.count * 8
        addScore -= lowRisk.count * 2
        addScore = max(0, addScore)

        // Combined score: 60% nutrition, 40% additive purity
        let nutritionScore = food.nutritionScore
        let combined = Int((Double(nutritionScore) * 0.6 + Double(addScore) * 0.4).rounded())

        let grade: String
        let color: Color
        switch combined {
        case 80...:    grade = "A"; color = .green
        case 65..<80:  grade = "B"; color = Color(red: 0.4, green: 0.8, blue: 0.2)
        case 50..<65:  grade = "C"; color = .yellow
        case 35..<50:  grade = "D"; color = .orange
        default:       grade = "F"; color = .red
        }

        let summary = buildSummary(food: food, additives: parsed.additives, score: combined)
        let suggestion = buildSuggestion(food: food, score: combined, highRiskCount: highRisk.count)

        return Verdict(
            overallGrade: grade,
            overallColor: color,
            nutritionScore: nutritionScore,
            additiveScore: addScore,
            highRiskAdditives: highRisk,
            moderateRiskAdditives: moderateRisk,
            lowRiskAdditives: lowRisk,
            allergens: parsed.allergens,
            summary: summary,
            suggestion: suggestion
        )
    }

    private static func buildSummary(food: FoodItem, additives: [Additive], score: Int) -> String {
        let highCount = additives.filter { $0.riskLevel == .high }.count
        let modCount = additives.filter { $0.riskLevel == .moderate }.count
        if highCount > 0 {
            return "Contains \(highCount) high-risk additive\(highCount == 1 ? "" : "s") and \(additives.count) total. The System recommends finding a cleaner alternative."
        } else if modCount >= 2 {
            return "Several moderate-risk additives detected. Acceptable in moderation, not as a daily staple."
        } else if !additives.isEmpty {
            return "Mostly clean ingredient profile. \(additives.count) additive\(additives.count == 1 ? "" : "s") flagged but none high-risk."
        } else if score >= 80 {
            return "Excellent. Whole-food profile with no detected additives. Consume freely."
        } else {
            return "No additives flagged. Macro profile is the main concern here."
        }
    }

    private static func buildSuggestion(food: FoodItem, score: Int, highRiskCount: Int) -> String {
        if highRiskCount > 0 {
            return "Look for the same product without artificial preservatives or colors. Whole-food alternatives in the same category will grade higher."
        }
        if score < 50 {
            return "Reach for higher-protein, lower-sugar options in this category. Your goal stats will thank you."
        }
        if score < 70 {
            return "A solid choice. Pair with protein and fiber to boost the meal's overall grade."
        }
        return "Keep this in your rotation. The System approves."
    }

    // MARK: - Bundled databases

    /// Curated additive risk database. ~50 entries covering the most common
    /// E-numbers, artificial sweeteners, preservatives, and emulsifiers
    /// flagged by mainstream consumer health guides.
    private static let additivesDatabase: [Additive] = [
        // High risk — strongly linked to health concerns
        Additive(id: "E102", displayName: "Tartrazine (Yellow #5)", riskLevel: .high,
                 reason: "Artificial color linked to hyperactivity in children and allergic reactions."),
        Additive(id: "E110", displayName: "Sunset Yellow FCF", riskLevel: .high,
                 reason: "Artificial color associated with hyperactivity and adverse reactions."),
        Additive(id: "E122", displayName: "Carmoisine", riskLevel: .high,
                 reason: "Artificial color linked to behavioral issues and banned in some countries."),
        Additive(id: "E124", displayName: "Ponceau 4R", riskLevel: .high,
                 reason: "Artificial color associated with hyperactivity in children."),
        Additive(id: "E129", displayName: "Allura Red AC", riskLevel: .high,
                 reason: "Artificial red color linked to inflammation in animal studies."),
        Additive(id: "E131", displayName: "Patent Blue V", riskLevel: .high,
                 reason: "Artificial color with documented allergic reactions."),
        Additive(id: "E150d", displayName: "Sulphite Ammonia Caramel", riskLevel: .high,
                 reason: "Caramel coloring containing 4-MEI, a possible carcinogen."),
        Additive(id: "E211", displayName: "Sodium Benzoate", riskLevel: .high,
                 reason: "Preservative that can form benzene with vitamin C; linked to hyperactivity."),
        Additive(id: "E220", displayName: "Sulphur Dioxide", riskLevel: .high,
                 reason: "Preservative that can trigger asthma and other respiratory issues."),
        Additive(id: "E249", displayName: "Potassium Nitrite", riskLevel: .high,
                 reason: "Preservative in cured meats; forms nitrosamines, which are carcinogenic."),
        Additive(id: "E250", displayName: "Sodium Nitrite", riskLevel: .high,
                 reason: "Preservative in processed meats; linked to colorectal cancer when consumed regularly."),
        Additive(id: "E951", displayName: "Aspartame", riskLevel: .high,
                 reason: "Artificial sweetener; WHO IARC classified as 'possibly carcinogenic to humans' in 2023."),
        Additive(id: "E952", displayName: "Cyclamate", riskLevel: .high,
                 reason: "Artificial sweetener banned in the US since 1969 due to bladder cancer concerns in animal studies."),
        Additive(id: "BHA", displayName: "BHA (E320)", riskLevel: .high,
                 reason: "Synthetic antioxidant classified as 'reasonably anticipated to be a human carcinogen' by the US NTP."),
        Additive(id: "BHT", displayName: "BHT (E321)", riskLevel: .high,
                 reason: "Synthetic antioxidant linked to liver and kidney issues in animal studies."),
        Additive(id: "PHO", displayName: "Partially Hydrogenated Oil", riskLevel: .high,
                 reason: "Source of trans fats — strongly linked to heart disease. Banned in many countries."),
        Additive(id: "HFCS", displayName: "High-Fructose Corn Syrup", riskLevel: .high,
                 reason: "Cheap sweetener linked to obesity, fatty liver disease, and type 2 diabetes."),

        // Moderate risk — some concerns, OK in moderation
        Additive(id: "E330", displayName: "Citric Acid", riskLevel: .moderate,
                 reason: "Often manufactured from black mold (Aspergillus niger); generally safe but can trigger reactions in sensitive individuals."),
        Additive(id: "E407", displayName: "Carrageenan", riskLevel: .moderate,
                 reason: "Thickener that may cause inflammation and digestive issues in sensitive people."),
        Additive(id: "E412", displayName: "Guar Gum", riskLevel: .moderate,
                 reason: "Thickener that can cause digestive discomfort in large amounts."),
        Additive(id: "E466", displayName: "Carboxymethyl Cellulose", riskLevel: .moderate,
                 reason: "Emulsifier that may disrupt gut microbiome based on animal studies."),
        Additive(id: "E471", displayName: "Mono- & Diglycerides", riskLevel: .moderate,
                 reason: "Emulsifier that can contain trans fats as a byproduct."),
        Additive(id: "E621", displayName: "MSG (Monosodium Glutamate)", riskLevel: .moderate,
                 reason: "Flavor enhancer; some people report headaches and reactions ('Chinese restaurant syndrome')."),
        Additive(id: "E950", displayName: "Acesulfame K", riskLevel: .moderate,
                 reason: "Artificial sweetener with limited long-term safety data."),
        Additive(id: "E955", displayName: "Sucralose", riskLevel: .moderate,
                 reason: "Artificial sweetener that may impact gut bacteria and insulin response."),
        Additive(id: "E960", displayName: "Steviol Glycosides", riskLevel: .low,
                 reason: "Plant-based sweetener generally recognized as safe."),
        Additive(id: "E965", displayName: "Maltitol", riskLevel: .moderate,
                 reason: "Sugar alcohol that can cause digestive upset and bloating."),
        Additive(id: "E202", displayName: "Potassium Sorbate", riskLevel: .moderate,
                 reason: "Preservative; some evidence of DNA damage in lab studies but considered safe in normal amounts."),
        Additive(id: "E160c", displayName: "Paprika Extract", riskLevel: .low,
                 reason: "Natural color from paprika peppers; generally safe."),
        Additive(id: "E322", displayName: "Lecithin", riskLevel: .low,
                 reason: "Natural emulsifier from soy or sunflower; generally safe."),
        Additive(id: "E300", displayName: "Vitamin C (Ascorbic Acid)", riskLevel: .low,
                 reason: "Used as a preservative and nutrient; safe and beneficial."),
        Additive(id: "E306", displayName: "Vitamin E (Tocopherols)", riskLevel: .low,
                 reason: "Natural antioxidant; safe and beneficial."),
        Additive(id: "E440", displayName: "Pectin", riskLevel: .low,
                 reason: "Natural fiber from fruit; safe and beneficial."),

        // Common name aliases
        Additive(id: "RedDye", displayName: "Red Dye 40", riskLevel: .high,
                 reason: "Same as E129 (Allura Red AC) — see above."),
        Additive(id: "Yellow5", displayName: "Yellow Dye 5", riskLevel: .high,
                 reason: "Same as E102 (Tartrazine) — see above."),
        Additive(id: "Aspartame", displayName: "Aspartame", riskLevel: .high,
                 reason: "WHO IARC classified as possibly carcinogenic to humans in 2023."),
        Additive(id: "Sucralose", displayName: "Sucralose (Splenda)", riskLevel: .moderate,
                 reason: "May affect gut bacteria and insulin sensitivity."),
        Additive(id: "MSG", displayName: "MSG", riskLevel: .moderate,
                 reason: "Flavor enhancer; some report headaches and reactions."),
    ]

    /// Substring markers we look for in the lowercased ingredient text
    /// for each additive ID.
    private static let additiveMarkers: [String: [String]] = [
        "E102":     ["e102", "tartrazine", "yellow 5", "yellow #5"],
        "E110":     ["e110", "sunset yellow", "yellow 6"],
        "E122":     ["e122", "carmoisine", "azorubine"],
        "E124":     ["e124", "ponceau 4r", "ponceau"],
        "E129":     ["e129", "allura red", "red 40", "red dye 40"],
        "E131":     ["e131", "patent blue"],
        "E150d":    ["e150d", "sulphite ammonia caramel", "caramel iv"],
        "E211":     ["e211", "sodium benzoate"],
        "E220":     ["e220", "sulphur dioxide", "sulfur dioxide"],
        "E249":     ["e249", "potassium nitrite"],
        "E250":     ["e250", "sodium nitrite"],
        "E951":     ["e951", "aspartame"],
        "E952":     ["e952", "cyclamate"],
        "BHA":      ["bha", "butylated hydroxyanisole", "e320"],
        "BHT":      ["bht", "butylated hydroxytoluene", "e321"],
        "PHO":      ["partially hydrogenated", "trans fat"],
        "HFCS":     ["high fructose corn syrup", "high-fructose corn syrup", "hfcs", "corn syrup solids"],
        "E330":     ["e330", "citric acid"],
        "E407":     ["e407", "carrageenan"],
        "E412":     ["e412", "guar gum"],
        "E466":     ["e466", "carboxymethyl cellulose", "cellulose gum"],
        "E471":     ["e471", "mono- and diglycerides", "monoglycerides", "diglycerides"],
        "E621":     ["e621", "monosodium glutamate", "msg"],
        "E950":     ["e950", "acesulfame", "ace-k"],
        "E955":     ["e955", "sucralose", "splenda"],
        "E960":     ["e960", "stevia", "steviol glycoside"],
        "E965":     ["e965", "maltitol"],
        "E202":     ["e202", "potassium sorbate"],
        "E160c":    ["e160c", "paprika extract"],
        "E322":     ["e322", "lecithin", "soy lecithin", "sunflower lecithin"],
        "E300":     ["e300", "ascorbic acid", "vitamin c"],
        "E306":     ["e306", "tocopherol", "mixed tocopherols", "vitamin e"],
        "E440":     ["e440", "pectin"],
        "RedDye":   ["red dye 40", "red 40"],
        "Yellow5":  ["yellow dye 5", "yellow 5"],
        "Aspartame":["aspartame"],
        "Sucralose":["sucralose", "splenda"],
        "MSG":      ["msg", "monosodium glutamate"],
    ]

    private struct AllergenEntry {
        let label: String
        let markers: [String]
    }

    private static let commonAllergens: [AllergenEntry] = [
        AllergenEntry(label: "Wheat / Gluten",   markers: ["wheat", "gluten", "barley", "rye", "spelt", "kamut", "flour"]),
        AllergenEntry(label: "Milk / Dairy",     markers: ["milk", "cream", "butter", "cheese", "whey", "casein", "lactose"]),
        AllergenEntry(label: "Egg",              markers: ["egg", "albumin"]),
        AllergenEntry(label: "Peanut",           markers: ["peanut", "groundnut"]),
        AllergenEntry(label: "Tree Nut",         markers: ["almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "macadamia", "brazil nut"]),
        AllergenEntry(label: "Soy",              markers: ["soy", "soya", "soybean", "tofu", "edamame"]),
        AllergenEntry(label: "Fish",             markers: ["fish", "anchovy", "tuna", "salmon", "cod", "tilapia"]),
        AllergenEntry(label: "Shellfish",        markers: ["shrimp", "crab", "lobster", "shellfish", "prawn"]),
        AllergenEntry(label: "Sesame",           markers: ["sesame", "tahini"]),
        AllergenEntry(label: "Sulphites",        markers: ["sulphite", "sulfite", "e220", "e221", "e222"]),
    ]
}
