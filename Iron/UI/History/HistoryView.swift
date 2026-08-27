//
//  HistoryView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 22.06.19.
//  Rebuilt as Iron's progress dashboard.
//

import SwiftUI
import CoreData
import MuscleMap
import WorkoutDataKit

struct HistoryView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var sceneState: SceneState

    @FetchRequest(fetchRequest: HistoryView.fetchRequest) private var workouts

    @State private var activityItems: [Any]?
    @State private var workoutToDelete: Workout?
    @State private var showingMuscleBreakdown = false
    @State private var showingRepeatBlocked = false
    @State private var showingShareUnavailable = false
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
            ZStack {
                IronScreenBackground()
                VStack(spacing: 0) {
                    historyModePicker

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            historyModeContent
                        }
                        .padding(IronTheme.horizontalPadding)
                        .padding(.top, 10)
                        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
                    }
                }
            }
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
                workout.deleteOrCrash()
            }
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
        } message: {
            Text("This removes the workout, its logged sets, and Iron’s matching Apple Health workout.")
        }
        .sheet(isPresented: $showingMuscleBreakdown) {
            WeeklyMuscleBreakdownSheet(items: weeklyMuscleBreakdown)
                .presentationDetents([.height(390), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(IronTheme.modalSurface)
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
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            IronSectionTitle(title: "Training trend", detail: selectedTimeFrame.compactTitle)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trendMetric.headline(value: currentTrendValue, weightUnit: settingsStore.weightUnit))
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                        .contentTransition(.numericText())
                    Text("This week · \(trendMetric.contextLabel(weightUnit: settingsStore.weightUnit))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(IronTheme.secondaryText)
                }

                HStack(spacing: 6) {
                    ForEach(WorkoutExerciseChartData.TimeFrame.allCases, id: \.title) { timeFrame in
                        Button {
                            selectedTimeFrame = timeFrame
                        } label: {
                            Text(timeFrame.compactTitle)
                        }
                        .buttonStyle(IronChoicePillButtonStyle(isSelected: selectedTimeFrame == timeFrame))
                        .accessibilityLabel(timeFrame.title)
                    }
                }

                HistoryTrendChart(
                    points: trendPoints,
                    metricTitle: trendMetric.title,
                    weightUnit: settingsStore.weightUnit,
                    valueLabel: { trendMetric.axisLabel(value: $0, weightUnit: settingsStore.weightUnit) }
                )

                Picker("Trend metric", selection: $trendMetric) {
                    ForEach(HistoryTrendMetric.allCases) { metric in
                        Text(metric.title)
                            .tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 0) {
                    compactWeekMetric(value: "\(workoutsThisWeek)", label: "WORKOUTS")
                    weekMetricDivider
                    compactWeekMetric(value: "\(setsThisWeek)", label: "SETS")
                    weekMetricDivider
                    compactWeekMetric(value: durationThisWeek, label: "TIME")
                }
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.raisedSurface)
                )
            }
            .padding(.vertical, 14)
            .overlay(IronHairline(opacity: 0.48), alignment: .top)
            .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
        }
    }

    private var historyModePicker: some View {
        Picker("History section", selection: $browseMode) {
            ForEach(HistoryBrowseMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(IronTheme.background)
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

    private var workoutHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Workout history", detail: "\(completedWorkouts.count) TOTAL")

            if completedWorkouts.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(completedWorkouts.enumerated()), id: \.element.id) { index, workout in
                        HStack(alignment: .top, spacing: 0) {
                            NavigationLink(destination: WorkoutDetailView(workout: workout).environmentObject(settingsStore)) {
                                WorkoutProgressCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            IronPopupMenu(
                                title: "Workout actions",
                                actions: workoutPopupActions(for: workout),
                                arrowEdge: .bottom
                            ) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(IronTheme.primaryText)
                                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                                    .background(Circle().fill(IronTheme.raisedSurface))
                            }
                            .padding(.top, 4)
                            .padding(.trailing, 4)
                        }

                        if index < completedWorkouts.count - 1 {
                            IronHairline(opacity: 0.46)
                                .padding(.leading, 14)
                        }
                    }
                }
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            }
        }
    }

    private var exerciseHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Exercise history", detail: "\(trainedExerciseSummaries.count) TRAINED")

            if trainedExerciseSummaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(IronTheme.accent)
                    Text("No exercise history yet")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("Complete a set to start tracking sessions, volume, and personal records for each exercise.")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 34)
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(trainedExerciseSummaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink(destination: ExerciseDetailView(exercise: summary.exercise)) {
                            historyExerciseRow(summary)
                        }
                        .buttonStyle(.plain)

                        if index < trainedExerciseSummaries.count - 1 {
                            IronHairline(opacity: 0.44)
                                .padding(.leading, 64)
                        }
                    }
                }
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            }
        }
    }

    private func historyExerciseRow(_ summary: HistoryExerciseSummary) -> some View {
        HStack(spacing: 12) {
            ExerciseDiagramThumbnail(exercise: summary.exercise, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.exercise.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(2)

                Text("\(summary.sessionCount) session\(summary.sessionCount == 1 ? "" : "s") · \(summary.setCount) set\(summary.setCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(summary.lastTrained.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens exercise statistics and session history")
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

    private func compactWeekMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundColor(IronTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var weekMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.55))
            .frame(width: 1, height: 30)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("Your progress starts with one set")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Finished workouts, volume, effort, and personal records will appear here.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .overlay(IronHairline(opacity: 0.48), alignment: .top)
        .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
    }

    private var muscleRecoveryMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Muscle load", detail: "LAST 7 DAYS")

            VStack(spacing: 12) {
                if weeklyMuscleSets.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "figure.arms.open")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(IronTheme.accent)
                        Text("Complete sets to build your muscle map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Your weekly training distribution will appear here.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 176)
                } else {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            weeklyBody(side: .front)
                            weeklyBody(side: .back)
                        }
                        .frame(height: 176)

                        HStack {
                            Text("FRONT")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(IronTheme.accent.opacity(0.25)).frame(width: 7, height: 7)
                                Text("LOW")
                                Rectangle()
                                    .fill(LinearGradient(colors: [IronTheme.accent.opacity(0.22), IronTheme.accent.opacity(0.62), IronTheme.accent], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 64, height: 5)
                                    .clipShape(Capsule())
                                Text("HIGH")
                            }
                            Spacer()
                            Text("BACK")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                    }
                    .allowsHitTesting(false)
                }

                IronHairline()

                Button(action: { showingMuscleBreakdown = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(IronTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View muscle breakdown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text("Set counts and weekly distribution")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: IronTheme.controlHeight)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows set counts for each trained muscle")
            }
            .padding(.vertical, 14)
            .overlay(IronHairline(opacity: 0.48), alignment: .top)
            .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            .frame(maxWidth: .infinity)
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
            defaultFillColor: IronTheme.secondaryText.opacity(0.14),
            strokeColor: IronTheme.secondaryText.opacity(0.16),
            strokeWidth: 0.5,
            headColor: IronTheme.secondaryText.opacity(0.20),
            hairColor: IronTheme.secondaryText.opacity(0.10)
        )
        let scale = HeatmapColorScale(colors: [IronTheme.accent.opacity(0.25), IronTheme.accent.opacity(0.62), IronTheme.accent])
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
        let didStart: Bool
        if blank {
            didStart = WorkoutDetailView.repeatWorkoutBlank(
                workout: workout,
                settingsStore: settingsStore,
                sceneState: sceneState
            )
        } else {
            didStart = WorkoutDetailView.repeatWorkout(
                workout: workout,
                settingsStore: settingsStore,
                sceneState: sceneState
            )
        }

        if !didStart {
            showingRepeatBlocked = true
        }
    }

    private func workoutPopupActions(for workout: Workout) -> [IronPopupAction] {
        [
            IronPopupAction(title: "Share Workout", systemImage: "square.and.arrow.up") {
                share(workout)
            },
            IronPopupAction(title: "Repeat Workout", systemImage: "arrow.clockwise") {
                repeatWorkout(workout, blank: false)
            },
            IronPopupAction(title: "Repeat with Blank Sets", systemImage: "doc") {
                repeatWorkout(workout, blank: true)
            },
            IronPopupAction(
                title: "Delete Workout",
                systemImage: "trash",
                role: .destructive
            ) {
                workoutToDelete = workout
            }
        ]
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
    let points: [HistoryTrendPoint]
    let metricTitle: String
    let weightUnit: WeightUnit
    let valueLabel: (Double) -> String

    @State private var selectedPointID: Date?

    // Keep the number shown to people independent from the denominator used to
    // keep an all-zero chart drawable.
    private var displayedMaximum: Double {
        max(points.map(\.value).max() ?? 0, 0)
    }

    private var scaleDenominator: Double {
        max(displayedMaximum, 1)
    }

    private var selectedPoint: HistoryTrendPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    var body: some View {
        VStack(spacing: 7) {
            selectionHeader

            GeometryReader { proxy in
                let showsScroll = points.count > 8
                ScrollView(.horizontal, showsIndicators: showsScroll) {
                    ZStack {
                        VStack(spacing: 0) {
                            IronHairline(opacity: 0.34)
                            Spacer()
                            IronHairline(opacity: 0.25)
                            Spacer()
                            IronHairline(opacity: 0.34)
                                .padding(.bottom, 21)
                        }

                        HStack(alignment: .bottom, spacing: 7) {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                VStack(spacing: 5) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(barColor(for: point, isSelected: point.id == selectedPointID))
                                        .frame(height: barHeight(for: point.value, availableHeight: proxy.size.height - 24))
                                    Text(shouldShowLabel(at: index, point: point) ? point.label : " ")
                                        .font(.system(size: 9, weight: point.isCurrent ? .bold : .medium))
                                        .foregroundColor(point.isCurrent ? IronTheme.accent : IronTheme.tertiaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                                .frame(minWidth: showsScroll ? 28 : 0, maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(accessibilityLabel(for: point))
                            }
                        }
                        .frame(minWidth: proxy.size.width)

                        if let selectedPoint {
                            selectionGuide(
                                for: selectedPoint,
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                                .transition(.opacity)
                        }
                    }
                    .frame(minWidth: proxy.size.width)
                    .frame(height: proxy.size.height)
                }
                .defaultScrollAnchorCompat_trailing()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            selectPoint(at: value.location.x, width: proxy.size.width)
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .onChanged { value in
                            // Let the containing ScrollView own vertical intent;
                            // only a clearly horizontal drag scrubs the chart.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            selectPoint(at: value.location.x, width: proxy.size.width)
                        }
                )
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        selectPoint(
                            at: location.x,
                            width: proxy.size.width,
                            producesHaptic: false
                        )
                    case .ended:
                        selectedPointID = nil
                    }
                }
            }
            .frame(height: 132)

            if let selectedPoint {
                detailCallout(for: selectedPoint)
                    // The callout is laid out after the plot. An opacity-only
                    // transition keeps its animation from crossing the marks.
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: points.map(\.value))
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selectedPointID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eight week activity chart")
        .accessibilityValue(
            selectedPoint.map(accessibilityValue(for:)) ?? "No week selected"
        )
        .accessibilityHint("Swipe up or down to inspect another week")
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
    }

    private func barHeight(for value: Double, availableHeight: CGFloat) -> CGFloat {
        guard value > 0 else { return 4 }
        return max(8, availableHeight * CGFloat(value / scaleDenominator))
    }

    private var selectionHeader: some View {
        HStack(spacing: 6) {
            if let selectedPoint {
                Text(periodLabel(for: selectedPoint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                Text("\(metricTitle) · \(valueLabel(selectedPoint.value))")
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text("PEAK")
                    .tracking(0.8)
                Spacer()
                Text(valueLabel(displayedMaximum))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(IronTheme.secondaryText)
        // A fixed row prevents selecting a week from moving the plot.
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func barColor(for point: HistoryTrendPoint, isSelected: Bool) -> Color {
        guard point.value > 0 else {
            return isSelected
                ? IronTheme.accent.opacity(0.55)
                : (point.isCurrent ? IronTheme.accent.opacity(0.28) : IronTheme.outline.opacity(0.32))
        }
        if isSelected { return IronTheme.accent }
        return point.isCurrent ? IronTheme.accent : IronTheme.accent.opacity(0.48)
    }

    private func shouldShowLabel(at index: Int, point: HistoryTrendPoint) -> Bool {
        if points.count <= 7 { return true }
        if point.isCurrent || index == 0 || index == points.count - 1 { return true }
        let stride = max(points.count / 4, 1)
        return index % stride == 0
    }

    private func selectPoint(
        at xPosition: CGFloat,
        width: CGFloat,
        producesHaptic: Bool = true
    ) {
        guard !points.isEmpty, width > 0 else { return }
        let clampedX = min(max(xPosition, 0), max(width - 0.001, 0))
        let index = min(Int((clampedX / width) * CGFloat(points.count)), points.count - 1)
        let id = points[index].id
        guard selectedPointID != id else { return }
        selectedPointID = id
        if producesHaptic {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        let currentIndex = selectedPointID.flatMap { id in points.firstIndex { $0.id == id } }
            ?? (points.count - 1)
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(currentIndex + 1, points.count - 1)
        case .decrement:
            nextIndex = max(currentIndex - 1, 0)
        @unknown default:
            nextIndex = currentIndex
        }
        selectedPointID = points[nextIndex].id
    }

    private func selectionGuide(
        for point: HistoryTrendPoint,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let index = points.firstIndex { $0.id == point.id } ?? 0
        let slotWidth = width / CGFloat(max(points.count, 1))
        let xPosition = (CGFloat(index) + 0.5) * slotWidth

        return Rectangle()
            .fill(IronTheme.accent.opacity(0.34))
            .frame(width: 1, height: height)
            .position(x: xPosition, y: height / 2)
            .allowsHitTesting(false)
    }

    private func detailCallout(for point: HistoryTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(periodLabel(for: point))
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text("\(metricTitle) · \(valueLabel(point.value))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            HStack(spacing: 0) {
                detailMetric("Workouts", value: "\(point.workoutCount)")
                detailMetric("Sets", value: "\(point.sets)")
                detailMetric("Reps", value: "\(point.repetitions)")
            }

            HStack(spacing: 0) {
                detailMetric("Time", value: durationLabel(point.duration))
                detailMetric("Volume", value: volumeLabel(point.volume))
                detailMetric(
                    "Effort",
                    value: point.averageEffort.map { String(format: "%.1f/10", $0) } ?? "—"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func detailMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.55)
                .foregroundColor(IronTheme.tertiaryText)
            Text(value)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func periodLabel(for point: HistoryTrendPoint) -> String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: point.end) ?? point.end
        return "\(point.id.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = max(Int(duration / 60), 0)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func volumeLabel(_ volume: Double) -> String {
        let value: String
        if volume >= 1_000_000 {
            value = String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            value = String(format: "%.1fk", volume / 1_000)
        } else {
            value = String(format: "%.0f", volume)
        }
        return "\(value) \(weightUnit.unit.symbol)"
    }

    private func accessibilityLabel(for point: HistoryTrendPoint) -> String {
        var values = [
            periodLabel(for: point),
            "\(metricTitle) \(valueLabel(point.value))",
            "\(point.workoutCount) \(point.workoutCount == 1 ? "workout" : "workouts")",
            "\(point.sets) sets",
            "\(point.repetitions) repetitions",
            durationLabel(point.duration),
            volumeLabel(point.volume)
        ]
        if let averageEffort = point.averageEffort {
            values.append(String(format: "average effort %.1f out of 10", averageEffort))
        }
        return values.joined(separator: ", ")
    }

    private func accessibilityValue(for point: HistoryTrendPoint) -> String {
        "Selected \(periodLabel(for: point)), \(metricTitle) \(valueLabel(point.value))"
    }
}

private struct WeeklyMuscleLoad: Identifiable {
    let id: String
    let title: String
    let sets: Int
    let fraction: Double
}

private struct WeeklyMuscleBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [WeeklyMuscleLoad]

    private var totalTargetedSets: Int {
        items.reduce(0) { $0 + $1.sets }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IronModalBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if items.isEmpty {
                            emptyState
                        } else {
                            summaryCard
                            distributionCard

                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(IronTheme.accent)
                                Text("A completed set is counted for every primary muscle assigned to its exercise, so targeted sets can exceed your workout set total.")
                                    .font(.caption)
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(IronTheme.horizontalPadding)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Muscle Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .ironScreen()
    }

    private var emptyState: some View {
        IronCard {
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(IronTheme.accent)
                Text("No muscle load yet")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Complete a working set and Iron will map your weekly distribution here.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var summaryCard: some View {
        IronCard {
            HStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST 7 DAYS")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundColor(IronTheme.secondaryText)
                    Text("\(totalTargetedSets) targeted \(totalTargetedSets == 1 ? "set" : "sets")")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                    if let leading = items.first {
                        Text("Most trained: \(leading.title)")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }

                Spacer()
            }
        }
    }

    private var distributionCard: some View {
        IronCard {
            VStack(alignment: .leading, spacing: 16) {
                IronSectionTitle(title: "Distribution", detail: "SETS")

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Spacer()
                            Text("\(item.sets)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundColor(IronTheme.accent)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(IronTheme.raisedSurface)
                                Capsule(style: .continuous)
                                    .fill(IronTheme.accent)
                                    .frame(width: max(8, proxy.size.width * CGFloat(item.fraction)))
                            }
                        }
                        .frame(height: 8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.title), \(item.sets) sets")
                    }
                }
            }
        }
    }
}

private struct WorkoutProgressCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject var workout: Workout

    private var exercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    private var durationText: String {
        guard let duration = workout.duration else { return "—" }
        return Workout.durationFormatter.string(from: duration) ?? "—"
    }

    private var volumeText: String {
        guard let volume = workout.totalCompletedWeight else { return "—" }
        return WeightUnit.format(weight: volume, from: .metric, to: settingsStore.weightUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.displayTitle(in: exerciseStore.exercises))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text(Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date"))
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
                Spacer()
                workout.muscleGroupImage(in: exerciseStore.exercises)
                    .font(.title2)
            }

            HStack(spacing: 14) {
                Label(durationText, systemImage: "clock")
                Label("\(workout.numberOfCompletedSets ?? 0) sets", systemImage: "checkmark.circle")
                Label(volumeText, systemImage: "scalemass")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(IronTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(exercises.compactMap { $0.exercise(in: exerciseStore.exercises)?.title }.joined(separator: " • "))
                .font(.caption)
                .foregroundColor(IronTheme.tertiaryText)
                .lineLimit(2)

            if let effort = workout.sessionEffortValue {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text("Session effort \(Int(effort))/10")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(IronTheme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
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
