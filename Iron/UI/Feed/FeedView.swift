//
//  FeedView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 19.06.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import Combine
import PhotosUI
import UIKit
import WorkoutDataKit

struct FeedView : View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    @EnvironmentObject private var sceneState: SceneState
    @ObservedObject private var bodyMetricsStore = BodyMetricsStore.shared

    @FetchRequest(fetchRequest: FeedView.workoutFetchRequest) private var workouts: FetchedResults<Workout>
    @FetchRequest(fetchRequest: FeedView.currentWorkoutFetchRequest) private var currentWorkouts: FetchedResults<Workout>
    @FetchRequest(fetchRequest: FeedView.planFetchRequest) private var workoutPlans: FetchedResults<WorkoutPlan>

    @State private var showingMeasurements = false
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

    static var planFetchRequest: NSFetchRequest<WorkoutPlan> {
        let request: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutPlan.title, ascending: true)]
        return request
    }

    private var routines: [WorkoutRoutine] {
        workoutPlans.flatMap { $0.workoutRoutines?.array as? [WorkoutRoutine] ?? [] }
    }

    private var activeRoutineObjectID: NSManagedObjectID? {
        currentWorkouts.first?.workoutRoutine?.objectID
    }

    private var completedWorkouts: [Workout] {
        workouts.filter { $0.hasCompletedSets ?? false }
    }

    private var recentWorkouts: [Workout] {
        Array(completedWorkouts.prefix(8))
    }

    private var workoutsThisWeek: [Workout] {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return completedWorkouts.filter { ($0.start ?? .distantPast) >= start }
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

    private func start(_ routine: WorkoutRoutine) {
        do {
            _ = try Workout.startNew(in: managedObjectContext, routine: routine)
            sceneState.selectedTab = .workout
            sceneState.isCurrentWorkoutExpanded = true
        } catch {
            persistenceError = "The workout was not started. \(error.localizedDescription)"
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentWorkouts.isEmpty ? "READY WHEN YOU ARE" : "WORKOUT IN PROGRESS")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundColor(IronTheme.accent)
                    Text(currentWorkouts.first.map { $0.displayTitle(in: exerciseStore.exercises) } ?? "Build today’s session")
                        .font(.title2.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                }
                Spacer()
                Image(systemName: currentWorkouts.isEmpty ? "bolt.fill" : "figure.strengthtraining.traditional")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(IronTheme.accentSoft))
            }

            Text(heroDescription)
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                if currentWorkouts.isEmpty { startEmptyWorkout() }
                else {
                    sceneState.selectedTab = .workout
                    sceneState.isCurrentWorkoutExpanded = true
                }
            }) {
                HStack {
                    Image(systemName: currentWorkouts.isEmpty ? "plus" : "play.fill")
                    Text(currentWorkouts.isEmpty ? "Start Empty Workout" : "Resume Workout")
                }
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
        .padding(.vertical, 4)
    }

    private var heroDescription: String {
        guard !currentWorkouts.isEmpty else {
            return "Start empty or choose a saved workout. Your latest values will be ready on every set."
        }
        guard settingsStore.watchCompanion else {
            return "Your session is saved continuously on this iPhone."
        }
        return WatchConnectionManager.shared.isReachable
            ? "Your session is saved continuously and syncing live with Apple Watch."
            : "Your session is saved on this iPhone; Watch changes will sync when it reconnects."
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "This week", detail: "MON – SUN")
            HStack(spacing: 0) {
                dashboardMetric(icon: "calendar", value: "\(workoutsThisWeek.count)", label: "Workouts")
                dashboardMetricDivider
                dashboardMetric(
                    icon: "checkmark.circle.fill",
                    value: "\(completedSetsThisWeek)",
                    label: "Sets",
                    tint: IronTheme.success
                )
                dashboardMetricDivider
                dashboardMetric(
                    icon: "scalemass.fill",
                    value: compactWeight(volumeThisWeek),
                    label: "Volume",
                    tint: IronTheme.warning
                )
            }
            .padding(.vertical, 14)
            .overlay(IronHairline(opacity: 0.48), alignment: .top)
            .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Calendar", detail: "TRAINING DAYS")

            NavigationLink(destination: WorkoutCalendarView()) {
                HStack(spacing: 13) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                .fill(IronTheme.accentSoft)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open training calendar")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Workouts, rest days, and your \(trainingStreak)-week streak")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(IronHairline(opacity: 0.48), alignment: .top)
            .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
        }
    }

    private func compactWeight(_ kilograms: Double) -> String {
        let value = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        if value >= 10_000 { return String(format: "%.1fk", value / 1_000) }
        return String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Workouts", detail: routines.isEmpty ? "CREATE IN WORKOUT" : "\(routines.count) SAVED")
            if routines.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.title2)
                        .foregroundColor(IronTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No saved workouts yet")
                            .font(.headline)
                            .foregroundColor(IronTheme.primaryText)
                        Text("Build repeatable training days from the Workout tab.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                        let isActiveRoutine = activeRoutineObjectID == routine.objectID
                        let isBlockedByAnotherWorkout = !currentWorkouts.isEmpty && !isActiveRoutine

                        Button(action: {
                            if isActiveRoutine {
                                sceneState.selectedTab = .workout
                                sceneState.isCurrentWorkoutExpanded = true
                            } else {
                                start(routine)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(IronTheme.accent)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(IronTheme.accentSoft))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(routine.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(IronTheme.primaryText)
                                        .lineLimit(1)
                                    Text(routine.subtitle(in: exerciseStore.exercises))
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(isActiveRoutine ? "Resume" : "Start")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(isBlockedByAnotherWorkout ? IronTheme.secondaryText : IronTheme.accent)
                                Image(systemName: isBlockedByAnotherWorkout ? "lock.fill" : (isActiveRoutine ? "play.fill" : "arrow.right"))
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(isBlockedByAnotherWorkout ? IronTheme.secondaryText : IronTheme.accent)
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBlockedByAnotherWorkout)
                        .opacity(isBlockedByAnotherWorkout ? 0.62 : 1)

                        if index < routines.count - 1 {
                            IronHairline(opacity: 0.42)
                                .padding(.leading, 52)
                        }
                    }
                }
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            }
        }
    }

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Body", detail: bodyMetricsStore.latest.map { RelativeDateTimeFormatter().localizedString(for: $0.date, relativeTo: Date()).uppercased() } ?? "NO ENTRIES")
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    dashboardMetric(
                        icon: "figure.arms.open",
                        value: measurementText(.bodyWeight),
                        label: "Weight",
                        tint: IronTheme.accent
                    )
                    dashboardMetricDivider
                    dashboardMetric(
                        icon: "percent",
                        value: measurementText(.bodyFat),
                        label: "Body fat",
                        tint: IronTheme.warning
                    )
                    dashboardMetricDivider
                    dashboardMetric(
                        icon: "ruler",
                        value: measurementText(.rightBicep),
                        label: "R. bicep",
                        tint: IronTheme.success
                    )
                }
                .padding(.vertical, 14)
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
                Button(action: { showingMeasurements = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(bodyMetricsStore.entries.isEmpty ? "Log First Measurement" : "Log Measurements")
                    }
                }
                .buttonStyle(IronSecondaryButtonStyle())
            }
        }
    }

    private func dashboardMetric(
        icon: String,
        value: String,
        label: String,
        tint: Color = IronTheme.accent
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tint)
                    Text(value)
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Text(label)
                    .font(.caption)
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Label(label, systemImage: icon)
                    .font(.caption)
                    .foregroundColor(tint)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 12)
        .accessibilityElement(children: .combine)
    }

    private var dashboardMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.6))
            .frame(width: 1, height: 46)
    }

    private func measurementText(_ kind: BodyMeasurementKind) -> String {
        guard let value = bodyMetricsStore.latestValue(for: kind) else { return "—" }
        let display = kind.displayValue(from: value, weightUnit: settingsStore.weightUnit)
        return String(format: "%.1f", display)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Recent training", detail: "\(trainingStreak) WEEK STREAK")
            if recentWorkouts.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(IronTheme.accentSoft))
                    Text("Your completed workouts will build a private training timeline here.")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentWorkouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(IronTheme.onAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(IronTheme.success))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.displayTitle(in: exerciseStore.exercises))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(IronTheme.primaryText)
                                    Text(Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date"))
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                }
                                Spacer()
                                Text("\(workout.numberOfCompletedSets ?? 0) sets")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(IronTheme.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(IronTheme.tertiaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        if index < min(recentWorkouts.count, 3) - 1 {
                            IronHairline().padding(.leading, 59)
                        }
                    }
                }
                .overlay(IronHairline(opacity: 0.48), alignment: .top)
                .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IronScreenBackground()
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(dateText)
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                            weeklyOverview
                            calendarSection
                            measurementsSection
                            recentSection
                        }
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 12)
                        // Keep the last dashboard cards fully clear of the
                        // floating native tab bar, matching Profile/Settings.
                        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .alert("Workout Not Started", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
            .navigationDestination(isPresented: $showingMeasurements) {
                BodyMeasurementsView(store: bodyMetricsStore)
                    .environmentObject(settingsStore)
                    .ironScreen()
            }
        }
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
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    overview
                    if !photoEntries.isEmpty {
                        progressPhotosSection
                    }
                    trendSection
                    latestMeasurements
                    historySection
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .navigationTitle("Measures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { openEditor() }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log measurements")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $showingEditor) {
            BodyMeasurementsView(store: store, initialEntryID: editorEntryID)
                .environmentObject(settingsStore)
                .ironScreen()
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

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            IronCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "figure.arms.open")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(IronTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.entries.isEmpty ? "Start your baseline" : "Your latest measurements")
                                .font(.headline)
                                .foregroundColor(IronTheme.primaryText)
                            Text(latestEntrySubtitle)
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Label("Private", systemImage: "lock.fill")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundColor(IronTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(IronTheme.raisedSurface))
                    }
                    .padding(14)

                    IronHairline(opacity: 0.42)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 0) {
                            summaryMetricRow(kind: .bodyWeight, icon: "scalemass.fill")
                            IronHairline(opacity: 0.36).padding(.leading, 46)
                            summaryMetricRow(kind: .bodyFat, icon: "percent")
                            IronHairline(opacity: 0.36).padding(.leading, 46)
                            summaryMetricRow(kind: .waist, icon: "ruler")
                        }
                    } else {
                        HStack(spacing: 0) {
                            summaryMetricColumn(kind: .bodyWeight, icon: "scalemass.fill")
                            summaryMetricDivider
                            summaryMetricColumn(kind: .bodyFat, icon: "percent")
                            summaryMetricDivider
                            summaryMetricColumn(kind: .waist, icon: "ruler")
                        }
                    }
                }
            }

            Button(action: { openEditor() }) {
                Label(store.entries.isEmpty ? "Log first measurements" : "Log measurements",
                      systemImage: "plus.circle.fill")
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
    }

    private var latestEntrySubtitle: String {
        guard let latest = store.latest else {
            return "Track weight, body composition, and circumferences privately."
        }
        return "Updated \(RelativeDateTimeFormatter().localizedString(for: latest.date, relativeTo: Date()))."
    }

    private func summaryMetricColumn(kind: BodyMeasurementKind, icon: String) -> some View {
        let tint = kind == .bodyFat ? IronTheme.warning : IronTheme.accent
        let hasValue = store.latestValue(for: kind) != nil

        return VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: icon)
                .font(.caption)
                .foregroundColor(tint)
                .lineLimit(1)
            Text(latestValueText(for: kind, includeUnit: false))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(hasValue ? kind.unitLabel(weightUnit: settingsStore.weightUnit) : "Not logged")
                .font(.caption2)
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
    }

    private func summaryMetricRow(kind: BodyMeasurementKind, icon: String) -> some View {
        let tint = kind == .bodyFat ? IronTheme.warning : IronTheme.accent
        let hasValue = store.latestValue(for: kind) != nil

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 30)
            Text(kind.title)
                .font(.body)
                .foregroundColor(IronTheme.primaryText)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(latestValueText(for: kind, includeUnit: false))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                Text(hasValue ? kind.unitLabel(weightUnit: settingsStore.weightUnit) : "Not logged")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }

    private var summaryMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.5))
            .frame(width: 1, height: 52)
    }

    private var progressPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Progress photos", detail: "\(photoEntries.count) PRIVATE")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photoEntries) { entry in
                        Button(action: { openEditor(entry.id) }) {
                            VStack(alignment: .leading, spacing: 9) {
                                if let data = entry.progressPhotoData,
                                   let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 176)
                                        .clipped()
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: IronTheme.compactCornerRadius,
                                                style: .continuous
                                            )
                                        )
                                }

                                HStack(spacing: 5) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .lineLimit(1)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(IronTheme.secondaryText)
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Progress photo from \(entry.date.formatted(date: .long, time: .omitted))")
                        .accessibilityHint("Opens this measurement entry")
                    }
                }
                .padding(.trailing, IronTheme.horizontalPadding)
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Progress", detail: selectedTimeFrame.compactTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(featuredKinds) { kind in
                        Button(action: { selectedKind = kind }) {
                            IronChip(title: compactTitle(for: kind), isSelected: selectedKind == kind)
                        }
                        .buttonStyle(.plain)
                    }
                }
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

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedKind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(IronTheme.secondaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(latestValueText(for: selectedKind, includeUnit: false))
                                .font(.system(size: 30, weight: .bold).monospacedDigit())
                                .foregroundColor(IronTheme.primaryText)
                            Text(selectedKind.unitLabel(weightUnit: settingsStore.weightUnit))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.secondaryText)
                        }
                    }

                    Spacer()

                    if let delta = selectedDelta {
                        Label(delta.text, systemImage: delta.symbol)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(delta.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(delta.color.opacity(0.12)))
                    }
                }

                if trendSamples.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.flattrend.xyaxis")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(IronTheme.accent)
                        Text("No \(selectedKind.title.lowercased()) data yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Add this measurement to start its private trend.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    let domainStart = selectedTimeFrame.domainStart(earliestDate: trendSamples.first?.date)
                    let domainEnd = Date()
                    GeometryReader { geometry in
                        let plotWidth = selectedTimeFrame.plotWidth(
                            viewportWidth: geometry.size.width,
                            earliestDate: trendSamples.first?.date
                        )
                        let needsScroll = plotWidth > geometry.size.width + 1
                        Group {
                            if needsScroll {
                                ScrollView(.horizontal, showsIndicators: true) {
                                    BodyMeasurementTrendChart(
                                        samples: trendSamples,
                                        measurementTitle: selectedKind.title,
                                        domainStart: domainStart,
                                        domainEnd: domainEnd,
                                        valueLabel: { value in
                                            let formatted = String(format: value >= 100 ? "%.0f" : "%.1f", value)
                                            return "\(formatted) \(selectedKind.unitLabel(weightUnit: settingsStore.weightUnit))"
                                        }
                                    )
                                    .frame(width: plotWidth, height: 158)
                                }
                                .defaultScrollAnchorCompat_trailing()
                            } else {
                                BodyMeasurementTrendChart(
                                    samples: trendSamples,
                                    measurementTitle: selectedKind.title,
                                    domainStart: domainStart,
                                    domainEnd: domainEnd,
                                    valueLabel: { value in
                                        let formatted = String(format: value >= 100 ? "%.0f" : "%.1f", value)
                                        return "\(formatted) \(selectedKind.unitLabel(weightUnit: settingsStore.weightUnit))"
                                    }
                                )
                            }
                        }
                    }
                    .frame(height: 158)

                    HStack {
                        Text(shortDate(domainStart))
                        Spacer()
                        Text(selectedTimeFrame.compactTitle)
                        Spacer()
                        Text(shortDate(domainEnd))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(IronTheme.tertiaryText)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
        }
    }

    private var latestMeasurements: some View {
        VStack(alignment: .leading, spacing: 16) {
            IronSectionTitle(title: "Latest measurements", detail: "TAP TO GRAPH")
            measurementGroup(title: "Core", kinds: coreKinds)
            measurementGroup(title: "Torso", kinds: torsoKinds)
            measurementGroup(title: "Arms & legs", kinds: limbKinds)
        }
    }

    private func measurementGroup(title: String, kinds: [BodyMeasurementKind]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .foregroundColor(IronTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                    Button(action: { selectedKind = kind }) {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: kind))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(selectedKind == kind ? IronTheme.onAccent : IronTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(selectedKind == kind ? IronTheme.accent : IronTheme.accentSoft)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(IronTheme.primaryText)
                                Text(latestDateText(for: kind))
                                    .font(.caption)
                                    .foregroundColor(IronTheme.secondaryText)
                            }

                            Spacer()

                            Text(latestValueText(for: kind, includeUnit: true))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundColor(store.latestValue(for: kind) == nil ? IronTheme.tertiaryText : IronTheme.primaryText)

                            Image(systemName: "chart.xyaxis.line")
                                .font(.caption.weight(.bold))
                                .foregroundColor(selectedKind == kind ? IronTheme.accent : IronTheme.tertiaryText)
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < kinds.count - 1 {
                        IronHairline().padding(.leading, 59)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "History", detail: "\(store.entries.count) TOTAL")

            if store.entries.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundColor(IronTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No measurement history yet")
                            .font(.headline)
                            .foregroundColor(IronTheme.primaryText)
                        Text("Your saved entries will appear here and remain private.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.surface)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            Button(action: { openEditor(entry.id) }) {
                                HStack(spacing: 12) {
                                    if let data = entry.progressPhotoData,
                                       let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 38, height: 38)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(IronTheme.outline.opacity(0.55), lineWidth: 1))
                                    } else {
                                        Image(systemName: "calendar.circle.fill")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundColor(IronTheme.accent)
                                            .frame(width: 38, height: 38)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(IronTheme.primaryText)
                                        Text(entrySummary(entry))
                                            .font(.caption)
                                            .foregroundColor(IronTheme.secondaryText)
                                    }

                                    Spacer()

                                    if let weight = entry[.bodyWeight] {
                                        Text(displayText(value: weight, kind: .bodyWeight, includeUnit: true))
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .foregroundColor(IronTheme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            IronPopupMenu(title: "Measurement entry", actions: [
                                IronPopupAction(title: "Edit", systemImage: "pencil") { openEditor(entry.id) },
                                IronPopupAction(title: "Delete", systemImage: "trash", role: .destructive) {
                                    entryToDelete = entry
                                }
                            ]) {
                                Image(systemName: "ellipsis")
                                    .font(.headline.weight(.bold))
                                    .foregroundColor(IronTheme.secondaryText)
                                    .frame(width: 40, height: 40)
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)

                        if index < store.entries.count - 1 {
                            IronHairline().padding(.leading, 56)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.surface)
                )
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
            return ("No change", "minus", IronTheme.secondaryText)
        }
        let format = abs(delta) >= 10 ? "%.0f" : "%.1f"
        let text = (delta > 0 ? "+" : "") + String(format: format, delta)
        return (text, delta > 0 ? "arrow.up.right" : "arrow.down.right", IronTheme.accent)
    }

    private func latestEntry(for kind: BodyMeasurementKind) -> BodyMeasurementEntry? {
        store.entries.first { $0[kind] != nil }
    }

    private func latestValueText(for kind: BodyMeasurementKind, includeUnit: Bool) -> String {
        guard let canonical = store.latestValue(for: kind) else { return "—" }
        return displayText(value: canonical, kind: kind, includeUnit: includeUnit)
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
    let samples: [BodyMeasurementTrendSample]
    let measurementTitle: String
    var domainStart: Date? = nil
    var domainEnd: Date? = nil
    let valueLabel: (Double) -> String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Path { path in
                        let y = geometry.size.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(IronTheme.outline.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }

                if samples.count > 1 {
                    areaPath(in: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [IronTheme.accent.opacity(0.24), IronTheme.accent.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(in: geometry.size)
                        .stroke(IronTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(samples) { sample in
                    let position = point(for: sample, in: geometry.size)
                    Circle()
                        .fill(IronTheme.background)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(IronTheme.accent, lineWidth: 3))
                        .position(position)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measurementTitle) trend")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = samples.first, let latest = samples.last else {
            return "No measurements"
        }

        let low = samples.map(\.value).min() ?? latest.value
        let high = samples.map(\.value).max() ?? latest.value
        let change = latest.value - first.value
        let direction: String
        if abs(change) < 0.001 {
            direction = "no overall change"
        } else {
            direction = change > 0 ? "up \(valueLabel(abs(change))) overall" : "down \(valueLabel(abs(change))) overall"
        }

        return "\(samples.count) measurements. \(first.date.formatted(date: .abbreviated, time: .omitted)), \(valueLabel(first.value)). Latest \(latest.date.formatted(date: .abbreviated, time: .omitted)), \(valueLabel(latest.value)). Low \(valueLabel(low)); high \(valueLabel(high)); \(direction)."
    }

    private var minimumValue: Double { samples.map(\.value).min() ?? 0 }
    private var maximumValue: Double { samples.map(\.value).max() ?? 1 }
    private var valueRange: Double { max(maximumValue - minimumValue, max(abs(maximumValue) * 0.04, 1)) }
    private var firstDate: Date { domainStart ?? samples.first?.date ?? Date() }
    private var lastDate: Date { domainEnd ?? samples.last?.date ?? firstDate.addingTimeInterval(1) }

    private func point(for sample: BodyMeasurementTrendSample, in size: CGSize) -> CGPoint {
        let horizontalInset: CGFloat = 7
        let verticalInset: CGFloat = 8
        let dateRange = max(lastDate.timeIntervalSince(firstDate), 1)
        let xFraction = sample.date.timeIntervalSince(firstDate) / dateRange
        let yFraction = (sample.value - minimumValue) / valueRange
        return CGPoint(
            x: horizontalInset + (size.width - horizontalInset * 2) * CGFloat(xFraction),
            y: size.height - verticalInset - (size.height - verticalInset * 2) * CGFloat(yFraction)
        )
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            guard let first = samples.first else { return }
            path.move(to: point(for: first, in: size))
            for sample in samples.dropFirst() {
                path.addLine(to: point(for: sample, in: size))
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        Path { path in
            guard let first = samples.first, let last = samples.last else { return }
            let firstPoint = point(for: first, in: size)
            let lastPoint = point(for: last, in: size)
            path.move(to: CGPoint(x: firstPoint.x, y: size.height))
            path.addLine(to: firstPoint)
            for sample in samples.dropFirst() {
                path.addLine(to: point(for: sample, in: size))
            }
            path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
            path.closeSubpath()
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
    @State private var showingDateEditor = false
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

        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 10) {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(2)
                Spacer()

                HStack(spacing: 5) {
                    TextField(latestPlaceholder(for: kind), text: valueBinding(for: kind))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundColor(invalid ? IronTheme.danger : IronTheme.primaryText)
                        .accessibilityLabel("\(kind.title), \(kind.unitLabel(weightUnit: settingsStore.weightUnit))")
                        .accessibilityHint(invalid ? "Enter a number greater than zero" : "Numeric measurement")

                    Text(kind.unitLabel(weightUnit: settingsStore.weightUnit))
                        .font(.caption.weight(.bold))
                        .foregroundColor(invalid ? IronTheme.danger : IronTheme.secondaryText)
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(width: 132, height: IronTheme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .stroke(
                            invalid ? IronTheme.danger : IronTheme.outline.opacity(0.45),
                            lineWidth: invalid ? 1.5 : 1
                        )
                )
            }

            if invalid {
                Label("Enter a number greater than zero", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(IronTheme.danger)
                    .frame(width: 132, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
    }

    private func fieldsCard(title: String, kinds: [BodyMeasurementKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: title)
            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                    field(kind)
                    if index < kinds.count - 1 {
                        IronHairline(opacity: 0.42)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
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
        ZStack {
            IronScreenBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 1).id("measurement-top")

                        VStack(alignment: .leading, spacing: 5) {
                            IronSectionTitle(
                                title: isReviewingEntry
                                    ? "Measurement"
                                    : (editingEntryID == nil ? "New entry" : "Edit entry"),
                                detail: isReviewingEntry ? "SAVED" : (editingEntryID == nil ? "PRIVATE" : "SAVED ENTRY")
                            )
                            Text(isReviewingEntry
                                 ? "Only values recorded in this entry are shown."
                                 : (editingEntryID == nil
                                    ? "Track only what matters to you. Empty fields are ignored."
                                    : "Update this measurement entry. Empty fields stay omitted."))
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                        }

                        if isReviewingEntry {
                            reviewSummaryCard
                            if progressPhotoData != nil {
                                progressPhotoCard
                            }
                            recordedValuesCard
                        } else {
                            dateCard
                            progressPhotoCard

                            if HealthSettingsView.isSupported {
                                Button(action: syncHealth) {
                                    HStack(spacing: 9) {
                                        if syncingHealth {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: IronTheme.accent))
                                        } else {
                                            Image(systemName: "heart.fill")
                                                .foregroundColor(IronTheme.danger)
                                        }
                                        Text(syncingHealth ? "Reading Apple Health…" : "Import Latest from Apple Health")
                                    }
                                }
                                .buttonStyle(IronSecondaryButtonStyle())
                                .disabled(syncingHealth)

                                if let notice = healthImportNotice {
                                    healthImportNoticeView(notice)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }

                            fieldsCard(title: "Core", kinds: primaryKinds)
                            fieldsCard(title: "Torso", kinds: torsoKinds)
                            fieldsCard(title: "Arms & legs", kinds: limbKinds)

                            if hasInvalidInputs {
                                Label("Correct the highlighted values before saving.", systemImage: "exclamationmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(IronTheme.danger)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else if !canSave {
                                Label("Enter at least one measurement to save.", systemImage: "info.circle")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(IronTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        if editingEntryID == nil, !store.entries.isEmpty {
                            recentEntries { entry in
                                load(entry)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo("measurement-top", anchor: .top)
                                }
                            }
                        }
                    }
                    .padding(IronTheme.horizontalPadding)
                    .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
                }
            }
        }
        .navigationTitle(isReviewingEntry ? "Measurement" : (editingEntryID == nil ? "Log Measurements" : "Edit Measurements"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isReviewingEntry {
                    Button {
                        isEditingFields = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit measurement")
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
        .sheet(isPresented: $showingDateEditor) {
            IronDateTimePickerSheet(
                title: "Measurement date",
                subtitle: "Choose when these measurements were recorded.",
                initialDate: date,
                range: Date.distantPast...Date()
            ) { newDate in
                date = newDate
            }
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

    private func healthImportNoticeView(_ notice: HealthImportNotice) -> some View {
        let tint = notice.isError ? IronTheme.danger : IronTheme.success

        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.13)))

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.isError ? "Apple Health import failed" : "Apple Health imported")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text(notice.message)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: { healthImportNotice = nil }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(IronTheme.raisedSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Apple Health status")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private var reviewSummaryCard: some View {
        IronCard {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IronTheme.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                        .foregroundColor(IronTheme.primaryText)
                    Text(recordedKinds.isEmpty && progressPhotoData == nil
                         ? "No measurements recorded"
                         : "\(recordedKinds.count) updated measurement\(recordedKinds.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var recordedValuesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Recorded", detail: "THIS ENTRY")
            if recordedKinds.isEmpty {
                Text("This entry only saved a progress photo.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                            .fill(IronTheme.surface)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recordedKinds.enumerated()), id: \.element.id) { index, kind in
                        HStack {
                            Text(kind.title)
                                .font(.body)
                                .foregroundColor(IronTheme.primaryText)
                            Spacer()
                            Text(reviewValueText(for: kind))
                                .font(.body.monospacedDigit())
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        .padding(.vertical, 10)
                        if index < recordedKinds.count - 1 {
                            IronHairline(opacity: 0.42)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                        .fill(IronTheme.surface)
                )
            }
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

    private var dateCard: some View {
        VStack(spacing: 10) {
            IronCard {
                IronDateTimeButton(
                    title: "Measurement date",
                    systemImage: "calendar.badge.clock",
                    date: date,
                    compactValue: true,
                    action: { showingDateEditor = true }
                )
            }

            if editingEntryID != nil {
                Button(action: startNewEntry) {
                    Label("Start a new entry", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(IronTheme.accentSoft))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progressPhotoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Progress photo", detail: "PRIVATE")

            VStack(spacing: 12) {
                if let data = progressPhotoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipped()
                        .clipShape(
                            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        )
                        .overlay(alignment: .bottomLeading) {
                            Label("Progress photo", systemImage: "lock.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(IronTheme.onMedia)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Capsule(style: .continuous).fill(IronTheme.mediaBadgeSurface))
                                .padding(10)
                        }

                    HStack(spacing: 10) {
                        if !isReviewingEntry {
                            PhotosPicker(
                                selection: $progressPhotoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(IronSecondaryButtonStyle())

                            Button(role: .destructive, action: {
                                progressPhotoData = nil
                                progressPhotoItem = nil
                                progressPhotoError = nil
                            }) {
                                Label("Remove", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(IronConfirmationButtonStyle(tint: IronTheme.danger))
                        }
                    }
                } else {
                    PhotosPicker(
                        selection: $progressPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 9) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundColor(IronTheme.accent)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(IronTheme.accentSoft))
                            Text("Add progress photo")
                                .font(.headline)
                                .foregroundColor(IronTheme.primaryText)
                            Text("Compare your physique over time")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 168)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if isLoadingProgressPhoto {
                    HStack(spacing: 8) {
                        ProgressView().tint(IronTheme.accent)
                        Text("Preparing photo…")
                            .font(.caption.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if let progressPhotoError {
                    Label(progressPhotoError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundColor(IronTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label("Stored locally and included in Iron backups", systemImage: "lock.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(IronTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
        }
    }

    private func recentEntries(onEdit: @escaping (BodyMeasurementEntry) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "History", detail: "\(store.entries.count) TOTAL")
            LazyVStack(spacing: 0) {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 8) {
                        Button(action: { onEdit(entry) }) {
                            HStack(spacing: 12) {
                                if let data = entry.progressPhotoData,
                                   let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(IronTheme.outline.opacity(0.55), lineWidth: 1))
                                } else {
                                    Image(systemName: editingEntryID == entry.id ? "pencil.circle.fill" : "calendar.circle.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(editingEntryID == entry.id ? IronTheme.warning : IronTheme.accent)
                                        .frame(width: 40, height: 40)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(IronTheme.primaryText)
                                    Text(historySummary(entry))
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                }

                                Spacer()

                                if let weight = entry[.bodyWeight] {
                                    Text(String(
                                        format: "%.1f %@",
                                        BodyMeasurementKind.bodyWeight.displayValue(from: weight, weightUnit: settingsStore.weightUnit),
                                        BodyMeasurementKind.bodyWeight.unitLabel(weightUnit: settingsStore.weightUnit)
                                    ))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundColor(IronTheme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        IronPopupMenu(title: "Measurement entry", actions: [
                            IronPopupAction(title: "Edit", systemImage: "pencil") { onEdit(entry) },
                            IronPopupAction(title: "Delete", systemImage: "trash", role: .destructive) {
                                measurementToDelete = entry
                            }
                        ]) {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(IronTheme.secondaryText)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < store.entries.count - 1 {
                        Divider().background(IronTheme.outline).padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
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
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("No Pinned Charts")
                            .font(.headline)
                        Text("Pin an exercise chart from Home to keep it close at hand.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
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
