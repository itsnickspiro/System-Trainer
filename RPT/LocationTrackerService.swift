import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - LocationTrackerService
//
// Strava replacement — tracks outdoor patrol routes using CoreLocation.
//
// Background tracking requires:
//   • Info.plist: NSLocationWhenInUseUsageDescription + NSLocationAlwaysAndWhenInUseUsageDescription
//   • Info.plist UIBackgroundModes array: "location"
//   • Signing & Capabilities → Background Modes → Location updates (enabled)
//
// The service updates in real time, stores a CLLocationCoordinate2D array,
// encodes it as JSON into PatrolRoute.encodedCoordinates for SwiftData persistence.

@MainActor
final class LocationTrackerService: NSObject, ObservableObject {

    static let shared = LocationTrackerService()

    // MARK: - Published State
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking: Bool = false
    @Published var currentRoute: PatrolRoute?
    @Published var liveCoordinates: [CLLocationCoordinate2D] = []
    @Published var liveDistanceMeters: Double = 0.0
    @Published var liveDurationSeconds: Int = 0
    @Published var livePaceSecondsPerKm: Double = 0.0
    @Published var errorMessage: String?

    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var trackingStartedAt: Date?
    private var durationTimer: Timer?
    private var lastLocation: CLLocation?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5      // Update every 5 metres
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        authStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Tracking Control

    func startPatrol(name: String = "Patrol Route", activityType: PatrolActivityType = .run) {
        guard !isTracking else { return }
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            errorMessage = "Location permission required. Enable in Settings."
            return
        }

        let route = PatrolRoute(name: name, activityType: activityType)
        currentRoute = route
        liveCoordinates = []
        liveDistanceMeters = 0
        liveDurationSeconds = 0
        livePaceSecondsPerKm = 0
        lastLocation = nil
        trackingStartedAt = Date()
        isTracking = true

        locationManager.startUpdatingLocation()
        startDurationTimer()
    }

    func stopPatrol() -> PatrolRoute? {
        guard isTracking, let route = currentRoute else { return nil }

        locationManager.stopUpdatingLocation()
        stopDurationTimer()
        isTracking = false

        // Finalise route data
        route.finishedAt = Date()
        route.distanceMeters = liveDistanceMeters
        route.durationSeconds = liveDurationSeconds
        route.averagePaceSecondsPerKm = livePaceSecondsPerKm
        route.elevationGainMeters = calculateElevationGain()
        route.encodedCoordinates = encodeCoordinates(liveCoordinates)

        // Award XP based on distance and activity type
        let km = liveDistanceMeters / 1000
        route.xpAwarded = Int(km * Double(route.activityType.xpPerKm))

        currentRoute = route
        return route
    }

    // MARK: - Live Metrics Helpers

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.liveDurationSeconds += 1
                self?.updateLivePace()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateLivePace() {
        guard liveDistanceMeters > 50 && liveDurationSeconds > 0 else { return }
        let km = liveDistanceMeters / 1000
        livePaceSecondsPerKm = km > 0 ? Double(liveDurationSeconds) / km : 0
    }

    private func calculateElevationGain() -> Double {
        // Sum of all positive altitude changes across the route
        // Requires altitude-aware CLLocation samples stored separately.
        // For now, returns 0 — full implementation requires storing CLLocation,
        // not just CLLocationCoordinate2D.
        return 0
    }

    // MARK: - Coordinate Serialisation

    /// Encodes [CLLocationCoordinate2D] as a JSON array of {lat, lng} objects.
    private func encodeCoordinates(_ coords: [CLLocationCoordinate2D]) -> String {
        let dicts = coords.map { ["lat": $0.latitude, "lng": $0.longitude] }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    /// Decodes a PatrolRoute's encodedCoordinates back to MapKit-ready coordinates.
    static func decodeCoordinates(from encoded: String) -> [CLLocationCoordinate2D] {
        guard
            let data = encoded.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]]
        else { return [] }
        return arr.compactMap { dict in
            guard let lat = dict["lat"], let lng = dict["lng"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    /// Builds a MKPolyline from a PatrolRoute for rendering on a Map.
    static func polyline(for route: PatrolRoute) -> MKPolyline {
        var coords = decodeCoordinates(from: route.encodedCoordinates)
        return MKPolyline(coordinates: &coords, count: coords.count)
    }

    // MARK: - Formatted Display Values

    var durationDisplay: String {
        let h = liveDurationSeconds / 3600
        let m = (liveDurationSeconds % 3600) / 60
        let s = liveDurationSeconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    var distanceDisplay: String {
        String(format: "%.2f km", liveDistanceMeters / 1000)
    }

    var paceDisplay: String {
        guard livePaceSecondsPerKm > 0 else { return "--:--" }
        let m = Int(livePaceSecondsPerKm) / 60
        let s = Int(livePaceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTrackerService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        // Filter out inaccurate samples
        guard newLocation.horizontalAccuracy < 20 else { return }

        Task { @MainActor in
            // Accumulate distance
            if let last = lastLocation {
                let delta = newLocation.distance(from: last)
                // Sanity check: discard GPS jumps > 50m in a single update
                if delta < 50 {
                    liveDistanceMeters += delta
                }
            }

            liveCoordinates.append(newLocation.coordinate)
            lastLocation = newLocation
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authStatus = manager.authorizationStatus
            if authStatus == .denied || authStatus == .restricted {
                errorMessage = "Location access denied. Enable in Settings → Privacy → Location."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Location error: \(error.localizedDescription)"
        }
    }
}
