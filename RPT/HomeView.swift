import SwiftUI
import SwiftData
import Combine

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataManager = DataManager.shared
    @State private var now: Date = Date()
    @State private var rotationAngle: Double = 0
    @State private var showingHealthPermissions = false
    @State private var showingSettingsSheet = false
    @State private var selectedStatForDetails: RPGStatsBar.StatType? = nil
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var profile: Profile? {
        dataManager.currentProfile
    }
    
    var todaysQuests: [Quest] {
        dataManager.todaysQuests
    }
    
    var body: some View {
        ZStack {
            // Background with adaptive color
            Rectangle()
                .fill(colorScheme == .dark ? .black.opacity(0.8) : .white)
                .ignoresSafeArea(.all)
            
            // Animated grid overlay (only in dark mode)
            if colorScheme == .dark {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in
                        Rectangle()
                            .stroke(.cyan.opacity(0.1), lineWidth: 0.5)
                            .frame(height: 50)
                    }
                }
                .ignoresSafeArea()
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    // Player Card (now contains core attributes)
                    playerCard

                    // Quests to complete
                    questSummaryCard
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
        }
        .onReceive(timer) { t in
            now = t
            
            guard let currentProfile = profile else { return }
            
            currentProfile.applyHardcoreResetIfNeeded(now: now)
            currentProfile.updateDailyStats()
            
            // Subtle rotation animation for UI elements
            withAnimation(.linear(duration: 1)) {
                rotationAngle += 1
            }
        }
        .onAppear {
            Task {
                await dataManager.healthManager.requestAuthorization()
                
                if dataManager.healthManager.needsHealthPermissions {
                    showingHealthPermissions = true
                }
            }
        }
        .alert("Health Integration", isPresented: $showingHealthPermissions) {
            Button("Enable Access") {
                Task {
                    await dataManager.healthManager.requestAuthorization()
                }
            }
            Button("Use Mock Data") {
                showingHealthPermissions = false
            }
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text(dataManager.healthManager.permissionStatusMessage)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStatForDetails) { stat in
            if let currentProfile = profile {
                VStack {
                    StatDetailView(stat: stat, profile: currentProfile)
                }
                .padding()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled)
            }
        }
    }
    
    private var playerCard: some View {
        Group {
            if let currentProfile = profile {
                ZStack {
                    // Main card background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                                .shadow(color: .cyan, radius: 10, x: 0, y: 0)
                        )
                    
                    VStack(spacing: 20) {
                        // Header with avatar and name only
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PLAYER")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.8))
                                Text(currentProfile.name)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }

                            Spacer()

                            Button {
                                showingSettingsSheet = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open Settings")
                        }
                        
                        ZStack(alignment: .leading) {
                            // Centered XP ring with avatar
                            CurvedXPBar(
                                currentXP: currentProfile.xp,
                                level: currentProfile.level,
                                threshold: currentProfile.levelXPThreshold(level: currentProfile.level),
                                profileName: currentProfile.name
                            )
                            .frame(maxWidth: .infinity, alignment: .center)

                            // Left-side slim vertical column of compact stat rings
                            VStack(alignment: .leading, spacing: 6) {
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.health.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.health.color,
                                    icon: RPGStatsBar.StatType.health.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .health }
                                )
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.energy.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.energy.color,
                                    icon: RPGStatsBar.StatType.energy.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .energy }
                                )
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.strength.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.strength.color,
                                    icon: RPGStatsBar.StatType.strength.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .strength }
                                )
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.endurance.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.endurance.color,
                                    icon: RPGStatsBar.StatType.endurance.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .endurance }
                                )
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.focus.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.focus.color,
                                    icon: RPGStatsBar.StatType.focus.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .focus }
                                )
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.discipline.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.discipline.color,
                                    icon: RPGStatsBar.StatType.discipline.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .discipline }
                                )
                            }
                            .padding(.leading, 0)
                        }
                        
                        // Compact Streak/Best below XP bar, aligned to trailing
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                VStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.orange)
                                    Text("\(currentProfile.currentStreak)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                VStack(spacing: 2) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.green)
                                    Text("\(currentProfile.bestStreak)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Loading state
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .frame(height: 300)
                    .overlay(
                        ProgressView("Loading Profile...")
                            .foregroundColor(.cyan)
                    )
            }
        }
    }
    
    private func statBlock(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(color.opacity(0.8))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private var questSummaryCard: some View {
        let todays = todaysQuests
        let completed = todays.filter { $0.isCompleted }.count
        _ = todays.filter { $0.type == .daily }
        let upcomingQuests = todays.filter { !$0.isCompleted }.prefix(3)
        
        return VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MISSION STATUS")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                    Text("Daily Quests")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(completed)/\(todays.count)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(completed == todays.count ? .green : .orange)
                    Text("COMPLETE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar for daily completion
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(0.3))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: completed == todays.count ? [.green, .mint] : [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: todays.count > 0 ? geo.size.width * (Double(completed) / Double(todays.count)) : 0)
                        .animation(.easeInOut(duration: 0.5), value: completed)
                }
            }
            .frame(height: 12)
            
            // Quick quest preview
            if !upcomingQuests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE MISSIONS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                    
                    ForEach(Array(upcomingQuests), id: \.id) { quest in
                        HStack {
                            Circle()
                                .fill(quest.type.color)
                                .frame(width: 8, height: 8)
                            
                            Text(quest.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("+\(quest.xpReward) XP")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.orange.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helper Functions
    
    private func timeToMidnightString() -> String {
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        return timeRemaining(until: midnight)
    }
    
    private func timeRemaining(until date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: now, to: date)
        let h = comps.hour ?? 0, m = comps.minute ?? 0, s = comps.second ?? 0
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Quest.self, Profile.self], inMemory: true)
}
