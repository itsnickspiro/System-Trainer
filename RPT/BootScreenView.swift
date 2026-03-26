import SwiftUI

// MARK: - Boot Screen View
//
// Single visual state — no phases, no transitions between states.
//   0.0s  Title + rings visible immediately
//   0.0s  Breathing ring animation begins
//   2.0s  "SYSTEM ONLINE" banner fades in
//   3.0s  Screen fades out (0.5s)
//   3.5s  onComplete() called

struct BootScreenView: View {

    let onComplete: () -> Void

    @State private var ringPulse: Bool = false
    @State private var bannerOpacity: Double = 0.0
    @State private var bannerPulse: Bool = false
    @State private var screenOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                mainContent
                Spacer()
                systemOnlineBanner
                    .opacity(bannerOpacity)
                    .padding(.bottom, 60)
            }
        }
        .opacity(screenOpacity)
        .onAppear { startBootSequence() }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 20) {
            Text("SYSTEM TRAINER")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .white],
                                   startPoint: .leading, endPoint: .trailing)
                )

            Text("TRAIN. LEVEL UP. ASCEND.")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6))
                .tracking(4)

            // Breathing concentric rings
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [.cyan, .blue, .cyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5
                    )
                    .frame(width: ringPulse ? 140 : 120, height: ringPulse ? 140 : 120)
                    .blur(radius: 4)
                    .opacity(ringPulse ? 0.5 : 0.2)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                               value: ringPulse)

                // Middle ring
                Circle()
                    .stroke(Color.cyan.opacity(ringPulse ? 0.4 : 0.15), lineWidth: 1)
                    .frame(width: ringPulse ? 108 : 92, height: ringPulse ? 108 : 92)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                               value: ringPulse)

                // Inner ring
                Circle()
                    .stroke(Color.cyan.opacity(ringPulse ? 0.25 : 0.08), lineWidth: 1)
                    .frame(width: ringPulse ? 76 : 64, height: ringPulse ? 76 : 64)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                               value: ringPulse)

                // Center dot
                Circle()
                    .fill(Color.cyan.opacity(ringPulse ? 0.6 : 0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                               value: ringPulse)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
    }

    // MARK: - System Online Banner

    private var systemOnlineBanner: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .cyan.opacity(0.8), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 40)

            Text("◆  SYSTEM ONLINE  ◆")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .tracking(6)
                .scaleEffect(bannerPulse ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: bannerPulse)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, .cyan.opacity(0.8), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Boot Sequence

    private func startBootSequence() {
        // Breathing rings start immediately
        ringPulse = true

        // "SYSTEM ONLINE" fades in at 2.0s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.4)) { bannerOpacity = 1.0 }
            bannerPulse = true
        }

        // Screen fades out at 3.0s, onComplete at 3.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) { screenOpacity = 0.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BootScreenView(onComplete: {})
        .preferredColorScheme(.dark)
}
