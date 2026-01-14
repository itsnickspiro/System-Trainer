import Foundation
import SwiftData
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Centralized data manager that coordinates between local SwiftData, Firebase, and APIs
@MainActor
final class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // MARK: - Core Managers
    @Published private(set) var healthManager = HealthManager()
    @Published private(set) var recipeAPI = RecipeAPI.shared
    private let firebaseManager = FirebaseManager.shared
    
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
    
    // MARK: - Configuration
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private var syncTimer: Timer?
    
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
        
        Task {
            await syncWithFirebase()
        }
    }
    
    private func setupObservers() {
        // Monitor network connectivity
        NetworkMonitor.shared.$isConnected
            .assign(to: &$isOnline)
        
        // Monitor health data changes
        healthManager.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.handleHealthDataUpdate()
                }
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
        } catch {
            print("Failed to load today's quests: \(error)")
        }
    }
    
    // MARK: - Profile Management
    func updateProfile(_ updates: (Profile) -> Void) {
        guard let profile = currentProfile else { return }
        
        updates(profile)
        saveLocalChanges()
        
        Task {
            do {
                try await syncProfileToFirebase(profile)
            } catch {
                print("Failed to sync profile update: \(error)")
            }
        }
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
        
        Task {
            do {
                try await syncProfileToFirebase(profile)
            } catch {
                print("Failed to sync XP update: \(error)")
            }
        }
    }
    
    private func handleLevelUp(from oldLevel: Int, to newLevel: Int) {
        // Handle level up rewards, notifications, etc.
        print("Level up! \(oldLevel) -> \(newLevel)")
        
        Task {
            await firebaseManager.logEvent("level_up", parameters: [
                "old_level": oldLevel,
                "new_level": newLevel,
                "timestamp": Date().timeIntervalSince1970
            ])
        }
    }
    
    // MARK: - Quest Management
    func addQuest(_ quest: Quest) {
        guard let context = modelContext else { return }
        
        context.insert(quest)
        saveLocalChanges()
        refreshTodaysQuests()
        
        Task {
            do {
                try await syncQuestToFirebase(quest)
            } catch {
                print("Failed to sync new quest: \(error)")
            }
        }
    }
    
    func completeQuest(_ quest: Quest) {
        quest.isCompleted = true
        quest.completedAt = Date()

        // Award XP and register completion
        if let profile = currentProfile {
            profile.addXP(quest.xpReward)
            profile.registerCompletion()
        }

        saveLocalChanges()
        refreshTodaysQuests()

        Task {
            do {
                // Sync quest completion
                try await syncQuestToFirebase(quest)

                // CRITICAL: Sync updated profile with new XP to Firebase
                if let profile = currentProfile {
                    try await syncProfileToFirebase(profile)
                }
            } catch {
                print("Failed to sync completed quest: \(error)")
            }
        }
    }
    
    func deleteQuest(_ quest: Quest) {
        guard let context = modelContext else { return }

        do {
            context.delete(quest)
            try context.save()
            refreshTodaysQuests()

            Task {
                do {
                    try await firebaseManager.deleteQuest(questId: quest.id.uuidString)
                } catch {
                    print("Failed to delete quest from Firebase: \(error)")
                }
            }
        } catch {
            print("Failed to delete quest: \(error)")
        }
    }

    // MARK: - Default Quest Generation
    func generateDefaultDailyQuests() {
        guard let context = modelContext else { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Check if default quests already exist for today
        let questDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { quest in
                quest.dateTag >= today
            }
        )

        do {
            let existingQuests = try context.fetch(questDescriptor)

            // Define default daily quest templates
            let defaultQuestTitles = [
                "Drink 8 Glasses of Water",
                "Complete a 30-Min Workout",
                "Log All Meals Today",
                "Get 7-8 Hours of Sleep",
                "Take 10,000 Steps"
            ]

            // Only create quests that don't already exist
            for title in defaultQuestTitles {
                let questExists = existingQuests.contains { $0.title == title }
                if !questExists {
                    let quest = Quest(
                        title: title,
                        details: getQuestDetails(for: title),
                        type: .daily,
                        createdAt: Date(),
                        dueDate: Calendar.current.date(byAdding: .day, value: 1, to: today),
                        xpReward: 20,
                        dateTag: today
                    )
                    addQuest(quest)
                }
            }
        } catch {
            print("Failed to check existing quests: \(error)")
        }
    }

    private func getQuestDetails(for title: String) -> String {
        switch title {
        case "Drink 8 Glasses of Water":
            return "Stay hydrated throughout the day for optimal health and energy"
        case "Complete a 30-Min Workout":
            return "Engage in any physical activity for at least 30 minutes"
        case "Log All Meals Today":
            return "Track your nutrition by logging breakfast, lunch, and dinner"
        case "Get 7-8 Hours of Sleep":
            return "Ensure quality rest for recovery and mental clarity"
        case "Take 10,000 Steps":
            return "Meet the daily step goal to improve cardiovascular health"
        default:
            return "Complete this quest to earn XP and improve your stats"
        }
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

        Task {
            await firebaseManager.logEvent("recipe_saved", parameters: [
                "recipe_id": recipe.id,
                "recipe_title": recipe.title
            ])
        }
    }
    
    // MARK: - Health Data Integration
    private func handleHealthDataUpdate() async {
        guard let profile = currentProfile else { return }

        // Fetch latest health data
        await healthManager.fetchTodaysHealthData(for: profile)

        // Update daily stats (this handles XP internally once per day)
        profile.updateDailyStats()

        saveLocalChanges()

        // Sync health changes to Firebase
        do {
            try await syncProfileToFirebase(profile)
        } catch {
            print("Failed to sync health data update: \(error)")
        }
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
        
        Task {
            do {
                try await syncProfileToFirebase(profile)
            } catch {
                print("Failed to sync health action: \(error)")
            }
        }
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
    
    // MARK: - Firebase Sync
    private func syncWithFirebase() async {
        guard isOnline else { return }
        
        isSyncing = true
        syncError = nil
        
        var hasErrors = false
        
        // Sync profile
        if let profile = currentProfile {
            do {
                try await firebaseManager.syncProfile(profile)
            } catch {
                print("Failed to sync profile: \(error)")
                syncError = error
                hasErrors = true
            }
        }
        
        // Sync quests
        for quest in todaysQuests {
            do {
                try await firebaseManager.syncQuest(quest)
            } catch {
                print("Failed to sync quest: \(error)")
                if syncError == nil {
                    syncError = error
                }
                hasErrors = true
            }
        }
        
        if !hasErrors {
            lastSyncDate = Date()
        }
        
        isSyncing = false
    }
    
    private func syncProfileToFirebase(_ profile: Profile) async throws {
        try await firebaseManager.syncProfile(profile)
    }
    
    private func syncQuestToFirebase(_ quest: Quest) async throws {
        try await firebaseManager.syncQuest(quest)
    }
    
    // MARK: - Periodic Sync
    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncWithFirebase()
            }
        }
    }
    
    func forceSyncNow() async {
        await syncWithFirebase()
    }
    
    // MARK: - Cleanup
    deinit {
        syncTimer?.invalidate()
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
    
    private init() {
        // Implement actual network monitoring
        // For now, assume always connected
    }
}
