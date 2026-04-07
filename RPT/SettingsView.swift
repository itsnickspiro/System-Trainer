import SwiftUI
import SwiftData
import AuthenticationServices

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @ObservedObject private var dataManager = DataManager.shared
    @State private var showingHealthSettings = false
    @State private var showingProfileEditor = false
    @State private var showingResetConfirmation = false
    @State private var showingBodyMetrics = false
    @State private var showingAchievements = false
    @State private var showingStore = false
    @State private var showingInventory = false
    @State private var showingCreditHistory = false
    @ObservedObject private var playerProfile = PlayerProfileService.shared
    @ObservedObject private var storeService = StoreService.shared
    @ObservedObject private var appleAuth = AppleAuthService.shared
    @State private var showingRestartOnboardingAlert = false
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    @State private var copiedPlayerID = false
    @State private var showingDietInfo = false
    @State private var showingGuildView = false

    private var dietBinding: Binding<DietType> {
        Binding(
            get: { dataManager.currentProfile?.dietType ?? .none },
            set: { newValue in
                dataManager.updateProfile { $0.dietType = newValue }
            }
        )
    }
    
    var profile: Profile {
        if let p = profiles.first { return p }
        let p = Profile()
        context.insert(p)
        return p
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section (Sign in with Apple)
                Section {
                    if appleAuth.isSignedIn {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appleAuth.currentDisplayName ?? "Signed in with Apple")
                                    .font(.subheadline.weight(.semibold))
                                if let email = appleAuth.currentEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        Button(role: .destructive) {
                            appleAuth.signOut()
                        } label: {
                            Label("Sign out of Apple", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign in with Apple to back up your profile and recover it on any other device.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            SignInWithAppleButtonView(label: .signIn) { result in
                                guard let result else { return }
                                Task {
                                    _ = await PlayerProfileService.shared.linkAppleID(
                                        appleUserID: result.userID,
                                        displayName: result.displayName
                                    )
                                }
                            }
                            .frame(height: 50)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if !appleAuth.isSignedIn {
                        Text("Your CloudKit account still works as before — Apple ID is just an extra portable identifier.")
                    }
                }

                // Profile Section
                Section("Player Profile") {
                    Button {
                        showingProfileEditor = true
                    } label: {
                        ProfileSummaryRow(profile: profile)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showingAchievements = true
                    } label: {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading) {
                                Text("Achievements")
                                Text("\(profile.level) levels • \(profile.bestStreak) day streak")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        showingBodyMetrics = true
                    } label: {
                        HStack {
                            Image(systemName: "scalemass.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Body Metrics")
                                Text("Weight & measurements history")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    // Store
                    Button {
                        showingStore = true
                    } label: {
                        HStack {
                            Image(systemName: "bag.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Item Shop")
                                Text("Browse and buy items with XP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    // Inventory
                    Button {
                        showingInventory = true
                    } label: {
                        HStack {
                            Image(systemName: "backpack.fill")
                                .foregroundColor(.teal)
                            VStack(alignment: .leading) {
                                Text("Inventory")
                                Text("Equipped items and consumables")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    // Player ID row — tap anywhere to copy
                    Button {
                        guard !playerProfile.playerId.isEmpty else { return }
                        UIPasteboard.general.string = playerProfile.playerId
                        withAnimation { copiedPlayerID = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copiedPlayerID = false }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Player ID")
                                Text(copiedPlayerID ? "Copied!" : "Tap to copy")
                                    .font(.caption)
                                    .foregroundColor(copiedPlayerID ? .green : .secondary)
                                    .animation(.easeInOut(duration: 0.2), value: copiedPlayerID)
                            }
                            Spacer()
                            let pid = playerProfile.playerId.isEmpty ? "Loading…" : playerProfile.playerId
                            Text(pid)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Image(systemName: copiedPlayerID ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(copiedPlayerID ? .green : .accentColor)
                                .animation(.easeInOut(duration: 0.2), value: copiedPlayerID)
                        }
                    }
                    .disabled(playerProfile.playerId.isEmpty)

                    // Gold Pieces balance row
                    Button {
                        showingCreditHistory = true
                    } label: {
                        HStack {
                            Image(systemName: storeService.currencyIcon)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("\(storeService.currencyName) Balance")
                                Text("View transaction history")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(playerProfile.systemCredits.formatted()) \(storeService.currencySymbol)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }

                // Diet & Nutrition Section
                Section {
                    Picker("Diet Plan", selection: dietBinding) {
                        ForEach(DietType.allCases, id: \.self) { diet in
                            Text(diet.displayName).tag(diet)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showingDietInfo = true
                    } label: {
                        HStack {
                            Image(systemName: "fork.knife.circle")
                                .foregroundColor(.green)
                            Text("Browse diet plans")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text("Diet & Nutrition")
                } footer: {
                    Text("Logged foods that don't match your diet will show a warning before being added to your diary.")
                }

                // Guild Section
                Section {
                    Button {
                        showingGuildView = true
                    } label: {
                        HStack {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profiles.first?.guildName.isEmpty == false ? "Your Guild" : "Find or Create a Guild")
                                if let name = profiles.first?.guildName, !name.isEmpty {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text("Guild")
                } footer: {
                    Text("Join a guild to fight weekly raid bosses with up to 11 other adventurers and split the rewards.")
                }

                // Health Integration Section
                Section("Health Integration") {
                    HStack {
                        Image(systemName: dataManager.healthManager.isAuthorized ? "heart.fill" : "heart")
                            .foregroundColor(dataManager.healthManager.isAuthorized ? .green : .red)
                        VStack(alignment: .leading) {
                            Text("Apple Health")
                            Text(dataManager.healthManager.permissionStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !dataManager.healthManager.isAuthorized && dataManager.healthManager.healthDataAvailable {
                            Button("Connect") {
                                Task {
                                    await dataManager.healthManager.requestAuthorization()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Button("Health Settings") {
                        showingHealthSettings = true
                    }
                }
                
                // App Settings Section
                Section("App Settings") {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(.teal)
                        Text("Units")
                        Spacer()
                        Picker("Units", selection: Binding(
                            get: { profile.useMetric },
                            set: { profile.useMetric = $0; context.safeSave() }
                        )) {
                            Text("Metric (kg)").tag(true)
                            Text("Imperial (lbs)").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.blue)
                            Text("Notifications")
                        }
                    }
                    
                    NavigationLink(destination: GameplaySettingsView()) {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundColor(.purple)
                            Text("Gameplay")
                        }
                    }
                    
                    NavigationLink(destination: AppearanceSettingsView()) {
                        HStack {
                            Image(systemName: "paintbrush.fill")
                                .foregroundColor(.orange)
                            Text("Appearance")
                        }
                    }
                }
                
                // Data Section
                Section("Data Management") {
                    NavigationLink(destination: DataExportView()) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Export Data")
                        }
                    }
                    
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset All Data")
                        }
                    }

                    Button(role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                        showingRestartOnboardingAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restart Onboarding")
                        }
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    // Replace these URLs with your actual hosted privacy policy and terms pages
                    if let privacyURL = URL(string: "https://spiro-technologies.github.io/rpt/privacy") {
                        Link(destination: privacyURL) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundColor(.green)
                                Text("Privacy Policy")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }

                    if let termsURL = URL(string: "https://spiro-technologies.github.io/rpt/terms") {
                        Link(destination: termsURL) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.blue)
                                Text("Terms of Service")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProfileEditor) {
                ProfileEditorView(profile: profile)
            }
            .sheet(isPresented: $showingHealthSettings) {
                HealthSettingsView(healthManager: dataManager.healthManager, profile: profile)
            }
            .sheet(isPresented: $showingBodyMetrics) {
                BodyMetricsView()
            }
            .sheet(isPresented: $showingAchievements) {
                AchievementsView()
            }
            .sheet(isPresented: $showingStore) {
                StoreView()
            }
            .sheet(isPresented: $showingInventory) {
                InventoryView()
            }
            .sheet(isPresented: $showingCreditHistory) {
                CreditHistoryView()
            }
            .sheet(isPresented: $showingGuildView) {
                GuildView()
            }
            .sheet(isPresented: $showingDietInfo) {
                DietInfoView()
            }
            .confirmationDialog(
                "Reset All Data",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all your progress, quests, and settings. This action cannot be undone.")
            }
            .alert("Onboarding Reset", isPresented: $showingRestartOnboardingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Restart the app to begin onboarding again.")
            }
        }
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        .onAppear {
            Task {
                await dataManager.healthManager.requestAuthorization()
            }
        }
    }
    
    private func resetAllData() {
        do {
            // Delete all SwiftData model instances
            try context.delete(model: Profile.self)
            try context.delete(model: Quest.self)
            try context.delete(model: FoodEntry.self)
            try context.delete(model: FoodItem.self)
            try context.delete(model: CustomMeal.self)
            try context.delete(model: CustomMealItem.self)
            try context.delete(model: WorkoutSession.self)
            try context.delete(model: ExerciseSet.self)
            try context.delete(model: ExerciseItem.self)
            try context.delete(model: ActiveRoutine.self)
            try context.delete(model: PersonalRecord.self)
            try context.delete(model: PatrolRoute.self)
            try context.delete(model: InventoryItem.self)
            try context.delete(model: Achievement.self)
            try context.delete(model: BodyMeasurement.self)
            try context.delete(model: PlannedMeal.self)
            try context.delete(model: CustomWorkoutPlan.self)
            try context.save()

            // Clear onboarding flag so the user is sent back to setup
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "userProfileName")
        } catch {
            print("Failed to reset all data: \(error)")
        }
    }
}

struct ProfileSummaryRow: View {
    let profile: Profile
    @ObservedObject private var avatarService = AvatarService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AvatarImageView(key: avatarService.current?.key ?? "avatar_default", size: 50)
                .overlay(
                    Circle()
                        .stroke(avatarService.current?.color ?? .cyan, lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Level \(profile.level) • \(profile.xp) XP")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ProgressView(value: Double(profile.xp), total: Double(profile.levelXPThreshold(level: profile.level)))
                    .tint(.cyan)
                    .frame(width: 150)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Sub-Settings Views

struct NotificationSettingsView: View {
    @AppStorage("questReminders") private var questReminders = true
    @AppStorage("streakWarnings") private var streakWarnings = true
    @AppStorage("levelUpNotifications") private var levelUpNotifications = true
    @AppStorage("healthGoalNotifications") private var healthGoalNotifications = true
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    
    var body: some View {
        List {
            Section("Quest Notifications") {
                Toggle("Daily Quest Reminders", isOn: $questReminders)
                Toggle("Streak Warning", isOn: $streakWarnings)
            }
            
            Section("Achievement Notifications") {
                Toggle("Level Up", isOn: $levelUpNotifications)
                Toggle("Health Goals", isOn: $healthGoalNotifications)
            }
            
            Section {
                Button("Open System Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
            } footer: {
                Text("For notification permissions and advanced settings, use the system Settings app.")
            }
        }
        .navigationTitle("Notifications")
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
    }
}

struct GameplaySettingsView: View {
    @AppStorage("autoGenerateQuests") private var autoGenerateQuests = true
    @AppStorage("weeklyGoalsEnabled") private var weeklyGoalsEnabled = true
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    
    var body: some View {
        List {
            Section("Quest Generation") {
                Toggle("Auto-Generate Daily Quests", isOn: $autoGenerateQuests)
                Toggle("Weekly Goals", isOn: $weeklyGoalsEnabled)
            }
        }
        .navigationTitle("Gameplay")
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("colorScheme") private var colorScheme = "dark"
    @AppStorage("animationsEnabled") private var animationsEnabled = true
    
    var body: some View {
        List {
            Section("Theme") {
                Picker("Color Scheme", selection: $colorScheme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Auto").tag("auto")
                }
            }
            
            Section("Effects") {
                Toggle("Animations", isOn: $animationsEnabled)
            }
        }
        .navigationTitle("Appearance")
        .id(colorScheme)
        .preferredColorScheme(colorScheme == "auto" ? nil : (colorScheme == "dark" ? .dark : .light))
    }
}

struct DataExportView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query(sort: \FoodEntry.dateConsumed) private var foodEntries: [FoodEntry]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var shareItem: URL?
    @State private var showingShareSheet = false
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    var body: some View {
        List {
            Section(header: Text("Export as CSV"), footer: Text("Exports open the iOS share sheet so you can save to Files, email, or any app.")) {
                exportRow(title: "Nutrition Log", icon: "fork.knife", color: .orange, action: exportNutritionCSV)
                exportRow(title: "Workout History", icon: "dumbbell.fill", color: .blue, action: exportWorkoutsCSV)
                exportRow(title: "Body Measurements", icon: "scalemass.fill", color: .green, action: exportMeasurementsCSV)
            }
            Section(header: Text("Export as JSON")) {
                exportRow(title: "Full Profile Backup", icon: "person.fill", color: .purple, action: exportProfileJSON)
            }
        }
        .navigationTitle("Export Data")
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareItem {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text(title)
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundColor(.secondary).font(.caption)
            }
        }
        .foregroundColor(.primary)
    }

    private func writeTemp(_ content: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func share(_ url: URL?) {
        guard let url else { return }
        shareItem = url
        showingShareSheet = true
    }

    private func exportNutritionCSV() {
        var csv = "Date,Meal,Food,Calories,Protein(g),Carbs(g),Fat(g)\n"
        let fmt = DateFormatter(); fmt.dateStyle = .short
        for e in foodEntries {
            let cal = Int(e.totalCalories)
            csv += "\(fmt.string(from: e.dateConsumed)),\(e.meal.displayName),\"\(e.foodItem?.name ?? "")\",\(cal),\(String(format:"%.1f",e.totalProtein)),\(String(format:"%.1f",e.totalCarbs)),\(String(format:"%.1f",e.totalFat))\n"
        }
        share(writeTemp(csv, name: "nutrition_log.csv"))
    }

    private func exportWorkoutsCSV() {
        var csv = "Date,Routine,Duration(min),XP Awarded,Sets\n"
        let fmt = DateFormatter(); fmt.dateStyle = .short
        for s in sessions {
            let sets = s.sets?.count ?? 0
            csv += "\(fmt.string(from: s.startedAt)),\"\(s.routineName)\",\(s.durationMinutes),\(s.xpAwarded),\(sets)\n"
        }
        share(writeTemp(csv, name: "workout_history.csv"))
    }

    private func exportMeasurementsCSV() {
        var csv = "Date,Weight(kg),Chest(cm),Waist(cm),Hips(cm),BodyFat(%),Note\n"
        let fmt = DateFormatter(); fmt.dateStyle = .short
        for m in measurements {
            csv += "\(fmt.string(from: m.date)),\(m.weightKg),\(m.chestCm.map{String(format:"%.1f",$0)} ?? ""),\(m.waistCm.map{String(format:"%.1f",$0)} ?? ""),\(m.hipsCm.map{String(format:"%.1f",$0)} ?? ""),\(m.bodyFatPercent.map{String(format:"%.1f",$0)} ?? ""),\"\(m.note)\"\n"
        }
        share(writeTemp(csv, name: "body_measurements.csv"))
    }

    private func exportProfileJSON() {
        guard let p = profiles.first else { return }
        let dict: [String: Any] = [
            "name": p.name, "level": p.level, "xp": p.xp,
            "currentStreak": p.currentStreak, "bestStreak": p.bestStreak,
            "weight": p.weight, "height": p.height, "age": p.age,
            "gender": p.genderRaw, "fitnessGoal": p.fitnessGoalRaw,
            "dailyStepsGoal": p.dailyStepsGoal, "weeklyWorkoutGoal": p.weeklyWorkoutGoal,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return }
        share(writeTemp(str, name: "rpt_profile_backup.json"))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .modelContainer(for: [
            Quest.self, Profile.self,
            FoodItem.self, FoodEntry.self, CustomMeal.self, CustomMealItem.self,
            WorkoutSession.self, ExerciseSet.self, ExerciseItem.self, ActiveRoutine.self,
            PersonalRecord.self, PatrolRoute.self, InventoryItem.self,
            Achievement.self, BodyMeasurement.self, PlannedMeal.self, CustomWorkoutPlan.self
        ], inMemory: true)
}

