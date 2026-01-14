import SwiftUI
import SwiftData
import Firebase

@main
@MainActor
struct RPTApp: App {
    @AppStorage("colorScheme") private var colorScheme = "dark"
    @State private var isOnboardingComplete = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Quest.self,
            Profile.self,
            FoodItem.self,
            FoodEntry.self,
            CustomMeal.self,
        ])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            // Try creating a persistent (on-disk) container first
            return try ModelContainer(for: schema, configurations: [diskConfig])
        } catch {
            // Fall back to an in-memory store to keep the app running during development
            // Common causes: incompatible/corrupted store or schema changes without migration.
            // You can reset the simulator’s data or delete the app to clear the old store.
            print("[SwiftData] Failed to create persistent container: \(error). Falling back to in-memory store.")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }()

    init() {
        // Ensure Firebase is configured exactly once and on the main actor.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("[Firebase] Configured")
        } else {
            print("[Firebase] Already configured")
        }
        
        // Set up initial user defaults
        setupUserDefaults()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboardingComplete {
                    ContentView()
                        .onAppear {
                            // Initialize sample food data
                            SampleFoodData.createSampleFoods(context: sharedModelContainer.mainContext)
                        }
                } else {
                    OnboardingView(isOnboardingComplete: $isOnboardingComplete)
                }
            }
            .preferredColorScheme(colorScheme == "auto" ? nil : (colorScheme == "dark" ? .dark : .light))
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func setupUserDefaults() {
        let defaults = UserDefaults.standard
        
        // Set default notification preferences
        if defaults.object(forKey: "questReminders") == nil {
            defaults.set(true, forKey: "questReminders")
        }
        if defaults.object(forKey: "streakWarnings") == nil {
            defaults.set(true, forKey: "streakWarnings")
        }
        if defaults.object(forKey: "levelUpNotifications") == nil {
            defaults.set(true, forKey: "levelUpNotifications")
        }
        if defaults.object(forKey: "healthGoalNotifications") == nil {
            defaults.set(true, forKey: "healthGoalNotifications")
        }
        
        // Set default gameplay preferences
        if defaults.object(forKey: "hardcoreMode") == nil {
            defaults.set(false, forKey: "hardcoreMode")
        }
        if defaults.object(forKey: "autoGenerateQuests") == nil {
            defaults.set(true, forKey: "autoGenerateQuests")
        }
        if defaults.object(forKey: "weeklyGoalsEnabled") == nil {
            defaults.set(true, forKey: "weeklyGoalsEnabled")
        }
        
        // Set default appearance preferences
        if defaults.object(forKey: "colorScheme") == nil {
            defaults.set("dark", forKey: "colorScheme")
        }
        if defaults.object(forKey: "animationsEnabled") == nil {
            defaults.set(true, forKey: "animationsEnabled")
        }
    }
}
