import SwiftUI

// MARK: - AchievementsView
//
// Full achievement gallery accessible from Settings. Shows all achievements
// (locked + unlocked), completion progress, and lets the player pin up to
// 6 achievements to their public profile showcase.

struct AchievementGalleryView: View {
    @ObservedObject private var service = AchievementsService.shared
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    private var unlockedKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "rpt_unlocked_achievement_keys") ?? [])
    }

    private var showcaseKeys: [String] {
        UserDefaults.standard.stringArray(forKey: "rpt_showcase_achievement_keys") ?? []
    }

    private var completionPercent: Int {
        let total = service.achievements.count
        guard total > 0 else { return 0 }
        return Int(Double(unlockedKeys.count) / Double(total) * 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    progressHeader

                    if !showcaseKeys.isEmpty {
                        showcaseSection
                    }

                    achievementsList
                }
                .padding()
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(completionPercent) / 100)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(completionPercent)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Complete")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            Text("\(unlockedKeys.count) / \(service.achievements.count) Unlocked")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Showcase Section

    private var showcaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR SHOWCASE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(showcaseKeys, id: \.self) { key in
                    if let a = service.achievements.first(where: { $0.key == key }) {
                        showcaseCell(a)
                    }
                }
            }

            Text("Tap achievements below to add or remove from showcase (max 6)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func showcaseCell(_ a: AchievementTemplate) -> some View {
        VStack(spacing: 6) {
            Image(systemName: a.iconSymbol)
                .font(.system(size: 22))
                .foregroundColor(.yellow)
            Text(a.title)
                .font(.system(size: 9, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Achievements List

    private var achievementsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(service.achievements) { achievement in
                AchievementRow(
                    achievement: achievement,
                    isUnlocked: unlockedKeys.contains(achievement.key),
                    isShowcased: showcaseKeys.contains(achievement.key),
                    onToggleShowcase: { toggleShowcase(achievement.key) }
                )
            }
        }
    }

    private func toggleShowcase(_ key: String) {
        var keys = showcaseKeys
        if let idx = keys.firstIndex(of: key) {
            keys.remove(at: idx)
        } else if keys.count < 6 {
            keys.append(key)
        }
        UserDefaults.standard.set(keys, forKey: "rpt_showcase_achievement_keys")

        // Sync to server
        Task {
            await PlayerProfileService.shared.syncShowcaseKeys(keys)
        }
    }
}

// MARK: - Achievement Row

private struct AchievementRow: View {
    let achievement: AchievementTemplate
    let isUnlocked: Bool
    let isShowcased: Bool
    let onToggleShowcase: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.iconSymbol)
                .font(.system(size: 28))
                .foregroundColor(isUnlocked ? .yellow : .secondary.opacity(0.4))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.subheadline.weight(isUnlocked ? .bold : .regular))
                    .foregroundColor(isUnlocked ? .primary : .secondary)

                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if isUnlocked && achievement.xpReward > 0 {
                    Text("+\(achievement.xpReward) XP")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
            }

            Spacer()

            if isUnlocked {
                Button(action: onToggleShowcase) {
                    Image(systemName: isShowcased ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(isShowcased ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUnlocked ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isShowcased ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
        )
        .opacity(isUnlocked ? 1 : 0.6)
    }
}
