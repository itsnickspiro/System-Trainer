import SwiftUI
import MapKit
import SwiftData

// MARK: - PatrolMapView
//
// Displays a completed or in-progress PatrolRoute on a dark MapKit map with a
// glowing cyan polyline and a bottom HUD showing live/final metrics.
//
// Two usage modes:
//  • Live mode:    PatrolMapView(mode: .live) — observes LocationTrackerService.shared
//  • Review mode:  PatrolMapView(mode: .review(route)) — renders a saved PatrolRoute

enum PatrolMapMode {
    case live
    case review(PatrolRoute)
}

struct PatrolMapView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tracker = LocationTrackerService.shared

    let mode: PatrolMapMode

    // Map camera
    @State private var cameraPosition: MapCameraPosition = .automatic

    // HUD / notification state
    @State private var showCompletionBanner = false
    @State private var completionMessage = ""
    @State private var isEndingPatrol = false

    // MARK: - Derived data from mode

    private var displayCoords: [CLLocationCoordinate2D] {
        switch mode {
        case .live:
            return tracker.liveCoordinates
        case .review(let route):
            return LocationTrackerService.decodeCoordinates(from: route.encodedCoordinates)
        }
    }

    private var distanceText: String {
        switch mode {
        case .live:   return tracker.distanceDisplay
        case .review(let route): return route.distanceDisplay
        }
    }

    private var durationText: String {
        switch mode {
        case .live:
            return tracker.durationDisplay
        case .review(let route):
            let h = route.durationSeconds / 3600
            let m = (route.durationSeconds % 3600) / 60
            let s = route.durationSeconds % 60
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%02d:%02d", m, s)
        }
    }

    private var paceText: String {
        switch mode {
        case .live:   return tracker.paceDisplay
        case .review(let route): return route.paceDisplay
        }
    }

    private var activityType: PatrolActivityType {
        switch mode {
        case .live:   return tracker.currentRoute?.activityType ?? .run
        case .review(let route): return route.activityType
        }
    }

    private var xpText: String {
        switch mode {
        case .live:
            let km = tracker.liveDistanceMeters / 1000
            let xp = Int(km * Double(activityType.xpPerKm))
            return "+\(xp) XP"
        case .review(let route):
            return "+\(route.xpAwarded) XP"
        }
    }

    private var isLive: Bool {
        if case .live = mode { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Map ──────────────────────────────────────────────────────
            Map(position: $cameraPosition) {
                // Glow effect: draw a wider, dimmer stroke beneath the main line
                if displayCoords.count >= 2 {
                    MapPolyline(coordinates: displayCoords)
                        .stroke(.cyan.opacity(0.25), lineWidth: 14)
                    MapPolyline(coordinates: displayCoords)
                        .stroke(.cyan, lineWidth: 4)
                }

                // Start marker
                if let first = displayCoords.first {
                    Annotation("START", coordinate: first) {
                        SystemMarker(label: "S", color: .cyan)
                    }
                }

                // End / current position marker
                if let last = displayCoords.last, displayCoords.count > 1 {
                    Annotation(isLive ? "NOW" : "END", coordinate: last) {
                        SystemMarker(label: isLive ? "●" : "E", color: isLive ? .green : .cyan)
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()
            .onChange(of: displayCoords.count) { _, _ in
                recenterCamera()
            }
            .onAppear { recenterCamera() }

            // ── Gradient fade at bottom ──────────────────────────────────
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // ── HUD ──────────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Completion notification banner
                if showCompletionBanner {
                    SystemNotificationBanner(message: completionMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                PatrolHUD(
                    activityType: activityType,
                    distance: distanceText,
                    duration: durationText,
                    pace: paceText,
                    xp: xpText,
                    isLive: isLive,
                    isEnding: isEndingPatrol,
                    onEnd: endPatrol,
                    onDismiss: { dismiss() }
                )
            }
            .padding(.bottom, 24)
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func recenterCamera() {
        guard displayCoords.count >= 2 else {
            if let first = displayCoords.first {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: first,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )
                )
            }
            return
        }
        // Fit camera to all coordinates with padding
        let lats = displayCoords.map(\.latitude)
        let lngs = displayCoords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  (lats.max()! - lats.min()!) * 1.4 + 0.003,
            longitudeDelta: (lngs.max()! - lngs.min()!) * 1.4 + 0.003
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func endPatrol() {
        guard isLive else { dismiss(); return }

        isEndingPatrol = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        guard let sealed = tracker.stopPatrol() else {
            isEndingPatrol = false
            return
        }

        // Persist the finished route
        context.insert(sealed)
        try? context.save()

        // Award XP to profile
        // (Profile XP update is handled by DataManager / QuestManager on next sync)

        let km = sealed.distanceMeters / 1000
        let msg = String(
            format: "Notice: Patrol Complete. Distance logged: %.2f km. +%d XP awarded.",
            km, sealed.xpAwarded
        )

        withAnimation(.spring(duration: 0.4)) {
            completionMessage = msg
            showCompletionBanner = true
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            dismiss()
        }
    }
}

// MARK: - Subviews

private struct PatrolHUD: View {
    let activityType: PatrolActivityType
    let distance: String
    let duration: String
    let pace: String
    let xp: String
    let isLive: Bool
    let isEnding: Bool
    let onEnd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Activity type label
            HStack(spacing: 6) {
                Image(systemName: activityType.icon)
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Text(activityType.displayName.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.cyan)
                if isLive {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isLive ? 1 : 0)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: isLive)
                }
                Spacer()
                Text(xp)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.yellow)
            }

            // Metric row
            HStack(spacing: 0) {
                MetricCell(label: "DISTANCE", value: distance)
                MetricDivider()
                MetricCell(label: "DURATION", value: duration)
                MetricDivider()
                MetricCell(label: "PACE", value: pace)
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
                    )
            )

            // Action button
            if isLive {
                Button(action: onEnd) {
                    HStack(spacing: 8) {
                        if isEnding {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "stop.fill")
                        }
                        Text(isEnding ? "SEALING ROUTE..." : "END PATROL")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.cyan))
                }
                .disabled(isEnding)
            } else {
                Button(action: onDismiss) {
                    Text("CLOSE DEBRIEF")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.cyan))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .padding(.horizontal, 16)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 36)
    }
}

private struct SystemMarker: View {
    let label: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .frame(width: 22, height: 22)
            Text(label)
                .font(.system(size: 9, design: .monospaced).weight(.black))
                .foregroundStyle(color)
        }
    }
}

private struct SystemNotificationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.cyan)
                .font(.title3)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1)
                )
        )
    }
}
