import Foundation
import SwiftData
import SwiftUI

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
        /// Scales quest rewards to match the steeper XP threshold curve so players
        /// at every rank take roughly the same real-world effort to level up (~2-3 weeks of
        /// consistent daily quest completion).
        var xpMultiplier: Double {
            switch rank {
            case .e: return 1.0       // Rank E: base XP values
            case .d: return 3.0       // Rank D: ~3× base (threshold ~4-8× higher)
            case .c: return 12.0      // Rank C: ~12× base
            case .b: return 60.0      // Rank B: ~60× base
            case .a: return 350.0     // Rank A: ~350× base
            case .s: return 2_500.0   // Rank S: ~2,500× base — every quest session is a serious grind
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
    /// If the profile has an active anime workout plan, the plan's quest for
    /// today's weekday is returned instead of the generic algorithm.
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
        existingQuests: [Quest],
        modelContext: ModelContext? = nil
    ) -> [Quest] {
        guard existingQuests.isEmpty else { return [] } // Already generated today

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)

        // --- Active Plan Override (anime or custom) ---
        // When a plan is active, replace the generic strength/cardio quests with
        // the plan's quest for today (keyed by day-of-week, 0 = Monday).
        if !profile.activePlanID.isEmpty {
            let activePlan = AnimeWorkoutPlanService.shared.plan(id: profile.activePlanID)
                ?? customPlan(id: profile.activePlanID, context: modelContext)
            if let plan = activePlan {
                return buildPlanQuests(plan: plan, profile: profile, date: today, dueDate: tomorrow)
            }
        }

        // --- Generic Algorithm ---
        let tier = QuestManager.tier(for: profile.level)
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

    // MARK: - Anime Plan Quest Builder

    /// Converts today's `DayPlan` from an anime workout plan into Quest objects.
    /// Also appends the always-present penalty-awareness and discipline quests.
    func buildPlanQuests(
        plan: AnimeWorkoutPlan,
        profile: Profile,
        date: Date,
        dueDate: Date?
    ) -> [Quest] {
        var quests: [Quest] = []

        // Map Calendar weekday (1=Sun…7=Sat) → plan index (0=Mon…6=Sun)
        let calWeekday = Calendar.current.component(.weekday, from: date)
        let planIndex = (calWeekday + 5) % 7 // Sun=0→6, Mon=1→0, Tue=2→1 …
        let dayPlan = plan.weeklySchedule[planIndex]

        if dayPlan.isRest {
            // Rest day — single active recovery quest
            quests.append(Quest(
                title: "[\(plan.character)] Rest & Recover",
                details: """
                Rest day on the \(plan.character) protocol. \
                Active recovery: light stretching, mobility work, or a slow walk. \
                Sleep 8+ hours. Hydrate. Let the adaptations compound.
                """,
                type: .daily,
                createdAt: Date(),
                dueDate: dueDate,
                xpReward: 50,
                statTarget: "energy",
                completionCondition: "sleep:8",
                dateTag: date
            ))
        } else {
            // Training day — one quest per planned exercise block
            // (group all exercises into a single workout quest for simplicity)
            let exerciseLines = dayPlan.exercises.map { ex -> String in
                "\(ex.sets)×\(ex.reps) \(ex.name)\(ex.notes.isEmpty ? "" : " — \(ex.notes)")"
            }.joined(separator: "\n")

            quests.append(Quest(
                title: dayPlan.questTitle,
                details: """
                \(plan.character) Protocol — \(dayPlan.focus)

                \(exerciseLines)

                \(dayPlan.questDetails)
                """,
                type: .daily,
                createdAt: Date(),
                dueDate: dueDate,
                xpReward: dayPlan.xpReward,
                statTarget: "strength",
                dateTag: date
            ))
        }

        // Always include penalty-awareness and discipline anchors
        if let deadline = profile.hardcoreResetDeadline {
            let hoursLeft = deadline.timeIntervalSinceNow / 3600
            if hoursLeft > 0 && hoursLeft <= 4 {
                quests.append(urgencyQuest(hoursLeft: hoursLeft, date: date, dueDate: dueDate))
            }
        }

        let tier = QuestManager.tier(for: profile.level)
        quests.append(disciplineQuest(profile: profile, tier: tier, date: date, dueDate: dueDate))

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
        let baseReps = (tier.repRange.lowerBound + tier.repRange.upperBound) / 2
        // Females and 50+ players: shift to higher rep ranges (12-15) for joint health and
        // connective tissue adaptation — same training stimulus, safer loading.
        let repOffset = (profile.gender == .female || profile.age >= 50) ? 2 : 0
        let reps = baseReps + repOffset

        // Progressive overload target weight
        let targetWeight: Double
        if let pr {
            // Add micro-progression: +2.5% of 1RM every 4 sessions (linear periodisation)
            let sessionBonus = 1.0 + (Double(profile.currentStreak % 4) * 0.025)
            targetWeight = pr.oneRepMaxKg * tier.workingSetPercent * sessionBonus
        } else {
            // No PR — use bodyweight percentage as seed (adjusted for gender & age)
            targetWeight = profile.weight * bodyweightSeedPercent(tier: tier, exercise: exercise, profile: profile)
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

        // Bio-factor: females average ~10% lower absolute distance at the same effort level
        // due to smaller lung volume and lower haemoglobin (ACSM position stand).
        // Age 50+: reduce target by ~10% to protect joints and cardiovascular load.
        let genderAdjust: Double = profile.gender == .female ? 0.90 : 1.0
        let ageAdjust: Double = profile.age >= 50 ? 0.90 : 1.0

        let targetKm = (baseKm + vo2Bonus) * genderAdjust * ageAdjust
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

        // Age factor: WHO recommends 7,000–10,000 for adults; reduce for 60+ (joint load)
        let ageStepFactor: Double = profile.age >= 60 ? 0.85 : 1.0
        let totalGoal = Int(Double(baseGoal + streakBonus) * ageStepFactor)
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
            completionCondition: "discipline_check",
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

    // MARK: - Custom Plan Lookup

    /// Fetches a user-created `CustomWorkoutPlan` from SwiftData by ID and converts it
    /// to an `AnimeWorkoutPlan` so it can be handled by the same code path.
    private func customPlan(id: String, context: ModelContext?) -> AnimeWorkoutPlan? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<CustomWorkoutPlan>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first?.asAnimeWorkoutPlan()
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
    /// Applies gender and age modifiers on top of the tier base.
    private func bodyweightSeedPercent(tier: PlayerTier, exercise: ExerciseItem, profile: Profile) -> Double {
        let isBigLift = exercise.primaryMuscles.contains { ["Quadriceps", "Glutes", "Back", "Chest"].contains($0) }
        let base: Double
        switch tier.rank {
        case .e: base = isBigLift ? 0.40 : 0.20
        case .d: base = isBigLift ? 0.55 : 0.30
        case .c: base = isBigLift ? 0.70 : 0.40
        case .b: base = isBigLift ? 0.90 : 0.55
        case .a: base = isBigLift ? 1.10 : 0.65
        case .s: base = isBigLift ? 1.30 : 0.80
        }

        // Gender: females average ~65% relative strength of males at the same BW ratio
        // (NSCA/ACSM general population baseline). This seeds appropriate starting weights.
        let genderFactor: Double = profile.gender == .female ? 0.65 : 1.0

        // Age: peak strength 25-35 years. Younger players build fast; older need conservative starts.
        let ageFactor: Double
        switch profile.age {
        case ..<20:       ageFactor = 0.85  // still developing, protect joints
        case 20..<36:     ageFactor = 1.0   // prime
        case 36..<50:     ageFactor = 0.92  // slight decline in peak force
        default:          ageFactor = 0.82  // 50+ conservative, longevity first
        }

        return base * genderFactor * ageFactor
    }

    /// Rounds a weight to the nearest 2.5 kg plate increment.
    private func roundToNearestPlate(_ weight: Double) -> Double {
        (weight / 2.5).rounded() * 2.5
    }
}

// MARK: - Bodyweight Alternative Quests

extension QuestManager {

    /// Builds a single one-off bodyweight alternative quest derived from a
    /// training focus. Used when the player has no access to equipment
    /// (travel days, home workouts, etc.). Not added to the daily generator —
    /// spawned on demand via `spawnBodyweightAlternative`.
    func bodyweightAlternativeQuest(focusBodyParts: [String], date: Date, dueDate: Date?) -> Quest {
        // Normalize inputs to lowercase for keyword matching.
        let parts = focusBodyParts.map { $0.lowercased() }

        // Pick the most prominent body part and resolve it to a focus bucket.
        // Priority order mirrors the spec: push → pull → legs → core → cardio → default.
        let focusLabel: String
        let movements: String
        if parts.contains(where: { ["chest", "push", "shoulders", "arms"].contains($0) }) {
            focusLabel = "Push"
            movements = """
            3 sets of 10–15 reps each:
            • Push-Ups
            • Pike Push-Ups
            • Tricep Dips (use a sturdy chair)
            """
        } else if parts.contains(where: { ["back", "pull"].contains($0) }) {
            focusLabel = "Pull"
            movements = """
            3 sets of 8–12 reps each:
            • Inverted Rows (use a sturdy table)
            • Doorway Pulls
            • Superman Holds
            """
        } else if parts.contains(where: { ["legs", "glutes", "lower"].contains($0) }) {
            focusLabel = "Legs"
            movements = """
            3 sets of 15–20 reps each:
            • Bodyweight Squats
            • Walking Lunges
            • Glute Bridges
            • Calf Raises
            """
        } else if parts.contains("core") {
            focusLabel = "Core"
            movements = """
            3 rounds of 30 seconds each:
            • Plank
            • Dead Bug
            • Mountain Climbers
            • Side Plank
            """
        } else if parts.contains("cardio") {
            focusLabel = "Cardio"
            movements = """
            4 rounds of 1 minute work / 30 sec rest:
            • Jumping Jacks
            • High Knees
            • Burpees
            """
        } else {
            // mobility, fullBody, mixed, or anything unrecognized.
            focusLabel = "Full Body"
            movements = """
            15-minute full-body bodyweight circuit:
            • Bodyweight Squats
            • Push-Ups
            • Planks
            • Walking Lunges
            Repeat as many rounds as possible in 15 minutes.
            """
        }

        return Quest(
            title: "Bodyweight Alternative — \(focusLabel)",
            details: movements,
            type: .daily,
            dueDate: dueDate,
            xpReward: 60,
            statTarget: "discipline",
            completionCondition: "workout:any",
            dateTag: date
        )
    }

    /// Inserts a bodyweight alternative quest into the given context so it
    /// appears immediately in the quest list. The quest auto-completes when
    /// any workout is logged (via the existing `workout:any` path).
    @MainActor
    func spawnBodyweightAlternative(focusBodyParts: [String], context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let quest = bodyweightAlternativeQuest(focusBodyParts: focusBodyParts, date: today, dueDate: tomorrow)
        context.insert(quest)
        try? context.save()
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
