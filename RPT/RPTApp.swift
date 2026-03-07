import SwiftUI
import SwiftData

@main
@MainActor
struct RPTApp: App {
    @AppStorage("colorScheme") private var colorScheme = "dark"
    @State private var isOnboardingComplete = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var hasBootedUp = false
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Quest.self,
            Profile.self,
            FoodItem.self,
            FoodEntry.self,
            CustomMeal.self,
            CustomMealItem.self,
            ExerciseItem.self,
            // New models — Part 2 & 4
            WorkoutSession.self,
            ExerciseSet.self,
            ActiveRoutine.self,
            PersonalRecord.self,
            PatrolRoute.self,
            InventoryItem.self,
        ])

        // CloudKit private database sync is enabled by passing a cloudKitDatabase
        // argument to ModelConfiguration. SwiftData bridges to
        // NSPersistentCloudKitContainer automatically.
        //
        // Requirements:
        //   • The bundle's iCloud container (iCloud.<bundleID>) must be created in
        //     the Apple Developer portal and added under Signing & Capabilities →
        //     iCloud → CloudKit Containers in Xcode.
        //   • All @Model properties must be optional or have defaults (done above).
        //   • All @Relationship targets must be optional (done above).
        //
        // The container identifier must exactly match what is registered in the
        // Developer portal. By convention it mirrors the bundle ID.
        // Must match exactly what is in RPT.entitlements and the Apple Developer portal.
        let cloudKitContainerID = "iCloud.com.SpiroTechnologies.RPT"

        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // CloudKit config can fail in the Simulator (no iCloud account) or when
            // the entitlement isn't set up yet. Fall back to a local-only store so
            // development remains unblocked.
            print("[SwiftData] CloudKit container failed (\(error)). Falling back to local store.")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    init() {
        setupUserDefaults()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasBootedUp {
                    // Boot screen shown once per cold launch
                    BootScreenView(onComplete: { hasBootedUp = true })
                        .preferredColorScheme(.dark)
                } else if isOnboardingComplete {
                    ContentView()
                        .onAppear {
                            SampleFoodData.createSampleFoods(context: sharedModelContainer.mainContext)
                            SystemDataSeeder.seedIfNeeded(context: sharedModelContainer.mainContext)
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
