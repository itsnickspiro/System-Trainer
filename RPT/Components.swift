import Combine
import Foundation
import SwiftData
import SwiftUI

struct XPBar: View {
    var currentXP: Int
    var level: Int
    var threshold: Int

    var progress: Double { min(1.0, Double(currentXP) / Double(threshold)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(level)")
                    .font(.headline)
                Spacer()
                Text("XP: \(currentXP)/\(threshold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 14)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
    }
}

// NOTE: This is a legacy complex version of CurvedXPBar with more features
// The current app uses the simpler CurvedXPBar.swift version
// Keeping this here for reference/future use
struct CurvedXPBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let currentXP: Int
    let level: Int
    let threshold: Int
    let profileName: String
    var avatarKey: String? = nil
    var onSettingsTapped: (() -> Void)? = nil
    @State private var animatedProgress: Double = 0
    @State private var rotationAngle: Double = 0
    
    private var progress: Double { 
        min(1.0, Double(currentXP) / Double(threshold)) 
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background glow effect
                Circle()
                    .fill(RadialGradient(
                        colors: [.cyan.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 80,
                        endRadius: 120
                    ))
                    .frame(width: 200, height: 200)
                    .blur(radius: 8)
                
                // XP Ring - 3/4 circle (270 degrees)
                ZStack {
                    // Background track
                    CurvedProgressTrack()
                        .stroke(.gray.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 160, height: 160)
                    
                    // Outer glow ring
                    CurvedProgressTrack()
                        .stroke(.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 160, height: 160)
                        .blur(radius: 6)
                        .opacity(animatedProgress > 0.1 ? 1 : 0)
                    
                    // Progress ring with gradient
                    CurvedProgressTrack()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple, .pink, .cyan]),
                                center: .center,
                                startAngle: .degrees(135), // Start at bottom-left
                                endAngle: .degrees(45)     // End at top-right (270° span)
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .shadow(color: .cyan, radius: 4, x: 0, y: 0)
                    
                    // Progress indicator dot removed
                }
                
                // Central user avatar area
                ZStack {
                    // Avatar background with gradient
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue.opacity(0.9), .cyan.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 110, height: 110)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.8), lineWidth: 3)
                        )
                        .shadow(color: .cyan.opacity(0.8), radius: 15, x: 0, y: 0)
                    
                    // User avatar
                    VStack(spacing: 4) {
                        AvatarImageView(key: avatarKey ?? "avatar_default", size: 70)

                        Text(profileName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                
                // XP text at bottom
                VStack {
                    Spacer()
                    Text("\(currentXP) / \(threshold) XP")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.9))
                                .overlay(
                                    Capsule()
                                        .stroke(.cyan.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .padding(.bottom, 8)
                }
                .frame(width: 180, height: 180)
                
                // Floating particles for extra effect
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(.cyan.opacity(0.8))
                        .frame(width: 3, height: 3)
                        .offset(y: -90 + Double(index) * 5)
                        .rotationEffect(.degrees(Double(index) * 60 + rotationAngle))
                        .opacity(animatedProgress > 0.2 ? 0.8 : 0.3)
                }
            }
            .frame(width: 200, height: 200)
            
            VStack(spacing: 2) {
                Text("LVL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                Text("\(level)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.cyan)
                    .shadow(color: .cyan, radius: 3, x: 0, y: 0)
            }
        }
        .onAppear {
            // Animate the progress ring on appear
            withAnimation(.easeInOut(duration: 1.5)) {
                animatedProgress = progress
            }
            
            // Start particle rotation animation
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
        .onChange(of: progress) { _, newProgress in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = newProgress
            }
        }
    }
}

// Custom shape for 3/4 circle progress track
struct CurvedProgressTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        // Create a 3/4 circle (270 degrees) starting from bottom-left
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(135),  // Start at bottom-left (225° from standard 0°)
            endAngle: .degrees(45),     // End at top-right (45° from standard 0°)
            clockwise: false
        )
        
        return path
    }
}

struct RPGStatsBar: View {
    let profile: Profile
    @State private var selectedStat: StatType? = nil
    
    enum StatType: CaseIterable, Identifiable {
        case health, energy, strength, endurance, focus, discipline
        
        var id: String { 
            switch self {
            case .health: return "health"
            case .energy: return "energy"  
            case .strength: return "strength"
            case .endurance: return "endurance"
            case .focus: return "focus"
            case .discipline: return "discipline"
            }
        }
        
        var displayName: String {
            switch self {
            case .health: return "HEALTH"
            case .energy: return "ENERGY"
            case .strength: return "STRENGTH"
            case .endurance: return "ENDURANCE"
            case .focus: return "FOCUS"
            case .discipline: return "DISCIPLINE"
            }
        }
        
        var icon: String {
            switch self {
            case .health: return "cross.fill"
            case .energy: return "bolt.fill"
            case .strength: return "dumbbell"
            case .endurance: return "heart.fill"
            case .focus: return "brain"
            case .discipline: return "shield.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .health: return .red
            case .energy: return .yellow
            case .strength: return .orange
            case .endurance: return .blue
            case .focus: return .purple
            case .discipline: return .green
            }
        }
        
        func getValue(from profile: Profile) -> Double {
            switch self {
            case .health: return profile.health
            case .energy: return profile.energy
            case .strength: return profile.strength
            case .endurance: return profile.endurance
            case .focus: return profile.focus
            case .discipline: return profile.discipline
            }
        }
        
        var description: String {
            switch self {
            case .health: return "Affected by food, water, sleep, and overall wellness"
            case .energy: return "Your current vitality and alertness level"
            case .strength: return "Physical power improved through resistance training"
            case .endurance: return "Cardiovascular fitness from cardio workouts"
            case .focus: return "Mental clarity enhanced by meditation and study"
            case .discipline: return "Willpower built through consistent quest completion"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLAYER STATS")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                    Text("Core Attributes")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                
                // Overall power level
                VStack(alignment: .trailing, spacing: 4) {
                    let averageStat = StatType.allCases.map { $0.getValue(from: profile) }.reduce(0, +) / Double(StatType.allCases.count)
                    Text("\(Int(averageStat))")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.cyan)
                    Text("POWER")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Stats grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                ForEach(StatType.allCases, id: \.id) { stat in
                    StatCard(stat: stat, profile: profile, isSelected: selectedStat == stat) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedStat = selectedStat == stat ? nil : stat
                        }
                    }
                }
            }
            
            // Selected stat details
            if let selectedStat = selectedStat {
                StatDetailView(stat: selectedStat, profile: profile)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.cyan.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

struct StatCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let stat: RPGStatsBar.StatType
    let profile: Profile
    let isSelected: Bool
    let onTap: () -> Void
    var showLabel: Bool = true
    var compact: Bool = false
    var showValue: Bool = true
    
    private var value: Double { stat.getValue(from: profile) }
    private var normalizedValue: Double { value / 100.0 }
    
    var body: some View {
        if compact {
            HStack(spacing: 8) {
                Image(systemName: stat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(stat.color)
                    .frame(width: 20)

                // Progress bar inline with icon
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [stat.color.opacity(0.8), stat.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * normalizedValue)
                            .animation(.easeInOut(duration: 0.8), value: value)

                        if normalizedValue > 0.7 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stat.color.opacity(0.3))
                                .frame(width: geo.size.width * normalizedValue)
                                .blur(radius: 2)
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(8)
            // Remove card borders/background in compact mode
            .background(Color.clear)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: stat.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(stat.color)
                        .frame(width: 20)

                    Spacer()

                    if showValue {
                        Text("\(Int(value))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [stat.color.opacity(0.8), stat.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * normalizedValue)
                            .animation(.easeInOut(duration: 0.8), value: value)

                        if normalizedValue > 0.7 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stat.color.opacity(0.3))
                                .frame(width: geo.size.width * normalizedValue)
                                .blur(radius: 2)
                        }
                    }
                }
                .frame(height: 6)

                if showLabel {
                    Text(stat.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(stat.color.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? .black.opacity(0.2) : .white.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? stat.color : stat.color.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .overlay(
                        // Add subtle border for light mode
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? .clear : .gray.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(color: isSelected ? stat.color.opacity(0.5) : .clear, radius: 8, x: 0, y: 0)
        }
    }
}

struct StatDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let stat: RPGStatsBar.StatType
    let profile: Profile

    @State private var showSleepLog = false
    @State private var sleepHoursInput: Double = 7.5
    @State private var showMeditation = false

    private var value: Double { stat.getValue(from: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: stat.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(stat.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Current: \(Int(value))/100")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(stat.color.opacity(0.8))
                }

                Spacer()

                // Status indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Circle()
                        .fill(statusColor(for: value))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.5), lineWidth: 1)
                        )
                    Text(statusText(for: value))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Text(stat.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.gray)
                .lineLimit(nil)

            // Quick actions based on stat type
            quickActions(for: stat)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black.opacity(0.4) : .white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(stat.color.opacity(0.5), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showSleepLog) {
            SleepLogSheet(hours: $sleepHoursInput) { hours in
                profile.recordSleep(hours: hours)
            }
        }
        .sheet(isPresented: $showMeditation) {
            MeditationTimerSheet()
        }
    }

    private func statusColor(for value: Double) -> Color {
        switch value {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    private func statusText(for value: Double) -> String {
        switch value {
        case 80...: return "EXCELLENT"
        case 60..<80: return "GOOD"
        case 40..<60: return "FAIR"
        case 20..<40: return "POOR"
        default: return "CRITICAL"
        }
    }

    @ViewBuilder
    private func quickActions(for stat: RPGStatsBar.StatType) -> some View {
        HStack(spacing: 8) {
            switch stat {
            case .health:
                QuickActionButton(title: "Log Meal / Water", icon: "fork.knife", color: .green) {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .rptNavigateToTab,
                        object: nil,
                        userInfo: ["tab": "diet"]
                    )
                }
            case .energy:
                QuickActionButton(title: "Log Sleep", icon: "bed.double.fill", color: .purple) {
                    showSleepLog = true
                }
            case .strength:
                QuickActionButton(title: "Strength Training", icon: "dumbbell", color: .orange) {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .rptNavigateToTab,
                        object: nil,
                        userInfo: ["tab": "training"]
                    )
                }
            case .endurance:
                QuickActionButton(title: "Cardio", icon: "heart.fill", color: .red) {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .rptNavigateToTab,
                        object: nil,
                        userInfo: ["tab": "training"]
                    )
                }
            case .focus:
                QuickActionButton(title: "Meditate", icon: "brain", color: .purple) {
                    showMeditation = true
                }
            case .discipline:
                QuickActionButton(title: "View Quests", icon: "target", color: .green) {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .rptNavigateToTab,
                        object: nil,
                        userInfo: ["tab": "quests"]
                    )
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct WeekScroller: View {
    @Binding var selectedDay: Date

    private var weekDays: [Date] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -3, to: selectedDay.startOfDay())!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                let isToday = Calendar.current.isDate(day, inSameDayAs: Date())
                
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .black : .cyan.opacity(0.8))
                    
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .black : .white)
                    
                    // Today indicator
                    if isToday && !isSelected {
                        Circle()
                            .fill(.cyan)
                            .frame(width: 4, height: 4)
                    } else {
                        Circle()
                            .fill(.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.cyan)
                                .shadow(color: .cyan, radius: 8, x: 0, y: 0)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            isToday ? .cyan.opacity(0.8) : .gray.opacity(0.3), 
                                            lineWidth: isToday ? 2 : 1
                                        )
                                )
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedDay = day 
                    }
                }
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
        .padding(.horizontal)
    }
}

struct QuestRow: View {
    var quest: Quest
    var onToggle: (() -> Void)?
    var isLocked: Bool = false
    @State private var showingDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Status indicator with glow effect
            ZStack {
                Circle()
                    .fill(quest.type.color.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .blur(radius: 4)
                
                Circle()
                    .fill(quest.type.color)
                    .frame(width: 12, height: 12)
            }
            .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(quest.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(quest.type.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(quest.type.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(quest.type.color.opacity(0.2))
                                .overlay(
                                    Capsule()
                                        .stroke(quest.type.color.opacity(0.8), lineWidth: 1)
                                )
                        )
                }
                
                if !quest.details.isEmpty {
                    Text(quest.details)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                HStack {
                    if let due = quest.dueDate {
                        Label {
                            Text(due.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .foregroundColor(.orange)
                        .labelStyle(.titleAndIcon)
                    }
                    
                    Spacer()
                    
                    if quest.isUserCreated {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Text("Custom Quest")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                                Text("+\(quest.xpReward) XP")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.cyan)

                            if quest.creditReward > 0 {
                                Text("•")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Image(systemName: "centsign.circle.fill")
                                        .font(.system(size: 11))
                                    Text("+\(quest.creditReward) \(RemoteConfigService.shared.string("currency_symbol", default: "GP"))")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                            }
                        }
                    }
                }
            }
            
            // Action button
            Button(action: { if !isLocked { onToggle?() } }) {
                ZStack {
                    Circle()
                        .fill(quest.isCompleted ? .green.opacity(0.2) : isLocked ? .gray.opacity(0.05) : .gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(quest.isCompleted ? .green : .gray.opacity(isLocked ? 0.3 : 0.5), lineWidth: 2)
                        )

                    if quest.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    } else if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.5))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isLocked)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .stroke(.separator, lineWidth: 0.5)
        )
        .scaleEffect(quest.isCompleted ? 0.98 : 1.0)
        .opacity(quest.isCompleted ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: quest.isCompleted)
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .sheet(isPresented: $showingDetail) {
            QuestDetailSheet(quest: quest, onToggle: onToggle, isLocked: isLocked)
        }
    }
}

// MARK: - Quest Detail Sheet

struct QuestDetailSheet: View {
    let quest: Quest
    var onToggle: (() -> Void)?
    var isLocked: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status hero
                    ZStack {
                        LinearGradient(
                            colors: [quest.type.color.opacity(0.25), quest.type.color.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(quest.type.color.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                Image(systemName: quest.isCompleted ? "checkmark.seal.fill" : questTypeIcon(quest.type))
                                    .font(.system(size: 38))
                                    .foregroundColor(quest.isCompleted ? .green : quest.type.color)
                            }
                            .padding(.top, 28)

                            HStack(spacing: 8) {
                                Text(quest.type.displayName.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(quest.type.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(quest.type.color.opacity(0.15)))

                                if quest.isCompleted {
                                    Text("COMPLETED")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 0))

                    VStack(spacing: 20) {
                        // Details text
                        if !quest.details.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("OBJECTIVE", systemImage: "doc.text.fill")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(quest.details)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
                        }

                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            QuestStatCell(label: "XP REWARD", value: "+\(quest.xpReward) XP", icon: "bolt.fill", color: .cyan)

                            if quest.creditReward > 0 {
                                QuestStatCell(
                                    label: "\(RemoteConfigService.shared.string("currency_symbol", default: "GP")) REWARD",
                                    value: "+\(quest.creditReward) \(RemoteConfigService.shared.string("currency_symbol", default: "GP"))",
                                    icon: "centsign.circle.fill",
                                    color: Color(red: 1.0, green: 0.8, blue: 0.0)
                                )
                            }

                            if let stat = quest.statTarget, !stat.isEmpty {
                                QuestStatCell(label: "STAT BOOST", value: stat.capitalized, icon: "chart.bar.fill", color: quest.type.color)
                            }

                            if let due = quest.dueDate {
                                QuestStatCell(
                                    label: "DUE",
                                    value: due.formatted(date: .abbreviated, time: .omitted),
                                    icon: "clock.fill",
                                    color: .orange
                                )
                            }

                            if let condition = quest.completionCondition, !condition.isEmpty {
                                QuestStatCell(label: "VERIFIED BY", value: verificationLabel(condition), icon: "checkmark.shield.fill", color: .green)
                            }
                        }

                        // Complete / Uncomplete button
                        if isLocked {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 20))
                                Text("Locked — past day")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.gray.opacity(0.3))
                            )
                            .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                onToggle?()
                                dismiss()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: quest.isCompleted ? "arrow.uturn.left.circle.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                    Text(quest.isCompleted ? "Mark Incomplete" : "Complete Quest")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(quest.isCompleted ? Color.orange : Color.green)
                                )
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(quest.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func verificationLabel(_ condition: String) -> String {
        let parts = condition.split(separator: ":").map(String.init)
        switch parts.first {
        case "steps":    return "HealthKit Steps"
        case "calories": return "Active Calories"
        case "workout":  return "Workout Log"
        case "sleep":    return "HealthKit Sleep"
        default:         return "Manual"
        }
    }

    private func questTypeIcon(_ type: QuestType) -> String {
        switch type {
        case .oneTime: return "1.circle.fill"
        case .daily:   return "sun.max.fill"
        case .weekly:  return "calendar.badge.clock"
        case .custom:  return "star.fill"
        }
    }
}

struct QuestStatCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}

struct HealthMetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let target: String
    let progress: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.8))
            }
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text("/ \(target)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorScheme == .dark ? .black.opacity(0.3) : .gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? .black.opacity(0.2) : .white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}


struct StatInfluenceIndicator: View {
    let statName: String
    let influence: StatInfluence
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: influence.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(influence.color)
            
            Text(statName.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

struct CurvedStatRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double // 0...1
    let color: Color
    let icon: String
    var size: CGFloat = 72
    var lineWidth: CGFloat = 6
    var action: (() -> Void)? = nil

    @State private var animatedProgress: Double = 0

    var body: some View {
        Button(action: { action?() }) {
            ZStack {
                // Container box - adaptive background
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? .black.opacity(0.25) : .white.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? .clear : .gray.opacity(0.2), lineWidth: 1)
                    )

                // Background track
                CurvedProgressTrack()
                    .stroke(colorScheme == .dark ? .gray.opacity(0.25) : .gray.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size - 16, height: size - 16)

                // Progress ring
                CurvedProgressTrack()
                    .trim(from: 0, to: max(0, min(1, animatedProgress)))
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.8), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: size - 16, height: size - 16)
                    .shadow(color: color.opacity(0.6), radius: 3, x: 0, y: 0)

                // Center icon
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedProgress = newValue
            }
        }
        .accessibilityLabel(Text(icon))
    }
}

// MARK: - Meditation Timer Sheet

struct MeditationTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var secondsRemaining: Int = 0
    @State private var totalSeconds: Int = 300
    @State private var isRunning = false
    @State private var phase: MeditationPhase = .inhale
    @State private var breathProgress: Double = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let breathTicker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    enum MeditationPhase: String {
        case inhale = "Inhale"
        case hold   = "Hold"
        case exhale = "Exhale"

        var color: Color {
            switch self {
            case .inhale: return .cyan
            case .hold:   return .indigo
            case .exhale: return .purple
            }
        }

        static let phaseDuration: Double = 4.0
    }

    private let durations = [60, 120, 180, 300, 600]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Duration picker shown before session starts
                if !isRunning && secondsRemaining == 0 {
                    Picker("Duration", selection: $totalSeconds) {
                        ForEach(durations, id: \.self) { sec in
                            Text("\(sec / 60) min").tag(sec)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                // Breath guidance circle
                ZStack {
                    Circle()
                        .stroke(phase.color.opacity(0.15), lineWidth: 20)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: breathProgress)
                        .stroke(
                            LinearGradient(
                                colors: [phase.color, phase.color.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(.linear(duration: 0.05), value: breathProgress)

                    VStack(spacing: 4) {
                        Text(phase.rawValue)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(phase.color)
                        if isRunning || secondsRemaining > 0 {
                            Text(timeString(secondsRemaining))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack(spacing: 20) {
                    Button(action: toggleTimer) {
                        Label(isRunning ? "Pause" : "Start",
                              systemImage: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 120, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.indigo))
                            .foregroundColor(.white)
                    }

                    if secondsRemaining > 0 || isRunning {
                        Button(action: resetTimer) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 100, height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3)))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Meditate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(ticker) { _ in
                guard isRunning else { return }
                if secondsRemaining > 0 {
                    secondsRemaining -= 1
                } else {
                    isRunning = false
                }
            }
            .onReceive(breathTicker) { _ in
                guard isRunning else { return }
                let elapsed = Double(totalSeconds - secondsRemaining)
                let cycleDuration = MeditationPhase.phaseDuration * 3
                let posInCycle = elapsed.truncatingRemainder(dividingBy: cycleDuration)
                let d = MeditationPhase.phaseDuration
                if posInCycle < d {
                    phase = .inhale
                    breathProgress = posInCycle / d
                } else if posInCycle < d * 2 {
                    phase = .hold
                    breathProgress = (posInCycle - d) / d
                } else {
                    phase = .exhale
                    breathProgress = (posInCycle - d * 2) / d
                }
            }
        }
    }

    private func toggleTimer() {
        if secondsRemaining == 0 { secondsRemaining = totalSeconds }
        isRunning.toggle()
    }

    private func resetTimer() {
        isRunning = false
        secondsRemaining = 0
        breathProgress = 0
        phase = .inhale
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

