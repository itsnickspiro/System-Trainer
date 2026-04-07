import Foundation
import SwiftData
import SwiftUI

@Model
final class Profile {
    // CloudKit sync requires every stored property to be optional or have a default value.
    // Non-optional properties without defaults crash when CloudKit returns a record
    // that doesn't yet have that field (e.g. first sync, schema evolution).
    var id: UUID = UUID()
    var name: String = "Player"
    var xp: Int = 0
    var level: Int = 1
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    /// Monotonically increasing total XP earned (never decremented).
    /// Used for CloudKit conflict resolution — highest totalXPEarned wins.
    var totalXPEarned: Int = 0
    var lastCompletionDate: Date?
    var hardcoreResetDeadline: Date?

    // RPG Stats
    var health: Double = 80.0
    var energy: Double = 75.0
    var strength: Double = 50.0
    var endurance: Double = 50.0
    var focus: Double = 60.0
    var discipline: Double = 50.0

    // Health tracking
    var waterIntake: Int = 0
    var lastMealTime: Date?
    var lastWorkoutTime: Date?
    var sleepHours: Double = 7.0
    var lastStatUpdate: Date = Date()

    // Diet preference (Phase D1). Stored as raw string for CloudKit compatibility.
    // Use the `dietType` computed accessor (Profile extension) for type-safe reads/writes.
    var dietTypeRaw: String = "none"

    // Player class / archetype (Phase D-3). Stored as raw string for CloudKit compatibility.
    // Use the `playerClass` computed accessor (Profile extension) for type-safe reads/writes.
    var playerClassRaw: String = "unselected"


    // HealthKit Integration Properties
    var dailySteps: Int = 0
    var dailyStepsGoal: Int = 10000
    var restingHeartRate: Int = 70 // BPM
    var activeHeartRate: Int = 120 // BPM during exercise
    var weight: Double = 70.0 // kg
    var height: Double = 170.0 // cm
    var bodyFatPercentage: Double = 20.0 // %
    var vo2Max: Double = 35.0 // ml/kg/min
    
    // Activity Metrics
    var dailyActiveCalories: Int = 0
    var dailyActiveCaloriesGoal: Int = 400
    var weeklyWorkoutMinutes: Int = 0
    var weeklyWorkoutGoal: Int = 150 // WHO recommendation
    
    // Sleep & Recovery
    var sleepEfficiency: Double = 0.85 // % of time in bed actually sleeping
    var heartRateVariability: Double = 40.0 // RMSSD in milliseconds
    var restingHeartRateVariability: Double = 0.0 // Change from baseline
    
    // Nutrition Tracking
    var dailyProteinIntake: Double = 0.0 // grams
    var dailyFiberIntake: Double = 0.0 // grams
    var dailySugarIntake: Double = 0.0 // grams
    var alcoholUnitsThisWeek: Double = 0.0 // standard drinks
    
    // Environmental & Behavioral
    var screenTimeToday: Double = 0.0 // hours
    var mindfulnessMinutesToday: Int = 0
    var stairFlightsClimbed: Int = 0
    var uvExposure: Double = 0.0 // UV Index exposure

    // Player Demographics — used by QuestManager progressive overload & BMR
    var age: Int = 25
    var genderRaw: String = PlayerGender.male.rawValue
    var gymEnvironmentRaw: String = GymEnvironment.fullGym.rawValue
    var fitnessGoalRaw: String = FitnessGoal.generalHealth.rawValue

    // Goal Survey — populated when the user picks "Build my own plan" during
    // onboarding. Drives quest generation for the custom plan path.
    var goalSurveyCompleted: Bool = false
    var goalSurveyDaysPerWeek: Int = 0          // 0 = unset
    var goalSurveySplitRaw: String = ""         // raw of GoalSurveySplit
    var goalSurveySessionMinutes: Int = 0
    var goalSurveyIntensityRaw: String = ""     // raw of GoalSurveyIntensity
    var goalSurveyFocusAreasRaw: [String] = []  // raw values, max 3
    var goalSurveyCardioRaw: String = ""        // raw of GoalSurveyCardio

    var gender: PlayerGender {
        get { PlayerGender(rawValue: genderRaw) ?? .male }
        set { genderRaw = newValue.rawValue }
    }

    var gymEnvironment: GymEnvironment {
        get { GymEnvironment(rawValue: gymEnvironmentRaw) ?? .fullGym }
        set { gymEnvironmentRaw = newValue.rawValue }
    }

    var fitnessGoal: FitnessGoal {
        get { FitnessGoal(rawValue: fitnessGoalRaw) ?? .generalHealth }
        set { fitnessGoalRaw = newValue.rawValue }
    }

    /// Short shareable code friends use to find this player (e.g. "A3F9K2").
    /// Generated once from the CloudKit user record ID and stored persistently.
    var friendCode: String = ""

    // MARK: - Rival
    //
    // The user can pick one friend from the leaderboard as their rival.
    // The Home screen shows a weekly Versus banner comparing the two on
    // level / XP / streak. Cosmetic — the rival doesn't know.
    var rivalCloudKitUserID: String = ""
    var rivalDisplayName: String = ""

    /// The ID of the currently active anime workout plan (e.g. "saitama").
    /// Empty string means no plan is active — use the generic quest/workout system.
    var activePlanID: String = ""

    /// Whether the user prefers metric (kg/km) or imperial (lbs/miles) units.
    /// Defaults to the device locale on first launch.
    var useMetric: Bool = (Locale.current.measurementSystem == .metric)

    // Penalty System State
    /// True when the player has an active exemption protecting against the midnight reset.
    var hasActiveExemption: Bool = false
    var exemptionExpiresAt: Date?

    // Recovery Mode — activated automatically after a Level 1 hardcore reset
    /// True when the player is in the Rehabilitation Arc (3-day post-reset recovery window).
    var isInRecovery: Bool = false
    /// Days remaining in the Rehabilitation Arc (counts down 3 → 2 → 1 → 0, then clears).
    var recoveryDaysRemaining: Int = 0
    /// Date of the most recent hardcore reset — used for Recovery Arc badge display.
    var lastResetDate: Date?

    // Earnable Exemption Passes (stored on profile for quick access, mirrored to InventoryItem)
    /// Number of earned Hermit's Miracle Seeds in the player's possession (max 3).
    var exemptionPassCount: Int = 0

    // Double XP state
    var doubleXPActiveUntil: Date?
    var hasDoubleXP: Bool { doubleXPActiveUntil.map { $0 > Date() } ?? false }

    // Custom Nutrition Goals — 0 means "use TDEE / plan default"
    /// Activity level multiplier index: 0=sedentary, 1=light, 2=moderate, 3=active, 4=very active
    var activityLevelIndex: Int = 1
    var customCalorieGoal: Int = 0   // 0 = auto-calculate from BMR × activity
    var customProteinGoal: Int = 0   // 0 = auto (0.8 g/kg bodyweight)
    var customCarbGoal: Int = 0      // 0 = auto (fill remaining calories)
    var customFatGoal: Int = 0       // 0 = auto (25% of calories)

    /// TDEE = BMR × activity multiplier
    var tdee: Double {
        let multipliers = [1.2, 1.375, 1.55, 1.725, 1.9]
        let idx = max(0, min(multipliers.count - 1, activityLevelIndex))
        return bmr * multipliers[idx]
    }

    /// Effective calorie goal: custom if set, else TDEE adjusted for fitness goal
    var effectiveCalorieGoal: Int {
        if customCalorieGoal > 0 { return customCalorieGoal }
        let base = tdee
        switch fitnessGoal {
        case .loseFat:        return Int((base - 500).rounded())
        case .buildMuscle:    return Int((base + 300).rounded())
        case .generalHealth, .endurance:
            return Int(base.rounded())
        }
    }

    /// Effective protein goal in grams
    var effectiveProteinGoal: Int {
        if customProteinGoal > 0 { return customProteinGoal }
        // 1.6 g/kg for muscle building, 1.2 g/kg otherwise
        let ratio = fitnessGoal == .buildMuscle ? 1.6 : 1.2
        return Int((weight * ratio).rounded())
    }

    /// Effective carb goal in grams
    var effectiveCarbGoal: Int {
        if customCarbGoal > 0 { return customCarbGoal }
        let proteinCals = Double(effectiveProteinGoal) * 4
        let fatCals = Double(effectiveFatGoal) * 9
        let carbCals = max(0, Double(effectiveCalorieGoal) - proteinCals - fatCals)
        return Int((carbCals / 4).rounded())
    }

    /// Effective fat goal in grams
    var effectiveFatGoal: Int {
        if customFatGoal > 0 { return customFatGoal }
        // 25% of total calories from fat
        return Int((Double(effectiveCalorieGoal) * 0.25 / 9).rounded())
    }
    
    // Computed Health Metrics
    var bmi: Double { weight / pow(height / 100, 2) }

    /// Basal Metabolic Rate — Mifflin-St Jeor Equation using real age & gender.
    var bmr: Double {
        let base = (10 * weight) + (6.25 * height) - (5 * Double(age))
        return gender == .female ? base - 161 : base + 5
    }
    
    var healthScore: Double {
        calculateOverallHealthScore()
    }

    init(name: String = "Player", xp: Int = 0, level: Int = 1, currentStreak: Int = 0, bestStreak: Int = 0, lastCompletionDate: Date? = nil, hardcoreResetDeadline: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.xp = xp
        self.level = level
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.lastCompletionDate = lastCompletionDate
        self.hardcoreResetDeadline = hardcoreResetDeadline
        
        // Initialize RPG stats
        self.health = 80.0
        self.energy = 75.0
        self.strength = 50.0
        self.endurance = 50.0
        self.focus = 60.0
        self.discipline = 50.0
        
        // Initialize health tracking
        self.waterIntake = 0
        self.lastMealTime = nil
        self.lastWorkoutTime = nil
        self.sleepHours = 7.0
        self.lastStatUpdate = Date()
        
        // Initialize HealthKit properties with defaults
        self.dailySteps = 0
        self.dailyStepsGoal = 10000
        self.restingHeartRate = 70
        self.activeHeartRate = 120
        self.weight = 70.0
        self.height = 170.0
        self.bodyFatPercentage = 20.0
        self.vo2Max = 35.0
        self.dailyActiveCalories = 0
        self.dailyActiveCaloriesGoal = 400
        self.weeklyWorkoutMinutes = 0
        self.weeklyWorkoutGoal = 150
        self.sleepEfficiency = 0.85
        self.heartRateVariability = 40.0
        self.restingHeartRateVariability = 0.0
        self.dailyProteinIntake = 0.0
        self.dailyFiberIntake = 0.0
        self.dailySugarIntake = 0.0
        self.alcoholUnitsThisWeek = 0.0
        self.screenTimeToday = 0.0
        self.mindfulnessMinutesToday = 0
        self.stairFlightsClimbed = 0
        self.uvExposure = 0.0
    }

    func addXP(_ amount: Int) {
        xp += amount
        if amount > 0 { totalXPEarned += amount }
        // Level up every 100 XP plus 50 XP per level increment
        while xp >= levelXPThreshold(level: level) {
            xp -= levelXPThreshold(level: level)
            level += 1
            // Boost all stats slightly on level up
            boostAllStats(by: 2.0)
        }
    }

    /// Removes XP, handling level-down if the subtraction would push XP below zero.
    func subtractXP(_ amount: Int) {
        xp -= amount
        // Level down if XP goes negative (can only drop to level 1)
        while xp < 0 && level > 1 {
            level -= 1
            xp += levelXPThreshold(level: level)
        }
        // Floor at 0 XP on level 1
        xp = max(0, xp)
    }

    func levelXPThreshold(level: Int) -> Int {
        // RPG-style steep exponential curve — levelling should feel meaningful at every tier.
        //
        // Rank E (1-5):   150 → ~330 XP   — accessible, motivating early gains
        // Rank D (6-15):  ~400 → ~2,200 XP — consistent effort required
        // Rank C (16-30): ~2,700 → ~32,000 XP — serious grind, real commitment
        // Rank B (31-50): ~39k → ~550k XP  — elite territory, months of work
        // Rank A (51-80): ~670k → ~huge    — legendary status
        // Rank S (81+):   astronomical     — true endgame
        //
        // Formula: 150 × 1.22^(level−1)
        // No linear bonus — pure exponential so each rank feels distinct.
        let baseXP: Double = 150
        let exponent: Double = 1.22
        return max(150, Int(baseXP * pow(exponent, Double(level - 1))))
    }

    func registerCompletion(on date: Date = Date()) {
        let cal = Calendar.current
        if let last = lastCompletionDate {
            if cal.isDate(date, inSameDayAs: last) {
                // same day, streak unchanged
            } else if let next = cal.date(byAdding: .day, value: 1, to: last), cal.isDate(date, inSameDayAs: next) {
                currentStreak += 1
                // Boost discipline for maintaining streak
                adjustStat(\.discipline, by: 1.5)
                // Award Exemption Pass on 7-day streak milestones
                checkAndAwardStreakPass()
            } else {
                currentStreak = 1
                // Slight discipline penalty for breaking streak
                adjustStat(\.discipline, by: -2.0)
            }
        } else {
            currentStreak = 1
        }
        bestStreak = max(bestStreak, currentStreak)
        lastCompletionDate = date
    }

    func applyHardcoreResetIfNeeded(now: Date = Date()) {
        guard let deadline = hardcoreResetDeadline, now >= deadline else { return }

        // Check for active exemption item (via profile flag or pass count)
        if hasActiveExemption || exemptionPassCount > 0 {
            let exemptionValid = hasActiveExemption
                ? (exemptionExpiresAt.map { now < $0 } ?? false)
                : true // pass count ≥ 1 is always valid
            if exemptionValid {
                // Only consume a pass if one wasn't already consumed by activateExemption()
                if !hasActiveExemption && exemptionPassCount > 0 {
                    exemptionPassCount -= 1
                }
                hasActiveExemption = false
                exemptionExpiresAt = nil
                // Defer deadline by 24 hours from the original deadline (not from now)
                hardcoreResetDeadline = Calendar.current.date(byAdding: .day, value: 1, to: deadline)
                return
            }
            // Expired exemption flag — clear and fall through to reset
            hasActiveExemption = false
            exemptionExpiresAt = nil
        }

        // Penalty: full Level 1 reset (bestStreak preserved — it's a historical record)
        xp = 0
        level = 1
        currentStreak = 0
        lastCompletionDate = nil
        hardcoreResetDeadline = nil
        health = max(20.0, health - 30.0)
        energy = max(10.0, energy - 40.0)
        discipline = max(10.0, discipline - 50.0)

        // Activate the Rehabilitation Arc — 3 days of easier quests
        isInRecovery = true
        recoveryDaysRemaining = 3
        lastResetDate = now
    }

    /// Called once per day from updateDailyStats() — advances or clears the Rehabilitation Arc.
    func advanceRecoveryIfNeeded() {
        guard isInRecovery else { return }
        recoveryDaysRemaining = max(0, recoveryDaysRemaining - 1)
        if recoveryDaysRemaining == 0 {
            isInRecovery = false
        }
    }

    /// Checks if the player has earned a new Exemption Pass milestone and awards one if so.
    /// Call after any streak increment. Max 3 passes stored.
    /// Returns true if a pass was awarded this call.
    @discardableResult
    func checkAndAwardStreakPass() -> Bool {
        // Award a pass every 7 consecutive days (7, 14, 21, …), cap at 3
        guard currentStreak > 0,
              currentStreak % 7 == 0,
              exemptionPassCount < 3 else { return false }
        exemptionPassCount += 1
        return true
    }

    /// Consume an exemption item from inventory and mark the profile as protected.
    /// Returns true if the item was available and consumed.
    @discardableResult
    func activateExemption(durationHours: Int = 24) -> Bool {
        guard exemptionPassCount > 0 else { return false }
        exemptionPassCount -= 1
        hasActiveExemption = true
        exemptionExpiresAt = Calendar.current.date(byAdding: .hour, value: durationHours, to: Date())
        return true
    }
    
    // MARK: - RPG Stat System
    
    func updateDailyStats() {
        let now = Date()
        let calendar = Calendar.current
        
        // Only update once per day
        guard !calendar.isDate(lastStatUpdate, inSameDayAs: now) else { return }
        
        // Reset daily counters FIRST so stats are computed from fresh values
        resetDailyCounters()

        // Update stats based on real health data
        updateStatsFromHealthData()

        // Decay stats over time if no activity
        applyDailyDecay()

        // Advance Rehabilitation Arc countdown
        advanceRecoveryIfNeeded()
        
        lastStatUpdate = now
    }
    
    private func updateStatsFromHealthData() {
        // STRENGTH: Based on BMI, body composition, and resistance training
        let optimalBMI: Double = 22.5
        let bmiDeviation = abs(bmi - optimalBMI) / optimalBMI
        let bmiMultiplier = max(0.5, 1.0 - bmiDeviation) // Penalize unhealthy BMI
        
        let strengthFromBMI = 50.0 + (bodyFatPercentage < 15 ? 20.0 : 0.0) + (bodyFatPercentage > 30 ? -15.0 : 0.0)
        let targetStrength = strengthFromBMI * bmiMultiplier
        adjustStatToTarget(\.strength, target: targetStrength, maxDailyChange: 2.0)
        
        // ENDURANCE: Based on VO2 max, resting heart rate, and cardio activity
        let vo2MaxScore = min(100, (vo2Max / 60.0) * 100) // 60 ml/kg/min = excellent
        let heartRateScore = max(0, 100 - Double(restingHeartRate - 40)) // 40 BPM = perfect
        let enduranceTarget = (vo2MaxScore + heartRateScore) / 2
        adjustStatToTarget(\.endurance, target: enduranceTarget, maxDailyChange: 2.0)
        
        // HEALTH: Based on overall health metrics
        let healthTarget = calculateOverallHealthScore()
        adjustStatToTarget(\.health, target: healthTarget, maxDailyChange: 3.0)
        
        // ENERGY: Based on sleep, activity, and recovery
        let sleepScore = min(100, max(0, (sleepHours / 8.0) * 100 * sleepEfficiency))
        let activityScore = min(100, Double(dailyActiveCalories) / Double(dailyActiveCaloriesGoal) * 100)
        let energyTarget = (sleepScore + activityScore) / 2
        adjustStatToTarget(\.energy, target: energyTarget, maxDailyChange: 5.0)
        
        // FOCUS: Based on mindfulness, screen time, and sleep quality
        let mindfulnessScore = min(50, Double(mindfulnessMinutesToday) * 2.5) // 20 min = 50 points
        let screenTimeScore = max(0, 50 - (screenTimeToday * 5)) // Penalize excessive screen time
        let sleepQualityScore = sleepEfficiency * 50
        let focusTarget = mindfulnessScore + screenTimeScore + sleepQualityScore
        adjustStatToTarget(\.focus, target: focusTarget, maxDailyChange: 3.0)
        
        // DISCIPLINE: Based on consistency in meeting goals
        let stepsGoalMet = dailySteps >= dailyStepsGoal ? 20.0 : 0.0
        let caloriesGoalMet = dailyActiveCalories >= dailyActiveCaloriesGoal ? 20.0 : 0.0
        let workoutConsistency = weeklyWorkoutMinutes >= weeklyWorkoutGoal ? 30.0 : 0.0
        let hydrationConsistency = waterIntake >= 8 ? 15.0 : 0.0
        let sleepConsistency = (sleepHours >= 7 && sleepHours <= 9) ? 15.0 : 0.0
        
        let disciplineTarget = stepsGoalMet + caloriesGoalMet + workoutConsistency + hydrationConsistency + sleepConsistency
        adjustStatToTarget(\.discipline, target: disciplineTarget, maxDailyChange: 4.0)
    }
    
    private func calculateOverallHealthScore() -> Double {
        var score: Double = 50 // Base score
        
        // BMI Assessment
        let optimalBMI: Double = 22.5
        let bmiScore: Double
        if bmi >= 18.5 && bmi <= 25 {
            bmiScore = 25 - abs(bmi - optimalBMI) * 2
        } else {
            bmiScore = max(0, 25 - abs(bmi - optimalBMI) * 3)
        }
        score += bmiScore
        
        // Cardiovascular Health
        let restingHRScore = max(0, 25 - (Double(restingHeartRate - 60) * 0.5))
        score += restingHRScore
        
        // Activity Level
        let activityScore = min(25, Double(dailyActiveCalories) / Double(dailyActiveCaloriesGoal) * 25)
        score += activityScore
        
        // Sleep Quality
        let sleepScore = sleepHours >= 7 ? min(15, sleepHours * sleepEfficiency * 2) : max(0, sleepHours * sleepEfficiency * 2)
        score += sleepScore
        
        // Nutrition Penalties
        if dailySugarIntake > 50 { score -= 5 } // High sugar penalty
        if alcoholUnitsThisWeek > 14 { score -= 10 } // Excessive alcohol penalty
        if dailyFiberIntake < 25 { score -= 3 } // Low fiber penalty
        
        // Hydration
        score += min(10, Double(waterIntake) * 1.25)
        
        return max(0, min(100, score))
    }
    
    private func adjustStatToTarget(_ keyPath: ReferenceWritableKeyPath<Profile, Double>, target: Double, maxDailyChange: Double) {
        let currentValue = self[keyPath: keyPath]
        let difference = target - currentValue
        let change = max(-maxDailyChange, min(maxDailyChange, difference * 0.1)) // 10% of difference, capped
        
        self[keyPath: keyPath] = max(0.0, min(100.0, currentValue + change))
    }
    
    private func resetDailyCounters() {
        dailySteps = 0
        dailyActiveCalories = 0
        waterIntake = 0
        dailyProteinIntake = 0
        dailyFiberIntake = 0
        dailySugarIntake = 0
        screenTimeToday = 0
        mindfulnessMinutesToday = 0
        stairFlightsClimbed = 0
        
        // Weekly counters (reset on Sunday)
        let calendar = Calendar.current
        if calendar.component(.weekday, from: Date()) == 1 { // Sunday
            weeklyWorkoutMinutes = 0
            alcoholUnitsThisWeek = 0
        }
    }
    
    private func applyDailyDecay() {
        // Natural stat decay to encourage consistent activity
        adjustStat(\.health, by: -2.0)
        adjustStat(\.energy, by: -3.0)
        adjustStat(\.strength, by: -1.0)
        adjustStat(\.endurance, by: -1.0)
        adjustStat(\.focus, by: -1.5)
        
        // Check for severe penalties
        let hoursSinceLastMeal = lastMealTime?.timeIntervalSinceNow ?? -28800 // 8 hours default
        if hoursSinceLastMeal < -43200 { // 12+ hours without food
            adjustStat(\.health, by: -10.0)
            adjustStat(\.energy, by: -15.0)
        }
        
        if waterIntake < 4 { // Less than 4 glasses yesterday
            adjustStat(\.health, by: -5.0)
            adjustStat(\.energy, by: -8.0)
        }
        
        if sleepHours < 6 {
            adjustStat(\.health, by: -8.0)
            adjustStat(\.energy, by: -12.0)
            adjustStat(\.focus, by: -10.0)
        }
    }
    
    func recordWorkout(type: WorkoutType, duration: Int) {
        lastWorkoutTime = Date()

        // Level-tier scaling: higher levels have denser muscle/cardio adaptation curves,
        // so they need more volume to move stats — but discipline and focus scale up instead.
        // Tier E (1-5): full multiplier, easy gains
        // Tier D (6-15): 90% — base gains start tapering
        // Tier C (16-30): 80%
        // Tier B (31-50): 70% — veteran, must work harder for marginal gains
        // Tier A (51-80): 60%
        // Tier S (81+):   50% — elite diminishing returns
        let tierMultiplier: Double
        switch level {
        case 1...5:   tierMultiplier = 1.0
        case 6...15:  tierMultiplier = 0.9
        case 16...30: tierMultiplier = 0.8
        case 31...50: tierMultiplier = 0.7
        case 51...80: tierMultiplier = 0.6
        default:      tierMultiplier = 0.5
        }
        let d = Double(duration) * tierMultiplier

        switch type {
        case .strength:
            adjustStat(\.strength, by: d * 0.5)
            adjustStat(\.endurance, by: d * 0.2)
            adjustStat(\.discipline, by: 2.0 + Double(level) * 0.05) // discipline keeps scaling
        case .cardio:
            adjustStat(\.endurance, by: d * 0.8)
            adjustStat(\.strength, by: d * 0.1)
            adjustStat(\.discipline, by: 2.0 + Double(level) * 0.05)
        case .flexibility:
            adjustStat(\.health, by: d * 0.3)
            adjustStat(\.focus, by: d * 0.2 + Double(level) * 0.03) // focus scales with level
            adjustStat(\.discipline, by: 1.5 + Double(level) * 0.04)
        case .mixed:
            adjustStat(\.strength, by: d * 0.3)
            adjustStat(\.endurance, by: d * 0.4)
            adjustStat(\.health, by: d * 0.2)
            adjustStat(\.discipline, by: 2.5 + Double(level) * 0.05)
        }

        // General workout benefits — scale slightly with tier
        adjustStat(\.health, by: 3.0 * tierMultiplier)
        adjustStat(\.energy, by: 5.0 * tierMultiplier)
    }
    
    func recordMeal(healthiness: MealHealthiness) {
        lastMealTime = Date()

        // Each meal nudges multiple stats. Magnitudes are deliberately small so
        // that logging many items in a day moves stats meaningfully but cannot
        // pin them to 0 or 100 from a single meal.
        switch healthiness {
        case .veryHealthy:   // grade A
            adjustStat(\.health,     by:  4.0)
            adjustStat(\.energy,     by:  3.0)
            adjustStat(\.strength,   by:  1.0) // protein/micronutrient support
            adjustStat(\.endurance,  by:  1.0)
            adjustStat(\.focus,      by:  1.0)
            adjustStat(\.discipline, by:  0.5)
        case .healthy:       // grade B
            adjustStat(\.health,     by:  2.0)
            adjustStat(\.energy,     by:  1.5)
            adjustStat(\.strength,   by:  0.5)
            adjustStat(\.endurance,  by:  0.5)
            adjustStat(\.focus,      by:  0.5)
            adjustStat(\.discipline, by:  0.25)
        case .neutral:       // grade C
            adjustStat(\.health,     by:  0.5)
            adjustStat(\.energy,     by:  0.5)
            adjustStat(\.discipline, by:  0.25)
        case .unhealthy:     // grade D
            adjustStat(\.health,     by: -1.5)
            adjustStat(\.energy,     by: -1.0)
            adjustStat(\.focus,      by: -0.5)
            adjustStat(\.endurance,  by: -0.5)
        case .veryUnhealthy: // grade F
            adjustStat(\.health,     by: -3.5)
            adjustStat(\.energy,     by: -2.5)
            adjustStat(\.focus,      by: -1.5)
            adjustStat(\.endurance,  by: -1.5)
            adjustStat(\.strength,   by: -0.5)
        }
    }
    
    func recordWaterIntake() {
        waterIntake += 1
        
        if waterIntake <= 8 { // Don't over-reward excessive water
            adjustStat(\.health, by: 1.0)
            adjustStat(\.energy, by: 0.5)
        }
    }
    
    func recordSleep(hours: Double) {
        sleepHours = hours
        
        if hours >= 7 && hours <= 9 {
            adjustStat(\.health, by: 5.0)
            adjustStat(\.energy, by: 15.0)
            adjustStat(\.focus, by: 8.0)
        } else if hours >= 6 && hours < 7 {
            adjustStat(\.health, by: 2.0)
            adjustStat(\.energy, by: 8.0)
            adjustStat(\.focus, by: 4.0)
        } else if hours < 6 {
            adjustStat(\.health, by: -5.0)
            adjustStat(\.energy, by: -10.0)
            adjustStat(\.focus, by: -8.0)
        } else if hours > 9 {
            adjustStat(\.energy, by: -3.0) // Oversleeping penalty
        }
    }
    
    func recordMeditation(minutes: Int) {
        self.mindfulnessMinutesToday += minutes
        adjustStat(\.focus, by: Double(minutes) * 0.8)
        adjustStat(\.health, by: Double(minutes) * 0.3)
        adjustStat(\.discipline, by: 1.5)
    }
    
    func adjustStat(_ keyPath: ReferenceWritableKeyPath<Profile, Double>, by amount: Double) {
        self[keyPath: keyPath] = max(0.0, min(100.0, self[keyPath: keyPath] + amount))
    }
    
    // MARK: - Nutrition Tracking
    func updateNutritionFromFoodEntries(_ entries: [FoodEntry]) {
        // Reset daily nutrition counters
        dailyProteinIntake = 0.0
        dailyFiberIntake = 0.0
        dailySugarIntake = 0.0
        
        // Sum up from all food entries for today
        for entry in entries {
            dailyProteinIntake += entry.totalProtein
            dailyFiberIntake += entry.totalFiber
            if let fi = entry.foodItem {
                dailySugarIntake += fi.sugar * (entry.unit == .grams ? entry.quantity / 100.0 : (entry.quantity * fi.servingSize / 100.0))
            }
        }
        
        // Update health stat based on nutrition quality
        if dailyProteinIntake >= 50 { // Good protein intake
            adjustStat(\.health, by: 0.5)
        }
        
        if dailyFiberIntake >= 25 { // Adequate fiber
            adjustStat(\.health, by: 0.5)
        }
        
        if dailySugarIntake > 50 { // Too much sugar
            adjustStat(\.health, by: -0.5)
            adjustStat(\.energy, by: -0.3)
        }
    }
    
    private func boostAllStats(by amount: Double) {
        adjustStat(\.health, by: amount)
        adjustStat(\.energy, by: amount)
        adjustStat(\.strength, by: amount)
        adjustStat(\.endurance, by: amount)
        adjustStat(\.focus, by: amount)
        adjustStat(\.discipline, by: amount)
    }
}

enum WorkoutType: String, CaseIterable, Identifiable, Codable {
    case strength = "strength"
    case cardio = "cardio"
    case flexibility = "flexibility"
    case mixed = "mixed"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .flexibility: return "Flexibility"
        case .mixed: return "Mixed"
        }
    }
    
    var icon: String {
        switch self {
        case .strength: return "dumbbell"
        case .cardio: return "heart"
        case .flexibility: return "figure.yoga"
        case .mixed: return "figure.mixed.cardio"
        }
    }
}

enum MealHealthiness: String, CaseIterable, Identifiable {
    case veryHealthy = "veryHealthy"
    case healthy = "healthy"
    case neutral = "neutral"
    case unhealthy = "unhealthy"
    case veryUnhealthy = "veryUnhealthy"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .veryHealthy: return "Very Healthy"
        case .healthy: return "Healthy"
        case .neutral: return "Neutral"
        case .unhealthy: return "Unhealthy"
        case .veryUnhealthy: return "Very Unhealthy"
        }
    }
    
    var color: Color {
        switch self {
        case .veryHealthy: return .green
        case .healthy: return .mint
        case .neutral: return .yellow
        case .unhealthy: return .orange
        case .veryUnhealthy: return .red
        }
    }
}

enum QuestType: String, Codable, CaseIterable, Identifiable {
    case oneTime = "oneTime"
    case daily
    case weekly
    case custom

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .oneTime: return .blue
        case .daily:   return .orange
        case .weekly:  return .purple
        case .custom:  return .cyan
        }
    }

    var displayName: String {
        switch self {
        case .oneTime: return "One Time"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .custom:  return "Custom"
        }
    }
}

enum StatInfluence {
    case positive, neutral, negative
    
    var color: Color {
        switch self {
        case .positive: return .green
        case .neutral: return .yellow
        case .negative: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .positive: return "arrow.up.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .negative: return "arrow.down.circle.fill"
        }
    }
}

@Model
final class Quest {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var type: QuestType = QuestType.daily
    var createdAt: Date = Date()
    var dueDate: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    var repeatDays: [Int] = []
    var xpReward: Int = 20
    var creditReward: Int = 0
    var dateTag: Date = Date()
    var isUserCreated: Bool = false
    var statTarget: String?
    /// Encodes how the quest is verified automatically. Format:
    ///   "steps:10000"       — complete when HealthKit steps >= target
    ///   "calories:400"      — complete when active calories >= target
    ///   "workout:strength|cardio|flexibility|mixed|any" — complete when matching workout is logged
    ///   "sleep:8"           — complete when sleep hours >= target
    ///   "water:6"           — complete when water glasses logged today >= count
    ///   "meditation:10"     — complete when mindfulness minutes today >= target
    ///   "meals:2"           — complete when food entries logged today >= count
    ///   "discipline_check"  — complete when 1+ meal logged AND 1+ other quest completed
    ///   "manual"            — user taps to confirm (default for system quests)
    var completionCondition: String?

    init(title: String, details: String = "", type: QuestType = .daily, createdAt: Date = Date(), dueDate: Date? = nil, isCompleted: Bool = false, completedAt: Date? = nil, repeatDays: [Int] = [], xpReward: Int = 20, creditReward: Int = 0, isUserCreated: Bool = false, statTarget: String? = nil, completionCondition: String? = nil, dateTag: Date = Calendar.current.startOfDay(for: Date())) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.type = type
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.repeatDays = repeatDays
        self.xpReward = xpReward
        self.creditReward = creditReward
        self.isUserCreated = isUserCreated
        self.statTarget = statTarget
        self.completionCondition = completionCondition
        self.dateTag = dateTag
    }
}

// MARK: - Food Tracking Models

@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?

    // Nutritional info per 100g or per serving
    var caloriesPer100g: Double = 0.0
    var servingSize: Double = 100.0
    var caloriesPerServing: Double = 0.0

    // Macronutrients (per 100g)
    var carbohydrates: Double = 0.0
    var protein: Double = 0.0
    var fat: Double = 0.0
    var fiber: Double = 0.0
    var sugar: Double = 0.0
    var sodium: Double = 0.0

    // Micronutrients (per 100g) — 0 = not available
    var potassiumMg: Double = 0.0
    var calciumMg: Double = 0.0
    var ironMg: Double = 0.0
    var magnesiumMg: Double = 0.0
    var zincMg: Double = 0.0
    var vitaminCMg: Double = 0.0    // Ascorbic acid
    var vitaminB12Mcg: Double = 0.0 // Cobalamin (mcg)
    var vitaminDMcg: Double = 0.0   // D3 (mcg)
    var cholesterolMg: Double = 0.0
    var saturatedFatG: Double = 0.0

    // Diet compatibility tags. Populated from the foods-proxy backend or backfilled
    // from category/macro heuristics. Defaults represent "unknown / safe assumption."
    var containsMeat: Bool = false      // beef, pork, poultry, etc.
    var containsFish: Bool = false      // any fish or seafood
    var containsDairy: Bool = false     // milk, cheese, yogurt, butter
    var containsEggs: Bool = false      // any whole eggs or egg ingredients
    var containsGluten: Bool = false    // wheat, barley, rye, malt
    var containsAlcohol: Bool = false   // for halal compliance
    var isHalalCertified: Bool = false  // explicit halal certification

    /// Nutrition score 0–100 and A–F grade (per 100 kcal basis, Nutri-Score inspired).
    /// Positive points: protein, fiber, potassium, calcium, iron, vitamins.
    /// Negative points: sugar, saturated fat, sodium, calories.
    var nutritionScore: Int {
        guard caloriesPer100g > 0 else { return 0 }
        var score = 50 // baseline

        // Positive nutrients (per 100 kcal)
        let kcal = max(1, caloriesPer100g)
        score += min(15, Int(protein / kcal * 100 * 1.5))       // protein density
        score += min(10, Int(fiber / kcal * 100 * 3))            // fiber density
        if potassiumMg > 0  { score += min(5, Int(potassiumMg / kcal * 0.5)) }
        if calciumMg > 0    { score += min(5, Int(calciumMg / kcal * 0.3)) }
        if ironMg > 0       { score += min(5, Int(ironMg / kcal * 8)) }
        if vitaminCMg > 0   { score += min(5, Int(vitaminCMg / kcal * 2)) }

        // Negative nutrients
        score -= min(20, Int(sugar / kcal * 100 * 2))            // sugar density
        score -= min(15, Int(saturatedFatG / kcal * 100 * 3))    // sat fat density
        score -= min(10, Int(sodium / kcal * 0.3))               // sodium
        if caloriesPer100g > 400 { score -= 5 }                  // calorie-dense processed foods

        return max(0, min(100, score))
    }

    var nutritionGrade: String {
        switch nutritionScore {
        case 80...: return "A"
        case 65..<80: return "B"
        case 50..<65: return "C"
        case 35..<50: return "D"
        default:      return "F"
        }
    }

    /// Returns a 0–100 score aligned to the player's fitness goal.
    /// Weights protein, carbs, and fat differently based on the goal.
    func goalAlignedScore(for goal: FitnessGoal) -> Int {
        guard caloriesPer100g > 0 else { return nutritionScore }
        let kcal = max(1, caloriesPer100g)

        // Base from objective score
        var score = Double(nutritionScore)

        switch goal {
        case .buildMuscle:
            // Reward high protein density; penalise saturated fat
            let proteinDensity = min(20.0, protein / kcal * 100 * 2.0)
            let satPenalty = min(10.0, saturatedFatG / kcal * 100 * 2.0)
            score += proteinDensity - satPenalty

        case .loseFat:
            // Reward fiber and protein; penalise sugar and total calories
            let fiberBonus = min(15.0, fiber / kcal * 100 * 3.0)
            let proteinBonus = min(10.0, protein / kcal * 100 * 1.0)
            let sugarPenalty = min(20.0, sugar / kcal * 100 * 3.0)
            let calDensityPenalty = caloriesPer100g > 300 ? 10.0 : 0.0
            score += fiberBonus + proteinBonus - sugarPenalty - calDensityPenalty

        case .endurance:
            // Reward complex carbs and low sugar; mild protein bonus
            let carbBonus = min(15.0, carbohydrates / kcal * 100 * 1.0)
            let sugarPenalty = min(10.0, sugar / kcal * 100 * 2.0)
            score += carbBonus - sugarPenalty

        case .generalHealth:
            // Reward micronutrient density; penalise sodium and sat fat
            let microBonus = min(15.0, (potassiumMg + calciumMg + ironMg) / kcal * 0.1)
            let sodiumPenalty = min(10.0, sodium / kcal * 0.2)
            score += microBonus - sodiumPenalty
        }

        // NOVA penalty: ultra-processed foods lose 10–20 points
        if novaGroup == 4 { score -= 20 }
        else if novaGroup == 3 { score -= 10 }

        // Additive risk penalty
        score -= Double(additiveRiskLevel) * 5

        return max(0, min(100, Int(score.rounded())))
    }

    /// Returns whether this food item is compatible with the given diet.
    /// Returns `.compliant`, `.caution`, or `.notCompliant` based on the tags
    /// and macro thresholds. Used by the DietComplianceBadge UI.
    func dietCompliance(for diet: DietType) -> DietCompliance {
        switch diet {
        case .none:
            return .compliant
        case .vegetarian:
            if containsMeat || containsFish { return .notCompliant(reason: "Contains meat or fish") }
            return .compliant
        case .vegan:
            if containsMeat || containsFish { return .notCompliant(reason: "Contains meat or fish") }
            if containsDairy { return .notCompliant(reason: "Contains dairy") }
            if containsEggs { return .notCompliant(reason: "Contains eggs") }
            return .compliant
        case .pescatarian:
            if containsMeat { return .notCompliant(reason: "Contains meat") }
            return .compliant
        case .keto:
            // Threshold: under 10g net carbs per 100g is keto-friendly
            let netCarbs = max(0, carbohydrates - fiber)
            if netCarbs <= 5 { return .compliant }
            if netCarbs <= 10 { return .caution(reason: "Moderate carbs (\(Int(netCarbs))g per 100g)") }
            return .notCompliant(reason: "Too high in carbs (\(Int(netCarbs))g per 100g)")
        case .halal:
            if !isHalalCertified && containsMeat {
                return .caution(reason: "Meat — verify halal certification")
            }
            if containsAlcohol { return .notCompliant(reason: "Contains alcohol") }
            return .compliant
        case .glutenFree:
            if containsGluten { return .notCompliant(reason: "Contains gluten") }
            return .compliant
        case .lactoseFree:
            if containsDairy { return .notCompliant(reason: "Contains dairy / lactose") }
            return .compliant
        }
    }

    /// Maps the goal-aligned letter grade to a MealHealthiness bucket so that
    /// logging this food applies the right RPG stat adjustments.
    func mealHealthiness(for goal: FitnessGoal) -> MealHealthiness {
        switch goalAlignedGrade(for: goal) {
        case "A": return .veryHealthy
        case "B": return .healthy
        case "C": return .neutral
        case "D": return .unhealthy
        default:  return .veryUnhealthy
        }
    }

    /// Goal-aligned grade letter.
    func goalAlignedGrade(for goal: FitnessGoal) -> String {
        let s = goalAlignedScore(for: goal)
        switch s {
        case 80...: return "A"
        case 65..<80: return "B"
        case 50..<65: return "C"
        case 35..<50: return "D"
        default:      return "F"
        }
    }

    // Categories
    var category: FoodCategory = FoodCategory.other
    var isCustom: Bool = true
    var isVerified: Bool = false

    /// Source of the nutrition data: "USDA", "OpenFoodFacts", "User", or "" (unknown).
    var dataSource: String = ""

    /// NOVA food processing group (1–4). 0 = unknown.
    /// 1=Unprocessed, 2=Culinary ingredients, 3=Processed, 4=Ultra-processed
    var novaGroup: Int = 0

    /// Additive risk level from Open Food Facts ingredient analysis.
    /// 0=none/unknown, 1=low risk, 2=moderate risk, 3=high risk
    var additiveRiskLevel: Int = 0

    var createdAt: Date = Date()
    var lastUsed: Date?
    var isFavorite: Bool = false

    // Inverses required by CloudKit — must exist for all relationships pointing at FoodItem
    @Relationship var entries: [FoodEntry]?
    @Relationship var mealItems: [CustomMealItem]?

    init(name: String, brand: String? = nil, barcode: String? = nil, caloriesPer100g: Double, servingSize: Double = 100, carbohydrates: Double = 0, protein: Double = 0, fat: Double = 0, fiber: Double = 0, sugar: Double = 0, sodium: Double = 0, category: FoodCategory = .other, isCustom: Bool = true) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.caloriesPer100g = caloriesPer100g
        self.servingSize = servingSize
        self.caloriesPerServing = (caloriesPer100g * servingSize) / 100
        self.carbohydrates = carbohydrates
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.category = category
        self.isCustom = isCustom
        self.isVerified = !isCustom
        self.createdAt = Date()
        self.lastUsed = nil
    }
}

@Model
final class FoodEntry {
    var id: UUID = UUID()
    // CloudKit sync requires relationships to be optional and have inverses.
    @Relationship(inverse: \FoodItem.entries) var foodItem: FoodItem?
    var quantity: Double = 0.0
    var unit: FoodUnit = FoodUnit.grams
    var meal: MealType = MealType.lunch
    var dateConsumed: Date = Date()
    var notes: String?

    // Computed nutritional values — guard against nil foodItem during sync
    var totalCalories: Double {
        guard let foodItem else { return 0 }
        return unit == .grams ?
            (foodItem.caloriesPer100g * quantity / 100.0) :
            (foodItem.caloriesPerServing * quantity)
    }

    var totalCarbs: Double {
        guard let foodItem else { return 0 }
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.carbohydrates * multiplier
    }

    var totalProtein: Double {
        guard let foodItem else { return 0 }
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.protein * multiplier
    }

    var totalFat: Double {
        guard let foodItem else { return 0 }
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.fat * multiplier
    }

    var totalFiber: Double {
        guard let foodItem else { return 0 }
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.fiber * multiplier
    }

    // Micronutrient totals (scaled by quantity)
    private var microMultiplier: Double {
        guard let foodItem else { return 0 }
        return unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
    }
    var totalPotassium: Double  { (foodItem?.potassiumMg  ?? 0) * microMultiplier }
    var totalCalcium: Double    { (foodItem?.calciumMg    ?? 0) * microMultiplier }
    var totalIron: Double       { (foodItem?.ironMg       ?? 0) * microMultiplier }
    var totalMagnesium: Double  { (foodItem?.magnesiumMg  ?? 0) * microMultiplier }
    var totalZinc: Double       { (foodItem?.zincMg       ?? 0) * microMultiplier }
    var totalVitaminC: Double   { (foodItem?.vitaminCMg   ?? 0) * microMultiplier }
    var totalVitaminB12: Double { (foodItem?.vitaminB12Mcg ?? 0) * microMultiplier }
    var totalVitaminD: Double   { (foodItem?.vitaminDMcg  ?? 0) * microMultiplier }
    var totalCholesterol: Double{ (foodItem?.cholesterolMg ?? 0) * microMultiplier }
    var totalSaturatedFat: Double { (foodItem?.saturatedFatG ?? 0) * microMultiplier }

    init(foodItem: FoodItem, quantity: Double, unit: FoodUnit = .grams, meal: MealType, dateConsumed: Date = Date(), notes: String? = nil) {
        self.id = UUID()
        self.foodItem = foodItem
        self.quantity = quantity
        self.unit = unit
        self.meal = meal
        self.dateConsumed = dateConsumed
        self.notes = notes
        foodItem.lastUsed = Date()
    }
}

@Model
final class CustomMeal {
    var id: UUID = UUID()
    var name: String = ""
    var details: String?
    @Relationship(deleteRule: .cascade, inverse: \CustomMealItem.meal) var foodItems: [CustomMealItem]?
    var category: MealType = MealType.lunch
    var createdAt: Date = Date()
    var lastUsed: Date?
    var isFavorite: Bool = false
    
    // Computed nutritional totals — guard against nil foodItem during CloudKit sync
    var totalCalories: Double {
        (foodItems ?? []).reduce(0) { sum, item in
            guard let fi = item.foodItem else { return sum }
            let calories = item.unit == .grams ?
                (fi.caloriesPer100g * item.quantity / 100.0) :
                (fi.caloriesPerServing * item.quantity)
            return sum + calories
        }
    }

    var totalCarbs: Double {
        (foodItems ?? []).reduce(0) { sum, item in
            guard let fi = item.foodItem else { return sum }
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * fi.servingSize / 100.0)
            return sum + (fi.carbohydrates * multiplier)
        }
    }

    var totalProtein: Double {
        (foodItems ?? []).reduce(0) { sum, item in
            guard let fi = item.foodItem else { return sum }
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * fi.servingSize / 100.0)
            return sum + (fi.protein * multiplier)
        }
    }

    var totalFat: Double {
        (foodItems ?? []).reduce(0) { sum, item in
            guard let fi = item.foodItem else { return sum }
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * fi.servingSize / 100.0)
            return sum + (fi.fat * multiplier)
        }
    }

    init(name: String, details: String? = nil, foodItems: [CustomMealItem] = [], category: MealType = .lunch) {
        self.id = UUID()
        self.name = name
        self.details = details
        self.foodItems = foodItems
        self.category = category
        self.createdAt = Date()
        self.lastUsed = nil
        self.isFavorite = false
    }
}

@Model final class CustomMealItem {
    var id: UUID = UUID()
    @Relationship(inverse: \FoodItem.mealItems) var foodItem: FoodItem?
    var meal: CustomMeal?   // inverse of CustomMeal.foodItems — required by CloudKit
    var quantity: Double = 0.0
    var unit: FoodUnit = FoodUnit.grams

    init(foodItem: FoodItem, quantity: Double, unit: FoodUnit) {
        self.id = UUID()
        self.foodItem = foodItem
        self.quantity = quantity
        self.unit = unit
    }
}

enum FoodCategory: String, CaseIterable, Codable {
    case fruits = "fruits"
    case vegetables = "vegetables"
    case grains = "grains"
    case protein = "protein"
    case dairy = "dairy"
    case fats = "fats"
    case beverages = "beverages"
    case snacks = "snacks"
    case desserts = "desserts"
    case condiments = "condiments"
    case packaged = "packaged"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .fruits: return "Fruits"
        case .vegetables: return "Vegetables"
        case .grains: return "Grains & Cereals"
        case .protein: return "Protein"
        case .dairy: return "Dairy"
        case .fats: return "Fats & Oils"
        case .beverages: return "Beverages"
        case .snacks: return "Snacks"
        case .desserts: return "Desserts"
        case .condiments: return "Condiments"
        case .packaged: return "Packaged Foods"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .fruits: return "🍎"
        case .vegetables: return "🥬"
        case .grains: return "🌾"
        case .protein: return "🍗"
        case .dairy: return "🥛"
        case .fats: return "🫒"
        case .beverages: return "🥤"
        case .snacks: return "🍿"
        case .desserts: return "🍰"
        case .condiments: return "🧂"
        case .packaged: return "📦"
        case .other: return "🍽️"
        }
    }
}

enum MealType: String, CaseIterable, Codable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snacks = "snacks"
    
    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }
    
    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .blue
        case .dinner: return .purple
        case .snacks: return .green
        }
    }
    
    var icon: String {
        switch self {
        case .breakfast: return "sun.rise"
        case .lunch: return "sun.max"
        case .dinner: return "moon"
        case .snacks: return "star"
        }
    }
}

enum FoodUnit: String, CaseIterable, Codable {
    case grams = "g"
    case servings = "serving"
    case cups = "cup"
    case tablespoons = "tbsp"
    case teaspoons = "tsp"
    case ounces = "oz"
    case pounds = "lbs"
    case milliliters = "ml"
    case liters = "L"
    case pieces = "piece"
    
    var displayName: String {
        switch self {
        case .grams: return "Grams"
        case .servings: return "Servings"
        case .cups: return "Cups"
        case .tablespoons: return "Tablespoons"
        case .teaspoons: return "Teaspoons"
        case .ounces: return "Ounces"
        case .pounds: return "Pounds"
        case .milliliters: return "Milliliters"
        case .liters: return "Liters"
        case .pieces: return "Pieces"
        }
    }
}

// MARK: - Exercise Cache Model

/// Cached exercise data fetched from the wger REST API.
/// Persisted locally so the app works offline after the first fetch.
@Model
final class ExerciseItem {
    /// wger's own integer ID — stable across API calls.
    var wgerID: Int = 0
    var name: String = ""
    var exerciseDescription: String = ""
    var category: String = ""
    var equipment: [String] = []
    var primaryMuscles: [String] = []
    var secondaryMuscles: [String] = []
    var workoutType: WorkoutType = WorkoutType.mixed
    var cachedAt: Date = Date()

    init(
        wgerID: Int,
        name: String,
        exerciseDescription: String = "",
        category: String = "",
        equipment: [String] = [],
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        workoutType: WorkoutType = .mixed
    ) {
        self.wgerID = wgerID
        self.name = name
        self.exerciseDescription = exerciseDescription
        self.category = category
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.workoutType = workoutType
        self.cachedAt = Date()
    }
}

// MARK: - Recipe Model

/// Recipe model for meal planning and nutrition tracking
/// Used with RecipeAPI for fetching and storing recipes
struct Recipe: Codable, Identifiable {
    let title: String
    let ingredients: String
    let servings: String
    let instructions: String
    
    var id: String { title }
    
    // Computed properties for better UX
    var ingredientsList: [String] {
        ingredients.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    var instructionsList: [String] {
        // Split by common instruction separators
        let separators = CharacterSet(charactersIn: ".|")
        return instructions.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    enum CodingKeys: String, CodingKey {
        case title
        case ingredients
        case servings
        case instructions
    }
}

// MARK: - Workout Session Models (Hevy Replacement)

/// A named routine template — the "master" the player builds once and reuses.
/// Lives in SwiftData; cloned into WorkoutSession each time the player starts training.
@Model
final class ActiveRoutine {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    /// Ordered list of exercise IDs (wger IDs) in this routine.
    var exerciseWgerIDs: [Int] = []
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    /// GymEnvironment raw value — used to filter available exercises.
    var gymEnvironmentRaw: String = GymEnvironment.fullGym.rawValue

    var gymEnvironment: GymEnvironment {
        get { GymEnvironment(rawValue: gymEnvironmentRaw) ?? .fullGym }
        set { gymEnvironmentRaw = newValue.rawValue }
    }

    init(name: String, notes: String = "", exerciseWgerIDs: [Int] = [],
         gymEnvironment: GymEnvironment = .fullGym) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.exerciseWgerIDs = exerciseWgerIDs
        self.createdAt = Date()
        self.gymEnvironmentRaw = gymEnvironment.rawValue
    }
}

/// A completed (or in-progress) training session — one instance of a routine.
@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var routineName: String = ""
    var startedAt: Date = Date()
    var finishedAt: Date?
    var totalVolumeKg: Double = 0.0   // sum of (weight × reps) for all sets
    var durationMinutes: Int = 0
    var xpAwarded: Int = 0
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.session) var sets: [ExerciseSet]?

    var isComplete: Bool { finishedAt != nil }

    /// Duration as a display string, e.g. "42 min"
    var durationDisplay: String {
        durationMinutes > 0 ? "\(durationMinutes) min" : "In Progress"
    }

    init(routineName: String) {
        self.id = UUID()
        self.routineName = routineName
        self.startedAt = Date()
    }

    func finish() {
        let now = Date()
        finishedAt = now
        durationMinutes = Int(now.timeIntervalSince(startedAt) / 60)
        totalVolumeKg = (sets ?? []).reduce(0) { $0 + ($1.weightKg * Double($1.reps)) }
        // XP = 1 pt per 10 kg of volume, capped to encourage quality over spam
        xpAwarded = min(500, Int(totalVolumeKg / 10))
    }
}

/// A single logged set within a WorkoutSession.
@Model
final class ExerciseSet {
    var id: UUID = UUID()
    var exerciseName: String = ""
    var exerciseWgerID: Int = 0
    var setNumber: Int = 1
    var weightKg: Double = 0.0
    var reps: Int = 0
    var isWarmUp: Bool = false
    var rpe: Double = 0.0           // Rate of Perceived Exertion 1–10
    var loggedAt: Date = Date()
    // Cardio extras (only populated for cardio sets)
    var paceMinPerKm: Double = 0.0  // 0 = not tracked
    var heartRateZone: Int = 0      // 1-5, 0 = not tracked
    // Superset / circuit flagging
    var isSuperset: Bool = false
    var supersetGroupID: String = "" // same ID = paired exercises in a superset
    var session: WorkoutSession?  // inverse of WorkoutSession.sets — required by CloudKit

    init(exerciseName: String, exerciseWgerID: Int, setNumber: Int,
         weightKg: Double, reps: Int, isWarmUp: Bool = false, rpe: Double = 7.0) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.exerciseWgerID = exerciseWgerID
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmUp = isWarmUp
        self.rpe = rpe
        self.loggedAt = Date()
    }
}

/// Personal record for a given exercise — used by QuestManager for progressive overload.
@Model
final class PersonalRecord {
    var id: UUID = UUID()
    var exerciseWgerID: Int = 0
    var exerciseName: String = ""
    var oneRepMaxKg: Double = 0.0   // Epley formula estimate
    var bestWeightKg: Double = 0.0
    var bestReps: Int = 0
    var achievedAt: Date = Date()

    init(exerciseWgerID: Int, exerciseName: String,
         weightKg: Double, reps: Int) {
        self.id = UUID()
        self.exerciseWgerID = exerciseWgerID
        self.exerciseName = exerciseName
        self.bestWeightKg = weightKg
        self.bestReps = reps
        self.achievedAt = Date()
        // Epley 1RM = weight × (1 + reps/30)
        self.oneRepMaxKg = weightKg * (1.0 + Double(reps) / 30.0)
    }
}

// MARK: - Patrol Route Model (Strava Replacement)

/// A tracked outdoor activity (run, walk, cycle) stored as an encoded polyline.
@Model
final class PatrolRoute {
    var id: UUID = UUID()
    var name: String = "Patrol Route"
    var activityType: PatrolActivityType = PatrolActivityType.run
    var startedAt: Date = Date()
    var finishedAt: Date?
    var distanceMeters: Double = 0.0
    var durationSeconds: Int = 0
    var averagePaceSecondsPerKm: Double = 0.0
    var elevationGainMeters: Double = 0.0
    var xpAwarded: Int = 0
    /// JSON-encoded [CLLocationCoordinate2D] — stored as string for SwiftData compat.
    var encodedCoordinates: String = ""

    var distanceDisplay: String {
        let km = distanceMeters / 1000
        return String(format: "%.2f km", km)
    }

    var paceDisplay: String {
        guard averagePaceSecondsPerKm > 0 else { return "--:--" }
        let mins = Int(averagePaceSecondsPerKm) / 60
        let secs = Int(averagePaceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    init(name: String = "Patrol Route", activityType: PatrolActivityType = .run) {
        self.id = UUID()
        self.name = name
        self.activityType = activityType
        self.startedAt = Date()
    }
}

enum PatrolActivityType: String, Codable, CaseIterable {
    case run = "run"
    case walk = "walk"
    case cycle = "cycle"
    case hike = "hike"

    var displayName: String {
        switch self {
        case .run:   return "Run"
        case .walk:  return "Walk"
        case .cycle: return "Cycle"
        case .hike:  return "Hike"
        }
    }

    var icon: String {
        switch self {
        case .run:   return "figure.run"
        case .walk:  return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .hike:  return "figure.hiking"
        }
    }

    /// XP per km completed
    var xpPerKm: Int {
        switch self {
        case .run:   return 30
        case .walk:  return 15
        case .cycle: return 20
        case .hike:  return 25
        }
    }
}

// MARK: - Inventory & Penalty System

/// An item the player can own in their inventory to block penalties or unlock bonuses.
@Model
final class InventoryItem {
    var id: UUID = UUID()
    var itemType: InventoryItemType = InventoryItemType.hermitMiracleSeed
    var quantity: Int = 0
    var acquiredAt: Date = Date()

    var displayName: String { itemType.displayName }
    var description: String { itemType.description }
    var icon: String { itemType.icon }

    init(itemType: InventoryItemType, quantity: Int = 1) {
        self.id = UUID()
        self.itemType = itemType
        self.quantity = quantity
        self.acquiredAt = Date()
    }
}

enum InventoryItemType: String, Codable, CaseIterable {
    case hermitMiracleSeed      = "hermit_miracle_seed"
    case gateEscapeFragment     = "gate_escape_fragment"
    case demonLordPanacea       = "demon_lord_panacea"
    case pocketGuardianCandy    = "pocket_guardian_candy"
    case equivalentExchangeChalk = "equivalent_exchange_chalk"

    // MARK: Display

    var displayName: String {
        switch self {
        case .hermitMiracleSeed:       return "Hermit's Miracle Seed"
        case .gateEscapeFragment:      return "Gate Escape Fragment"
        case .demonLordPanacea:        return "Demon Lord's Panacea"
        case .pocketGuardianCandy:     return "Pocket Guardian's Candy"
        case .equivalentExchangeChalk: return "Equivalent Exchange Chalk"
        }
    }

    var description: String {
        switch self {
        case .hermitMiracleSeed:
            return "Fully restores all HP stats and nullifies a Level 1 reset. Use before the midnight deadline."
        case .gateEscapeFragment:
            return "Flee a Daily Quest without breaking your streak. One incomplete quest is absolved."
        case .demonLordPanacea:
            return "Doubles HealthKit sleep recovery HP for 24 hours. Clears all active debuffs."
        case .pocketGuardianCandy:
            return "Grants a massive flat XP bonus. The System rewards those who hoard power."
        case .equivalentExchangeChalk:
            return "Rerolls one exercise based on your available equipment. No streak penalty."
        }
    }

    var icon: String {
        switch self {
        case .hermitMiracleSeed:       return "shield.fill"
        case .gateEscapeFragment:      return "arrow.up.right.square.fill"
        case .demonLordPanacea:        return "cross.vial.fill"
        case .pocketGuardianCandy:     return "star.circle.fill"
        case .equivalentExchangeChalk: return "arrow.triangle.2.circlepath"
        }
    }

    var accentColor: String {
        switch self {
        case .hermitMiracleSeed:       return "cyan"
        case .gateEscapeFragment:      return "purple"
        case .demonLordPanacea:        return "green"
        case .pocketGuardianCandy:     return "yellow"
        case .equivalentExchangeChalk: return "orange"
        }
    }

    var category: ItemCategory {
        switch self {
        case .hermitMiracleSeed:       return .exemption
        case .gateEscapeFragment:      return .exemption
        case .demonLordPanacea:        return .restoration
        case .pocketGuardianCandy:     return .statBoost
        case .equivalentExchangeChalk: return .utility
        }
    }

    /// XP cost in the System Shop.
    var shopXPCost: Int {
        switch self {
        case .hermitMiracleSeed:       return 5_000
        case .gateEscapeFragment:      return 2_500
        case .demonLordPanacea:        return 3_000
        case .pocketGuardianCandy:     return 4_000
        case .equivalentExchangeChalk: return 1_500
        }
    }

    /// Whether consuming this item blocks the hardcore Level 1 penalty.
    var blocksLevelReset: Bool {
        self == .hermitMiracleSeed || self == .gateEscapeFragment
    }

    /// Flat XP bonus granted on consumption (0 if not applicable).
    var xpBonus: Int {
        switch self {
        case .pocketGuardianCandy: return 2_000
        default:                   return 0
        }
    }
}

enum ItemCategory: String, Codable {
    case exemption  = "exemption"
    case restoration = "restoration"
    case statBoost  = "stat_boost"
    case utility    = "utility"

    var displayName: String {
        switch self {
        case .exemption:   return "Exemption"
        case .restoration: return "Restoration"
        case .statBoost:   return "Stat Boost"
        case .utility:     return "Utility"
        }
    }

    var badgeColor: String {
        switch self {
        case .exemption:   return "cyan"
        case .restoration: return "green"
        case .statBoost:   return "yellow"
        case .utility:     return "orange"
        }
    }
}

// MARK: - Gym Environment Presets

/// Defines which equipment categories are available in a given gym,
/// mapping directly to wger equipment IDs.
enum PlayerGender: String, Codable, CaseIterable {
    case male   = "male"
    case female = "female"
    case other  = "other"

    var displayName: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
        case .other:  return "Other"
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable {
    case loseFat      = "lose_fat"
    case buildMuscle  = "build_muscle"
    case endurance    = "endurance"
    case generalHealth = "general_health"

    var displayName: String {
        switch self {
        case .loseFat:      return "Lose Fat"
        case .buildMuscle:  return "Build Muscle"
        case .endurance:    return "Improve Endurance"
        case .generalHealth: return "General Health"
        }
    }

    var icon: String {
        switch self {
        case .loseFat:      return "flame.fill"
        case .buildMuscle:  return "dumbbell.fill"
        case .endurance:    return "figure.run"
        case .generalHealth: return "heart.fill"
        }
    }

    var description: String {
        switch self {
        case .loseFat:      return "Cut body fat while preserving muscle"
        case .buildMuscle:  return "Maximize muscle growth and strength"
        case .endurance:    return "Build cardiovascular fitness and stamina"
        case .generalHealth: return "Balanced fitness and well-being"
        }
    }
}

enum GymEnvironment: String, Codable, CaseIterable {
    case fullGym        = "full_gym"
    case planetFitness  = "planet_fitness"
    case laFitness      = "la_fitness"
    case homeGym        = "home_gym"
    case bodyweightOnly = "bodyweight_only"

    var displayName: String {
        switch self {
        case .fullGym:        return "Full Gym"
        case .planetFitness:  return "Planet Fitness"
        case .laFitness:      return "LA Fitness"
        case .homeGym:        return "Home Gym"
        case .bodyweightOnly: return "Bodyweight Only"
        }
    }

    var icon: String {
        switch self {
        case .fullGym:        return "building.2.fill"
        case .planetFitness:  return "p.circle.fill"
        case .laFitness:      return "l.circle.fill"
        case .homeGym:        return "house.fill"
        case .bodyweightOnly: return "figure.mind.and.body"
        }
    }

    /// wger equipment IDs available in this environment.
    /// wger IDs: 1=Barbell, 2=SZ-Bar, 3=Dumbbell, 4=Gym Mat, 5=Swiss Ball,
    /// 6=Pull-up Bar, 7=Cable, 8=Bench, 9=Incline Bench, 10=Kettlebell,
    /// 11=Smith Machine, 12=Resistance Bands, 99=Bodyweight (no equipment)
    var allowedEquipmentIDs: Set<Int> {
        switch self {
        case .fullGym:
            return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99]
        case .planetFitness:
            // No standard barbells (ID 1) — Smith Machine + dumbbells + cables only
            return [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99]
        case .laFitness:
            // Full selection minus SZ-Bar
            return [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99]
        case .homeGym:
            return [1, 3, 4, 5, 6, 8, 10, 12, 99]
        case .bodyweightOnly:
            return [4, 5, 6, 99]
        }
    }
}

// MARK: - Custom Workout Plan helpers
// Defined before the @Model class so their Codable conformances are synthesised
// outside the @MainActor context and can be used freely from nonisolated code.

struct CustomDayPlan: Codable, Sendable {
    var dayName: String = ""
    var focus: String = ""
    var isRest: Bool = false
    var exercises: [CustomPlannedExercise] = []
    var questTitle: String = ""
    var questDetails: String = ""
    var xpReward: Int = 100

    static func restDay(name: String) -> CustomDayPlan {
        CustomDayPlan(dayName: name, focus: "Rest", isRest: true,
                      exercises: [], questTitle: "Active Recovery",
                      questDetails: "Rest day — stretch, walk, hydrate.",
                      xpReward: 50)
    }
}

struct CustomPlannedExercise: Codable, Sendable {
    var name: String = ""
    var sets: Int = 3
    var reps: String = "10"
    var restSeconds: Int = 90
    var notes: String = ""
}

struct CustomPlanNutrition: Sendable {
    var dailyCalories: Int = 2000
    var proteinGrams: Int = 150
    var carbGrams: Int = 200
    var fatGrams: Int = 65
    var waterGlasses: Int = 8
    var mealPrepTips: [String] = []
    var avoidList: [String] = []
}

extension CustomPlanNutrition: Codable {
    private enum CodingKeys: String, CodingKey {
        case dailyCalories, proteinGrams, carbGrams, fatGrams, waterGlasses, mealPrepTips, avoidList
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyCalories = try c.decodeIfPresent(Int.self, forKey: .dailyCalories) ?? 2000
        proteinGrams  = try c.decodeIfPresent(Int.self, forKey: .proteinGrams)  ?? 150
        carbGrams     = try c.decodeIfPresent(Int.self, forKey: .carbGrams)     ?? 200
        fatGrams      = try c.decodeIfPresent(Int.self, forKey: .fatGrams)      ?? 65
        waterGlasses  = try c.decodeIfPresent(Int.self, forKey: .waterGlasses)  ?? 8
        mealPrepTips  = try c.decodeIfPresent([String].self, forKey: .mealPrepTips) ?? []
        avoidList     = try c.decodeIfPresent([String].self, forKey: .avoidList)    ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dailyCalories, forKey: .dailyCalories)
        try c.encode(proteinGrams,  forKey: .proteinGrams)
        try c.encode(carbGrams,     forKey: .carbGrams)
        try c.encode(fatGrams,      forKey: .fatGrams)
        try c.encode(waterGlasses,  forKey: .waterGlasses)
        try c.encode(mealPrepTips,  forKey: .mealPrepTips)
        try c.encode(avoidList,     forKey: .avoidList)
    }
}

// MARK: - Custom Workout Plan (SwiftData)
//
// User-created plans stored locally. Mirrors the AnimeWorkoutPlan shape so the
// same QuestManager / DietView / WorkoutView code can render both interchangeably.
// IDs are prefixed "custom-" to distinguish from anime plan IDs.

@Model
final class CustomWorkoutPlan {
    var id: String = "custom-\(UUID().uuidString)"
    var name: String = ""
    var planDescription: String = ""
    var difficultyRaw: String = "Intermediate"
    var accentColorHex: String = "#5E5CE6"  // stored as hex; converted to Color at runtime
    var iconSymbol: String = "figure.strengthtraining.traditional"
    var createdAt: Date = Date()

    /// JSON-encoded [CustomDayPlan]
    var weeklyScheduleJSON: String = "[]"
    /// JSON-encoded CustomPlanNutrition
    var nutritionJSON: String = "{}"

    /// Whether this plan was generated by Apple Intelligence (vs manual)
    var isAIGenerated: Bool = false

    /// The questionnaire answers used to generate the plan (for display)
    var aiPromptSummary: String = ""

    init(name: String = "", description: String = "") {
        self.id = "custom-\(UUID().uuidString)"
        self.name = name
        self.planDescription = description
    }

    var difficulty: AnimeWorkoutPlan.PlanDifficulty {
        AnimeWorkoutPlan.PlanDifficulty(rawValue: difficultyRaw) ?? .intermediate
    }

    var accentColor: Color {
        Color(hex: accentColorHex) ?? .indigo
    }

    /// Decode the weekly schedule from JSON.
    var weeklySchedule: [CustomDayPlan] {
        get {
            (try? JSONDecoder().decode([CustomDayPlan].self, from: Data(weeklyScheduleJSON.utf8))) ?? []
        }
        set {
            weeklyScheduleJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    /// Decode the nutrition from JSON.
    var nutrition: CustomPlanNutrition {
        get {
            (try? JSONDecoder().decode(CustomPlanNutrition.self, from: Data(nutritionJSON.utf8))) ?? CustomPlanNutrition()
        }
        set {
            nutritionJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    /// Convert to an AnimeWorkoutPlan-compatible value so all existing rendering code works unchanged.
    func asAnimeWorkoutPlan() -> AnimeWorkoutPlan {
        AnimeWorkoutPlan(
            id: id,
            character: name,
            anime: "Custom",
            tagline: isAIGenerated ? "AI-generated for you" : "Your plan",
            description: planDescription,
            difficulty: difficulty,
            accentColor: accentColor,
            iconSymbol: iconSymbol,
            weeklySchedule: weeklySchedule.map { day in
                AnimeWorkoutPlan.DayPlan(
                    dayName: day.dayName,
                    focus: day.focus,
                    isRest: day.isRest,
                    exercises: day.exercises.map { ex in
                        AnimeWorkoutPlan.PlannedExercise(
                            name: ex.name,
                            sets: ex.sets,
                            reps: ex.reps,
                            restSeconds: ex.restSeconds,
                            notes: ex.notes
                        )
                    },
                    questTitle: day.questTitle,
                    questDetails: day.questDetails,
                    xpReward: day.xpReward
                )
            },
            nutrition: AnimeWorkoutPlan.PlanNutrition(
                dailyCalories: nutrition.dailyCalories,
                proteinGrams: nutrition.proteinGrams,
                carbGrams: nutrition.carbGrams,
                fatGrams: nutrition.fatGrams,
                waterGlasses: nutrition.waterGlasses,
                mealPrepTips: nutrition.mealPrepTips,
                avoidList: nutrition.avoidList
            ),
            targetGender: nil  // custom plans are gender-neutral
        )
    }
}

// MARK: - Custom Plan Supporting Types (Codable for JSON storage)

// MARK: - Achievement System

enum AchievementID: String, CaseIterable {
    // Streaks
    case streak3        = "streak_3"
    case streak7        = "streak_7"
    case streak30       = "streak_30"
    case streak100      = "streak_100"
    // Workouts
    case firstWorkout   = "first_workout"
    case workouts10     = "workouts_10"
    case workouts50     = "workouts_50"
    case workouts100    = "workouts_100"
    // Levels
    case level5         = "level_5"
    case level10        = "level_10"
    case level25        = "level_25"
    case level50        = "level_50"
    // Rank ups
    case rankD          = "rank_d"
    case rankC          = "rank_c"
    case rankB          = "rank_b"
    case rankA          = "rank_a"
    case rankS          = "rank_s"
    // Nutrition
    case loggedFood7    = "logged_food_7"
    case waterGoal7     = "water_goal_7"
    // Other
    case earlyBird      = "early_bird"      // workout before 7 am
    case nightOwl       = "night_owl"       // workout after 9 pm

    var title: String {
        switch self {
        case .streak3:      return "On a Roll"
        case .streak7:      return "Week Warrior"
        case .streak30:     return "30-Day Legend"
        case .streak100:    return "Century Streak"
        case .firstWorkout: return "First Blood"
        case .workouts10:   return "Getting Started"
        case .workouts50:   return "Halfway Hero"
        case .workouts100:  return "Centurion"
        case .level5:       return "Rising Star"
        case .level10:      return "Double Digits"
        case .level25:      return "Quarter Century"
        case .level50:      return "Halfway Legend"
        case .rankD:        return "Rank Up: D"
        case .rankC:        return "Rank Up: C"
        case .rankB:        return "Rank Up: B"
        case .rankA:        return "Rank Up: A"
        case .rankS:        return "Rank Up: S"
        case .loggedFood7:  return "Nutrition Nerd"
        case .waterGoal7:   return "Hydration Hero"
        case .earlyBird:    return "Early Bird"
        case .nightOwl:     return "Night Owl"
        }
    }

    var description: String {
        switch self {
        case .streak3:      return "Complete quests 3 days in a row"
        case .streak7:      return "Complete quests 7 days in a row"
        case .streak30:     return "Complete quests 30 days in a row"
        case .streak100:    return "Maintain a 100-day streak"
        case .firstWorkout: return "Log your first workout"
        case .workouts10:   return "Complete 10 workouts"
        case .workouts50:   return "Complete 50 workouts"
        case .workouts100:  return "Complete 100 workouts"
        case .level5:       return "Reach level 5"
        case .level10:      return "Reach level 10"
        case .level25:      return "Reach level 25"
        case .level50:      return "Reach level 50"
        case .rankD:        return "Advance to Rank D"
        case .rankC:        return "Advance to Rank C"
        case .rankB:        return "Advance to Rank B"
        case .rankA:        return "Advance to Rank A"
        case .rankS:        return "Achieve Rank S — the pinnacle"
        case .loggedFood7:  return "Log your food 7 days in a row"
        case .waterGoal7:   return "Hit your water goal 7 days in a row"
        case .earlyBird:    return "Complete a workout before 7 AM"
        case .nightOwl:     return "Complete a workout after 9 PM"
        }
    }

    var icon: String {
        switch self {
        case .streak3:      return "flame"
        case .streak7:      return "flame.fill"
        case .streak30:     return "calendar.badge.checkmark"
        case .streak100:    return "crown.fill"
        case .firstWorkout: return "bolt.fill"
        case .workouts10:   return "figure.strengthtraining.traditional"
        case .workouts50:   return "medal"
        case .workouts100:  return "medal.fill"
        case .level5:       return "star"
        case .level10:      return "star.fill"
        case .level25:      return "star.circle.fill"
        case .level50:      return "rosette"
        case .rankD:        return "d.circle.fill"
        case .rankC:        return "c.circle.fill"
        case .rankB:        return "b.circle.fill"
        case .rankA:        return "a.circle.fill"
        case .rankS:        return "s.circle.fill"
        case .loggedFood7:  return "fork.knife"
        case .waterGoal7:   return "drop.fill"
        case .earlyBird:    return "sunrise.fill"
        case .nightOwl:     return "moon.stars.fill"
        }
    }

    var color: String {
        switch self {
        case .streak3, .streak7:   return "#FF6B35"
        case .streak30, .streak100: return "#FFD700"
        case .firstWorkout:        return "#00FFCC"
        case .workouts10, .workouts50: return "#4A90E2"
        case .workouts100:         return "#7B2FBE"
        case .level5, .level10:    return "#4CAF50"
        case .level25, .level50:   return "#F44336"
        case .rankD:               return "#9E9E9E"
        case .rankC:               return "#2196F3"
        case .rankB:               return "#4CAF50"
        case .rankA:               return "#FF9800"
        case .rankS:               return "#F44336"
        case .loggedFood7:         return "#8BC34A"
        case .waterGoal7:          return "#03A9F4"
        case .earlyBird:           return "#FF9800"
        case .nightOwl:            return "#673AB7"
        }
    }
}

@Model
final class Achievement {
    var id: String = ""
    var unlockedAt: Date = Date()

    var achievementID: AchievementID? { AchievementID(rawValue: id) }

    init(id: AchievementID) {
        self.id = id.rawValue
        self.unlockedAt = Date()
    }
}

// MARK: - Body Measurement

/// A single timestamped body measurement entry (weight + optional measurements).
@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0.0
    // Optional tape measurements in cm
    var chestCm: Double? = nil
    var waistCm: Double? = nil
    var hipsCm: Double? = nil
    var bodyFatPercent: Double? = nil
    var note: String = ""

    init(date: Date = Date(), weightKg: Double, chestCm: Double? = nil, waistCm: Double? = nil, hipsCm: Double? = nil, bodyFatPercent: Double? = nil, note: String = "") {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.bodyFatPercent = bodyFatPercent
        self.note = note
    }
}

// MARK: - Meal Planning

/// A meal planned for a future date (used by MealPlanCalendarView).
@Model
final class PlannedMeal {
    var id: UUID = UUID()
    /// The calendar day this meal is planned for.
    var plannedDate: Date = Date()
    /// Which meal slot (breakfast, lunch, etc.)
    var mealSlot: String = "Lunch"
    /// Free-text description or recipe/food name.
    var title: String = ""
    var notes: String = ""
    /// Optional calorie estimate for planning purposes.
    var estimatedCalories: Int = 0
    var isCompleted: Bool = false

    init(plannedDate: Date, mealSlot: String, title: String, notes: String = "", estimatedCalories: Int = 0) {
        self.id = UUID()
        self.plannedDate = plannedDate
        self.mealSlot = mealSlot
        self.title = title
        self.notes = notes
        self.estimatedCalories = estimatedCalories
        self.isCompleted = false
    }
}

// MARK: - Color hex helper (used by CustomWorkoutPlan)

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Returns a 6-digit hex string (no alpha).
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

// MARK: - Goal Survey enums

enum GoalSurveySplit: String, CaseIterable, Codable, Identifiable {
    case fullBody     = "fullBody"
    case upperLower   = "upperLower"
    case pushPullLegs = "pushPullLegs"
    case broSplit     = "broSplit"
    case custom       = "custom"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fullBody:     return "Full Body"
        case .upperLower:   return "Upper / Lower"
        case .pushPullLegs: return "Push / Pull / Legs"
        case .broSplit:     return "Bro Split"
        case .custom:      return "Custom (I decide each day)"
        }
    }
    var blurb: String {
        switch self {
        case .fullBody:     return "Hit every muscle every session"
        case .upperLower:   return "Two upper-body days, two lower-body days"
        case .pushPullLegs: return "Push, pull, legs — classic 3-way split"
        case .broSplit:     return "One muscle group per day"
        case .custom:       return "Flexible — you pick each day"
        }
    }
}

enum GoalSurveyIntensity: String, CaseIterable, Codable, Identifiable {
    case easy, moderate, intense
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .easy:     return "Easy — Build the habit"
        case .moderate: return "Moderate — Steady gains"
        case .intense:  return "Intense — Push hard"
        }
    }
    var xpMultiplier: Double {
        switch self {
        case .easy: return 0.8
        case .moderate: return 1.0
        case .intense: return 1.3
        }
    }
}

enum GoalSurveyCardio: String, CaseIterable, Codable, Identifiable {
    case none, light, moderate, high
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:     return "None"
        case .light:    return "Light — walks, easy bike"
        case .moderate: return "Moderate — jogging, cycling"
        case .high:     return "High — HIIT, sprints"
        }
    }
    var sessionsPerWeek: Int {
        switch self {
        case .none: return 0
        case .light: return 2
        case .moderate: return 3
        case .high: return 4
        }
    }
}

enum GoalSurveyFocusArea: String, CaseIterable, Codable, Identifiable {
    case arms, chest, back, shoulders, legs, glutes, core, cardio, mobility
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .arms:      return "figure.arms.open"
        case .chest:     return "figure.cross.training"
        case .back:      return "figure.strengthtraining.traditional"
        case .shoulders: return "figure.boxing"
        case .legs:      return "figure.run"
        case .glutes:    return "figure.walk"
        case .core:      return "figure.core.training"
        case .cardio:    return "heart.fill"
        case .mobility:  return "figure.flexibility"
        }
    }
}

extension Profile {
    var goalSurveySplit: GoalSurveySplit? {
        get { GoalSurveySplit(rawValue: goalSurveySplitRaw) }
        set { goalSurveySplitRaw = newValue?.rawValue ?? "" }
    }
    var goalSurveyIntensity: GoalSurveyIntensity? {
        get { GoalSurveyIntensity(rawValue: goalSurveyIntensityRaw) }
        set { goalSurveyIntensityRaw = newValue?.rawValue ?? "" }
    }
    var goalSurveyCardio: GoalSurveyCardio? {
        get { GoalSurveyCardio(rawValue: goalSurveyCardioRaw) }
        set { goalSurveyCardioRaw = newValue?.rawValue ?? "" }
    }
    var goalSurveyFocusAreas: [GoalSurveyFocusArea] {
        get { goalSurveyFocusAreasRaw.compactMap { GoalSurveyFocusArea(rawValue: $0) } }
        set { goalSurveyFocusAreasRaw = newValue.map(\.rawValue) }
    }
}

// MARK: - Diet Preferences (Phase D1)

enum DietType: String, CaseIterable, Codable, Identifiable {
    case none         = "none"
    case vegetarian   = "vegetarian"
    case vegan        = "vegan"
    case pescatarian  = "pescatarian"
    case keto         = "keto"
    case halal        = "halal"
    case glutenFree   = "glutenFree"
    case lactoseFree  = "lactoseFree"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:        return "No restrictions"
        case .vegetarian:  return "Vegetarian"
        case .vegan:       return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .keto:        return "Keto"
        case .halal:       return "Halal"
        case .glutenFree:  return "Gluten-Free"
        case .lactoseFree: return "Lactose-Free"
        }
    }

    /// Short tagline used in the diet picker.
    var tagline: String {
        switch self {
        case .none:        return "Eat anything"
        case .vegetarian:  return "No meat or fish"
        case .vegan:       return "No animal products at all"
        case .pescatarian: return "Vegetarian + fish/seafood"
        case .keto:        return "Very low carb, high fat"
        case .halal:       return "Permitted under Islamic law"
        case .glutenFree:  return "No wheat, barley, rye"
        case .lactoseFree: return "No milk-derived dairy"
        }
    }

    var icon: String {
        switch self {
        case .none:        return "fork.knife"
        case .vegetarian:  return "leaf"
        case .vegan:       return "leaf.fill"
        case .pescatarian: return "fish"
        case .keto:        return "flame"
        case .halal:       return "moon.stars"
        case .glutenFree:  return "exclamationmark.shield"
        case .lactoseFree: return "drop.triangle"
        }
    }
}

extension Profile {
    var dietType: DietType {
        get { DietType(rawValue: dietTypeRaw) ?? .none }
        set { dietTypeRaw = newValue.rawValue }
    }
}

enum DietCompliance: Equatable {
    case compliant
    case caution(reason: String)
    case notCompliant(reason: String)

    var symbolName: String {
        switch self {
        case .compliant:    return "checkmark.seal.fill"
        case .caution:      return "exclamationmark.triangle.fill"
        case .notCompliant: return "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .compliant:    return "Compatible"
        case .caution:      return "Caution"
        case .notCompliant: return "Not compatible"
        }
    }

    var reason: String? {
        switch self {
        case .compliant: return nil
        case .caution(let r): return r
        case .notCompliant(let r): return r
        }
    }
}

// MARK: - Player Class (Phase D-3)

enum PlayerClass: String, CaseIterable, Codable, Identifiable {
    case unselected = "unselected"
    case warrior    = "warrior"
    case ranger     = "ranger"
    case monk       = "monk"
    case sage       = "sage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unselected: return "Unselected"
        case .warrior:    return "Warrior"
        case .ranger:     return "Ranger"
        case .monk:       return "Monk"
        case .sage:       return "Sage"
        }
    }

    var tagline: String {
        switch self {
        case .unselected: return "Pick a path"
        case .warrior:    return "Strength is the foundation"
        case .ranger:     return "Endurance is the journey"
        case .monk:       return "Discipline is the way"
        case .sage:       return "Focus is the answer"
        }
    }

    var description: String {
        switch self {
        case .unselected: return "Choose a class to get a 10% XP bonus on quests that match your path."
        case .warrior:    return "Built for raw power. Warriors gain bonus XP on strength training and progressive overload quests."
        case .ranger:     return "Built for the long run. Rangers gain bonus XP on cardio, steps, and endurance quests."
        case .monk:       return "Built on consistency. Monks gain bonus XP on discipline, streaks, mindfulness, and recovery quests."
        case .sage:       return "Built on awareness. Sages gain bonus XP on focus, deep work, and nutrition tracking quests."
        }
    }

    var icon: String {
        switch self {
        case .unselected: return "questionmark.circle"
        case .warrior:    return "figure.strengthtraining.traditional"
        case .ranger:     return "figure.run"
        case .monk:       return "figure.mind.and.body"
        case .sage:       return "brain.head.profile"
        }
    }

    var bonusStatTarget: String {
        switch self {
        case .unselected: return ""
        case .warrior:    return "strength"
        case .ranger:     return "endurance"
        case .monk:       return "discipline"
        case .sage:       return "focus"
        }
    }

    var color: String {
        switch self {
        case .unselected: return "gray"
        case .warrior:    return "red"
        case .ranger:     return "green"
        case .monk:       return "purple"
        case .sage:       return "cyan"
        }
    }
}

extension Profile {
    var playerClass: PlayerClass {
        get { PlayerClass(rawValue: playerClassRaw) ?? .unselected }
        set { playerClassRaw = newValue.rawValue }
    }
}

extension Profile {
    /// Dragon Ball Z-style "power level" — a single deterministic number
    /// that combines level, all six stats, streak, and lifetime XP into one
    /// summary figure visible on the Home player card and leaderboards.
    var powerLevel: Int {
        let base = Double(level) * 120.0
        let statSum = health + energy + strength + endurance + focus + discipline
        let streakBoost = Double(currentStreak) * 8.0
        let xpBoost = Double(totalXPEarned) / 50.0
        let raw = base + (statSum * 5.0) + streakBoost + xpBoost
        return max(0, Int(raw.rounded()))
    }

    /// Short-formatted power level string — "1,234" or "12.3K" for big numbers.
    var powerLevelFormatted: String {
        let pl = powerLevel
        if pl >= 1000 {
            let k = Double(pl) / 1000.0
            if k >= 100 {
                return String(format: "%.0fK", k)
            } else if k >= 10 {
                return String(format: "%.1fK", k)
            } else {
                return String(format: "%.2fK", k)
            }
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: pl)) ?? "\(pl)"
    }

    /// Qualitative tier label based on power level. Used for flavor text.
    var powerLevelTier: String {
        switch powerLevel {
        case 0..<1000:      return "Trainee"
        case 1000..<3000:   return "Adept"
        case 3000..<6000:   return "Veteran"
        case 6000..<9000:   return "Elite"
        case 9000..<15000:  return "Beyond Elite"
        case 15000..<25000: return "Legendary"
        case 25000..<50000: return "Mythic"
        default:            return "Transcendent"
        }
    }
}

// MARK: - Weekly Boss Raids

@Model
final class WeeklyBoss {
    @Attribute(.unique) var id: UUID = UUID()
    var bossKey: String = ""           // raw enum value of WeeklyBossArchetype
    var weekStartDate: Date = Date()   // Monday 00:00 of the active week
    var maxHP: Int = 100
    var currentHP: Int = 100
    var damageDealt: Int = 0           // monotonic counter — what we use for progress display
    var defeatedAt: Date?              // nil = still alive
    var rewardClaimed: Bool = false
    var createdAt: Date = Date()

    init(bossKey: String, weekStartDate: Date, maxHP: Int) {
        self.id = UUID()
        self.bossKey = bossKey
        self.weekStartDate = weekStartDate
        self.maxHP = maxHP
        self.currentHP = maxHP
        self.damageDealt = 0
        self.defeatedAt = nil
        self.rewardClaimed = false
        self.createdAt = Date()
    }

    var isDefeated: Bool { currentHP <= 0 }
    var progress: Double {
        guard maxHP > 0 else { return 0 }
        return min(1.0, Double(damageDealt) / Double(maxHP))
    }
}

/// The 6 weekly boss themes that rotate. The week-of-year mod 6 picks which
/// boss spawns on a given Monday — deterministic, so different players don't
/// face wildly different challenges.
enum WeeklyBossArchetype: String, CaseIterable {
    case slothDemon       = "sloth_demon"
    case gluttonKing      = "glutton_king"
    case hollowWarrior    = "hollow_warrior"
    case ironSleeper      = "iron_sleeper"
    case witheringSpirit  = "withering_spirit"
    case forsakenDragon   = "forsaken_dragon"

    var displayName: String {
        switch self {
        case .slothDemon:      return "The Sloth Demon"
        case .gluttonKing:     return "The Glutton King"
        case .hollowWarrior:   return "The Hollow Warrior"
        case .ironSleeper:     return "The Iron Sleeper"
        case .witheringSpirit: return "The Withering Spirit"
        case .forsakenDragon:  return "The Forsaken Dragon"
        }
    }

    var flavor: String {
        switch self {
        case .slothDemon:      return "He feeds on stillness. Move, and he weakens."
        case .gluttonKing:     return "He thrives in dietary chaos. Log every meal to drain his power."
        case .hollowWarrior:   return "An empty husk of a champion. Train hard enough and he crumbles."
        case .ironSleeper:     return "Bound by inertia. Each completed quest cracks his chains."
        case .witheringSpirit: return "A drought given form. Hydration is the only blade that cuts him."
        case .forsakenDragon:  return "The hardest of the rotation. Only sustained effort across the whole week brings him down."
        }
    }

    var icon: String {
        switch self {
        case .slothDemon:      return "moon.zzz.fill"
        case .gluttonKing:     return "fork.knife.circle.fill"
        case .hollowWarrior:   return "figure.fall"
        case .ironSleeper:     return "bed.double.fill"
        case .witheringSpirit: return "drop.degreesign.slash"
        case .forsakenDragon:  return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .slothDemon:      return .indigo
        case .gluttonKing:     return .orange
        case .hollowWarrior:   return Color(red: 0.6, green: 0.2, blue: 0.4)
        case .ironSleeper:     return .gray
        case .witheringSpirit: return .teal
        case .forsakenDragon:  return .red
        }
    }

    var maxHP: Int {
        switch self {
        case .slothDemon:      return 50_000   // total steps
        case .gluttonKing:     return 40       // meal logs
        case .hollowWarrior:   return 180      // workout minutes
        case .ironSleeper:     return 50       // quest completions
        case .witheringSpirit: return 60       // water cups
        case .forsakenDragon:  return 3000     // XP
        }
    }

    var hpUnit: String {
        switch self {
        case .slothDemon:      return "steps"
        case .gluttonKing:     return "meals"
        case .hollowWarrior:   return "minutes"
        case .ironSleeper:     return "quests"
        case .witheringSpirit: return "cups"
        case .forsakenDragon:  return "XP"
        }
    }

    /// GP awarded on defeat
    var defeatReward: Int {
        switch self {
        case .slothDemon, .ironSleeper:    return 100
        case .gluttonKing, .witheringSpirit: return 120
        case .hollowWarrior:               return 150
        case .forsakenDragon:              return 250
        }
    }

    /// Unique title awarded on first defeat (cosmetic — display in profile)
    var defeatTitle: String {
        switch self {
        case .slothDemon:      return "Demon Slayer"
        case .gluttonKing:     return "Tempered Hunger"
        case .hollowWarrior:   return "Iron Body"
        case .ironSleeper:     return "Chain Breaker"
        case .witheringSpirit: return "Wellspring"
        case .forsakenDragon:  return "Dragonsbane"
        }
    }
}
