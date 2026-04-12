import Foundation

// MARK: - Activity Intensity

/// How hard the activity is — drives XP-per-minute calculation.
enum ActivityIntensity: String, CaseIterable, Codable {
    case easy, moderate, hard

    var xpPerMinute: Int {
        switch self {
        case .easy: return 1
        case .moderate: return 2
        case .hard: return 3
        }
    }

    var displayName: String { rawValue.capitalized }
}

// MARK: - Mapped Workout Type

/// The workout category an activity maps to.
enum MappedWorkoutType: String, Codable {
    case cardio, strength, flexibility, mixed

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .cardio: return "heart.fill"
        case .strength: return "dumbbell.fill"
        case .flexibility: return "figure.flexibility"
        case .mixed: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Activity Mapping

/// The result of mapping a free-text activity description to a workout category.
struct ActivityMapping {
    let workoutType: MappedWorkoutType
    let suggestedIntensity: ActivityIntensity
    let label: String // Human-readable name shown in the UI
}

// MARK: - Activity Mapper

/// Static utility that maps activity descriptions to workout categories and calculates XP.
struct ActivityMapper {

    // Each rule is a tuple: (keywords, workoutType, intensity, label).
    // First match wins, so more specific keywords should come first.
    private static let rules: [([String], MappedWorkoutType, ActivityIntensity, String)] = [
        // Cardio — easy
        (["walk", "dog", "stroll", "hike"],           .cardio,      .easy,     "Walking"),
        (["dance", "dancing"],                         .cardio,      .easy,     "Dancing"),

        // Cardio — moderate
        (["run", "jog", "sprint"],                     .cardio,      .moderate, "Running"),
        (["bike", "cycle", "cycling"],                 .cardio,      .moderate, "Cycling"),
        (["swim", "swimming", "pool"],                 .cardio,      .moderate, "Swimming"),
        (["sports", "basketball", "soccer",
          "tennis", "football"],                        .cardio,      .moderate, "Sports"),
        (["stairs", "climb"],                          .cardio,      .moderate, "Stair Climbing"),

        // Strength
        (["shovel", "snow", "dig"],                    .strength,    .hard,     "Shoveling"),
        (["move", "furniture", "carry", "lift"],       .strength,    .moderate, "Heavy Lifting"),

        // Flexibility
        (["yoga", "stretch"],                          .flexibility, .easy,     "Yoga / Stretching"),

        // Mixed
        (["mow", "lawn", "yard", "rake"],             .mixed,       .moderate, "Yard Work"),
        (["clean", "house", "vacuum", "mop"],          .mixed,       .easy,     "Cleaning"),
        (["garden", "gardening", "weed"],              .mixed,       .easy,     "Gardening"),
    ]

    /// Maps a free-text activity description to a workout type, intensity, and label.
    /// Returns a default "Activity / mixed / moderate" mapping when no keywords match.
    static func map(_ description: String) -> ActivityMapping {
        let lowered = description.lowercased()

        for (keywords, workoutType, intensity, label) in rules {
            for keyword in keywords {
                if lowered.contains(keyword) {
                    return ActivityMapping(
                        workoutType: workoutType,
                        suggestedIntensity: intensity,
                        label: label
                    )
                }
            }
        }

        // Default fallback
        return ActivityMapping(
            workoutType: .mixed,
            suggestedIntensity: .moderate,
            label: "Activity"
        )
    }

    /// Calculates XP earned for an activity, capped at 300.
    static func calculateXP(durationMinutes: Int, intensity: ActivityIntensity) -> Int {
        min(300, durationMinutes * intensity.xpPerMinute)
    }
}
