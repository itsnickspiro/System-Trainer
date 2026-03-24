import Foundation
import SwiftData
import Combine
import Network
import HealthKit
import UIKit

/// Centralized data manager that coordinates between local SwiftData and APIs
@MainActor
final class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // MARK: - Core Managers
    @Published private(set) var healthManager = HealthManager()
    @Published private(set) var recipeAPI = RecipeAPI.shared
    
    // MARK: - Local Data Context
    private var modelContext: ModelContext?
    
    // MARK: - Cached Data
    @Published private(set) var currentProfile: Profile?
    @Published private(set) var todaysQuests: [Quest] = []
    @Published private(set) var cachedRecipes: [Recipe] = []
    @Published private(set) var lastSyncDate: Date?
    
    // MARK: - State
    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var syncError: Error?
    
    // MARK: - HealthKit background delivery
    /// Active observer queries, keyed by sample type identifier.
    /// Keeping strong references prevents queries from being deallocated.
    private var observerQueries: [String: HKObserverQuery] = [:]
    /// Direct reference to the HKHealthStore so deinit (nonisolated) can stop queries.
    private let hkStore = HKHealthStore()

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
        startPeriodicSync()
    }
    
    // MARK: - Setup
    func configure(with context: ModelContext) {
        self.modelContext = context
        loadLocalData()
    }
    
    private func setupObservers() {
        // Monitor network connectivity
        NetworkMonitor.shared.$isConnected
            .assign(to: &$isOnline)

        // When HealthKit authorization is granted, register background observers.
        healthManager.$isAuthorized
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                self?.startHealthKitBackgroundDelivery()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    private func loadLocalData() {
        guard let context = modelContext else { return }
        
        // Load current profile
        let profileDescriptor = FetchDescriptor<Profile>()
        do {
            let profiles = try context.fetch(profileDescriptor)
            if let profile = profiles.first {
                currentProfile = profile
            } else {
                // Create default profile with saved name from onboarding
                let savedName = UserDefaults.standard.string(forKey: "userProfileName") ?? "Player"
                let newProfile = Profile(name: savedName)
                context.insert(newProfile)
                try context.save()
                currentProfile = newProfile
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
        
        // Load today's quests
        refreshTodaysQuests()

        // Generate default daily quests if they don't exist
        generateDefaultDailyQuests()
    }
    
    private func refreshTodaysQuests() {
        guard let context = modelContext else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = today.addingTimeInterval(86400) // Calculate outside the predicate
        let questDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { quest in
                quest.dateTag >= today && quest.dateTag < tomorrow
            },
            sortBy: [SortDescriptor(\Quest.createdAt, order: .reverse)]
        )
        
        do {
            todaysQuests = try context.fetch(questDescriptor)
            refreshWidgetData(context: context)
        } catch {
            print("Failed to load today's quests: \(error)")
        }
    }

    /// Push a fresh snapshot to App Group UserDefaults so widgets can update.
    private func refreshWidgetData(context: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let entryDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.dateConsumed >= todayStart
            }
        )
        let todayEntries = (try? context.fetch(entryDescriptor)) ?? []
        WidgetDataManager.shared.update(
            profile: currentProfile,
            quests: todaysQuests,
            nutritionEntries: todayEntries
        )
    }

    // MARK: - Profile Management
    func updateProfile(_ updates: (Profile) -> Void) {
        guard let profile = currentProfile else { return }
        
        updates(profile)
        saveLocalChanges()
    }
    
    func addXPToProfile(_ xp: Int, source: String = "General") {
        guard let profile = currentProfile else { return }
        
        let oldLevel = profile.level
        profile.addXP(xp)
        
        // Check for level up
        if profile.level > oldLevel {
            handleLevelUp(from: oldLevel, to: profile.level)
        }
        
        saveLocalChanges()
    }
    
    private func handleLevelUp(from oldLevel: Int, to newLevel: Int) {
        print("Level up! \(oldLevel) -> \(newLevel)")
    }
    
    // MARK: - Quest Management
    func addQuest(_ quest: Quest) {
        guard let context = modelContext else { return }
        
        context.insert(quest)
        saveLocalChanges()
        refreshTodaysQuests()
    }
    
    func completeQuest(_ quest: Quest) {
        quest.isCompleted = true
        quest.completedAt = Date()

        // Award XP and register completion
        if let profile = currentProfile {
            let prevPassCount = profile.exemptionPassCount
            profile.addXP(quest.xpReward)
            profile.registerCompletion()

            // If registerCompletion awarded a streak pass, mirror it to InventoryItem
            if profile.exemptionPassCount > prevPassCount {
                syncExemptionPassToInventory(profile: profile)
            }
        }

        // Haptic feedback for quest completion
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        saveLocalChanges()
        refreshTodaysQuests()
    }

    /// Ensures the InventoryItem for hermitMiracleSeed matches profile.exemptionPassCount.
    private func syncExemptionPassToInventory(profile: Profile) {
        guard let context = modelContext else { return }
        // Fetch all inventory items and filter in-memory (enum predicates not supported in SwiftData)
        let descriptor = FetchDescriptor<InventoryItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []
        let seedTypeRaw = InventoryItemType.hermitMiracleSeed.rawValue
        if let existing = allItems.first(where: { $0.itemType.rawValue == seedTypeRaw }) {
            existing.quantity = profile.exemptionPassCount
        } else {
            let newItem = InventoryItem(itemType: .hermitMiracleSeed, quantity: profile.exemptionPassCount)
            context.insert(newItem)
        }
    }

    func uncompleteQuest(_ quest: Quest) {
        quest.isCompleted = false
        quest.completedAt = nil

        // Refund XP — the player didn't actually earn it
        if let profile = currentProfile {
            profile.subtractXP(quest.xpReward)
        }

        saveLocalChanges()
        refreshTodaysQuests()
    }
    
    func deleteQuest(_ quest: Quest) {
        guard let context = modelContext else { return }

        do {
            context.delete(quest)
            try context.save()
            refreshTodaysQuests()
        } catch {
            print("Failed to delete quest: \(error)")
        }
    }

    // MARK: - Workout Quest Auto-Complete

    /// Called immediately after a user logs a workout. Finds today's incomplete quests
    /// that match the workout type and marks them complete, awarding XP.
    ///
    /// Matching logic (system quests keyed on statTarget):
    ///   - strength    → statTarget "strength"
    ///   - cardio      → statTarget "endurance"
    ///   - flexibility → statTarget "energy"
    ///   - mixed       → statTarget "strength" OR "endurance"
    ///   - Any type    → plan training quest (title starts with "[")
    ///
    /// Custom quests are matched via completionCondition "workout:<type>" or "workout:any".
    @discardableResult
    func autoCompleteWorkoutQuests(for workoutType: WorkoutType) -> Int {
        let matchingTargets: Set<String>
        switch workoutType {
        case .strength:    matchingTargets = ["strength"]
        case .cardio:      matchingTargets = ["endurance"]
        case .flexibility: matchingTargets = ["energy"]
        case .mixed:       matchingTargets = ["strength", "endurance"]
        }

        var completed = 0
        for quest in todaysQuests where !quest.isCompleted {
            // Custom quests: check completionCondition
            if let condition = quest.completionCondition, condition.hasPrefix("workout:") {
                let required = String(condition.dropFirst("workout:".count))
                if required == "any" || required == workoutType.rawValue {
                    completeQuest(quest)
                    completed += 1
                }
                continue
            }

            // System quests: match by statTarget
            let targetMatches = quest.statTarget.map { matchingTargets.contains($0) } ?? false
            // Plan training quests (no completionCondition, title starts with "[")
            let isPlanTrainingQuest = quest.completionCondition == nil
                && quest.title.hasPrefix("[")
                && !quest.title.contains("Rest")
            if targetMatches || isPlanTrainingQuest {
                completeQuest(quest)
                completed += 1
            }
        }
        return completed
    }

    // MARK: - Health Quest Auto-Complete

    /// Checks all of today's incomplete quests that have a HealthKit-backed
    /// completionCondition and auto-completes them when the threshold is met.
    /// Called from handleHealthDataUpdate() every time new health data arrives.
    @discardableResult
    func autoCompleteHealthQuests() -> Int {
        guard let profile = currentProfile else { return 0 }
        var completed = 0

        for quest in todaysQuests where !quest.isCompleted {
            guard let condition = quest.completionCondition else { continue }
            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let target = Double(parts[1]) else { continue }
            let kind = String(parts[0])

            let met: Bool
            switch kind {
            case "steps":
                met = Double(profile.dailySteps) >= target
            case "calories":
                met = Double(profile.dailyActiveCalories) >= target
            case "sleep":
                met = profile.sleepHours >= target
            default:
                continue  // "workout" and "manual" are not health-triggered
            }

            if met {
                completeQuest(quest)
                completed += 1
            }
        }
        return completed
    }

    // MARK: - Daily Quest Generation

    /// Generates today's quests from HealthKit data if they haven't been generated yet.
    /// Called once on app launch; keyed to today's date so it only runs once per day.
    func generateDefaultDailyQuests() {
        let today = Calendar.current.startOfDay(for: Date())
        let key = "questsGeneratedDate"
        let lastGenerated = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast

        // Already generated today — skip
        guard !Calendar.current.isDate(lastGenerated, inSameDayAs: today) else { return }

        guard let context = modelContext, let profile = currentProfile else { return }

        // Clear any stale auto-generated quests from yesterday
        let yesterday = today.addingTimeInterval(-86400)
        let staleDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { q in q.dateTag >= yesterday && q.dateTag < today }
        )
        if let staleQuests = try? context.fetch(staleDescriptor) {
            staleQuests.filter { !$0.isCompleted }.forEach { context.delete($0) }
        }

        // Active plan override: use plan quests instead of generic health-driven ones
        let activePlanID = profile.activePlanID
        if !activePlanID.isEmpty {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
            let animePlan = AnimeWorkoutPlanService.shared.plan(id: activePlanID)
            let resolvedPlan: AnimeWorkoutPlan?
            if let p = animePlan {
                resolvedPlan = p
            } else {
                // Try fetching from SwiftData as a custom plan
                let descriptor = FetchDescriptor<CustomWorkoutPlan>(
                    predicate: #Predicate { $0.id == activePlanID }
                )
                resolvedPlan = (try? context.fetch(descriptor))?.first?.asAnimeWorkoutPlan()
            }
            if let plan = resolvedPlan {
                let planQuests = QuestManager.shared.buildPlanQuests(
                    plan: plan, profile: profile, date: today, dueDate: tomorrow
                )
                planQuests.forEach { addQuest($0) }
                UserDefaults.standard.set(today, forKey: key)
                return
            }
        }

        // Recovery Mode override: use lighter rehabilitation quests
        if profile.isInRecovery {
            let quests = buildRecoveryQuests(for: profile, on: today)
            quests.forEach { addQuest($0) }
            UserDefaults.standard.set(today, forKey: key)
            return
        }

        // Build quest list driven by the player's health data gaps
        let quests = buildHealthDrivenQuests(for: profile, on: today)
        quests.forEach { addQuest($0) }

        UserDefaults.standard.set(today, forKey: key)
    }

    /// Rehabilitation Arc quests — 50% XP, gentler targets, 3 days post-reset.
    private func buildRecoveryQuests(for profile: Profile, on date: Date) -> [Quest] {
        var quests: [Quest] = []
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)
        let dayNum = 4 - max(0, profile.recoveryDaysRemaining) // Day 1, 2, or 3

        // ── Recovery Arc Header Quest ─────────────────────────────────────────
        quests.append(Quest(
            title: "[REHABILITATION ARC] Day \(dayNum) of 3",
            details: "System detected a critical failure. Reduced difficulty protocols active. Complete all quests to rebuild your foundation. 50% XP penalty lifted after 3 days.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 25, statTarget: "discipline", dateTag: date
        ))

        // ── Light Movement — 5,000 steps (half of normal) ────────────────────
        quests.append(Quest(
            title: "Light Movement Protocol",
            details: "Walk 5,000 steps today. No intense training required — focus on re-establishing a daily routine.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 40, statTarget: "endurance",
            completionCondition: "steps:5000", dateTag: date
        ))

        // ── Sleep Recovery ────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Sleep Recalibration",
            details: "Achieve 7+ hours of sleep tonight. Your body is recovering from a critical stress event.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 50, statTarget: "energy",
            completionCondition: "sleep:7", dateTag: date
        ))

        // ── Gentle Workout ────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Rehabilitation Training",
            details: "Complete any 15-minute workout — stretching, mobility, or light cardio counts. No heavy lifting required.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 40, statTarget: "health", dateTag: date
        ))

        // ── Hydration ─────────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Hydration Protocol",
            details: "Drink 6 glasses of water today. Hydration accelerates recovery and stat restoration.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 25, statTarget: "health", dateTag: date
        ))

        // ── Nutrition Log ─────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Nutrition Log",
            details: "Log at least 2 meals today in the Diary tab. Rebuilding nutritional awareness is key to recovery.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 30, statTarget: "discipline", dateTag: date
        ))

        return quests
    }

    /// Analyses the player's current health stats and returns a tailored set of quests.
    private func buildHealthDrivenQuests(for profile: Profile, on date: Date) -> [Quest] {
        var quests: [Quest] = []
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)

        // ── Steps ──────────────────────────────────────────────────────────────
        let stepGoal = 10_000
        let stepGap = stepGoal - profile.dailySteps
        if stepGap > 5_000 {
            quests.append(Quest(
                title: "Step Count Protocol",
                details: "Reach \(stepGoal.formatted()) steps today. Current: \(profile.dailySteps.formatted()). Endurance stat will increase.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 75, statTarget: "endurance", dateTag: date
            ))
        } else {
            quests.append(Quest(
                title: "Maintain Pace",
                details: "Hit \(stepGoal.formatted()) steps. You're on track — keep moving.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 50, statTarget: "endurance", dateTag: date
            ))
        }

        // ── Sleep ──────────────────────────────────────────────────────────────
        if profile.sleepHours < 6.5 {
            quests.append(Quest(
                title: "Sleep Debt Recovery",
                details: "Last night: \(String(format: "%.1f", profile.sleepHours))h. Sleep deficit detected. Achieve 8h tonight to restore Energy and Focus stats.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 100, statTarget: "energy", dateTag: date
            ))
        } else if profile.sleepHours < 7.5 {
            quests.append(Quest(
                title: "Rest Optimization",
                details: "Sleep logged: \(String(format: "%.1f", profile.sleepHours))h. Target 8h for maximum stat recovery.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 60, statTarget: "energy", dateTag: date
            ))
        }

        // ── Active Calories ────────────────────────────────────────────────────
        let calGoal = 400
        if profile.dailyActiveCalories < calGoal / 2 {
            quests.append(Quest(
                title: "Burn Protocol — URGENT",
                details: "Active calories today: \(profile.dailyActiveCalories) kcal. Target: \(calGoal) kcal. Complete any 30-min workout.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 120, statTarget: "strength", dateTag: date
            ))
        } else if profile.dailyActiveCalories < calGoal {
            quests.append(Quest(
                title: "Burn Target",
                details: "Active calories: \(profile.dailyActiveCalories)/\(calGoal) kcal. Close the gap with a workout session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 80, statTarget: "strength", dateTag: date
            ))
        }

        // ── Resting Heart Rate ────────────────────────────────────────────────
        if profile.restingHeartRate > 75 {
            quests.append(Quest(
                title: "Cardiovascular Conditioning",
                details: "Resting HR: \(profile.restingHeartRate) bpm — above optimal. 20 minutes of zone-2 cardio will improve Health stat.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 90, statTarget: "health", dateTag: date
            ))
        }

        // ── Discipline (streak guard) ─────────────────────────────────────────
        quests.append(Quest(
            title: "Daily Discipline Check",
            details: "Current streak: \(profile.currentStreak) days. Log at least one meal and complete one quest before midnight.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 50, statTarget: "discipline", dateTag: date
        ))

        // ── Low stat — Focus ──────────────────────────────────────────────────
        if profile.focus < 40 {
            quests.append(Quest(
                title: "Cognitive Training",
                details: "Focus stat is low (\(Int(profile.focus))/100). Meditate for 10 minutes or complete a focused deep-work session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: 70, statTarget: "focus", dateTag: date
            ))
        }

        // ── Guaranteed: Daily Training — always present so there is always a workout quest ──
        let tier = QuestManager.tier(for: profile.level)
        let weekday = Calendar.current.component(.weekday, from: date)
        let trainingFocus: String
        let trainingDetails: String
        switch weekday {
        case 2, 5: // Mon, Thu — Push
            trainingFocus = "Push Day"
            trainingDetails = "Upper body push — chest, shoulders, triceps. Complete at least 3 working sets of any push movement."
        case 3, 6: // Tue, Fri — Pull
            trainingFocus = "Pull Day"
            trainingDetails = "Upper body pull — back, biceps, rear delts. Complete at least 3 working sets of any pull movement."
        case 4, 7: // Wed, Sat — Legs
            trainingFocus = "Leg Day"
            trainingDetails = "Lower body — quads, hamstrings, glutes. Complete at least 3 working sets of any leg movement."
        default:   // Sun — Active Recovery
            trainingFocus = "Active Recovery"
            trainingDetails = "Light movement day — stretching, mobility, yoga, or a slow walk. Let your body recover and adapt."
        }
        quests.append(Quest(
            title: "Daily Training: \(trainingFocus)",
            details: "\(tier.rank.displayName) Protocol — \(trainingDetails)\nComplete any logged workout to auto-check this quest.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: Int(100.0 * tier.xpMultiplier), statTarget: "strength", dateTag: date
        ))

        // ── Guaranteed: Nutrition Log — always present ─────────────────────────
        quests.append(Quest(
            title: "Nutrition Log",
            details: "Log all meals for today in the Diary tab. Hitting your calorie and protein goals awards full XP.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: Int(50.0 * tier.xpMultiplier), statTarget: "discipline", dateTag: date
        ))

        return quests
    }
    
    // MARK: - Recipe Management
    func searchRecipes(query: String? = nil, limit: Int = 10) async throws -> [Recipe] {
        // Try to fetch from API
        do {
            let recipes = try await recipeAPI.fetchRecipes(query: query, limit: limit)
            
            // Cache the results
            if query == nil || query?.isEmpty == true {
                // Only cache general searches to avoid cluttering
                cachedRecipes = recipes
            }
            
            return recipes
        } catch {
            // Fallback to cached recipes if available
            if !cachedRecipes.isEmpty {
                return cachedRecipes.prefix(limit).map { $0 }
            }
            throw error
        }
    }
    
    func saveRecipeToProfile(_ recipe: Recipe) {
        // Record meal (affects health stats, but no XP - only quests give XP)
        updateProfile { profile in
            profile.recordMeal(healthiness: .healthy) // Default to healthy
        }

    }
    
    // MARK: - Health Data Integration

    /// Called whenever HealthKit delivers new data (via observer query) or the
    /// health manager publishes an objectWillChange notification.
    private func handleHealthDataUpdate() async {
        guard let profile = currentProfile else { return }

        // Fetch latest health data
        await healthManager.fetchTodaysHealthData(for: profile)

        // Update daily stats (this handles XP internally once per day)
        profile.updateDailyStats()

        saveLocalChanges()

        // Reload quests so we have the latest state before checking conditions
        refreshTodaysQuests()

        // Auto-complete any custom quests whose HealthKit threshold is now met
        autoCompleteHealthQuests()
    }

    // MARK: - HealthKit Background Observer Setup

    /// Registers HKObserverQuery + enableBackgroundDelivery for the four core
    /// metrics: steps, active calories, workouts, and resting heart rate.
    ///
    /// When HealthKit wakes the app via silent push (background delivery), the
    /// observer fires, we refetch and update the profile in SwiftData.
    /// This replaces any polling timer and is iOS-recommended for battery health.
    private func startHealthKitBackgroundDelivery() {
        guard hkStore.authorizationStatus(for: HKQuantityType(.stepCount)) != .notDetermined else {
            // HealthKit not yet authorised — do nothing; observers will be
            // registered after the user grants permission via requestAuthorization.
            return
        }

        let trackedTypes: [(HKSampleType, HKUpdateFrequency)] = [
            (HKQuantityType(.stepCount),          .hourly),
            (HKQuantityType(.activeEnergyBurned), .hourly),
            (HKQuantityType(.restingHeartRate),   .daily),
            (HKObjectType.workoutType(),          .immediate),
        ]

        for (sampleType, frequency) in trackedTypes {
            let typeID = sampleType.identifier

            // Skip if an observer is already registered for this type.
            guard observerQueries[typeID] == nil else { continue }

            // Register background delivery so HealthKit wakes the app via silent push.
            hkStore.enableBackgroundDelivery(for: sampleType, frequency: frequency) { _, error in
                if let error { print("[HealthKit] Background delivery failed for \(typeID): \(error)") }
            }

            // Observer query fires when new samples arrive (foreground or background).
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    print("[HealthKit] Observer error for \(typeID): \(error)")
                    completionHandler()
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.handleHealthDataUpdate()
                    completionHandler() // Must be called to signal HealthKit the delivery was handled.
                }
            }

            observerQueries[typeID] = query
            hkStore.execute(query)
        }
    }

    /// Call this after HealthKit authorization is granted so observers are
    /// registered immediately without waiting for the next app launch.
    func registerHealthKitObserversAfterAuthorization() {
        startHealthKitBackgroundDelivery()
    }

    /// Call when app returns to foreground to ensure health data is fresh.
    func refreshHealthOnForeground() {
        Task { await handleHealthDataUpdate() }
        // Re-run daily quest generation in case the day rolled over while the app was open
        generateDefaultDailyQuests()
        refreshTodaysQuests()
    }
    
    func recordHealthAction(_ action: HealthAction) {
        guard let profile = currentProfile else { return }
        
        switch action {
        case .drinkWater:
            profile.recordWaterIntake()
        case .recordMeal(let healthiness):
            profile.recordMeal(healthiness: healthiness)
        case .recordWorkout(let type, let duration):
            profile.recordWorkout(type: type, duration: duration)
        case .recordSleep(let hours):
            profile.recordSleep(hours: hours)
        case .recordMeditation(let minutes):
            profile.recordMeditation(minutes: minutes)
        }
        
        saveLocalChanges()
    }
    
    // MARK: - Local Storage
    private func saveLocalChanges() {
        guard let context = modelContext else { return }
        
        do {
            try context.save()
        } catch {
            print("Failed to save local changes: \(error)")
        }
    }
    
    // MARK: - Sync
    private func startPeriodicSync() {
        // No-op: sync is driven by HKObserverQuery background delivery.
    }

    func forceSyncNow() async {
        await handleHealthDataUpdate()
    }
    
    // MARK: - Cleanup
    deinit {
        // Stop all active HealthKit observer queries.
        // hkStore is a nonisolated stored property so safe to access in deinit.
        for query in observerQueries.values {
            hkStore.stop(query)
        }
        observerQueries.removeAll()
        cancellables.removeAll()
    }
}

// MARK: - Health Actions
enum HealthAction {
    case drinkWater
    case recordMeal(MealHealthiness)
    case recordWorkout(WorkoutType, duration: Int)
    case recordSleep(hours: Double)
    case recordMeditation(minutes: Int)
}

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rpt.networkMonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
