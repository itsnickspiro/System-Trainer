import Foundation
import SwiftData
import SwiftUI

@Model
final class Profile {
    var id: UUID
    var name: String
    var xp: Int
    var level: Int
    var currentStreak: Int
    var bestStreak: Int
    var lastCompletionDate: Date?
    var hardcoreResetDeadline: Date?
    
    // RPG Stats
    var health: Double // 0-100, affected by food, water, sleep
    var energy: Double // 0-100, affected by rest and activities
    var strength: Double // 0-100, affected by workouts
    var endurance: Double // 0-100, affected by cardio
    var focus: Double // 0-100, affected by meditation, study
    var discipline: Double // 0-100, affected by quest completion consistency
    
    // Health tracking
    var waterIntake: Int // glasses of water today
    var lastMealTime: Date?
    var lastWorkoutTime: Date?
    var sleepHours: Double // hours slept last night
    var lastStatUpdate: Date
    
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
    
    // Computed Health Metrics
    var bmi: Double { weight / pow(height / 100, 2) }

    // Note: For more accurate BMR, add age and gender properties to Profile
    var bmr: Double { // Basal Metabolic Rate (Mifflin-St Jeor Equation)
        // Using estimated age of 25 and male formula
        // TODO: Add age and gender properties for accurate calculation
        return (10 * weight) + (6.25 * height) - (5 * 25) + 5
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
        // Level up every 100 XP plus 50 XP per level increment
        while xp >= levelXPThreshold(level: level) {
            xp -= levelXPThreshold(level: level)
            level += 1
            // Boost all stats slightly on level up
            boostAllStats(by: 2.0)
        }
    }

    func levelXPThreshold(level: Int) -> Int { 
        // Exponential scaling: each level requires significantly more XP
        // Level 1: 100 XP, Level 2: 150 XP, Level 5: 300 XP, Level 10: 750 XP, Level 20: 2000 XP
        let baseXP = 100
        let exponentialFactor = 1.15 // 15% increase per level
        let levelBonus = max(0, level - 1) * 25 // Additional linear component
        
        return Int(Double(baseXP) * pow(exponentialFactor, Double(level - 1))) + levelBonus
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
        if let deadline = hardcoreResetDeadline, now >= deadline {
            // wipe progress
            xp = 0
            level = 1
            currentStreak = 0
            bestStreak = 0
            lastCompletionDate = nil
            hardcoreResetDeadline = nil
            // Massive stat penalties
            health = max(20.0, health - 30.0)
            energy = max(10.0, energy - 40.0)
            discipline = max(10.0, discipline - 50.0)
        }
    }
    
    // MARK: - RPG Stat System
    
    func updateDailyStats() {
        let now = Date()
        let calendar = Calendar.current
        
        // Only update once per day
        guard !calendar.isDate(lastStatUpdate, inSameDayAs: now) else { return }
        
        // Update stats based on real health data
        updateStatsFromHealthData()
        
        // Decay stats over time if no activity
        applyDailyDecay()
        
        // Reset daily counters
        resetDailyCounters()
        
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
        
        switch type {
        case .strength:
            adjustStat(\.strength, by: Double(duration) * 0.5)
            adjustStat(\.endurance, by: Double(duration) * 0.2)
            adjustStat(\.discipline, by: 2.0)
        case .cardio:
            adjustStat(\.endurance, by: Double(duration) * 0.8)
            adjustStat(\.strength, by: Double(duration) * 0.1)
            adjustStat(\.discipline, by: 2.0)
        case .flexibility:
            adjustStat(\.health, by: Double(duration) * 0.3)
            adjustStat(\.focus, by: Double(duration) * 0.2)
            adjustStat(\.discipline, by: 1.5)
        case .mixed:
            adjustStat(\.strength, by: Double(duration) * 0.3)
            adjustStat(\.endurance, by: Double(duration) * 0.4)
            adjustStat(\.health, by: Double(duration) * 0.2)
            adjustStat(\.discipline, by: 2.5)
        }
        
        // General workout benefits
        adjustStat(\.health, by: 3.0)
        adjustStat(\.energy, by: 5.0)
    }
    
    func recordMeal(healthiness: MealHealthiness) {
        lastMealTime = Date()
        
        switch healthiness {
        case .veryHealthy:
            adjustStat(\.health, by: 8.0)
            adjustStat(\.energy, by: 6.0)
        case .healthy:
            adjustStat(\.health, by: 4.0)
            adjustStat(\.energy, by: 3.0)
        case .neutral:
            adjustStat(\.health, by: 1.0)
        case .unhealthy:
            adjustStat(\.health, by: -3.0)
            adjustStat(\.energy, by: -2.0)
        case .veryUnhealthy:
            adjustStat(\.health, by: -8.0)
            adjustStat(\.energy, by: -5.0)
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
            dailySugarIntake += entry.foodItem.sugar * (entry.unit == .grams ? entry.quantity / 100.0 : (entry.quantity * entry.foodItem.servingSize / 100.0))
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

enum WorkoutType: String, CaseIterable, Identifiable {
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
    case daily
    case weekly
    case custom

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .daily: return .orange
        case .weekly: return .purple
        case .custom: return .cyan
        }
    }

    var displayName: String {
        switch self {
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .custom: return "CUSTOM"
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
    var id: UUID
    var title: String
    var details: String
    var type: QuestType
    var createdAt: Date
    var dueDate: Date? // for scheduled/punishment
    var isCompleted: Bool
    var completedAt: Date?
    var repeatDays: [Int] // 1...7 for Sun..Sat using Calendar.weekday
    var xpReward: Int
    var dateTag: Date // normalized day for daily grouping

    init(title: String, details: String = "", type: QuestType = .daily, createdAt: Date = Date(), dueDate: Date? = nil, isCompleted: Bool = false, completedAt: Date? = nil, repeatDays: [Int] = [], xpReward: Int = 20, dateTag: Date = Calendar.current.startOfDay(for: Date())) {
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
        self.dateTag = dateTag
    }
}

// MARK: - Food Tracking Models

@Model
final class FoodItem {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    
    // Nutritional info per 100g or per serving
    var caloriesPer100g: Double
    var servingSize: Double // in grams
    var caloriesPerServing: Double
    
    // Macronutrients (per 100g)
    var carbohydrates: Double // grams
    var protein: Double // grams
    var fat: Double // grams
    var fiber: Double // grams
    var sugar: Double // grams
    var sodium: Double // mg
    
    // Categories
    var category: FoodCategory
    var isCustom: Bool // User-created vs database food
    var isVerified: Bool // Whether nutritional info is verified
    
    var createdAt: Date
    var lastUsed: Date?
    
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
    var id: UUID
    @Relationship var foodItem: FoodItem
    var quantity: Double // in grams or servings based on unit
    var unit: FoodUnit
    var meal: MealType
    var dateConsumed: Date
    var notes: String?
    
    // Computed nutritional values for this entry
    var totalCalories: Double {
        return unit == .grams ?
            (foodItem.caloriesPer100g * quantity / 100.0) :
            (foodItem.caloriesPerServing * quantity)
    }
    
    var totalCarbs: Double {
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.carbohydrates * multiplier
    }
    
    var totalProtein: Double {
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.protein * multiplier
    }
    
    var totalFat: Double {
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.fat * multiplier
    }
    
    var totalFiber: Double {
        let multiplier = unit == .grams ? quantity / 100.0 : (quantity * foodItem.servingSize / 100.0)
        return foodItem.fiber * multiplier
    }
    
    init(foodItem: FoodItem, quantity: Double, unit: FoodUnit = .grams, meal: MealType, dateConsumed: Date = Date(), notes: String? = nil) {
        self.id = UUID()
        self.foodItem = foodItem
        self.quantity = quantity
        self.unit = unit
        self.meal = meal
        self.dateConsumed = dateConsumed
        self.notes = notes
        
        // Update last used date
        foodItem.lastUsed = Date()
    }
}

@Model 
final class CustomMeal {
    var id: UUID
    var name: String
    var details: String?
    @Relationship var foodItems: [CustomMealItem]
    var category: MealType
    var createdAt: Date
    var lastUsed: Date?
    var isFavorite: Bool
    
    // Computed nutritional totals
    var totalCalories: Double {
        foodItems.reduce(0) { sum, item in
            let calories = item.unit == .grams ?
                (item.foodItem.caloriesPer100g * item.quantity / 100.0) :
                (item.foodItem.caloriesPerServing * item.quantity)
            return sum + calories
        }
    }
    
    var totalCarbs: Double {
        foodItems.reduce(0) { sum, item in
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * item.foodItem.servingSize / 100.0)
            return sum + (item.foodItem.carbohydrates * multiplier)
        }
    }
    
    var totalProtein: Double {
        foodItems.reduce(0) { sum, item in
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * item.foodItem.servingSize / 100.0)
            return sum + (item.foodItem.protein * multiplier)
        }
    }
    
    var totalFat: Double {
        foodItems.reduce(0) { sum, item in
            let multiplier = item.unit == .grams ? item.quantity / 100.0 : (item.quantity * item.foodItem.servingSize / 100.0)
            return sum + (item.foodItem.fat * multiplier)
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
    var id: UUID
    @Relationship var foodItem: FoodItem
    var quantity: Double
    var unit: FoodUnit

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

