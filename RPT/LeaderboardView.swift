import SwiftUI
import CloudKit
import Observation

// MARK: - CloudKit Leaderboard Manager

@Observable
@MainActor
final class CloudKitLeaderboardManager {
    static let shared = CloudKitLeaderboardManager()

    var players: [LeaderboardPlayer] = []
    var friends: [LeaderboardPlayer] = []
    var isLoading = false
    var isFriendsLoading = false
    var errorMessage: String?
    var friendsErrorMessage: String?

    private let recordType = "LeaderboardEntry"
    private let publicDB = CKContainer.default().publicCloudDatabase

    /// Saved friend codes the user has added (stored in UserDefaults).
    var savedFriendCodes: [String] {
        get { UserDefaults.standard.stringArray(forKey: "savedFriendCodes") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "savedFriendCodes") }
    }

    /// The user's iCloud-account-bound CloudKit record ID.
    /// Cached after the first successful fetch. Persists across app reinstalls and
    /// device transfers because it is tied to the user's iCloud account, not the device.
    private var _cachedCloudKitUserID: String?

    /// Returns the cached CloudKit user ID, or nil if not yet fetched.
    var currentUserID: String? { _cachedCloudKitUserID }

    /// Fetches (and caches) the anonymous iCloud user record ID.
    /// This is a stable, account-bound identifier that survives app deletion and device changes.
    private func resolveUserID() async throws -> String {
        if let cached = _cachedCloudKitUserID { return cached }
        // Check UserDefaults cache first to avoid a network round-trip on every launch.
        if let persisted = UserDefaults.standard.string(forKey: "cloudKitUserRecordID") {
            _cachedCloudKitUserID = persisted
            return persisted
        }
        let recordID = try await CKContainer.default().userRecordID()
        let idString = recordID.recordName
        _cachedCloudKitUserID = idString
        UserDefaults.standard.set(idString, forKey: "cloudKitUserRecordID")
        return idString
    }

    // MARK: - Friend Code Generation

    /// Derives a stable 6-character alphanumeric friend code from a CloudKit user ID string.
    /// Uses a simple hash so the same ID always produces the same code.
    static func friendCode(from cloudKitUserID: String) -> String {
        let charset = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // 32 chars, no ambiguous I/O/0/1
        var hash: UInt64 = 14695981039346656037 // FNV-1a offset basis
        for byte in cloudKitUserID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        var code = ""
        var h = hash
        for _ in 0..<6 {
            code.append(charset[Int(h % 32)])
            h >>= 5
        }
        return code
    }

    /// Ensures the profile has a friend code set. Generates one from the CloudKit ID if missing.
    func ensureFriendCode(for profile: Profile) async {
        guard profile.friendCode.isEmpty else { return }
        if let userID = try? await resolveUserID() {
            profile.friendCode = Self.friendCode(from: userID)
        }
    }

    // MARK: - Push local player to CloudKit

    func pushScore(name: String, level: Int, xp: Int, streak: Int, friendCode: String) async {
        do {
            let userID = try await resolveUserID()
            let record = try await fetchOwnRecord(userID: userID) ?? CKRecord(recordType: recordType)
            record["playerName"] = name as CKRecordValue
            record["level"] = level as CKRecordValue
            record["xp"] = xp as CKRecordValue
            record["streak"] = streak as CKRecordValue
            record["cloudKitUserID"] = userID as CKRecordValue
            record["friendCode"] = friendCode as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await publicDB.save(record)
            errorMessage = nil
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            errorMessage = "Sign in to iCloud in Settings to post your score."
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch global leaderboard

    func fetchLeaderboard() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Resolve user ID in parallel with the leaderboard fetch so we can
        // highlight the current user's row without a second round-trip.
        async let userIDResult: String? = try? resolveUserID()

        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "xp", ascending: false)]
            let keys = ["playerName", "level", "xp", "streak", "cloudKitUserID", "friendCode"]
            let records = try await performQuery(query, desiredKeys: keys, limit: 100)
            let resolvedUserID = await userIDResult

            var fetched: [LeaderboardPlayer] = []
            for record in records {
                guard
                    let name = record["playerName"] as? String,
                    let level = record["level"] as? Int,
                    let xp = record["xp"] as? Int,
                    let streak = record["streak"] as? Int,
                    let ckUserID = record["cloudKitUserID"] as? String
                else { continue }
                let code = record["friendCode"] as? String ?? ""
                fetched.append(LeaderboardPlayer(
                    id: record.recordID.recordName,
                    cloudKitUserID: ckUserID,
                    friendCode: code,
                    name: name,
                    level: level,
                    xp: xp,
                    streak: streak,
                    rank: 0,
                    isCurrentUser: ckUserID == resolvedUserID
                ))
            }
            players = fetched.enumerated().map { idx, p in
                LeaderboardPlayer(id: p.id, cloudKitUserID: p.cloudKitUserID, friendCode: p.friendCode,
                                  name: p.name, level: p.level, xp: p.xp, streak: p.streak,
                                  rank: idx + 1, isCurrentUser: p.isCurrentUser)
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            players = []
        } catch {
            errorMessage = "Could not load leaderboard: \(error.localizedDescription)"
        }
    }

    // MARK: - Friends

    func addFriend(code: String) async {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !savedFriendCodes.contains(normalized) else { return }
        savedFriendCodes.append(normalized)
        await fetchFriends()
    }

    func removeFriend(code: String) {
        savedFriendCodes.removeAll { $0 == code }
        friends.removeAll { $0.friendCode == code }
    }

    func fetchFriends() async {
        let codes = savedFriendCodes
        guard !codes.isEmpty else { friends = []; return }
        isFriendsLoading = true
        friendsErrorMessage = nil
        defer { isFriendsLoading = false }

        do {
            let predicate = NSPredicate(format: "friendCode IN %@", codes)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "xp", ascending: false)]
            let keys = ["playerName", "level", "xp", "streak", "cloudKitUserID", "friendCode"]
            let records = try await performQuery(query, desiredKeys: keys, limit: 200)
            let myID = try? await resolveUserID()

            let fetched: [LeaderboardPlayer] = records.compactMap { record -> LeaderboardPlayer? in
                guard
                    let name = record["playerName"] as? String,
                    let level = record["level"] as? Int,
                    let xp = record["xp"] as? Int,
                    let streak = record["streak"] as? Int,
                    let ckUserID = record["cloudKitUserID"] as? String
                else { return nil }
                let code = record["friendCode"] as? String ?? ""
                return LeaderboardPlayer(
                    id: record.recordID.recordName,
                    cloudKitUserID: ckUserID,
                    friendCode: code,
                    name: name,
                    level: level,
                    xp: xp,
                    streak: streak,
                    rank: 0,
                    isCurrentUser: ckUserID == myID
                )
            }
            let sorted = fetched.sorted { $0.xp > $1.xp }
            friends = sorted.enumerated().map { idx, p in
                LeaderboardPlayer(id: p.id, cloudKitUserID: p.cloudKitUserID, friendCode: p.friendCode,
                                  name: p.name, level: p.level, xp: p.xp, streak: p.streak,
                                  rank: idx + 1, isCurrentUser: p.isCurrentUser)
            }
        } catch {
            friendsErrorMessage = "Could not load friends: \(error.localizedDescription)"
        }
    }

    // MARK: - Private helpers

    private func fetchOwnRecord(userID: String) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "cloudKitUserID == %@", userID)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        return try await performQuery(query, desiredKeys: nil, limit: 1).first
    }

    /// Wraps `CKQueryOperation` in an async/throws interface.
    private func performQuery(_ query: CKQuery, desiredKeys: [CKRecord.FieldKey]?, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [CKRecord] = []
            var finished = false

            let op = CKQueryOperation(query: query)
            op.desiredKeys = desiredKeys
            op.resultsLimit = limit

            op.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    collected.append(record)
                }
            }

            op.queryResultBlock = { result in
                guard !finished else { return }
                finished = true
                switch result {
                case .success:
                    continuation.resume(returning: collected)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            publicDB.add(op)
        }
    }
}

// MARK: - Leaderboard Data Model

struct LeaderboardPlayer: Identifiable {
    let id: String
    let cloudKitUserID: String
    let friendCode: String
    let name: String
    let level: Int
    let xp: Int
    let streak: Int
    let rank: Int
    /// True when this player record belongs to the signed-in iCloud account.
    let isCurrentUser: Bool
}

// MARK: - Root View

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var leaderboard: CloudKitLeaderboardManager { CloudKitLeaderboardManager.shared }
    private var dataManager: DataManager { DataManager.shared }
    @State private var selectedTab: LeaderboardTab = .world

    enum LeaderboardTab: String, CaseIterable {
        case world = "World"
        case friends = "Friends"
        case you = "You"

        var icon: String {
            switch self {
            case .world: return "globe"
            case .friends: return "person.2.fill"
            case .you: return "person.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector

                TabView(selection: $selectedTab) {
                    WorldLeaderboardView()
                        .tag(LeaderboardTab.world)
                    FriendsLeaderboardView()
                        .tag(LeaderboardTab.friends)
                    YourRankView()
                        .tag(LeaderboardTab.you)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: selectedTab)
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let profile = dataManager.currentProfile {
                                await leaderboard.ensureFriendCode(for: profile)
                                await leaderboard.pushScore(
                                    name: profile.name,
                                    level: profile.level,
                                    xp: profile.xp,
                                    streak: profile.currentStreak,
                                    friendCode: profile.friendCode
                                )
                            }
                            await leaderboard.fetchLeaderboard()
                        }
                    } label: {
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
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(colorScheme == .dark ? .gray.opacity(0.3) : .gray.opacity(0.2), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - World Leaderboard

struct WorldLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var leaderboard: CloudKitLeaderboardManager { CloudKitLeaderboardManager.shared }
    private var dataManager: DataManager { DataManager.shared }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let msg = leaderboard.errorMessage {
                    errorBanner(msg)
                }
                contentView
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task { await leaderboard.fetchLeaderboard() }
        .refreshable { await leaderboard.fetchLeaderboard() }
    }

    @ViewBuilder
    private var contentView: some View {
        if leaderboard.isLoading {
            ProgressView("Loading Leaderboard...")
                .foregroundColor(.cyan)
                .padding()
        } else if leaderboard.players.isEmpty {
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
        ForEach(leaderboard.players) { player in
            LeaderboardRow(player: player, isCurrentUser: player.isCurrentUser)
        }
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

// MARK: - Your Rank View

struct YourRankView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var leaderboard: CloudKitLeaderboardManager { CloudKitLeaderboardManager.shared }
    private var dataManager: DataManager { DataManager.shared }
    @State private var showCopied = false

    private var ownEntry: LeaderboardPlayer? {
        leaderboard.players.first { $0.isCurrentUser }
    }

    private var friendCode: String {
        dataManager.currentProfile?.friendCode ?? ""
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Friend code card — always shown
                if !friendCode.isEmpty {
                    friendCodeCard
                        .padding(.top, 20)
                }

                if let player = ownEntry {
                    VStack(spacing: 8) {
                        Text("YOUR RANK")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))

                        PodiumCard(player: player, position: player.rank)
                            .scaleEffect(1.05)
                    }
                } else if let profile = dataManager.currentProfile {
                    // Not yet synced
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 48))
                            .foregroundColor(.cyan.opacity(0.5))
                        Text("You're not on the board yet")
                            .font(.headline)
                        Text("Tap the sync button at the top to post your score.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Local preview shown before the first sync.
                        let preview = LeaderboardPlayer(
                            id: "preview",
                            cloudKitUserID: leaderboard.currentUserID ?? "",
                            friendCode: profile.friendCode,
                            name: profile.name,
                            level: profile.level,
                            xp: profile.xp,
                            streak: profile.currentStreak,
                            rank: 0,
                            isCurrentUser: true
                        )
                        LeaderboardRow(player: preview, isCurrentUser: true)
                            .opacity(0.6)
                    }
                    .padding(.vertical, 40)
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task {
            // Generate friend code if needed when this tab appears
            if let profile = dataManager.currentProfile {
                await leaderboard.ensureFriendCode(for: profile)
            }
        }
    }

    private var friendCodeCard: some View {
        VStack(spacing: 10) {
            Text("YOUR FRIEND CODE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.8))

            Text(friendCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .tracking(6)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = friendCode
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(showCopied ? "Copied!" : "Copy Code", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(showCopied ? .green : .cyan)
                }

                if let shareURL = URL(string: "rpt://addfriend/\(friendCode)") {
                    ShareLink(
                        item: shareURL,
                        subject: Text("Add me on RPT!"),
                        message: Text("Use my friend code \(friendCode) to add me on RPT — the fitness RPG app! Tap the link or enter the code manually: \(shareURL.absoluteString)")
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

// MARK: - Friends Leaderboard View

struct FriendsLeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var leaderboard: CloudKitLeaderboardManager { CloudKitLeaderboardManager.shared }
    @State private var enteredCode = ""
    @State private var showAddField = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Add friend section
                addFriendSection
                    .padding(.top, 8)

                if let msg = leaderboard.friendsErrorMessage {
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
                } else if leaderboard.friends.isEmpty && leaderboard.savedFriendCodes.isEmpty {
                    emptyState
                } else {
                    friendsList
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        .task { await leaderboard.fetchFriends() }
        .refreshable { await leaderboard.fetchFriends() }
        .onReceive(NotificationCenter.default.publisher(for: .rptAddFriendDeepLink)) { notification in
            guard let code = notification.userInfo?["code"] as? String, code.count == 6 else { return }
            Task {
                await leaderboard.addFriend(code: code)
            }
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
                    TextField("Enter friend code (e.g. A3F9K2)", text: $enteredCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, design: .monospaced))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.05))
                        )

                    Button("Add") {
                        let code = enteredCode.uppercased().trimmingCharacters(in: .whitespaces)
                        guard code.count == 6 else { return }
                        Task {
                            await leaderboard.addFriend(code: code)
                            enteredCode = ""
                            withAnimation { showAddField = false }
                        }
                    }
                    .disabled(enteredCode.trimmingCharacters(in: .whitespaces).count != 6)
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
            Text("Tap \"Add Friend\" and enter a friend's 6-character code to follow their progress.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private var friendsList: some View {
        ForEach(leaderboard.friends) { player in
            LeaderboardRow(player: player, isCurrentUser: player.isCurrentUser)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        leaderboard.removeFriend(code: player.friendCode)
                    } label: {
                        Label("Remove", systemImage: "person.badge.minus")
                    }
                }
        }
    }
}

// MARK: - Supporting Views

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
                    Image(systemName: "flame.fill").font(.system(size: 8)).foregroundColor(.orange)
                    Text("\(player.streak)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.orange)
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
    let player: LeaderboardPlayer
    let isCurrentUser: Bool

    init(player: LeaderboardPlayer, isCurrentUser: Bool = false) {
        self.player = player
        self.isCurrentUser = isCurrentUser
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("#\(player.rank)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(isCurrentUser ? .cyan : .secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(player.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCurrentUser ? .cyan : (colorScheme == .dark ? .white : .black))

                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.cyan))
                    }
                }

                HStack(spacing: 12) {
                    Text("LVL \(player.level)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill").font(.system(size: 10)).foregroundColor(.orange)
                        Text("\(player.streak)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.orange)
                    }
                }
            }

            Spacer()

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
                      (colorScheme == .dark ? .black.opacity(0.2) : .white.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrentUser ? .cyan.opacity(0.5) : .gray.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: isCurrentUser ? .cyan.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
    }
}

#Preview {
    LeaderboardView()
}
