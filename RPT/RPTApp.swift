import SwiftUI
import SwiftData
import WidgetKit

extension Notification.Name {
    static let rptAddFriendDeepLink = Notification.Name("rptAddFriendDeepLink")
    static let rptNavigateToTab = Notification.Name("rptNavigateToTab")
}

@main
@MainActor
struct RPTApp: App {
    @AppStorage("colorScheme") private var colorScheme = "dark"
    @State private var isOnboardingComplete = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var hasBootedUp = false
    @State private var notificationManager = NotificationManager()



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
            CustomWorkoutPlan.self,
            Achievement.self,
            BodyMeasurement.self,
            PlannedMeal.self,
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
            // RootContainerView is a stable wrapper whose identity never changes.
            // The .task is attached here so it is never cancelled when the inner
            // view switches between BootScreenView → OnboardingView → ContentView.
            // Previously the .task was on the Group, which got cancelled and
            // restarted on every view-tree replacement, causing hangs on TestFlight.
            RootContainerView(
                hasBootedUp: $hasBootedUp,
                isOnboardingComplete: $isOnboardingComplete,
                modelContainer: sharedModelContainer,
                onBootComplete: handleBootComplete
            )
            .preferredColorScheme(colorScheme == "auto" ? nil : (colorScheme == "dark" ? .dark : .light))
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .rptWidgetDataDidChange)) { _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
            // ── Service refresh chain ──────────────────────────────────────────
            // Attached to RootContainerView (stable identity) so it runs ONCE on
            // launch and is never cancelled by inner view transitions.
            //
            // Order matters:
            //  1. CloudKit user ID — must resolve before any service that needs it.
            //     Uses a 10-second timeout internally; failure is non-fatal.
            //  2. RemoteConfig — feature flags needed by later services.
            //  3. PlayerProfile — needs CloudKit ID, must come after step 1.
            //  4–10. All other services in dependency order.
            .task {
                // Step 1: Resolve CloudKit identity first (10-second timeout, non-fatal)
                await LeaderboardService.shared.resolveCloudKitUserIDIfNeeded()

                // Step 2: Notification permission (non-blocking UI)
                await notificationManager.requestAuthorization()
                if notificationManager.isAuthorized {
                    notificationManager.setupNotificationCategories()
                    notificationManager.configureRecurringNotifications()
                }
                // Step 3: Remote config — feature flags / thresholds available ASAP
                await RemoteConfigService.shared.refresh()
                // Step 4: Cloud player profile (account recovery, overrides)
                await PlayerProfileService.shared.refresh()
                // Step 5: Quest templates and arcs
                await QuestTemplateService.shared.refresh()
                // Step 6: Achievement definitions
                await AchievementsService.shared.refresh()
                // Step 7: Announcements filtered by player level
                await AnnouncementsService.shared.refresh()
                // Step 8: Store catalog and player inventory
                await StoreService.shared.refresh()
                // Step 9: Special events and participation records
                await EventsService.shared.refresh()
                // Step 10: Anime workout plans (falls back to bundled data)
                await AnimeWorkoutPlanService.shared.refresh()
                // Step 11: Leaderboard upsert + rankings (CloudKit ID already resolved)
                await LeaderboardService.shared.refresh()
                // Step 12: Avatar catalog and current equipped avatar
                await AvatarService.shared.refresh()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Boot Completion

    private func handleBootComplete() {
        hasBootedUp = true
    }

    // MARK: - Deep Links

    /// Handles incoming deep links.
    /// - `rpt://addfriend/XXXXXX`          → friend invite
    /// - `rpt://quests`                    → navigate to Quests tab (from widget)
    /// - `rpt://diet`                      → navigate to Diet tab (from widget)
    /// - `systemtrainer://addfriend/XXXXXX` → friend invite (new scheme)
    /// - `systemtrainer://quests`           → navigate to Quests tab (new scheme)
    /// - `systemtrainer://diet`             → navigate to Diet tab (new scheme)
    private func handleDeepLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "rpt" || scheme == "systemtrainer" else { return }
        let host = url.host?.lowercased() ?? ""

        switch host {
        case "addfriend":
            let code = url.pathComponents.dropFirst().first?.uppercased() ?? ""
            guard code.count == 6 else { return }
            NotificationCenter.default.post(
                name: .rptAddFriendDeepLink,
                object: nil,
                userInfo: ["code": code]
            )
        case "quests":
            NotificationCenter.default.post(name: .rptNavigateToTab, object: nil, userInfo: ["tab": "quests"])
        case "diet":
            NotificationCenter.default.post(name: .rptNavigateToTab, object: nil, userInfo: ["tab": "diet"])
        default:
            break
        }
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

// MARK: - RootContainerView
//
// A stable wrapper with a fixed identity so the .task modifier on RPTApp
// is never cancelled when the inner view changes between boot / onboarding / main.

private struct RootContainerView: View {
    @Binding var hasBootedUp: Bool
    @Binding var isOnboardingComplete: Bool
    let modelContainer: ModelContainer
    let onBootComplete: () -> Void

    @State private var didSeedData = false

    var body: some View {
        Group {
            if !hasBootedUp {
                BootScreenView(onComplete: onBootComplete)
                    .preferredColorScheme(.dark)
            } else if isOnboardingComplete {
                ContentView()
                    .onAppear {
                        guard !didSeedData else { return }
                        didSeedData = true
                        let ctx = modelContainer.mainContext
                        SampleFoodData.createSampleFoods(context: ctx)
                        SystemDataSeeder.seedIfNeeded(context: ctx)
                    }
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
    }
}
