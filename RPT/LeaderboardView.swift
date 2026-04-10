import SwiftUI

// MARK: - LeaderboardView
//
// Displays the Supabase-backed leaderboard with three tabs:
//   Global  — all-time XP rankings (paginated, top 50)
//   Weekly  — XP earned this week, resets each Monday
//   Friends — players you follow via ST-XXXXX codes
//
// The current player's row is highlighted; if they fall outside the top 50 on
// Global/Weekly their row is pinned to the bottom of the list.

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leaderboard = LeaderboardService.shared
    @State private var selectedTab: LeaderboardTab = .global

    enum LeaderboardTab: String, CaseIterable {
        case global  = "Global"
        case weekly  = "Weekly"
        case friends = "Friends"

        var icon: String {
            switch self {
            case .global:  return "globe"
            case .weekly:  return "calendar.badge.clock"
            case .friends: return "person.2.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector

                TabView(selection: $selectedTab) {
                    GlobalLeaderboardView()
                        .tag(LeaderboardTab.global)
                    WeeklyLeaderboardView()
                        .tag(LeaderboardTab.weekly)
                    FriendsLeaderboardView()
                        .tag(LeaderboardTab.friends)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: selectedTab)
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await leaderboard.refresh() }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        }
        .task { await leaderboard.refresh() }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 14, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedTab == tab ?
                                  AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)) :
                                  AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? .gray.opacity(0.3) : .gray.opacity(0.2), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Global Leaderboard

private struct GlobalLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leaderboard = LeaderboardService.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let msg = leaderboard.lastError {
                    errorBanner(msg)
                }
                contentView
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task { await leaderboard.fetchGlobal(page: 1) }
    }

    @ViewBuilder
    private var contentView: some View {
        if leaderboard.isLoading {
            ProgressView("Loading Leaderboard...")
                .foregroundColor(.cyan)
                .padding()
        } else if leaderboard.globalEntries.isEmpty {
            emptyState
        } else {
            leaderboardList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan.opacity(0.5))
            Text("No Players Yet")
                .font(.headline)
            Text("Tap the sync button to post your score and be first!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var leaderboardList: some View {
        let entries      = leaderboard.globalEntries
        let currentEntry = entries.first { $0.isCurrentUser == true }
        let inTopList    = currentEntry != nil

        return Group {
            ForEach(entries) { entry in
                LeaderboardRow(entry: entry)
            }

            // Pin the current player below the list if they're not in the top 50
            if let rank = leaderboard.playerGlobalRank, !inTopList {
                Divider().padding(.vertical, 4)
                // Build a placeholder entry for the current player
                let placeholder = currentPlayerPlaceholder(rank: rank)
                LeaderboardRow(entry: placeholder)
            }
        }
    }

    private func currentPlayerPlaceholder(rank: Int) -> LeaderboardEntry {
        let dm = DataManager.shared
        return LeaderboardEntry(
            playerId:       PlayerProfileService.shared.playerId,
            displayName:    dm.currentProfile?.name ?? "You",
            level:          dm.currentProfile?.level ?? 1,
            totalXP:        dm.currentProfile?.xp ?? 0,
            weeklyXP:       0,
            weeklyWorkouts: nil,
            rank:           rank,
            currentStreak:  dm.currentProfile?.currentStreak ?? 0,
            avatarKey:      AvatarService.shared.current?.key,
            isCurrentUser:  true
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.caption).foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }
}

// MARK: - Weekly Leaderboard

private struct WeeklyLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leaderboard = LeaderboardService.shared

    /// Seconds until next Monday 00:00 UTC.
    private var secondsUntilReset: Int {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 2=Mon, ..., 7=Sat
        let daysUntilMonday = weekday == 2 ? 7 : (9 - weekday) % 7
        guard let nextMonday = cal.date(byAdding: .day, value: daysUntilMonday, to: cal.startOfDay(for: now)) else { return 0 }
        return max(0, Int(nextMonday.timeIntervalSince(now)))
    }

    private var resetCountdown: String {
        let s = secondsUntilReset
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Reset countdown banner
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.cyan)
                    Text("Resets in \(resetCountdown)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("Weekly XP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.08)))

                if leaderboard.weeklyEntries.isEmpty && !leaderboard.isLoading {
                    emptyState
                } else {
                    ForEach(leaderboard.weeklyEntries) { entry in
                        LeaderboardRow(entry: entry, showWeeklyXP: true)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task { await leaderboard.fetchWeekly(page: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.cyan.opacity(0.5))
            Text("No Weekly Data Yet")
                .font(.headline)
            Text("Complete quests and workouts to appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Friends Leaderboard View

private struct FriendsLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leaderboard = LeaderboardService.shared
    @State private var enteredCode = ""
    @State private var showAddField = false
    @FocusState private var isFriendCodeFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                addFriendSection
                    .padding(.top, 8)

                if let msg = leaderboard.friendsError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
                }

                if leaderboard.isFriendsLoading {
                    ProgressView("Loading friends...")
                        .foregroundColor(.cyan)
                        .padding()
                } else if leaderboard.friendEntries.isEmpty {
                    emptyState
                } else {
                    friendsList
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFriendCodeFocused = false }
            }
        }
        .onTapGesture { isFriendCodeFocused = false }
        .task { await leaderboard.fetchFriends() }
        .onReceive(NotificationCenter.default.publisher(for: .rptAddFriendDeepLink)) { notification in
            guard let code = notification.userInfo?["code"] as? String, !code.isEmpty else { return }
            Task { await leaderboard.addFriend(playerID: code) }
        }
    }

    private var addFriendSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("FRIENDS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                Spacer()
                Button {
                    withAnimation { showAddField.toggle() }
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cyan)
                }
            }

            if showAddField {
                HStack(spacing: 10) {
                    TextField("Enter ST-XXXXX code", text: $enteredCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isFriendCodeFocused)
                        .submitLabel(.done)
                        .onSubmit { isFriendCodeFocused = false }
                        .font(.system(size: 15, design: .monospaced))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.05))
                        )

                    Button("Add") {
                        let code = enteredCode.uppercased().trimmingCharacters(in: .whitespaces)
                        guard !code.isEmpty else { return }
                        Task {
                            await leaderboard.addFriend(playerID: code)
                            enteredCode = ""
                            withAnimation { showAddField = false }
                        }
                    }
                    .disabled(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(.cyan.opacity(0.4))
            Text("No Friends Added Yet")
                .font(.headline)
            Text("Tap \"Add Friend\" and enter a friend's ST-XXXXX code to follow their progress.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private var friendsList: some View {
        ForEach(leaderboard.friendEntries) { entry in
            LeaderboardRow(entry: entry)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await leaderboard.removeFriend(playerID: entry.playerId ?? "") }
                    } label: {
                        Label("Remove", systemImage: "person.badge.minus")
                    }
                }
        }
    }
}

// MARK: - Your Rank / Player ID Card (shown in the You tab)
//
// This view is no longer a separate tab — the player's row is highlighted inline
// in Global/Weekly. However we keep a "Your Player ID" card in the Friends tab
// area accessible via a dedicated view you can push to.

struct YourPlayerIDView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leaderboard = LeaderboardService.shared
    @State private var showCopied = false

    private var playerID: String {
        PlayerProfileService.shared.playerId
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if !playerID.isEmpty {
                    playerIDCard
                        .padding(.top, 20)
                }

                if let entry = leaderboard.globalEntries.first(where: { $0.isCurrentUser == true }) {
                    VStack(spacing: 8) {
                        Text("YOUR RANK")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                        PodiumCard(entry: entry, position: entry.rank ?? 0)
                            .scaleEffect(1.05)
                    }
                } else if let rank = leaderboard.playerGlobalRank {
                    VStack(spacing: 8) {
                        Text("YOUR RANK")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                        Text(rank == 0 ? "—" : "#\(rank)")
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("Your Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var playerIDCard: some View {
        VStack(spacing: 10) {
            Text("YOUR PLAYER ID")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.8))

            Text(playerID)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .tracking(2)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = playerID
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(showCopied ? "Copied!" : "Copy Code",
                          systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(showCopied ? .green : .cyan)
                }

                if let shareURL = URL(string: "rpt://addfriend/\(playerID)") {
                    ShareLink(
                        item: shareURL,
                        subject: Text("Add me on System Trainer!"),
                        message: Text("Use my player ID \(playerID) to add me on System Trainer. Tap: \(shareURL.absoluteString)")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                }
            }

            Text("Share this code with friends so they can add you")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
        )
    }
}

// MARK: - Supporting Views

struct PodiumCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: LeaderboardEntry
    let position: Int

    private var positionColor: Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .cyan
        }
    }

    private var positionIcon: String {
        switch position {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal"
        default: return "trophy.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AvatarImageView(key: entry.avatarKey ?? "avatar_default", size: 50)
                    .overlay(Circle().stroke(positionColor.opacity(0.8), lineWidth: 2))

                Image(systemName: positionIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(positionColor)
                    .padding(4)
                    .background(Circle().fill(colorScheme == .dark ? Color.black : Color.white))
                    .offset(x: 4, y: -4)
            }

            Text(entry.displayName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            VStack(spacing: 4) {
                Text("LVL \(entry.level ?? 1)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(positionColor)

                Text("\(entry.totalXP ?? 0) XP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    Image(systemName: "flame.fill").font(.system(size: 8)).foregroundColor(.orange)
                    Text("\(entry.currentStreak ?? 0)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(positionColor.opacity(0.5), lineWidth: 2))
        )
        .shadow(color: positionColor.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dataManager = DataManager.shared
    @State private var showRivalConfirmation = false
    let entry: LeaderboardEntry
    var showWeeklyXP: Bool = false

    private var isRival: Bool {
        guard let id = entry.playerId, !id.isEmpty,
              let profile = dataManager.currentProfile else { return false }
        return profile.rivalCloudKitUserID == id
    }

    private var canBeRival: Bool {
        // Don't allow setting yourself as a rival
        entry.isCurrentUser != true && (entry.playerId?.isEmpty == false)
    }

    var body: some View {
        rowContent
            .contextMenu {
                if canBeRival {
                    if isRival {
                        Button(role: .destructive) {
                            LeaderboardService.shared.clearRival()
                        } label: {
                            Label("Clear Rival", systemImage: "flame.fill")
                        }
                    } else {
                        Button {
                            LeaderboardService.shared.setRival(entry: entry)
                            showRivalConfirmation = true
                        } label: {
                            Label("Set as Rival", systemImage: "flame.fill")
                        }
                    }
                }
            }
            .alert("Rival Set", isPresented: $showRivalConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(entry.displayName) is now your rival. Surpass them!")
            }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text((entry.rank ?? 0) == 0 ? "—" : "#\(entry.rank ?? 0)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(entry.isCurrentUser == true ? .cyan : .secondary)
                .frame(width: 32, alignment: .leading)

            AvatarImageView(key: entry.avatarKey ?? "avatar_default", size: 36)
                .overlay(Circle().stroke(entry.isCurrentUser == true ? Color.cyan : Color.gray.opacity(0.3), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(entry.isCurrentUser == true ? .cyan : (colorScheme == .dark ? .white : .black))

                    if entry.isCurrentUser == true {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.cyan))
                    }

                    if isRival {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").font(.system(size: 8))
                            Text("RIVAL")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                    }
                }

                HStack(spacing: 12) {
                    Text("LVL \(entry.level ?? 1)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill").font(.system(size: 10)).foregroundColor(.orange)
                        Text("\(entry.currentStreak ?? 0)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(showWeeklyXP ? (entry.weeklyXP ?? 0) : (entry.totalXP ?? 0))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(entry.isCurrentUser == true ? .cyan : (colorScheme == .dark ? .white : .black))
                Text(showWeeklyXP ? "WK XP" : "XP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(entry.isCurrentUser == true ?
                      (colorScheme == .dark ? .cyan.opacity(0.1) : .cyan.opacity(0.05)) :
                      (colorScheme == .dark ? .black.opacity(0.2) : .white.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isRival ? .red.opacity(0.7) : (entry.isCurrentUser == true ? .cyan.opacity(0.5) : .gray.opacity(0.2)),
                            lineWidth: isRival ? 1.5 : 1))
        )
        .shadow(color: isRival ? .red.opacity(0.25) : (entry.isCurrentUser == true ? .cyan.opacity(0.2) : .clear), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    LeaderboardView()
}
