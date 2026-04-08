import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif
import Combine

@MainActor
class HealthManager: ObservableObject {
    // MARK: - HealthKit Setup
    let healthStore = HKHealthStore()
    
    // MARK: - Published State
    @Published var isAuthorized = false
    @Published var healthDataAvailable = false
    
    // MARK: - Health Data Types
    private let readTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()
        
        // Activity & Fitness
        types.insert(HKQuantityType(.stepCount))
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.distanceWalkingRunning))
        types.insert(HKQuantityType(.flightsClimbed))
        types.insert(HKQuantityType(.appleExerciseTime))
        
        // Heart Rate & Cardiovascular
        types.insert(HKQuantityType(.restingHeartRate))
        types.insert(HKQuantityType(.heartRate))
        types.insert(HKQuantityType(.heartRateVariabilitySDNN))
        types.insert(HKQuantityType(.vo2Max))
        
        // Body Measurements
        types.insert(HKQuantityType(.bodyMass))
        types.insert(HKQuantityType(.height))
        types.insert(HKQuantityType(.bodyFatPercentage))
        types.insert(HKQuantityType(.bodyMassIndex))
        
        // Sleep (Category Type)
        types.insert(HKCategoryType(.sleepAnalysis))
        
        // Additional Metrics
        types.insert(HKQuantityType(.respiratoryRate))
        types.insert(HKQuantityType(.oxygenSaturation))
        
        return types
    }()
    
    // MARK: - Initialization
    init() {
        healthDataAvailable = HKHealthStore.isHealthDataAvailable()
    }
    
    // MARK: - Authorization
    func requestAuthorization() async {
        guard healthDataAvailable else {
            print("HealthKit not available on this device")
            isAuthorized = false
            return
        }
        
        do {
            // Write types we log from the app — full nutrition coverage so
            // logged meals round-trip into Apple Health's Nutrition screen.
            let writeTypes: Set<HKSampleType> = [
                HKObjectType.workoutType(),
                HKQuantityType(.bodyMass),
                HKQuantityType(.dietaryWater),
                HKQuantityType(.dietaryEnergyConsumed),
                HKQuantityType(.dietaryProtein),
                HKQuantityType(.dietaryCarbohydrates),
                HKQuantityType(.dietaryFatTotal),
                HKQuantityType(.dietaryFatSaturated),
                HKQuantityType(.dietaryFiber),
                HKQuantityType(.dietarySugar),
                HKQuantityType(.dietarySodium),
                HKQuantityType(.dietaryCholesterol),
                HKQuantityType(.dietaryPotassium),
                HKQuantityType(.dietaryCalcium),
                HKQuantityType(.dietaryIron),
                HKQuantityType(.dietaryVitaminC),
                HKQuantityType(.dietaryVitaminD),
                HKCategoryType(.mindfulSession)
            ]
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            // requestAuthorization succeeds even when the user denies all
            // types. Apple does not expose read-permission status (privacy),
            // so we use the *write* status of bodyMass (which we always
            // request) as a proxy: if the user authorized writes, they
            // overwhelmingly also authorized reads, and the prompt was at
            // least dismissed by tapping Allow. The previous check
            // (`!= .notDetermined`) was a false-positive that treated
            // explicit denial as success and made every fetch silently fail
            // against zero-default Profile fields.
            let writeStatus = healthStore.authorizationStatus(for: HKQuantityType(.bodyMass))
            isAuthorized = (writeStatus == .sharingAuthorized)
        } catch {
            print("HealthKit authorization failed: \(error)")
            isAuthorized = false
        }
    }
    
    // MARK: - Data Fetching
    func fetchTodaysHealthData(for profile: Profile) async {
        await fetchRealHealthData(for: profile)
    }
    
    private func fetchRealHealthData(for profile: Profile) async {
        guard isAuthorized else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        
        await withTaskGroup(of: Void.self) { group in
            // Fetch all health metrics concurrently
            group.addTask { await self.fetchSteps(for: profile, from: startOfDay, to: endOfDay) }
            group.addTask { await self.fetchActiveCalories(for: profile, from: startOfDay, to: endOfDay) }
            group.addTask { await self.fetchSleepData(for: profile) }
            group.addTask { await self.fetchRestingHeartRate(for: profile) }
            group.addTask { await self.fetchVO2Max(for: profile) }
            group.addTask { await self.fetchBodyMass(for: profile) }
            group.addTask { await self.fetchHeartRateVariability(for: profile) }
        }
    }
    
    // MARK: - Individual Health Metric Fetchers
    private func fetchSteps(for profile: Profile, from startDate: Date, to endDate: Date) async {
        let stepsType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        do {
            let totalSteps = try await queryStatistics(type: stepsType, predicate: predicate, unit: .count())
            let prevSteps = profile.dailySteps
            let newSteps = Int(totalSteps)
            profile.dailySteps = newSteps
            // Damage the weekly raid boss with the step delta (only the
            // Sloth Demon archetype consumes this).
            let delta = newSteps - prevSteps
            if delta > 0 {
                await MainActor.run {
                    BossRaidService.shared.applyDamage(source: .steps, amount: delta)
                }
            }
        } catch {
            print("Failed to fetch steps: \(error)")
        }
    }

    private func fetchActiveCalories(for profile: Profile, from startDate: Date, to endDate: Date) async {
        let caloriesType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        do {
            let totalCalories = try await queryStatistics(type: caloriesType, predicate: predicate, unit: .kilocalorie())
            profile.dailyActiveCalories = Int(totalCalories)
        } catch {
            print("Failed to fetch active calories: \(error)")
        }
    }
    
    private func fetchSleepData(for profile: Profile) async {
        let sleepType = HKCategoryType(.sleepAnalysis)
        // Query the last 24 hours (previous night's sleep window).
        // Calendar.date(byAdding:) is documented as returning Optional<Date>
        // (overflow / extreme range protection), so use safe defaults rather
        // than force-unwrap — a nil here previously crashed the background
        // delivery handler whenever it fired.
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday.addingTimeInterval(-86400)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86400)
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfToday)

        do {
            let samples = try await queryCategoryData(type: sleepType, predicate: predicate)
            // Sum durations for asleep stages only (exclude .inBed and .awake)
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]
            let totalSeconds = samples
                .filter { asleepValues.contains($0.value) }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            profile.sleepHours = totalSeconds / 3600.0
        } catch {
            print("Failed to fetch sleep data: \(error)")
        }
    }
    
    private func fetchRestingHeartRate(for profile: Profile) async {
        let hrType = HKQuantityType(.restingHeartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()), end: Date())
        
        do {
            let samples = try await queryHealthData(type: hrType, predicate: predicate)
            if let latestSample = samples.last {
                profile.restingHeartRate = Int(latestSample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
            }
        } catch {
            print("Failed to fetch resting heart rate: \(error)")
        }
    }
    
    private func fetchVO2Max(for profile: Profile) async {
        let vo2MaxType = HKQuantityType(.vo2Max)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .month, value: -1, to: Date()), end: Date())
        
        do {
            let samples = try await queryHealthData(type: vo2MaxType, predicate: predicate)
            if let latestSample = samples.last {
                profile.vo2Max = latestSample.quantity.doubleValue(for: .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute()))
            }
        } catch {
            print("Failed to fetch VO2 Max: \(error)")
        }
    }
    
    private func fetchBodyMass(for profile: Profile) async {
        let weightType = HKQuantityType(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .month, value: -1, to: Date()), end: Date())
        
        do {
            let samples = try await queryHealthData(type: weightType, predicate: predicate)
            if let latestSample = samples.last {
                profile.weight = latestSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            }
        } catch {
            print("Failed to fetch body mass: \(error)")
        }
    }
    
    private func fetchHeartRateVariability(for profile: Profile) async {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()), end: Date())
        
        do {
            let samples = try await queryHealthData(type: hrvType, predicate: predicate)
            if let latestSample = samples.last {
                profile.heartRateVariability = latestSample.quantity.doubleValue(for: .secondUnit(with: .milli))
            }
        } catch {
            print("Failed to fetch HRV: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    private func queryCategoryData(type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            self.healthStore.execute(query)
        }
    }

    /// Uses HKStatisticsQuery to get a de-duplicated cumulative sum.
    /// HealthKit merges overlapping samples from multiple sources (iPhone + Apple Watch)
    /// so the result is never double-counted.
    private func queryStatistics(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                    continuation.resume(returning: value)
                }
            }
            healthStore.execute(query)
        }
    }

    private func queryHealthData(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - XP Calculation
    func calculateDailyXPFromHealth(profile: Profile) -> Int {
        var xp = 0
        
        // Steps XP (up to 25 XP for meeting goal)
        let stepProgress = min(1.0, Double(profile.dailySteps) / Double(profile.dailyStepsGoal))
        xp += Int(stepProgress * 25)
        
        // Active calories XP (up to 25 XP for meeting goal)
        let calorieProgress = min(1.0, Double(profile.dailyActiveCalories) / Double(profile.dailyActiveCaloriesGoal))
        xp += Int(calorieProgress * 25)
        
        // Sleep XP (up to 20 XP for 8+ hours)
        let sleepProgress = min(1.0, profile.sleepHours / 8.0)
        xp += Int(sleepProgress * 20)
        
        // Health metrics bonus XP
        if profile.restingHeartRate < 70 { xp += 10 }
        if profile.vo2Max > 35 { xp += 15 }
        if profile.heartRateVariability > 30 { xp += 10 }
        
        return xp
    }
    
    // MARK: - Real-time Monitoring
    func startHealthMonitoring(for profile: Profile) {
        guard isAuthorized else { return }
        
        // Set up real-time health data observers
        // This would include HKObserverQuery for live updates
        print("Starting real-time health monitoring")
    }
    
    func stopHealthMonitoring() {
        
        // Clean up observers
        print("Stopping health monitoring")
    }
}

// MARK: - Write-back to Apple Health
extension HealthManager {

    /// Save a completed workout to Apple Health using HKWorkoutBuilder.
    func saveWorkout(type workoutType: WorkoutType, start: Date, durationMinutes: Int) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        let config = HKWorkoutConfiguration()
        config.activityType = hkActivityType(for: workoutType)
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            print("[HealthManager] saveWorkout failed: \(error)")
        }
    }

    /// Save a body weight reading to Apple Health.
    func saveBodyWeight(_ kg: Double, date: Date = Date()) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.bodyMass)
        let qty = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        try? await healthStore.save(sample)
    }

    /// Save logged food calories to Apple Health.
    func saveCalories(_ kcal: Double, date: Date = Date()) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.dietaryEnergyConsumed)
        let qty = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        try? await healthStore.save(sample)
    }

    /// Save a full nutrition sample for a single logged food item to Apple
    /// Health. Writes every macro and micro the FoodItem has non-zero data
    /// for, scaled by the actual serving weight. Call this from any meal
    /// logging site so entries show up in Apple Health's Nutrition screen
    /// alongside data from other apps.
    func saveMealSample(foodItem: FoodItem, servingGrams: Double, date: Date = Date()) async {
        guard isAuthorized, HKHealthStore.isHealthDataAvailable() else { return }
        guard servingGrams > 0 else { return }
        let factor = servingGrams / 100.0

        // (HealthKit type, value, unit) tuples. Only non-zero values are written.
        let entries: [(HKQuantityType, Double, HKUnit)] = [
            (HKQuantityType(.dietaryEnergyConsumed),  foodItem.caloriesPer100g * factor, .kilocalorie()),
            (HKQuantityType(.dietaryProtein),         foodItem.protein * factor,          .gram()),
            (HKQuantityType(.dietaryCarbohydrates),   foodItem.carbohydrates * factor,    .gram()),
            (HKQuantityType(.dietaryFatTotal),        foodItem.fat * factor,              .gram()),
            (HKQuantityType(.dietaryFiber),           foodItem.fiber * factor,            .gram()),
            (HKQuantityType(.dietarySugar),           foodItem.sugar * factor,            .gram()),
            (HKQuantityType(.dietaryFatSaturated),    foodItem.saturatedFatG * factor,    .gram()),
            (HKQuantityType(.dietaryCholesterol),     foodItem.cholesterolMg * factor,    .gramUnit(with: .milli)),
            (HKQuantityType(.dietarySodium),          foodItem.sodium * factor,           .gramUnit(with: .milli)),
            (HKQuantityType(.dietaryPotassium),       foodItem.potassiumMg * factor,      .gramUnit(with: .milli)),
            (HKQuantityType(.dietaryCalcium),         foodItem.calciumMg * factor,        .gramUnit(with: .milli)),
            (HKQuantityType(.dietaryIron),            foodItem.ironMg * factor,           .gramUnit(with: .milli)),
            (HKQuantityType(.dietaryVitaminC),        foodItem.vitaminCMg * factor,       .gramUnit(with: .milli)),
            (HKQuantityType(.dietaryVitaminD),        foodItem.vitaminDMcg * factor,      .gramUnit(with: .micro))
        ]

        let samples: [HKQuantitySample] = entries.compactMap { (type, value, unit) in
            guard value > 0 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date
            )
        }

        guard !samples.isEmpty else { return }
        try? await healthStore.save(samples)
    }

    private func hkActivityType(for type: WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .strength: return .traditionalStrengthTraining
        case .cardio: return .running
        case .flexibility: return .yoga
        case .mixed: return .highIntensityIntervalTraining
        }
    }
}

// MARK: - Health Permissions Helper
extension HealthManager {
    var needsHealthPermissions: Bool {
        !healthDataAvailable || !isAuthorized
    }
    
    var permissionStatusMessage: String {
        if !healthDataAvailable {
            return "HealthKit not available on this device"
        } else if !isAuthorized {
            return "Health access required for full experience"
        } else {
            return "Health data connected successfully"
        }
    }
}
