import SwiftUI

struct CoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var userInput = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Welcome message
                            if messages.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 64))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.cyan, .blue],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    Text("Your AI Fitness Coach")
                                        .font(.title.bold())
                                    
                                    Text("Ask me anything about your fitness journey, nutrition, workouts, or get personalized advice based on your progress.")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Try asking:")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        
                                        suggestedQuestion("How can I improve my streak?")
                                        suggestedQuestion("What should I eat for better energy?")
                                        suggestedQuestion("Create a workout plan for me")
                                        suggestedQuestion("How do I level up faster?")
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1))
                                    )
                                }
                                .padding()
                                .padding(.top, 40)
                            } else {
                                ForEach(messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            
                            // Typing indicator
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
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack(spacing: 12) {
                        TextField("Ask your coach...", text: $userInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.1))
                            )
                            .lineLimit(1...5)
                        
                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                        AnyShapeStyle(.gray) : 
                                        AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                        }
                        .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white)
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color(.systemGroupedBackground))
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func suggestedQuestion(_ text: String) -> some View {
        Button {
            userInput = text
            sendMessage()
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
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
    
    private func sendMessage() {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(content: trimmedInput, isUser: true)
        messages.append(userMessage)
        userInput = ""
        
        // Show typing indicator
        isTyping = true
        
        // Simulate AI response (replace with actual API call later)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTyping = false
            
            let response = generateResponse(for: trimmedInput)
            let aiMessage = ChatMessage(content: response, isUser: false)
            messages.append(aiMessage)
        }
    }
    
    private func generateResponse(for input: String) -> String {
        let lowercased = input.lowercased()
        
        // Simple keyword-based responses (replace with actual AI later)
        if lowercased.contains("streak") {
            return "Great question! To improve your streak, focus on consistency over intensity. Complete at least one quest every day, even if it's small. Your current streak shows your discipline stat, which unlocks bonus XP multipliers as it grows!"
        } else if lowercased.contains("energy") || lowercased.contains("eat") {
            return "For better energy levels, focus on: 1) Complex carbs like whole grains, 2) Lean proteins, 3) Healthy fats from nuts and avocados, 4) Stay hydrated with 8+ glasses of water, 5) Eat every 3-4 hours to maintain stable blood sugar."
        } else if lowercased.contains("workout") || lowercased.contains("exercise") {
            return "I can help you create a personalized workout plan! For beginners, I recommend: 3x per week strength training (30 mins), 2x per week cardio (20-30 mins), and daily stretching (10 mins). This builds your Strength and Endurance stats while improving Health. Want me to break this down by day?"
        } else if lowercased.contains("level") || lowercased.contains("xp") {
            return "To level up faster: 1) Complete all daily quests (major XP), 2) Hit your health goals (steps, calories, sleep) for bonus XP, 3) Maintain your streak for multipliers, 4) Log healthy meals, and 5) Try new recipes. Each level requires more XP but unlocks better rewards!"
        } else if lowercased.contains("sleep") {
            return "Sleep is crucial for your Energy and Focus stats! Aim for 7-9 hours per night. Tips: Set a consistent bedtime, avoid screens 1 hour before bed, keep your room cool (65-68°F), and try relaxation techniques. Your sleep efficiency currently affects XP gains!"
        } else if lowercased.contains("water") || lowercased.contains("hydration") {
            return "Hydration is essential! Aim for 8 glasses (64oz) daily, more if you exercise. Water boosts your Health and Energy stats. Try: drinking a glass when you wake up, keeping water visible, and setting hourly reminders. Track it in the Diet tab!"
        } else {
            return "That's a great question! I'm here to help you optimize your fitness journey. Based on your profile, I can provide personalized advice on nutrition, workouts, recovery, and achieving your goals. What specific aspect would you like to focus on?"
        }
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
                Text(message.content)
                    .font(.body)
                    .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .white : .black))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.isUser ? 
                                  AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                                  AnyShapeStyle(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                            )
                    )
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !message.isUser { Spacer(minLength: 50) }
        }
        .padding(.horizontal)
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var opacity1: Double = 0.3
    @State private var opacity2: Double = 0.3
    @State private var opacity3: Double = 0.3
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
                .opacity(opacity1)
            
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
                .opacity(opacity2)
            
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
                .opacity(opacity3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.gray.opacity(0.2))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                opacity1 = 1.0
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(0.2)) {
                opacity2 = 1.0
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(0.4)) {
                opacity3 = 1.0
            }
        }
    }
}

#Preview {
    CoachView()
        .preferredColorScheme(.dark)
}
