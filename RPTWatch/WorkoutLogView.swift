import SwiftUI

/// Training tab — minimal. Just a start button.
struct WorkoutLogView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var didTap = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if didTap {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("Opening on iPhone")
                        .font(.system(size: 12, weight: .semibold))
                }
                .transition(.opacity)
            } else {
                Button {
                    session.startSession()
                    withAnimation { didTap = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { didTap = false }
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.cyan)
                        Text("Start Session")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!session.isConnected)
                .opacity(session.isConnected ? 1 : 0.4)
            }

            Spacer()

            if !session.isConnected {
                Label("iPhone not connected", systemImage: "iphone.slash")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Training")
    }
}
