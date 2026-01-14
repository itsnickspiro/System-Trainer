import SwiftUI
import SwiftUI
import SwiftData
import Foundation

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
                    
                    // Progress indicator dot
                    if animatedProgress > 0 {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .cyan, radius: 6, x: 0, y: 0)
                            .offset(y: -80) // Radius of the progress ring
                            .rotationEffect(.degrees(135 + (animatedProgress * 270))) // Follow the progress
                    }
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
                    
                    // User avatar (placeholder - can be replaced with actual image)
                    VStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                        
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
    let stat: RPGStatsBar.StatType
    let profile: Profile
    
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
                QuickActionButton(title: "Log Meal", icon: "fork.knife", color: .green) {
                    // TODO: Open meal logging
                }
                QuickActionButton(title: "Drink Water", icon: "drop.fill", color: .blue) {
                    profile.recordWaterIntake()
                }
            case .energy:
                QuickActionButton(title: "Log Sleep", icon: "bed.double.fill", color: .purple) {
                    // TODO: Open sleep logging
                }
            case .strength:
                QuickActionButton(title: "Strength Training", icon: "dumbbell", color: .orange) {
                    // TODO: Open workout logging
                }
            case .endurance:
                QuickActionButton(title: "Cardio", icon: "heart.fill", color: .red) {
                    // TODO: Open cardio logging
                }
            case .focus:
                QuickActionButton(title: "Meditate", icon: "brain", color: .purple) {
                    // TODO: Open meditation timer
                }
            case .discipline:
                QuickActionButton(title: "View Quests", icon: "target", color: .green) {
                    // TODO: Navigate to quests
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
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("+\(quest.xpReward)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.cyan)
                }
            }
            
            // Action button
            Button(action: { onToggle?() }) {
                ZStack {
                    Circle()
                        .fill(quest.isCompleted ? .green.opacity(0.2) : .gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(quest.isCompleted ? .green : .gray.opacity(0.5), lineWidth: 2)
                        )
                    
                    if quest.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            quest.isCompleted ? 
                                .green.opacity(0.5) : 
                                quest.type.color.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(quest.isCompleted ? 0.98 : 1.0)
        .opacity(quest.isCompleted ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: quest.isCompleted)
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

