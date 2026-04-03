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
    /// Reuse HealthManager's HKHealthStore to avoid duplicate instances.
    private var hkStore: HKHealthStore { healthManager.healthStore }

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

        // Award daily login GP bonus (once per day)
        Task { await checkDailyLoginBonus() }
    }
    
    private func refreshTodaysQuests() {
        guard let context = modelContext else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
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

        // Apply active XP multipliers from equipped items and events
        let storeMultiplier = StoreService.shared.activeXPMultiplier
        let eventMultiplier = EventsService.shared.activeXPMultiplier
        let scaledXP = xp > 0 ? Int(Double(xp) * storeMultiplier * eventMultiplier) : xp

        let oldLevel = profile.level
        profile.addXP(scaledXP)

        // Check for level up
        if profile.level > oldLevel {
            handleLevelUp(from: oldLevel, to: profile.level)
        }

        saveLocalChanges()
    }

    private func handleLevelUp(from oldLevel: Int, to newLevel: Int) {
        print("Level up! \(oldLevel) -> \(newLevel)")
        // Sync progress to cloud, award level-up GP, evaluate achievements, and update leaderboard
        Task {
            await PlayerProfileService.shared.syncProfile()
            await PlayerProfileService.shared.syncIfStreakMilestone(
                currentProfile?.currentStreak ?? 0
            )
            AchievementsService.shared.evaluate()

            // Award GP for level-up
            let rc = RemoteConfigService.shared
            let levelUpBonus = rc.int("credits_per_level_up", default: 50)
            if levelUpBonus > 0 {
                await PlayerProfileService.shared.addCredits(
                    amount: levelUpBonus,
                    type: "level_up_bonus",
                    referenceKey: "level_\(newLevel)"
                )
            }

            // Update leaderboard with new level/XP
            await LeaderboardService.shared.upsertEntry()
        }
    }
    // MARK: - GP Bonus Helpers

    /// Awards daily login GP bonus once per calendar day.
    private func checkDailyLoginBonus() async {
        let key = "rpt_last_daily_login_credit_date"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) { return }

        let rc = RemoteConfigService.shared
        let bonus = rc.int("credits_daily_login_bonus", default: 5)
        if bonus > 0 {
            await PlayerProfileService.shared.addCredits(amount: bonus, type: "daily_login")
        }
        UserDefaults.standard.set(today, forKey: key)
    }

    /// Awards GP for streak milestones (7-day and 30-day). Called after streak changes.
    private func checkStreakMilestoneBonus(streak: Int) {
        let rc = RemoteConfigService.shared
        let milestones: [(threshold: Int, key: String, configKey: String)] = [
            (7,  "rpt_streak_credit_7",  "credits_streak_bonus_7day"),
            (30, "rpt_streak_credit_30", "credits_streak_bonus_30day"),
        ]
        for m in milestones {
            guard streak == m.threshold else { continue }
            let awarded = UserDefaults.standard.bool(forKey: "\(m.key)_\(streak)")
            guard !awarded else { continue }
            let bonus = rc.int(m.configKey, default: m.threshold == 7 ? 25 : 100)
            if bonus > 0 {
                Task {
                    await PlayerProfileService.shared.addCredits(
                        amount: bonus,
                        type: "streak_bonus",
                        referenceKey: "\(m.threshold)_day_streak"
                    )
                }
                UserDefaults.standard.set(true, forKey: "\(m.key)_\(streak)")
            }
        }
    }

    // MARK: - Quest Management
    func addQuest(_ quest: Quest) {
        guard let context = modelContext else { return }
        
        context.insert(quest)
        saveLocalChanges()
        refreshTodaysQuests()
    }
    
    func completeQuest(_ quest: Quest) {
        // Idempotency: prevent double-completion from concurrent code paths
        guard !quest.isCompleted else { return }
        // Date guard: only allow completing quests dated today
        guard Calendar.current.isDateInToday(quest.dateTag) else { return }

        quest.isCompleted = true
        quest.completedAt = Date()

        // Award XP (through multipliers) and register completion
        if let profile = currentProfile {
            let prevPassCount = profile.exemptionPassCount
            addXPToProfile(quest.xpReward, source: "Quest")
            profile.registerCompletion()

            // If registerCompletion awarded a streak pass, mirror it to InventoryItem
            if profile.exemptionPassCount > prevPassCount {
                syncExemptionPassToInventory(profile: profile)
            }

            // Check streak milestone GP bonuses
            checkStreakMilestoneBonus(streak: profile.currentStreak)
        }

        // Haptic feedback for quest completion
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Increment the aggregate quests-completed counter for achievement evaluation
        let questCount = UserDefaults.standard.integer(forKey: "rpt_total_quests_completed") + 1
        UserDefaults.standard.set(questCount, forKey: "rpt_total_quests_completed")

        saveLocalChanges()
        refreshTodaysQuests()

        // Evaluate achievements and report progress to events
        AchievementsService.shared.evaluate()
        Task { await EventsService.shared.updateAllEventProgress() }

        // Award GP for quest completion and sync to activity/leaderboard backends
        Task {
            let rc = RemoteConfigService.shared
            let baseCreditsPerQuest = rc.int("credits_quest_completion", default: 10)
            let baseMultiplier = rc.float("credits_multiplier_base", default: 1.0)
            let eventMultiplier = EventsService.shared.activeCreditMultiplier
            let scaledAmount = Int(Double(baseCreditsPerQuest) * Double(baseMultiplier) * eventMultiplier)
            if scaledAmount > 0 {
                await PlayerProfileService.shared.addCredits(
                    amount: scaledAmount,
                    type: "quest_reward",
                    referenceKey: quest.title
                )
            }

            // Log streak day activity to Supabase
            let totalQuests = UserDefaults.standard.integer(forKey: "rpt_quests_today") + 1
            UserDefaults.standard.set(totalQuests, forKey: "rpt_quests_today")
            await ActivitySyncService.shared.logStreakDay(
                activityTypes: ["quest"],
                questCount: totalQuests,
                workoutCount: UserDefaults.standard.integer(forKey: "rpt_workouts_today"),
                steps: currentProfile?.dailySteps ?? 0
            )

            // Update leaderboard with latest XP
            await LeaderboardService.shared.upsertEntry()
        }
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

    /// Delete a user-created quest, reversing XP/GP awards if it was already completed.
    func deleteUserCreatedQuest(_ quest: Quest) {
        guard quest.isUserCreated else { return }
        if quest.isCompleted {
            // Reverse XP
            if let profile = currentProfile {
                profile.subtractXP(quest.xpReward)
            }
            // Reverse GP (credits) via PlayerProfileService (negative amount = debit)
            if quest.creditReward > 0 {
                Task { @MainActor in
                    await PlayerProfileService.shared.addCredits(
                        amount: -quest.creditReward,
                        type: "quest_deletion_reversal",
                        referenceKey: quest.id.uuidString
                    )
                }
            }
        }
        deleteQuest(quest)
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

        if completed > 0 {
            // Increment workout counter for achievement evaluation
            let workoutCount = UserDefaults.standard.integer(forKey: "rpt_total_workouts_logged") + 1
            UserDefaults.standard.set(workoutCount, forKey: "rpt_total_workouts_logged")
            // Evaluate achievements and report to events after workout
            AchievementsService.shared.evaluate()
            Task { await EventsService.shared.updateAllEventProgress() }
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

        // Reset daily activity counters for the new day
        UserDefaults.standard.set(0, forKey: "rpt_quests_today")
        UserDefaults.standard.set(0, forKey: "rpt_workouts_today")

        guard let context = modelContext, let profile = currentProfile else { return }

        // Keep incomplete quests from previous days visible (read-only)
        // so the player can see what they missed. QuestsView locks
        // interaction for any day that isn't today.

        // ── Check if yesterday's quests were all completed ────────────────────
        // If any were left incomplete, set the hardcore reset deadline to now
        // so applyHardcoreResetIfNeeded() can trigger the penalty.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86400)
        let yesterdayDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { q in q.dateTag >= yesterday && q.dateTag < today }
        )
        if let yesterdayQuests = try? context.fetch(yesterdayDescriptor), !yesterdayQuests.isEmpty {
            let allComplete = yesterdayQuests.allSatisfy { $0.isCompleted }
            if !allComplete && profile.hardcoreResetDeadline == nil {
                // Missed quests — arm the reset deadline for end of today,
                // giving the player time to use an Exemption Pass before the penalty fires.
                let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
                profile.hardcoreResetDeadline = endOfToday
            }
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
            xpReward: 40, statTarget: "health",
            completionCondition: "workout:any", dateTag: date
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
        let rc = RemoteConfigService.shared

        // ── Steps ──────────────────────────────────────────────────────────────
        let stepGoal = rc.int("daily_step_goal", default: 10_000)
        let stepGap = stepGoal - profile.dailySteps
        if stepGap > 5_000 {
            quests.append(Quest(
                title: "Step Count Protocol",
                details: "Reach \(stepGoal.formatted()) steps today. Current: \(profile.dailySteps.formatted()). Endurance stat will increase.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_steps_urgent", default: 75), statTarget: "endurance",
                completionCondition: "steps:\(stepGoal)", dateTag: date
            ))
        } else {
            quests.append(Quest(
                title: "Maintain Pace",
                details: "Hit \(stepGoal.formatted()) steps. You're on track — keep moving.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_steps_normal", default: 50), statTarget: "endurance",
                completionCondition: "steps:\(stepGoal)", dateTag: date
            ))
        }

        // ── Sleep ──────────────────────────────────────────────────────────────
        if profile.sleepHours < 6.5 {
            quests.append(Quest(
                title: "Sleep Debt Recovery",
                details: "Last night: \(String(format: "%.1f", profile.sleepHours))h. Sleep deficit detected. Achieve 8h tonight to restore Energy and Focus stats.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_sleep_debt", default: 100), statTarget: "energy",
                completionCondition: "sleep:8", dateTag: date
            ))
        } else if profile.sleepHours < 7.5 {
            quests.append(Quest(
                title: "Rest Optimization",
                details: "Sleep logged: \(String(format: "%.1f", profile.sleepHours))h. Target 8h for maximum stat recovery.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_sleep_normal", default: 60), statTarget: "energy",
                completionCondition: "sleep:8", dateTag: date
            ))
        }

        // ── Active Calories ────────────────────────────────────────────────────
        let calGoal = rc.int("daily_active_calories_goal", default: 400)
        if profile.dailyActiveCalories < calGoal / 2 {
            quests.append(Quest(
                title: "Burn Protocol — URGENT",
                details: "Active calories today: \(profile.dailyActiveCalories) kcal. Target: \(calGoal) kcal. Complete any 30-min workout.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_calories_urgent", default: 120), statTarget: "strength",
                completionCondition: "calories:\(calGoal)", dateTag: date
            ))
        } else if profile.dailyActiveCalories < calGoal {
            quests.append(Quest(
                title: "Burn Target",
                details: "Active calories: \(profile.dailyActiveCalories)/\(calGoal) kcal. Close the gap with a workout session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_calories_normal", default: 80), statTarget: "strength",
                completionCondition: "calories:\(calGoal)", dateTag: date
            ))
        }

        // ── Resting Heart Rate ────────────────────────────────────────────────
        let hrThreshold = rc.int("resting_hr_threshold", default: 75)
        if profile.restingHeartRate > hrThreshold {
            quests.append(Quest(
                title: "Cardiovascular Conditioning",
                details: "Resting HR: \(profile.restingHeartRate) bpm — above optimal (>\(hrThreshold) bpm). 20 minutes of zone-2 cardio will improve Health stat.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_cardio_conditioning", default: 90), statTarget: "health",
                completionCondition: "workout:cardio", dateTag: date
            ))
        }

        // ── Discipline (streak guard) ─────────────────────────────────────────
        quests.append(Quest(
            title: "Daily Discipline Check",
            details: "Current streak: \(profile.currentStreak) days. Log at least one meal and complete one quest before midnight.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: rc.int("xp_discipline_check", default: 50), statTarget: "discipline", dateTag: date
        ))

        // ── Low stat — Focus ──────────────────────────────────────────────────
        let focusThreshold = rc.int("focus_low_threshold", default: 40)
        if profile.focus < Double(focusThreshold) {
            quests.append(Quest(
                title: "Cognitive Training",
                details: "Focus stat is low (\(Int(profile.focus))/100). Meditate for 10 minutes or complete a focused deep-work session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_cognitive_training", default: 70), statTarget: "focus", dateTag: date
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
        let trainingBaseXP = rc.int("xp_daily_training_base", default: 100)
        quests.append(Quest(
            title: "Daily Training: \(trainingFocus)",
            details: "\(tier.rank.displayName) Protocol — \(trainingDetails)\nComplete any logged workout to auto-check this quest.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: Int(Double(trainingBaseXP) * tier.xpMultiplier), statTarget: "strength",
            completionCondition: "workout:any", dateTag: date
        ))

        // ── Guaranteed: Nutrition Log — always present ─────────────────────────
        let nutritionBaseXP = rc.int("xp_nutrition_log_base", default: 50)
        quests.append(Quest(
            title: "Nutrition Log",
            details: "Log all meals for today in the Diary tab. Hitting your calorie and protein goals awards full XP.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: Int(Double(nutritionBaseXP) * tier.xpMultiplier), statTarget: "discipline", dateTag: date
        ))

        // ── Cap to max_daily_quests if configured ─────────────────────────────
        let maxQuests = rc.int("max_daily_quests", default: 0)
        if maxQuests > 0 && quests.count > maxQuests {
            return Array(quests.prefix(maxQuests))
        }
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
    func saveLocalChanges() {
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

    // MARK: - CloudKit Conflict Reconciliation

    /// Called after a CloudKit import completes. Ensures progression fields
    /// reflect the highest values across all devices (prevents last-write-wins
    /// from silently regressing XP, level, or bestStreak).
    func reconcileAfterCloudSync() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Profile>()
        guard let profiles = try? context.fetch(descriptor) else { return }

        for profile in profiles {
            // Derive the correct level from totalXPEarned to detect sync regression
            var derivedLevel = 1
            var derivedXP = profile.totalXPEarned
            while derivedXP >= profile.levelXPThreshold(level: derivedLevel) {
                derivedXP -= profile.levelXPThreshold(level: derivedLevel)
                derivedLevel += 1
            }

            // If the synced profile has a lower level than what totalXPEarned implies,
            // the remote wrote a stale level — restore the derived values.
            if profile.level < derivedLevel {
                profile.level = derivedLevel
                profile.xp = derivedXP
                print("[CloudKit] Reconciled: level \(profile.level), xp \(profile.xp) from totalXPEarned \(profile.totalXPEarned)")
            }

            // bestStreak should never decrease — take the max
            // (already protected by code, but CloudKit sync could overwrite)
            if profile.currentStreak > profile.bestStreak {
                profile.bestStreak = profile.currentStreak
            }
        }

        saveLocalChanges()
    }

    // MARK: - Cleanup
    deinit {
        // DataManager is a singleton — deinit is effectively dead code.
        // Observer queries are cleaned up implicitly when the process exits.
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
