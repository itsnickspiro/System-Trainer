import Foundation
import SwiftUI

struct Exercise: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: String?
    let muscle: String?
    let equipment: String?
    let difficulty: String?
    let instructions: String?

    init(id: UUID = UUID(), name: String, type: String?, muscle: String?, equipment: String?, difficulty: String?, instructions: String?) {
        self.id = id
        self.name = name
        self.type = type
        self.muscle = muscle
        self.equipment = equipment
        self.difficulty = difficulty
        self.instructions = instructions
    }

    enum CodingKeys: String, CodingKey {
        case id // allow encoding/decoding id when present
        case name, type, muscle, equipment, difficulty, instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // If the payload includes an id, use it; otherwise generate one
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.muscle = try container.decodeIfPresent(String.self, forKey: .muscle)
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
        try container.encodeIfPresent(equipment, forKey: .equipment)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encodeIfPresent(instructions, forKey: .instructions)
    }
}

final class ExercisesAPI {
    static let shared = ExercisesAPI()
    private init() {}

    enum APIError: Error { case missingAPIKey, badURL, requestFailed, decodingFailed, http(Int) }

    func fetchExercises(muscle: String? = nil, type: String? = nil, name: String? = nil, limit: Int = 20) async throws -> [Exercise] {
        let apiKey = Secrets.apiNinjasKey
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        var comps = URLComponents(string: "https://api.api-ninjas.com/v1/exercises")
        var items: [URLQueryItem] = []
        if let muscle, !muscle.isEmpty { items.append(URLQueryItem(name: "muscle", value: muscle)) }
        if let type, !type.isEmpty { items.append(URLQueryItem(name: "type", value: type)) }
        if let name, !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
        comps?.queryItems = items.isEmpty ? nil : items
        guard let url = comps?.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.timeoutInterval = 20

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
                let equipment = dict["equipment"] as? String
                let difficulty = dict["difficulty"] as? String
                let instructions = dict["instructions"] as? String
                return Exercise(name: name, type: type, muscle: muscle, equipment: equipment, difficulty: difficulty, instructions: instructions)
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
