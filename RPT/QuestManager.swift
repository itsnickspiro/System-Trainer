import Foundation
import SwiftData

// MARK: - QuestManager
//
// Generates daily and weekly quests that progressively overload in difficulty
// based on the player's Level, gender, height, weight, and logged Personal Records.
//
// Algorithm:
//   1. Determine the player's Tier from their Level (1–5 tiers).
//   2. Calculate a progressive-overload target weight for strength exercises
//      using the player's 1RM from PersonalRecord, applying a percentage
//      proportional to tier and current streak.
//   3. Build a workout block (compound lift + accessory) per muscle group
//      chosen from the available exercises, filtered by GymEnvironment.
//   4. Generate cardio / patrol quests scaled to the player's VO2 max and
//      step history.
//   5. Apply a penalty-awareness quest if the midnight deadline is within 4 hours.

@MainActor
final class QuestManager {

    static let shared = QuestManager()

    // MARK: - Tier System
    //
    // Mirrors the Solo Leveling rank system: E → D → C → B → A → S
    // Each tier unlocks harder exercises and higher XP ceilings.

    struct PlayerTier {
        let rank: TierRank
        let minLevel: Int
        let maxLevel: Int

        /// Percentage of 1RM used for working sets (linear progression within tier).
        var workingSetPercent: Double {
            switch rank {
            case .e: return 0.50   // Beginner — 50% 1RM, high reps
            case .d: return 0.60
            case .c: return 0.70
            case .b: return 0.75
            case .a: return 0.80
            case .s: return 0.85   // Elite — 85% 1RM, lower reps
            }
        }

        /// Rep range for working sets.
        var repRange: ClosedRange<Int> {
            switch rank {
            case .e: return 12...15
            case .d: return 10...12
            case .c: return 8...10
            case .b: return 6...8
            case .a: return 5...6
            case .s: return 3...5
            }
        }

        /// Number of working sets per compound lift.
        var workingSets: Int {
            switch rank {
            case .e: return 3
            case .d: return 3
            case .c: return 4
            case .b: return 4
            case .a: return 5
            case .s: return 5
            }
        }

        /// XP multiplier for this tier.
        var xpMultiplier: Double {
            switch rank {
            case .e: return 1.0
            case .d: return 1.2
            case .c: return 1.5
            case .b: return 1.8
            case .a: return 2.2
            case .s: return 3.0
            }
        }
    }

    enum TierRank: String, CaseIterable {
        case e = "E"
        case d = "D"
        case c = "C"
        case b = "B"
        case a = "A"
        case s = "S"

        var displayName: String { "Rank-\(rawValue)" }
        var color: String {
            switch self {
            case .e: return "gray"
            case .d: return "green"
            case .c: return "blue"
            case .b: return "purple"
            case .a: return "orange"
            case .s: return "yellow"
            }
        }
    }

    // MARK: - Tier Lookup

    static func tier(for level: Int) -> PlayerTier {
        switch level {
        case 1...5:   return PlayerTier(rank: .e, minLevel: 1,  maxLevel: 5)
        case 6...15:  return PlayerTier(rank: .d, minLevel: 6,  maxLevel: 15)
        case 16...30: return PlayerTier(rank: .c, minLevel: 16, maxLevel: 30)
        case 31...50: return PlayerTier(rank: .b, minLevel: 31, maxLevel: 50)
        case 51...80: return PlayerTier(rank: .a, minLevel: 51, maxLevel: 80)
        default:      return PlayerTier(rank: .s, minLevel: 81, maxLevel: Int.max)
        }
    }

    // MARK: - Primary Entry Point

    /// Generates today's quest list for the given profile.
    ///
    /// - Parameters:
    ///   - profile: The current PlayerProfile.
    ///   - exercises: All cached ExerciseItems from SwiftData.
    ///   - personalRecords: All PersonalRecord entries from SwiftData.
    ///   - existingQuests: Any quests already created today (prevents duplicates).
    /// - Returns: Array of Quest objects ready to be inserted into SwiftData.
    func generateDailyQuests(
        for profile: Profile,
        exercises: [ExerciseItem],
        personalRecords: [PersonalRecord],
        existingQuests: [Quest]
    ) -> [Quest] {
        guard existingQuests.isEmpty else { return [] } // Already generated today

        let tier = QuestManager.tier(for: profile.level)
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        var quests: [Quest] = []

        // 1. Strength Block
        quests += buildStrengthBlock(
            profile: profile, tier: tier,
            exercises: exercises, prs: personalRecords,
            date: today, dueDate: tomorrow
        )

        // 2. Cardio / Patrol Quest
        quests += buildCardioQuests(
            profile: profile, tier: tier,
            date: today, dueDate: tomorrow
        )

        // 3. Step Quest
        quests += buildStepQuest(
            profile: profile, tier: tier,
            date: today, dueDate: tomorrow
        )

        // 4. Sleep / Recovery Quest (conditional)
        if profile.sleepHours < 7 {
            quests += buildSleepQuest(profile: profile, date: today, dueDate: tomorrow)
        }

        // 5. Penalty-awareness quest (if deadline within 4 hours)
        if let deadline = profile.hardcoreResetDeadline {
            let hoursLeft = deadline.timeIntervalSinceNow / 3600
            if hoursLeft > 0 && hoursLeft <= 4 {
                quests.append(urgencyQuest(hoursLeft: hoursLeft, date: today, dueDate: tomorrow))
            }
        }

        // 6. Discipline anchor (always present)
        quests.append(disciplineQuest(profile: profile, tier: tier, date: today, dueDate: tomorrow))

        return quests
    }

    // MARK: - Strength Block Builder

    private func buildStrengthBlock(
        profile: Profile,
        tier: PlayerTier,
        exercises: [ExerciseItem],
        prs: [PersonalRecord],
        date: Date,
        dueDate: Date?
    ) -> [Quest] {
        var quests: [Quest] = []

        // Filter exercises by the player's gym environment
        let allowedIDs = profile.gymEnvironment.allowedEquipmentIDs
        let eligible = exercises.filter { exercise in
            // An exercise is eligible if it has no required equipment (bodyweight)
            // OR if all its equipment is available in the current gym.
            if exercise.equipment.isEmpty { return true }
            // Map equipment name → wger ID using our lookup table.
            let exerciseEquipIDs = exercise.equipment.compactMap { equipmentIDForName($0) }
            return exerciseEquipIDs.allSatisfy { allowedIDs.contains($0) }
        }

        // Pick one compound push, one pull, one leg — the Big 3 for the day.
        // This rotates by day-of-week to avoid monotony.
        let weekday = Calendar.current.component(.weekday, from: date)
        let muscleGroups: [[String]] = muscleGroupForWeekday(weekday)

        for muscles in muscleGroups {
            guard let exercise = pickBestExercise(
                from: eligible, targetMuscles: muscles, prs: prs
            ) else { continue }

            let pr = prs.first { $0.exerciseWgerID == exercise.wgerID }
            let quest = makeStrengthQuest(
                exercise: exercise, pr: pr,
                tier: tier, profile: profile,
                date: date, dueDate: dueDate
            )
            quests.append(quest)
        }

        return quests
    }

    /// Returns the target muscle groups for today based on weekday rotation.
    /// Mon/Thu = Push, Tue/Fri = Pull, Wed/Sat = Legs, Sun = Full Body.
    private func muscleGroupForWeekday(_ weekday: Int) -> [[String]] {
        switch weekday {
        case 2, 5: return [["Chest", "Shoulders"], ["Triceps"]]   // Push
        case 3, 6: return [["Back", "Lats"], ["Biceps"]]           // Pull
        case 4, 7: return [["Quadriceps", "Glutes"], ["Hamstrings"]] // Legs
        default:   return [["Chest"], ["Back"], ["Quadriceps"]]     // Full Body (Sun/Mon)
        }
    }

    /// Choose the exercise that best matches target muscles, preferring ones with PRs.
    private func pickBestExercise(
        from exercises: [ExerciseItem],
        targetMuscles: [String],
        prs: [PersonalRecord]
    ) -> ExerciseItem? {
        let prIDs = Set(prs.map { $0.exerciseWgerID })

        // Prefer exercises we have a PR for (progressive overload data available)
        let matched = exercises.filter { ex in
            ex.primaryMuscles.contains { muscle in
                targetMuscles.contains { muscle.localizedCaseInsensitiveContains($0) }
            }
        }
        return matched.first { prIDs.contains($0.wgerID) } ?? matched.first
    }

    private func makeStrengthQuest(
        exercise: ExerciseItem,
        pr: PersonalRecord?,
        tier: PlayerTier,
        profile: Profile,
        date: Date,
        dueDate: Date?
    ) -> Quest {
        let sets = tier.workingSets
        let reps = (tier.repRange.lowerBound + tier.repRange.upperBound) / 2

        // Progressive overload target weight
        let targetWeight: Double
        if let pr {
            // Add micro-progression: +2.5% of 1RM every 4 sessions (linear periodisation)
            let sessionBonus = 1.0 + (Double(profile.currentStreak % 4) * 0.025)
            targetWeight = pr.oneRepMaxKg * tier.workingSetPercent * sessionBonus
        } else {
            // No PR — use bodyweight percentage as seed
            targetWeight = profile.weight * bodyweightSeedPercent(tier: tier, exercise: exercise)
        }

        let rounded = roundToNearestPlate(targetWeight)
        let baseXP = Int(Double(sets * reps) * tier.xpMultiplier * 2.5)

        let details: String
        if rounded > 0 {
            details = """
            Target: \(sets) × \(reps) reps @ \(String(format: "%.1f", rounded)) kg
            Primary: \(exercise.primaryMuscles.joined(separator: ", "))
            Protocol: \(tier.rank.displayName) progressive overload. \
            Failure to log forfeits Strength XP for the cycle.
            """
        } else {
            details = """
            Target: \(sets) × \(reps) reps (bodyweight)
            Primary: \(exercise.primaryMuscles.joined(separator: ", "))
            Protocol: \(tier.rank.displayName) — establish baseline weight for progressive overload.
            """
        }

        return Quest(
            title: exercise.name,
            details: details,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: baseXP,
            statTarget: exercise.workoutType == .strength ? "strength" : "endurance",
            dateTag: date
        )
    }

    // MARK: - Cardio Block Builder

    private func buildCardioQuests(
        profile: Profile,
        tier: PlayerTier,
        date: Date,
        dueDate: Date?
    ) -> [Quest] {
        // Scale distance target to VO2 max and tier
        let baseKm: Double = {
            switch tier.rank {
            case .e: return 1.5
            case .d: return 2.5
            case .c: return 4.0
            case .b: return 5.5
            case .a: return 7.0
            case .s: return 10.0
            }
        }()

        // Bonus distance for good cardio fitness (VO2 max > 45 = elite)
        let vo2Bonus = max(0.0, (profile.vo2Max - 35.0) / 10.0) * 0.5
        let targetKm = baseKm + vo2Bonus
        let xp = Int(Double(tier.rank == .s ? 200 : 80) * tier.xpMultiplier)

        return [Quest(
            title: "Patrol Route: \(String(format: "%.1f", targetKm)) km",
            details: """
            Directive: Complete a \(String(format: "%.1f", targetKm)) km outdoor patrol. \
            GPS tracking active. Endurance XP locked until route is closed. \
            Pace requirement: none — completion is the metric.
            """,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: xp,
            statTarget: "endurance",
            dateTag: date
        )]
    }

    // MARK: - Step Quest Builder

    private func buildStepQuest(
        profile: Profile,
        tier: PlayerTier,
        date: Date,
        dueDate: Date?
    ) -> [Quest] {
        // Step goal scales with tier and current streak momentum
        let baseGoal = 8_000 + (tier.rank.ordinal * 1_000)
        let streakBonus = min(2_000, profile.currentStreak * 100)
        let totalGoal = baseGoal + streakBonus
        let gap = totalGoal - profile.dailySteps

        guard gap > 1_000 else { return [] } // Already near goal — skip

        let xp = Int(Double(50 + gap / 100) * tier.xpMultiplier)

        return [Quest(
            title: "Step Count Directive",
            details: """
            Target: \(totalGoal.formatted()) steps. \
            Current: \(profile.dailySteps.formatted()). \
            Delta: \(gap.formatted()) steps remaining. \
            Streak modifier applied: +\(streakBonus) step bonus.
            """,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: xp,
            statTarget: "endurance",
            dateTag: date
        )]
    }

    // MARK: - Sleep Quest Builder

    private func buildSleepQuest(profile: Profile, date: Date, dueDate: Date?) -> [Quest] {
        let deficit = max(0, 8.0 - profile.sleepHours)
        return [Quest(
            title: "Sleep Deficit: Critical",
            details: """
            Analysis: \(String(format: "%.1f", profile.sleepHours))h logged — \
            \(String(format: "%.1f", deficit))h below optimal. \
            Focus stat suppressed. Energy regeneration at \(Int((profile.sleepHours / 8.0) * 100))%. \
            Directive: Restore 8h sleep cycle tonight to clear debuff.
            """,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: 100,
            statTarget: "energy",
            dateTag: date
        )]
    }

    // MARK: - Urgency Quest (Penalty Warning)

    private func urgencyQuest(hoursLeft: Double, date: Date, dueDate: Date?) -> Quest {
        Quest(
            title: "⚠ DEADLINE IMMINENT",
            details: """
            Warning: Midnight reset deadline in \(String(format: "%.1f", hoursLeft)) hours. \
            Incomplete quests will trigger Level 1 reset. \
            Use an Exemption Pass from inventory to nullify the penalty. \
            Execute all active directives immediately.
            """,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: 0,
            statTarget: "discipline",
            dateTag: date
        )
    }

    // MARK: - Discipline Anchor Quest

    private func disciplineQuest(
        profile: Profile, tier: PlayerTier,
        date: Date, dueDate: Date?
    ) -> Quest {
        let streakText = profile.currentStreak > 0
            ? "Current streak: \(profile.currentStreak) days."
            : "Streak broken. Rebuild begins now."
        return Quest(
            title: "Daily Discipline Check",
            details: """
            \(streakText) \
            Directive: Log one meal and complete one quest before midnight. \
            Failure breaks streak and reduces Discipline stat.
            """,
            type: .daily,
            createdAt: Date(),
            dueDate: dueDate,
            xpReward: Int(50.0 * tier.xpMultiplier),
            statTarget: "discipline",
            dateTag: date
        )
    }

    // MARK: - Exercise Substitution (Equipment Unavailable)

    /// Finds a biomechanically equivalent exercise when the player taps
    /// "Equipment Unavailable." Matches on primary muscle group and workout type,
    /// filtered by the player's current gym environment.
    func substituteExercise(
        for original: ExerciseItem,
        profile: Profile,
        availableExercises: [ExerciseItem]
    ) -> ExerciseItem? {
        let allowedIDs = profile.gymEnvironment.allowedEquipmentIDs

        return availableExercises.first { candidate in
            guard candidate.wgerID != original.wgerID else { return false }
            guard candidate.workoutType == original.workoutType else { return false }

            // Must share at least one primary muscle
            let muscleOverlap = candidate.primaryMuscles.contains { muscle in
                original.primaryMuscles.contains { muscle.localizedCaseInsensitiveContains($0) }
            }
            guard muscleOverlap else { return false }

            // Must be available with current gym equipment
            if candidate.equipment.isEmpty { return true }
            let candidateIDs = candidate.equipment.compactMap { equipmentIDForName($0) }
            return candidateIDs.allSatisfy { allowedIDs.contains($0) }
        }
    }

    // MARK: - Helpers

    /// Maps wger equipment name strings to their numeric IDs.
    private func equipmentIDForName(_ name: String) -> Int? {
        switch name.lowercased() {
        case "barbell":                         return 1
        case "sz-bar", "ez bar", "ez-bar":      return 2
        case "dumbbell", "dumbbells":           return 3
        case "gym mat":                         return 4
        case "swiss ball", "exercise ball":     return 5
        case "pull-up bar", "pull up bar":      return 6
        case "cable":                           return 7
        case "bench":                           return 8
        case "incline bench":                   return 9
        case "kettlebell", "kettle bell":       return 10
        case "smith machine":                   return 11
        case "resistance band", "bands":        return 12
        case "body weight", "bodyweight", "none", "": return 99
        default:                                return nil
        }
    }

    /// Seed weight as a percentage of bodyweight when no PR exists.
    private func bodyweightSeedPercent(tier: PlayerTier, exercise: ExerciseItem) -> Double {
        let isBigLift = exercise.primaryMuscles.contains { ["Quadriceps", "Glutes", "Back", "Chest"].contains($0) }
        switch tier.rank {
        case .e: return isBigLift ? 0.40 : 0.20
        case .d: return isBigLift ? 0.55 : 0.30
        case .c: return isBigLift ? 0.70 : 0.40
        case .b: return isBigLift ? 0.90 : 0.55
        case .a: return isBigLift ? 1.10 : 0.65
        case .s: return isBigLift ? 1.30 : 0.80
        }
    }

    /// Rounds a weight to the nearest 2.5 kg plate increment.
    private func roundToNearestPlate(_ weight: Double) -> Double {
        (weight / 2.5).rounded() * 2.5
    }
}

// MARK: - TierRank Ordinal (for arithmetic)

extension QuestManager.TierRank {
    var ordinal: Int {
        switch self {
        case .e: return 0
        case .d: return 1
        case .c: return 2
        case .b: return 3
        case .a: return 4
        case .s: return 5
        }
    }
}
