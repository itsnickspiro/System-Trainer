import SwiftUI

/// Post-scan verdict screen — shown after a barcode/label scan to give
/// the user a Yuka-style breakdown: overall grade, nutrition vs additive
/// scores, flagged additives by risk tier, allergens, and a one-line
/// suggestion. Pure presentation; mutation happens via the callbacks.
struct PostScanVerdictView: View {
    let food: FoodItem
    let onLogAnyway: () -> Void
    let onDismiss: () -> Void

    private var verdict: IngredientGrader.Verdict {
        IngredientGrader.verdict(for: food)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    scoreBreakdown
                    summaryBlock

                    if !verdict.highRiskAdditives.isEmpty {
                        additiveSection(title: "High-Risk Additives",
                                        tint: .red,
                                        items: verdict.highRiskAdditives)
                    }
                    if !verdict.moderateRiskAdditives.isEmpty {
                        additiveSection(title: "Moderate-Risk Additives",
                                        tint: .orange,
                                        items: verdict.moderateRiskAdditives)
                    }
                    if !verdict.allergens.isEmpty {
                        allergensSection
                    }

                    suggestionFooter
                    actionButtons
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Verdict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(verdict.overallColor.opacity(0.2))
                    .frame(width: 110, height: 110)
                Circle()
                    .stroke(verdict.overallColor, lineWidth: 4)
                    .frame(width: 110, height: 110)
                Text(verdict.overallGrade)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(verdict.overallColor)
            }
            Text(food.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Score bars

    private var scoreBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            scoreBar(label: "Nutrition",
                     value: verdict.nutritionScore,
                     tint: .cyan)
            scoreBar(label: "Additive Purity",
                     value: verdict.additiveScore,
                     tint: .mint)
        }
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func scoreBar(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(value)/100")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, geo.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        Text(verdict.summary)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Additives lists

    private func additiveSection(title: String,
                                 tint: Color,
                                 items: [IngredientGrader.Additive]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            ForEach(items) { additive in
                VStack(alignment: .leading, spacing: 4) {
                    Text(additive.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(additive.reason)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Allergens

    private var allergensSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.yellow)
                Text("Allergens")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            FlowLayout(spacing: 8) {
                ForEach(verdict.allergens, id: \.self) { name in
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Suggestion + actions

    private var suggestionFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.cyan)
            Text(verdict.suggestion)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onLogAnyway) {
                Text("Log Anyway")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
            Button(action: onDismiss) {
                Text("Find Alternatives")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Tiny flow layout for allergen pills

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
