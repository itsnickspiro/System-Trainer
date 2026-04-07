import SwiftUI

/// Compact DBZ-style "scouter" badge showing the player's current Power Level.
/// Designed to slot next to the player name in HomeView's player card, or be
/// used as a secondary display anywhere a profile is shown.
struct PowerLevelBadge: View {
    let profile: Profile
    var compact: Bool = true

    private var tierColor: Color {
        switch profile.powerLevel {
        case 0..<1000:      return .white.opacity(0.7)
        case 1000..<3000:   return .cyan
        case 3000..<6000:   return Color(red: 0.2, green: 0.8, blue: 1.0)
        case 6000..<9000:   return .purple
        case 9000..<15000:  return Color(red: 1.0, green: 0.3, blue: 0.6)
        case 15000..<25000: return .yellow
        case 25000..<50000: return Color(red: 1.0, green: 0.5, blue: 0.1)
        default:            return Color(red: 1.0, green: 0.1, blue: 0.1)
        }
    }

    var body: some View {
        if compact {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("PWR")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1)
                Text(profile.powerLevelFormatted)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(tierColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tierColor.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(tierColor.opacity(0.45), lineWidth: 1)
                    )
            )
            .help("Power Level: \(profile.powerLevel) — \(profile.powerLevelTier)")
        } else {
            VStack(spacing: 2) {
                Text("【SCOUTER】")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(tierColor.opacity(0.8))
                    .tracking(2)
                Text(profile.powerLevelFormatted)
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundColor(tierColor)
                Text(profile.powerLevelTier.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(tierColor.opacity(0.7))
                    .tracking(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tierColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tierColor.opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: tierColor.opacity(0.3), radius: 12)
        }
    }
}
