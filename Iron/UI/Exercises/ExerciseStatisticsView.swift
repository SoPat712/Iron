//
//  ExerciseStatisticsView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 06.07.19.
//  Rebuilt for Iron's focused exercise progress view.
//

import SwiftUI
import Charts
import CoreData
import WorkoutDataKit

struct ExerciseStatisticsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exercise: Exercise

    @State private var selectedTimeFrame = WorkoutExerciseChartData.TimeFrame.month
    @FetchRequest private var history: FetchedResults<WorkoutExercise>

    init(exercise: Exercise) {
        self.exercise = exercise
        _history = FetchRequest(fetchRequest: WorkoutExercise.historyFetchRequest(of: exercise.uuid))
    }

    private var progress: ExerciseProgressData {
        ExerciseProgressData(exercise: exercise, workoutExercises: Array(history), settingsStore: settingsStore)
    }

    private var completedWorkoutExercises: [WorkoutExercise] {
        history.filter { session in
            (session.numberOfCompletedSets ?? 0) > 0 &&
                (selectedTimeFrame.from.map { (session.workout?.start ?? .distantPast) >= $0 } ?? true)
        }
    }

    private var completedSets: Int {
        completedWorkoutExercises.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
    }

    private var lastSessionDate: Date? {
        completedWorkoutExercises.compactMap { $0.workout?.start }.max()
    }

    var body: some View {
        List {
            Section {
                Picker("Time Frame", selection: $selectedTimeFrame) {
                    ForEach(WorkoutExerciseChartData.TimeFrame.progressCases, id: \.title) { timeFrame in
                        Text(timeFrame.compactTitle).tag(timeFrame)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } footer: {
                Text(selectedTimeFrame.subtitle)
            }

            Section("Overview") {
                LabeledContent("Sessions") {
                    Text(completedWorkoutExercises.count, format: .number)
                        .font(.ironMetric(.body))
                        .foregroundStyle(IronTheme.accent)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }
                LabeledContent("Completed Sets") {
                    Text(completedSets, format: .number)
                        .font(.ironMetric(.body))
                        .foregroundStyle(IronTheme.metricSets)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }
                LabeledContent(
                    "Last Trained",
                    value: lastSessionDate.map(Self.compactDateFormatter.string) ?? "—"
                )
            }

            if completedWorkoutExercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Progress Yet", systemImage: "chart.line.flattrend.xyaxis")
                    } description: {
                        Text("Complete a set of this exercise and Iron will chart strength, volume, sets, and reps here.")
                    } actions: {
                        if selectedTimeFrame != .all {
                            Button("Show All History") {
                                setTimeFrame(.all)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(progress.progressMetrics, id: \.self) { metric in
                    progressSection(metric)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedTimeFrame)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: completedSets)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: completedWorkoutExercises.count)
    }

    private func setTimeFrame(_ timeFrame: WorkoutExerciseChartData.TimeFrame) {
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            selectedTimeFrame = timeFrame
        }
    }

    @ViewBuilder
    private func progressSection(_ metric: ExerciseProgressMetric) -> some View {
        let points = progress.progressPoints(for: metric).filter { point in
            selectedTimeFrame.from.map { point.date >= $0 } ?? true
        }

        Section {
            if points.isEmpty {
                Text(metric.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ExerciseProgressChart(
                    points: points,
                    domainStart: selectedTimeFrame.domainStart(earliestDate: points.first?.date),
                    domainEnd: Date(),
                    valueLabel: { progress.formatted($0, for: metric) },
                    valueText: { value, style, unitStyle in
                        progress.metricText(value, for: metric, style: style, unitStyle: unitStyle)
                    },
                    color: metric.color,
                    dateLabel: { ExerciseProgressData.detailDateFormatter.string(from: $0) }
                )
                .frame(height: 170)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 16))

                if let latest = points.last {
                    LabeledContent("Latest") {
                        progress.metricText(latest.value, for: metric)
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: latest.value)
                    }
                }

                if let first = points.first, let latest = points.last, points.count > 1 {
                    let difference = latest.value - first.value
                    LabeledContent("Change") {
                        if abs(difference) < 0.0001 {
                            Text("No change")
                                .foregroundStyle(.secondary)
                        } else {
                            Label {
                                progress.metricText(difference, for: metric, prefix: difference > 0 ? "+" : "")
                                    .contentTransition(reduceMotion ? .opacity : .numericText())
                                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: difference)
                            } icon: {
                                Image(systemName: difference > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .foregroundStyle(metric.color)
                            }
                        }
                    }
                }
            }
        } header: {
            Label(metric.title, systemImage: metric.icon)
                .foregroundStyle(metric.color)
        } footer: {
            Text(metric.caption)
        }
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

}

/// A single native List card, with at most four metric/history segments.
struct ExerciseInlineProgressView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FetchRequest private var history: FetchedResults<WorkoutExercise>

    let exercise: Exercise
    @State private var selectedTimeFrame = WorkoutExerciseChartData.TimeFrame.month
    @State private var selection: Selection = .metric(.oneRM)
    @State private var alternateMetric: ExerciseProgressMetric?

    private enum Selection: Hashable {
        case metric(ExerciseProgressMetric)
        case history
    }

    init(exercise: Exercise) {
        self.exercise = exercise
        _history = FetchRequest(fetchRequest: WorkoutExercise.historyFetchRequest(of: exercise.uuid))
    }

    private var progress: ExerciseProgressData {
        ExerciseProgressData(exercise: exercise, workoutExercises: Array(history), settingsStore: settingsStore)
    }

    private var metrics: [ExerciseProgressMetric] { progress.progressMetrics }

    private var visibleMetrics: [ExerciseProgressMetric] {
        guard metrics.count > 3 else { return metrics }
        let third = alternateMetric.flatMap { metrics.dropFirst(2).contains($0) ? $0 : nil } ?? metrics[2]
        return Array(metrics.prefix(2)) + [third]
    }

    private var activeSelection: Selection {
        if case .metric(let metric) = selection, !metrics.contains(metric), let first = metrics.first {
            return .metric(first)
        }
        return selection
    }

    private var completedHistory: [WorkoutExercise] {
        history.filter { ($0.numberOfCompletedSets ?? 0) > 0 }
    }

    private var rangedHistory: [WorkoutExercise] {
        let start = selectedTimeFrame.from
        return completedHistory.filter { session in
            start.map { (session.workout?.start ?? .distantPast) >= $0 } ?? true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Progress view", selection: Binding(get: { activeSelection }, set: { selection = $0 })) {
                ForEach(visibleMetrics, id: \.self) { metric in
                    Text(metric.compactTitle).tag(Selection.metric(metric))
                }
                Text("History").tag(Selection.history)
            }
            .pickerStyle(.segmented)

            Picker("Time range", selection: $selectedTimeFrame) {
                ForEach(WorkoutExerciseChartData.TimeFrame.progressCases, id: \.self) { range in
                    Text(range.compactTitle).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if metrics.count > 3 {
                Menu {
                    ForEach(metrics.dropFirst(2), id: \.self) { metric in
                        Button {
                            alternateMetric = metric
                            selection = .metric(metric)
                        } label: {
                            Label(metric.title, systemImage: metric.icon)
                        }
                    }
                } label: {
                    Label("More metrics", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Changes the third progress segment")
            }

            if completedHistory.isEmpty {
                placeholder("No sessions yet — your progress will chart here")
            } else if rangedHistory.isEmpty {
                placeholder("No sessions in this range")
                Button("Show all history") { selectedTimeFrame = .all }
                    .font(.subheadline.weight(.medium))
            } else {
                switch activeSelection {
                case .history:
                    recentHistory
                        .transition(.opacity)
                case .metric(let metric):
                    metricContent(metric)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selection)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedTimeFrame)
        .onChange(of: metrics, initial: true) { _, metrics in
            if case .metric(let metric) = selection, !metrics.contains(metric), let first = metrics.first {
                selection = .metric(first)
            }
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(IronTheme.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @ViewBuilder
    private func metricContent(_ metric: ExerciseProgressMetric) -> some View {
        let data = progress
        let start = selectedTimeFrame.from
        let points = data.progressPoints(for: metric).filter { point in start.map { point.date >= $0 } ?? true }
        if let latest = points.last {
            VStack(alignment: .leading, spacing: 4) {
                Text("Latest · \(metric.title)")
                    .font(.caption)
                    .foregroundStyle(IronTheme.secondaryText)
                data.metricText(latest.value, for: metric, style: .largeTitle, unitStyle: .title3)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .accessibilityLabel("Latest \(metric.title): \(data.formatted(latest.value, for: metric))")
                if let first = points.first, points.count > 1 {
                    let delta = latest.value - first.value
                    Text("\(delta > 0 ? "+" : "")\(data.formatted(delta, for: metric)) since range start")
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                } else {
                    Text("First session in this range")
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                }
            }
            ExerciseProgressChart(
                points: points,
                domainStart: selectedTimeFrame.domainStart(earliestDate: points.first?.date),
                domainEnd: Date(),
                valueLabel: { data.formatted($0, for: metric) },
                valueText: { data.metricText($0, for: metric, style: $1, unitStyle: $2) },
                color: metric.color,
                dateLabel: { ExerciseProgressData.detailDateFormatter.string(from: $0) }
            )
            .frame(height: 200)
            HStack(alignment: .top, spacing: 8) {
                Text(metric.caption)
                    .foregroundStyle(IronTheme.secondaryText)
                Spacer(minLength: 0)
                if points.contains(where: \.isRecord) {
                    Label("PR", systemImage: "circle.fill")
                        .foregroundStyle(IronTheme.metricRecord)
                        .accessibilityLabel("Personal record for this metric")
                }
            }
            .font(.caption2)
        } else {
            placeholder(metric.emptyMessage)
        }
    }

    private var recentHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(rangedHistory.prefix(5))) { session in
                VStack(alignment: .leading, spacing: 10) {
                    if let workout = session.workout {
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            HStack {
                                Text(Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date"))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    if let comment = session.comment, !comment.isEmpty {
                        Text(comment).font(.caption).foregroundStyle(IronTheme.secondaryText)
                    }
                    let sets = session.workoutSets?.array as? [WorkoutSet] ?? []
                    ForEach(Array(sets.enumerated()).filter { $0.element.isCompleted }, id: \.element.id) { index, set in
                        ExerciseHistorySetRow(set: set, index: index)
                    }
                }
                Divider()
            }
            NavigationLink {
                ExerciseHistoryView(exercise: exercise)
                    .navigationTitle("History")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Show all", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(IronTheme.accent)
        }
    }
}

/// Shared session calculations keep standalone and inline progress consistent.
struct ExerciseProgressData {
    let exercise: Exercise
    let workoutExercises: [WorkoutExercise]
    let settingsStore: SettingsStore

    private var completedWorkoutSets: [WorkoutSet] {
        workoutExercises.flatMap { completedSets(for: $0) }
    }

    var progressMetrics: [ExerciseProgressMetric] {
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

        return [.oneRM, .totalWeight, .totalRepetitions, .totalSets]
    }

    func progressPoints(
        for metric: ExerciseProgressMetric
    ) -> [ExerciseProgressPoint] {
        let points: [ExerciseProgressPoint] = workoutExercises.compactMap { workoutExercise in
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
        // Compare with all earlier sessions, never just the visible range.
        var best: Double?
        return points.map { point in
            var point = point
            point.isRecord = best.map { point.value > $0 } ?? false
            best = max(best ?? point.value, point.value)
            return point
        }
    }

    private func sessionDetails(for workoutExercise: WorkoutExercise) -> [Text] {
        let sets = completedSets(for: workoutExercise)
        var details = [detailText(Double(sets.count), for: .totalSets) + detailUnit(sets.count == 1 ? "set" : "sets")]

        let repetitions = sets.reduce(0) { $0 + Int($1.repetitionsValue) }
        if repetitions > 0 {
            details.append(detailText(Double(repetitions), for: .totalRepetitions) + detailUnit("reps"))
        }

        if let kilograms = workoutExercise.totalCompletedWeight, kilograms > 0 {
            let weight = WeightUnit.convert(
                weight: kilograms,
                from: .metric,
                to: settingsStore.weightUnit
            )
            details.append(detailText(weight, for: .totalWeight))
        }

        let duration = sets.compactMap(\.durationValue).reduce(0, +)
        if duration > 0 {
            details.append(detailText(duration, for: .totalDuration))
        }

        let distance = sets.compactMap(\.distanceValue).reduce(0, +)
        if distance > 0 {
            details.append(detailText(distance, for: .totalDistance))
        }

        return Array(details.prefix(4))
    }

    func formatted(
        _ value: Double,
        for metric: ExerciseProgressMetric
    ) -> String {
        let parts = valueParts(value, for: metric)
        return parts.number + (parts.unit.map { " \($0)" } ?? "")
    }

    func metricText(
        _ value: Double,
        for metric: ExerciseProgressMetric,
        prefix: String = "",
        style: Font.TextStyle = .body,
        unitStyle: Font.TextStyle = .caption
    ) -> Text {
        let parts = valueParts(value, for: metric)
        let number = Text(prefix + parts.number)
            .font(.ironMetric(style, weight: .semibold))
            .foregroundColor(metric.color)
        guard let unit = parts.unit else { return number }
        return number + Text(" \(unit)").font(.system(unitStyle)).foregroundColor(IronTheme.secondaryText)
    }

    private func detailText(_ value: Double, for metric: ExerciseProgressMetric) -> Text {
        metricText(value, for: metric, style: .caption, unitStyle: .caption2)
    }

    private func detailUnit(_ unit: String) -> Text {
        Text(" \(unit)").font(.caption2).foregroundColor(IronTheme.secondaryText)
    }

    private func valueParts(
        _ value: Double,
        for metric: ExerciseProgressMetric
    ) -> (number: String, unit: String?) {
        switch metric {
        case .totalDuration, .bestDuration:
            return (formatDuration(value), nil)
        case .totalDistance, .bestDistance:
            let parts = formatDistance(value).split(separator: " ", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : nil)
        case .oneRM, .totalWeight:
            let number = settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
            return (number, settingsStore.weightUnit.unit.symbol)
        case .totalSets, .totalRepetitions, .bestRepetitions:
            return (value.formatted(.number.precision(.fractionLength(0...1))), nil)
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

    static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy jm")
        return formatter
    }()
}

struct ExerciseProgressPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let details: [Text]
    var isRecord = false
}

struct ExerciseProgressChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let points: [ExerciseProgressPoint]
    let domainStart: Date
    let domainEnd: Date
    let valueLabel: (Double) -> String
    let valueText: (Double, Font.TextStyle, Font.TextStyle) -> Text
    let color: Color
    let dateLabel: (Date) -> String

    @State private var selectedDate: Date?
    @State private var hasAppeared = false

    private var yDomain: ClosedRange<Double> {
        0...max((points.map(\.value).max() ?? 0) * 1.12, 1)
    }

    private var chartIdentity: String {
        let start = Calendar.current.startOfDay(for: domainStart).timeIntervalSinceReferenceDate
        return "\(start)|" + points.map { "\($0.id):\($0.value)" }.joined(separator: "|")
    }

    private var selectedPoint: ExerciseProgressPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            calloutHeader

            Group {
                if reduceMotion {
                    progressChart.id(chartIdentity).transition(.opacity)
                } else {
                    progressChart
                }
            }
            .opacity(reduceMotion && !hasAppeared ? 0 : 1)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: chartIdentity)
        }
        .onChange(of: chartIdentity) { _, _ in selectedDate = nil }
        .task {
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }

    private var progressChart: some View {
        Chart {
                ForEach(points) { point in
                    let value = hasAppeared || reduceMotion ? point.value : 0
                    AreaMark(x: .value("Date", point.date), y: .value("Value", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [color.opacity(0.28), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    LineMark(x: .value("Date", point.date), y: .value("Value", value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)

                    PointMark(x: .value("Date", point.date), y: .value("Value", value))
                        .symbolSize(point.isRecord ? 52 : (points.count > 40 ? 0 : 28))
                        .foregroundStyle(point.isRecord ? IronTheme.metricRecord : color)
                        .accessibilityLabel(point.isRecord ? "Personal record" : "Session")
                        .accessibilityValue(valueLabel(point.value))
                }

                if let selectedPoint {
                    RuleMark(x: .value("Date", selectedPoint.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartXScale(domain: domainStart...max(domainEnd, domainStart.addingTimeInterval(60)))
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            valueText(raw, .caption, .caption2)
                                .accessibilityLabel(valueLabel(raw))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartXSelection(value: $selectedDate)
            .accessibilityLabel("Progress chart with \(points.count) sessions")
    }

    @ViewBuilder
    private var calloutHeader: some View {
        if let selectedPoint {
            VStack(alignment: .leading, spacing: 1) {
                Text(dateLabel(selectedPoint.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                valueText(selectedPoint.value, .subheadline, .caption)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                if !selectedPoint.details.isEmpty {
                    selectedPoint.details.dropFirst().reduce(selectedPoint.details[0]) {
                        $0 + Text(" · ").font(.caption2).foregroundColor(IronTheme.secondaryText) + $1
                    }
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }
            }
            .transition(.opacity)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedPoint.id)
        } else {
            Text("Touch and hold the chart to inspect a session.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

enum ExerciseProgressMetric: Hashable {
    case oneRM
    case totalWeight
    case totalSets
    case totalRepetitions
    case bestRepetitions
    case totalDuration
    case bestDuration
    case totalDistance
    case bestDistance

    var color: Color {
        switch self {
        case .oneRM, .totalWeight: return IronTheme.metricVolume
        case .totalSets, .totalRepetitions, .bestRepetitions: return IronTheme.metricSets
        case .totalDuration, .bestDuration, .totalDistance, .bestDistance: return IronTheme.metricTime
        }
    }

    var title: String {
        switch self {
        case .oneRM: return "Estimated 1RM"
        case .totalWeight: return "Volume"
        case .totalSets: return "Total Sets"
        case .totalRepetitions: return "Total Repetitions"
        case .bestRepetitions: return "Best Set Reps"
        case .totalDuration: return "Total Duration"
        case .bestDuration: return "Best Duration"
        case .totalDistance: return "Total Distance"
        case .bestDistance: return "Best Distance"
        }
    }

    var compactTitle: String {
        switch self {
        case .oneRM: return "1RM"
        case .totalWeight: return "Volume"
        case .totalSets: return "Sets"
        case .totalRepetitions: return "Reps"
        case .bestRepetitions: return "Best reps"
        case .totalDuration: return "Time"
        case .bestDuration: return "Best time"
        case .totalDistance: return "Distance"
        case .bestDistance: return "Best dist."
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
