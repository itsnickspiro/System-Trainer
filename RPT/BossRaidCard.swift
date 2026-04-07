import SwiftUI

struct BossRaidCard: View {
    @ObservedObject private var service = BossRaidService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let boss = service.currentBoss, let archetype = service.currentArchetype {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(archetype.color.opacity(0.18))
                            .frame(width: 52, height: 52)
                        Circle()
                            .stroke(archetype.color.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: archetype.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(archetype.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("【WEEKLY RAID】")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(archetype.color)
                            .tracking(2)
                        Text(archetype.displayName.uppercased())
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    if boss.isDefeated {
                        Text("DEFEATED")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.18), in: Capsule())
                    }
                }

                // Flavor
                Text(archetype.flavor)
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // HP bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("HP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(boss.damageDealt) / \(boss.maxHP) \(archetype.hpUnit)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(archetype.color)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.gray.opacity(0.18))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    colors: [archetype.color.opacity(0.7), archetype.color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: max(4, geo.size.width * boss.progress), height: 12)
                                .animation(.easeOut(duration: 0.4), value: boss.damageDealt)
                        }
                    }
                    .frame(height: 12)
                }

                // Claim button (only when defeated and unclaimed)
                if boss.isDefeated && !boss.rewardClaimed {
                    Button {
                        service.claimReward()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                            Text("Claim \(archetype.defeatReward) GP + Title")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(archetype.color)
                                .shadow(color: archetype.color.opacity(0.5), radius: 12, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? .black.opacity(0.5) : .white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(archetype.color.opacity(0.5), lineWidth: 1.5)
                    )
            )
            .shadow(color: archetype.color.opacity(0.15), radius: 14, y: 4)
        }
    }
}
