import SwiftUI

/// The cast of in-game NPCs that hand out daily quests. Each NPC is tied to a
/// stat-target archetype, has a portrait icon, an accent color, and rotating
/// dialogue lines that surface as the quest's "from" tagline.
///
/// All names are generic medieval-fantasy archetypes — zero IP risk.
enum QuestNPC: String, CaseIterable, Identifiable {
    case guildMaster   = "Guild Master"
    case villageLeader = "Village Leader"
    case blacksmith    = "Blacksmith"
    case alchemist     = "Alchemist"
    case sage          = "Sage"
    case captain       = "Captain"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// SF Symbol used as a portrait. Chosen for tonal fit, not realism.
    var icon: String {
        switch self {
        case .guildMaster:   return "shield.lefthalf.filled"
        case .villageLeader: return "house.fill"
        case .blacksmith:    return "hammer.fill"
        case .alchemist:     return "flask.fill"
        case .sage:          return "brain.head.profile"
        case .captain:       return "binoculars.fill"
        }
    }

    var color: Color {
        switch self {
        case .guildMaster:   return .yellow
        case .villageLeader: return .orange
        case .blacksmith:    return .red
        case .alchemist:     return .green
        case .sage:          return .purple
        case .captain:       return .cyan
        }
    }

    /// Short tagline shown on the quest row, e.g. "FROM THE BLACKSMITH".
    var tagline: String { "FROM THE \(rawValue.uppercased())" }

    /// Rotating dialogue lines. Picked deterministically based on the quest
    /// title hash so the same quest always shows the same line, but different
    /// quests show variety. Used in quest detail sheets, not the row itself.
    var dialogueLines: [String] {
        switch self {
        case .guildMaster:
            return [
                "Discipline is the foundation of every adventurer. Prove yours.",
                "The Guild expects nothing less than your full effort today.",
                "Another day, another quest. The Guild does not rest, and neither should you."
            ]
        case .villageLeader:
            return [
                "The village still believes in you. Don't let them down.",
                "We've prepared what we can. The rest is up to your will.",
                "Take this task to heart. Our future depends on adventurers like you."
            ]
        case .blacksmith:
            return [
                "Steel sharpens steel — and iron is forged through fire. Get to work.",
                "I've seen weaker hands than yours move mountains. Time to prove me right.",
                "No shortcut to strength, traveler. Only the grind."
            ]
        case .alchemist:
            return [
                "What you eat becomes what you are. Choose wisely.",
                "The body is a vessel — fill it with the right ingredients.",
                "I've prepared a formula. Follow it and your stats will rise."
            ]
        case .sage:
            return [
                "The mind must be tempered as carefully as the body.",
                "Wisdom is gathered, not granted. Seek it today.",
                "Your focus is dim. A quiet hour will return your edge."
            ]
        case .captain:
            return [
                "The patrol leaves at dawn. Be ready or be left behind.",
                "I need scouts who can run all day. Show me your endurance.",
                "Distance separates the strong from the willing. Cover ground today."
            ]
        }
    }

    /// Pick a deterministic dialogue line for a given quest title — same
    /// title always returns the same line, so the player sees consistency.
    func dialogue(for questTitle: String) -> String {
        let lines = dialogueLines
        guard !lines.isEmpty else { return "" }
        let hash = abs(questTitle.hashValue)
        return lines[hash % lines.count]
    }
}

/// Maps a Quest to the NPC most likely to have given it, based on the
/// quest's stat target, completion condition, and title keywords. The
/// mapping is heuristic — it's flavor, not gameplay.
extension Quest {
    var suggestedNPC: QuestNPC {
        // Title keywords win first — they're the most specific signal.
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("custom plan") || lowerTitle.contains("survey") {
            return .villageLeader
        }
        if lowerTitle.contains("rehabilitation") || lowerTitle.contains("recovery") {
            return .alchemist
        }
        if lowerTitle.contains("nutrition") || lowerTitle.contains("meal") || lowerTitle.contains("water") || lowerTitle.contains("hydrat") {
            return .alchemist
        }
        if lowerTitle.contains("meditat") || lowerTitle.contains("focus") || lowerTitle.contains("cognitive") || lowerTitle.contains("mind") {
            return .sage
        }
        if lowerTitle.contains("step") || lowerTitle.contains("walk") || lowerTitle.contains("patrol") || lowerTitle.contains("cardio") || lowerTitle.contains("run") {
            return .captain
        }
        if lowerTitle.contains("training") || lowerTitle.contains("push") || lowerTitle.contains("pull") || lowerTitle.contains("legs") || lowerTitle.contains("workout") || lowerTitle.contains("strength") {
            return .blacksmith
        }
        if lowerTitle.contains("discipline") || lowerTitle.contains("daily check") || lowerTitle.contains("streak") {
            return .guildMaster
        }

        // Fall back to statTarget mapping.
        switch (statTarget ?? "").lowercased() {
        case "strength":   return .blacksmith
        case "endurance":  return .captain
        case "health":     return .alchemist
        case "energy":     return .alchemist
        case "focus":      return .sage
        case "discipline": return .guildMaster
        default:           return .villageLeader
        }
    }
}
