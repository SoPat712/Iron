//
//  FeedView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 19.06.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import Charts
import CoreData
import Combine
import PhotosUI
import UIKit
import WorkoutDataKit

struct FeedView : View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    @EnvironmentObject private var sceneState: SceneState
    @ObservedObject private var bodyMetricsStore = BodyMetricsStore.shared
    @EnvironmentObject private var pinnedChartsStore: PinnedChartsStore

    @FetchRequest(fetchRequest: FeedView.workoutFetchRequest) private var workouts: FetchedResults<Workout>
    @FetchRequest(fetchRequest: FeedView.currentWorkoutFetchRequest) private var currentWorkouts: FetchedResults<Workout>

    @State private var showingMeasurements = false
    @State private var showingChartSelector = false
    @State private var showingChartEditor = false
    @State private var persistenceError: String?

    static var workoutFetchRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return request
    }

    static var currentWorkoutFetchRequest: NSFetchRequest<Workout> {
        Workout.currentWorkoutFetchRequest
    }

    private var completedWorkouts: [Workout] {
        workouts.filter { $0.hasCompletedSets ?? false }
    }

    private var recentWorkouts: [Workout] {
        Array(completedWorkouts.prefix(8))
    }

    private var workoutsThisWeek: [Workout] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return completedWorkouts.filter {
            guard let date = $0.start else { return false }
            return date >= week.start && date < week.end
        }
    }

    private var completedSetsThisWeek: Int {
        workoutsThisWeek.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
    }

    private var volumeThisWeek: Double {
        workoutsThisWeek.reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) }
    }

    private var trainingStreak: Int {
        var streak = 0
        var cursor = Date()
        var weeksChecked = 0
        let calendar = Calendar.current
        while weeksChecked < 520, let interval = calendar.dateInterval(of: .weekOfYear, for: cursor) {
            let trained = completedWorkouts.contains { workout in
                guard let date = workout.start else { return false }
                return interval.contains(date)
            }
            if trained {
                streak += 1
            } else if weeksChecked > 0 || !interval.contains(Date()) {
                break
            }
            weeksChecked += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start) else { break }
            cursor = previous
        }
        return streak
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private func startEmptyWorkout() {
        do {
            _ = try Workout.startNew(in: managedObjectContext)
            sceneState.selectedTab = .workout
            sceneState.isCurrentWorkoutExpanded = true
        } catch {
            persistenceError = "The workout was not started. \(error.localizedDescription)"
        }
    }

    private var weekSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                weekMetrics

                WeeklyVolumeChart(
                    days: weekVolumeByDay,
                    unit: settingsStore.weightUnit.unit.symbol,
                    valueLabel: { compactWeight($0) }
                )

                Button {
                    if currentWorkouts.isEmpty {
                        startEmptyWorkout()
                    } else {
                        sceneState.selectedTab = .workout
                        sceneState.isCurrentWorkoutExpanded = true
                    }
                } label: {
                    Label(
                        currentWorkouts.isEmpty ? "Start Workout" : "Resume Workout",
                        systemImage: "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .ironProminentGlassButtonStyle()
                .frame(minHeight: 50)
            }
            .padding(16)
            .ironLiquidGlassSurface(cornerRadius: IronTheme.heroCornerRadius)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text(greeting)
                .font(.headline)
                .foregroundStyle(IronTheme.secondaryText)
                .textCase(nil)
                .padding(.bottom, 8)
        } footer: {
            if let comparison = weekComparisonText {
                comparison
                    .font(.footnote)
                    .foregroundStyle(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weekMetrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            weekMetric(
                value: "\(workoutsThisWeek.count)", label: "Workouts",
                systemImage: "figure.strengthtraining.traditional",
                tint: IronTheme.accent, container: IronTheme.accentSoft, index: 0
            )
            weekMetric(
                value: "\(completedSetsThisWeek)", label: "Sets",
                systemImage: "checklist",
                tint: IronTheme.metricSets, container: IronTheme.metricSetsContainer, index: 1
            )
            weekMetric(
                value: compactWeight(volumeThisWeek), label: "Volume",
                unit: settingsStore.weightUnit.unit.symbol, systemImage: "scalemass.fill",
                tint: IronTheme.metricVolume, container: IronTheme.metricVolumeContainer, index: 2
            )
        }
    }

    private func weekMetric(
        value: String,
        label: String,
        unit: String? = nil,
        systemImage: String,
        tint: Color,
        container: Color,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(container))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // Text can wrap the unit onto another line at large type sizes.
                (Text(value).font(.ironMetric(.title2)).foregroundColor(tint)
                 + Text(unit.map { " " + $0 } ?? "")
                    .font(.footnote.weight(.semibold)).foregroundColor(IronTheme.secondaryText))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: value)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironStaggeredEntrance(index: index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value)\(unit.map { " " + $0 } ?? "") \(label)")
    }

    /// Volume per weekday for the current week, including untrained days so the
    /// chart keeps a stable seven-column shape.
    private var weekVolumeByDay: [DayVolume] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let volume = completedWorkouts
                .filter { calendar.isDate($0.start ?? .distantPast, inSameDayAs: day) }
                .reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) }
            return DayVolume(date: day, volume: volume, isFuture: day > Date())
        }
    }

    private var volumeLastWeek: Double {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: thisWeek.start),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: previousDay) else { return 0 }
        return completedWorkouts
            .filter { lastWeek.contains($0.start ?? .distantPast) }
            .reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) }
    }

    private var weekComparisonText: Text? {
        guard volumeLastWeek > 0 else { return nil }
        let change = (volumeThisWeek - volumeLastWeek) / volumeLastWeek * 100
        guard abs(change) > 3 else {
            return Text("Volume is about the same as last week")
        }
        let direction = change > 0 ? "up" : "down"
        return Text("Volume is \(direction) ")
            + Text("\(Int(abs(change).rounded()))%")
                .font(.ironMetric(.footnote, weight: .semibold))
                .foregroundColor(change > 0 ? IronTheme.metricVolume : IronTheme.secondaryText)
            + Text(" on last week")
    }

    /// Share of completed sets by muscle group over the last month, so the user
    /// can see what they have been neglecting.
    private var muscleFocus: [MuscleFocusSlice] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -28, to: Date()) else { return [] }
        var setsByGroup: [String: Int] = [:]
        for workout in completedWorkouts where (workout.start ?? .distantPast) >= cutoff {
            let workoutExercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
            for workoutExercise in workoutExercises {
                let group = workoutExercise.exercise(in: exerciseStore.exercises)?.muscleGroup ?? "other"
                let sets = (workoutExercise.workoutSets?.array as? [WorkoutSet] ?? [])
                    .filter { $0.isCompleted == true }
                    .count
                guard sets > 0 else { continue }
                setsByGroup[group, default: 0] += sets
            }
        }
        let total = setsByGroup.values.reduce(0, +)
        guard total > 0 else { return [] }
        return setsByGroup
            .map { MuscleFocusSlice(muscleGroup: $0.key, sets: $0.value, share: Double($0.value) / Double(total)) }
            .sorted { $0.sets > $1.sets }
    }

    private var muscleFocusSection: some View {
        Section {
            if muscleFocus.isEmpty {
                Text("Complete a few workouts to see which muscle groups you train most.")
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.secondaryText)
            } else {
                ForEach(muscleFocus.prefix(5)) { slice in
                    MuscleFocusRow(slice: slice)
                }
            }
        } header: {
            Text("Muscle Focus")
        } footer: {
            if let top = muscleFocus.first {
                Text("\(top.muscleGroup.capitalized) leads your last 4 weeks at ")
                + Text("\(Int((top.share * 100).rounded()))%")
                    .font(.ironMetric(.footnote, weight: .semibold))
                + Text(" of completed sets.")
            } else {
                Text("Based on completed sets over the last 4 weeks.")
            }
        }
    }

    private var calendarSection: some View {
        Section {
            HomeTrainingCalendar(workouts: completedWorkouts)
                .padding(.vertical, 6)

            NavigationLink("Open Training Calendar") {
                WorkoutCalendarView()
            }
        } header: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Last 4 Weeks")
                    Spacer()
                    streakChip
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 4 Weeks")
                    streakChip
                }
            }
        } footer: {
            if trainingStreak == 0 {
                Text("Train this week to start a streak.")
            } else {
                Text("\(trainingStreak)").font(.ironMetric(.footnote, weight: .semibold))
                + Text(" week streak.")
            }
        }
    }

    @ViewBuilder
    private var streakChip: some View {
        let streak = trainingStreak
        if streak >= 2 {
            Label {
                Text("\(streak)-week streak")
            } icon: {
                Image(systemName: "flame.fill")
            }
            .font(.ironMetric(.caption))
            .foregroundStyle(IronTheme.accent)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(IronTheme.accentSoft, in: Capsule())
            .textCase(nil)
            .accessibilityLabel("\(streak) week training streak")
        }
    }

    private func compactWeight(_ kilograms: Double) -> String {
        let value = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        return WorkoutPreviewFormatting.volume(value)
    }

    /// Body lives on Home, not in Settings: measurements are training data, not
    /// a device preference.
    private var measurementsSection: some View {
        Section {
            ForEach(homeMeasurementKinds, id: \.self) { kind in
                LabeledContent(kind.title) {
                    HStack(spacing: 6) {
                        if let change = measurementChange(kind) {
                            Label(
                                String(format: "%.1f", abs(change)),
                                systemImage: change > 0 ? "arrow.up" : "arrow.down"
                            )
                            .font(.ironMetric(.caption, weight: .semibold))
                            .foregroundStyle(IronTheme.metricBody)
                        }
                        measurementValue(kind)
                    }
                }
            }

            NavigationLink("Measurements & Trends") {
                BodyMeasurementsDashboardView(store: bodyMetricsStore)
                    .environmentObject(settingsStore)
                    .ironScreen()
            }

            Button(bodyMetricsStore.entries.isEmpty ? "Log First Measurement" : "Log Measurement") {
                showingMeasurements = true
            }
        } header: {
            Text("Body")
        } footer: {
            if let latest = bodyMetricsStore.latest {
                Text("Last logged \(latest.date.formatted(.relative(presentation: .named))).")
            } else {
                Text("Weight, body fat, and tape measurements stay on this device.")
            }
        }
    }

    private var homeMeasurementKinds: [BodyMeasurementKind] {
        [.bodyWeight, .bodyFat, .waist]
    }

    @ViewBuilder
    private func measurementValue(_ kind: BodyMeasurementKind) -> some View {
        if let value = bodyMetricsStore.latestValue(for: kind) {
            let display = kind.displayValue(from: value, weightUnit: settingsStore.weightUnit)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", display))
                    .font(.ironMetric(.body))
                    .foregroundStyle(IronTheme.metricBody)
                Text(kind.unitLabel(weightUnit: settingsStore.weightUnit))
                    .font(.caption)
                    .foregroundStyle(IronTheme.secondaryText)
            }
        } else {
            Text("—").font(.ironMetric(.body))
        }
    }

    /// Change between the two most recent entries that recorded this kind, in
    /// display units, so the row shows direction rather than a bare number.
    private func measurementChange(_ kind: BodyMeasurementKind) -> Double? {
        let values = bodyMetricsStore.entries
            .compactMap { $0[kind] }
            .prefix(2)
        guard values.count == 2 else { return nil }
        let unit = settingsStore.weightUnit
        let change = kind.displayValue(from: values[0], weightUnit: unit)
            - kind.displayValue(from: values[1], weightUnit: unit)
        return abs(change) < 0.05 ? nil : change
    }

    private var pinnedChartsSection: some View {
        Section {
            if pinnedChartsStore.pinnedCharts.isEmpty {
                Button("Pin an Exercise Chart") { showingChartSelector = true }
            } else {
                ForEach(pinnedChartsStore.pinnedCharts, id: \.self) { chart in
                    if let exercise = exerciseStore.find(with: chart.exerciseUuid) {
                        PinnedExerciseChartRow(exercise: exercise, measurementType: chart.measurementType)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
            }
        } header: {
            HStack {
                Label("Pinned Charts", systemImage: "pin.fill")
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : pinnedChartsStore.pinnedCharts.count)
                Spacer()
                Menu("Chart Options", systemImage: "ellipsis.circle") {
                    Button("Pin Chart", systemImage: "pin") { showingChartSelector = true }
                    if !pinnedChartsStore.pinnedCharts.isEmpty {
                        Button("Edit Pins", systemImage: "slider.horizontal.3") { showingChartEditor = true }
                    }
                }
                .labelStyle(.iconOnly)
                .textCase(nil)
            }
        }
    }

    private var recentSection: some View {
        Section("Recent Training") {
            if recentWorkouts.isEmpty {
                Text("Completed workouts build a private training timeline here.")
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.secondaryText)
            } else {
                ForEach(recentWorkouts.prefix(3)) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.displayTitle(in: exerciseStore.exercises))
                                .font(.headline)
                            Text(WorkoutPreviewFormatting.date(workout.start))
                                .font(.caption)
                                .foregroundStyle(IronTheme.secondaryText)
                        }
                    }
                    .badge(Text("\(workout.numberOfCompletedSets ?? 0) sets")
                        .font(.ironMetric(.caption))
                        .foregroundColor(IronTheme.metricSets))
                }

                Button("See All History") {
                    sceneState.selectedTab = .history
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                weekSection
                calendarSection
                recentSection
                muscleFocusSection
                measurementsSection
                pinnedChartsSection
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, IronTheme.floatingWorkoutBottomClearance, for: .scrollContent)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showingMeasurements) {
                BodyMeasurementsView(store: bodyMetricsStore)
                    .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showingChartSelector) {
                PinnedChartSelectorSheet(exercises: exerciseStore.shownExercises) { chart in
                    pinnedChartsStore.pinnedCharts.append(chart)
                }
                .environmentObject(pinnedChartsStore)
                .environmentObject(exerciseStore)
            }
            .sheet(isPresented: $showingChartEditor) {
                PinnedChartEditSheet()
                    .environmentObject(pinnedChartsStore)
                    .environmentObject(exerciseStore)
            }
            .alert("Workout Not Started", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
            .sensoryFeedback(.error, trigger: persistenceError) { _, error in error != nil }
        }
    }
}

/// Home owns its presentation of the rolling 28-day calendar. The standalone
/// calendar keeps its existing implementation and navigation.
private struct HomeTrainingCalendar: View {
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .subheadline) private var dayDiameter: CGFloat = 34
    let workouts: [Workout]

    private var cellSize: CGFloat { max(IronTheme.controlHeight, dayDiameter + 10) }

    private var days: [Date?] {
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -27, to: today),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDay),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let count = calendar.dateComponents([.day], from: firstWeek.start, to: lastWeek.end).day ?? 0
        return (0..<count).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstWeek.start),
                  day >= firstDay, day <= today else { return nil }
            return day
        }
    }

    private func workouts(on day: Date) -> [Workout] {
        workouts.filter { workout in
            workout.start.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }

    var body: some View {
        let days = days
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 4) {
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IronTheme.secondaryText)
                            .frame(width: cellSize)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(0..<(days.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            if let day = days[week * 7 + weekday] {
                                dayCell(day)
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .preference(key: WorkoutsLast28DaysKey.self, value: days.compactMap { $0 }.reduce(0) { $0 + workouts(on: $1).count })
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let sessions = workouts(on: day)
        let date = day.formatted(date: .complete, time: .omitted)
        if let workout = sessions.first {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                dayCircle(day, trained: true)
                    .frame(width: cellSize, height: cellSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(date), \(sessions.count) workout\(sessions.count == 1 ? "" : "s")")
        } else {
            dayCircle(day, trained: false)
                .frame(width: cellSize, height: cellSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(date), rest day")
        }
    }

    private func dayCircle(_ day: Date, trained: Bool) -> some View {
        Text("\(calendar.component(.day, from: day))")
            .font(.ironMetric(.subheadline))
            .foregroundStyle(trained ? IronTheme.onAccent : IronTheme.secondaryText)
            .frame(width: dayDiameter, height: dayDiameter)
            .background(trained ? IronTheme.accent : IronTheme.tertiaryFill, in: Circle())
            .overlay {
                if !trained && calendar.isDateInToday(day) {
                    Circle().strokeBorder(IronTheme.accent, lineWidth: 1.5)
                }
            }
    }
}

struct DayVolume: Identifiable {
    var id: Date { date }
    let date: Date
    let volume: Double
    let isFuture: Bool

    var weekdayInitial: String {
        date.formatted(.dateTime.weekday(.narrow))
    }
}

/// Seven fixed columns for the current week. Untrained days keep a faint
/// placeholder bar so the week always reads as a week.
private struct WeeklyVolumeChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var selectedDayID: Date?

    let days: [DayVolume]
    let unit: String
    let valueLabel: (Double) -> String

    private var maxVolume: Double {
        let maximum = days.map(\.volume).max() ?? 0
        return maximum > 0 ? maximum : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Track", maxVolume),
                    width: .fixed(22)
                )
                .clipShape(Capsule())
                .foregroundStyle(IronTheme.tertiaryFill)
                .accessibilityHidden(true)

                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Volume", hasAppeared || reduceMotion ? day.volume : 0),
                    width: .fixed(22)
                )
                .clipShape(Capsule())
                .foregroundStyle(IronTheme.accent)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue("\(valueLabel(day.volume)) \(unit)")
            }
            .chartYScale(domain: 0...maxVolume)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            let isToday = Calendar.current.isDateInToday(date)
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? IronTheme.accent : IronTheme.secondaryText)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in plot.frame(height: 80) }
            .frame(height: 104)
            .opacity(!reduceMotion || hasAppeared ? 1 : 0)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: days.map(\.volume))
            .onAppear { hasAppeared = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume by day this week")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction(adjustDay)
            .sensoryFeedback(.selection, trigger: selectedDayID)

            if let best = days.max(by: { $0.volume < $1.volume }), best.volume > 0 {
                (Text("Best day \(best.date.formatted(.dateTime.weekday(.wide))) at ")
                 + Text(valueLabel(best.volume))
                    .font(.ironMetric(.footnote))
                    .foregroundColor(IronTheme.metricVolume)
                 + Text(" \(unit)").font(.caption).foregroundColor(IronTheme.secondaryText))
                    .font(.footnote)
                    .foregroundStyle(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: best.volume)
            }
        }
    }

    private var accessibilitySummary: String {
        let selectedDays = selectedDayID.map { id in days.filter { $0.id == id } } ?? days
        return selectedDays.map {
            "\($0.date.formatted(.dateTime.weekday(.wide))), \(valueLabel($0.volume)) \(unit)"
        }.joined(separator: "; ")
    }

    private func adjustDay(_ direction: AccessibilityAdjustmentDirection) {
        guard !days.isEmpty else { return }
        let current = selectedDayID.flatMap { id in days.firstIndex { $0.id == id } }
        switch direction {
        case .increment: selectedDayID = days[min((current ?? -1) + 1, days.count - 1)].id
        case .decrement: selectedDayID = days[max((current ?? days.count) - 1, 0)].id
        @unknown default: break
        }
    }
}

struct MuscleFocusSlice: Identifiable {
    var id: String { muscleGroup }
    let muscleGroup: String
    let sets: Int
    let share: Double
}

private struct MuscleFocusRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let slice: MuscleFocusSlice

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        VStack(alignment: .leading, spacing: 6) {
            layout {
                Text(slice.muscleGroup.capitalized)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                (Text("\(slice.sets)").font(.ironMetric(.subheadline, weight: .semibold))
                    .foregroundColor(IronTheme.metricSets)
                 + Text(" sets").font(.caption).foregroundColor(IronTheme.secondaryText))
            }

            ProgressView(value: slice.share)
                .tint(IronTheme.metricSets)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slice.muscleGroup), \(slice.sets) sets, \(Int((slice.share * 100).rounded())) percent")
    }
}

struct BodyMeasurementsDashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var store: BodyMetricsStore

    @State private var selectedKind: BodyMeasurementKind = .bodyWeight
    @State private var selectedTimeFrame = WorkoutExerciseChartData.TimeFrame.month
    @State private var showingEditor = false
    @State private var editorEntryID: UUID?
    @State private var entryToDelete: BodyMeasurementEntry?

    private let featuredKinds: [BodyMeasurementKind] = [
        .bodyWeight, .bodyFat, .waist, .chest, .leftBicep, .rightBicep
    ]
    private let coreKinds: [BodyMeasurementKind] = [.bodyWeight, .bodyFat, .height]
    private let torsoKinds: [BodyMeasurementKind] = [.neck, .shoulders, .chest, .waist, .abdomen, .hips]
    private let limbKinds: [BodyMeasurementKind] = [
        .leftBicep, .rightBicep, .leftForearm, .rightForearm,
        .leftThigh, .rightThigh, .leftCalf, .rightCalf
    ]

    private var photoEntries: [BodyMeasurementEntry] {
        store.entries.filter { $0.progressPhotoData != nil }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Latest Entry", value: latestEntrySubtitle)
                ForEach(coreKinds) { kind in
                    LabeledContent(kind.title) {
                        measurementValue(store.latestValue(for: kind), kind: kind)
                    }
                }
            } header: {
                Text("Overview")
            } footer: {
                Text("Measurements stay on this device unless you sync them with Apple Health.")
            }

            if !photoEntries.isEmpty {
                progressPhotosSection
            }

            trendSection
            latestMeasurementsSection
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Measures")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log Measurements", systemImage: "plus") { openEditor() }
                    .labelStyle(.iconOnly)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $showingEditor) {
            BodyMeasurementsView(store: store, initialEntryID: editorEntryID)
                .environmentObject(settingsStore)
        }
        .confirmationDialog(
            "Delete measurement entry?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                guard let entry = entryToDelete else { return }
                entryToDelete = nil
                store.delete(id: entry.id)
            }
            Button("Cancel", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            if let entry = entryToDelete {
                Text("This removes the measurements saved on \(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)).")
            }
        }
    }

    private var latestEntrySubtitle: String {
        guard let latest = store.latest else { return "No entries yet" }
        return RelativeDateTimeFormatter().localizedString(for: latest.date, relativeTo: Date())
    }

    private var progressPhotosSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photoEntries) { entry in
                        Button(action: { openEditor(entry.id) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let data = entry.progressPhotoData,
                                   let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 132, height: 158)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }

                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 132, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Progress photo from \(entry.date.formatted(date: .long, time: .omitted))")
                        .accessibilityHint("Opens this measurement entry")
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
        } header: {
            Text("Progress Photos")
        } footer: {
            Text("\(photoEntries.count) photo\(photoEntries.count == 1 ? "" : "s") stored privately on this device.")
        }
    }

    private var trendSection: some View {
        Section {
            Picker("Measurement", selection: $selectedKind) {
                ForEach(featuredKinds) { kind in
                    Text(compactTitle(for: kind)).tag(kind)
                }
            }

            Picker("Range", selection: $selectedTimeFrame) {
                ForEach(WorkoutExerciseChartData.TimeFrame.allCases, id: \.title) { timeFrame in
                    Text(timeFrame.compactTitle).tag(timeFrame)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if trendSamples.isEmpty {
                ContentUnavailableView {
                    Label("No \(selectedKind.title) Data", systemImage: "chart.line.flattrend.xyaxis")
                } description: {
                    Text("Add this measurement to start its private trend.")
                }
                .listRowBackground(Color.clear)
            } else {
                BodyMeasurementTrendChart(
                    samples: trendSamples,
                    measurementTitle: selectedKind.title,
                    domainStart: selectedTimeFrame.domainStart(earliestDate: trendSamples.first?.date),
                    domainEnd: Date(),
                    valueLabel: { value in
                        let formatted = String(format: value >= 100 ? "%.0f" : "%.1f", value)
                        return "\(formatted) \(selectedKind.unitLabel(weightUnit: settingsStore.weightUnit))"
                    }
                )
                .frame(height: 170)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 16))

                LabeledContent("Latest") {
                    measurementValue(store.latestValue(for: selectedKind), kind: selectedKind)
                }

                if let delta = selectedDelta {
                    LabeledContent("Change") {
                        Label(delta.text, systemImage: delta.symbol)
                            .font(.ironMetric(.body, weight: .semibold))
                            .foregroundStyle(delta.color)
                    }
                }
            }
        } header: {
            Text("Progress")
        }
    }

    private var latestMeasurementsSection: some View {
        Group {
            measurementGroup(title: "Core", kinds: coreKinds)
            measurementGroup(title: "Torso", kinds: torsoKinds)
            measurementGroup(title: "Arms & Legs", kinds: limbKinds)
        }
    }

    private func measurementGroup(title: String, kinds: [BodyMeasurementKind]) -> some View {
        Section(title) {
            ForEach(kinds) { kind in
                Button {
                    selectedKind = kind
                } label: {
                    HStack {
                        Label(kind.title, systemImage: icon(for: kind))
                            .foregroundStyle(.primary)
                        Spacer()
                        measurementValue(store.latestValue(for: kind), kind: kind)
                        if selectedKind == kind {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityHint("Charts \(kind.title) in the progress section")
            }
        }
    }

    private var historySection: some View {
        Section {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("No History Yet", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Your saved entries appear here and remain private.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.entries) { entry in
                    Button {
                        openEditor(entry.id)
                    } label: {
                        HStack(spacing: 12) {
                            if let data = entry.progressPhotoData,
                               let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short))
                                    .foregroundStyle(.primary)
                                Text(entrySummary(entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let weight = entry[.bodyWeight] {
                                measurementValue(weight, kind: .bodyWeight)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            entryToDelete = entry
                        }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { openEditor(entry.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                    }
                }
            }
        } header: {
            Text("History")
        } footer: {
            if !store.entries.isEmpty {
                Text("\(store.entries.count) entr\(store.entries.count == 1 ? "y" : "ies")")
            }
        }
    }

    private var trendSamples: [BodyMeasurementTrendSample] {
        let start = selectedTimeFrame.from
        return store.entries.reversed().compactMap { entry in
            if let start, entry.date < start { return nil }
            guard let canonical = entry[selectedKind] else { return nil }
            return BodyMeasurementTrendSample(
                id: entry.id,
                date: entry.date,
                value: selectedKind.displayValue(from: canonical, weightUnit: settingsStore.weightUnit)
            )
        }
    }

    private var selectedDelta: (text: String, symbol: String, color: Color)? {
        guard trendSamples.count >= 2 else { return nil }
        let delta = trendSamples[trendSamples.count - 1].value - trendSamples[trendSamples.count - 2].value
        guard abs(delta) >= 0.001 else {
            return ("No change", "minus", Color.secondary)
        }
        let format = abs(delta) >= 10 ? "%.0f" : "%.1f"
        let text = (delta > 0 ? "+" : "") + String(format: format, delta)
        return (text, delta > 0 ? "arrow.up.right" : "arrow.down.right", IronTheme.metricBody)
    }

    private func latestEntry(for kind: BodyMeasurementKind) -> BodyMeasurementEntry? {
        store.entries.first { $0[kind] != nil }
    }

    private func measurementValue(_ canonical: Double?, kind: BodyMeasurementKind) -> Text {
        guard let canonical else { return Text("—").font(.ironMetric(.body)).foregroundColor(IronTheme.secondaryText) }
        return Text(displayText(value: canonical, kind: kind, includeUnit: false))
            .font(.ironMetric(.body)).foregroundColor(IronTheme.primaryText)
            + Text(" \(kind.unitLabel(weightUnit: settingsStore.weightUnit))")
                .font(.caption).foregroundColor(IronTheme.secondaryText)
    }

    private func displayText(value canonical: Double, kind: BodyMeasurementKind, includeUnit: Bool) -> String {
        let display = kind.displayValue(from: canonical, weightUnit: settingsStore.weightUnit)
        let value = String(format: display >= 100 ? "%.0f" : "%.1f", display)
        return includeUnit ? "\(value) \(kind.unitLabel(weightUnit: settingsStore.weightUnit))" : value
    }

    private func latestDateText(for kind: BodyMeasurementKind) -> String {
        guard let entry = latestEntry(for: kind) else { return "Not logged" }
        return RelativeDateTimeFormatter().localizedString(for: entry.date, relativeTo: Date())
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private func compactTitle(for kind: BodyMeasurementKind) -> String {
        switch kind {
        case .bodyWeight: return "Weight"
        case .bodyFat: return "Body fat"
        case .leftBicep: return "L. bicep"
        case .rightBicep: return "R. bicep"
        default: return kind.title
        }
    }

    private func icon(for kind: BodyMeasurementKind) -> String {
        switch kind {
        case .bodyWeight: return "scalemass.fill"
        case .bodyFat: return "percent"
        case .height: return "ruler.fill"
        case .neck, .shoulders, .chest, .waist, .abdomen, .hips: return "figure.arms.open"
        default: return "ruler"
        }
    }

    private func entrySummary(_ entry: BodyMeasurementEntry) -> String {
        var parts: [String] = []
        if !entry.values.isEmpty {
            parts.append("\(entry.values.count) measurement\(entry.values.count == 1 ? "" : "s")")
        }
        if entry.progressPhotoData != nil {
            parts.append("Progress photo")
        }
        return parts.joined(separator: " · ")
    }

    private func openEditor(_ entryID: UUID? = nil) {
        editorEntryID = entryID
        showingEditor = true
    }
}

private struct BodyMeasurementTrendSample: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

private struct BodyMeasurementTrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let samples: [BodyMeasurementTrendSample]
    let measurementTitle: String
    var domainStart: Date? = nil
    var domainEnd: Date? = nil
    let valueLabel: (Double) -> String

    @State private var selectedDate: Date?

    private var firstDate: Date { domainStart ?? samples.first?.date ?? Date() }
    private var lastDate: Date { domainEnd ?? samples.last?.date ?? firstDate.addingTimeInterval(60) }

    private var selectedSample: BodyMeasurementTrendSample? {
        guard let selectedDate else { return nil }
        return samples.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedSample {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedSample.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(valueLabel(selectedSample.value))
                        .font(.ironMetric(.subheadline))
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedDate)
                        .foregroundStyle(IronTheme.metricBody)
                }
            } else {
                Text("Touch and hold the chart to inspect an entry.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(samples) { sample in
                    AreaMark(x: .value("Date", sample.date), y: .value(measurementTitle, hasAppeared || reduceMotion ? sample.value : 0))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [IronTheme.metricBody.opacity(0.28), IronTheme.metricBody.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    LineMark(x: .value("Date", sample.date), y: .value(measurementTitle, hasAppeared || reduceMotion ? sample.value : 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(IronTheme.metricBody)

                    PointMark(x: .value("Date", sample.date), y: .value(measurementTitle, hasAppeared || reduceMotion ? sample.value : 0))
                        .symbolSize(samples.count > 40 ? 0 : 28)
                        .foregroundStyle(IronTheme.metricBody)
                }

                if let selectedSample {
                    RuleMark(x: .value("Date", selectedSample.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYScale(domain: 0...max((samples.map(\.value).max() ?? 0) * 1.1, 1))
            .opacity(!reduceMotion || hasAppeared ? 1 : 0)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
            .onAppear { hasAppeared = true }
            .chartXScale(domain: firstDate...max(lastDate, firstDate.addingTimeInterval(60)))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(valueLabel(raw))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartXSelection(value: $selectedDate)
            .accessibilityLabel("\(measurementTitle) trend with \(samples.count) entries")
        }
    }
}

struct BodyMeasurementsView: View {
    private struct HealthImportNotice: Identifiable {
        let id = UUID()
        let isError: Bool
        let message: String
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var store: BodyMetricsStore

    @State private var date = Date()
    @State private var inputs: [String: String] = [:]
    @State private var originalValues: [String: Double] = [:]
    @State private var editedKinds: Set<String> = []
    @State private var loadedInitialValues = false
    @State private var syncingHealth = false
    @State private var editingEntryID: UUID?
    @State private var healthImportNotice: HealthImportNotice?
    @State private var measurementToDelete: BodyMeasurementEntry?
    @State private var progressPhotoItem: PhotosPickerItem?
    @State private var progressPhotoData: Data?
    @State private var isLoadingProgressPhoto = false
    @State private var progressPhotoError: String?
    @State private var measurementSaveFailed = false
    @State private var isEditingFields = true

    let initialEntryID: UUID?

    private let primaryKinds: [BodyMeasurementKind] = [.bodyWeight, .bodyFat, .height]
    private let torsoKinds: [BodyMeasurementKind] = [.neck, .shoulders, .chest, .waist, .abdomen, .hips]
    private let limbKinds: [BodyMeasurementKind] = [.leftBicep, .rightBicep, .leftForearm, .rightForearm, .leftThigh, .rightThigh, .leftCalf, .rightCalf]

    init(store: BodyMetricsStore, initialEntryID: UUID? = nil) {
        self.store = store
        self.initialEntryID = initialEntryID
    }

    private var measurementDeleteMessage: String {
        guard let entry = measurementToDelete else {
            return "This removes the saved measurements."
        }
        let date = DateFormatter.localizedString(
            from: entry.date,
            dateStyle: .medium,
            timeStyle: .short
        )
        return "This removes the measurements saved on \(date)."
    }

    private var isReviewingEntry: Bool {
        editingEntryID != nil && !isEditingFields
    }

    private var recordedKinds: [BodyMeasurementKind] {
        BodyMeasurementKind.allCases.filter { kind in
            if let raw = inputs[kind.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return true
            }
            return originalValues[kind.rawValue] != nil
        }
    }

    private func valueBinding(for kind: BodyMeasurementKind) -> Binding<String> {
        Binding(
            get: { inputs[kind.rawValue] ?? "" },
            set: {
                inputs[kind.rawValue] = sanitizedMeasurementInput($0)
                editedKinds.insert(kind.rawValue)
            }
        )
    }

    private func editableMeasurementText(_ value: Double) -> String {
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private func sanitizedMeasurementInput(_ input: String) -> String {
        var result = ""
        var hasDecimalSeparator = false

        for character in input.replacingOccurrences(of: ",", with: ".") {
            if character.isNumber {
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }
        return result
    }

    private func isInvalidInput(_ kind: BodyMeasurementKind) -> Bool {
        guard let raw = inputs[kind.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return false }
        return kind.validatedCanonicalValue(from: raw, weightUnit: settingsStore.weightUnit) == nil
    }

    private var hasInvalidInputs: Bool {
        BodyMeasurementKind.allCases.contains(where: isInvalidInput)
    }

    private func field(_ kind: BodyMeasurementKind) -> some View {
        let invalid = isInvalidInput(kind)

        return LabeledContent(kind.title) {
            HStack(spacing: 4) {
                TextField(latestPlaceholder(for: kind), text: valueBinding(for: kind))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.ironMetric(.body))
                    .foregroundStyle(invalid ? IronTheme.danger : IronTheme.primaryText)
                    .accessibilityLabel("\(kind.title), \(kind.unitLabel(weightUnit: settingsStore.weightUnit))")
                    .accessibilityHint(invalid ? "Enter a number greater than zero" : "Numeric measurement")

                Text(kind.unitLabel(weightUnit: settingsStore.weightUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    private func fieldsSection(title: String, kinds: [BodyMeasurementKind]) -> some View {
        Section(title) {
            ForEach(kinds) { kind in
                field(kind)
            }
        }
    }

    private func loadLatestValuesIfNeeded() {
        guard !loadedInitialValues else { return }
        loadedInitialValues = true
        // A new entry is intentionally sparse. Previous values remain visible
        // as placeholders, but are not silently written again when the user
        // changes only one measurement.
        inputs.removeAll()
        originalValues.removeAll()
        editedKinds.removeAll()
        isEditingFields = true
    }

    private func loadInitialValuesIfNeeded() {
        guard !loadedInitialValues else { return }
        if let initialEntryID,
           let entry = store.entries.first(where: { $0.id == initialEntryID }) {
            loadedInitialValues = true
            load(entry)
        } else {
            loadLatestValuesIfNeeded()
        }
    }

    private func load(_ entry: BodyMeasurementEntry) {
        editingEntryID = entry.id
        date = entry.date
        progressPhotoData = entry.progressPhotoData
        progressPhotoItem = nil
        progressPhotoError = nil
        inputs.removeAll()
        originalValues = entry.values
        editedKinds.removeAll()
        isEditingFields = false
        for kind in BodyMeasurementKind.allCases {
            guard let value = entry[kind] else { continue }
            let display = kind.displayValue(from: value, weightUnit: settingsStore.weightUnit)
            inputs[kind.rawValue] = editableMeasurementText(display)
        }
    }

    private func startNewEntry() {
        editingEntryID = nil
        date = Date()
        progressPhotoData = nil
        progressPhotoItem = nil
        progressPhotoError = nil
        inputs.removeAll()
        originalValues.removeAll()
        editedKinds.removeAll()
        isEditingFields = true
    }

    private func latestPlaceholder(for kind: BodyMeasurementKind) -> String {
        guard editingEntryID == nil,
              let canonical = store.latestValue(for: kind) else { return "—" }
        let display = kind.displayValue(from: canonical, weightUnit: settingsStore.weightUnit)
        return String(format: display >= 100 ? "%.0f" : "%.1f", display)
    }

    private var parsedValues: [String: Double] {
        var values: [String: Double] = [:]
        for kind in BodyMeasurementKind.allCases {
            if editingEntryID != nil,
               !editedKinds.contains(kind.rawValue),
               let originalValue = originalValues[kind.rawValue] {
                values[kind.rawValue] = originalValue
                continue
            }

            guard let raw = inputs[kind.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let canonical = kind.validatedCanonicalValue(from: raw, weightUnit: settingsStore.weightUnit) else { continue }
            values[kind.rawValue] = canonical
        }
        return values
    }

    private var canSave: Bool {
        (!parsedValues.isEmpty || progressPhotoData != nil) && !hasInvalidInputs
    }

    private func save() {
        let values = parsedValues
        guard canSave else { return }
        let saved = store.save(
            BodyMeasurementEntry(
                id: editingEntryID ?? UUID(),
                date: date,
                values: values,
                progressPhotoData: progressPhotoData
            ),
            exportToHealth: !values.isEmpty
        )
        if saved {
            dismiss()
        } else {
            measurementSaveFailed = true
        }
    }

    @MainActor
    private func importProgressPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingProgressPhoto = true
        progressPhotoError = nil
        defer { isLoadingProgressPhoto = false }

        do {
            guard let originalData = try await item.loadTransferable(type: Data.self),
                  let compressedData = compressedProgressPhotoData(from: originalData) else {
                throw NSError(
                    domain: "Iron.ProgressPhoto",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Iron could not read that image."]
                )
            }
            progressPhotoData = compressedData
        } catch {
            progressPhotoError = error.localizedDescription
            progressPhotoItem = nil
        }
    }

    private func compressedProgressPhotoData(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let maximumDimension: CGFloat = 1_280
        let largestDimension = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / largestDimension)
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.76)
    }

    private func syncHealth() {
        healthImportNotice = nil
        syncingHealth = true
        HealthManager.shared.fetchLatestBodyMeasurements { result in
            syncingHealth = false
            switch result {
            case .success(let read):
                guard !read.values.isEmpty else {
                    healthImportNotice = HealthImportNotice(
                        isError: true,
                        message: "No body measurements were found. Check Iron's Health access in Settings and try again."
                    )
                    return
                }
                for (kind, value) in read.values {
                    let display = kind.displayValue(from: value, weightUnit: settingsStore.weightUnit)
                    inputs[kind.rawValue] = editableMeasurementText(display)
                    editedKinds.insert(kind.rawValue)
                }
                if let healthDate = read.date { date = healthDate }
                healthImportNotice = HealthImportNotice(
                    isError: false,
                    message: "Imported \(read.values.count) latest measurement\(read.values.count == 1 ? "" : "s"). Review the values, then save."
                )
            case .failure(let error):
                healthImportNotice = HealthImportNotice(isError: true, message: error.localizedDescription)
            }
        }
    }

    var body: some View {
        Form {
            if isReviewingEntry {
                Section {
                    LabeledContent("Recorded", value: date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(
                        "Measurements",
                        value: recordedKinds.isEmpty ? "Photo only" : "\(recordedKinds.count)"
                    )
                } header: {
                    Text("Entry")
                } footer: {
                    Text("Only values recorded in this entry are shown.")
                }

                if progressPhotoData != nil {
                    progressPhotoSection
                }

                Section("Recorded Values") {
                    if recordedKinds.isEmpty {
                        Text("This entry only saved a progress photo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recordedKinds) { kind in
                            LabeledContent(kind.title, value: reviewValueText(for: kind))
                        }
                    }
                }
            } else {
                Section {
                    DatePicker(
                        "Measurement Date",
                        selection: $date,
                        in: Date.distantPast...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    if editingEntryID != nil {
                        Button("Start a New Entry", systemImage: "plus", action: startNewEntry)
                    }
                } footer: {
                    Text(editingEntryID == nil
                         ? "Track only what matters to you. Empty fields are ignored."
                         : "Update this entry. Empty fields stay omitted.")
                }

                if HealthSettingsView.isSupported {
                    Section {
                        Button(action: syncHealth) {
                            HStack {
                                Label(
                                    syncingHealth ? "Reading Apple Health…" : "Import Latest from Apple Health",
                                    systemImage: "heart.fill"
                                )
                                Spacer()
                                if syncingHealth {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(syncingHealth)
                    } footer: {
                        if let notice = healthImportNotice {
                            Label(notice.message, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(notice.isError ? Color.red : Color.green)
                        }
                    }
                }

                progressPhotoSection

                fieldsSection(title: "Core", kinds: primaryKinds)
                fieldsSection(title: "Torso", kinds: torsoKinds)
                fieldsSection(title: "Arms & Legs", kinds: limbKinds)

                if hasInvalidInputs || !canSave {
                    Section {
                        Label(
                            hasInvalidInputs
                                ? "Correct the highlighted values before saving."
                                : "Enter at least one measurement to save.",
                            systemImage: hasInvalidInputs ? "exclamationmark.circle.fill" : "info.circle"
                        )
                        .foregroundStyle(hasInvalidInputs ? Color.red : Color.secondary)
                    }
                }
            }

            if editingEntryID == nil, !store.entries.isEmpty {
                historySection
            }
        }
        .navigationTitle(isReviewingEntry ? "Measurement" : (editingEntryID == nil ? "Log Measurements" : "Edit Measurements"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isReviewingEntry {
                    Button("Edit", systemImage: "pencil") { isEditingFields = true }
                        .labelStyle(.iconOnly)
                } else {
                    Button(editingEntryID == nil ? "Save" : "Update", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: loadInitialValuesIfNeeded)
        .alert("Measurements Not Saved", isPresented: $measurementSaveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Iron could not save these measurements. Your previous entries are unchanged. Check the values and try again.")
        }
        .onChange(of: progressPhotoItem) { _, item in
            Task { await importProgressPhoto(item) }
        }
        .confirmationDialog(
            "Delete measurement entry?",
            isPresented: Binding(
                get: { measurementToDelete != nil },
                set: { if !$0 { measurementToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                guard let entry = measurementToDelete else { return }
                measurementToDelete = nil
                store.delete(id: entry.id)
                if editingEntryID == entry.id { startNewEntry() }
            }
            Button("Cancel", role: .cancel) {
                measurementToDelete = nil
            }
        } message: {
            Text(measurementDeleteMessage)
        }
    }

    private func reviewValueText(for kind: BodyMeasurementKind) -> String {
        if let raw = inputs[kind.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return "\(raw) \(kind.unitLabel(weightUnit: settingsStore.weightUnit))"
        }
        if let canonical = originalValues[kind.rawValue] {
            let display = kind.displayValue(from: canonical, weightUnit: settingsStore.weightUnit)
            return "\(String(format: display >= 100 ? "%.0f" : "%.1f", display)) \(kind.unitLabel(weightUnit: settingsStore.weightUnit))"
        }
        return "—"
    }

    private var progressPhotoSection: some View {
        Section {
            if let data = progressPhotoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if !isReviewingEntry {
                    PhotosPicker(
                        selection: $progressPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button("Remove Photo", systemImage: "trash", role: .destructive) {
                        progressPhotoData = nil
                        progressPhotoItem = nil
                        progressPhotoError = nil
                    }
                }
            } else if !isReviewingEntry {
                PhotosPicker(
                    selection: $progressPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Progress Photo", systemImage: "photo.badge.plus")
                }
            }

            if isLoadingProgressPhoto {
                HStack {
                    ProgressView()
                    Text("Preparing photo…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Progress Photo")
        } footer: {
            if let progressPhotoError {
                Label(progressPhotoError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("Stored locally and included in Iron backups.")
            }
        }
    }

    private var historySection: some View {
        Section {
            ForEach(store.entries) { entry in
                Button {
                    load(entry)
                } label: {
                    HStack(spacing: 12) {
                        if let data = entry.progressPhotoData,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short))
                                .foregroundStyle(.primary)
                            Text(historySummary(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let weight = entry[.bodyWeight] {
                            (Text(String(
                                format: "%.1f",
                                BodyMeasurementKind.bodyWeight.displayValue(from: weight, weightUnit: settingsStore.weightUnit)
                            )).font(.ironMetric(.body)).foregroundColor(IronTheme.primaryText)
                             + Text(" \(BodyMeasurementKind.bodyWeight.unitLabel(weightUnit: settingsStore.weightUnit))")
                                .font(.caption).foregroundColor(IronTheme.secondaryText))
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        measurementToDelete = entry
                    }
                }
            }
        } header: {
            Text("History")
        } footer: {
            Text("Tap an entry to load its values.")
        }
    }

    private func historySummary(_ entry: BodyMeasurementEntry) -> String {
        var parts: [String] = []
        if !entry.values.isEmpty {
            parts.append("\(entry.values.count) measurement\(entry.values.count == 1 ? "" : "s")")
        }
        if entry.progressPhotoData != nil {
            parts.append("Progress photo")
        }
        return parts.joined(separator: " · ")
    }
}

struct PinnedExerciseChartRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.managedObjectContext) private var managedObjectContext

    let exercise: Exercise
    let measurementType: WorkoutExerciseChartData.MeasurementType

    @State private var selectedDate: Date?

    private struct Point: Identifiable {
        let id: NSManagedObjectID
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        let timeFrame = WorkoutExerciseChartData.TimeFrame.threeMonths
        let request = WorkoutExercise.historyFetchRequest(
            of: exercise.uuid,
            from: timeFrame.from,
            until: timeFrame.until
        )
        let evaluator = WorkoutExerciseChartData.evaluator(
            for: measurementType,
            weightUnit: settingsStore.weightUnit,
            maxRepetitionsForOneRepMax: settingsStore.maxRepetitionsOneRepMax
        )

        let workoutExercises = (try? managedObjectContext.fetch(request)) ?? []
        return workoutExercises
            .compactMap { workoutExercise -> Point? in
                guard let date = workoutExercise.workout?.start,
                      let value = evaluator(workoutExercise),
                      value > 0, value.isFinite else { return nil }
                return Point(id: workoutExercise.objectID, date: date, value: value)
            }
            .sorted { $0.date < $1.date }
    }

    private var metricColor: Color {
        switch measurementType {
        case .oneRM: return IronTheme.accent
        case .totalWeight: return IronTheme.metricVolume
        case .totalSets, .totalRepetitions: return IronTheme.metricSets
        }
    }

    private var unitSuffix: String {
        switch measurementType {
        case .oneRM, .totalWeight: return " \(settingsStore.weightUnit.unit.symbol)"
        case .totalSets, .totalRepetitions: return ""
        }
    }

    private func label(_ value: Double) -> String {
        numberLabel(value) + unitSuffix
    }

    private func numberLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)).grouping(.automatic))
    }

    private func metricText(_ value: Double) -> Text {
        Text(numberLabel(value)).foregroundColor(metricColor)
            + Text(unitSuffix).font(.caption2).foregroundColor(IronTheme.secondaryText)
    }

    var body: some View {
        let points = points

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(measurementType.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let selected = selectedPoint(in: points) {
                    VStack(alignment: .trailing, spacing: 1) {
                        metricText(selected.value)
                            .font(.ironMetric(.subheadline, weight: .semibold))
                            .foregroundStyle(metricColor)
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedDate)
                        Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest = points.last {
                    metricText(latest.value)
                        .font(.ironMetric(.subheadline, weight: .semibold))
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: latest.value)
                }
            }

            if points.isEmpty {
                Text("No completed sets in the last 3 months.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 96, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date), y: .value(measurementType.title, hasAppeared || reduceMotion ? point.value : 0))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [
                                        metricColor.opacity(0.26),
                                        metricColor.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        LineMark(x: .value("Date", point.date), y: .value(measurementType.title, hasAppeared || reduceMotion ? point.value : 0))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(metricColor)
                    }

                    if let selected = selectedPoint(in: points) {
                        RuleMark(x: .value("Date", selected.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYScale(domain: 0...max((points.map(\.value).max() ?? 0) * 1.1, 1))
                .opacity(!reduceMotion || hasAppeared ? 1 : 0)
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
                .onAppear { hasAppeared = true }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text(label(raw)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 96)
                .accessibilityLabel("\(exercise.title) \(measurementType.title) over the last 3 months")
            }
        }
    }

    private func selectedPoint(in points: [Point]) -> Point? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }
}

private struct PinnedChartEditSheet: View {
    @EnvironmentObject var pinnedChartsStore: PinnedChartsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(pinnedChartsStore.pinnedCharts, id: \.self) { chart in
                    HStack {
                        Text(exerciseStore.find(with: chart.exerciseUuid)?.title ?? "Unknown Exercise")
                        Spacer()
                        Text(chart.measurementType.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    self.pinnedChartsStore.pinnedCharts.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    self.pinnedChartsStore.pinnedCharts.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if pinnedChartsStore.pinnedCharts.isEmpty {
                    ContentUnavailableView {
                        Label("No Pinned Charts", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Pin an exercise chart from Home to keep it close at hand.")
                    }
                }
            }
            .navigationTitle("Edit Charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}

private struct PinnedChartSelectorSheet: View {
    @EnvironmentObject var pinnedChartsStore: PinnedChartsStore
    @Environment(\.dismiss) private var dismiss

    let onSelection: (PinnedChart) -> Void
    
    @State private var selectedExercise: Exercise? = nil

    @ObservedObject private var filter: ExerciseGroupFilter
    
    init(exercises: [Exercise], onSelection: @escaping (PinnedChart) -> Void) {
        filter = ExerciseGroupFilter(exerciseGroups: ExerciseStore.splitIntoMuscleGroups(exercises: exercises))
        self.onSelection = onSelection
    }
    
    private func resetAndDismiss() {
        dismiss()
        self.filter.filter = ""
    }

    private func isAvailable(_ measurementType: WorkoutExerciseChartData.MeasurementType, for exercise: Exercise) -> Bool {
        !pinnedChartsStore.pinnedCharts.contains(
            PinnedChart(exerciseUuid: exercise.uuid, measurementType: measurementType)
        )
    }

    private func select(_ measurementType: WorkoutExerciseChartData.MeasurementType, for exercise: Exercise) {
        onSelection(PinnedChart(exerciseUuid: exercise.uuid, measurementType: measurementType))
        resetAndDismiss()
    }
    
    var body: some View {
        NavigationStack {
            ExerciseSingleSelectionView(exerciseGroups: filter.exerciseGroups) { exercise in
                selectedExercise = exercise
            }
            .navigationTitle("Pin Chart")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.filter, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { resetAndDismiss() }
                }
            }
        }
        .confirmationDialog(
            selectedExercise?.title ?? "Choose a chart",
            isPresented: Binding(
                get: { selectedExercise != nil },
                set: { if !$0 { selectedExercise = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let exercise = selectedExercise {
                ForEach(
                    WorkoutExerciseChartData.MeasurementType.allCases.filter { isAvailable($0, for: exercise) },
                    id: \.self
                ) { measurementType in
                    Button(measurementType.title) {
                        select(measurementType, for: exercise)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                selectedExercise = nil
            }
        }
    }
}

#if DEBUG
struct FeedView_Previews : PreviewProvider {
    static var previews: some View {
        Group {
            FeedView()
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
