import SwiftUI
import SwiftData
import FirebaseAuth

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: LeaderboardTab = .world
    
    enum LeaderboardTab: String, CaseIterable {
        case world = "World"
        case friends = "Friends"
        
        var icon: String {
            switch self {
            case .world: return "globe"
            case .friends: return "person.2.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                
                // Content
                TabView(selection: $selectedTab) {
                    WorldLeaderboardView()
                        .tag(LeaderboardTab.world)
                    
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
                    Button(action: {
                        Task {
                            await manualSync()
                        }
                    }) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        }
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tabSelectorBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private func tabButton(for tab: LeaderboardTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = tab
            }
        }) {
            tabButtonContent(for: tab)
        }
        .buttonStyle(.plain)
    }
    
    private func tabButtonContent(for tab: LeaderboardTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .semibold))
            
            Text(tab.rawValue)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(selectedTab == tab ? .white : .secondary)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(tabButtonBackground(for: tab))
    }
    
    private func tabButtonBackground(for tab: LeaderboardTab) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(selectedTab == tab ? 
                  AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)) :
                  AnyShapeStyle(Color.clear)
            )
    }
    
    private var tabSelectorBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? .gray.opacity(0.3) : .gray.opacity(0.2), lineWidth: 1)
            )
    }

    private func manualSync() async {
        guard let profile = DataManager.shared.currentProfile else { return }
        do {
            try await FirebaseManager.shared.syncProfile(profile)
            print("✅ Manual sync completed successfully")
        } catch {
            print("❌ Manual sync failed: \(error)")
        }
    }
}

// MARK: - World Leaderboard
struct WorldLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataManager = DataManager.shared
    @State private var leaderboardPlayers: [LeaderboardPlayer] = []
    @State private var isLoading = false

    var currentPlayer: LeaderboardPlayer? {
        guard let profile = dataManager.currentProfile else { return nil }
        // Find current player's rank in the leaderboard
        let rank = leaderboardPlayers.firstIndex { $0.id == FirebaseManager.shared.currentUser?.uid } ?? 0
        return LeaderboardPlayer(
            id: "you",
            name: profile.name,
            level: profile.level,
            xp: profile.xp,
            streak: profile.currentStreak,
            rank: rank + 1
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                contentView
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task {
            await fetchLeaderboard()
        }
        .refreshable {
            await fetchLeaderboard()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading Leaderboard...")
                .foregroundColor(.cyan)
                .padding()
        } else if leaderboardPlayers.isEmpty {
            emptyStateView
        } else {
            leaderboardContent
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan.opacity(0.5))
            Text("No Players Yet")
                .font(.headline)
            Text("Be the first to sync your progress!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var leaderboardContent: some View {
        if let player = currentPlayer {
            // Your rank card
            VStack(spacing: 16) {
                Text("YOUR RANK")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))

                PodiumCard(player: player, position: player.rank)
                    .scaleEffect(1.05)
            }
            .padding(.vertical, 20)
        }

        // Top players section
        Text("TOP PLAYERS")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.cyan.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

        ForEach(leaderboardPlayers) { player in
            LeaderboardRow(
                player: player,
                isCurrentUser: player.id == FirebaseManager.shared.currentUser?.uid
            )
        }
    }

    private func fetchLeaderboard() async {
        isLoading = true
        do {
            let entries = try await FirebaseManager.shared.fetchLeaderboard(limit: 50)
            leaderboardPlayers = entries.enumerated().map { index, entry in
                LeaderboardPlayer(
                    id: entry.id,
                    name: entry.name,
                    level: entry.level,
                    xp: entry.xp,
                    streak: entry.currentStreak,
                    rank: index + 1
                )
            }
        } catch {
            print("Failed to fetch leaderboard: \(error)")
        }
        isLoading = false
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.8))
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Friends Leaderboard
struct FriendsLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataManager = DataManager.shared
    
    var currentPlayer: LeaderboardPlayer? {
        guard let profile = dataManager.currentProfile else { return nil }
        return LeaderboardPlayer(
            id: "you",
            name: profile.name,
            level: profile.level,
            xp: profile.xp,
            streak: profile.currentStreak,
            rank: 1
        )
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // No friends state (since there are no other users in Firebase)
                VStack(spacing: 24) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.cyan.opacity(0.5))
                    
                    VStack(spacing: 8) {
                        Text("No Friends Yet")
                            .font(.title2.bold())
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("Friends feature coming soon! For now, focus on your personal fitness journey.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Show current user's progress
                    if let player = currentPlayer {
                        VStack(spacing: 12) {
                            Text("YOUR PROGRESS")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.8))
                            
                            LeaderboardRow(
                                player: player,
                                isCurrentUser: true
                            )
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.vertical, 60)
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
    }
}

// MARK: - Supporting Views
struct LeaderboardPlayer: Identifiable {
    let id: String
    let name: String
    let level: Int
    let xp: Int
    let streak: Int
    let rank: Int
}

struct PodiumCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: LeaderboardPlayer
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
            Image(systemName: positionIcon)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(positionColor)
            
            Text(player.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
            
            VStack(spacing: 4) {
                Text("LVL \(player.level)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(positionColor)
                
                Text("\(player.xp) XP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text("\(player.streak)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(positionColor.opacity(0.5), lineWidth: 2)
                )
        )
        .shadow(color: positionColor.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: LeaderboardPlayer
    let isCurrentUser: Bool
    let showFriendBadge: Bool
    
    init(player: LeaderboardPlayer, isCurrentUser: Bool = false, showFriendBadge: Bool = false) {
        self.player = player
        self.isCurrentUser = isCurrentUser
        self.showFriendBadge = showFriendBadge
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("#\(player.rank)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(isCurrentUser ? .cyan : .secondary)
                .frame(width: 40, alignment: .leading)
            
            // Player info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(player.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCurrentUser ? .cyan : (colorScheme == .dark ? .white : .black))
                    
                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.cyan)
                            )
                    }
                    
                    if showFriendBadge && !isCurrentUser {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 12) {
                    Text("LVL \(player.level)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                    
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(player.streak)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // XP
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.xp)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isCurrentUser ? .cyan : (colorScheme == .dark ? .white : .black))
                
                Text("XP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentUser ? 
                      (colorScheme == .dark ? .cyan.opacity(0.1) : .cyan.opacity(0.05)) :
                      (colorScheme == .dark ? .black.opacity(0.2) : .white.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCurrentUser ? .cyan.opacity(0.5) : .gray.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: isCurrentUser ? .cyan.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
    }
}

#Preview {
    LeaderboardView()
}
