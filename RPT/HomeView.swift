import SwiftUI
import SwiftData
import Combine

// Rolling 30-day window for bounded @Query predicates in HomeView.
private let homeViewSessionCutoff: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var achievementManager = AchievementManager.shared
    @ObservedObject private var avatarService = AvatarService.shared
    @Query(filter: #Predicate<WorkoutSession> { session in
        session.startedAt >= homeViewSessionCutoff
    }, sort: \WorkoutSession.startedAt, order: .reverse) private var recentSessions: [WorkoutSession]

    @State private var now: Date = Date()
    @State private var lastTickMinute: Int = -1
    @State private var rotationAngle: Double = 0
    @State private var showingHealthPermissions = false
    @State private var showingSettingsSheet = false
    @State private var showingInventorySheet = false
    @State private var selectedStatForDetails: RPGStatsBar.StatType? = nil
    // Level-up animation state
    @State private var showingLevelUp = false
    @State private var levelUpLevel: Int = 0
    @State private var levelUpParticleScale: CGFloat = 0
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
            
            
            ScrollView {
                VStack(spacing: 32) {
                    // Player Card (now contains core attributes)
                    playerCard

                    // Rehabilitation Arc banner (shown for 3 days after a Level 1 reset)
                    if let currentProfile = profile, currentProfile.isInRecovery {
                        rehabilitationBanner(for: currentProfile)
                    }

                    // Exemption Pass earned notification
                    if let currentProfile = profile, currentProfile.exemptionPassCount > 0 {
                        exemptionPassBanner(for: currentProfile)
                    }

                    // Recovery / deload recommendation
                    if let currentProfile = profile {
                        recoveryRecommendationCard(for: currentProfile)
                    }

                    // Quests to complete
                    // Active weekly raid boss — renders if a boss is alive
                    // for the current week.
                    BossRaidCard()

                    // Guild raid summary — only renders if the player is in
                    // a guild AND that guild has an active weekly raid.
                    GuildBannerView()

                    // Rival head-to-head — only renders when the player
                    // has set a rival from the leaderboard.
                    RivalBannerView()

                    // Weekly AI review briefing — renders only on Mondays
                    // and only until the user taps the dismiss button.
                    WeeklyReviewCard()

                    // Weight log card
                    if let currentProfile = profile {
                        WeightLogCard(profile: currentProfile)
                    }

                    // Activity logger
                    activityLogButton

                    questSummaryCard

                    Spacer(minLength: 50)
                }
                .padding()
            }
        }
        .overlay(alignment: .top) {
            // Achievement unlock banner
            if let id = achievementManager.recentlyUnlocked {
                AchievementUnlockBanner(id: id)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .id(id)
            }
        }
        .overlay {
            // Level-up overlay
            if showingLevelUp {
                LevelUpOverlay(level: levelUpLevel, particleScale: $levelUpParticleScale) {
                    withAnimation(.easeOut) {
                        showingLevelUp = false
                    }
                }
                .transition(.opacity)
                .zIndex(200)
            }
        }
        // Isekai-style system notification overlay (fires on milestones:
        // first quest, first workout, level 5/10/25, first 7-day streak, etc.)
        .overlay { SystemSkillBannerView() }
        // First-run coach-mark tour — renders only if the user has never
        // completed it, starts automatically when Home first appears.
        .overlay { CoachMarkOverlay() }
        .task {
            // Kick off the weekly AI review generation and the first-run tour
            // check once the view mounts. Both are idempotent and safe to
            // re-run on every appearance.
            CoachMarkTourManager.shared.startIfNeeded()
            await WeeklyReviewService.shared.refreshIfNeeded(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityLogged)) { notification in
            guard let info = notification.userInfo,
                  let activityName = info["activityName"] as? String,
                  let workoutType = info["workoutType"] as? String,
                  let durationMinutes = info["durationMinutes"] as? Int,
                  let xpEarned = info["xpEarned"] as? Int else { return }

            // Create a WorkoutSession for the activity
            let session = WorkoutSession(routineName: activityName)
            session.startedAt = Date().addingTimeInterval(-Double(durationMinutes * 60))
            session.finishedAt = Date()
            session.durationMinutes = durationMinutes
            session.xpAwarded = xpEarned
            context.insert(session)

            // Award XP to the profile
            if let p = profile {
                p.xp += xpEarned
                p.totalXPEarned += xpEarned
            }
            context.safeSave()

            // Auto-complete matching workout quests
            if let wt = WorkoutType(rawValue: workoutType) {
                _ = dataManager.autoCompleteWorkoutQuests(for: wt)
            }

            PhoneSessionManager.shared.sendStats()
        }
        .onReceive(timer) { t in
            now = t

            // Gate the expensive per-tick work to once per minute.
            let minute = Calendar.current.component(.minute, from: now)
            guard minute != lastTickMinute else { return }
            lastTickMinute = minute

            guard let currentProfile = profile else { return }

            let prevLevel = currentProfile.level
            currentProfile.applyHardcoreResetIfNeeded(now: now)
            currentProfile.updateDailyStats()
            
            // Trigger level-up animation if level changed
            if currentProfile.level > prevLevel {
                levelUpLevel = currentProfile.level
                // Haptic feedback for level-up milestone
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring()) {
                    showingLevelUp = true
                    levelUpParticleScale = 1
                }
                // Auto-dismiss after 3s
                Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    await MainActor.run {
                        withAnimation { showingLevelUp = false; levelUpParticleScale = 0 }
                    }
                }
            }

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
        .alert("Training Grid Offline", isPresented: $showingHealthPermissions) {
            Button("Sync the Grid") {
                Task {
                    await dataManager.healthManager.requestAuthorization()
                }
            }
            Button("Train Manually") {
                showingHealthPermissions = false
            }
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Connect Apple Health to auto-complete step, sleep, and calorie quests — and unlock passive XP every time your body moves.")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingInventorySheet) {
            InventoryAndShopView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { selectedStatForDetails != nil },
            set: { if !$0 { selectedStatForDetails = nil } }
        )) {
            if let stat = selectedStatForDetails, let currentProfile = profile {
                StatDetailView(stat: stat, profile: currentProfile)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .presentationDetents([.height(220)])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationCornerRadius(20)
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
                                .stroke(LinearGradient(colors: [.cyan.opacity(0.4), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                .shadow(color: .cyan, radius: 10, x: 0, y: 0)
                        )
                    
                    VStack(spacing: 20) {
                        // Header with avatar, name, and rank badge
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PLAYER")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(colorScheme == .dark ? .cyan.opacity(0.8) : .teal)
                                Text(currentProfile.name)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                // DBZ-style scouter badge — recomputes live as
                                // stats / level / streak / XP change.
                                PowerLevelBadge(profile: currentProfile)
                                    .padding(.top, 2)
                            }

                            Spacer()

                            // Tier rank badge
                            let tier = QuestManager.tier(for: currentProfile.level)
                            Text(tier.rank.displayName)
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(tierRankColor(tier.rank))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(tierRankColor(tier.rank).opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(tierRankColor(tier.rank).opacity(0.6), lineWidth: 1.5)
                                        )
                                )

                            Button {
                                showingInventorySheet = true
                            } label: {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open Inventory")
                        }
                        
                        ZStack(alignment: .leading) {
                            // Centered XP ring with avatar
                            CurvedXPBar(
                                currentXP: currentProfile.xp,
                                level: currentProfile.level,
                                threshold: currentProfile.levelXPThreshold(level: currentProfile.level),
                                profileName: currentProfile.name,
                                avatarKey: avatarService.current?.key
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
                                .accessibilityLabel("Health: \(Int(RPGStatsBar.StatType.health.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.energy.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.energy.color,
                                    icon: RPGStatsBar.StatType.energy.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .energy }
                                )
                                .accessibilityLabel("Energy: \(Int(RPGStatsBar.StatType.energy.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.strength.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.strength.color,
                                    icon: RPGStatsBar.StatType.strength.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .strength }
                                )
                                .accessibilityLabel("Strength: \(Int(RPGStatsBar.StatType.strength.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.endurance.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.endurance.color,
                                    icon: RPGStatsBar.StatType.endurance.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .endurance }
                                )
                                .accessibilityLabel("Endurance: \(Int(RPGStatsBar.StatType.endurance.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.focus.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.focus.color,
                                    icon: RPGStatsBar.StatType.focus.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .focus }
                                )
                                .accessibilityLabel("Focus: \(Int(RPGStatsBar.StatType.focus.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                                CurvedStatRing(
                                    progress: min(1.0, RPGStatsBar.StatType.discipline.getValue(from: currentProfile) / 100.0),
                                    color: RPGStatsBar.StatType.discipline.color,
                                    icon: RPGStatsBar.StatType.discipline.icon,
                                    size: 40,
                                    lineWidth: 3,
                                    action: { selectedStatForDetails = .discipline }
                                )
                                .accessibilityLabel("Discipline: \(Int(RPGStatsBar.StatType.discipline.getValue(from: currentProfile)))%")
                                .accessibilityHint("Double-tap to view details")
                            }
                            .padding(.leading, 0)
                        }
                        
                        // Coaching tagline + streak stats on one balanced row
                        HStack(alignment: .center) {
                            coachingBanner(for: currentProfile)
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
                .fill(color.opacity(0.08))
                .stroke(color.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    // MARK: - Rehabilitation Arc Banner

    @ViewBuilder
    private func rehabilitationBanner(for profile: Profile) -> some View {
        let daysLeft = profile.recoveryDaysRemaining
        let dayNum = max(1, 4 - daysLeft)

        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("REHABILITATION ARC")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                    Text("DAY \(dayNum)/3")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.15)))
                }
                Text("System failure detected. Reduced difficulty protocols active — \(daysLeft) day\(daysLeft == 1 ? "" : "s") remaining. Rebuild your foundation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { day in
                        Circle()
                            .fill(day < dayNum ? Color.red : (day == dayNum ? Color.red : Color.red.opacity(0.2)))
                            .frame(width: 8, height: 8)
                    }
                    Text("Recovery complete at Day 3")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Exemption Pass Banner

    @ViewBuilder
    private func exemptionPassBanner(for profile: Profile) -> some View {
        let count = profile.exemptionPassCount
        // Only show once per milestone (i.e., when count was just awarded)
        // We show a persistent indicator so the player knows they have protection
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "shield.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("EXEMPTION PASS ACTIVE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                Text("You have \(count) Hermit's Miracle Seed\(count == 1 ? "" : "s"). The System will consume one automatically if you miss the midnight deadline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Pass count badge
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.cyan)
                Text("PASS\(count == 1 ? "" : "ES")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Recovery / Deload Recommendation Card

    /// Returns a recommendation level based on HRV, sleep, and recent workout frequency.
    /// - Returns: .rest, .deload, .train, or nil (not enough data)
    private enum RecoveryStatus { case train, rest, deload }

    private func recoveryStatus(for profile: Profile) -> RecoveryStatus {
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let workoutsThisWeek = recentSessions.filter { $0.startedAt >= sevenDaysAgo }.count

        let hrv = profile.heartRateVariability   // ms SDNN, 0 = no data
        let sleep = profile.sleepHours            // hours last night
        let rhr = Double(profile.restingHeartRate) // bpm, 0 = no data

        // Deload signals: 5+ workouts in 7 days AND (low HRV OR poor sleep OR elevated RHR)
        let highFrequency = workoutsThisWeek >= 5
        let lowHRV = hrv > 0 && hrv < 30          // below 30 ms = suppressed recovery
        let poorSleep = sleep > 0 && sleep < 6.5
        let elevatedRHR = rhr > 0 && rhr > 72

        if highFrequency && (lowHRV || elevatedRHR) {
            return .deload
        }
        if (lowHRV && poorSleep) || (poorSleep && workoutsThisWeek >= 4) {
            return .rest
        }
        return .train
    }

    @ViewBuilder
    private func recoveryRecommendationCard(for profile: Profile) -> some View {
        let status = recoveryStatus(for: profile)
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let workoutsThisWeek = recentSessions.filter { $0.startedAt >= sevenDaysAgo }.count

        // Only show if there's something meaningful to say
        if status == .rest || status == .deload || workoutsThisWeek >= 3 {
            let (icon, title, message, accentColor): (String, String, String, Color) = {
                switch status {
                case .deload:
                    return ("battery.25", "Deload Recommended",
                            "You've trained \(workoutsThisWeek)× this week with signs of fatigue. Consider a lighter session — reduce weight by 40–50% and focus on form.",
                            .orange)
                case .rest:
                    return ("moon.zzz.fill", "Rest Day Recommended",
                            "Low sleep or suppressed HRV detected. An active recovery walk, stretching, or a full rest day will accelerate adaptation.",
                            .blue)
                case .train:
                    return ("bolt.heart.fill", "Ready to Train",
                            "\(workoutsThisWeek) workout\(workoutsThisWeek == 1 ? "" : "s") this week. Recovery signals look good — push hard today.",
                            .green)
                }
            }()

            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(accentColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(accentColor)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Activity Logger Button

    @State private var showActivityLogger = false

    private var activityLogButton: some View {
        Button {
            showActivityLogger = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("LOG ACTIVITY")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Text("Walk, yard work, sports...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showActivityLogger) {
            ActivityLoggerView()
        }
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
                                .minimumScaleFactor(0.8)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Text("+\(quest.xpReward) XP")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                if quest.creditReward > 0 {
                                    Text("•")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("+\(quest.creditReward) \(RemoteConfigService.shared.string("currency_symbol", default: "GP"))")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                }
                            }
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
                        .stroke(.orange.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Coaching Banner

    /// Returns a card that surfaces the player's weakest stat with tier-appropriate motivation.
    @ViewBuilder
    private func coachingBanner(for currentProfile: Profile) -> some View {
        let tier = QuestManager.tier(for: currentProfile.level)
        let weak = weakestStat(for: currentProfile)
        let message = coachingMessage(stat: weak.name, tier: tier.rank, value: weak.value)

        HStack(spacing: 8) {
            Image(systemName: weak.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(weak.color)

            Text(message.headline)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private struct WeakStat {
        let name: String
        let value: Double
        let icon: String
        let color: Color
    }

    private func weakestStat(for p: Profile) -> WeakStat {
        let candidates: [(name: String, value: Double, icon: String, color: Color)] = [
            ("Strength",   p.strength,   "dumbbell.fill",      RPGStatsBar.StatType.strength.color),
            ("Endurance",  p.endurance,  "heart.fill",         RPGStatsBar.StatType.endurance.color),
            ("Focus",      p.focus,      "brain.head.profile", RPGStatsBar.StatType.focus.color),
            ("Discipline", p.discipline, "bolt.fill",          RPGStatsBar.StatType.discipline.color),
            ("Health",     p.health,     "cross.fill",         RPGStatsBar.StatType.health.color),
            ("Energy",     p.energy,     "flame.fill",         RPGStatsBar.StatType.energy.color),
        ]
        let weakest = candidates.min(by: { $0.value < $1.value }) ?? candidates[0]
        return WeakStat(name: weakest.name, value: weakest.value, icon: weakest.icon, color: weakest.color)
    }

    private struct CoachingMessage {
        let headline: String
        let tip: String
    }

    private func coachingMessage(stat: String, tier: QuestManager.TierRank, value: Double) -> CoachingMessage {
        switch tier {
        case .e:
            // Rank E — beginner, encouraging and educational
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "Build your foundation.", tip: "Start with bodyweight or light resistance. Consistency beats intensity."),
                "Endurance":  .init(headline: "Your lungs need training too.", tip: "Add a 15-minute walk or jog to your next session."),
                "Focus":      .init(headline: "The mind leads the body.", tip: "Try 5 minutes of deep breathing before your workout."),
                "Discipline": .init(headline: "Show up even when you don't feel like it.", tip: "Discipline is a skill — train it daily."),
                "Health":     .init(headline: "Recovery is part of training.", tip: "Sleep 7–9 hours and stay hydrated every day."),
                "Energy":     .init(headline: "Fuel your training.", tip: "Eat a balanced meal 1–2 hours before workouts."),
            ]
            return tips[stat] ?? .init(headline: "Keep showing up.", tip: "Every rep counts at this stage.")

        case .d:
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "\(stat) is your weak link.", tip: "Add one strength session per week with progressive overload."),
                "Endurance":  .init(headline: "\(stat) needs attention.", tip: "Push your cardio sessions to 30+ minutes consistently."),
                "Focus":      .init(headline: "Your mental edge is lagging.", tip: "Reduce distractions — quality reps over quantity."),
                "Discipline": .init(headline: "Break the inconsistency cycle.", tip: "Schedule workouts like appointments. No skipping."),
                "Health":     .init(headline: "Your recovery is falling behind.", tip: "Prioritise sleep and manage stress — it directly affects gains."),
                "Energy":     .init(headline: "Energy is flagging.", tip: "Review your nutrition timing and cut excessive cardio frequency."),
            ]
            return tips[stat] ?? .init(headline: "Address your \(stat) gap.", tip: "Targeted work now prevents a bigger gap later.")

        case .c:
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "\(stat) is holding you back.", tip: "Introduce periodisation — heavy weeks followed by deload weeks."),
                "Endurance":  .init(headline: "Cardiovascular deficit detected.", tip: "Add zone-2 cardio (conversational pace) 2× per week."),
                "Focus":      .init(headline: "Cognitive performance is subpar.", tip: "Sleep quality and single-tasking before sessions matter most here."),
                "Discipline": .init(headline: "Rank C demands more consistency.", tip: "Your streak data shows gaps — analyse the pattern and close it."),
                "Health":     .init(headline: "Structural health check needed.", tip: "Incorporate mobility work and soft-tissue maintenance into your routine."),
                "Energy":     .init(headline: "Energy output is inconsistent.", tip: "Track your sleep cycles and pre-workout nutrition more precisely."),
            ]
            return tips[stat] ?? .init(headline: "Rank C requires balanced stats.", tip: "Neglecting \(stat) will cap your progression.")

        case .b:
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "Elite \(stat) requires elite programming.", tip: "Add accessory work targeting your weakest movement patterns."),
                "Endurance":  .init(headline: "Cardiovascular base needs rebuilding.", tip: "Dedicate a full training block to aerobic base development."),
                "Focus":      .init(headline: "Mental performance matters at Rank B.", tip: "Visualisation and pre-session routines sharpen execution."),
                "Discipline": .init(headline: "Rank B athletes don't miss sessions.", tip: "Review your schedule and eliminate obstacles to consistency."),
                "Health":     .init(headline: "Longevity requires structural integrity.", tip: "Add a dedicated mobility and recovery protocol this week."),
                "Energy":     .init(headline: "Energy regulation is an elite skill.", tip: "Audit your sleep, nutrition, and training load — balance all three."),
            ]
            return tips[stat] ?? .init(headline: "\(stat) is the bottleneck.", tip: "Rank B requires no obvious weak points.")

        case .a:
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "Rank A: every kilogram matters.", tip: "Optimise your training max percentages and recovery between heavy days."),
                "Endurance":  .init(headline: "Aerobic capacity is your limiter.", tip: "Structured polarised training — 80% easy, 20% threshold intensity."),
                "Focus":      .init(headline: "At Rank A, the mind is the edge.", tip: "Develop pre-competition focus protocols and review them daily."),
                "Discipline": .init(headline: "Rank A athletes operate on systems.", tip: "Build non-negotiable habits that execute regardless of motivation."),
                "Health":     .init(headline: "Injury prevention is performance.", tip: "Schedule regular soft tissue work and do not skip deload weeks."),
                "Energy":     .init(headline: "Energy management is a discipline.", tip: "Periodise your training load to match your recovery capacity precisely."),
            ]
            return tips[stat] ?? .init(headline: "Fix the \(stat) gap — Rank S demands it.", tip: "Balanced attributes unlock the next tier.")

        case .s:
            let tips: [String: CoachingMessage] = [
                "Strength":   .init(headline: "Rank S — even marginal \(stat) gains matter.", tip: "At this level, specificity and sleep are your final levers."),
                "Endurance":  .init(headline: "Aerobic ceiling: push it.", tip: "Sub-maximal volume combined with high-quality threshold work is your path."),
                "Focus":      .init(headline: "The elite compete in their minds first.", tip: "Every session, every rep — full intentionality. No autopilot."),
                "Discipline": .init(headline: "Rank S is built on relentless consistency.", tip: "You've earned this rank by showing up. Now protect it."),
                "Health":     .init(headline: "Longevity is the Rank S meta-game.", tip: "Protect your joints, tendons, and sleep above all else."),
                "Energy":     .init(headline: "At Rank S, energy management is mastery.", tip: "Micro-periodisation and sleep architecture are your last performance levers."),
            ]
            return tips[stat] ?? .init(headline: "Rank S. Maintain all stats — decline is not an option.", tip: "You are the standard.")
        }
    }

    // MARK: - Tier Rank Color

    private func tierRankColor(_ rank: QuestManager.TierRank) -> Color {
        switch rank {
        case .e: return .gray
        case .d: return .green
        case .c: return .blue
        case .b: return .purple
        case .a: return .orange
        case .s: return .yellow
        }
    }

    // MARK: - Helper Functions
    
    private func timeToMidnightString() -> String {
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        return timeRemaining(until: midnight)
    }
    
    private func timeRemaining(until date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: now, to: date)
        let h = comps.hour ?? 0, m = comps.minute ?? 0, s = comps.second ?? 0
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Level Up Overlay

struct LevelUpOverlay: View {
    let level: Int
    @Binding var particleScale: CGFloat
    let onDismiss: () -> Void

    @State private var glowOpacity: Double = 0
    @State private var textScale: CGFloat = 0.1

    var body: some View {
        ZStack {
            // Dim backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Radial glow
            RadialGradient(
                colors: [.cyan.opacity(0.5), .clear],
                center: .center, startRadius: 10, endRadius: 300
            )
            .scaleEffect(particleScale * 2)
            .opacity(glowOpacity)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated star burst
                ZStack {
                    ForEach(0..<8, id: \.self) { i in
                        Rectangle()
                            .fill(LinearGradient(colors: [.cyan, .clear], startPoint: .center, endPoint: .trailing))
                            .frame(width: 120, height: 2)
                            .rotationEffect(.degrees(Double(i) * 45))
                            .scaleEffect(particleScale)
                    }
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 90, height: 90)
                        .shadow(color: .cyan, radius: 20)
                        .overlay(
                            Text("⭐")
                                .font(.system(size: 40))
                        )
                }

                VStack(spacing: 8) {
                    Text("LEVEL UP!")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .white], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .cyan, radius: 10)

                    Text("Level \(level)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .cyan, radius: 15)

                    Text("All stats +2")
                        .font(.title3)
                        .foregroundColor(.cyan.opacity(0.9))
                }
                .scaleEffect(textScale)

                Button("Continue") { onDismiss() }
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.cyan))
                    .shadow(color: .cyan.opacity(0.5), radius: 8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                textScale = 1.0
                glowOpacity = 1.0
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Quest.self, Profile.self], inMemory: true)
}
