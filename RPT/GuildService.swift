import Foundation
import Combine
import SwiftUI

// Allow `Result<T, String>` return types throughout this file. Swift's
// Result requires Failure: Error, so we retroactively conform String.
extension String: @retroactive Error {}

@MainActor
final class GuildService: ObservableObject {
    static let shared = GuildService()

    // MARK: - Published state

    @Published private(set) var currentGuild: GuildSummary? = nil
    @Published private(set) var currentRole: String = ""
    @Published private(set) var currentMembers: [GuildMember] = []
    @Published private(set) var currentRaid: GuildRaid? = nil
    @Published private(set) var currentContributions: [GuildContribution] = []
    @Published private(set) var publicGuilds: [GuildSummary] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String? = nil

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/guild-proxy"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public API

    /// Idempotent — fetch the user's current guild + active raid. Call on
    /// every launch and on every Home appear. Updates the local Profile
    /// cache fields if membership has changed since last sync.
    func refresh() async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await postToProxy(body: [
                "action": "get_my_guild",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(MyGuildResponse.self, from: data)
            applyMyGuildResponse(response)
        } catch {
            print("[GuildService] refresh failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func createGuild(name: String, description: String, isPublic: Bool) async -> Result<GuildSummary, String> {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            return .failure("Not signed in")
        }
        let displayName = DataManager.shared.currentProfile?.name ?? "Player"
        do {
            let data = try await postToProxy(body: [
                "action": "create_guild",
                "name": name,
                "description": description,
                "is_public": isPublic,
                "owner_cloudkit_user_id": cloudKitID,
                "owner_display_name": displayName
            ])
            let response = try JSONDecoder().decode(CreateGuildResponse.self, from: data)
            if let guild = response.guild {
                await refresh()
                return .success(guild)
            }
            return .failure(response.error ?? "Unknown error")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func joinGuild(_ guildID: String) async -> Result<GuildSummary, String> {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            return .failure("Not signed in")
        }
        let displayName = DataManager.shared.currentProfile?.name ?? "Player"
        do {
            let data = try await postToProxy(body: [
                "action": "join_guild",
                "guild_id": guildID,
                "cloudkit_user_id": cloudKitID,
                "display_name": displayName
            ])
            let response = try JSONDecoder().decode(CreateGuildResponse.self, from: data)
            if let guild = response.guild {
                await refresh()
                return .success(guild)
            }
            return .failure(response.error ?? "Could not join")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func leaveGuild() async -> Result<Void, String> {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            return .failure("Not signed in")
        }
        do {
            _ = try await postToProxy(body: [
                "action": "leave_guild",
                "cloudkit_user_id": cloudKitID
            ])
            // Clear local cache + refresh
            DataManager.shared.updateProfile { p in
                p.guildID = ""
                p.guildName = ""
                p.guildRole = ""
            }
            currentGuild = nil
            currentRole = ""
            currentMembers = []
            currentRaid = nil
            currentContributions = []
            return .success(())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func setWeeklyFocus(_ focus: String) async -> Result<Void, String> {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty,
              let guild = currentGuild else { return .failure("Not in a guild") }
        do {
            _ = try await postToProxy(body: [
                "action": "set_focus",
                "guild_id": guild.id,
                "requested_by_cloudkit_user_id": cloudKitID,
                "focus": focus
            ])
            await refresh()
            return .success(())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func loadPublicGuilds(page: Int = 1) async {
        do {
            let data = try await postToProxy(body: [
                "action": "list_public_guilds",
                "page": page,
                "page_size": 50
            ])
            let response = try JSONDecoder().decode(PublicGuildsResponse.self, from: data)
            publicGuilds = response.guilds ?? []
        } catch {
            print("[GuildService] loadPublicGuilds failed: \(error.localizedDescription)")
        }
    }

    /// Fire-and-forget contribution to the current week's guild raid.
    /// Called from the same DataManager hooks that already drive the
    /// per-player WeeklyBoss damage system, but the guild proxy aggregates
    /// across all members. Damage is the SAME amount the personal boss
    /// receives — players double-dip when they're in a guild, which is
    /// the right incentive to join one.
    func contributeDamage(_ damage: Int) async {
        guard damage > 0,
              let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty,
              currentGuild != nil else { return }
        let displayName = DataManager.shared.currentProfile?.name ?? "Player"
        do {
            let data = try await postToProxy(body: [
                "action": "contribute_to_raid",
                "cloudkit_user_id": cloudKitID,
                "display_name": displayName,
                "damage": damage
            ])
            // Refresh raid state from response so the UI reflects the new HP immediately
            if let response = try? JSONDecoder().decode(ContributeResponse.self, from: data) {
                if let raid = response.raid {
                    currentRaid = raid
                }
                if response.defeated == true {
                    // Reload contributions so the MVP order updates
                    await refresh()
                }
            }
        } catch {
            print("[GuildService] contributeDamage failed: \(error.localizedDescription)")
        }
    }

    func claimRaidReward() async -> Result<Int, String> {
        guard let cloudKitID = LeaderboardService.shared.currentUserID, !cloudKitID.isEmpty else {
            return .failure("Not signed in")
        }
        do {
            let data = try await postToProxy(body: [
                "action": "claim_raid_reward",
                "cloudkit_user_id": cloudKitID
            ])
            let response = try JSONDecoder().decode(ClaimResponse.self, from: data)
            if let gp = response.gp_award {
                // Award GP locally via PlayerProfileService so the UI updates
                await PlayerProfileService.shared.addCredits(
                    amount: gp,
                    type: "guild_raid_defeat",
                    referenceKey: currentRaid?.id ?? "guild_raid"
                )
                await refresh()
                return .success(gp)
            }
            return .failure(response.error ?? "No reward to claim")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Internals

    private func applyMyGuildResponse(_ response: MyGuildResponse) {
        currentGuild = response.guild
        currentRole = response.role ?? ""
        currentMembers = response.members ?? []
        currentRaid = response.raid
        currentContributions = response.contributions ?? []

        // Update the local Profile cache
        DataManager.shared.updateProfile { p in
            p.guildID = response.guild?.id ?? ""
            p.guildName = response.guild?.name ?? ""
            p.guildRole = response.role ?? ""
        }
    }

    private func postToProxy(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.proxyURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // Try to decode an error message from the body
            if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let msg = errResp.error {
                throw NSError(domain: "GuildService", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw NSError(domain: "GuildService", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return data
    }
}

// MARK: - Wire Models

struct GuildSummary: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let owner_cloudkit_user_id: String?
    let member_count: Int?
    let max_members: Int?
    let level: Int?
    let total_xp: Int?
    let weekly_focus: String?
    let is_public: Bool?
    let is_disbanded: Bool?
    let created_at: String?

    // Convenience accessors with sensible defaults
    var memberCount: Int { member_count ?? 1 }
    var maxMembers: Int { max_members ?? 12 }
    var guildLevel: Int { level ?? 1 }
    var weeklyFocus: String { weekly_focus ?? "" }
    var isFull: Bool { memberCount >= maxMembers }
}

struct GuildMember: Codable, Identifiable, Equatable {
    var id: String { cloudkit_user_id }
    let cloudkit_user_id: String
    let display_name: String
    let role: String              // "owner" | "officer" | "member"
    let contribution_xp: Int?
    let joined_at: String?

    var isOwner: Bool { role == "owner" }
}

struct GuildRaid: Codable, Identifiable, Equatable {
    let id: String
    let guild_id: String?
    let week_start_date: String?
    let boss_key: String?
    let max_hp: Int?
    let current_hp: Int?
    let damage_dealt: Int?
    let defeated_at: String?

    var maxHP: Int { max_hp ?? 0 }
    var currentHP: Int { current_hp ?? 0 }
    var damageDealt: Int { damage_dealt ?? 0 }
    var isDefeated: Bool { defeated_at != nil }
    var progress: Double {
        guard maxHP > 0 else { return 0 }
        return min(1.0, Double(damageDealt) / Double(maxHP))
    }
}

struct GuildContribution: Codable, Identifiable, Equatable {
    var id: String { cloudkit_user_id }
    let cloudkit_user_id: String
    let display_name: String
    let damage_contributed: Int
    let reward_claimed: Bool?
}

private struct MyGuildResponse: Decodable {
    let guild: GuildSummary?
    let role: String?
    let members: [GuildMember]?
    let raid: GuildRaid?
    let contributions: [GuildContribution]?
}

private struct CreateGuildResponse: Decodable {
    let success: Bool?
    let guild: GuildSummary?
    let error: String?
}

private struct PublicGuildsResponse: Decodable {
    let guilds: [GuildSummary]?
    let total: Int?
}

private struct ContributeResponse: Decodable {
    let success: Bool?
    let raid: GuildRaid?
    let defeated: Bool?
}

private struct ClaimResponse: Decodable {
    let success: Bool?
    let gp_award: Int?
    let error: String?
}

private struct ErrorResponse: Decodable {
    let error: String?
}
