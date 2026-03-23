import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
import SwiftUI
import Combine

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    // MARK: - Health Data Types
    private let healthDataTypes: Set<HKQuantityType> = {
        var types = Set<HKQuantityType>()
        
        // Activity & Fitness
        if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepsType)
        }
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergyType)
        }
        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distanceType)
        }
        if let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            types.insert(flightsType)
        }
        if let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTimeType)
        }
        
        // Heart Rate
        if let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHRType)
        }
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
        }
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrvType)
        }
        if let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.insert(vo2MaxType)
        }
        
        // Body Measurements
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weightType)
        }
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(heightType)
        }
        if let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFatType)
        }
        
        // Sleep
        if let sleepAnalysisType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            // Note: Sleep is HKCategoryType, not HKQuantityType
        }
        
        // Nutrition
        if let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(waterType)
        }
        if let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(proteinType)
        }
        if let fiberType = HKQuantityType.quantityType(forIdentifier: .dietaryFiber) {
            types.insert(fiberType)
        }
        if let sugarType = HKQuantityType.quantityType(forIdentifier: .dietarySugar) {
            types.insert(sugarType)
        }
        
        // Mindfulness
        if let mindfulnessType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            // Note: Mindfulness is HKCategoryType, not HKQuantityType
        }
        
        return types
    }()
    
    private let categoryTypes: Set<HKCategoryType> = {
        var types = Set<HKCategoryType>()
        
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        if let mindfulnessType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindfulnessType)
        }
        
        return types
    }()
    
    // MARK: - Authorization
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            return
        }
        
        let allTypes = Set(healthDataTypes.map { $0 as HKSampleType }) 
                      .union(Set(categoryTypes.map { $0 as HKSampleType }))

        // Write types — workouts + nutrition we log in-app
        var shareTypes = Set<HKSampleType>()
        shareTypes.insert(HKObjectType.workoutType())
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) { shareTypes.insert(water) }
        if let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) { shareTypes.insert(protein) }
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) { shareTypes.insert(weight) }
        
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: allTypes)
            await MainActor.run {
                self.isAuthorized = true
                self.authorizationStatus = .sharingAuthorized
            }
        } catch {
            print("HealthKit authorization failed: \(error)")
            await MainActor.run {
                self.authorizationStatus = .sharingDenied
            }
        }
    }
    
    // MARK: - Data Fetching
    func fetchTodaysHealthData(for profile: Profile) async {
        guard isAuthorized else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        await withTaskGroup(of: Void.self) { group in
            // Fetch all health data concurrently
            group.addTask { await self.fetchSteps(from: today, to: tomorrow, profile: profile) }
            group.addTask { await self.fetchActiveCalories(from: today, to: tomorrow, profile: profile) }
            group.addTask { await self.fetchRestingHeartRate(for: profile) }
            group.addTask { await self.fetchVO2Max(for: profile) }
            group.addTask { await self.fetchBodyMeasurements(for: profile) }
            group.addTask { await self.fetchSleepData(from: today, to: tomorrow, profile: profile) }
            group.addTask { await self.fetchNutritionData(from: today, to: tomorrow, profile: profile) }
            group.addTask { await self.fetchMindfulnessData(from: today, to: tomorrow, profile: profile) }
            group.addTask { await self.fetchFlightsClimbed(from: today, to: tomorrow, profile: profile) }
        }
    }
    
    private func fetchSteps(from startDate: Date, to endDate: Date, profile: Profile) async {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        nonisolated(unsafe) let profile = profile
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let _ = self else { return }
            guard let result = result, let sum = result.sumQuantity() else { return }
            let stepsValue = Int(sum.doubleValue(for: .count()))
            Task { @MainActor in
                profile.dailySteps = stepsValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchActiveCalories(from startDate: Date, to endDate: Date, profile: Profile) async {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        nonisolated(unsafe) let profile = profile
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(
            quantityType: caloriesType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let _ = self else { return }
            guard let result = result, let sum = result.sumQuantity() else { return }
            let caloriesValue = Int(sum.doubleValue(for: .kilocalorie()))
            Task { @MainActor in
                profile.dailyActiveCalories = caloriesValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchRestingHeartRate(for profile: Profile) async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        nonisolated(unsafe) let profile = profile
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let _ = self else { return }
            guard let samples = samples as? [HKQuantitySample],
                  let latestSample = samples.first else { return }
            let restingHRValue = Int(latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            Task { @MainActor in
                profile.restingHeartRate = restingHRValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchVO2Max(for profile: Profile) async {
        guard let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        nonisolated(unsafe) let profile = profile
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: vo2MaxType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let _ = self else { return }
            guard let samples = samples as? [HKQuantitySample],
                  let latestSample = samples.first else { return }
            let vo2MaxValue = latestSample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute()))
            Task { @MainActor in
                profile.vo2Max = vo2MaxValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchBodyMeasurements(for profile: Profile) async {
        nonisolated(unsafe) let profile = profile
        
        // Fetch weight
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                guard let _ = self else { return }
                guard let samples = samples as? [HKQuantitySample],
                      let latestSample = samples.first else { return }
                let weightKg = latestSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                Task { @MainActor in
                    profile.weight = weightKg
                }
            }
            healthStore.execute(query)
        }
        
        // Fetch height
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                guard let _ = self else { return }
                guard let samples = samples as? [HKQuantitySample],
                      let latestSample = samples.first else { return }
                let heightCm = latestSample.quantity.doubleValue(for: .meterUnit(with: .centi))
                Task { @MainActor in
                    profile.height = heightCm
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchSleepData(from startDate: Date, to endDate: Date, profile: Profile) async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        nonisolated(unsafe) let profile = profile
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let _ = self else { return }
            guard let samples = samples as? [HKCategorySample] else { return }
            var totalSleepTime: TimeInterval = 0
            var totalTimeInBed: TimeInterval = 0
            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch sample.value {
                case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    totalTimeInBed += duration
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    totalSleepTime += duration
                default:
                    break
                }
            }
            let hoursValue = totalSleepTime / 3600
            let efficiencyValue = totalTimeInBed > 0 ? totalSleepTime / totalTimeInBed : 0.85
            Task { @MainActor in
                profile.sleepHours = hoursValue
                profile.sleepEfficiency = efficiencyValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchNutritionData(from startDate: Date, to endDate: Date, profile: Profile) async {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        
        nonisolated(unsafe) let profile = profile
        
        // Water intake
        if let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            let query = HKStatisticsQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { [weak self] _, result, error in
                guard let _ = self else { return }
                guard let result = result, let sum = result.sumQuantity() else { return }
                let liters = sum.doubleValue(for: .liter())
                let glassesValue = Int(liters * 4)
                Task { @MainActor in
                    profile.waterIntake = glassesValue
                }
            }
            healthStore.execute(query)
        }
        
        // Protein intake
        if let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let query = HKStatisticsQuery(
                quantityType: proteinType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { [weak self] _, result, error in
                guard let _ = self else { return }
                guard let result = result, let sum = result.sumQuantity() else { return }
                let gramsValue = sum.doubleValue(for: .gram())
                Task { @MainActor in
                    profile.dailyProteinIntake = gramsValue
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMindfulnessData(from startDate: Date, to endDate: Date, profile: Profile) async {
        guard let mindfulnessType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return }
        nonisolated(unsafe) let profile = profile
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKSampleQuery(
            sampleType: mindfulnessType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let _ = self else { return }
            guard let samples = samples else { return }
            var totalMindfulnessTime: TimeInterval = 0
            for sample in samples {
                totalMindfulnessTime += sample.endDate.timeIntervalSince(sample.startDate)
            }
            let minutesValue = Int(totalMindfulnessTime / 60)
            Task { @MainActor in
                profile.mindfulnessMinutesToday = minutesValue
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchFlightsClimbed(from startDate: Date, to endDate: Date, profile: Profile) async {
        guard let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else { return }
        nonisolated(unsafe) let profile = profile
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(
            quantityType: flightsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let _ = self else { return }
            guard let result = result, let sum = result.sumQuantity() else { return }
            let flightsValue = Int(sum.doubleValue(for: .count()))
            Task { @MainActor in
                profile.stairFlightsClimbed = flightsValue
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Write-back to Apple Health

    /// Save a completed WorkoutSession as an HKWorkout in Apple Health.
    func saveWorkoutSession(_ session: WorkoutSession) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        guard let finishedAt = session.finishedAt else { return }

        // Map routineName to an HKWorkoutActivityType (best-effort)
        let activityType: HKWorkoutActivityType = activityType(for: session.routineName)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            try await builder.endCollection(at: finishedAt)
            try await builder.finishWorkout()
        } catch {
            print("[HealthKit] Failed to save workout: \(error)")
        }
    }

    /// Save a body weight measurement to Apple Health.
    func saveBodyWeight(_ kg: Double, date: Date = Date()) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: weightType, quantity: quantity, start: date, end: date)
        do {
            try await healthStore.save(sample)
        } catch {
            print("[HealthKit] Failed to save weight: \(error)")
        }
    }

    /// Save daily water intake to Apple Health.
    func saveWaterIntake(glasses: Int, date: Date = Date()) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        let liters = Double(glasses) * 0.25 // 250 mL per glass
        let quantity = HKQuantity(unit: .liter(), doubleValue: liters)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)
        do {
            try await healthStore.save(sample)
        } catch {
            print("[HealthKit] Failed to save water: \(error)")
        }
    }

    private func activityType(for name: String) -> HKWorkoutActivityType {
        let lower = name.lowercased()
        if lower.contains("run") || lower.contains("cardio") { return .running }
        if lower.contains("cycl") || lower.contains("bike") { return .cycling }
        if lower.contains("swim") { return .swimming }
        if lower.contains("yoga") || lower.contains("flex") { return .yoga }
        if lower.contains("hiit") || lower.contains("mixed") { return .highIntensityIntervalTraining }
        return .traditionalStrengthTraining
    }

    // MARK: - Background Refresh

    /// Fetch today's health data and update the profile. Call on app foreground.
    func refreshTodayIfNeeded(profile: Profile) async {
        guard isAuthorized else { return }
        await fetchTodaysHealthData(for: profile)
    }

    // MARK: - XP Calculation
    func calculateDailyXPFromHealth(profile: Profile) -> Int {
        var xp = 0
        
        // Steps XP (0-100 XP based on goal achievement)
        let stepsProgress = min(1.0, Double(profile.dailySteps) / Double(profile.dailyStepsGoal))
        xp += Int(stepsProgress * 100)
        
        // Active calories XP (0-75 XP)
        let caloriesProgress = min(1.0, Double(profile.dailyActiveCalories) / Double(profile.dailyActiveCaloriesGoal))
        xp += Int(caloriesProgress * 75)
        
        // Sleep XP (0-50 XP for 7-9 hours of quality sleep)
        if profile.sleepHours >= 7 && profile.sleepHours <= 9 {
            xp += Int(profile.sleepEfficiency * 50)
        }
        
        // Mindfulness XP (0-25 XP for meditation)
        xp += min(25, profile.mindfulnessMinutesToday)
        
        // Hydration XP (0-20 XP for 8+ glasses)
        xp += min(20, profile.waterIntake * 2)
        
        // Health metrics bonuses
        if profile.bmi >= 18.5 && profile.bmi <= 25 { xp += 10 } // Healthy BMI
        if profile.restingHeartRate >= 60 && profile.restingHeartRate <= 80 { xp += 10 } // Good resting HR
        if profile.stairFlightsClimbed >= 5 { xp += 15 } // Stair climbing bonus
        
        // Consistency bonuses (exponential rewards for meeting multiple goals)
        let goalsMetCount = [
            profile.dailySteps >= profile.dailyStepsGoal,
            profile.dailyActiveCalories >= profile.dailyActiveCaloriesGoal,
            profile.waterIntake >= 8,
            profile.sleepHours >= 7,
            profile.mindfulnessMinutesToday >= 10
        ].filter { $0 }.count
        
        let consistencyBonus = goalsMetCount * goalsMetCount * 5 // 5, 20, 45, 80, 125 XP
        xp += consistencyBonus
        
        return xp
    }
}

