import SwiftUI

// MARK: - ChallengeView
//
// Shows active, pending, and completed 1v1 challenges.
// Accessible from Settings or a future dedicated tab.

struct ChallengeView: View {
    @ObservedObject private var service = ChallengeService.shared
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    // Session 2: + toolbar button opens the friends picker, which on
    // friend-tap immediately presents the SendChallengeSheet prefilled
    // with that friend's identifiers. Two-state handoff so the picker
    // sheet fully dismisses before the challenge sheet is presented,
    // avoiding a SwiftUI double-sheet race.
    @State private var showingFriendsPicker = false
    @State private var pendingFriendTarget: FriendChallengeTarget? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !service.pendingIncoming.isEmpty {
                        sectionHeader("INCOMING CHALLENGES", color: .red)
                        ForEach(service.pendingIncoming) { c in
                            IncomingChallengeCard(challenge: c)
                        }
                    }

                    if !service.activeChallenges.isEmpty {
                        sectionHeader("ACTIVE CHALLENGES", color: .cyan)
                        ForEach(service.activeChallenges) { c in
                            ActiveChallengeCard(challenge: c)
                        }
                    }

                    if !service.pendingSent.isEmpty {
                        sectionHeader("SENT (WAITING)", color: .secondary)
                        ForEach(service.pendingSent) { c in
                            PendingCard(challenge: c)
                        }
                    }

                    if !service.completedChallenges.isEmpty {
                        sectionHeader("COMPLETED", color: .green)
                        ForEach(service.completedChallenges) { c in
                            CompletedCard(challenge: c)
                        }
                    }

                    if service.challenges.isEmpty && !service.isLoading {
                        ContentUnavailableView(
                            "No Challenges Yet",
                            systemImage: "figure.boxing",
                            description: Text("Tap a player's profile on the leaderboard to send a challenge, or tap + above to pick a friend.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFriendsPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                    .accessibilityLabel("Challenge a friend")
                }
            }
            .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        }
        .task { await service.refresh() }
        .sheet(isPresented: $showingFriendsPicker) {
            FriendsPickerSheet { target in
                showingFriendsPicker = false
                // Defer the challenge sheet so the picker finishes
                // dismissing first — presenting both sheets
                // simultaneously triggers a SwiftUI glitch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    pendingFriendTarget = target
                }
            }
        }
        .sheet(item: $pendingFriendTarget) { target in
            SendChallengeSheet(
                targetCloudKitID: target.cloudKitID,
                targetDisplayName: target.displayName
            )
        }
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Identifiable payload for the deferred SendChallengeSheet presentation.
struct FriendChallengeTarget: Identifiable {
    let cloudKitID: String
    let displayName: String
    var id: String { cloudKitID }
}

// MARK: - Friends Picker Sheet

/// Session 2: Lists the player's friends so they can pick one to challenge
/// directly from ChallengeView. Reuses `LeaderboardService.friendEntries`
/// as the data source — populated by `LeaderboardService.fetchFriends()`
/// on launch and kept in sync with add/remove friend actions.
struct FriendsPickerSheet: View {
    let onPick: (FriendChallengeTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var leaderboard = LeaderboardService.shared
    @State private var isLoading = false

    private var friends: [LeaderboardEntry] {
        // Filter out the current user if they appear in their own friends
        // list for any reason — you can't challenge yourself.
        let myID = LeaderboardService.shared.currentUserID ?? ""
        return leaderboard.friendEntries.filter { $0.cloudkitUserId != myID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && friends.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friends.isEmpty {
                    ContentUnavailableView(
                        "No Friends Yet",
                        systemImage: "person.2.slash",
                        description: Text("Add friends from the Leaderboard tab to challenge them directly.")
                    )
                } else {
                    List(friends) { friend in
                        Button {
                            // cloudkit_user_id is the stable key the
                            // challenge-proxy uses. player_id is prone to
                            // drift (see session 2 player cards bug fix).
                            guard let ckID = friend.cloudkitUserId, !ckID.isEmpty else { return }
                            onPick(FriendChallengeTarget(
                                cloudKitID: ckID,
                                displayName: friend.displayName
                            ))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarImageView(key: friend.avatarKey ?? "avatar_default", size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    HStack(spacing: 6) {
                                        Text("Lv \(friend.level ?? 1)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.cyan)
                                        Text("·")
                                            .foregroundColor(.secondary)
                                        Text("\(friend.totalXP ?? 0) XP")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pick a Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            isLoading = true
            await leaderboard.fetchFriends()
            isLoading = false
        }
    }
}

// MARK: - Active Challenge Card

private struct ActiveChallengeCard: View {
    let challenge: Challenge
    private var myID: String { LeaderboardService.shared.currentUserID ?? "" }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                if let type = challenge.type {
                    Image(systemName: type.icon)
                        .foregroundColor(.cyan)
                }
                Text(challenge.type?.displayName ?? challenge.challengeType)
                    .font(.headline)
                Spacer()
                if let target = challenge.targetValue {
                    Text("Goal: \(target)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
            }

            // VS header
            HStack {
                Text("YOU")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
                Text("VS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                Text(challenge.opponentName(myID))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            // Progress bars
            HStack(spacing: 12) {
                progressBar(value: challenge.myProgress(myID), target: challenge.targetValue, color: .cyan, label: "\(challenge.myProgress(myID))")
                progressBar(value: challenge.opponentProgress(myID), target: challenge.targetValue, color: .red, label: "\(challenge.opponentProgress(myID))")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }

    private func progressBar(value: Int, target: Int?, color: Color, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            if let target = target, target > 0 {
                ProgressView(value: Double(value), total: Double(target))
                    .tint(color)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Incoming Challenge Card

private struct IncomingChallengeCard: View {
    let challenge: Challenge
    @ObservedObject private var service = ChallengeService.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if let type = challenge.type {
                    Image(systemName: type.icon).foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(challenge.challengerDisplayName) challenged you!")
                        .font(.subheadline.weight(.bold))
                    Text(challenge.type?.displayName ?? challenge.challengeType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let days = challenge.durationDays {
                    Text("\(days)d")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await service.acceptChallenge(challenge.id) }
                } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)
                }

                Button {
                    Task { await service.declineChallenge(challenge.id) }
                } label: {
                    Text("Decline")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Pending Sent Card

private struct PendingCard: View {
    let challenge: Challenge

    var body: some View {
        HStack {
            if let type = challenge.type {
                Image(systemName: type.icon).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for \(challenge.challengedDisplayName)")
                    .font(.subheadline)
                Text(challenge.type?.displayName ?? challenge.challengeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}

// MARK: - Completed Card

private struct CompletedCard: View {
    let challenge: Challenge
    private var myID: String { LeaderboardService.shared.currentUserID ?? "" }
    private var didWin: Bool { challenge.winnerCloudkitUserId == myID }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: didWin ? "trophy.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(didWin ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(didWin ? "Victory!" : "Defeated")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(didWin ? .yellow : .secondary)
                Text("vs \(challenge.opponentName(myID)) · \(challenge.type?.displayName ?? challenge.challengeType)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(challenge.myProgress(myID))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(didWin ? .cyan : .secondary)
                Text("vs \(challenge.opponentProgress(myID))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(didWin ? Color.yellow.opacity(0.08) : Color(.systemGray6)))
    }
}

// MARK: - Send Challenge Sheet

struct SendChallengeSheet: View {
    let targetCloudKitID: String
    let targetDisplayName: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = ChallengeService.shared
    @State private var selectedType: ChallengeType = .xpRace
    @State private var targetValue = "500"
    @State private var durationDays = 7
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ChallengeType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Goal") {
                    TextField("Target value (e.g. 500 XP)", text: $targetValue)
                        .keyboardType(.numberPad)
                }

                Section("Duration") {
                    Picker("Days", selection: $durationDays) {
                        Text("3 days").tag(3)
                        Text("5 days").tag(5)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        isSending = true
                        Task {
                            let target = Int(targetValue)
                            let success = await service.sendChallenge(
                                targetCloudKitID: targetCloudKitID,
                                targetDisplayName: targetDisplayName,
                                type: selectedType,
                                targetValue: target,
                                durationDays: durationDays
                            )
                            isSending = false
                            if success { dismiss() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                            } else {
                                Label("Send Challenge", systemImage: "bolt.fill")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSending)
                }
            }
            .navigationTitle("Challenge \(targetDisplayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
