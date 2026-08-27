//
//  ExerciseStatisticsView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 06.07.19.
//  Rebuilt for Iron's focused exercise progress view.
//

import SwiftUI
import WorkoutDataKit

struct ExerciseStatisticsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exercise: Exercise

    @State private var selectedTimeFrame = WorkoutExerciseChartData.TimeFrame.month

    private var workoutExercises: [WorkoutExercise] {
        WorkoutExerciseChartData.workoutExercises(
            uuid: exercise.uuid,
            timeFrame: selectedTimeFrame,
            context: managedObjectContext
        ) ?? []
    }

    private var completedWorkoutExercises: [WorkoutExercise] {
        workoutExercises.filter { ($0.numberOfCompletedSets ?? 0) > 0 }
    }

    private var completedSets: Int {
        completedWorkoutExercises.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
    }

    private var lastSessionDate: Date? {
        completedWorkoutExercises.compactMap { $0.workout?.start }.max()
    }

    private var completedWorkoutSets: [WorkoutSet] {
        completedWorkoutExercises.flatMap { completedSets(for: $0) }
    }

    private var progressMetrics: [ExerciseProgressMetric] {
        let hasWeight = completedWorkoutSets.contains { $0.weightValue > 0 }
        let hasRepetitions = completedWorkoutSets.contains { $0.repetitionsValue > 0 }
        let hasDuration = completedWorkoutSets.contains { $0.durationValue != nil }
        let hasDistance = completedWorkoutSets.contains { $0.distanceValue != nil }
        let isBodyweight = exercise.equipment.contains { equipment in
            let normalized = equipment.lowercased().replacingOccurrences(of: "-", with: " ")
            return normalized.contains("body weight") || normalized.contains("bodyweight")
        }

        if hasDistance {
            var metrics: [ExerciseProgressMetric] = [.totalDistance, .bestDistance]
            if hasDuration {
                metrics += [.totalDuration, .bestDuration]
            }
            if hasRepetitions {
                metrics.append(.totalRepetitions)
            }
            metrics.append(.totalSets)
            return metrics
        }

        if hasDuration && !hasWeight {
            var metrics: [ExerciseProgressMetric] = [.totalDuration, .bestDuration]
            if hasRepetitions {
                metrics.append(.totalRepetitions)
            }
            metrics.append(.totalSets)
            return metrics
        }

        if isBodyweight && !hasWeight {
            var metrics: [ExerciseProgressMetric] = []
            if hasRepetitions {
                metrics += [.bestRepetitions, .totalRepetitions]
            }
            metrics.append(.totalSets)
            return metrics
        }

        return [.oneRM, .totalWeight, .totalSets, .totalRepetitions]
    }

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    overviewCard
                        .padding(.bottom, 16)
                    timeFramePicker
                        .padding(.bottom, 20)
                    IronHairline(opacity: 0.52)

                    if completedWorkoutExercises.isEmpty {
                        noCompletedDataCard
                            .padding(.vertical, 24)
                    } else {
                        ForEach(Array(progressMetrics.enumerated()), id: \.element) { index, metric in
                            progressCard(metric)
                            if index < progressMetrics.count - 1 {
                                IronHairline(opacity: 0.52)
                            }
                        }
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(selectedTimeFrame.subtitle)
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)

                Spacer(minLength: 8)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(IronTheme.accentSoft))
            }

            HStack(spacing: 0) {
                summaryMetric(
                    value: "\(completedWorkoutExercises.count)",
                    label: completedWorkoutExercises.count == 1 ? "Session" : "Sessions"
                )
                summaryMetricDivider
                summaryMetric(
                    value: "\(completedSets)",
                    label: completedSets == 1 ? "Completed set" : "Completed sets"
                )
                summaryMetricDivider
                summaryMetric(
                    value: lastSessionDate.map(Self.compactDateFormatter.string) ?? "—",
                    label: "Last trained"
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var summaryMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.55))
            .frame(width: 1, height: 36)
    }

    private var timeFramePicker: some View {
        HStack(spacing: 6) {
            ForEach(WorkoutExerciseChartData.TimeFrame.allCases, id: \.title) { timeFrame in
                Button {
                    if reduceMotion {
                        selectedTimeFrame = timeFrame
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedTimeFrame = timeFrame
                        }
                    }
                } label: {
                    Text(timeFrame.compactTitle)
                }
                .buttonStyle(IronChoicePillButtonStyle(isSelected: selectedTimeFrame == timeFrame))
                .accessibilityLabel(timeFrame.title)
                .accessibilityAddTraits(selectedTimeFrame == timeFrame ? .isSelected : [])
            }
        }
    }

    private var noCompletedDataCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 58, height: 58)
                .background(Circle().fill(IronTheme.accentSoft))

            VStack(spacing: 5) {
                Text("No progress in this period")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Complete a set of this exercise and Iron will chart strength, volume, sets, and repetitions here.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedTimeFrame == .all {
                Label("All available history is selected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))
                    .accessibilityHint("Complete a set to begin tracking this exercise")
            } else {
                Button {
                    if reduceMotion {
                        selectedTimeFrame = .all
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedTimeFrame = .all
                        }
                    }
                } label: {
                    Label("Show all history", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(IronCompactPillButtonStyle())
                .accessibilityHint("Shows all available completed workout data")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func progressCard(_ metric: ExerciseProgressMetric) -> some View {
        let points = progressPoints(for: metric)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: metric.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text(metric.caption)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 8)

                if let latest = points.last {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatted(latest.value, for: metric))
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundColor(IronTheme.primaryText)
                        trendLabel(points, metric: metric)
                    }
                }
            }

            if points.isEmpty {
                emptyState(for: metric)
            } else {
                let domainStart = selectedTimeFrame.domainStart(earliestDate: points.first?.date)
                let domainEnd = Date()
                GeometryReader { geometry in
                    let plotWidth = selectedTimeFrame.plotWidth(
                        viewportWidth: geometry.size.width,
                        earliestDate: points.first?.date
                    )
                    let needsScroll = plotWidth > geometry.size.width + 1

                    Group {
                        if needsScroll {
                            ScrollView(.horizontal, showsIndicators: true) {
                                ExerciseProgressLine(
                                    points: points,
                                    domainStart: domainStart,
                                    domainEnd: domainEnd,
                                    valueLabel: { formatted($0, for: metric) },
                                    dateLabel: { Self.detailDateFormatter.string(from: $0) }
                                )
                                .frame(width: plotWidth, height: 148)
                            }
                            .defaultScrollAnchorCompat_trailing()
                        } else {
                            ExerciseProgressLine(
                                points: points,
                                domainStart: domainStart,
                                domainEnd: domainEnd,
                                valueLabel: { formatted($0, for: metric) },
                                dateLabel: { Self.detailDateFormatter.string(from: $0) }
                            )
                        }
                    }
                }
                .frame(height: 148)

                HStack {
                    Text(Self.axisDateFormatter.string(from: domainStart))
                    Spacer()
                    Text(selectedTimeFrame.compactTitle)
                        .foregroundColor(IronTheme.secondaryText)
                    Spacer()
                    Text(Self.axisDateFormatter.string(from: domainEnd))
                }
                .font(.caption2.weight(.medium))
                .foregroundColor(IronTheme.tertiaryText)

                if selectedTimeFrame.plotWidth(viewportWidth: 320, earliestDate: points.first?.date) > 321 {
                    Text("Scroll horizontally to see the full \(selectedTimeFrame.title.lowercased()) range.")
                        .font(.caption2)
                        .foregroundColor(IronTheme.tertiaryText)
                }
            }
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func trendLabel(
        _ points: [ExerciseProgressPoint],
        metric: ExerciseProgressMetric
    ) -> some View {
        if let first = points.first, let latest = points.last, points.count > 1 {
            let difference = latest.value - first.value
            if abs(difference) < 0.0001 {
                Label("No change", systemImage: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
            } else {
                Label(
                    "\(difference > 0 ? "+" : "")\(formatted(difference, for: metric))",
                    systemImage: difference > 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(difference > 0 ? IronTheme.success : IronTheme.secondaryText)
            }
        } else {
            Text("Latest")
                .font(.caption2.weight(.medium))
                .foregroundColor(IronTheme.secondaryText)
        }
    }

    private func emptyState(for metric: ExerciseProgressMetric) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(IronTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(IronTheme.raisedSurface))

            VStack(alignment: .leading, spacing: 3) {
                Text("No completed data yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text(metric.emptyMessage)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface.opacity(0.72))
        )
    }

    private func progressPoints(
        for metric: ExerciseProgressMetric
    ) -> [ExerciseProgressPoint] {
        return workoutExercises.compactMap { workoutExercise in
            guard let date = workoutExercise.workout?.start,
                  let value = value(for: metric, in: workoutExercise),
                  value > 0,
                  value.isFinite else { return nil }
            let identifier = workoutExercise.uuid?.uuidString
                ?? workoutExercise.objectID.uriRepresentation().absoluteString
            return ExerciseProgressPoint(
                id: identifier,
                date: date,
                value: value,
                details: sessionDetails(for: workoutExercise)
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func sessionDetails(for workoutExercise: WorkoutExercise) -> [String] {
        let sets = completedSets(for: workoutExercise)
        var details = [sets.count == 1 ? "1 set" : "\(sets.count) sets"]

        let repetitions = sets.reduce(0) { $0 + Int($1.repetitionsValue) }
        if repetitions > 0 {
            details.append("\(repetitions) reps")
        }

        if let kilograms = workoutExercise.totalCompletedWeight, kilograms > 0 {
            let weight = WeightUnit.convert(
                weight: kilograms,
                from: .metric,
                to: settingsStore.weightUnit
            )
            let formattedWeight = settingsStore.weightUnit.numberFormatter.string(
                from: NSNumber(value: weight)
            ) ?? String(format: "%.1f", weight)
            details.append("\(formattedWeight) \(settingsStore.weightUnit.unit.symbol)")
        }

        let duration = sets.compactMap(\.durationValue).reduce(0, +)
        if duration > 0 {
            details.append(formatDuration(duration))
        }

        let distance = sets.compactMap(\.distanceValue).reduce(0, +)
        if distance > 0 {
            details.append(formatDistance(distance))
        }

        return Array(details.prefix(4))
    }

    private func formatted(
        _ value: Double,
        for metric: ExerciseProgressMetric
    ) -> String {
        switch metric {
        case .totalDuration, .bestDuration:
            return formatDuration(value)
        case .totalDistance, .bestDistance:
            return formatDistance(value)
        default:
            break
        }

        let absolute = abs(value)
        let number: String
        if absolute >= 1_000_000 {
            number = String(format: "%.1fM", value / 1_000_000)
        } else if absolute >= 10_000 {
            number = String(format: "%.1fk", value / 1_000)
        } else if value.rounded() == value {
            number = String(format: "%.0f", value)
        } else {
            number = String(format: "%.1f", value)
        }

        switch metric {
        case .oneRM, .totalWeight:
            return "\(number) \(settingsStore.weightUnit.unit.symbol)"
        case .totalSets, .totalRepetitions, .bestRepetitions:
            return number
        case .totalDuration, .bestDuration, .totalDistance, .bestDistance:
            return number
        }
    }

    private func value(for metric: ExerciseProgressMetric, in workoutExercise: WorkoutExercise) -> Double? {
        let sets = completedSets(for: workoutExercise)

        switch metric {
        case .oneRM:
            return sets
                .compactMap { $0.estimatedOneRepMax(maxReps: settingsStore.maxRepetitionsOneRepMax) }
                .max()
                .map {
                    WeightUnit.convert(weight: $0, from: .metric, to: settingsStore.weightUnit)
                }
        case .totalWeight:
            return workoutExercise.totalCompletedWeight.map {
                WeightUnit.convert(weight: $0, from: .metric, to: settingsStore.weightUnit)
            }
        case .totalSets:
            return Double(sets.count)
        case .totalRepetitions:
            return Double(sets.reduce(0) { $0 + Int($1.repetitionsValue) })
        case .bestRepetitions:
            return sets.map { Double($0.repetitionsValue) }.max()
        case .totalDuration:
            return sets.compactMap(\.durationValue).reduce(0, +)
        case .bestDuration:
            return sets.compactMap(\.durationValue).max()
        case .totalDistance:
            return sets.compactMap(\.distanceValue).reduce(0, +)
        case .bestDistance:
            return sets.compactMap(\.distanceValue).max()
        }
    }

    private func completedSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        (workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []).filter(\.isCompleted)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "−" : ""
        let roundedSeconds = Int(abs(seconds).rounded())
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        if hours > 0 {
            return String(format: "%@%d:%02d:%02d", sign, hours, minutes, remainingSeconds)
        }
        return String(format: "%@%d:%02d", sign, minutes, remainingSeconds)
    }

    private func formatDistance(_ meters: Double) -> String {
        let sign = meters < 0 ? "−" : ""
        let absoluteMeters = abs(meters)

        switch settingsStore.weightUnit {
        case .metric:
            if absoluteMeters >= 1_000 {
                return String(format: "%@%.2f km", sign, absoluteMeters / 1_000)
            }
            return String(format: "%@%.0f m", sign, absoluteMeters)
        case .imperial:
            let miles = Measurement(value: absoluteMeters, unit: UnitLength.meters)
                .converted(to: .miles).value
            if miles >= 0.1 {
                return String(format: "%@%.2f mi", sign, miles)
            }
            let feet = Measurement(value: absoluteMeters, unit: UnitLength.meters)
                .converted(to: .feet).value
            return String(format: "%@%.0f ft", sign, feet)
        }
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy jm")
        return formatter
    }()
}

private struct ExerciseProgressPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let details: [String]
}

private struct ExerciseProgressLine: View {
    let points: [ExerciseProgressPoint]
    var domainStart: Date? = nil
    var domainEnd: Date? = nil
    let valueLabel: (Double) -> String
    let dateLabel: (Date) -> String

    @State private var selectedPointID: ExerciseProgressPoint.ID?

    var body: some View {
        GeometryReader { geometry in
            let chartGeometry = ExerciseProgressChartGeometry(
                points: points,
                size: geometry.size,
                domainStart: domainStart,
                domainEnd: domainEnd
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard !points.isEmpty, size.width > 0, size.height > 0 else { return }

                    for fraction in [0.0, 0.5, 1.0] {
                        var gridLine = Path()
                        let y = chartGeometry.plot.minY + (chartGeometry.plot.height * fraction)
                        gridLine.move(to: CGPoint(x: chartGeometry.plot.minX, y: y))
                        gridLine.addLine(to: CGPoint(x: chartGeometry.plot.maxX, y: y))
                        context.stroke(gridLine, with: .color(IronTheme.outline.opacity(0.35)), lineWidth: 1)
                    }

                    var line = Path()
                    if let first = points.first,
                       let firstPosition = chartGeometry.position(for: first.id) {
                        line.move(to: firstPosition)
                        for point in points.dropFirst() {
                            if let position = chartGeometry.position(for: point.id) {
                                line.addLine(to: position)
                            }
                        }
                    }

                    if points.count > 1,
                       let first = points.first,
                       let last = points.last,
                       let firstPosition = chartGeometry.position(for: first.id),
                       let lastPosition = chartGeometry.position(for: last.id) {
                        var fill = line
                        fill.addLine(to: CGPoint(x: lastPosition.x, y: chartGeometry.plot.maxY))
                        fill.addLine(to: CGPoint(x: firstPosition.x, y: chartGeometry.plot.maxY))
                        fill.closeSubpath()
                        context.fill(
                            fill,
                            with: .linearGradient(
                                Gradient(colors: [IronTheme.accent.opacity(0.24), IronTheme.accent.opacity(0.01)]),
                                startPoint: CGPoint(x: 0, y: chartGeometry.plot.minY),
                                endPoint: CGPoint(x: 0, y: chartGeometry.plot.maxY)
                            )
                        )
                    }

                    context.stroke(
                        line,
                        with: .color(IronTheme.accent),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                    if let selectedPoint,
                       let selectedPosition = chartGeometry.position(for: selectedPoint.id) {
                        var guide = Path()
                        guide.move(to: CGPoint(x: selectedPosition.x, y: chartGeometry.plot.minY))
                        guide.addLine(to: CGPoint(x: selectedPosition.x, y: chartGeometry.plot.maxY))
                        context.stroke(
                            guide,
                            with: .color(IronTheme.accent.opacity(0.62)),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                    }

                    for point in points {
                        guard let position = chartGeometry.position(for: point.id) else { continue }
                        if point.id == selectedPoint?.id {
                            let halo = CGRect(x: position.x - 10, y: position.y - 10, width: 20, height: 20)
                            let ring = CGRect(x: position.x - 7, y: position.y - 7, width: 14, height: 14)
                            let center = CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: halo), with: .color(IronTheme.accent.opacity(0.18)))
                            context.stroke(Path(ellipseIn: ring), with: .color(IronTheme.accent), lineWidth: 2)
                            context.fill(Path(ellipseIn: center), with: .color(IronTheme.background))
                        } else {
                            let outer = CGRect(x: position.x - 5, y: position.y - 5, width: 10, height: 10)
                            let inner = CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
                            context.fill(Path(ellipseIn: outer), with: .color(IronTheme.accent))
                            context.fill(Path(ellipseIn: inner), with: .color(IronTheme.background))
                        }
                    }
                }

                ForEach(Array(chartGeometry.axisValues.enumerated()), id: \.offset) { index, value in
                    Text(valueLabel(value))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundColor(IronTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .frame(width: 52, alignment: .trailing)
                        .position(
                            x: 26,
                            y: chartGeometry.plot.minY
                                + chartGeometry.plot.height * CGFloat(index) / 2
                        )
                        .accessibilityHidden(true)
                }

                if let selectedPoint,
                   let selectedPosition = chartGeometry.position(for: selectedPoint.id) {
                    selectionTooltip(for: selectedPoint, at: selectedPosition, in: geometry.size)
                }
            }
            .animation(.easeOut(duration: 0.12), value: selectedPointID)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedPointID = chartGeometry.nearestPointID(to: value.location)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Exercise progress chart with \(points.count) data points")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Tap or drag across the chart to select a session. Use the previous and next session actions to explore the chart.")
            .accessibilityAction(named: Text("Previous session")) {
                adjustSelection(.decrement)
            }
            .accessibilityAction(named: Text("Next session")) {
                adjustSelection(.increment)
            }
            .onChange(of: points.map(\.id)) { _, identifiers in
                if let selectedPointID, !identifiers.contains(selectedPointID) {
                    self.selectedPointID = nil
                }
            }
        }
    }

    private var selectedPoint: ExerciseProgressPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    private var accessibilityValue: String {
        guard let selectedPoint,
              let index = points.firstIndex(where: { $0.id == selectedPoint.id }) else {
            let sessionLabel = points.count == 1 ? "1 session" : "\(points.count) sessions"
            return "\(sessionLabel). Select a point to hear its date and value."
        }
        let details = selectedPoint.details.joined(separator: ", ")
        return "\(dateLabel(selectedPoint.date)), \(valueLabel(selectedPoint.value)), \(details); session \(index + 1) of \(points.count)"
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }

        let currentIndex = selectedPointID.flatMap { id in
            points.firstIndex { $0.id == id }
        }
        let targetIndex: Int
        switch direction {
        case .increment:
            targetIndex = min((currentIndex ?? -1) + 1, points.count - 1)
        case .decrement:
            targetIndex = max((currentIndex ?? points.count) - 1, 0)
        @unknown default:
            return
        }
        selectedPointID = points[targetIndex].id
    }

    @ViewBuilder
    private func selectionTooltip(
        for point: ExerciseProgressPoint,
        at position: CGPoint,
        in size: CGSize
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dateLabel(point.date))
                .font(.caption2.weight(.medium))
                .foregroundColor(IronTheme.secondaryText)
            Text(valueLabel(point.value))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
            Text(point.details.joined(separator: "  •  "))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 224, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
        .position(
            x: min(max(position.x, 118), max(size.width - 118, 118)),
            y: position.y < 52 ? min(position.y + 46, size.height - 36) : position.y - 46
        )
        .accessibilityHidden(true)
    }
}

private struct ExerciseProgressChartGeometry {
    let plot: CGRect
    let lowerValue: Double
    let upperValue: Double
    private let points: [ExerciseProgressPoint]
    private let positions: [ExerciseProgressPoint.ID: CGPoint]

    init(
        points: [ExerciseProgressPoint],
        size: CGSize,
        domainStart: Date? = nil,
        domainEnd: Date? = nil
    ) {
        self.points = points
        plot = CGRect(
            x: 58,
            y: 10,
            width: max(size.width - 63, 1),
            height: max(size.height - 20, 1)
        )

        let minimumValue = points.map(\.value).min() ?? 0
        let maximumValue = points.map(\.value).max() ?? minimumValue
        let rawRange = maximumValue - minimumValue
        let padding = rawRange > 0 ? rawRange * 0.14 : max(abs(maximumValue) * 0.12, 1)
        lowerValue = minimumValue - padding
        upperValue = maximumValue + padding
        let valueRange = max(upperValue - lowerValue, 1)

        let minimumDate = (domainStart ?? points.map(\.date).min() ?? Date()).timeIntervalSinceReferenceDate
        let maximumDate = (domainEnd ?? points.map(\.date).max() ?? Date()).timeIntervalSinceReferenceDate
        let dateRange = max(maximumDate - minimumDate, 1)

        var calculatedPositions: [ExerciseProgressPoint.ID: CGPoint] = [:]
        for point in points {
            let x = plot.minX + plot.width * CGFloat((point.date.timeIntervalSinceReferenceDate - minimumDate) / dateRange)
            let y = plot.maxY - plot.height * CGFloat((point.value - lowerValue) / valueRange)
            calculatedPositions[point.id] = CGPoint(x: x, y: y)
        }
        positions = calculatedPositions
    }

    var axisValues: [Double] {
        [upperValue, lowerValue + (upperValue - lowerValue) / 2, lowerValue]
    }

    func position(for id: ExerciseProgressPoint.ID) -> CGPoint? {
        positions[id]
    }

    func nearestPointID(to location: CGPoint) -> ExerciseProgressPoint.ID? {
        points.min { left, right in
            guard let leftPosition = positions[left.id],
                  let rightPosition = positions[right.id] else { return false }
            return abs(leftPosition.x - location.x) < abs(rightPosition.x - location.x)
        }?.id
    }
}

private enum ExerciseProgressMetric: Hashable {
    case oneRM
    case totalWeight
    case totalSets
    case totalRepetitions
    case bestRepetitions
    case totalDuration
    case bestDuration
    case totalDistance
    case bestDistance

    var title: String {
        switch self {
        case .oneRM: return "Estimated 1RM"
        case .totalWeight: return "Total Weight"
        case .totalSets: return "Total Sets"
        case .totalRepetitions: return "Total Repetitions"
        case .bestRepetitions: return "Best Set Reps"
        case .totalDuration: return "Total Duration"
        case .bestDuration: return "Best Duration"
        case .totalDistance: return "Total Distance"
        case .bestDistance: return "Best Distance"
        }
    }

    var icon: String {
        switch self {
        case .oneRM: return "bolt.fill"
        case .totalWeight: return "scalemass.fill"
        case .totalSets: return "square.stack.3d.up.fill"
        case .totalRepetitions: return "repeat"
        case .bestRepetitions: return "trophy.fill"
        case .totalDuration: return "timer"
        case .bestDuration: return "stopwatch.fill"
        case .totalDistance: return "point.topleft.down.curvedto.point.bottomright.up"
        case .bestDistance: return "flag.checkered"
        }
    }

    var caption: String {
        switch self {
        case .oneRM: return "Best strength estimate per session"
        case .totalWeight: return "Completed volume per session"
        case .totalSets: return "Completed sets per session"
        case .totalRepetitions: return "Completed reps per session"
        case .bestRepetitions: return "Highest-rep set per session"
        case .totalDuration: return "Completed time per session"
        case .bestDuration: return "Longest completed set per session"
        case .totalDistance: return "Completed distance per session"
        case .bestDistance: return "Longest completed set per session"
        }
    }

    var emptyMessage: String {
        switch self {
        case .oneRM: return "Complete a weighted set with reps to calculate your strength trend."
        case .totalWeight: return "Complete a weighted set to start tracking session volume."
        case .totalSets: return "Complete a set of this exercise to start the chart."
        case .totalRepetitions: return "Complete a set with reps to start the chart."
        case .bestRepetitions: return "Complete a set with reps to track your best set."
        case .totalDuration: return "Complete a timed set to start the chart."
        case .bestDuration: return "Complete a timed set to track your longest effort."
        case .totalDistance: return "Complete a distance set to start the chart."
        case .bestDistance: return "Complete a distance set to track your longest effort."
        }
    }
}

#if DEBUG
struct ExerciseStatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseStatisticsView(exercise: ExerciseStore.shared.exercises.first(where: { $0.everkineticId == 99 })!)
            .mockEnvironment(weightUnit: .metric)
            .preferredColorScheme(.dark)
    }
}
#endif
