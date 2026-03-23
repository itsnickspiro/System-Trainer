import Foundation
import SwiftUI

struct Exercise: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: String?
    let muscle: String?
    let secondaryMuscle: String?
    let equipment: String?
    let difficulty: String?
    let instructions: String?

    init(id: UUID = UUID(), name: String, type: String?, muscle: String?,
         secondaryMuscle: String? = nil, equipment: String?,
         difficulty: String?, instructions: String?) {
        self.id = id
        self.name = name
        self.type = type
        self.muscle = muscle
        self.secondaryMuscle = secondaryMuscle
        self.equipment = equipment
        self.difficulty = difficulty
        self.instructions = instructions
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name, type, muscle, secondaryMuscle, equipment, difficulty, instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.muscle = try container.decodeIfPresent(String.self, forKey: .muscle)
        self.secondaryMuscle = try container.decodeIfPresent(String.self, forKey: .secondaryMuscle)
        self.equipment = try container.decodeIfPresent(String.self, forKey: .equipment)
        self.difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
        self.instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(muscle, forKey: .muscle)
        try container.encodeIfPresent(secondaryMuscle, forKey: .secondaryMuscle)
        try container.encodeIfPresent(equipment, forKey: .equipment)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encodeIfPresent(instructions, forKey: .instructions)
    }

    // MARK: - Derived helpers

    /// Icon that represents the primary muscle group
    var muscleIcon: String {
        switch muscle?.lowercased() {
        case "chest":                    return "figure.arms.open"
        case "back", "lats", "traps":   return "figure.strengthtraining.traditional"
        case "shoulders", "deltoids":   return "figure.boxing"
        case "biceps", "triceps", "forearms": return "figure.strengthtraining.functional"
        case "legs", "quadriceps", "hamstrings", "glutes", "calves": return "figure.run"
        case "abdominals", "abs", "core": return "figure.core.training"
        case "cardio":                  return "heart.fill"
        default:                        return "figure.mixed.cardio"
        }
    }

    /// Difficulty colour for UI tinting
    var difficultyColor: Color {
        switch difficulty?.lowercased() {
        case "beginner":   return .green
        case "intermediate": return .orange
        case "expert":     return .red
        default:           return .secondary
        }
    }

    /// Numbered step breakdown parsed from the instructions string.
    /// Falls back to the full string as one step if no numbering found.
    var instructionSteps: [String] {
        guard let raw = instructions, !raw.isEmpty else { return [] }
        // Try splitting on numbered patterns like "1." "1)" or newlines
        let lines = raw.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        // Try splitting on period+space patterns used by the API
        let dotSplit = raw.components(separatedBy: ". ").filter { !$0.isEmpty }
        if dotSplit.count > 2 { return dotSplit.map { $0.hasSuffix(".") ? $0 : $0 + "." } }
        return [raw]
    }
}

final class ExercisesAPI {
    static let shared = ExercisesAPI()
    private init() {}

    enum APIError: Error { case badURL, requestFailed, decodingFailed, http(Int) }

    func fetchExercises(muscle: String? = nil, type: String? = nil, name: String? = nil, difficulty: String? = nil, offset: Int? = nil, limit: Int = 20) async throws -> [Exercise] {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/exercises-proxy") else {
            throw APIError.badURL
        }

        var body: [String: String] = [:]
        if let muscle, !muscle.isEmpty         { body["muscle"] = muscle }
        if let type, !type.isEmpty             { body["type"] = type }
        if let name, !name.isEmpty             { body["name"] = name }
        if let difficulty, !difficulty.isEmpty { body["difficulty"] = difficulty }
        if let offset                          { body["offset"] = String(offset) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.timeoutInterval = 20
        req.httpBody = try? JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.http(http.statusCode)
        }
        do {
            // API returns an array of objects without id; map to Exercise with generated UUIDs
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let mapped: [Exercise] = raw.compactMap { dict in
                let name = dict["name"] as? String ?? "Unknown"
                let type = dict["type"] as? String
                let muscle = dict["muscle"] as? String
                let secondaryMuscle = dict["secondaryMuscle"] as? String
                let equipment = dict["equipment"] as? String
                let difficulty = dict["difficulty"] as? String
                let instructions = dict["instructions"] as? String
                return Exercise(name: name, type: type, muscle: muscle,
                                secondaryMuscle: secondaryMuscle, equipment: equipment,
                                difficulty: difficulty, instructions: instructions)
            }
            return Array(mapped.prefix(limit))
        } catch {
            throw APIError.decodingFailed
        }
    }
}

struct ExerciseResultsView: View {
    let exercises: [Exercise]

    var body: some View {
        List(exercises) { ex in
            VStack(alignment: .leading, spacing: 6) {
                Text(ex.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let muscle = ex.muscle { Tag(text: muscle.capitalized, color: .blue) }
                    if let type = ex.type { Tag(text: type.capitalized, color: .orange) }
                    if let difficulty = ex.difficulty { Tag(text: difficulty.capitalized, color: .purple) }
                }
                if let instructions = ex.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
            )
    }
}
