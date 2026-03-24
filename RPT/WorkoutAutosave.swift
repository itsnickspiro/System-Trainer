import Foundation

// MARK: - Workout Autosave
//
// Persists in-progress workout state to UserDefaults every 30 seconds.
// On next launch of ActiveWorkoutView, the app checks for a stale autosave
// from the same routine and offers to resume it.
//
// Data flow:
//   ActiveWorkoutView
//     └─► WorkoutAutosaveManager.save(state:) every 30s
//     └─► WorkoutAutosaveManager.clearSave() on complete / abandon
//     └─► WorkoutAutosaveManager.loadSave(routineName:) on appear

// MARK: - Codable snapshot of one editable set

struct SavedSetState: Codable {
    let setNumber: Int
    let wgerID: Int
    let exerciseName: String
    let weightText: String
    let repsText: String
    let isComplete: Bool
}

// MARK: - Full autosave payload

struct WorkoutAutosaveState: Codable {
    let routineName: String
    let savedAt: Date
    let elapsedSeconds: Int
    let sets: [Int: [SavedSetState]]  // keyed by wgerID

    var isStale: Bool {
        // Consider stale if more than 4 hours old (no one runs a 4h workout)
        Date().timeIntervalSince(savedAt) > 4 * 3600
    }
}

// MARK: - Manager

final class WorkoutAutosaveManager {
    static let shared = WorkoutAutosaveManager()

    private static let defaultsKey = "RPTWorkoutAutosave"

    private init() {}

    /// Persist the current set states to UserDefaults.
    func save(
        routineName: String,
        elapsedSeconds: Int,
        setStates: [Int: [WorkoutEditableSet]]
    ) {
        // Convert Observable view models → Codable value types
        let savedSets = setStates.mapValues { sets in
            sets.map { s in
                SavedSetState(
                    setNumber: s.setNumber,
                    wgerID: s.wgerID,
                    exerciseName: s.exerciseName,
                    weightText: s.weightText,
                    repsText: s.repsText,
                    isComplete: s.isComplete
                )
            }
        }

        let state = WorkoutAutosaveState(
            routineName: routineName,
            savedAt: Date(),
            elapsedSeconds: elapsedSeconds,
            sets: savedSets
        )

        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }

    /// Load any persisted autosave for the given routine. Returns nil if none or stale.
    func loadSave(for routineName: String) -> WorkoutAutosaveState? {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let state = try? JSONDecoder().decode(WorkoutAutosaveState.self, from: data),
            state.routineName == routineName,
            !state.isStale
        else {
            return nil
        }
        return state
    }

    /// Check if there's any stale (non-matching routine) autosave that should be cleared.
    func hasSaveForDifferentRoutine(than routineName: String) -> WorkoutAutosaveState? {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let state = try? JSONDecoder().decode(WorkoutAutosaveState.self, from: data),
            state.routineName != routineName,
            !state.isStale
        else {
            return nil
        }
        return state
    }

    /// Erase the autosave. Call on workout completion, abandon, or after restoring.
    func clearSave() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    /// Convert a loaded save's set state back to WorkoutEditableSet view models.
    func restoreSetStates(from save: WorkoutAutosaveState) -> [Int: [WorkoutEditableSet]] {
        save.sets.mapValues { savedSets in
            savedSets.map { saved in
                let set = WorkoutEditableSet(setNumber: saved.setNumber, wgerID: saved.wgerID)
                set.exerciseName = saved.exerciseName
                set.weightText = saved.weightText
                set.repsText = saved.repsText
                set.isComplete = saved.isComplete
                return set
            }
        }
    }
}
