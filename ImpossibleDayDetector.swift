import Foundation

// MARK: - Impossible Day Detector
//
// Analyses the day's quest completionConditions against known physiological
// limits to surface quests that are literally unachievable in a single day.
// This prevents the RPG from punishing players for system-generated quests
// that would require superhuman effort.
//
// Physical limits used (conservative real-world upper bounds):
//   Steps      : 40 000  (elite runner daily training)
//   Calories   : 2 000   (active calorie burn, not TDEE)
//   Sleep      : 12 h    (maximum restorative sleep)
//   Workout    : 4 h     (accumulated daily training time)
//   Hydration  : 8 L     (extreme heat/endurance ceiling)

struct ImpossibleDayDetector {

    // MARK: - Limits

    struct PhysiologicalLimits {
        static let maxDailySteps: Int       = 40_000
        static let maxActiveCalories: Int   = 2_000
        static let maxSleepHours: Double    = 12.0
        static let maxWorkoutHours: Double  = 4.0
        static let maxHydrationLiters: Double = 8.0
    }

    // MARK: - Warning

    struct ImpossibleWarning: Identifiable {
        let id = UUID()
        let questTitle: String
        let reason: String          // Human-readable explanation
        let suggestion: String      // Suggested replacement target
    }

    // MARK: - Detection

    /// Returns warnings for any quests whose completionCondition exceeds physiological limits.
    static func detect(in quests: [Quest]) -> [ImpossibleWarning] {
        quests.compactMap { quest in
            guard let condition = quest.completionCondition else { return nil }
            return evaluate(condition: condition, questTitle: quest.title)
        }
    }

    // MARK: - Private

    private static func evaluate(condition: String, questTitle: String) -> ImpossibleWarning? {
        let parts = condition.lowercased().split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let type = parts.first.map(String.init),
              let valueStr = parts.last.map(String.init) else { return nil }

        switch type {
        case "steps":
            guard let steps = Int(valueStr), steps > PhysiologicalLimits.maxDailySteps else {
                return nil
            }
            return ImpossibleWarning(
                questTitle: questTitle,
                reason: "\(steps.formatted()) steps exceeds the physiological daily limit of \(PhysiologicalLimits.maxDailySteps.formatted()).",
                suggestion: "Try a target of 10 000–20 000 steps."
            )

        case "calories":
            guard let cals = Int(valueStr), cals > PhysiologicalLimits.maxActiveCalories else {
                return nil
            }
            return ImpossibleWarning(
                questTitle: questTitle,
                reason: "\(cals) active calories exceeds the realistic single-day ceiling of \(PhysiologicalLimits.maxActiveCalories).",
                suggestion: "A target of 500–1 000 active calories is sustainable."
            )

        case "sleep":
            guard let hours = Double(valueStr), hours > PhysiologicalLimits.maxSleepHours else {
                return nil
            }
            return ImpossibleWarning(
                questTitle: questTitle,
                reason: "\(String(format: "%.1f", hours))h of sleep exceeds the healthy maximum of \(Int(PhysiologicalLimits.maxSleepHours))h.",
                suggestion: "7–9 hours is the optimal sleep target."
            )

        case "workout":
            // Format: "workout:strength|4h" or "workout:any|5h" – hours encoded after |
            let wParts = valueStr.split(separator: "|")
            if wParts.count == 2, let hours = Double(wParts[1].replacingOccurrences(of: "h", with: "")),
               hours > PhysiologicalLimits.maxWorkoutHours {
                return ImpossibleWarning(
                    questTitle: questTitle,
                    reason: "\(String(format: "%.1f", hours))h workout session exceeds the daily training ceiling of \(Int(PhysiologicalLimits.maxWorkoutHours))h.",
                    suggestion: "60–90 minute sessions are optimal for adaptation."
                )
            }
            return nil

        case "hydration":
            guard let liters = Double(valueStr), liters > PhysiologicalLimits.maxHydrationLiters else {
                return nil
            }
            return ImpossibleWarning(
                questTitle: questTitle,
                reason: "\(String(format: "%.1f", liters))L of water exceeds safe daily intake of \(Int(PhysiologicalLimits.maxHydrationLiters))L.",
                suggestion: "2.5–3.5L is a healthy daily target."
            )

        default:
            return nil
        }
    }
}
