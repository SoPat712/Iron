import SwiftUI
import Charts
import UIKit

/// Value-only session data. Callers own completion order, display-unit volumes,
/// record classification, and persistence. Work without a recorded duration is
/// estimated at 40 seconds; missing completion times never acquire coordinates.
struct IronSessionStrip: View {
    struct ExerciseGroup {
        let label: String
        let sets: [Set]
    }

    struct Set {
        let relativeVolume: Double
        var kind: Kind = .normal
        var completedAt: Date?
        var duration: TimeInterval?
        var volume: Double = 0
        var result: String = ""
        var rpe: Double?

        enum Kind {
            case warmUp, normal, record
        }

        fileprivate var workDuration: TimeInterval {
            guard let duration, duration.isFinite, duration > 0 else { return 40 }
            return duration
        }

        fileprivate var hasCompletionTime: Bool {
            completedAt?.timeIntervalSinceReferenceDate.isFinite == true
        }
    }

    enum Size {
        case full, compact
    }

    let size: Size
    let accessibilityLabel: String
    let volumeUnit: String
    private let visibleGroups: [ExerciseGroup]
    private let untimedGroups: [ExerciseGroup]
    private let data: Timeline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var minimumGroupWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .caption2) private var captionPointSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var captionHeight: CGFloat = 14
    @State private var hasAppeared = false
    @State private var revealedGroups = 0
    @State private var selectedID: Int?
    @State private var plotSize = CGSize(width: 280, height: 168)

    private struct Entry: Identifiable {
        let id: Int
        let groupIndex: Int
        let exercise: String
        let set: Set
        let start: Double
        let end: Double
    }

    private struct Rest: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        var seconds: Double { (end - start) * 60 }
        var midpoint: Double { (start + end) / 2 }
    }

    private struct Band: Identifiable {
        let id: Int
        let number: Int
        let label: String
        let start: Double
        let end: Double

        var caption: String { "\(number) \(label)" }
    }

    private struct Activity: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        var restID: Int?

        var isRest: Bool { restID != nil }
    }

    /// Built once per input update, shared by Charts and the lightweight row.
    private struct Timeline {
        var entries: [Entry] = []
        var rests: [Rest] = []
        var activity: [Activity] = []
        var bands: [Band] = []
        var end: Double = 1
        var maximumVolume: Double = 0

        init(groups: [ExerciseGroup], sessionStart: Date?) {
            var ordered: [(id: Int, group: Int, label: String, set: Set)] = []
            for (index, group) in groups.enumerated() {
                for set in group.sets {
                    ordered.append((ordered.count, index, IronSessionStrip.shortName(group.label), set))
                }
            }
            let timed = ordered.filter { $0.set.hasCompletionTime }.sorted {
                let lhs = $0.set.completedAt!
                let rhs = $1.set.completedAt!
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
            guard let first = timed.first else { return }
            let firstWork = first.set.completedAt!.addingTimeInterval(-first.set.workDuration)
            let origin: Date
            if let sessionStart, sessionStart <= firstWork,
               firstWork.timeIntervalSince(sessionStart) <= 120 {
                origin = sessionStart
            } else {
                origin = firstWork
            }
            for item in timed {
                let end = item.set.completedAt!.timeIntervalSince(origin) / 60
                // Overlapping work (e.g. supersets) must not double-count time.
                let start = min(end, max(entries.last?.end ?? 0, end - item.set.workDuration / 60))
                if let previous = entries.last {
                    let lower = min(previous.id, item.id)
                    let upper = max(previous.id, item.id)
                    let hasMissingTime = ordered.contains {
                        $0.id > lower && $0.id < upper && !$0.set.hasCompletionTime
                    }
                    if start > previous.end, !hasMissingTime {
                        rests.append(.init(id: item.id, start: previous.end, end: start))
                        activity.append(.init(id: activity.count, start: previous.end, end: start, restID: item.id))
                    }
                }
                if end > start {
                    activity.append(.init(id: activity.count, start: start, end: end))
                }
                entries.append(.init(id: item.id, groupIndex: item.group, exercise: item.label,
                                     set: item.set, start: start, end: end))
            }
            // Never extend to workout.end: an idle finish editor isn't activity.
            let last = entries.last!.end
            end = max(last * 1.03, 1.0 / 60)
            maximumVolume = entries.map { $0.set.volume }.filter { $0.isFinite && $0 > 0 }.max() ?? 0
            for index in groups.indices {
                let groupEntries = entries.filter { $0.groupIndex == index }
                guard let first = groupEntries.first, let last = groupEntries.last else { continue }
                bands.append(.init(id: index, number: bands.count + 1, label: first.exercise,
                                   start: first.start, end: last.end))
            }
        }
    }

    init(groups: [ExerciseGroup], size: Size = .full, accessibilityLabel: String,
         sessionStart: Date? = nil, volumeUnit: String = "") {
        let visible = groups.filter { !$0.sets.isEmpty }
        self.visibleGroups = visible
        self.untimedGroups = visible.compactMap { group in
            let sets = group.sets.filter { !$0.hasCompletionTime }
            return sets.isEmpty ? nil : .init(label: group.label, sets: sets)
        }
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.volumeUnit = volumeUnit
        self.data = Timeline(groups: visible, sessionStart: sessionStart)
    }

    private var hasTimeline: Bool { !data.entries.isEmpty }
    private var barBaseline: Double { 0.25 }
    private var barCeiling: Double { 1 - Double(captionHeight + 10) / max(1, plotSize.height) }
    private var trackY: Double { 0.045 }
    private var plotWidth: Double { max(1, Double(plotSize.width) - 8) }

    private var labeledRestIDs: [Int] {
        var result: [Int] = []
        var occupied: [ClosedRange<Double>] = []
        let longestFirst = data.rests.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
        for rest in longestFirst where rest.seconds >= 120 {
            let width = captionWidth(restDuration(rest.seconds), metric: true) + 8
            let center = rest.midpoint / data.end * plotWidth
            let bounds = (center - width / 2)...(center + width / 2)
            guard bounds.lowerBound >= 0, bounds.upperBound <= plotWidth,
                  !occupied.contains(where: { $0.overlaps(bounds) }) else { continue }
            result.append(rest.id)
            occupied.append(bounds)
            if result.count == 3 { break }
        }
        return result
    }

    private func bandFitsLabel(_ band: Band) -> Bool {
        let width = (band.end - band.start) / data.end * plotWidth
        return width >= captionWidth(band.caption) + 12
    }

    private func captionWidth(_ text: String, metric: Bool = false) -> Double {
        let font = metric ? UIFont.monospacedDigitSystemFont(ofSize: captionPointSize, weight: .semibold)
            : UIFont.systemFont(ofSize: captionPointSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private var selectedEntry: Entry? { data.entries.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if size == .full, hasTimeline {
                timeline
                if !untimedGroups.isEmpty {
                    Text("\(untimedGroups.reduce(0) { $0 + $1.sets.count }) sets have no completion time:")
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                    orderedStrip(untimedGroups)
                }
            } else if size == .compact, hasTimeline {
                HStack(alignment: .bottom, spacing: 8) {
                    compactTimeline
                    if !untimedGroups.isEmpty {
                        orderedStrip(untimedGroups)
                            .frame(width: min(72, CGFloat(untimedGroups.reduce(0) { $0 + $1.sets.count }) * 6))
                    }
                }
            } else {
                orderedStrip(visibleGroups)
                if size == .full {
                    Text("Rest times weren't recorded for this workout.")
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                }
            }
            if size == .full, !visibleGroups.isEmpty { legend }
        }
        .task(id: reduceMotion) {
            hasAppeared = true
            guard size == .full, hasTimeline else { return }
            if reduceMotion {
                revealedGroups = visibleGroups.count
            } else if revealedGroups < visibleGroups.count {
                for count in (revealedGroups + 1)...visibleGroups.count {
                    guard !Task.isCancelled else { return }
                    revealedGroups = count
                    do { try await Task.sleep(for: .milliseconds(40)) }
                    catch { return }
                }
            }
        }
        // Plays once; List prefetching can disappear rows before they are shown.
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            let total = data.rests.reduce(0) { $0 + $1.seconds }
            let average = data.rests.isEmpty ? "–" : restDuration(total / Double(data.rests.count))
            Text("Total rest \(restTotal(total)) · Avg rest \(average)")
                .font(.ironMetric(.caption, weight: .semibold))
                .foregroundStyle(IronTheme.metricTime)
                .fixedSize(horizontal: false, vertical: true)
            selectionCallout
            if data.maximumVolume > 0 {
                HStack {
                    Text("Set volume")
                    Spacer()
                    Text("\(data.maximumVolume.formatted(.number.precision(.fractionLength(0)))) \(volumeUnit)")
                        .font(.ironMetric(.caption2, weight: .semibold))
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(IronTheme.secondaryText)
            }
            sessionChart
            let narrowBands = data.bands.filter { !bandFitsLabel($0) }
            if !narrowBands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(narrowBands) { band in
                            Text(band.caption)
                                .font(.caption2)
                                .foregroundStyle(IronTheme.secondaryText)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(IronTheme.tertiaryFill, in: Capsule())
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionChart: some View {
        let restIDs = labeledRestIDs
        let restLabels = Dictionary(uniqueKeysWithValues: data.rests.filter { restIDs.contains($0.id) }
            .map { ($0.id, restDuration($0.seconds)) })
        return Chart {
            ForEach(data.bands) { band in
                RectangleMark(
                    xStart: .value("Minutes", band.start),
                    xEnd: .value("Minutes", band.end),
                    yStart: .value("Lane", 0),
                    yEnd: .value("Lane", 1)
                )
                .foregroundStyle(IronTheme.primaryText.opacity(band.number.isMultiple(of: 2) ? 0.02 : 0.045))
                .annotation(position: .overlay, alignment: .topLeading, spacing: 0) {
                    if bandFitsLabel(band) {
                        Text(band.caption)
                            .font(.caption2)
                            .foregroundStyle(IronTheme.secondaryText)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.leading, 5)
                            .padding(.top, 3)
                    } else if (band.end - band.start) / data.end * plotWidth > captionWidth("\(band.number)") + 8 {
                        Text("\(band.number)")
                            .font(.caption2)
                            .foregroundStyle(IronTheme.secondaryText)
                            .padding(.leading, 4)
                            .padding(.top, 3)
                    }
                }
                .accessibilityHidden(true)
            }
            if data.maximumVolume > 0 {
                RuleMark(y: .value("Maximum volume", barCeiling))
                    .foregroundStyle(IronTheme.outline.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .accessibilityHidden(true)
            }
            if let first = data.entries.first, let last = data.entries.last {
                RectangleMark(
                    xStart: .value("Minutes", first.start),
                    xEnd: .value("Minutes", last.end),
                    y: .value("Lane", trackY),
                    height: .fixed(10)
                )
                .foregroundStyle(IronTheme.tertiaryFill)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }
            ForEach(data.activity) { segment in
                RectangleMark(
                    xStart: .value("Minutes", segment.start),
                    xEnd: .value("Minutes", segment.end),
                    y: .value("Lane", trackY),
                    height: .fixed(10)
                )
                .foregroundStyle(segment.isRest ? IronTheme.metricTime : IronTheme.accent)
                .clipShape(trackShape(segment, radius: 5))
                .annotation(position: .top, spacing: 3) {
                    if let id = segment.restID, let label = restLabels[id] {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(IronTheme.metricTime)
                            .fixedSize()
                    }
                }
                .accessibilityHidden(true)
            }
            ForEach(data.entries) { entry in
                BarMark(
                    x: .value("Minutes", entry.end),
                    yStart: .value("Lane", barBaseline),
                    yEnd: .value("Lane", barTop(entry)),
                    width: .fixed(4)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                .foregroundStyle(color(for: entry.set.kind))
                .accessibilityLabel("\(entry.exercise), \(kindLabel(entry.set.kind))")
                .accessibilityValue(setDescription(entry))
            }
            if let selectedEntry {
                RuleMark(x: .value("Selected set", selectedEntry.end))
                    .foregroundStyle(IronTheme.secondaryText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: 0...data.end, range: .plotDimension(startPadding: 4, endPadding: 4))
        .chartYScale(domain: 0...1, range: .plotDimension(startPadding: 0, endPadding: 0))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisTicks) { value in
                AxisGridLine()
                    .foregroundStyle(IronTheme.outline.opacity(0.15))
                AxisTick()
                    .foregroundStyle(IronTheme.outline.opacity(0.4))
                AxisValueLabel {
                    if let minute = value.as(Double.self) {
                        Text(minuteLabel(minute))
                            .font(.caption2)
                            .foregroundStyle(IronTheme.secondaryText)
                    }
                }
            }
        }
        .chartXSelection(value: Binding<Double?>(
            get: { selectedEntry?.end },
            set: { value in
                guard let value else { return } // Retain the callout after lifting.
                selectedID = data.entries.min {
                    abs($0.end - value) < abs($1.end - value)
                }?.id
            }
        ))
        .chartOverlay { proxy in
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { _ in proxy.plotSize } action: { plotSize = $0 }
        }
        .frame(height: 176 + captionHeight * 2)
        .opacity(hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: revealedGroups)
        .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: hasAppeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(selectedEntry.map { "\($0.exercise), \(setDescription($0))" }
                            ?? "Total rest \(restTotal(data.rests.reduce(0) { $0 + $1.seconds })). Swipe up or down to inspect completed sets.")
        .accessibilityAdjustableAction { direction in
            let timed = data.entries
            let index = timed.firstIndex { $0.id == selectedID }
            switch direction {
            case .increment: selectedID = timed[min((index ?? -1) + 1, timed.count - 1)].id
            case .decrement: selectedID = timed[max((index ?? timed.count) - 1, 0)].id
            default: break
            }
        }
    }

    @ViewBuilder
    private var selectionCallout: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let selectedEntry {
                Text(selectedEntry.exercise).font(.subheadline.weight(.semibold))
                Text(setDescription(selectedEntry))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(IronTheme.secondaryText)
            } else {
                Text("Touch the timeline to inspect a set")
                    .font(.caption)
                    .foregroundStyle(IronTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func setDescription(_ entry: Entry) -> String {
        var parts = [entry.set.result.isEmpty ? "Completed set" : entry.set.result]
        if let rpe = entry.set.rpe, rpe > 0 {
            parts.append("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
        }
        parts.append("at \(minuteLabel(entry.end))")
        if let rest = data.rests.first(where: { $0.id == entry.id }) {
            parts.append("Rested \(restDuration(rest.seconds)) before")
        }
        return parts.joined(separator: " · ")
    }

    private var axisTicks: [Double] {
        let step: Double = data.end <= 15 ? 5 : data.end <= 50 ? 10 : data.end <= 100 ? 15 : ceil(data.end / 90) * 15
        return stride(from: 0.0, through: data.end, by: step).map { $0 }
    }

    private func minuteLabel(_ value: Double) -> String {
        let minutes = Int(value.rounded())
        if minutes == 0 { return "0" }
        return "\(minutes)m"
    }

    private func restDuration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    private func restTotal(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private static func shortName(_ name: String) -> String {
        name.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
    }

    private func barTop(_ entry: Entry) -> Double {
        guard reduceMotion || entry.groupIndex < revealedGroups else { return barBaseline }
        let fraction = entry.set.volume.isFinite && entry.set.volume > 0
            ? entry.set.volume / max(1, data.maximumVolume) : 0.12
        return barBaseline + max(0, barCeiling - barBaseline) * fraction
    }

    private func trackShape(_ segment: Activity, radius: CGFloat) -> UnevenRoundedRectangle {
        let leading = segment.start == data.entries.first?.start ? radius : 0
        let trailing = segment.end == data.entries.last?.end ? radius : 0
        return UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                      bottomTrailingRadius: trailing, topTrailingRadius: trailing)
    }

    /// Plain SwiftUI shapes placed by Layout, with no Charts or geometry reader
    /// in scrolling History rows. All segment widths use the same time scale.
    private var compactTimeline: some View {
        let end = max(1.0 / 60, data.entries.last?.end ?? 1)
        return VStack(spacing: 3) {
            IronSessionIntervalLayout(intervals: data.entries.map { ($0.end / end)...($0.end / end) }, barWidth: 3) {
                ForEach(data.entries) { entry in
                    UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5)
                        .fill(color(for: entry.set.kind))
                        .frame(width: 3, height: max(4, 24 * relativeVolume(entry.set)))
                }
            }
            .frame(height: 24)
            .scaleEffect(y: hasAppeared || reduceMotion ? 1 : 0, anchor: .bottom)

            IronSessionIntervalLayout(intervals: data.activity.map { ($0.start / end)...($0.end / end) }) {
                ForEach(data.activity) { segment in
                    trackShape(segment, radius: 1)
                        .fill(segment.isRest ? IronTheme.metricTime : IronTheme.accent)
                }
            }
            .frame(height: 2)
            .background(IronTheme.tertiaryFill, in: Capsule())
        }
        .padding(.horizontal, 2)
        .opacity(hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func orderedStrip(_ groups: [ExerciseGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: size == .compact ? 1 : 12) {
                ForEach(groups.indices, id: \.self) { index in
                    orderedGroup(groups[index], index: index)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func orderedGroup(_ group: ExerciseGroup, index: Int) -> some View {
        let barHeight: CGFloat = size == .full ? 64 : 24
        let barWidth: CGFloat = size == .full ? 8 : 3
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: size == .compact ? 1 : 2) {
                ForEach(group.sets.indices, id: \.self) { setIndex in
                    let set = group.sets[setIndex]
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: set.kind))
                        .frame(width: barWidth, height: max(4, barHeight * relativeVolume(set)))
                }
            }
            .frame(minWidth: size == .full ? minimumGroupWidth : 0, minHeight: barHeight, alignment: .bottomLeading)
            .scaleEffect(y: hasAppeared || reduceMotion ? 1 : 0, anchor: .bottom)
            if size == .full {
                Text(Self.shortName(group.label))
                    .font(.caption2)
                    .foregroundStyle(IronTheme.secondaryText)
                    .fixedSize()
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(
            IronMotion.snappy.delay(Double(index) * 0.04), reduceMotion: reduceMotion
        ), value: hasAppeared)
    }

    private func relativeVolume(_ set: Set) -> Double {
        set.relativeVolume.isFinite ? min(max(set.relativeVolume, 0), 1) : 0
    }

    private func color(for kind: Set.Kind) -> Color {
        switch kind {
        case .warmUp: return IronTheme.metricSets
        case .normal: return IronTheme.accent
        case .record: return IronTheme.metricRecord
        }
    }

    private func kindLabel(_ kind: Set.Kind) -> String {
        switch kind {
        case .warmUp: return "warm-up set"
        case .normal: return "set"
        case .record: return "personal record set"
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                legendItem("Set", symbol: "checkmark.circle.fill", color: IronTheme.accent)
                legendItem("Warm-up", symbol: "w.circle.fill", color: IronTheme.metricSets)
                legendItem("Record", symbol: "trophy.fill", color: IronTheme.metricRecord)
                legendItem("Rest", symbol: "minus", color: IronTheme.metricTime)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.caption2)
        .foregroundStyle(IronTheme.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, symbol: String, color: Color) -> some View {
        Label { Text(title).fixedSize() } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}

/// Intervals are fractions of the available width. A fixed bar width places a
/// set at an instant; otherwise the subview fills its proportional time span.
private struct IronSessionIntervalLayout: Layout {
    let intervals: [ClosedRange<Double>]
    var barWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 280, height: proposal.height ?? 24)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (interval, subview) in zip(intervals, subviews) {
            let width = barWidth ?? bounds.width * (interval.upperBound - interval.lowerBound)
            let x = bounds.minX + bounds.width * interval.lowerBound - (barWidth ?? 0) / 2
            subview.place(at: CGPoint(x: x, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

#Preview("Session strips") {
    let start = Date()
    let groups: [IronSessionStrip.ExerciseGroup] = [
        .init(label: "Bench Press: Barbell", sets: [
            .init(relativeVolume: 0.25, kind: .warmUp, completedAt: start.addingTimeInterval(50), volume: 250, result: "50 lb × 5"),
            .init(relativeVolume: 0.8, completedAt: start.addingTimeInterval(200), volume: 800, result: "160 lb × 5", rpe: 7),
            .init(relativeVolume: 1, kind: .record, completedAt: start.addingTimeInterval(410), volume: 1000, result: "200 lb × 5", rpe: 9)
        ]),
        .init(label: "Incline Press: Dumbbell", sets: [
            .init(relativeVolume: 0.6, completedAt: start.addingTimeInterval(650), volume: 600, result: "60 lb × 10"),
            .init(relativeVolume: 0.65, completedAt: start.addingTimeInterval(800), volume: 650, result: "65 lb × 10")
        ])
    ]
    List {
        Section("Session") {
            IronSessionStrip(groups: groups, accessibilityLabel: "Five completed sets across two exercises.", sessionStart: start, volumeUnit: "lb")
        }
        Section("History") {
            IronSessionStrip(groups: groups, size: .compact, accessibilityLabel: "Five completed sets.")
        }
        Section("Legacy") {
            IronSessionStrip(groups: [.init(label: "Bench Press", sets: [.init(relativeVolume: 0.5), .init(relativeVolume: 1)])], accessibilityLabel: "Two sets without timestamps.")
        }
    }
}
