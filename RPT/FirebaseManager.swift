import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI
import Combine

/// Firebase manager for cloud sync and analytics
@MainActor
final class FirebaseManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    static let shared = FirebaseManager()
    
    // MARK: - Firebase Services
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    // Handle for Firebase Auth state change listener
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    
    // MARK: - State
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isConfigured = false
    
    // MARK: - Collections
    private let profilesCollection = "profiles"
    private let questsCollection = "quests"
    private let analyticsCollection = "analytics"
    private let recipesCollection = "saved_recipes"
    
    private init() {
        setupAuthStateListener()
        configure()
    }
    
    // MARK: - Configuration
    private func configure() {
        // Configure Firestore settings
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
        
        isConfigured = true
    }
    
    private func setupAuthStateListener() {
        authStateListenerHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    // MARK: - Authentication
    func signInAnonymously() async throws {
        let result = try await auth.signInAnonymously()
        currentUser = result.user
        isAuthenticated = true
    }
    
    func signOut() throws {
        try auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }
    
    // MARK: - Profile Sync
    func syncProfile(_ profile: Profile) async throws {
        try await ensureAuthenticated()
        
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let profileData = try profileToFirestoreData(profile)
        let docRef = db.collection(profilesCollection).document(userId)
        
        try await docRef.setData(profileData, merge: true)
    }
    
    func fetchProfile() async throws -> [String: Any]? {
        try await ensureAuthenticated()
        
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let docRef = db.collection(profilesCollection).document(userId)
        let document = try await docRef.getDocument()
        
        return document.data()
    }
    
    private func profileToFirestoreData(_ profile: Profile) throws -> [String: Any] {
        return [
            "id": profile.id.uuidString,
            "name": profile.name,
            "xp": profile.xp,
            "level": profile.level,
            "currentStreak": profile.currentStreak,
            "bestStreak": profile.bestStreak,
            "lastCompletionDate": profile.lastCompletionDate?.timeIntervalSince1970 as Any,
            "hardcoreResetDeadline": profile.hardcoreResetDeadline?.timeIntervalSince1970 as Any,
            
            // RPG Stats
            "health": profile.health,
            "energy": profile.energy,
            "strength": profile.strength,
            "endurance": profile.endurance,
            "focus": profile.focus,
            "discipline": profile.discipline,
            
            // Health tracking
            "waterIntake": profile.waterIntake,
            "lastMealTime": profile.lastMealTime?.timeIntervalSince1970 as Any,
            "lastWorkoutTime": profile.lastWorkoutTime?.timeIntervalSince1970 as Any,
            "sleepHours": profile.sleepHours,
            "lastStatUpdate": profile.lastStatUpdate.timeIntervalSince1970,
            
            // HealthKit Integration
            "dailySteps": profile.dailySteps,
            "dailyStepsGoal": profile.dailyStepsGoal,
            "restingHeartRate": profile.restingHeartRate,
            "weight": profile.weight,
            "height": profile.height,
            "vo2Max": profile.vo2Max,
            "dailyActiveCalories": profile.dailyActiveCalories,
            "dailyActiveCaloriesGoal": profile.dailyActiveCaloriesGoal,
            
            // Computed metrics (for analytics)
            "bmi": profile.bmi,
            "healthScore": profile.healthScore,
            
            // Sync metadata
            "lastSyncDate": Date().timeIntervalSince1970,
            "deviceId": UIDevice.current.identifierForVendor?.uuidString as Any
        ]
    }
    
    // MARK: - Quest Sync
    func syncQuest(_ quest: Quest) async throws {
        try await ensureAuthenticated()
        
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let questData = questToFirestoreData(quest)
        let docRef = db.collection(questsCollection)
            .document(userId)
            .collection("userQuests")
            .document(quest.id.uuidString)
        
        try await docRef.setData(questData, merge: true)
    }
    
    func fetchQuests(for date: Date) async throws -> [[String: Any]] {
        try await ensureAuthenticated()
        
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)
        
        let snapshot = try await db.collection(questsCollection)
            .document(userId)
            .collection("userQuests")
            .whereField("dateTag", isGreaterThanOrEqualTo: startOfDay.timeIntervalSince1970)
            .whereField("dateTag", isLessThan: endOfDay.timeIntervalSince1970)
            .getDocuments()
        
        return snapshot.documents.map { $0.data() }
    }
    
    func deleteQuest(questId: String) async throws {
        try await ensureAuthenticated()
        
        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let docRef = db.collection(questsCollection)
            .document(userId)
            .collection("userQuests")
            .document(questId)
        
        try await docRef.delete()
    }
    
    private func questToFirestoreData(_ quest: Quest) -> [String: Any] {
        return [
            "id": quest.id.uuidString,
            "title": quest.title,
            "details": quest.details,
            "type": quest.type.rawValue,
            "createdAt": quest.createdAt.timeIntervalSince1970,
            "dueDate": quest.dueDate?.timeIntervalSince1970 as Any,
            "isCompleted": quest.isCompleted,
            "completedAt": quest.completedAt?.timeIntervalSince1970 as Any,
            "repeatDays": quest.repeatDays,
            "xpReward": quest.xpReward,
            "dateTag": quest.dateTag.timeIntervalSince1970,
            "lastSyncDate": Date().timeIntervalSince1970
        ]
    }
    
    // MARK: - Analytics & Events
    func logEvent(_ eventName: String, parameters: [String: Any] = [:]) async {
        guard isAuthenticated, let userId = currentUser?.uid else { return }
        
        var eventData = parameters
        eventData["userId"] = userId
        eventData["timestamp"] = Date().timeIntervalSince1970
        eventData["platform"] = "iOS"
        eventData["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
        do {
            try await db.collection(analyticsCollection).addDocument(data: [
                "eventName": eventName,
                "data": eventData
            ])
        } catch {
            print("Failed to log analytics event: \(error)")
        }
    }
    
    // MARK: - Leaderboard
    func fetchLeaderboard(limit: Int = 50) async throws -> [LeaderboardEntry] {
        let snapshot = try await db.collection(profilesCollection)
            .order(by: "xp", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let name = data["name"] as? String,
                  let xp = data["xp"] as? Int,
                  let level = data["level"] as? Int else {
                return nil
            }
            
            return LeaderboardEntry(
                id: document.documentID,
                name: name,
                xp: xp,
                level: level,
                currentStreak: data["currentStreak"] as? Int ?? 0
            )
        }
    }
    
    // MARK: - Saved Recipes
    func saveRecipe(_ recipe: Recipe) async throws {
        try await ensureAuthenticated()

        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }

        let recipeData: [String: Any] = [
            "id": recipe.id,
            "title": recipe.title,
            "ingredients": recipe.ingredients,
            "servings": recipe.servings,
            "instructions": recipe.instructions,
            "savedAt": Date().timeIntervalSince1970
        ]

        // Use a hash of the title as the document ID for consistency
        let docRef = db.collection(recipesCollection)
            .document(userId)
            .collection("userRecipes")
            .document(recipe.id)

        try await docRef.setData(recipeData)
    }
    
    func fetchSavedRecipes() async throws -> [Recipe] {
        try await ensureAuthenticated()

        guard let userId = currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }

        let snapshot = try await db.collection(recipesCollection)
            .document(userId)
            .collection("userRecipes")
            .order(by: "savedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let title = data["title"] as? String,
                  let ingredients = data["ingredients"] as? String,
                  let servings = data["servings"] as? String,
                  let instructions = data["instructions"] as? String else {
                return nil
            }

            return Recipe(
                title: title,
                ingredients: ingredients,
                servings: servings,
                instructions: instructions
            )
        }
    }
    
    // MARK: - Helper Methods
    private func ensureAuthenticated() async throws {
        if !isAuthenticated {
            try await signInAnonymously()
        }
    }

    deinit {
        if let handle = authStateListenerHandle {
            auth.removeStateDidChangeListener(handle)
        }
    }
}

// MARK: - Firebase Errors
enum FirebaseError: LocalizedError {
    case notAuthenticated
    case notConfigured
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .notConfigured:
            return "Firebase not configured"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}

// MARK: - Leaderboard Entry
struct LeaderboardEntry: Identifiable, Codable {
    let id: String
    let name: String
    let xp: Int
    let level: Int
    let currentStreak: Int
}
