import SwiftUI

/// Shows active quests on the Watch with a complete button.
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
    @ObservedObject private var session = WatchSessionManager.shared

    private var title: String { quest["title"] as? String ?? "Quest" }
    private var questID: String { quest["id"] as? String ?? "" }
    private var xpReward: Int { quest["xp_reward"] as? Int ?? 0 }
    private var isCompleted: Bool { quest["is_completed"] as? Bool ?? false }

    var body: some View {
        Button {
            if !isCompleted {
                session.completeQuest(id: questID)
            }
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
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .disabled(isCompleted)
    }
}
