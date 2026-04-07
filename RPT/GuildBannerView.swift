import SwiftUI

struct GuildBannerView: View {
    @ObservedObject private var service = GuildService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let guild = service.currentGuild, let raid = service.currentRaid {
            let archetype = WeeklyBossArchetype(rawValue: raid.boss_key ?? "")
            let color = archetype?.color ?? .cyan
            let icon = archetype?.icon ?? "flame.fill"
            let name = archetype?.displayName ?? "Weekly Raid"

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                    Text("【GUILD: \(guild.name.uppercased())】")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.cyan)
                        .tracking(1)
                        .lineLimit(1)
                    Spacer()
                    Text("\(guild.memberCount)/\(guild.maxMembers)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                        Text(raid.isDefeated ? "DEFEATED — Tap to claim" : "Raid in progress")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(raid.isDefeated ? .green : .secondary)
                            .tracking(1)
                    }
                    Spacer()
                    Text("\(Int(raid.progress * 100))%")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(color)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.gray.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * raid.progress), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? .black.opacity(0.5) : .white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(LinearGradient(colors: [.cyan.opacity(0.5), color.opacity(0.5)], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                    )
            )
        }
    }
}
