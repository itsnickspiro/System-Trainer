import Foundation
import Combine

/// Lightweight, file-backed activity log for the Settings screen.
/// Appends structured entries to a JSON file in the app's documents
/// directory — no SwiftData schema changes, no CloudKit sync.
@MainActor
final class ActivityLogManager: ObservableObject {
    static let shared = ActivityLogManager()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("activity_log.json")
    }()

    /// Maximum entries kept on disk. Oldest are trimmed on save.
    private let maxEntries = 500

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    func log(_ category: ActivityLogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = ActivityLogEntry(
            date: Date(),
            category: category,
            message: message,
            detail: detail
        )
        entries.insert(entry, at: 0) // newest first
        saveToDisk()
    }

    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            var decoded = try JSONDecoder().decode([ActivityLogEntry].self, from: data)
            decoded.sort { $0.date > $1.date }
            entries = decoded
        } catch {
            print("[ActivityLog] Failed to load: \(error)")
        }
    }

    private func saveToDisk() {
        // Trim to max
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ActivityLog] Failed to save: \(error)")
        }
    }
}

// MARK: - Entry Model

struct ActivityLogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let category: Category
    let message: String
    let detail: String?

    init(date: Date, category: Category, message: String, detail: String?) {
        self.id = UUID()
        self.date = date
        self.category = category
        self.message = message
        self.detail = detail
    }

    enum Category: String, Codable, CaseIterable {
        case xp = "XP"
        case levelUp = "Level Up"
        case quest = "Quest"
        case streak = "Streak"
        case gp = "GP"
        case health = "Health"
        case profile = "Profile"
        case system = "System"

        var icon: String {
            switch self {
            case .xp: return "star.fill"
            case .levelUp: return "arrow.up.circle.fill"
            case .quest: return "scroll.fill"
            case .streak: return "flame.fill"
            case .gp: return "dollarsign.circle.fill"
            case .health: return "heart.fill"
            case .profile: return "person.fill"
            case .system: return "gearshape.fill"
            }
        }

        var color: String {
            switch self {
            case .xp: return "cyan"
            case .levelUp: return "yellow"
            case .quest: return "green"
            case .streak: return "orange"
            case .gp: return "orange"
            case .health: return "red"
            case .profile: return "blue"
            case .system: return "gray"
            }
        }
    }
}
