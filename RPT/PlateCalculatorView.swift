import SwiftUI

/// Olympic-bar plate loader. Given a target weight and the user's metric/
/// imperial preference, computes the optimal plate combination per side
/// of a 20kg / 45lb barbell using a greedy algorithm.
struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    let useMetric: Bool

    @State private var targetWeight: Double = 60

    init(useMetric: Bool, initialWeight: Double? = nil) {
        self.useMetric = useMetric
        let bar: Double = useMetric ? 20 : 45
        let start = max(bar, initialWeight ?? (useMetric ? 60 : 135))
        _targetWeight = State(initialValue: start)
    }

    private var barWeight: Double { useMetric ? 20 : 45 }
    private var unit: String { useMetric ? "kg" : "lb" }

    private var plateSet: [(weight: Double, color: Color, label: String)] {
        if useMetric {
            return [
                (25, .red, "25"),
                (20, .blue, "20"),
                (15, .yellow, "15"),
                (10, .green, "10"),
                (5, .white, "5"),
                (2.5, Color(red: 0.5, green: 0.7, blue: 1.0), "2.5"),
                (1.25, .gray, "1.25")
            ]
        } else {
            return [
                (45, .blue, "45"),
                (35, .yellow, "35"),
                (25, .green, "25"),
                (10, .white, "10"),
                (5, .blue, "5"),
                (2.5, .gray, "2.5")
            ]
        }
    }

    private var perSidePlates: [(weight: Double, count: Int, color: Color, label: String)] {
        let perSide = max(0, (targetWeight - barWeight) / 2)
        var remaining = perSide
        var result: [(Double, Int, Color, String)] = []
        for plate in plateSet {
            let count = Int((remaining / plate.weight).rounded(.down))
            if count > 0 {
                result.append((plate.weight, count, plate.color, plate.label))
                remaining -= Double(count) * plate.weight
            }
        }
        return result
    }

    private var perSideTotal: Double {
        perSidePlates.reduce(0) { $0 + (Double($1.count) * $1.weight) }
    }

    private var actualTotal: Double { barWeight + perSideTotal * 2 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Target weight stepper
                VStack(spacing: 8) {
                    Text("TARGET WEIGHT")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    HStack(spacing: 16) {
                        Button { targetWeight = max(barWeight, targetWeight - 2.5) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.cyan)
                        }
                        Text("\(targetWeight, specifier: "%.1f") \(unit)")
                            .font(.system(size: 36, weight: .black, design: .monospaced))
                            .frame(minWidth: 160)
                        Button { targetWeight += 2.5 } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.cyan)
                        }
                    }
                }

                Divider()

                // Per-side plate breakdown
                VStack(spacing: 12) {
                    Text("LOAD PER SIDE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    if perSidePlates.isEmpty {
                        Text("Just the bar")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(perSidePlates, id: \.weight) { plate in
                                HStack {
                                    Circle()
                                        .fill(plate.color)
                                        .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                                        .frame(width: 36, height: 36)
                                    Text("\(plate.label) \(unit)")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    Spacer()
                                    Text("× \(plate.count)")
                                        .font(.system(size: 18, weight: .black, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                // Actual total (may differ slightly if target isn't reachable with available plates)
                if abs(actualTotal - targetWeight) > 0.01 {
                    Text("Actual: \(actualTotal, specifier: "%.2f") \(unit)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
