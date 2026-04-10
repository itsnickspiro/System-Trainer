import SwiftUI

/// Main Watch face — glanceable stats display.
struct StatsView: View {
    @ObservedObject private var session = WatchSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Player name + level
                VStack(spacing: 4) {
                    Text(session.playerName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)

                    Text("LEVEL \(session.level)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)
                }

                // XP progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: xpProgress)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text("\(session.xp)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                        Text("XP")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                // Streak + Quests
                HStack(spacing: 16) {
                    statPill(icon: "flame.fill", value: "\(session.currentStreak)", color: .orange)
                    statPill(icon: "scroll.fill", value: "\(session.activeQuestCount)", color: .green)
                }

                if !session.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 10))
                        Text("iPhone not connected")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("System Trainer")
    }

    private var xpProgress: CGFloat {
        guard session.xpToNextLevel > 0 else { return 0 }
        return CGFloat(session.xp) / CGFloat(session.xpToNextLevel)
    }

    private func statPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15), in: Capsule())
    }
}
