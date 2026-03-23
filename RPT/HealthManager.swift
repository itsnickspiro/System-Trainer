import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif
import Combine

/// Production-ready HealthKit manager that gracefully falls back to mock data
/// Simply change `useMockData` to false when ready for App Store
@MainActor
class HealthManager: ObservableObject {
    // MARK: - Configuration
    private let useMockData = false // Change to false for production
    
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
        
        if useMockData {
            // Mock authorization success
            print("Using mock health data")
            isAuthorized = true
            return
        }
        
        do {
            // Write types we log from the app
            let writeTypes: Set<HKSampleType> = [
                HKObjectType.workoutType(),
                HKQuantityType(.bodyMass),
                HKQuantityType(.dietaryWater),
                HKQuantityType(.dietaryEnergyConsumed),
                HKQuantityType(.dietaryProtein)
            ]
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            print("HealthKit authorization failed: \(error)")
            isAuthorized = false
        }
    }
    
    // MARK: - Data Fetching
    func fetchTodaysHealthData(for profile: Profile) async {
        if useMockData {
            await fetchMockHealthData(for: profile)
        } else {
            await fetchRealHealthData(for: profile)
        }
    }
    
    private func fetchMockHealthData(for profile: Profile) async {
        // Simulate realistic daily health data
        let baseSteps = Int.random(in: 6000...15000)
        let baseCalories = Int.random(in: 250...600)
        let sleepHours = Double.random(in: 5.5...9.0)
        let restingHR = Int.random(in: 55...75)
        let weight = 70.0 + Double.random(in: -5...5)
        
        // Update profile with mock data
        profile.dailySteps = baseSteps
        profile.dailyActiveCalories = baseCalories
        profile.sleepHours = sleepHours
        profile.restingHeartRate = restingHR
        profile.weight = weight
        profile.vo2Max = Double.random(in: 30...50)
        profile.heartRateVariability = Double.random(in: 20...60)
        
        // BMI is automatically calculated from weight and height
        
        print("Updated profile with mock health data")
    }
    
    private func fetchRealHealthData(for profile: Profile) async {
        guard isAuthorized else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
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
            let samples = try await queryHealthData(type: stepsType, predicate: predicate)
            let totalSteps = samples.reduce(0) { $0 + Int($1.quantity.doubleValue(for: .count())) }
            profile.dailySteps = totalSteps
        } catch {
            print("Failed to fetch steps: \(error)")
        }
    }
    
    private func fetchActiveCalories(for profile: Profile, from startDate: Date, to endDate: Date) async {
        let caloriesType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        
        do {
            let samples = try await queryHealthData(type: caloriesType, predicate: predicate)
            let totalCalories = samples.reduce(0) { $0 + Int($1.quantity.doubleValue(for: .kilocalorie())) }
            profile.dailyActiveCalories = totalCalories
        } catch {
            print("Failed to fetch active calories: \(error)")
        }
    }
    
    private func fetchSleepData(for profile: Profile) async {
        let sleepType = HKCategoryType(.sleepAnalysis)
        // Query the last 24 hours (previous night's sleep window)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
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
        guard !useMockData && isAuthorized else { return }
        
        // Set up real-time health data observers
        // This would include HKObserverQuery for live updates
        print("Starting real-time health monitoring")
    }
    
    func stopHealthMonitoring() {
        guard !useMockData else { return }
        
        // Clean up observers
        print("Stopping health monitoring")
    }
}

// MARK: - Write-back to Apple Health
extension HealthManager {

    /// Save a completed workout to Apple Health using HKWorkoutBuilder.
    func saveWorkout(type workoutType: WorkoutType, start: Date, durationMinutes: Int) async {
        guard isAuthorized, !useMockData, HKHealthStore.isHealthDataAvailable() else { return }
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
        guard isAuthorized, !useMockData, HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.bodyMass)
        let qty = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        try? await healthStore.save(sample)
    }

    /// Save logged food calories to Apple Health.
    func saveCalories(_ kcal: Double, date: Date = Date()) async {
        guard isAuthorized, !useMockData, HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.dietaryEnergyConsumed)
        let qty = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        try? await healthStore.save(sample)
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
        !useMockData && (!healthDataAvailable || !isAuthorized)
    }
    
    var permissionStatusMessage: String {
        if useMockData {
            return "Using simulated health data for development"
        } else if !healthDataAvailable {
            return "HealthKit not available on this device"
        } else if !isAuthorized {
            return "Health access required for full experience"
        } else {
            return "Health data connected successfully"
        }
    }
}
