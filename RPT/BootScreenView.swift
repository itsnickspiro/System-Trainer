import SwiftUI

// MARK: - Boot Screen View
//
// Simulates a cold, dark-terminal "System boot" sequence before the main UI loads.
// Phases:
//   0  →  Black screen with blinking cursor
//   1  →  Core module log lines scroll in one by one
//   2  →  Logo materialises from scan-line blur
//   3  →  "SYSTEM ONLINE" banner pulses then fades out
//   4  →  Transition to ContentView

struct BootScreenView: View {

    // Called when the animation finishes so RPTApp can swap views.
    let onComplete: () -> Void

    // MARK: - State
    @State private var phase: BootPhase = .blank
    @State private var visibleLines: Int = 0
    @State private var logOpacity: Double = 1.0
    @State private var logoScale: Double = 0.6
    @State private var logoOpacity: Double = 0.0
    @State private var logoBlur: Double = 20.0
    @State private var bannerOpacity: Double = 0.0
    @State private var bannerPulse: Bool = false
    @State private var cursorVisible: Bool = true
    @State private var screenOpacity: Double = 1.0

    // MARK: - Boot Log Lines
    private let bootLog: [BootLogLine] = [
        BootLogLine("SYSTEM",    "Initialising kernel v4.1.0 ..."),
        BootLogLine("MEMORY",    "Allocating 512 MB heap — OK"),
        BootLogLine("HEALTHKIT", "Binding observer queries — OK"),
        BootLogLine("CLOUDKIT",  "Resolving iCloud identity — OK"),
        BootLogLine("SWIFTDATA", "Mounting persistent store — OK"),
        BootLogLine("AI_ENGINE", "Loading on-device model — OK"),
        BootLogLine("LOCATION",  "Registering patrol service — OK"),
        BootLogLine("QUESTS",    "Generating daily directives — OK"),
        BootLogLine("PENALTY",   "Evaluating midnight deadline — OK"),
        BootLogLine("SYSTEM",    "All modules nominal. Awaiting Player."),
    ]

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Phase 1: Boot Log ─────────────────────────────────────
                if phase == .logging || phase == .logo {
                    bootLogView
                        .opacity(logOpacity)
                        .transition(.opacity)
                }

                Spacer()

                // ── Phase 2: Logo ─────────────────────────────────────────
                if phase == .logo || phase == .banner {
                    logoView
                }

                Spacer()

                // ── Phase 3: SYSTEM ONLINE banner ─────────────────────────
                if phase == .banner {
                    systemOnlineBanner
                        .opacity(bannerOpacity)
                        .padding(.bottom, 60)
                }
            }

            // Phase 0: blinking cursor in top-left
            if phase == .blank {
                VStack {
                    HStack {
                        blinkingCursor
                            .padding(.leading, 20)
                            .padding(.top, 60)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .opacity(screenOpacity)
        .onAppear { startBootSequence() }
    }

    // MARK: - Sub-Views

    private var bootLogView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<min(visibleLines, bootLog.count), id: \.self) { i in
                BootLogRow(line: bootLog[i])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logoView: some View {
        VStack(spacing: 8) {
            // Outer glow ring
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: [.cyan, .blue, .cyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .frame(width: 110, height: 110)
                    .blur(radius: 4)
                    .opacity(logoOpacity * 0.6)

                // Logo mark
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
            .scaleEffect(logoScale)
            .blur(radius: logoBlur)
            .opacity(logoOpacity)

            Text("R P T")
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .white],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .opacity(logoOpacity)
                .scaleEffect(logoScale)

            Text("SOLO LEVELING FITNESS SYSTEM")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6))
                .tracking(4)
                .opacity(logoOpacity)
        }
        .padding(.vertical, 24)
    }

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
        .opacity(bannerOpacity)
    }

    private var blinkingCursor: some View {
        Text("_")
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(.cyan)
            .opacity(cursorVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    cursorVisible.toggle()
                }
            }
    }

    // MARK: - Boot Sequence

    private func startBootSequence() {
        // Phase 0 — blank with cursor (0.4 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.2)) { phase = .logging }
            scrollLogLines()
        }
    }

    private func scrollLogLines() {
        let lineDelay: Double = 0.12
        for i in 0..<bootLog.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * lineDelay) {
                withAnimation(.easeOut(duration: 0.1)) { visibleLines = i + 1 }
            }
        }
        let totalLogTime = Double(bootLog.count) * lineDelay + 0.3

        // Fade log out, show logo
        DispatchQueue.main.asyncAfter(deadline: .now() + totalLogTime) {
            withAnimation(.easeOut(duration: 0.4)) { logOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                phase = .logo
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                    logoBlur = 0.0
                }
                showBanner()
            }
        }
    }

    private func showBanner() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            phase = .banner
            withAnimation(.easeIn(duration: 0.4)) { bannerOpacity = 1.0 }
            bannerPulse = true

            // Hold for 1.2 s then fade out entire screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.6)) { screenOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Supporting Types

private enum BootPhase {
    case blank, logging, logo, banner
}

private struct BootLogLine {
    let module: String
    let message: String
    init(_ module: String, _ message: String) {
        self.module = module
        self.message = message
    }
}

private struct BootLogRow: View {
    let line: BootLogLine

    var body: some View {
        HStack(spacing: 8) {
            Text("[\(line.module)]")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 100, alignment: .leading)
            Text(line.message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.green.opacity(0.85))
        }
    }
}

// MARK: - Preview

#Preview {
    BootScreenView(onComplete: {})
        .preferredColorScheme(.dark)
}
