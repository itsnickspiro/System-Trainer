import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @ObservedObject private var dataManager = DataManager.shared
    private var ai: AIManager { AIManager.shared }
    @State private var userInput = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    @State private var showingSleepPicker = false
    @State private var sleepHoursInput: Double = 7.5
    // Session 2: Log Activity moved from HomeView into The System sheet.
    @State private var showingActivityLogger = false

    private static let historyKey = "coach_chat_history_v1"
    private static let maxStoredMessages = 50

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = decoded
    }

    private func saveHistory() {
        let toSave = Array(messages.suffix(Self.maxStoredMessages))
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }

    private func clearHistory() {
        messages = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Unavailability banner
                if !ai.isAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Apple Intelligence not enabled — enable it in Settings to use The System.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.1))
                }

                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if messages.isEmpty {
                                emptyStateView
                            } else {
                                ForEach(messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                            }

                            if isTyping {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                // Input Area
                VStack(spacing: 0) {
                    Divider()

                    // Quick Action Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ActionChip(icon: "drop.fill", label: "Log Water", color: .blue) {
                                logWater()
                            }
                            ActionChip(icon: "bed.double.fill", label: "Log Sleep", color: .indigo) {
                                showingSleepPicker = true
                            }
                            ActionChip(icon: "figure.walk", label: "Log Activity", color: .green) {
                                showingActivityLogger = true
                            }
                            ActionChip(icon: "dumbbell.fill", label: "Analyze Stats", color: .orange) {
                                userInput = "Analyze my stats and tell me what to prioritize today."
                                sendMessage()
                            }
                            ActionChip(icon: "fork.knife", label: "Meal Advice", color: .green) {
                                userInput = "Based on my nutrition goal and today's calories, what should I eat next?"
                                sendMessage()
                            }
                            ActionChip(icon: "figure.run", label: "Workout Plan", color: .cyan) {
                                userInput = "What is my workout focus today and which exercises should I prioritize?"
                                sendMessage()
                            }
                            ActionChip(icon: "bolt.fill", label: "Level Up Tips", color: .yellow) {
                                userInput = "What is the fastest way to gain XP and level up given my current stats?"
                                sendMessage()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    HStack(spacing: 12) {
                        TextField("Query the System...", text: $userInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1))
                            )
                            .lineLimit(1...5)

                        Button { sendMessage() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping
                                        ? AnyShapeStyle(.gray)
                                        : AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                        }
                        .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTyping)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white)
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color(.systemGroupedBackground))
            .navigationTitle("THE SYSTEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !messages.isEmpty {
                        Button {
                            clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                }
            }
            .onAppear { loadHistory() }
            .sheet(isPresented: $showingSleepPicker) {
                SleepLogSheet(hours: $sleepHoursInput) { hours in
                    logSleep(hours: hours)
                }
            }
            .sheet(isPresented: $showingActivityLogger) {
                ActivityLoggerView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("SYSTEM ONLINE")
                .font(.title.bold())
                .foregroundStyle(.cyan)

            Text("Player data is being monitored. Use quick actions or submit a query.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("SUGGESTED QUERIES")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                suggestedQuestion("Why is my Energy stat low?")
                suggestedQuestion("Am I on track to level up this week?")
                suggestedQuestion("What food should I log after a workout?")
                suggestedQuestion("Rate my performance today.")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1))
            )
        }
        .padding()
        .padding(.top, 40)
    }

    private func suggestedQuestion(_ text: String) -> some View {
        Button {
            userInput = text
            sendMessage()
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                Text(text)
                    .font(.caption)
                Spacer()
            }
            .foregroundColor(.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.cyan.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Quick Actions

    private func logWater() {
        guard let profile = dataManager.currentProfile else { return }
        profile.waterIntake += 1
        context.safeSave()
        let glasses = profile.waterIntake
        let systemMsg = glasses >= 8
            ? "Directive: \(glasses) glasses logged. Hydration threshold achieved. Endurance XP unlocked."
            : "Notice: Water intake updated — \(glasses)/8 glasses logged. \(8 - glasses) remaining to threshold. Continue."
        messages.append(ChatMessage(content: "Log water (+1 glass)", isUser: true))
        messages.append(ChatMessage(content: systemMsg, isUser: false))
        saveHistory()
    }

    private func logSleep(hours: Double) {
        guard dataManager.currentProfile != nil else { return }
        // Route through DataManager so RPG stats (energy/health/focus) are updated and persisted.
        dataManager.recordHealthAction(.recordSleep(hours: hours))
        let formatted = String(format: "%.1f", hours)
        let systemMsg: String
        if hours >= 8 {
            systemMsg = "Notice: \(formatted)h sleep logged. Optimal recovery achieved. Energy and Focus stats operating at full capacity."
        } else if hours >= 7 {
            systemMsg = "Analysis: \(formatted)h sleep logged. Suboptimal — 0.\(Int((8.0 - hours) * 10))h short of threshold. Focus stat mildly suppressed."
        } else {
            systemMsg = "Analysis: \(formatted)h sleep logged. Sleep deficit detected. Focus and Energy stats operating below capacity. Directive: Restore 8h cycle."
        }
        messages.append(ChatMessage(content: "Log sleep: \(formatted) hours", isUser: true))
        messages.append(ChatMessage(content: systemMsg, isUser: false))
        saveHistory()
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(content: trimmed, isUser: true))
        userInput = ""
        isTyping = true

        let ctx = buildPlayerContext()

        Task {
            do {
                let reply = try await ai.chat(message: trimmed, context: ctx)
                isTyping = false
                messages.append(ChatMessage(content: reply, isUser: false))
                saveHistory()
            } catch AIManagerError.unavailable {
                isTyping = false
                messages.append(ChatMessage(
                    content: "SYSTEM OFFLINE. Apple Intelligence must be enabled in iOS Settings > Apple Intelligence & Siri.",
                    isUser: false
                ))
                saveHistory()
            } catch {
                isTyping = false
                messages.append(ChatMessage(
                    content: "SYSTEM ERROR: \(error.localizedDescription)",
                    isUser: false
                ))
                saveHistory()
            }
        }
    }

    /// Serialise the current player profile into a compact context string for the AI.
    private func buildPlayerContext() -> String {
        guard let profile = dataManager.currentProfile else { return "" }
        let quests = dataManager.todaysQuests
        let completed = quests.filter { $0.isCompleted }.count

        let dict: [String: Any] = [
            "player_name": profile.name,
            "level": profile.level,
            "xp": profile.xp,
            "current_streak_days": profile.currentStreak,
            "best_streak_days": profile.bestStreak,
            "stats": [
                "health": profile.health,
                "energy": profile.energy,
                "strength": profile.strength,
                "endurance": profile.endurance,
                "focus": profile.focus,
                "discipline": profile.discipline
            ],
            "today": [
                "quests_total": quests.count,
                "quests_completed": completed,
                "steps": profile.dailySteps,
                "active_calories": profile.dailyActiveCalories,
                "sleep_hours": profile.sleepHours,
                "water_glasses": profile.waterIntake,
                "resting_heart_rate": profile.restingHeartRate
            ]
        ]
        return (try? String(data: JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted), encoding: .utf8)) ?? ""
    }
}

// MARK: - Action Chip

struct ActionChip: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
                    .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sleep Log Sheet

struct SleepLogSheet: View {
    @Binding var hours: Double
    let onLog: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [Double] = [4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.indigo)
                    .padding(.top, 20)

                Text("How many hours did you sleep?")
                    .font(.headline)

                Picker("Sleep Hours", selection: $hours) {
                    ForEach(options, id: \.self) { h in
                        Text(String(format: "%.1fh", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)

                Button(action: {
                    onLog(hours)
                    dismiss()
                }) {
                    Text("Log \(String(format: "%.1f", hours)) Hours")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.indigo))
                        .foregroundColor(.white)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Log Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date

    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 50) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                } else {
                    // Render System responses with markdown formatting
                    Text(systemText(from: message.content))
                        .font(.body)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                        )
                        .textSelection(.enabled)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isUser { Spacer(minLength: 50) }
        }
        .padding(.horizontal)
    }

    /// Convert the model's raw text into an AttributedString with markdown rendered.
    private func systemText(from raw: String) -> AttributedString {
        // Trim leading whitespace per line and collapse excess blank lines
        let cleaned = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var opacity1: Double = 0.3
    @State private var opacity2: Double = 0.3
    @State private var opacity3: Double = 0.3

    var body: some View {
        HStack(spacing: 8) {
            dot(opacity: $opacity1, delay: 0)
            dot(opacity: $opacity2, delay: 0.2)
            dot(opacity: $opacity3, delay: 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(.gray.opacity(0.2)))
    }

    private func dot(opacity: Binding<Double>, delay: Double) -> some View {
        Circle()
            .fill(.cyan)
            .frame(width: 8, height: 8)
            .opacity(opacity.wrappedValue)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(delay)) {
                    opacity.wrappedValue = 1.0
                }
            }
    }
}

#Preview {
    CoachView()
        .preferredColorScheme(.dark)
}
