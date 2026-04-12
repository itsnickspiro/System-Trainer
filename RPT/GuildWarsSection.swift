import SwiftUI

// MARK: - GuildWarsSection
//
// Displays active/pending guild wars inside GuildView.
// Fetches from GuildWarService and renders war cards with
// progress bars and accept/decline buttons for pending wars.

struct GuildWarsSection: View {
    @ObservedObject private var warService = GuildWarService.shared
    @State private var selectedWar: GuildWar?
    @State private var showingDeclareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Guild Wars", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
                if GuildService.shared.currentRole == "owner" {
                    Button {
                        showingDeclareSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }

            if warService.activeWars.isEmpty {
                Text("No active wars. Guild leaders can declare war on rival guilds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(warService.activeWars) { war in
                    warCard(war)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
        .sheet(isPresented: $showingDeclareSheet) {
            DeclareWarSheet()
        }
        .sheet(item: $selectedWar) { war in
            GuildWarDetailSheet(warID: war.id)
        }
        .task { await warService.refresh() }
    }

    private func warCard(_ war: GuildWar) -> some View {
        let myGuildID = warService.myGuildID ?? ""
        let isChallenger = war.challengerGuildId == myGuildID
        let myName = isChallenger ? (war.challengerGuildName ?? "Your Guild") : (war.challengedGuildName ?? "Your Guild")
        let opponentName = isChallenger ? (war.challengedGuildName ?? "Opponent") : (war.challengerGuildName ?? "Opponent")
        let isPending = war.status == "pending_acceptance" && !isChallenger

        return Button {
            if war.status != "pending_acceptance" {
                selectedWar = war
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(myName) vs \(opponentName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(war.statusLabel)
                        .font(.caption.weight(.bold))
                        .foregroundColor(warStatusColor(war))
                }

                if war.status == "active" {
                    HStack(spacing: 4) {
                        Text("\(war.durationDays)d war")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let prize = war.prizeGpPerMember, prize > 0 {
                            Text("\(prize) GP/member")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                }

                if isPending {
                    HStack(spacing: 12) {
                        Button("Accept") {
                            Task { _ = await warService.acceptWar(war.id) }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.15)))

                        Button("Decline") {
                            Task { _ = await warService.declineWar(war.id) }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red.opacity(0.15)))
                    }
                }

                if war.status == "completed" {
                    if war.isDraw == true {
                        Text("Draw!")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.orange)
                    } else if war.winnerGuildId == myGuildID {
                        Text("Victory!")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.green)
                    } else {
                        Text("Defeat")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
    }

    private func warStatusColor(_ war: GuildWar) -> Color {
        switch war.status {
        case "pending_acceptance": return .orange
        case "active": return .cyan
        case "completed": return .green
        case "declined": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Declare War Sheet

private struct DeclareWarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var warService = GuildWarService.shared
    @State private var guilds: [(id: String, name: String)] = []
    @State private var selectedGuildID: String?
    @State private var durationDays = 3
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Opponent Guild") {
                    if guilds.isEmpty {
                        Text("Loading guilds...")
                            .foregroundColor(.secondary)
                    }
                    ForEach(guilds, id: \.id) { guild in
                        Button {
                            selectedGuildID = guild.id
                        } label: {
                            HStack {
                                Text(guild.name)
                                Spacer()
                                if selectedGuildID == guild.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                Section("Duration") {
                    Picker("Days", selection: $durationDays) {
                        Text("1 Day").tag(1)
                        Text("3 Days").tag(3)
                        Text("7 Days").tag(7)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Declare War")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Declare") {
                        guard let guildID = selectedGuildID else { return }
                        Task {
                            isLoading = true
                            let success = await warService.declareWar(targetGuildID: guildID, durationDays: durationDays)
                            isLoading = false
                            if success { dismiss() }
                        }
                    }
                    .disabled(selectedGuildID == nil || isLoading)
                    .foregroundColor(.red)
                }
            }
        }
        .task { await loadGuilds() }
    }

    private func loadGuilds() async {
        // Fetch public guilds via guild-proxy
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/guild-proxy") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        let body: [String: Any] = ["action": "list_public_guilds", "page_size": 50]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let guildArray = json["guilds"] as? [[String: Any]] else { return }

        let myGuildID = GuildService.shared.currentGuild?.id ?? ""
        guilds = guildArray.compactMap { g in
            guard let id = g["id"] as? String, let name = g["name"] as? String, id != myGuildID else { return nil }
            return (id: id, name: name)
        }
    }
}

// MARK: - Guild War Detail Sheet

struct GuildWarDetailSheet: View {
    let warID: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var warService = GuildWarService.shared
    @State private var detail: GuildWarDetail?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let detail = detail {
                    VStack(spacing: 20) {
                        // Score header
                        HStack {
                            VStack {
                                Text(detail.war.challengerGuildName ?? "Challenger")
                                    .font(.subheadline.weight(.bold))
                                Text("\(detail.challengerTotal ?? 0)")
                                    .font(.title.weight(.bold))
                                    .foregroundColor(detail.war.winnerGuildId == detail.war.challengerGuildId ? .green : .primary)
                            }
                            .frame(maxWidth: .infinity)

                            Text("vs")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            VStack {
                                Text(detail.war.challengedGuildName ?? "Challenged")
                                    .font(.subheadline.weight(.bold))
                                Text("\(detail.challengedTotal ?? 0)")
                                    .font(.title.weight(.bold))
                                    .foregroundColor(detail.war.winnerGuildId == detail.war.challengedGuildId ? .green : .primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))

                        // Claim reward button
                        if detail.war.status == "completed" && detail.war.winnerGuildId == warService.myGuildID {
                            Button {
                                Task {
                                    let gp = await warService.claimReward(warID)
                                    if gp > 0 {
                                        self.detail = await warService.fetchWarDetail(warID)
                                    }
                                }
                            } label: {
                                Label("Claim \(detail.war.prizeGpPerMember ?? 250) GP Reward", systemImage: "gift.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.yellow))
                                    .foregroundColor(.black)
                            }
                        }

                        // Members lists
                        if !detail.challengerMembers.isEmpty {
                            membersSection(detail.war.challengerGuildName ?? "Challenger", members: detail.challengerMembers)
                        }
                        if !detail.challengedMembers.isEmpty {
                            membersSection(detail.war.challengedGuildName ?? "Challenged", members: detail.challengedMembers)
                        }
                    }
                    .padding()
                } else {
                    ProgressView("Loading war details...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .navigationTitle("War Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { detail = await warService.fetchWarDetail(warID) }
    }

    private func membersSection(_ title: String, members: [GuildWarParticipant]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))

            ForEach(members) { member in
                HStack {
                    Text(member.displayName ?? "Player")
                        .font(.subheadline)
                    Spacer()
                    Text("+\(member.delta) XP")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}
