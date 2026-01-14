import SwiftUI
import Combine

struct CoachBarView: View {
    var onAskCoach: () -> Void
    @State private var now = Date()
    private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(onAskCoach: @escaping () -> Void) {
        self.onAskCoach = onAskCoach
    }

    var body: some View {
        VStack(spacing: 8) {
            // Countdown clock at the very top
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(.cyan)
                Text(timeToMidnightString())
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // Coach message bar
            Button(action: onAskCoach) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.white)
                        .imageScale(.large)

                    Text("Ask your System…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.up")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.cyan.opacity(0.4), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.bottom, 6)
            .padding(.horizontal, 16) // safe horizontal spacing
            .padding(.vertical, 8) // additional tappable area to avoid accidental taps
        }
        .onReceive(timer) { now = $0 }
    }

    private func timeToMidnightString() -> String {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let comps = calendar.dateComponents([.hour, .minute, .second], from: now, to: startOfTomorrow)
        let h = comps.hour ?? 0, m = comps.minute ?? 0, s = comps.second ?? 0
        return String(format: "Reset in %02d:%02d:%02d", h, m, s)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CoachBarView(onAskCoach: {})
            .padding()
            .preferredColorScheme(.dark)
    }
}
