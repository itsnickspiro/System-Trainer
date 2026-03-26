import Combine
import Foundation
import SwiftUI

// MARK: - AnnouncementsService
//
// Fetches announcements from the announcements-proxy Edge Function, filtered
// by the current player's level.
//
// Announcement types:
//   • "modal"  — shown as a SwiftUI sheet on HomeView (once if show_once = true)
//   • "banner" — shown as a dismissable top banner on HomeView
//
// show_once announcements are tracked in UserDefaults so they never re-appear.
//
// notifications_config entries are forwarded to NotificationManager to
// replace any hardcoded notification copy.
//
// Usage:
//   await AnnouncementsService.shared.refresh()
//   AnnouncementsService.shared.pendingModal    // present as .sheet
//   AnnouncementsService.shared.activeBanners   // show as banners

@MainActor
final class AnnouncementsService: ObservableObject {

    static let shared = AnnouncementsService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    /// A modal announcement ready to display (cleared once shown).
    @Published var pendingModal: AnnouncementItem? = nil

    /// Active banner announcements (player can dismiss each).
    @Published private(set) var activeBanners: [AnnouncementItem] = []

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/announcements-proxy"
    private static let seenDefaultsKey = "rpt_seen_announcement_keys"

    private init() {}

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let level = DataManager.shared.currentProfile?.level ?? 1

        do {
            let payload = try await fetchFromSupabase(playerLevel: level)

            // Apply notification config templates
            if let configs = payload.notificationsConfig {
                applyNotificationConfigs(configs)
            }

            let seen = seenKeys()

            // Collect items to display
            var pendingModals: [AnnouncementItem] = []
            var banners: [AnnouncementItem] = []

            for item in payload.announcements {
                guard item.isEnabled else { continue }

                // Skip if already seen (for show_once items)
                if item.showOnce && seen.contains(item.key) { continue }

                switch item.displayType {
                case "modal":
                    pendingModals.append(item)
                case "banner":
                    banners.append(item)
                default:
                    break
                }
            }

            // Show first pending modal (queue the rest — simple first-come-first-served)
            if let first = pendingModals.first {
                pendingModal = first
            }

            activeBanners = banners
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Public Actions

    /// Call when a modal has been shown so it isn't re-displayed.
    func markModalSeen(_ item: AnnouncementItem) {
        if item.showOnce { markSeen(item.key) }
        pendingModal = nil
    }

    /// Dismiss a banner.
    func dismissBanner(_ item: AnnouncementItem) {
        if item.showOnce { markSeen(item.key) }
        activeBanners.removeAll { $0.key == item.key }
    }

    // MARK: - Private Helpers

    private func applyNotificationConfigs(_ configs: [NotificationConfigTemplate]) {
        // NotificationManager is created fresh each session in RPTApp;
        // we store the configs in UserDefaults so configureRecurringNotifications() can pick them up.
        var dict: [String: [String: String]] = [:]
        for c in configs {
            dict[c.key] = ["title": c.title, "body": c.body]
        }
        UserDefaults.standard.set(dict, forKey: "rpt_notification_config_overrides")
    }

    private func seenKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.seenDefaultsKey) ?? [])
    }

    private func markSeen(_ key: String) {
        var keys = seenKeys()
        keys.insert(key)
        UserDefaults.standard.set(Array(keys), forKey: Self.seenDefaultsKey)
    }

    // MARK: - Network

    private func fetchFromSupabase(playerLevel: Int) async throws -> AnnouncementsPayload {
        guard let url = URL(string: Self.proxyURL) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["player_level": playerLevel])
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return AnnouncementsPayload(announcements: [], notificationsConfig: nil)
        }

        return (try? JSONDecoder().decode(AnnouncementsPayload.self, from: data))
            ?? AnnouncementsPayload(announcements: [], notificationsConfig: nil)
    }
}

// MARK: - Public Models

struct AnnouncementItem: Codable, Identifiable {
    var id: String { key }

    let key:         String
    let title:       String
    let body:        String
    let displayType: String   // "modal" | "banner"
    let showOnce:    Bool
    let isEnabled:   Bool
    let ctaLabel:    String?  // Optional call-to-action button text for modals
    let ctaURL:      String?  // Optional URL for CTA

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case body
        case displayType  = "display_type"
        case showOnce     = "show_once"
        case isEnabled    = "is_enabled"
        case ctaLabel     = "cta_label"
        case ctaURL       = "cta_url"
    }
}

// MARK: - Wire Models (private)

private struct AnnouncementsPayload: Decodable {
    let announcements:     [AnnouncementItem]
    let notificationsConfig: [NotificationConfigTemplate]?

    enum CodingKeys: String, CodingKey {
        case announcements
        case notificationsConfig = "notifications_config"
    }
}

private struct NotificationConfigTemplate: Decodable {
    let key:   String
    let title: String
    let body:  String
}

// MARK: - Banner View

/// Dismissable top banner for announcements. Place in HomeView .overlay(alignment: .top).
struct AnnouncementBannerView: View {
    let item: AnnouncementItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "megaphone.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Modal View

/// Full-screen sheet for modal-type announcements.
struct AnnouncementModalView: View {
    let item: AnnouncementItem
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "megaphone.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(item.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(item.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            if let label = item.ctaLabel {
                Button(label) {
                    if let urlString = item.ctaURL, let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            Button("Dismiss", action: onDismiss)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
    }
}
