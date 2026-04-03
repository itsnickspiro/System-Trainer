import SwiftUI

// MARK: - AvatarPickerView
//
// Full-screen avatar selection grid. Avatars are grouped by category.
// Each cell shows the image from the Xcode asset catalog (key = asset name).
// Locked avatars are dimmed and show their unlock requirement.
// GP-priced locked avatars present a purchase confirmation sheet.

struct AvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var avatarService = AvatarService.shared
    @State private var purchaseTarget: AvatarTemplate? = nil
    @State private var isPurchasing = false
    @State private var showPurchaseError = false

    // Category display order and labels
    private let categoryOrder = ["free", "warrior", "mage", "rogue", "tank", "anime", "event"]
    private let categoryLabels: [String: String] = [
        "free":    "Free",
        "warrior": "Warrior",
        "mage":    "Mage",
        "rogue":   "Rogue",
        "tank":    "Tank",
        "anime":   "Anime",
        "event":   "Event"
    ]

    private var groupedCatalog: [(category: String, avatars: [AvatarTemplate])] {
        categoryOrder.compactMap { cat in
            let items = avatarService.catalog.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if avatarService.isLoading && avatarService.catalog.isEmpty {
                    ProgressView("Loading avatars…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(groupedCatalog, id: \.category) { group in
                                section(group.category, avatars: group.avatars)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Purchase Failed", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(avatarService.lastError ?? "An error occurred.")
            }
            .sheet(item: $purchaseTarget) { avatar in
                PurchaseAvatarSheet(avatar: avatar, isPurchasing: $isPurchasing) {
                    purchaseTarget = nil
                    Task {
                        isPurchasing = true
                        let ok = await avatarService.purchaseAndEquip(key: avatar.key)
                        isPurchasing = false
                        if !ok { showPurchaseError = true }
                    }
                }
            }
        }
        .task { await avatarService.refresh() }
    }

    // MARK: - Category Section

    private func section(_ category: String, avatars: [AvatarTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((categoryLabels[category] ?? category).uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 14) {
                ForEach(avatars) { avatar in
                    AvatarCell(avatar: avatar) {
                        handleTap(avatar)
                    }
                }
            }
        }
    }

    private func handleTap(_ avatar: AvatarTemplate) {
        guard !avatar.isEquipped else { return }
        if avatar.isUnlocked {
            Task { await avatarService.setAvatar(key: avatar.key) }
        } else if avatar.unlockType == "gp" {
            purchaseTarget = avatar
        }
        // level / achievement locked avatars: no-op (the cell shows the requirement)
    }
}

// MARK: - Avatar Cell

private struct AvatarCell: View {
    let avatar: AvatarTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 6) {
                    // Avatar image from asset catalog
                    avatarImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                        .overlay(ringOverlay)
                        .overlay(lockOverlay)
                        .opacity(avatar.isUnlocked ? 1 : 0.45)

                    Text(avatar.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(avatar.isUnlocked ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if !avatar.isUnlocked {
                        Text(avatar.unlockRequirement)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(avatar.unlockType == "gp" ? .orange : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(avatar.isEquipped
                              ? avatar.color.opacity(0.15)
                              : Color.secondary.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(avatar.isEquipped ? avatar.color : Color.clear, lineWidth: 2)
                        )
                )
                .shadow(color: avatar.isEquipped ? avatar.color.opacity(0.4) : .clear,
                        radius: 8, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!avatar.isUnlocked && avatar.unlockType != "gp")
    }

    private var avatarImage: Image {
        if UIImage(named: avatar.key) != nil {
            return Image(avatar.key)
        }
        return Image(systemName: "person.circle.fill")
    }

    @ViewBuilder
    private var ringOverlay: some View {
        if avatar.isEquipped {
            Circle()
                .stroke(avatar.color, lineWidth: 3)
                .shadow(color: avatar.color.opacity(0.8), radius: 6, x: 0, y: 0)
        } else {
            Circle()
                .stroke(avatar.rarityColor.opacity(0.6), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var lockOverlay: some View {
        if !avatar.isUnlocked {
            Circle()
                .fill(Color.black.opacity(0.35))
                .overlay(
                    Image(systemName: avatar.unlockType == "gp" ? "cart.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
        }
    }
}

// MARK: - Purchase Confirmation Sheet

private struct PurchaseAvatarSheet: View {
    let avatar: AvatarTemplate
    @Binding var isPurchasing: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeService = StoreService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Avatar preview
                AvatarImageView(key: avatar.key, size: 100)
                    .overlay(Circle().stroke(avatar.color, lineWidth: 3))
                    .shadow(color: avatar.color.opacity(0.5), radius: 10, x: 0, y: 0)

                VStack(spacing: 8) {
                    Text(avatar.name)
                        .font(.title2.weight(.bold))
                    Text(avatar.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Price
                HStack(spacing: 8) {
                    Image(systemName: storeService.currencyIcon)
                        .foregroundColor(.orange)
                    Text("\(avatar.gpPrice ?? 0) \(storeService.currencySymbol)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12), in: Capsule())

                HStack(spacing: 0) {
                    Text("Your balance: ")
                        .foregroundColor(.secondary)
                    Text("\(storeService.playerCredits) \(storeService.currencySymbol)")
                        .fontWeight(.semibold)
                        .foregroundColor(storeService.playerCredits >= (avatar.gpPrice ?? 0) ? .primary : .red)
                }
                .font(.subheadline)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView()
                        } else {
                            Text("Purchase & Equip")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        storeService.playerCredits >= (avatar.gpPrice ?? 0)
                            ? Color.orange
                            : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundColor(.white)
                }
                .disabled(storeService.playerCredits < (avatar.gpPrice ?? 0) || isPurchasing)
                .padding(.horizontal, 24)
            }
            .padding(.top, 32)
            .navigationTitle("Unlock Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Reusable AvatarImageView

/// Loads an avatar image from the Xcode asset catalog by key.
/// Falls back to the SF Symbol person.circle.fill when the asset is missing.
struct AvatarImageView: View {
    let key: String
    let size: CGFloat

    var body: some View {
        Group {
            if let img = UIImage(named: key) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.cyan)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("Player avatar")
    }
}
