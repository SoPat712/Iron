//
//  HistoryView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 22.06.19.
//  Rebuilt as Iron's progress dashboard.
//

import SwiftUI
import Charts
import CoreData
import MuscleMap
import WorkoutDataKit

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var sceneState: SceneState

    @FetchRequest(fetchRequest: HistoryView.fetchRequest) private var workouts

    @State private var activityItems: [Any]?
    @State private var workoutToDelete: Workout?
    @State private var showingMuscleBreakdown = false
    @State private var showingRepeatBlocked = false
    @State private var showingShareUnavailable = false
    @State private var persistenceError: String?
    @State private var trendMetric: HistoryTrendMetric = .duration
    @State private var selectedTimeFrame = WorkoutExerciseChartData.TimeFrame.month
    @State private var browseMode: HistoryBrowseMode = .workouts

    private var completedWorkouts: [Workout] {
        workouts.filter { $0.hasCompletedSets ?? false }
    }

    static var fetchRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return request
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmptyView()
                } header: {
                    Picker("History Section", selection: $browseMode) {
                        ForEach(HistoryBrowseMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 4)
                }

                historyModeContent
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, IronTheme.floatingWorkoutBottomClearance, for: .scrollContent)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { workoutToDelete != nil },
                set: { if !$0 { workoutToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                guard let workout = workoutToDelete else { return }
                workoutToDelete = nil
                do {
                    try workout.delete()
                } catch {
                    persistenceError = "The workout was not deleted. \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
        } message: {
            Text("This removes the workout, its logged sets, and Iron’s matching Apple Health workout.")
        }
        .sheet(isPresented: $showingMuscleBreakdown) {
            WeeklyMuscleBreakdownSheet(items: weeklyMuscleBreakdown)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRepeatBlocked) {
            IronStatusSheet(
                headerTitle: "Workout in progress",
                title: "Finish your current workout first",
                message: "Your active workout is safely stored on this iPhone. Finish or discard it before repeating another session.",
                systemImage: "figure.strengthtraining.traditional",
                tint: IronTheme.warning,
                actionTitle: "Got It"
            )
            .presentationDetents([.height(390), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingShareUnavailable) {
            IronStatusSheet(
                headerTitle: "Share workout",
                title: "Nothing to share yet",
                message: "This workout does not contain a completed set log. Add or complete a set before sharing it.",
                systemImage: "square.and.arrow.up",
                tint: IronTheme.accent,
                actionTitle: "Got It"
            )
            .presentationDetents([.height(390), .medium])
            .presentationDragIndicator(.visible)
        }
        .ironActivitySheet(activityItems: $activityItems)
        .alert("Workout Not Saved", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var historyModeContent: some View {
        switch browseMode {
        case .workouts:
            workoutHistoryContent
        case .exercises:
            exerciseHistoryContent
        case .insights:
            progressSummary
            muscleRecoveryMap
        }
    }

    @ViewBuilder
    private var progressSummary: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                trendMetric.headlineText(value: currentTrendValue, weightUnit: settingsStore.weightUnit)
                    .font(.ironMetric(.title))
                    .foregroundStyle(trendMetric.color)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: currentTrendValue)

                HistoryTrendChart(
                    points: trendPoints,
                    metricTitle: trendMetric.title,
                    metricColor: trendMetric.color,
                    weightUnit: settingsStore.weightUnit,
                    valueLabel: { trendMetric.axisLabel(value: $0, weightUnit: settingsStore.weightUnit) }
                )
            }
            .padding(.vertical, 6)

            Picker("Metric", selection: $trendMetric) {
                ForEach(HistoryTrendMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            Picker("Range", selection: $selectedTimeFrame) {
                ForEach(WorkoutExerciseChartData.TimeFrame.allCases, id: \.title) { timeFrame in
                    Text(timeFrame.title).tag(timeFrame)
                }
            }
        } header: {
            Text("Training Trend")
        } footer: {
            Text("Latest \(trendMetric.contextLabel(weightUnit: settingsStore.weightUnit)).")
        }

        Section("This Week") {
            LabeledContent("Workouts", value: "\(workoutsThisWeek)")
            LabeledContent("Sets", value: "\(setsThisWeek)")
            LabeledContent("Time", value: durationThisWeek)
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private var workoutHistoryContent: some View {
        let completed = completedWorkouts
        // isPersonalRecord performs count fetches. Build the same classification
        // once from the fetched history instead of querying from every row/bar.
        let records = HistoryRecordIndex.recordSetIDs(in: completed)
        if completed.isEmpty {
            Section("Workouts") {
                ContentUnavailableView(
                    "No Workouts Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Finished workouts, volume, effort, and personal records appear here.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            let weeks = HistoryWorkoutWeek.group(completed)
            ForEach(weeks) { week in
                Section {
                    ForEach(week.workouts, id: \.objectID) { workout in
                        workoutHistoryLink(workout, recordSetIDs: records)
                    }
                } header: {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(week.title)
                            Spacer(minLength: 8)
                            weekTotals(week)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(week.title)
                            weekTotals(week)
                        }
                    }
                    .textCase(nil)
                } footer: {
                    if week.id == weeks.last?.id {
                        Text("\(completed.count) completed workout\(completed.count == 1 ? "" : "s").")
                    }
                }
            }
        }
    }

    private func weekTotals(_ week: HistoryWorkoutWeek) -> some View {
        let volume = WeightUnit.convert(weight: week.volume, from: .metric, to: settingsStore.weightUnit)
        let value = volume >= 1_000
            ? String(format: "%.1fk", volume / 1_000)
            : String(format: "%.0f", volume)
        return (Text("\(week.workouts.count) workout\(week.workouts.count == 1 ? "" : "s")")
            .foregroundColor(IronTheme.accent)
            + Text(" · ").foregroundColor(IronTheme.secondaryText)
            + Text(value).foregroundColor(IronTheme.metricVolume)
            + Text(" \(settingsStore.weightUnit.unit.symbol)")
                .font(.caption2).foregroundColor(IronTheme.secondaryText))
            .font(.ironMetric(.caption))
    }

    private func workoutHistoryLink(_ workout: Workout, recordSetIDs: Set<NSManagedObjectID>) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
                .environmentObject(settingsStore)
        } label: {
            WorkoutHistoryRow(workout: workout, recordSetIDs: recordSetIDs)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                workoutToDelete = workout
            }
            Button("Share", systemImage: "square.and.arrow.up") {
                share(workout)
            }
            .tint(IronTheme.secondaryText)
        }
        .contextMenu {
            Button("Share Workout", systemImage: "square.and.arrow.up") { share(workout) }
            Button("Repeat Workout", systemImage: "arrow.clockwise") { repeatWorkout(workout, blank: false) }
            Button("Repeat with Blank Sets", systemImage: "doc") { repeatWorkout(workout, blank: true) }
            Divider()
            Button("Delete Workout", systemImage: "trash", role: .destructive) { workoutToDelete = workout }
        }
    }

    @ViewBuilder
    private var exerciseHistoryContent: some View {
        Section {
            if trainedExerciseSummaries.isEmpty {
                ContentUnavailableView(
                    "No Exercise History",
                    systemImage: "dumbbell",
                    description: Text("Complete a set to start tracking sessions, volume, and personal records for each exercise.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(trainedExerciseSummaries) { summary in
                    NavigationLink {
                        ExerciseDetailView(exercise: summary.exercise)
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseDiagramThumbnail(exercise: summary.exercise, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.exercise.title)
                                    .lineLimit(2)
                                Text("\(summary.sessionCount) session\(summary.sessionCount == 1 ? "" : "s") · \(summary.setCount) set\(summary.setCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text(summary.lastTrained.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Exercises")
        } footer: {
            if !trainedExerciseSummaries.isEmpty {
                Text("\(trainedExerciseSummaries.count) exercise\(trainedExerciseSummaries.count == 1 ? "" : "s") trained.")
            }
        }
    }

    private var trainedExerciseSummaries: [HistoryExerciseSummary] {
        var summaries: [UUID: HistoryExerciseSummary] = [:]

        for workout in completedWorkouts {
            let workoutDate = workout.start ?? .distantPast
            let workoutExercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []

            for workoutExercise in workoutExercises {
                let completedSets = max(workoutExercise.numberOfCompletedSets ?? 0, 0)
                guard completedSets > 0,
                      let exercise = workoutExercise.exercise(in: exerciseStore.exercises) else { continue }

                if var summary = summaries[exercise.uuid] {
                    summary.sessionCount += 1
                    summary.setCount += completedSets
                    summary.lastTrained = max(summary.lastTrained, workoutDate)
                    summaries[exercise.uuid] = summary
                } else {
                    summaries[exercise.uuid] = HistoryExerciseSummary(
                        exercise: exercise,
                        sessionCount: 1,
                        setCount: completedSets,
                        lastTrained: workoutDate
                    )
                }
            }
        }

        return summaries.values.sorted {
            if $0.lastTrained == $1.lastTrained {
                return $0.exercise.title.localizedCaseInsensitiveCompare($1.exercise.title) == .orderedAscending
            }
            return $0.lastTrained > $1.lastTrained
        }
    }

    @ViewBuilder
    private var muscleRecoveryMap: some View {
        Section {
            if weeklyMuscleSets.isEmpty {
                ContentUnavailableView(
                    "No Muscle Load",
                    systemImage: "figure.arms.open",
                    description: Text("Complete a working set and your weekly training distribution appears here.")
                )
                .listRowBackground(Color.clear)
            } else {
                HStack(spacing: 8) {
                    weeklyBody(side: .front)
                    weeklyBody(side: .back)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Button {
                    showingMuscleBreakdown = true
                } label: {
                    LabeledContent("Muscle Breakdown", value: "\(weeklyMuscleSets.count) muscles")
                }
                .accessibilityHint("Shows set counts for each trained muscle")
            }
        } header: {
            Text("Muscle Load")
        } footer: {
            Text("Primary muscles trained over the last 7 days. Darker means more sets.")
        }
    }

    private var weeklyMuscleBreakdown: [WeeklyMuscleLoad] {
        let maximum = max(weeklyMuscleSets.values.max() ?? 1, 1)
        return weeklyMuscleSets.map { muscle, sets in
            WeeklyMuscleLoad(
                id: String(describing: muscle),
                title: muscleTitle(muscle),
                sets: sets,
                fraction: Double(sets) / Double(maximum)
            )
        }
        .sorted {
            if $0.sets == $1.sets { return $0.title < $1.title }
            return $0.sets > $1.sets
        }
    }

    private func muscleTitle(_ muscle: Muscle) -> String {
        let titles: [String: String] = [
            "abs": "Abdominals", "lowerAbs": "Lower abdominals", "obliques": "Obliques", "serratus": "Serratus",
            "biceps": "Biceps", "triceps": "Triceps", "forearm": "Forearms", "hands": "Hands",
            "deltoids": "Shoulders", "rearDeltoid": "Rear deltoids",
            "rotatorCuff": "Rotator cuff", "trapezius": "Trapezius",
            "rhomboids": "Rhomboids", "neck": "Neck", "chest": "Chest", "upperChest": "Upper chest", "upperBack": "Upper back",
            "lowerBack": "Lower back", "gluteal": "Glutes", "hamstring": "Hamstrings",
            "quadriceps": "Quadriceps", "adductors": "Adductors",
            "hipFlexors": "Hip flexors", "calves": "Calves", "tibialis": "Shins",
            "ankles": "Ankles", "feet": "Feet"
        ]
        let key = String(describing: muscle)
        return titles[key] ?? key.capitalized
    }

    private var weeklyMuscleSets: [Muscle: Int] {
        var result: [Muscle: Int] = [:]
        for workout in workoutsThisWeekList {
            let workoutExercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
            for workoutExercise in workoutExercises {
                guard let exercise = workoutExercise.exercise(in: exerciseStore.exercises) else { continue }
                let completed = max(workoutExercise.numberOfCompletedSets ?? 0, 0)
                guard completed > 0 else { continue }
                for muscle in exercise.primaryMuscle.compactMap(mapMuscle) {
                    result[muscle, default: 0] += completed
                }
            }
        }
        return result
    }

    private var weeklyHeatmap: [MuscleIntensity] {
        let maximum = max(weeklyMuscleSets.values.max() ?? 1, 1)
        return weeklyMuscleSets.map { muscle, sets in
            MuscleIntensity(muscle: muscle, intensity: Double(sets) / Double(maximum))
        }
    }

    private func weeklyBody(side: BodySide) -> some View {
        let style = BodyViewStyle(
            defaultFillColor: Color(.quaternaryLabel),
            strokeColor: Color(.separator),
            strokeWidth: 0.5,
            headColor: Color(.tertiaryLabel),
            hairColor: Color(.quaternaryLabel)
        )
        let scale = HeatmapColorScale(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.62), Color.accentColor])
        return BodyView(gender: .male, side: side, style: style)
            .heatmap(weeklyHeatmap, colorScale: scale)
            // This is a read-only visualization. MuscleMap's own gesture
            // handling otherwise steals vertical drags from the surrounding
            // ScrollView and makes the workout history feel unreachable.
            .allowsHitTesting(false)
    }

    private func mapMuscle(_ rawName: String) -> Muscle? {
        switch rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "abs", "abdominals", "core": return .abs
        case "lower abs", "lowerabs": return .lowerAbs
        case "obliques": return .obliques
        case "serratus", "serratus anterior": return .serratus
        case "biceps", "biceps brachii", "brachialis": return .biceps
        case "triceps", "triceps brachii": return .triceps
        case "forearm", "forearms", "forerm", "wrists", "wrist flexors", "wrist extensors", "grip muscles": return .forearm
        case "hands": return .hands
        case "shoulders", "deltoid", "deltoids", "delts": return .deltoids
        case "rear deltoid", "rear deltoids", "reardeltoid": return .rearDeltoid
        case "rotator cuff", "rotatorcuff": return .rotatorCuff
        case "trapezius", "traps", "levator scapulae": return .trapezius
        case "rhomboids": return .rhomboids
        case "neck", "sternocleidomastoid": return .neck
        case "chest", "pectorals", "pectoralis major": return .chest
        case "upper chest", "upperchest": return .upperChest
        case "lats", "latissimus", "latissimus dorsi", "upper back", "upperback", "back": return .upperBack
        case "lower back", "lowerback", "spine", "erector spinae": return .lowerBack
        case "glutes", "glutaeus maximus", "abductors": return .gluteal
        case "hamstrings", "ischiocrural muscles": return .hamstring
        case "quadriceps", "quads": return .quadriceps
        case "adductors", "groin", "inner thighs": return .adductors
        case "hip flexor", "hip flexors", "hipflexors": return .hipFlexors
        case "calves", "gastrocnemius", "soleus": return .calves
        case "shin", "shins", "tibialis", "tibialis anterior": return .tibialis
        case "ankles", "ankle stabilizers": return .ankles
        case "feet": return .feet
        default: return nil
        }
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date.distantPast
    }

    private var workoutsThisWeekList: [Workout] {
        completedWorkouts.filter { ($0.start ?? .distantPast) >= weekStart }
    }

    private var workoutsThisWeek: Int { workoutsThisWeekList.count }

    private var setsThisWeek: Int {
        workoutsThisWeekList.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
    }

    private var durationThisWeek: String {
        let seconds = workoutsThisWeekList.reduce(0) { $0 + ($1.duration ?? 0) }
        if seconds >= 3600 {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(Int(seconds / 60))m"
    }

    private var trendPoints: [HistoryTrendPoint] {
        let calendar = Calendar.current
        let now = Date()

        switch selectedTimeFrame {
        case .week:
            let currentDay = calendar.startOfDay(for: now)
            return (0..<7).compactMap { index in
                guard let start = calendar.date(byAdding: .day, value: index - 6, to: currentDay),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                return trendPoint(start: start, end: end, label: start.formatted(.dateTime.weekday(.narrow)), isCurrent: index == 6)
            }
        case .month, .threeMonths:
            let weekCount = selectedTimeFrame == .month ? 4 : 12
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return (0..<weekCount).compactMap { index in
                guard let start = calendar.date(byAdding: .weekOfYear, value: index - (weekCount - 1), to: currentWeek),
                      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
                return trendPoint(
                    start: start,
                    end: end,
                    label: start.formatted(.dateTime.month(.abbreviated).day()),
                    isCurrent: index == weekCount - 1
                )
            }
        case .year, .all:
            let earliest = selectedTimeFrame.from
                ?? completedWorkouts.compactMap(\.start).min()
                ?? calendar.date(byAdding: .year, value: -1, to: now)
                ?? now
            let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: earliest)) ?? earliest
            let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            var months: [Date] = []
            var cursor = startMonth
            while cursor <= currentMonth {
                months.append(cursor)
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
                if months.count > 72 { break }
            }
            return months.enumerated().compactMap { index, start in
                guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                return trendPoint(
                    start: start,
                    end: end,
                    label: start.formatted(.dateTime.month(.abbreviated)),
                    isCurrent: index == months.count - 1
                )
            }
        }
    }

    private func trendPoint(start: Date, end: Date, label: String, isCurrent: Bool) -> HistoryTrendPoint {
        let bucketWorkouts = completedWorkouts.filter {
            let date = $0.start ?? .distantPast
            return date >= start && date < end
        }

        let duration = bucketWorkouts.reduce(0) { $0 + ($1.duration ?? 0) }
        let kilograms = bucketWorkouts.reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) }
        let volume = WeightUnit.convert(
            weight: kilograms,
            from: .metric,
            to: settingsStore.weightUnit
        )
        let sets = bucketWorkouts.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
        let repetitions = bucketWorkouts.reduce(0) { total, workout in
            let exercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
            return total + exercises.reduce(0) { $0 + ($1.numberOfCompletedRepetitions ?? 0) }
        }
        let efforts = bucketWorkouts.compactMap(\.sessionEffortValue)
        let averageEffort = efforts.isEmpty
            ? nil
            : efforts.reduce(0, +) / Double(efforts.count)

        let value: Double
        switch trendMetric {
        case .duration:
            value = duration
        case .volume:
            value = volume
        case .repetitions:
            value = Double(repetitions)
        }

        return HistoryTrendPoint(
            id: start,
            end: end,
            label: label,
            value: value,
            isCurrent: isCurrent,
            workoutCount: bucketWorkouts.count,
            duration: duration,
            volume: volume,
            sets: sets,
            repetitions: repetitions,
            averageEffort: averageEffort
        )
    }

    private var currentTrendValue: Double {
        trendPoints.last?.value ?? 0
    }

    private func share(_ workout: Workout) {
        guard let log = workout.logText(
            in: exerciseStore.exercises,
            weightUnit: settingsStore.weightUnit
        ) else {
            showingShareUnavailable = true
            return
        }
        activityItems = [log]
    }

    private func repeatWorkout(_ workout: Workout, blank: Bool) {
        do {
            let didStart: Bool
            if blank {
                didStart = try WorkoutDetailView.repeatWorkoutBlank(
                    workout: workout,
                    settingsStore: settingsStore,
                    sceneState: sceneState
                )
            } else {
                didStart = try WorkoutDetailView.repeatWorkout(
                    workout: workout,
                    settingsStore: settingsStore,
                    sceneState: sceneState
                )
            }

            if !didStart { showingRepeatBlocked = true }
        } catch {
            persistenceError = "The workout was not started. \(error.localizedDescription)"
        }
    }

}

private enum HistoryBrowseMode: String, CaseIterable, Identifiable {
    case workouts
    case exercises
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .exercises: return "Exercises"
        case .insights: return "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .workouts: return "clock.arrow.circlepath"
        case .exercises: return "dumbbell.fill"
        case .insights: return "chart.xyaxis.line"
        }
    }
}

private struct HistoryExerciseSummary: Identifiable {
    let exercise: Exercise
    var sessionCount: Int
    var setCount: Int
    var lastTrained: Date

    var id: UUID { exercise.uuid }
}

private enum HistoryTrendMetric: String, CaseIterable, Identifiable {
    case duration
    case volume
    case repetitions

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .duration: return IronTheme.metricTime
        case .volume: return IronTheme.metricVolume
        case .repetitions: return IronTheme.metricSets
        }
    }

    var title: String {
        switch self {
        case .duration: return "Duration"
        case .volume: return "Volume"
        case .repetitions: return "Reps"
        }
    }

    var systemImage: String {
        switch self {
        case .duration: return "clock"
        case .volume: return "dumbbell.fill"
        case .repetitions: return "repeat"
        }
    }

    func contextLabel(weightUnit: WeightUnit) -> String {
        switch self {
        case .duration: return "training time"
        case .volume: return "lifted volume in \(weightUnit.unit.symbol)"
        case .repetitions: return "completed repetitions"
        }
    }

    func headline(value: Double, weightUnit: WeightUnit) -> String {
        switch self {
        case .duration:
            let totalMinutes = max(Int(value / 60), 0)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours == 0 { return "\(minutes)m" }
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        case .volume:
            return "\(compact(value)) \(weightUnit.unit.symbol)"
        case .repetitions:
            return "\(Int(value.rounded())) reps"
        }
    }

    func headlineText(value: Double, weightUnit: WeightUnit) -> Text {
        if self == .volume {
            return Text(compact(value)).foregroundColor(IronTheme.metricVolume)
                + Text(" " + weightUnit.unit.symbol).font(.caption).foregroundColor(IronTheme.secondaryText)
        }
        return Text(headline(value: value, weightUnit: weightUnit))
    }

    func axisLabel(value: Double, weightUnit: WeightUnit) -> String {
        switch self {
        case .duration:
            let minutes = max(Int(value / 60), 0)
            return minutes >= 60 ? String(format: "%.1fh", Double(minutes) / 60) : "\(minutes)m"
        case .volume:
            return "\(compact(value)) \(weightUnit.unit.symbol)"
        case .repetitions:
            return "\(Int(value.rounded()))"
        }
    }

    private func compact(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

private struct HistoryTrendPoint: Identifiable {
    let id: Date
    let end: Date
    let label: String
    let value: Double
    let isCurrent: Bool
    let workoutCount: Int
    let duration: TimeInterval
    let volume: Double
    let sets: Int
    let repetitions: Int
    let averageEffort: Double?
}

private struct HistoryTrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [HistoryTrendPoint]
    let metricTitle: String
    let metricColor: Color
    let weightUnit: WeightUnit
    let valueLabel: (Double) -> String

    @State private var hasAppeared = false
    @State private var selectedPointID: Date?

    private var selectedPoint: HistoryTrendPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Period", point.id, unit: barUnit),
                y: .value(metricTitle, hasAppeared || reduceMotion ? point.value : 0)
            )
            .cornerRadius(4)
            .foregroundStyle(barStyle(for: point))
            .opacity(selectedPointID == nil || selectedPointID == point.id ? 1 : 0.4)
        }
        .chartYScale(domain: 0...max((points.map(\.value).max() ?? 0) * 1.1, 1))
        .opacity(!reduceMotion || hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
        .onAppear { hasAppeared = true }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(valueLabel(raw))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
            }
        }
        .chartXSelection(value: Binding(
            get: { selectedPoint?.id },
            set: { newDate in
                guard let newDate else {
                    selectedPointID = nil
                    return
                }
                selectedPointID = points.min {
                    abs($0.id.timeIntervalSince(newDate)) < abs($1.id.timeIntervalSince(newDate))
                }?.id
            }
        ))
        .frame(height: 150)
        .overlay(alignment: .topTrailing) {
            if let selectedPoint {
                selectionCallout(for: selectedPoint)
                    .transition(.opacity)
            }
        }
        .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: selectedPointID)
        .sensoryFeedback(.selection, trigger: selectedPointID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metricTitle) trend chart with \(points.count) periods")
        .accessibilityValue(selectedPoint.map(accessibilityValue(for:)) ?? "No period selected")
        .accessibilityAdjustableAction(adjustSelection)
    }

    private var barUnit: Calendar.Component {
        guard points.count > 1 else { return .day }
        let spacing = points[1].id.timeIntervalSince(points[0].id)
        if spacing > 60 * 60 * 24 * 20 { return .month }
        if spacing > 60 * 60 * 24 * 3 { return .weekOfYear }
        return .day
    }

    private func barStyle(for point: HistoryTrendPoint) -> Color {
        point.isCurrent ? metricColor : metricColor.opacity(0.55)
    }

    private func selectionCallout(for point: HistoryTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(periodLabel(for: point))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valueLabel(point.value))
                .font(.ironMetric(.subheadline, weight: .semibold))
                .foregroundStyle(metricColor)
                .contentTransition(reduceMotion ? .opacity : .numericText())
            Text("\(point.workoutCount) workout\(point.workoutCount == 1 ? "" : "s") · \(point.sets) sets · \(point.repetitions) reps")
                .font(.ironMetric(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        let currentIndex = selectedPointID.flatMap { id in points.firstIndex { $0.id == id } }
            ?? (points.count - 1)
        switch direction {
        case .increment:
            selectedPointID = points[min(currentIndex + 1, points.count - 1)].id
        case .decrement:
            selectedPointID = points[max(currentIndex - 1, 0)].id
        @unknown default:
            break
        }
    }

    private func periodLabel(for point: HistoryTrendPoint) -> String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: point.end) ?? point.end
        if Calendar.current.isDate(point.id, inSameDayAs: end) {
            return point.id.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(point.id.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func accessibilityValue(for point: HistoryTrendPoint) -> String {
        "Selected \(periodLabel(for: point)), \(metricTitle) \(valueLabel(point.value)), \(point.workoutCount) workouts, \(point.sets) sets, \(point.repetitions) repetitions"
    }
}

private struct WeeklyMuscleLoad: Identifiable {
    let id: String
    let title: String
    let sets: Int
    let fraction: Double
}

private struct WeeklyMuscleBreakdownSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @Environment(\.dismiss) private var dismiss

    let items: [WeeklyMuscleLoad]

    private var totalTargetedSets: Int {
        items.reduce(0) { $0 + $1.sets }
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Muscle Load",
                            systemImage: "figure.strengthtraining.traditional",
                            description: Text("Complete a working set and Iron will map your weekly distribution here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        LabeledContent("Targeted Sets") {
                            Text("\(totalTargetedSets)")
                                .font(.ironMetric(.body))
                                .foregroundStyle(IronTheme.metricSets)
                        }

                        if let leading = items.first {
                            LabeledContent("Most Trained", value: leading.title)
                        }
                    } header: {
                        Text("Last 7 Days")
                    } footer: {
                        Text("A completed set counts once for every primary muscle assigned to its exercise, so targeted sets can exceed your workout set total.")
                    }

                    Section("Distribution") {
                        Chart(items) { item in
                            BarMark(
                                x: .value("Sets", hasAppeared || reduceMotion ? item.sets : 0),
                                y: .value("Muscle", item.title)
                            )
                            .cornerRadius(4)
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("\(item.sets)")
                                    .font(.ironMetric(.caption2, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(IronTheme.metricSets)
                        .chartXScale(domain: 0...max(items.map(\.sets).max() ?? 0, 1))
                        .opacity(!reduceMotion || hasAppeared ? 1 : 0)
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
                        .onAppear { hasAppeared = true }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(items.count) * 26 + 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Muscle Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
private struct HistoryWorkoutWeek: Identifiable {
    let id: Date
    let workouts: [Workout]

    var volume: Double { workouts.reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) } }

    var title: String {
        guard id != .distantPast else { return "Unknown date" }
        let calendar = Calendar.current
        if calendar.isDate(id, equalTo: Date(), toGranularity: .weekOfYear) { return "This Week" }
        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()),
           calendar.isDate(id, equalTo: lastWeek, toGranularity: .weekOfYear) { return "Last Week" }
        return "Week of \(id.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    static func group(_ workouts: [Workout]) -> [Self] {
        let grouped = Dictionary(grouping: workouts) { workout in
            workout.start.flatMap { Calendar.current.dateInterval(of: .weekOfYear, for: $0)?.start } ?? .distantPast
        }
        return grouped.keys.sorted(by: >).map { Self(id: $0, workouts: grouped[$0] ?? []) }
    }
}

/// A small Pareto frontier of weight/repetition pairs, matching the model's
/// "no earlier set with both weight and reps >= this set" record rule.
private struct HistoryRecordFrontier {
    private var pairs: [(weight: Double, reps: Int16)] = []

    func dominates(weight: Double, reps: Int16) -> Bool {
        pairs.contains { $0.weight >= weight && $0.reps >= reps }
    }

    mutating func insert(weight: Double, reps: Int16) {
        guard !dominates(weight: weight, reps: reps) else { return }
        pairs.removeAll { weight >= $0.weight && reps >= $0.reps }
        pairs.append((weight, reps))
    }
}

private enum HistoryRecordIndex {
    static func recordSetIDs(in workouts: [Workout]) -> Set<NSManagedObjectID> {
        var records: Set<NSManagedObjectID> = []
        var trained: Set<UUID> = []
        var previous: [UUID: HistoryRecordFrontier] = [:]
        let dated = Dictionary(grouping: workouts.filter { $0.start != nil }, by: { $0.start! })

        // Workouts sharing a start are peers, never each other's prior history.
        for date in dated.keys.sorted() {
            let batch = dated[date] ?? []
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    var earlier = HistoryRecordFrontier()
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] {
                        if set.isCompleted, set.weight != nil, set.repetitions != nil,
                           set.repetitionsValue > 0, trained.contains(uuid),
                           !(previous[uuid]?.dominates(weight: set.weightValue, reps: set.repetitionsValue) ?? false),
                           !earlier.dominates(weight: set.weightValue, reps: set.repetitionsValue) {
                            records.insert(set.objectID)
                        }
                        // The model also considers earlier uncompleted sets in
                        // the same exercise when suppressing duplicate records.
                        earlier.insert(weight: set.weightValue, reps: set.repetitionsValue)
                    }
                }
            }
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] where set.isCompleted {
                        trained.insert(uuid)
                        if let weight = set.weight, let reps = set.repetitions {
                            previous[uuid, default: HistoryRecordFrontier()].insert(
                                weight: weight.doubleValue, reps: reps.int16Value
                            )
                        }
                    }
                }
            }
        }
        return records
    }
}

private struct WorkoutHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject var workout: Workout
    let recordSetIDs: Set<NSManagedObjectID>

    private var exercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    private var durationText: String {
        guard let duration = workout.duration else { return "—" }
        return Workout.durationFormatter.string(from: duration) ?? "—"
    }

    private var volumeNumber: String {
        guard let volume = workout.totalCompletedWeight else { return "—" }
        let value = WeightUnit.convert(weight: volume, from: .metric, to: settingsStore.weightUnit)
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private var metadata: String {
        let date = Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date")
        let muscles = workout.muscleGroups(in: exerciseStore.exercises)
            .filter { !$0.isEmpty && $0.lowercased() != "other" }
            .map { Exercise.displayName(forMuscleGroup: $0) }.joined(separator: ", ")
        return muscles.isEmpty ? date : "\(date) · \(muscles)"
    }

    private var breakdownItems: [WorkoutExerciseBreakdown.Item] {
        // Ordered relationships and the shared record index need no row fetches.
        exercises.map { exercise in
            var setCount = 0
            var volume = 0.0
            var recordCount = 0
            for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] where set.isCompleted {
                setCount += 1
                let setVolume = set.weightValue * Double(set.repetitionsValue)
                if setVolume.isFinite, setVolume > 0 { volume += setVolume }
                if recordSetIDs.contains(set.objectID) { recordCount += 1 }
            }
            return .init(
                id: exercise.objectID,
                name: exercise.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise",
                setCount: setCount,
                volume: volume,
                recordCount: recordCount
            )
        }
    }

    var body: some View {
        let items = breakdownItems
        let records = items.reduce(0) { $0 + $1.recordCount }
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                badges(records: records)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title
                        Spacer(minLength: 0)
                        badges(records: records)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        badges(records: records)
                    }
                }
            }

            Text(metadata)
                .font(.caption)
                .foregroundStyle(IronTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            (Text(durationText).foregroundColor(IronTheme.metricTime)
             + Text(" · ").foregroundColor(IronTheme.secondaryText)
             + Text("\(workout.numberOfCompletedSets ?? 0) sets").foregroundColor(IronTheme.metricSets)
             + Text(" · ").foregroundColor(IronTheme.secondaryText)
             + Text(volumeNumber).foregroundColor(IronTheme.metricVolume)
             + Text(" \(settingsStore.weightUnit.unit.symbol)")
                .font(.caption2).foregroundColor(IronTheme.secondaryText))
                .font(.ironMetric(.caption))
                .fixedSize(horizontal: false, vertical: true)

            WorkoutExerciseBreakdown(items: items)
        }
        .padding(.vertical, 4)
    }

    private var title: some View {
        Text(workout.displayTitle(in: exerciseStore.exercises))
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badges(records: Int) -> some View {
        HStack(spacing: 6) {
            if records > 0 {
                Label("\(records) PR\(records == 1 ? "" : "s")", systemImage: "trophy.fill")
                    .foregroundStyle(IronTheme.metricRecord)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(IronTheme.metricRecordContainer, in: Capsule())
                    .accessibilityLabel("\(records) personal record\(records == 1 ? "" : "s")")
            }
            if let effort = workout.sessionEffortValue, effort > 0 {
                Text("RPE \(Int(effort))")
                    .foregroundStyle(IronTheme.metricEffort)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(IronTheme.metricEffortContainer, in: Capsule())
                    .accessibilityLabel("Session effort \(Int(effort)) out of 10")
            }
        }
        .font(.ironMetric(.caption, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WorkoutExerciseBreakdown: View {
    struct Item: Identifiable {
        let id: NSManagedObjectID
        let name: String
        let setCount: Int
        let volume: Double
        let recordCount: Int

        var shortName: String {
            // Same equipment-suffix rule as the session strip's private helper.
            name.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var hasAppeared = false

    let items: [Item]
    private let shares: [Double]
    private let usesVolume: Bool

    init(items: [Item]) {
        self.items = items
        let usesVolume = items.contains { $0.volume > 0 }
        self.usesVolume = usesVolume
        let weights = items.map { usesVolume ? $0.volume : Double($0.setCount) }
        let total = weights.reduce(0, +)
        shares = weights.map { total > 0 ? $0 / total : 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkoutExerciseTrackLayout(shares: shares, layoutDirection: layoutDirection) {
                ForEach(items.indices, id: \.self) { index in
                    Rectangle()
                        .fill(segmentColor(at: index))
                        .scaleEffect(x: hasAppeared || reduceMotion ? 1 : 0, anchor: .leading)
                        .opacity(hasAppeared ? 1 : 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            ViewThatFits(in: .horizontal) {
                ForEach((0...min(4, items.count)).reversed(), id: \.self) { count in
                    legend(visibleCount: count)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }

    private func segmentColor(at index: Int) -> Color {
        IronTheme.accent.opacity([1.0, 0.7, 0.5, 0.35][index % 4])
    }

    private func legend(visibleCount: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<visibleCount, id: \.self) { index in
                let item = items[index]
                HStack(spacing: 4) {
                    Circle().fill(segmentColor(at: index)).frame(width: 6, height: 6)
                    Text(item.shortName)
                    Text("\(item.setCount)")
                        .font(.ironMetric(.caption, weight: .semibold))
                        .foregroundStyle(IronTheme.metricSets)
                    if item.recordCount > 0 {
                        Image(systemName: "trophy.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IronTheme.metricRecord)
                    }
                }
            }
            if visibleCount < items.count {
                Text("+\(items.count - visibleCount) more")
                    .font(.ironMetric(.caption, weight: .semibold))
            }
        }
        .font(.caption)
        .foregroundStyle(IronTheme.secondaryText)
        .lineLimit(1)
    }

    private var accessibilitySummary: String {
        let basis = usesVolume ? "volume" : "completed sets"
        let descriptions = items.indices.map { index in
            let item = items[index]
            let percent = (shares[index] * 100).formatted(.number.precision(.fractionLength(0)))
            let record = item.recordCount > 0 ? ", personal record" : ""
            return "\(item.shortName), \(item.setCount) set\(item.setCount == 1 ? "" : "s"), \(percent) percent of \(basis)\(record)"
        }
        return "Exercises: " + descriptions.joined(separator: "; ")
    }
}

/// Plain segment views, sized proportionally while keeping tiny contributions visible.
private struct WorkoutExerciseTrackLayout: Layout {
    let shares: [Double]
    let layoutDirection: LayoutDirection

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? CGFloat(subviews.count) * 8, height: 8)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = subviews.count
        let gap = min(2, bounds.width / CGFloat(max(1, count * 2 - 1)))
        var remainingWidth = max(0, bounds.width - CGFloat(count - 1) * gap)
        let minimumWidth = min(6, remainingWidth / CGFloat(count))
        var remainingShare = shares.reduce(0, +)
        var widths = [CGFloat](repeating: 0, count: count)

        // Clamp the smallest shares first; the remaining widths keep their ratios.
        for (offset, index) in shares.indices.sorted(by: { shares[$0] < shares[$1] }).enumerated() {
            let proportionalWidth = remainingShare > 0
                ? remainingWidth * CGFloat(shares[index] / remainingShare)
                : remainingWidth / CGFloat(count - offset)
            let width = min(remainingWidth, max(minimumWidth, proportionalWidth))
            widths[index] = width
            remainingWidth -= width
            remainingShare -= shares[index]
        }

        var offset: CGFloat = 0
        for index in subviews.indices {
            let width = widths[index]
            let x = layoutDirection == .rightToLeft ? bounds.maxX - offset - width : bounds.minX + offset
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            offset += width + gap
        }
    }
}

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
