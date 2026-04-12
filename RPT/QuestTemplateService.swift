import Combine
import Foundation

// MARK: - QuestTemplateService
//
// Fetches rows from the `quest_templates` and `quest_arcs` Supabase tables via
// the quest-templates-proxy Edge Function.
//
// Results are cached to disk (JSON) so the last-known set is available
// immediately on next launch even before the network fetch completes.
//
// Usage:
//   await QuestTemplateService.shared.refresh()
//   let templates = QuestTemplateService.shared.templates
//   let arcs      = QuestTemplateService.shared.arcs

@MainActor
final class QuestTemplateService: ObservableObject {

    static let shared = QuestTemplateService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    private(set) var templates: [QuestTemplate] = []
    private(set) var arcs: [QuestArc] = []

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/quest-templates-proxy"
    private static let templatesCacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("quest_templates_cache.json")
    }()
    private static let arcsCacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("quest_arcs_cache.json")
    }()

    private init() {
        // Start empty; load disk caches off-main to keep init() fast on cold launch.
        templates = []
        arcs = []
        Task.detached(priority: .utility) { [weak self] in
            let templatesURL = await Self.templatesCacheURL
            let arcsURL = await Self.arcsCacheURL
            let decodedTemplates: [QuestTemplate] = {
                guard let data = try? Data(contentsOf: templatesURL) else { return [] }
                return (try? JSONDecoder().decode([QuestTemplate].self, from: data)) ?? []
            }()
            let decodedArcs: [QuestArc] = {
                guard let data = try? Data(contentsOf: arcsURL) else { return [] }
                return (try? JSONDecoder().decode([QuestArc].self, from: data)) ?? []
            }()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !decodedTemplates.isEmpty { self.templates = decodedTemplates }
                if !decodedArcs.isEmpty { self.arcs = decodedArcs }
            }
        }
    }

    // MARK: - Public Accessors

    /// Templates filtered by arc key (nil = all templates)
    func templates(for arcKey: String? = nil) -> [QuestTemplate] {
        guard let arcKey else { return templates }
        return templates.filter { $0.requiresArc == arcKey }
    }

    /// Look up a template by its stable key
    func template(key: String) -> QuestTemplate? {
        templates.first { $0.key == key }
    }

    // MARK: - Refresh

    /// Fetches fresh templates and arcs from Supabase. Safe to call on every launch.
    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let (fetchedTemplates, fetchedArcs) = try await fetchFromSupabase()

            if !fetchedTemplates.isEmpty {
                templates = fetchedTemplates
                try? JSONEncoder().encode(fetchedTemplates).write(to: Self.templatesCacheURL, options: .atomic)
            }
            if !fetchedArcs.isEmpty {
                arcs = fetchedArcs
                try? JSONEncoder().encode(fetchedArcs).write(to: Self.arcsCacheURL, options: .atomic)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Network

    private func fetchFromSupabase() async throws -> ([QuestTemplate], [QuestArc]) {
        guard let url = URL(string: Self.proxyURL) else { return ([], []) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 15

        let (data, response) = try await PinnedURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return ([], []) }

        let payload = try JSONDecoder().decode(QuestTemplatesPayload.self, from: data)
        return (payload.templates, payload.arcs)
    }
}

// MARK: - Public Models

struct QuestTemplate: Codable, Identifiable {
    var id: String { key }

    let key: String
    let title: String
    let subtitle: String?
    let category: String
    let questType: String
    let conditionType: String?
    let conditionTarget: Double?
    let xpReward: Int
    let bonusXpReward: Int?
    let requiresArc: String?
    let arcDay: Int?
}

struct QuestArc: Codable, Identifiable {
    var id: String { key }

    let key: String
    let title: String
    let sortOrder: Int
}

// MARK: - Wire Model

private struct QuestTemplatesPayload: Decodable {
    let templates: [QuestTemplate]
    let arcs: [QuestArc]
}
