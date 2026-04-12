import SwiftUI

// MARK: - TournamentView
//
// Browse active tournaments, view brackets, register, and claim prizes.
// Accessed from HomeView or a dedicated navigation path.

struct TournamentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var tournaments = TournamentService.shared
    @State private var selectedTab: TournamentTab = .browse
    @State private var selectedTournament: Tournament?

    enum TournamentTab: String, CaseIterable {
        case browse = "Browse"
        case mine   = "My Tournaments"

        var icon: String {
            switch self {
            case .browse: return "trophy.fill"
            case .mine:   return "person.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector

                if tournaments.isLoading {
                    ProgressView("Loading Tournaments...")
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedTab) {
                        browseTab
                            .tag(TournamentTab.browse)
                        myTournamentsTab
                            .tag(TournamentTab.mine)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: selectedTab)
                }
            }
            .navigationTitle("Tournaments")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await tournaments.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
        }
        .task { await tournaments.refresh() }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(TournamentTab.allCases, id: \.self) { tab in
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
                                  AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)) :
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

    // MARK: - Browse Tab

    private var browseTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if tournaments.activeTournaments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange.opacity(0.5))
                        Text("No Active Tournaments")
                            .font(.headline)
                        Text("Check back soon for upcoming competitions!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(tournaments.activeTournaments) { tournament in
                        NavigationLink {
                            TournamentDetailView(tournamentID: tournament.id)
                        } label: {
                            tournamentCard(tournament)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minHeight: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - My Tournaments Tab

    private var myTournamentsTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if tournaments.myTournaments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.cyan.opacity(0.5))
                        Text("No Tournaments Joined")
                            .font(.headline)
                        Text("Register for a tournament to compete!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(tournaments.myTournaments) { entry in
                        if let t = entry.tournaments {
                            NavigationLink {
                                TournamentDetailView(tournamentID: t.id)
                            } label: {
                                myTournamentCard(entry, tournament: t)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minHeight: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - Cards

    private func tournamentCard(_ t: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                Text(t.title)
                    .font(.headline)
                Spacer()
                Text(t.statusLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor(t).opacity(0.15)))
                    .foregroundColor(statusColor(t))
            }

            if let desc = t.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                Label("\(t.bracketSize) players", systemImage: "person.3")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let prize = t.prizePoolGp, prize > 0 {
                    Label("\(prize) GP", systemImage: "dollarsign.circle")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                if let cost = t.entryGpCost, cost > 0 {
                    Label("Entry: \(cost) GP", systemImage: "ticket")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Label("Free Entry", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1))
        )
    }

    private func myTournamentCard(_ entry: TournamentParticipation, tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(tournament.title)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Text(tournament.statusLabel)
                        .font(.caption)
                        .foregroundColor(statusColor(tournament))
                    if let placement = entry.finalPlacement {
                        Text("#\(placement)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.yellow)
                    }
                }
            }
            Spacer()

            if entry.prizeClaimedAt == nil && entry.finalPlacement != nil && tournament.status == "completed" {
                Text("Claim")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.yellow.opacity(0.2)))
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }

    private func statusColor(_ t: Tournament) -> Color {
        switch t.status {
        case "registering": return .green
        case "active": return .cyan
        case "completed": return .orange
        default: return .gray
        }
    }
}

// MARK: - Tournament Detail View

struct TournamentDetailView: View {
    let tournamentID: String
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var service = TournamentService.shared
    @State private var detail: TournamentDetail?
    @State private var isRegistering = false
    @State private var registrationResult: String?

    var body: some View {
        ScrollView {
            if let detail = detail {
                VStack(spacing: 20) {
                    headerSection(detail.tournament)

                    if detail.tournament.status == "registering" && detail.myParticipation == nil {
                        registerButton(detail.tournament)
                    } else if let me = detail.myParticipation {
                        myStatusCard(me, tournament: detail.tournament)
                    }

                    if !detail.brackets.isEmpty {
                        bracketSection(detail)
                    }

                    if !detail.participants.isEmpty {
                        participantsSection(detail.participants)
                    }

                    Spacer(minHeight: 40)
                }
                .padding()
            } else {
                ProgressView("Loading tournament...")
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
        .navigationTitle(detail?.tournament.title ?? "Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .task { detail = await service.fetchTournamentDetail(tournamentID) }
    }

    private func headerSection(_ t: Tournament) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(t.title)
                .font(.title2.weight(.bold))

            if let desc = t.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                VStack {
                    Text("\(t.bracketSize)")
                        .font(.title3.weight(.bold))
                    Text("Players")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let prize = t.prizePoolGp, prize > 0 {
                    VStack {
                        Text("\(prize)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.yellow)
                        Text("GP Prize")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                VStack {
                    Text(t.statusLabel)
                        .font(.title3.weight(.bold))
                        .foregroundColor(statusColor(t))
                    Text("Status")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func registerButton(_ t: Tournament) -> some View {
        Button {
            Task {
                isRegistering = true
                let success = await service.register(tournamentID: tournamentID)
                isRegistering = false
                if success {
                    registrationResult = "Registered!"
                    detail = await service.fetchTournamentDetail(tournamentID)
                } else {
                    registrationResult = service.lastError ?? "Registration failed"
                }
            }
        } label: {
            HStack {
                if isRegistering {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "person.badge.plus")
                }
                Text(isRegistering ? "Registering..." : "Register")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
            .foregroundColor(.white)
        }
        .disabled(isRegistering)
        .overlay(alignment: .bottom) {
            if let result = registrationResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result == "Registered!" ? .green : .red)
                    .padding(.top, 4)
            }
        }
    }

    private func myStatusCard(_ me: TournamentParticipation, tournament: Tournament) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("You're registered!")
                    .font(.subheadline.weight(.semibold))
            }
            if let seed = me.seed {
                Text("Seed #\(seed)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let placement = me.finalPlacement {
                Text("Final Placement: #\(placement)")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            if me.prizeClaimedAt == nil && me.finalPlacement != nil && tournament.status == "completed" {
                Button("Claim Prize") {
                    Task {
                        let gp = await service.claimPrize(tournamentID: tournamentID)
                        if gp > 0 {
                            detail = await service.fetchTournamentDetail(tournamentID)
                        }
                    }
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.yellow))
                .foregroundColor(.black)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.1)))
    }

    private func bracketSection(_ detail: TournamentDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bracket")
                .font(.headline)

            let rounds = Set(detail.brackets.map(\.round)).sorted()
            ForEach(rounds, id: \.self) { round in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round \(round)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.cyan)

                    let matches = detail.brackets.filter { $0.round == round }.sorted { $0.matchIndex < $1.matchIndex }
                    ForEach(matches) { match in
                        matchCard(match)
                    }
                }
            }
        }
    }

    private func matchCard(_ match: TournamentBracketMatch) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(match.playerADisplayName ?? "TBD")
                    .font(.system(size: 14, weight: match.winnerCloudkitUserId == match.playerACloudkitUserId ? .bold : .regular))
                    .foregroundColor(match.winnerCloudkitUserId == match.playerACloudkitUserId ? .green : .primary)
                Spacer()
                Text("\(match.playerAXpDelta ?? 0) XP")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Divider()
            HStack {
                Text(match.playerBDisplayName ?? "BYE")
                    .font(.system(size: 14, weight: match.winnerCloudkitUserId == match.playerBCloudkitUserId ? .bold : .regular))
                    .foregroundColor(match.winnerCloudkitUserId == match.playerBCloudkitUserId ? .green : .primary)
                Spacer()
                Text("\(match.playerBXpDelta ?? 0) XP")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }

    private func participantsSection(_ participants: [TournamentParticipant]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants (\(participants.count))")
                .font(.headline)

            ForEach(participants) { p in
                HStack(spacing: 10) {
                    if let seed = p.seed {
                        Text("#\(seed)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                    AvatarImageView(key: p.avatarKey ?? "avatar_default", size: 32)
                    Text(p.displayName)
                        .font(.subheadline)
                    Spacer()
                    if let level = p.level {
                        Text("Lv.\(level)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func statusColor(_ t: Tournament) -> Color {
        switch t.status {
        case "registering": return .green
        case "active": return .cyan
        case "completed": return .orange
        default: return .gray
        }
    }
}
