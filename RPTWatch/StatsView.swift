import SwiftUI

/// Main Watch face — clean, glanceable overview.
/// Health data comes from WatchHealthManager (on-device HealthKit) first,
/// falling back to WatchSessionManager (iPhone relay) if the local value is zero.
struct StatsView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @ObservedObject private var health = WatchHealthManager.shared

    /// Use local HealthKit value if available, otherwise fall back to iPhone relay.
    private var displaySteps: Int { health.steps > 0 ? health.steps : session.steps }
    private var displayCalories: Int { health.caloriesBurned > 0 ? health.caloriesBurned : session.caloriesBurned }
    private var displayHeartRate: Int { health.heartRate > 0 ? health.heartRate : session.heartRate }
    private var displaySleepHours: Double { health.sleepHours > 0 ? health.sleepHours : session.sleepHours }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // XP ring with level inside
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: xpProgress)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: xpProgress)

                    VStack(spacing: 0) {
                        Text("\(session.level)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("LEVEL")
                            .font(.system(size: 7, weight: .heavy, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 76, height: 76)

                // Name + XP text
                VStack(spacing: 2) {
                    Text(session.playerName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(session.xp) / \(session.xpToNextLevel) XP")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                // Streak pill
                if session.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("\(session.currentStreak) day streak")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }

                // Health stats — 2x2 grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    healthTile(icon: "figure.walk", value: formatSteps(displaySteps), label: "Steps", color: .green)
                    healthTile(icon: "flame.fill", value: "\(displayCalories)", label: "Cal", color: .red)
                    healthTile(icon: "heart.fill", value: displayHeartRate > 0 ? "\(displayHeartRate)" : "—", label: "BPM", color: .pink)
                    healthTile(icon: "moon.fill", value: displaySleepHours > 0 ? String(format: "%.1f", displaySleepHours) : "—", label: "Sleep", color: .purple)
                }

                if !session.isConnected {
                    Label("iPhone not connected", systemImage: "iphone.slash")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            WatchHealthManager.shared.refreshHealthData()
        }
        .navigationTitle("System")
    }

    private var xpProgress: CGFloat {
        guard session.xpToNextLevel > 0 else { return 0 }
        return min(CGFloat(session.xp) / CGFloat(session.xpToNextLevel), 1.0)
    }

    private func healthTile(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatSteps(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1fk", Double(n) / 1000.0) }
        return "\(n)"
    }
}
