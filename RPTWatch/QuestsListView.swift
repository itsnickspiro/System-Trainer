import SwiftUI

/// Shows active quests on the Watch — read-only. Tap to see details.
struct QuestsListView: View {
    @ObservedObject private var session = WatchSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if session.activeQuests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        Text("All Done!")
                            .font(.system(size: 14, weight: .semibold))
                        Text("No active quests")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                } else {
                    ForEach(session.activeQuests.indices, id: \.self) { index in
                        let quest = session.activeQuests[index]
                        QuestRow(quest: quest)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Quests")
    }
}

private struct QuestRow: View {
    let quest: [String: Any]
    @State private var showingDetail = false

    private var title: String { quest["title"] as? String ?? "Quest" }
    private var xpReward: Int { quest["xp_reward"] as? Int ?? 0 }
    private var isCompleted: Bool { quest["is_completed"] as? Bool ?? false }
    private var questDescription: String { quest["description"] as? String ?? "" }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isCompleted ? .green : .cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .strikethrough(isCompleted)
                        .foregroundColor(isCompleted ? .secondary : .primary)

                    if xpReward > 0 {
                        Text("+\(xpReward) XP")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            QuestDetailView(
                title: title,
                description: questDescription,
                xpReward: xpReward,
                isCompleted: isCompleted
            )
        }
    }
}

private struct QuestDetailView: View {
    let title: String
    let description: String
    let xpReward: Int
    let isCompleted: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isCompleted ? .green : .cyan)
                    Text(isCompleted ? "Completed" : "In Progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isCompleted ? .green : .cyan)
                }

                Text(title)
                    .font(.system(size: 15, weight: .bold))

                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                    Text("+\(xpReward) XP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                Text("Complete quests on your iPhone")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Quest")
    }
}
