import SwiftUI

struct CoachView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataManager = DataManager.shared
    private var ai: AIManager { AIManager.shared }
    @State private var userInput = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false

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
                    .padding(.vertical, 12)
                }
                .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white)
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color(.systemGroupedBackground))
            .navigationTitle("THE SYSTEM")
            .navigationBarTitleDisplayMode(.inline)

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

            Text("Player data is being monitored. Submit your query.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("SUGGESTED QUERIES")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                suggestedQuestion("Analyze my current stats")
                suggestedQuestion("How do I increase my Endurance?")
                suggestedQuestion("What should I focus on today?")
                suggestedQuestion("Explain my XP progress")
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

    // MARK: - Send

    private func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(content: trimmed, isUser: true))
        userInput = ""
        isTyping = true

        let context = buildPlayerContext()

        Task {
            do {
                let reply = try await ai.chat(message: trimmed, context: context)
                isTyping = false
                messages.append(ChatMessage(content: reply, isUser: false))
            } catch AIManagerError.unavailable {
                isTyping = false
                messages.append(ChatMessage(
                    content: "SYSTEM OFFLINE. Apple Intelligence must be enabled in iOS Settings > Apple Intelligence & Siri.",
                    isUser: false
                ))
            } catch {
                isTyping = false
                messages.append(ChatMessage(
                    content: "SYSTEM ERROR: \(error.localizedDescription)",
                    isUser: false
                ))
            }
        }
    }

    /// Serialise the current player profile into a compact JSON string for context injection.
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
                "resting_heart_rate": profile.restingHeartRate
            ]
        ]
        return (try? String(data: JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted), encoding: .utf8)) ?? ""
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
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
