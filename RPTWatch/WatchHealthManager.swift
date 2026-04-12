import HealthKit
import Combine

/// Reads health data directly from HealthKit on the Watch,
/// replacing the old iPhone-relay approach via WatchConnectivity.
class WatchHealthManager: ObservableObject {
    static let shared = WatchHealthManager()

    @Published var steps: Int = 0
    @Published var caloriesBurned: Int = 0
    @Published var heartRate: Int = 0
    @Published var sleepHours: Double = 0.0

    private let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Authorization

    /// Request read-only HealthKit authorization, then fetch today's data.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            if let error = error {
                print("[WatchHealthManager] Auth error: \(error.localizedDescription)")
                return
            }
            if success {
                self?.refreshHealthData()
            }
        }
    }

    // MARK: - Refresh all metrics

    /// Query today's steps, calories, heart rate, and last night's sleep.
    func refreshHealthData() {
        fetchSteps()
        fetchCalories()
        fetchHeartRate()
        fetchSleep()
    }

    // MARK: - Steps (sum for today)

    private func fetchSteps() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let predicate = predicateForToday()

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            if let error = error {
                print("[WatchHealthManager] Steps error: \(error.localizedDescription)")
                return
            }
            let value = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            DispatchQueue.main.async {
                self?.steps = Int(value)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Calories (sum for today)

    private func fetchCalories() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let predicate = predicateForToday()

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            if let error = error {
                print("[WatchHealthManager] Calories error: \(error.localizedDescription)")
                return
            }
            let value = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            DispatchQueue.main.async {
                self?.caloriesBurned = Int(value)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Heart Rate (most recent sample)

    private func fetchHeartRate() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, error in
            if let error = error {
                print("[WatchHealthManager] Heart rate error: \(error.localizedDescription)")
                return
            }
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async {
                self?.heartRate = Int(bpm)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Sleep (last night, asleepCore + asleepDeep + asleepREM)

    private func fetchSleep() {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        // Look back from 6 PM yesterday to now to capture last night's sleep
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        // Yesterday at 6 PM
        components.day! -= 1
        components.hour = 18
        components.minute = 0
        components.second = 0
        let startOfSleepWindow = calendar.date(from: components) ?? now.addingTimeInterval(-18 * 3600)

        let predicate = HKQuery.predicateForSamples(withStart: startOfSleepWindow, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, error in
            if let error = error {
                print("[WatchHealthManager] Sleep error: \(error.localizedDescription)")
                return
            }
            guard let samples = samples as? [HKCategorySample] else { return }

            // Only count asleepCore, asleepDeep, asleepREM
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            var totalSeconds: TimeInterval = 0
            for sample in samples where asleepValues.contains(sample.value) {
                totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
            }

            let hours = totalSeconds / 3600.0
            DispatchQueue.main.async {
                self?.sleepHours = (hours * 10).rounded() / 10  // round to 1 decimal
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Helpers

    /// Predicate covering from midnight today until now.
    private func predicateForToday() -> NSPredicate {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
    }
}
