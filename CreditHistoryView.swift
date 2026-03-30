import SwiftUI

// MARK: - CreditHistoryView
//
// Displays a list of Gold Pieces (GP) transactions for the player.
// Transactions are fetched from PlayerProfileService.getCreditHistory()
// and sorted newest-first.

struct CreditHistoryView: View {
    @StateObject private var playerProfile = PlayerProfileService.shared
    @StateObject private var store = StoreService.shared

    @State private var transactions: [CreditTransaction] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: store.currencyIcon,
                        description: Text("Your Gold Pieces history will appear here.")
                    )
                } else {
                    List(transactions) { tx in
                        TransactionRow(tx: tx, currencySymbol: store.currencySymbol, currencyIcon: store.currencyIcon)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("GP History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Current balance pill
                    HStack(spacing: 4) {
                        Image(systemName: store.currencyIcon)
                            .foregroundColor(.orange)
                        Text("\(playerProfile.systemCredits.formatted())")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }
        }
        .task { await loadHistory() }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        transactions = await playerProfile.getCreditHistory()
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let tx: CreditTransaction
    let currencySymbol: String
    let currencyIcon: String

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundColor(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.subheadline.weight(.semibold))
                if let ref = tx.referenceKey {
                    Text(ref)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(Self.dateFormatter.string(from: tx.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Amount (+/-)
                Text(amountString)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(tx.amount >= 0 ? .green : .red)
                // Balance after
                Text("→ \(tx.balanceAfter.formatted()) \(currencySymbol)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var amountString: String {
        let sign = tx.amount >= 0 ? "+" : ""
        return "\(sign)\(tx.amount.formatted()) \(currencySymbol)"
    }

    private var typeLabel: String {
        switch tx.transactionType {
        case "quest_reward":        return "Quest Reward"
        case "level_up_bonus":      return "Level Up Bonus"
        case "daily_login":         return "Daily Login"
        case "streak_bonus":        return "Streak Bonus"
        case "achievement_reward":  return "Achievement"
        case "purchase":            return "Purchase"
        case "admin_grant":         return "Admin Grant"
        default:                    return tx.transactionType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var typeIcon: String {
        switch tx.transactionType {
        case "quest_reward":        return "checkmark.seal.fill"
        case "level_up_bonus":      return "arrow.up.circle.fill"
        case "daily_login":         return "calendar.badge.plus"
        case "streak_bonus":        return "flame.fill"
        case "achievement_reward":  return "trophy.fill"
        case "purchase":            return "cart.fill"
        case "admin_grant":         return "gift.fill"
        default:                    return "dollarsign.circle.fill"
        }
    }

    private var typeColor: Color {
        tx.amount >= 0 ? .green : .red
    }
}

// MARK: - Preview

#Preview {
    CreditHistoryView()
}
