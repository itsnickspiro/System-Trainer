import SwiftUI
import SwiftData

struct GuildView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = GuildService.shared

    @State private var showingCreateSheet = false
    @State private var showingFocusEditor = false
    @State private var showingLeaveConfirm = false
    @State private var focusDraft: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if service.currentGuild != nil {
                    inGuildContent
                } else {
                    notInGuildContent
                }
            }
            .navigationTitle("Guild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGuildSheet()
            }
            .sheet(isPresented: $showingFocusEditor) {
                NavigationStack {
                    Form {
                        Section("Weekly Focus") {
                            TextField("This week we're hitting…", text: $focusDraft, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }
                    .navigationTitle("Set Focus")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingFocusEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    _ = await service.setWeeklyFocus(focusDraft)
                                    showingFocusEditor = false
                                }
                            }
                        }
                    }
                }
            }
            .alert("Leave Guild", isPresented: $showingLeaveConfirm) {
                Button("Leave", role: .destructive) {
                    Task { _ = await service.leaveGuild() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if service.currentRole == "owner" {
                    Text("You're the owner. Leaving will transfer ownership to the longest-tenured member. The guild will continue without you.")
                } else {
                    Text("You can re-join later if there's still room.")
                }
            }
            .task {
                await service.refresh()
                if service.currentGuild == nil {
                    await service.loadPublicGuilds()
                }
            }
        }
    }

    // MARK: - Mode A: Browse public guilds

    private var notInGuildContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero header
            VStack(alignment: .leading, spacing: 8) {
                Text("【JOIN A GUILD】")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                    .tracking(2)
                Text("Combine forces with other adventurers. Take down weekly boss raids together. Share the loot.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            // Create
            Button {
                showingCreateSheet = true
            } label: {
                Label("Create New Guild", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)

            // Public list
            VStack(alignment: .leading, spacing: 8) {
                Text("PUBLIC GUILDS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(2)

                if service.publicGuilds.isEmpty {
                    Text(service.isLoading ? "Loading…" : "No public guilds yet. Be the first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(service.publicGuilds) { guild in
                        publicGuildRow(guild)
                    }
                }
            }
        }
        .padding()
    }

    private func publicGuildRow(_ guild: GuildSummary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.cyan.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(guild.name)
                    .font(.subheadline.weight(.bold))
                if let desc = guild.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text("Lv \(guild.guildLevel) · \(guild.memberCount)/\(guild.maxMembers) members")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { _ = await service.joinGuild(guild.id) }
            } label: {
                Text(guild.isFull ? "Full" : "Join")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(guild.isFull ? Color.gray : Color.cyan, in: Capsule())
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(guild.isFull)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mode B: In a guild

    @ViewBuilder
    private var inGuildContent: some View {
        if let guild = service.currentGuild {
            VStack(spacing: 20) {
                guildHeader(guild)
                if let raid = service.currentRaid {
                    raidCard(raid)
                }
                if !guild.weeklyFocus.isEmpty || canEditFocus {
                    focusBanner(guild)
                }
                membersSection
                if !service.currentContributions.isEmpty {
                    contributionsSection
                }
                Button(role: .destructive) {
                    showingLeaveConfirm = true
                } label: {
                    Label("Leave Guild", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var canEditFocus: Bool {
        service.currentRole == "owner" || service.currentRole == "officer"
    }

    private func guildHeader(_ guild: GuildSummary) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.cyan.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "shield.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(guild.name)
                    .font(.title3.bold())
                Text("Lv \(guild.guildLevel) · \(guild.memberCount)/\(guild.maxMembers) members")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !service.currentRole.isEmpty {
                    Text(service.currentRole.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.cyan)
                        .tracking(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.cyan.opacity(0.15), in: Capsule())
                }
            }
            Spacer()
        }
    }

    private func raidCard(_ raid: GuildRaid) -> some View {
        let archetype = WeeklyBossArchetype(rawValue: raid.boss_key ?? "")
        let color = archetype?.color ?? .red
        let icon = archetype?.icon ?? "flame.fill"
        let name = archetype?.displayName ?? "Weekly Raid"
        let unit = archetype?.hpUnit ?? "HP"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("【GUILD RAID】")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(color)
                        .tracking(2)
                    Text(name.uppercased())
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                Spacer()
                if raid.isDefeated {
                    Text("DEFEATED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                        .tracking(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.18), in: Capsule())
                }
            }
            // HP bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("HP").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(raid.damageDealt) / \(raid.maxHP) \(unit)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.gray.opacity(0.2))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * raid.progress), height: 12)
                            .animation(.easeOut(duration: 0.4), value: raid.damageDealt)
                    }
                }
                .frame(height: 12)
            }
            if raid.isDefeated {
                Button {
                    Task { _ = await service.claimRaidReward() }
                } label: {
                    Label("Claim Reward (200 GP)", systemImage: "gift.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }

    private func focusBanner(_ guild: GuildSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "target")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("WEEKLY FOCUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Text(guild.weeklyFocus.isEmpty ? "(No focus set)" : guild.weeklyFocus)
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(.primary)
            }
            Spacer()
            if canEditFocus {
                Button {
                    focusDraft = guild.weeklyFocus
                    showingFocusEditor = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMBERS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            ForEach(service.currentMembers.sorted(by: { ($0.contribution_xp ?? 0) > ($1.contribution_xp ?? 0) })) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: GuildMember) -> some View {
        let isMe = member.cloudkit_user_id == LeaderboardService.shared.currentUserID
        return HStack(spacing: 10) {
            Circle()
                .fill(member.isOwner ? .yellow.opacity(0.18) : .gray.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: member.isOwner ? "crown.fill" : "person.fill")
                        .font(.system(size: 13))
                        .foregroundColor(member.isOwner ? .yellow : .secondary)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.display_name)
                        .font(.subheadline.weight(.semibold))
                    if isMe {
                        Text("YOU")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.cyan.opacity(0.15), in: Capsule())
                    }
                }
                Text(member.role.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(member.isOwner ? .yellow : .secondary)
                    .tracking(1)
            }
            Spacer()
            Text("\(member.contribution_xp ?? 0)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(isMe ? Color.cyan.opacity(0.08) : Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var contributionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RAID CONTRIBUTIONS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            let sorted = service.currentContributions.sorted(by: { $0.damage_contributed > $1.damage_contributed })
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, contrib in
                HStack {
                    Text("#\(index + 1)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                    Text(contrib.display_name)
                        .font(.subheadline.weight(.medium))
                    if index == 0 {
                        Text("MVP")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.yellow.opacity(0.18), in: Capsule())
                    }
                    Spacer()
                    Text("\(contrib.damage_contributed)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Create Guild Sheet

private struct CreateGuildSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = GuildService.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isPublic: Bool = true
    @State private var error: String? = nil
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Guild Identity") {
                    TextField("Guild name (3–30 chars)", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("Visible to other players", isOn: $isPublic)
                }
                if let error {
                    Section { Text(error).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Found Guild", systemImage: "shield.checkered")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || isCreating)
                }
            }
            .navigationTitle("New Guild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let result = await service.createGuild(name: name, description: description, isPublic: isPublic)
        switch result {
        case .success:
            dismiss()
        case .failure(let msg):
            error = msg
        }
    }
}
