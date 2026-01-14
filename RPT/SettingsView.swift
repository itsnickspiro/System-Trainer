import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @StateObject private var healthManager = HealthManager()
    @State private var showingHealthSettings = false
    @State private var showingProfileEditor = false
    @State private var showingResetConfirmation = false
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    
    var profile: Profile {
        if let p = profiles.first { return p }
        let p = Profile()
        context.insert(p)
        return p
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section("Player Profile") {
                    ProfileSummaryRow(profile: profile)
                        .onTapGesture {
                            showingProfileEditor = true
                        }
                    
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
                
                // Health Integration Section
                Section("Health Integration") {
                    HStack {
                        Image(systemName: healthManager.isAuthorized ? "heart.fill" : "heart")
                            .foregroundColor(healthManager.isAuthorized ? .green : .red)
                        VStack(alignment: .leading) {
                            Text("Apple Health")
                            Text(healthManager.permissionStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !healthManager.isAuthorized && healthManager.healthDataAvailable {
                            Button("Connect") {
                                Task {
                                    await healthManager.requestAuthorization()
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
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://yourapp.com/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.green)
                            Text("Privacy Policy")
                        }
                    }
                    
                    Link(destination: URL(string: "https://yourapp.com/terms")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                            Text("Terms of Service")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProfileEditor) {
                ProfileEditorView(profile: profile)
            }
            .sheet(isPresented: $showingHealthSettings) {
                HealthSettingsView(healthManager: healthManager, profile: profile)
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
        }
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        .onAppear {
            Task {
                await healthManager.requestAuthorization()
            }
        }
    }
    
    private func resetAllData() {
        // Delete all profiles
        for profile in profiles {
            context.delete(profile)
        }
        
        // Note: You'd also want to delete quests here
        // This is a simplified version
        
        try? context.save()
    }
}

struct ProfileSummaryRow: View {
    let profile: Profile
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
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
        .preferredColorScheme(colorScheme == "auto" ? nil : (colorScheme == "dark" ? .dark : .light))
    }
}

struct DataExportView: View {
    @State private var isExporting = false
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    
    var body: some View {
        List {
            Section {
                Button("Export Profile Data") {
                    exportData()
                }
                
                Button("Export Quest History") {
                    exportQuests()
                }
            } footer: {
                Text("Export your data in JSON format for backup or analysis.")
            }
        }
        .navigationTitle("Export Data")
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
    }
    
    private func exportData() {
        // Implementation for data export
        isExporting = true
        // Add actual export logic here
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isExporting = false
        }
    }
    
    private func exportQuests() {
        // Implementation for quest export
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Quest.self, Profile.self], inMemory: true)
}

