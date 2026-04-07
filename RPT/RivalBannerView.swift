import SwiftUI
import SwiftData

/// Versus banner shown on Home when the player has set a rival. Compares
/// the local profile and the rival's last-known leaderboard snapshot on
/// level, total XP, and current streak. Cosmetic — purely a motivation
/// hook (the rival doesn't know they've been picked).
struct RivalBannerView: View {
    @ObservedObject private var leaderboard = LeaderboardService.shared
    @ObservedObject private var dataManager = DataManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var profile: Profile? { dataManager.currentProfile }
    private var rival: LeaderboardEntry? {
        guard let p = profile else { return nil }
        return leaderboard.currentRivalEntry(for: p)
    }

    var body: some View {
        if let profile, let rival, !profile.rivalCloudKitUserID.isEmpty {
            VStack(spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                    Text("【RIVAL MATCH】")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                        .tracking(2)
                    Spacer()
                    Button {
                        leaderboard.clearRival()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Names row
                HStack {
                    nameColumn(name: profile.name, isYou: true, color: .cyan)
                    Spacer()
                    Text("VS")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                        .tracking(2)
                    Spacer()
                    nameColumn(name: rival.displayName, isYou: false, color: .red)
                }

                Divider()

                // Stats rows
                statRow(
                    label: "Level",
                    leftValue: profile.level,
                    rightValue: rival.level ?? 0
                )
                statRow(
                    label: "Total XP",
                    leftValue: profile.totalXPEarned,
                    rightValue: rival.totalXP ?? 0
                )
                statRow(
                    label: "Streak",
                    leftValue: profile.currentStreak,
                    rightValue: rival.currentStreak ?? 0
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? .black.opacity(0.5) : .white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.6), .red.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .red.opacity(0.12), radius: 10, y: 4)
        }
    }

    private func nameColumn(name: String, isYou: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isYou ? "YOU" : "RIVAL")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(color.opacity(0.7))
                .tracking(1.5)
            Text(name)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    private func statRow<T: Comparable & Numeric>(label: String, leftValue: T, rightValue: T) -> some View {
        let youWins = leftValue > rightValue
        let rivalWins = rightValue > leftValue
        return HStack {
            HStack(spacing: 4) {
                if youWins {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.cyan)
                }
                Text("\(formatValue(leftValue))")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(youWins ? .cyan : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(1)

            HStack(spacing: 4) {
                Text("\(formatValue(rightValue))")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(rivalWins ? .red : .secondary)
                if rivalWins {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formatValue<T: Numeric>(_ value: T) -> String {
        if let int = value as? Int {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: int)) ?? "\(int)"
        }
        return "\(value)"
    }
}
