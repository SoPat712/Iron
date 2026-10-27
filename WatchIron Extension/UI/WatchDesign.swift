import SwiftUI

enum IronTheme {
    static let accent = Color.blue
    static let accentSoft = accent.opacity(0.18)
    static let background = Color.black
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.62)
    static let field = Color.secondary.opacity(0.16)
    static let tertiaryFill = Color.secondary.opacity(0.12)
    static let outline = Color.secondary.opacity(0.28)
    static let onAccent = Color.white
    static let metricSets = Color.orange
    static let metricVolume = Color.green
    static let metricTime = Color.cyan
    static let metricTimeContainer = metricTime.opacity(0.15)
    static let metricEffort = Color.pink
    static let metricRecord = Color.yellow
    static let metricHeartRate = Color.red
    static let metricEnergy = Color.orange
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    static let compactCornerRadius: CGFloat = 10
    static let controlHeight: CGFloat = 44
}

enum IronMotion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let fade = Animation.easeOut(duration: 0.14)

    static func preferred(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

extension View {
    @ViewBuilder
    func watchGlassButton(prominent: Bool = false) -> some View {
        if #available(watchOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

struct WatchMetricValue: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.ironMetric(.headline, weight: .semibold))
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(IronTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WatchDataField: View {
    let label: String
    let value: String
    let unit: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(IronTheme.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.ironMetric(.title2))
                        .foregroundStyle(IronTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(1)
                    if let unit {
                        Text(unit)
                            .fixedSize()
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(IronTheme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(IronTheme.field,
                        in: RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius,
                                             style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue([value, unit].compactMap { $0 }.joined(separator: " "))
        .accessibilityHint("Opens a Digital Crown editor")
    }
}

struct WatchNumericEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let initialValue: Double
    let allowsEmpty: Bool
    let onCommit: (Double?) -> Void

    @State private var draft: Double = 0
    @State private var isEmpty = false
    @FocusState private var crownFocused: Bool

    var body: some View {
        NavigationStack {
        ScrollView {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)

            Text(isEmpty ? "—" : WatchNumber.format(snapped(draft)))
                .font(.ironMetric(.largeTitle))
                .foregroundStyle(IronTheme.primaryText)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text(unit)
                .font(.caption)
                .foregroundStyle(IronTheme.secondaryText)

            if title == "RPE" || title == "Effort" {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...10, id: \.self) { level in
                        Capsule()
                            .fill(Double(level) <= draft ? IronTheme.metricEffort : IronTheme.tertiaryFill)
                            .frame(height: CGFloat(4 + level * 2))
                    }
                }
                .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                Button { adjust(-step) } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Decrease " + title.lowercased())
                    .frame(minWidth: IronTheme.controlHeight, minHeight: IronTheme.controlHeight)
                Button { adjust(step) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Increase " + title.lowercased())
                    .frame(minWidth: IronTheme.controlHeight, minHeight: IronTheme.controlHeight)
            }
            .watchGlassButton()

            if allowsEmpty {
                Button(isEmpty ? "Use Value" : "Clear") { isEmpty.toggle() }
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 8)
        }
        .navigationTitle("")
        .watchVitalsInset()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onCommit(isEmpty ? nil : snapped(draft)); dismiss()
                } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Done")
            }
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($draft, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(title)
        .accessibilityValue(isEmpty ? "Not set" : "\(WatchNumber.format(snapped(draft))) \(unit)")
        .onAppear {
            draft = snapped(initialValue)
            isEmpty = allowsEmpty && initialValue <= range.lowerBound
            crownFocused = true
        }
        .onChange(of: draft) { isEmpty = false }
        .accessibilityAdjustableAction { direction in
            switch direction { case .increment: adjust(step); case .decrement: adjust(-step); @unknown default: break }
        }
        }
    }

    // Keep raw Crown travel so sub-detent motion accumulates. Only the shown
    // and committed value snaps; steppers also begin from the nearest detent.
    private func snapped(_ value: Double) -> Double {
        let offset = ((value - range.lowerBound) / step).rounded() * step
        return min(max(range.lowerBound + offset, range.lowerBound), range.upperBound)
    }

    private func adjust(_ delta: Double) {
        isEmpty = false
        draft = snapped(draft + delta)
    }
}

enum WatchNumber {
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func whole(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return String(format: "%.0f", value)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func distance(meters: Double, unit: WatchWorkoutWeightUnit) -> (String, String) {
        if unit == .pound {
            return (format(meters / 1_609.344), "mi")
        }
        return (format(meters / 1_000), "km")
    }

    static func meters(displayValue: Double, unit: WatchWorkoutWeightUnit) -> Double {
        unit == .pound ? displayValue * 1_609.344 : displayValue * 1_000
    }
}


struct WatchWorkoutSummaryRow: View {
    let title: String
    let exercises: [WatchWorkoutExercise]
    var date: Date? = nil
    var duration: TimeInterval? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).lineLimit(3).foregroundStyle(IronTheme.primaryText)
            if let date { Text(date, style: .date).font(.caption2).foregroundStyle(IronTheme.secondaryText) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { summaryMetrics }
                VStack(alignment: .leading, spacing: 3) { summaryMetrics }
            }
            let muscles = WatchWorkoutSummary.muscles(exercises)
            if !muscles.isEmpty {
                Text(muscles).font(.caption2).foregroundStyle(IronTheme.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var summaryMetrics: some View {
        if let duration {
            Text(WatchNumber.clock(duration)).font(.ironMetric(.caption, weight: .semibold))
                .foregroundStyle(IronTheme.metricTime)
        } else {
            Text("\(exercises.count) exercises").font(.caption2).foregroundStyle(IronTheme.secondaryText)
        }
        Text("\(exercises.reduce(0) { $0 + $1.sets.count }) sets")
            .font(.ironMetric(.caption, weight: .semibold)).foregroundStyle(IronTheme.metricSets)
    }
}

enum WatchWorkoutSummary {
    static func muscles(_ exercises: [WatchWorkoutExercise]) -> String {
        var counts: [String: Int] = [:]
        for exercise in exercises {
            guard let muscle = exercise.muscleGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !muscle.isEmpty else { continue }
            counts[muscle.localizedCapitalized, default: 0] += max(1, exercise.sets.count)
        }
        return counts.keys.sorted {
            counts[$0] == counts[$1] ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending : counts[$0, default: 0] > counts[$1, default: 0]
        }.prefix(3).joined(separator: " · ")
    }
}

extension WatchWorkoutSnapshot {
    var recordedDuration: TimeInterval { max(0, (endDate ?? startDate).timeIntervalSince(startDate)) }
}


struct WatchVitalsInset: ViewModifier {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let snapshot = store.workoutSnapshot, !snapshot.isFinishedRecord {
                WatchVitalsRow(manager: store.workoutSessionManager, snapshot: snapshot)
                    .privacySensitive(false).unredacted()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(IronTheme.background)
            }
        }
    }
}

extension View {
    func watchVitalsInset() -> some View { modifier(WatchVitalsInset()) }
}
