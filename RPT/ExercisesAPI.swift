import Foundation
import SwiftUI

// MARK: - Exercise Model

struct Exercise: Identifiable, Codable, Equatable {
    let id: UUID

    // Core fields (returned by both old and new API shape)
    let name: String
    let type: String?           // backwards-compat alias for category
    let muscle: String?         // first entry from primaryMuscles
    let secondaryMuscle: String? // first entry from secondaryMuscles
    let equipment: String?
    let difficulty: String?     // backwards-compat alias for level
    let instructions: String?   // newline-joined steps for backwards compat

    // Extended fields from Supabase exercises table
    let slug: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let force: String?       // push | pull | static
    let level: String?       // beginner | intermediate | expert
    let mechanic: String?    // compound | isolation
    let category: String?    // strength | cardio | stretching | plyometrics
    let instructionSteps: [String]  // ordered steps array
    let tips: String?
    let imageUrls: [String]
    let gifUrl: String?
    let youtubeSearchUrl: String?

    init(
        id: UUID = UUID(),
        name: String,
        type: String?,
        muscle: String?,
        secondaryMuscle: String? = nil,
        equipment: String?,
        difficulty: String?,
        instructions: String?,
        slug: String? = nil,
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        force: String? = nil,
        level: String? = nil,
        mechanic: String? = nil,
        category: String? = nil,
        instructionSteps: [String] = [],
        tips: String? = nil,
        imageUrls: [String] = [],
        gifUrl: String? = nil,
        youtubeSearchUrl: String? = nil
    ) {
        self.id               = id
        self.name             = name
        self.type             = type
        self.muscle           = muscle
        self.secondaryMuscle  = secondaryMuscle
        self.equipment        = equipment
        self.difficulty       = difficulty
        self.instructions     = instructions
        self.slug             = slug
        self.primaryMuscles   = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.force            = force
        self.level            = level
        self.mechanic         = mechanic
        self.category         = category
        self.instructionSteps = instructionSteps
        self.tips             = tips
        self.imageUrls        = imageUrls
        self.gifUrl           = gifUrl
        self.youtubeSearchUrl = youtubeSearchUrl
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, type, muscle, secondaryMuscle, equipment, difficulty, instructions
        case slug
        case primaryMuscles, secondaryMuscles
        case force, level, mechanic, category
        case instructionSteps, tips
        case imageUrls, gifUrl, youtubeSearchUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id               = try c.decodeIfPresent(UUID.self,   forKey: .id)              ?? UUID()
        self.name             = try c.decode(String.self,           forKey: .name)
        self.type             = try c.decodeIfPresent(String.self,  forKey: .type)
        self.muscle           = try c.decodeIfPresent(String.self,  forKey: .muscle)
        self.secondaryMuscle  = try c.decodeIfPresent(String.self,  forKey: .secondaryMuscle)
        self.equipment        = try c.decodeIfPresent(String.self,  forKey: .equipment)
        self.difficulty       = try c.decodeIfPresent(String.self,  forKey: .difficulty)
        self.instructions     = try c.decodeIfPresent(String.self,  forKey: .instructions)
        self.slug             = try c.decodeIfPresent(String.self,  forKey: .slug)
        self.primaryMuscles   = try c.decodeIfPresent([String].self, forKey: .primaryMuscles)   ?? []
        self.secondaryMuscles = try c.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        self.force            = try c.decodeIfPresent(String.self,  forKey: .force)
        self.level            = try c.decodeIfPresent(String.self,  forKey: .level)
        self.mechanic         = try c.decodeIfPresent(String.self,  forKey: .mechanic)
        self.category         = try c.decodeIfPresent(String.self,  forKey: .category)
        self.instructionSteps = try c.decodeIfPresent([String].self, forKey: .instructionSteps) ?? []
        self.tips             = try c.decodeIfPresent(String.self,  forKey: .tips)
        self.imageUrls        = try c.decodeIfPresent([String].self, forKey: .imageUrls)  ?? []
        self.gifUrl           = try c.decodeIfPresent(String.self,  forKey: .gifUrl)
        self.youtubeSearchUrl = try c.decodeIfPresent(String.self,  forKey: .youtubeSearchUrl)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                           forKey: .id)
        try c.encode(name,                         forKey: .name)
        try c.encodeIfPresent(type,                forKey: .type)
        try c.encodeIfPresent(muscle,              forKey: .muscle)
        try c.encodeIfPresent(secondaryMuscle,     forKey: .secondaryMuscle)
        try c.encodeIfPresent(equipment,           forKey: .equipment)
        try c.encodeIfPresent(difficulty,          forKey: .difficulty)
        try c.encodeIfPresent(instructions,        forKey: .instructions)
        try c.encodeIfPresent(slug,                forKey: .slug)
        try c.encode(primaryMuscles,               forKey: .primaryMuscles)
        try c.encode(secondaryMuscles,             forKey: .secondaryMuscles)
        try c.encodeIfPresent(force,               forKey: .force)
        try c.encodeIfPresent(level,               forKey: .level)
        try c.encodeIfPresent(mechanic,            forKey: .mechanic)
        try c.encodeIfPresent(category,            forKey: .category)
        try c.encode(instructionSteps,             forKey: .instructionSteps)
        try c.encodeIfPresent(tips,                forKey: .tips)
        try c.encode(imageUrls,                    forKey: .imageUrls)
        try c.encodeIfPresent(gifUrl,              forKey: .gifUrl)
        try c.encodeIfPresent(youtubeSearchUrl,    forKey: .youtubeSearchUrl)
    }

    // MARK: - Derived helpers

    /// Effective primary muscle: prefers populated primaryMuscles array, falls back to legacy field
    var effectiveMuscle: String? {
        primaryMuscles.first ?? muscle
    }

    /// All muscles (primary + secondary) deduplicated
    var allMuscles: [String] {
        let combined = primaryMuscles + secondaryMuscles
        if combined.isEmpty, let m = muscle { return [m] }
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    /// Icon that represents the primary muscle group
    var muscleIcon: String {
        switch (primaryMuscles.first ?? muscle)?.lowercased() {
        case "chest":                               return "figure.arms.open"
        case "back", "lats", "traps",
             "middle back", "lower back":           return "figure.strengthtraining.traditional"
        case "shoulders", "deltoids":               return "figure.boxing"
        case "biceps", "triceps", "forearms":       return "figure.strengthtraining.functional"
        case "legs", "quadriceps", "hamstrings",
             "glutes", "calves", "adductors",
             "abductors", "hip flexors":            return "figure.run"
        case "abdominals", "abs", "core":           return "figure.core.training"
        case "cardio":                              return "heart.fill"
        default:                                    return "figure.mixed.cardio"
        }
    }

    /// Difficulty colour for UI tinting
    var difficultyColor: Color {
        switch (level ?? difficulty)?.lowercased() {
        case "beginner":     return .green
        case "intermediate": return .orange
        case "expert":       return .red
        default:             return .secondary
        }
    }

    /// Numbered step breakdown.
    /// Prefers the instructionSteps array; falls back to parsing the instructions string.
    var parsedInstructionSteps: [String] {
        if !instructionSteps.isEmpty { return instructionSteps }
        guard let raw = instructions, !raw.isEmpty else { return [] }
        let lines = raw.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        let dotSplit = raw.components(separatedBy: ". ").filter { !$0.isEmpty }
        if dotSplit.count > 2 { return dotSplit.map { $0.hasSuffix(".") ? $0 : $0 + "." } }
        return [raw]
    }

    /// Prefer parsedInstructionSteps for all callers (replaces old instructionSteps property)
    var instructionStepsDisplay: [String] { parsedInstructionSteps }

    /// First available exercise image URL
    var previewImageUrl: URL? {
        imageUrls.first.flatMap { URL(string: $0) }
    }

    /// GIF URL as a Foundation URL
    var gifURL: URL? {
        gifUrl.flatMap { URL(string: $0) }
    }

    /// YouTube search URL as Foundation URL
    var youtubeURL: URL? {
        youtubeSearchUrl.flatMap { URL(string: $0) }
    }
}

// MARK: - API Client

final class ExercisesAPI {
    static let shared = ExercisesAPI()
    private init() {}

    enum APIError: Error { case badURL, requestFailed, decodingFailed, http(Int) }

    func fetchExercises(
        muscle: String?     = nil,
        type: String?       = nil,
        name: String?       = nil,
        difficulty: String? = nil,
        offset: Int?        = nil,
        limit: Int          = 30
    ) async throws -> [Exercise] {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/exercises-proxy") else {
            throw APIError.badURL
        }

        var body: [String: String] = [:]
        if let muscle, !muscle.isEmpty         { body["muscle"]     = muscle }
        if let type,   !type.isEmpty           { body["type"]       = type }
        if let name,   !name.isEmpty           { body["query"]      = name }
        if let difficulty, !difficulty.isEmpty { body["level"]      = difficulty }
        if let offset                          { body["offset"]     = String(offset) }
        body["limit"] = String(limit)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",          forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret,           forHTTPHeaderField: "X-App-Secret")
        req.timeoutInterval = 20
        req.httpBody = try? JSONEncoder().encode(body)

        let (data, resp) = try await PinnedURLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.http(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([Exercise].self, from: data)
        } catch {
            // Fallback: try the old manual mapping approach
            let raw = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            return raw.compactMap { dict in
                let name = dict["name"] as? String ?? "Unknown"
                return Exercise(
                    name:          name,
                    type:          dict["type"]            as? String,
                    muscle:        dict["muscle"]          as? String,
                    secondaryMuscle: dict["secondaryMuscle"] as? String,
                    equipment:     dict["equipment"]       as? String,
                    difficulty:    dict["difficulty"]      as? String,
                    instructions:  dict["instructions"]    as? String,
                    primaryMuscles:   dict["primaryMuscles"]   as? [String] ?? [],
                    secondaryMuscles: dict["secondaryMuscles"] as? [String] ?? [],
                    force:         dict["force"]           as? String,
                    level:         dict["level"]           as? String,
                    mechanic:      dict["mechanic"]        as? String,
                    category:      dict["category"]        as? String,
                    instructionSteps: dict["instructionSteps"] as? [String] ?? [],
                    tips:          dict["tips"]            as? String,
                    imageUrls:     dict["imageUrls"]       as? [String] ?? [],
                    gifUrl:        dict["gifUrl"]          as? String,
                    youtubeSearchUrl: dict["youtubeSearchUrl"] as? String
                )
            }
        }
    }
}

// MARK: - Minimal list view (used by search results screen)

struct ExerciseResultsView: View {
    let exercises: [Exercise]

    var body: some View {
        List(exercises) { ex in
            VStack(alignment: .leading, spacing: 6) {
                Text(ex.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let muscle = ex.effectiveMuscle { Tag(text: muscle.capitalized, color: .blue) }
                    if let type   = ex.type             { Tag(text: type.capitalized,   color: .orange) }
                    if let diff   = ex.difficulty       { Tag(text: diff.capitalized,   color: .purple) }
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

// MARK: - Tag chip (shared UI primitive)

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
