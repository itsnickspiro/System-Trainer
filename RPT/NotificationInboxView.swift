import SwiftUI
import Combine

/// Persistent inbox for notifications the app has delivered.
/// Stored as a JSON file — no SwiftData schema changes needed.
@MainActor
final class NotificationInboxManager: ObservableObject {
    static let shared = NotificationInboxManager()

    @Published private(set) var messages: [InboxMessage] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("notification_inbox.json")
    }()

    private let maxMessages = 200

    private init() {
        loadFromDisk()
    }

    nonisolated func addFromBackground(title: String, body: String, category: String = "general") {
        Task { @MainActor in
            add(title: title, body: body, category: category)
        }
    }

    func add(title: String, body: String, category: String = "general") {
        let msg = InboxMessage(
            date: Date(),
            title: title,
            body: body,
            category: category,
            isRead: false
        )
        messages.insert(msg, at: 0)
        saveToDisk()
    }

    func markRead(_ id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].isRead = true
        saveToDisk()
    }

    func markAllRead() {
        for i in messages.indices { messages[i].isRead = true }
        saveToDisk()
    }

    func clearAll() {
        messages.removeAll()
        saveToDisk()
    }

    var unreadCount: Int {
        messages.filter { !$0.isRead }.count
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            var decoded = try JSONDecoder().decode([InboxMessage].self, from: data)
            decoded.sort { $0.date > $1.date }
            messages = decoded
        } catch {
            print("[NotificationInbox] Failed to load: \(error)")
        }
    }

    private func saveToDisk() {
        if messages.count > maxMessages {
            messages = Array(messages.prefix(maxMessages))
        }
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[NotificationInbox] Failed to save: \(error)")
        }
    }
}

struct InboxMessage: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let body: String
    let category: String
    var isRead: Bool

    init(date: Date, title: String, body: String, category: String, isRead: Bool) {
        self.id = UUID()
        self.date = date
        self.title = title
        self.body = body
        self.category = category
        self.isRead = isRead
    }
}

// MARK: - View

struct NotificationInboxView: View {
    @ObservedObject private var inbox = NotificationInboxManager.shared
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if inbox.messages.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("Notifications from quests, streaks, and achievements will appear here.")
                    )
                } else {
                    List {
                        ForEach(inbox.messages) { msg in
                            InboxMessageRow(message: msg)
                                .onAppear {
                                    if !msg.isRead {
                                        inbox.markRead(msg.id)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if inbox.unreadCount > 0 {
                            Button {
                                inbox.markAllRead()
                            } label: {
                                Label("Mark All Read", systemImage: "envelope.open")
                            }
                        }
                        if !inbox.messages.isEmpty {
                            Button(role: .destructive) {
                                showingClearConfirm = true
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Clear All Notifications?", isPresented: $showingClearConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    inbox.clearAll()
                }
            }
            .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        }
    }
}

private struct InboxMessageRow: View {
    let message: InboxMessage

    private var categoryIcon: String {
        switch message.category {
        case "quest": return "scroll.fill"
        case "streak": return "flame.fill"
        case "levelUp": return "arrow.up.circle.fill"
        case "health": return "heart.fill"
        case "achievement": return "trophy.fill"
        case "event": return "calendar.badge.exclamationmark"
        default: return "bell.fill"
        }
    }

    private var categoryColor: Color {
        switch message.category {
        case "quest": return .green
        case "streak": return .orange
        case "levelUp": return .yellow
        case "health": return .red
        case "achievement": return .purple
        case "event": return .cyan
        default: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon)
                .font(.title3)
                .foregroundColor(categoryColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.title)
                        .font(.subheadline.weight(message.isRead ? .regular : .bold))
                    Spacer()
                    Text(message.date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            if !message.isRead {
                Circle()
                    .fill(.cyan)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}
