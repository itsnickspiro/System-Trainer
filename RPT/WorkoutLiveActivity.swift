import ActivityKit
import SwiftUI

// MARK: - Workout Live Activity
//
// Shows an in-progress workout on the Lock Screen and Dynamic Island.
// Displays: routine name, elapsed time, current exercise, sets completed.
//
// How to use:
//   1. Call WorkoutActivityManager.shared.start(session:) when a workout begins
//   2. Call WorkoutActivityManager.shared.update(currentExercise:setsCompleted:totalSets:)
//      after each set
//   3. Call WorkoutActivityManager.shared.end(session:) when the workout finishes
//
// ActivityKit framework link: Add ActivityKit.framework to the main app target.
// NSSupportsLiveActivities must be set to YES in Info.plist.

// MARK: - Activity Attributes

struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias WorkoutStatus = ContentState

    public struct ContentState: Codable, Hashable {
        /// Current exercise being performed
        var currentExercise: String
        /// Sets completed for the entire workout
        var setsCompleted: Int
        /// Total sets in the workout
        var totalSets: Int
        /// Rest timer end date (nil = no active rest timer)
        var restTimerEnd: Date?
        /// Total volume lifted so far (kg)
        var totalVolumeKg: Double
        /// Elapsed workout duration in seconds (from startedAt)
        var elapsedSeconds: Int

        var isResting: Bool { restTimerEnd.map { $0 > Date() } ?? false }

        var progressFraction: Double {
            guard totalSets > 0 else { return 0 }
            return Double(setsCompleted) / Double(totalSets)
        }
    }

    /// Immutable data (set at activity start, cannot change)
    var routineName: String
    var startedAt: Date
}

// MARK: - Live Activity Manager

@MainActor
@Observable
final class WorkoutActivityManager {
    static let shared = WorkoutActivityManager()

    private(set) var isActive = false

    private var activity: Activity<WorkoutActivityAttributes>?
    private var elapsedTimer: Timer?
    private var startedAt: Date = Date()

    // MARK: - Start

    /// Start a Live Activity for the given workout session.
    func start(routineName: String, totalSets: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WorkoutActivityAttributes(
            routineName: routineName,
            startedAt: Date()
        )
        startedAt = attributes.startedAt

        let initialState = WorkoutActivityAttributes.ContentState(
            currentExercise: "Starting workout…",
            setsCompleted: 0,
            totalSets: max(1, totalSets),
            restTimerEnd: nil,
            totalVolumeKg: 0,
            elapsedSeconds: 0
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isActive = true
            startElapsedTimer()
        } catch {
            print("[WorkoutActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Update

    /// Update the activity after logging a set or starting a rest timer.
    func update(
        currentExercise: String,
        setsCompleted: Int,
        totalSets: Int,
        restDuration: TimeInterval? = nil,
        totalVolumeKg: Double = 0
    ) {
        guard let activity else { return }

        let restEnd = restDuration.map { Date().addingTimeInterval($0) }
        let elapsed = Int(Date().timeIntervalSince(startedAt))

        let newState = WorkoutActivityAttributes.ContentState(
            currentExercise: currentExercise,
            setsCompleted: setsCompleted,
            totalSets: totalSets,
            restTimerEnd: restEnd,
            totalVolumeKg: totalVolumeKg,
            elapsedSeconds: elapsed
        )

        Task {
            let content = ActivityContent(state: newState, staleDate: nil)
            await activity.update(content)
        }
    }

    // MARK: - End

    /// End the activity when the workout is finished.
    func end(totalVolumeKg: Double, xpAwarded: Int) {
        guard let activity else { return }

        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let finalState = WorkoutActivityAttributes.ContentState(
            currentExercise: "Workout complete! +\(xpAwarded) XP",
            setsCompleted: activity.content.state.totalSets,
            totalSets: activity.content.state.totalSets,
            restTimerEnd: nil,
            totalVolumeKg: totalVolumeKg,
            elapsedSeconds: elapsed
        )

        Task {
            let content = ActivityContent(state: finalState, staleDate: Date().addingTimeInterval(60))
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(30)))
        }

        stopElapsedTimer()
        isActive = false
        self.activity = nil
    }

    // MARK: - Private

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let act = self.activity else { return }
                let current = act.content.state
                let elapsed = Int(Date().timeIntervalSince(self.startedAt))
                let updated = WorkoutActivityAttributes.ContentState(
                    currentExercise: current.currentExercise,
                    setsCompleted: current.setsCompleted,
                    totalSets: current.totalSets,
                    restTimerEnd: current.restTimerEnd,
                    totalVolumeKg: current.totalVolumeKg,
                    elapsedSeconds: elapsed
                )
                let content = ActivityContent(state: updated, staleDate: nil)
                await act.update(content)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
