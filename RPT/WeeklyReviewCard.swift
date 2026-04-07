import SwiftUI

/// Dismissible card shown on Home that displays the current week's AI-generated
/// review. Only renders if `WeeklyReviewService.shared.shouldShowCard == true`.
struct WeeklyReviewCard: View {
    @ObservedObject private var service = WeeklyReviewService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if service.shouldShowCard, let review = service.currentReview {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("【WEEKLY SYSTEM BRIEFING】")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                            .tracking(2)
                        Text(review.weekMood.uppercased())
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button { service.dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Content rows
                VStack(alignment: .leading, spacing: 12) {
                    row(icon: "checkmark.seal.fill", color: .green, label: "Strong Suit", body: review.wentWell)
                    row(icon: "exclamationmark.triangle.fill", color: .orange, label: "Growth Edge", body: review.toImprove)
                    row(icon: "bolt.fill", color: .cyan, label: "This Week", body: review.nextWeekDirective)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.6), Color.purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: Color.cyan.opacity(0.15), radius: 16, y: 4)
        }
    }

    private func row(icon: String, color: Color, label: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
