import SwiftUI

struct ActivityLogView: View {
    @ObservedObject private var logManager = ActivityLogManager.shared
    @AppStorage("colorScheme") private var savedColorScheme = "dark"
    @State private var selectedCategory: ActivityLogEntry.Category?
    @State private var showingClearConfirm = false

    private var filteredEntries: [ActivityLogEntry] {
        guard let cat = selectedCategory else { return logManager.entries }
        return logManager.entries.filter { $0.category == cat }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(ActivityLogEntry.Category.allCases, id: \.self) { cat in
                            FilterChip(label: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "doc.text",
                        description: Text("Actions like earning XP, completing quests, and leveling up will appear here.")
                    )
                } else {
                    // Console-style log
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                LogEntryRow(entry: entry, showDate: shouldShowDate(at: index))
                                if index < filteredEntries.count - 1 {
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !logManager.entries.isEmpty {
                        Button("Clear") {
                            showingClearConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Clear Activity Log?", isPresented: $showingClearConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    logManager.clearAll()
                }
            } message: {
                Text("This removes all log entries. This cannot be undone.")
            }
            .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        }
    }

    /// Show a date header when the day changes between entries.
    private func shouldShowDate(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = filteredEntries[index - 1].date
        let curr = filteredEntries[index].date
        return !Calendar.current.isDate(prev, inSameDayAs: curr)
    }
}

// MARK: - Subviews

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.cyan.opacity(0.3) : Color(.systemGray5))
                .foregroundColor(isSelected ? .cyan : .secondary)
                .clipShape(Capsule())
        }
    }
}

private struct LogEntryRow: View {
    let entry: ActivityLogEntry
    let showDate: Bool

    private var entryColor: Color {
        switch entry.category.color {
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDate {
                Text(entry.date, style: .date)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.category.icon)
                    .font(.system(size: 14))
                    .foregroundColor(entryColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(ActivityLogView.timeFormatter.string(from: entry.date))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}
