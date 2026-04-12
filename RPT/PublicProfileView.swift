import SwiftUI

// MARK: - PublicProfileView
//
// Displays another player's public profile. Accessed by tapping a
// leaderboard row. Fetches data from player-proxy get_public_profile.
// Respects the privacy toggle — private profiles show only name + avatar.

struct PublicProfileView: View {
    let entry: LeaderboardEntry

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var achievementsService = AchievementsService.shared
    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingChallengeSheet = false
    @State private var showingReportSheet = false
    @State private var reportSubmitted = false

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let error = errorMessage {
                ContentUnavailableView("Could not load profile",
                                       systemImage: "person.slash",
                                       description: Text(error))
            } else if let profile = profile, profile.isPrivate == true {
                privateProfileView(profile)
            } else if let profile = profile {
                publicProfileContent(profile)
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entry.isCurrentUser != true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingReportSheet = true
                        } label: {
                            Label("Report Player", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            ReportPlayerSheet(
                targetCloudKitID: entry.cloudkitUserId ?? entry.playerId ?? "",
                targetPlayerID: entry.playerId,
                targetDisplayName: entry.displayName,
                onSubmitted: { reportSubmitted = true }
            )
        }
        .alert("Report Submitted", isPresented: $reportSubmitted) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you for your report. Our team will review it.")
        }
        .task { await fetchProfile() }
    }

    // MARK: - Private Profile

    private func privateProfileView(_ profile: PublicProfile) -> some View {
        VStack(spacing: 24) {
            avatarHeader(profile)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                Text("This player's profile is private")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

            Spacer()
        }
        .padding()
    }

    // MARK: - Public Profile Content

    private func publicProfileContent(_ profile: PublicProfile) -> some View {
        VStack(spacing: 20) {
            avatarHeader(profile)

            // Stats grid
            statsSection(profile)

            // Class + Goal
            if let playerClass = profile.playerClass, !playerClass.isEmpty,
               let goal = profile.fitnessGoal, !goal.isEmpty {
                classGoalSection(playerClass: playerClass, goal: goal)
            }

            // Guild
            if let guildName = profile.guildName, !guildName.isEmpty {
                guildSection(profile)
            }

            // Achievements showcase
            if !profile.showcaseAchievementKeys.isEmpty {
                achievementShowcase(profile.showcaseAchievementKeys)
            }

            // Activity stats
            activitySection(profile)

            // Action buttons
            if entry.isCurrentUser != true {
                challengeButton
                rivalButton
            }

            Spacer(minLength: 40)
        }
        .padding()
    }

    // MARK: - Components

    private func avatarHeader(_ profile: PublicProfile) -> some View {
        VStack(spacing: 12) {
            AvatarImageView(key: profile.avatarKey ?? "avatar_default", size: 100)
                .overlay(Circle().stroke(Color.cyan, lineWidth: 3))
                .shadow(color: .cyan.opacity(0.3), radius: 10)

            Text(profile.displayName)
                .font(.title2.weight(.bold))

            if let level = profile.level {
                Text("LEVEL \(level)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }
        .padding(.top, 8)
    }

    private func statsSection(_ profile: PublicProfile) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(profile.totalXP ?? 0)", label: "Total XP", icon: "bolt.fill", color: .cyan)
            Divider().frame(height: 40)
            statCell(value: "\(profile.currentStreak ?? 0)", label: "Streak", icon: "flame.fill", color: .orange)
            Divider().frame(height: 40)
            statCell(value: "\(profile.longestStreak ?? 0)", label: "Best", icon: "trophy.fill", color: .yellow)
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func classGoalSection(playerClass: String, goal: String) -> some View {
        HStack(spacing: 12) {
            Label(playerClass.capitalized, systemImage: "shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.cyan.opacity(0.12)))

            Label(goal.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "target")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.green.opacity(0.12)))
        }
    }

    private func guildSection(_ profile: PublicProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundColor(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.guildName ?? "")
                    .font(.subheadline.weight(.semibold))
                if let role = profile.guildRole, !role.isEmpty {
                    Text(role.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.1)))
    }

    private func achievementShowcase(_ keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACHIEVEMENTS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(keys, id: \.self) { key in
                    if let achievement = achievementsService.achievements.first(where: { $0.key == key }) {
                        VStack(spacing: 6) {
                            Image(systemName: achievement.iconSymbol)
                                .font(.system(size: 24))
                                .foregroundColor(.yellow)
                            Text(achievement.title)
                                .font(.system(size: 10, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
                    }
                }
            }
        }
    }

    private func activitySection(_ profile: PublicProfile) -> some View {
        HStack(spacing: 0) {
            activityCell(value: "\(profile.totalWorkoutsLogged ?? 0)", label: "Workouts", icon: "dumbbell.fill")
            Divider().frame(height: 40)
            activityCell(value: "\(profile.totalQuestsCompleted ?? 0)", label: "Quests", icon: "scroll.fill")
            Divider().frame(height: 40)
            activityCell(value: "\(profile.totalDaysActive ?? 0)", label: "Days Active", icon: "calendar")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
    }

    private func activityCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(.secondary)
                Text(value).font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var challengeButton: some View {
        Button {
            showingChallengeSheet = true
        } label: {
            Label("Challenge", systemImage: "bolt.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan.opacity(0.15)))
                .foregroundColor(.cyan)
        }
        .sheet(isPresented: $showingChallengeSheet) {
            if let profile = profile, let ckID = profile.cloudkitUserId {
                SendChallengeSheet(
                    targetCloudKitID: ckID,
                    targetDisplayName: profile.displayName
                )
            }
        }
    }

    private var rivalButton: some View {
        Button {
            LeaderboardService.shared.setRival(entry: entry)
        } label: {
            Label("Set as Rival", systemImage: "flame.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.15)))
                .foregroundColor(.red)
        }
        .padding(.top, 8)
    }

    // MARK: - Network

    private func fetchProfile() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/player-proxy") else { return }

        var body: [String: Any] = [
            "action": "get_public_profile",
            "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
        ]

        // Session 2 bug fix: prefer target_cloudkit_user_id over target_player_id.
        //
        // Early builds let the iOS client generate a local `player_id` on first
        // launch (before the server had authoritative IDs), and leaderboard rows
        // stored that local ID. When player_profiles later got a row inserted
        // via a different code path, the DB generated a fresh player_id. The
        // two tables ended up pointing at the same cloudkit_user_id with
        // different player_ids, and tapping a leaderboard row returned
        // "Player not found" because the proxy looked up by player_id.
        //
        // cloudkit_user_id is the stable universal key. Use it first; fall
        // back to player_id only when we don't have a CloudKit id (e.g.,
        // deep-link handoffs from rpt://addfriend/{CODE}).
        if let cloudkitUserId = entry.cloudkitUserId, !cloudkitUserId.isEmpty {
            body["target_cloudkit_user_id"] = cloudkitUserId
        } else if let playerId = entry.playerId, !playerId.isEmpty {
            body["target_player_id"] = playerId
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Server returned an error"
                return
            }

            let decoded = try JSONDecoder().decode(PublicProfile.self, from: data)
            if decoded.success == false {
                errorMessage = "Player not found"
                return
            }
            profile = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PublicProfile Model

struct PublicProfile: Decodable {
    let success: Bool?
    let isPrivate: Bool?
    let playerId: String?
    let cloudkitUserId: String?
    let displayName: String
    let avatarKey: String?
    let level: Int?
    let totalXP: Int?
    let currentStreak: Int?
    let longestStreak: Int?
    let playerClass: String?
    let fitnessGoal: String?
    let guildId: String?
    let guildName: String?
    let guildRole: String?
    let showcaseAchievementKeys: [String]
    let totalWorkoutsLogged: Int?
    let totalQuestsCompleted: Int?
    let totalDaysActive: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case isPrivate          = "is_private"
        case playerId           = "player_id"
        case cloudkitUserId     = "cloudkit_user_id"
        case displayName        = "display_name"
        case avatarKey          = "avatar_key"
        case level
        case totalXP            = "total_xp"
        case currentStreak      = "current_streak"
        case longestStreak      = "longest_streak"
        case playerClass        = "player_class"
        case fitnessGoal        = "fitness_goal"
        case guildId            = "guild_id"
        case guildName          = "guild_name"
        case guildRole          = "guild_role"
        case showcaseAchievementKeys = "showcase_achievement_keys"
        case totalWorkoutsLogged = "total_workouts_logged"
        case totalQuestsCompleted = "total_quests_completed"
        case totalDaysActive    = "total_days_active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success              = try? c.decodeIfPresent(Bool.self, forKey: .success)
        isPrivate            = try? c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        playerId             = try? c.decodeIfPresent(String.self, forKey: .playerId)
        cloudkitUserId       = try? c.decodeIfPresent(String.self, forKey: .cloudkitUserId)
        displayName          = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? "Unknown"
        avatarKey            = try? c.decodeIfPresent(String.self, forKey: .avatarKey)
        level                = try? c.decodeIfPresent(Int.self, forKey: .level)
        totalXP              = try? c.decodeIfPresent(Int.self, forKey: .totalXP)
        currentStreak        = try? c.decodeIfPresent(Int.self, forKey: .currentStreak)
        longestStreak        = try? c.decodeIfPresent(Int.self, forKey: .longestStreak)
        playerClass          = try? c.decodeIfPresent(String.self, forKey: .playerClass)
        fitnessGoal          = try? c.decodeIfPresent(String.self, forKey: .fitnessGoal)
        guildId              = try? c.decodeIfPresent(String.self, forKey: .guildId)
        guildName            = try? c.decodeIfPresent(String.self, forKey: .guildName)
        guildRole            = try? c.decodeIfPresent(String.self, forKey: .guildRole)
        showcaseAchievementKeys = (try? c.decodeIfPresent([String].self, forKey: .showcaseAchievementKeys)) ?? []
        totalWorkoutsLogged  = try? c.decodeIfPresent(Int.self, forKey: .totalWorkoutsLogged)
        totalQuestsCompleted = try? c.decodeIfPresent(Int.self, forKey: .totalQuestsCompleted)
        totalDaysActive      = try? c.decodeIfPresent(Int.self, forKey: .totalDaysActive)
    }
}

// MARK: - Report Player Sheet

struct ReportPlayerSheet: View {
    let targetCloudKitID: String
    let targetPlayerID: String?
    let targetDisplayName: String
    var onSubmitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var moderation = ModerationService.shared
    @State private var selectedReason: ReportReason?
    @State private var description = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Report \(targetDisplayName)")
                        .font(.headline)
                    Text("Select a reason for your report. False reports may result in action against your account.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Reason") {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Image(systemName: reason.icon)
                                    .frame(width: 24)
                                    .foregroundColor(selectedReason == reason ? .red : .secondary)
                                Text(reason.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                Section("Details (optional)") {
                    TextField("Describe the issue...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Report Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submitReport() }
                    }
                    .disabled(selectedReason == nil || moderation.isSubmitting)
                    .foregroundColor(.red)
                }
            }
        }
    }

    private func submitReport() async {
        guard let reason = selectedReason else { return }
        let result = await ModerationService.shared.reportPlayer(
            reportedCloudKitID: targetCloudKitID,
            reportedPlayerID: targetPlayerID,
            reason: reason,
            description: description.isEmpty ? nil : description
        )
        switch result {
        case .success:
            dismiss()
            onSubmitted()
        case .alreadyReported:
            errorMessage = "You already reported this player today."
        case .error(let msg):
            errorMessage = msg
        }
    }
}
