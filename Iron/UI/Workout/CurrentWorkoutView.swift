//
//  CurrentWorkoutView.swift
//  Iron
//
//  Iron's native inline workout logger for focused, one-handed set entry.
//

import SwiftUI
import StoreKit
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import CoreData
import MuscleMap
import WorkoutDataKit

private struct CurrentWorkoutScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PersonalRecordBanner: Identifiable, Equatable {
    let id = UUID()
    let exerciseTitle: String
    let detail: String
}

struct CurrentWorkoutView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var restTimerStore: RestTimerStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var workout: Workout
    @ObservedObject private var watchConnection = WatchConnectionManager.shared
    let onMinimize: () -> Void

    @State private var activeSheet: SheetType?
    @State private var showingExerciseSelector = false
    @State private var showingFinishEditor = false
    @State private var showingDiscardConfirmation = false
    @State private var showingFinishDiscardConfirmation = false
    @State private var finishTitle = ""
    @State private var sessionEffort = 0.0
    @State private var finishRecap = FinishWorkoutRecap()
    @State private var finishMediaItem: PhotosPickerItem?
    @State private var finishMediaURL: URL?
    @State private var finishMediaKind = FinishWorkoutMediaKind.image
    @State private var isLoadingFinishMedia = false
    @State private var finishMediaError: String?
    @State private var finishStartDate = Date()
    @State private var showingFinishStartDateEditor = false
    @State private var finishDuration: TimeInterval = 0
    @State private var updateLinkedRoutine = false
    @State private var syncWithHealth = true
    @State private var showingVisibilityInfo = false
    @State private var isSessionHeaderCollapsed = false
    @State private var isFinishingWorkout = false
    @State private var persistenceError: String?
    @State private var restTimerEditorExercise: WorkoutExercise?
    @State private var exercisePendingRemoval: WorkoutExercise?
    @State private var exercisePendingReplacement: WorkoutExercise?
    @State private var supersetExercise: WorkoutExercise?
    @State private var personalRecordBanner: PersonalRecordBanner?
    @State private var scrollTarget: NSManagedObjectID?
    @State private var runningSetTimers: [NSManagedObjectID: Date] = [:]
    @State private var restPillExerciseID: NSManagedObjectID?
    @State private var restPillSetID: NSManagedObjectID?
    @State private var isRestPillVisible = false
    @State private var restPillRevealsAt: Date?
    @State private var restRingPulses = false
    @State private var restEndFeedback = 0

    init(workout: Workout, onMinimize: @escaping () -> Void = {}) {
        self.workout = workout
        self.onMinimize = onMinimize
    }

    private enum SheetType: Identifiable {
        case workoutTime
        case restTimer
        case workoutOptions
        case plates(WorkoutSet)
        case warmups(WorkoutSet)

        var id: String {
            switch self {
            case .workoutTime: return "workout-time"
            case .restTimer: return "rest-timer"
            case .workoutOptions: return "workout-options"
            case .plates(let set): return "plates-\(set.objectID.uriRepresentation().absoluteString)"
            case .warmups(let set): return "warmups-\(set.objectID.uriRepresentation().absoluteString)"
            }
        }
    }

    private var workoutExercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    private var exercisePendingRemovalTitle: String {
        exercisePendingRemoval?.exercise(in: exerciseStore.exercises)?.title ?? "this exercise"
    }

    private var usesAccessibilityHeaderLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var workoutTopBarHeight: CGFloat {
        usesAccessibilityHeaderLayout ? 64 : 56
    }

    private var watchSyncBannerHeight: CGFloat {
        usesAccessibilityHeaderLayout ? 68 : 56
    }

    private let muscleMapHeight: CGFloat = 54
    private let workoutSummaryVerticalPadding: CGFloat = 12

    /// Derived from the muscle map rather than hardcoded: the header is clipped,
    /// so a summary shorter than its tallest child visibly cuts the body figures.
    private var workoutSummaryHeight: CGFloat {
        usesAccessibilityHeaderLayout
            ? 84
            : muscleMapHeight + workoutSummaryVerticalPadding * 2
    }

    private var sessionHeaderExpandedHeight: CGFloat {
        watchSyncBannerHeight + workoutSummaryHeight + 1
    }

    private var workoutTitle: Binding<String> {
        Binding(
            get: { workout.title ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                workout.title = trimmed.isEmpty ? nil : value
                save()
            }
        )
    }

    private var workoutComment: Binding<String> {
        Binding(
            get: { workout.comment ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                workout.comment = trimmed.isEmpty ? nil : value
                save()
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    workoutTopBar
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            if !isSessionHeaderCollapsed {
                                sessionHeader
                            }

                            ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: CurrentWorkoutScrollOffsetPreferenceKey.self,
                                            value: proxy.frame(in: .named("current-workout-scroll")).minY
                                        )
                                    }
                                    .frame(height: 0)

                                    workoutMetadata

                                    if workoutExercises.isEmpty {
                                        emptyWorkoutState
                                    } else {
                                        ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                                            workoutExerciseSection(workoutExercise, index: index)
                                        }
                                    }

                                    if !workoutExercises.isEmpty {
                                        Button {
                                            showingExerciseSelector = true
                                        } label: {
                                            Label("Add Exercises", systemImage: "plus")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .ironProminentGlassButtonStyle()
                                        .buttonBorderShape(.capsule)
                                        .controlSize(.large)
                                        .padding(.horizontal, IronTheme.horizontalPadding)
                                        .padding(.top, 18)
                                    }

                                    workoutBottomActions
                                }
                            }
                            .coordinateSpace(name: "current-workout-scroll")
                            .onPreferenceChange(CurrentWorkoutScrollOffsetPreferenceKey.self) { offset in
                                // Use hysteresis so a small bounce cannot make the two header
                                // presentations flicker. Returning to the real top always
                                // restores the complete summary.
                                if offset <= -64, !isSessionHeaderCollapsed {
                                    setSessionHeaderCollapsed(true)
                                } else if offset >= -1, isSessionHeaderCollapsed {
                                    setSessionHeaderCollapsed(false)
                                }
                            }
                            .onChange(of: scrollTarget) { _, target in
                                guard let target else { return }
                                withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                                    scrollProxy.scrollTo(target, anchor: .top)
                                }
                                scrollTarget = nil
                            }
                            }
                        }

                        if isSessionHeaderCollapsed {
                            collapsedWorkoutSummaryPill
                                .padding(.horizontal, IronTheme.horizontalPadding)
                                .padding(.top, 8)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                                .zIndex(2)
                        }

                        if let banner = personalRecordBanner {
                            personalRecordBannerView(banner)
                                .padding(.horizontal, IronTheme.horizontalPadding)
                                .padding(.top, isSessionHeaderCollapsed ? 62 : 8)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                                .zIndex(3)
                        }
                    }
                }
                .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: $showingExerciseSelector) {
            persistenceAlert(AddExercisesSheet(
                exercises: exerciseStore.shownExercises,
                recentExercises: AddExercisesSheet.loadRecentExercises(
                    context: managedObjectContext,
                    exercises: exerciseStore.shownExercises
                ),
                title: exercisePendingReplacement == nil ? "Add Exercise" : "Replace Exercise",
                actionTitle: exercisePendingReplacement == nil ? "Add" : "Replace",
                maximumSelectionCount: exercisePendingReplacement == nil ? nil : 1,
                onDismiss: {
                    guard persistenceError == nil else { return }
                    showingExerciseSelector = false
                    exercisePendingReplacement = nil
                },
                shouldDismiss: { persistenceError == nil },
                onAdd: { _ = applyExerciseSelection($0) }
            ))
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)        }
        .sheet(isPresented: $showingFinishEditor) {
            finishWorkoutSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)                .interactiveDismissDisabled(isLoadingFinishMedia || isFinishingWorkout)
        }
        .sheet(item: $activeSheet) { sheet in
            persistenceAlert(sheetView(sheet))
        }
        .sheet(item: $restTimerEditorExercise) { workoutExercise in
            let inheritedDuration = workoutDefaultRestTimerDuration(for: workoutExercise)
            persistenceAlert(RestTimerConfigurationSheet(
                title: "Rest timer",
                subtitle: "Recovery after each completed set",
                initialDuration: workoutExercise.restTimerDurationValue ?? inheritedDuration,
                secondaryActionTitle: workoutExercise.restTimerDurationValue == nil
                    ? "Keep workout default · \(restTimerDurationFormatter.string(from: inheritedDuration) ?? "0:00")"
                    : "Use workout default · \(restTimerDurationFormatter.string(from: inheritedDuration) ?? "0:00")",
                onSecondaryAction: {
                    setRestTimer(nil, for: workoutExercise)
                },
                shouldDismiss: { persistenceError == nil },
                onApply: { duration in
                    setRestTimer(duration, for: workoutExercise)
                }
            ))
        }
        // An alert, not a confirmation dialog: this is irreversible, so it should
        // dim the log behind it and demand an explicit choice.
        .alert("Discard this workout?", isPresented: $showingDiscardConfirmation) {
            Button("Discard Workout", role: .destructive) {
                showingDiscardConfirmation = false
                cancelWorkout()
            }
            Button("Cancel", role: .cancel) {
                showingDiscardConfirmation = false
            }
        } message: {
            Text("The workout, its notes, and every logged set will be permanently deleted.")
        }
        .alert("Workout Not Saved", isPresented: Binding(
            get: {
                persistenceError != nil
                    && !showingFinishEditor
                    && !showingExerciseSelector
                    && activeSheet == nil
                    && restTimerEditorExercise == nil
            },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
        .alert(
            "Remove \(exercisePendingRemovalTitle)?",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            )
        ) {
            Button("Remove Exercise", role: .destructive) {
                guard let workoutExercise = exercisePendingRemoval else { return }
                exercisePendingRemoval = nil
                DispatchQueue.main.async {
                    deleteWorkoutExercise(workoutExercise)
                }
            }
            Button("Cancel", role: .cancel) {
                exercisePendingRemoval = nil
            }
        } message: {
            Text("Every set logged for this exercise in the current workout will be removed.")
        }
        .confirmationDialog(
            "Superset",
            isPresented: Binding(
                get: { supersetExercise != nil },
                set: { if !$0 { supersetExercise = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let source = supersetExercise {
                ForEach(workoutExercises.filter { $0.objectID != source.objectID }) { candidate in
                    Button(supersetCandidateTitle(candidate)) {
                        if assignSuperset(between: source, and: candidate) {
                            supersetExercise = nil
                        }
                    }
                }

                if source.supersetUuid != nil {
                    Button("Remove from Superset", role: .destructive) {
                        if removeFromSuperset(source) {
                            supersetExercise = nil
                        }
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                supersetExercise = nil
            }
        } message: {
            if let source = supersetExercise {
                Text("Choose an exercise to alternate with \(supersetCandidateTitle(source)).")
            }
        }
        .ironScreen()
        .onAppear {
            isSessionHeaderCollapsed = false
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ironInspectAddExercises") {
                showingExerciseSelector = true
            } else if ProcessInfo.processInfo.arguments.contains("-ironInspectFinishWorkout") {
                showingFinishEditor = true
            }
            #endif
            applyIdleTimerPreference()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: settingsStore.keepScreenAwakeDuringWorkout) { _, _ in
            applyIdleTimerPreference()
        }
        .task(id: restPillTimerSnapshot) {
            await updateRestPillPresentation()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: restEndFeedback) { _, _ in
            settingsStore.workoutHaptics
        }
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = settingsStore.keepScreenAwakeDuringWorkout
    }

    private func persistenceAlert<Content: View>(_ content: Content) -> some View {
        content.alert("Workout Not Saved", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: SheetType) -> some View {
        switch sheet {
        case .workoutTime:
            utilitySheet(
                title: "Workout Duration",
                subtitle: "",
                systemImage: "stopwatch",
                detents: [.large]
            ) {
                EditCurrentWorkoutTimeView(workout: workout) {
                    if save() { activeSheet = nil }
                }
            }

        case .restTimer:
            IronUtilitySheet(
                title: "Rest Timer",
                subtitle: "Dial in your recovery",
                systemImage: "timer",
                onClose: { activeSheet = nil }
            ) {
                RestTimerView()
                    .environmentObject(restTimerStore)
            }
            // Running and selector states now use one bottom-sheet language;
            // their contextual actions are the only visual difference.
            .presentationDetents([.height(RestTimerSheetLayout.height)])
            .presentationDragIndicator(.visible)

        case .workoutOptions:
            NavigationStack {
                GeneralSettingsView()
                    .navigationTitle("Workout Options")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)

        case .plates(let set):
            utilitySheet(
                title: "Plate Calculator",
                subtitle: "",
                systemImage: "plusminus",
                detents: [.large]
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: max(displayWeight(for: set), settingsStore.weightUnit.barbellWeight),
                    onApply: { value in
                        let metricWeight = WeightUnit.convert(
                            weight: value,
                            from: settingsStore.weightUnit,
                            to: .metric
                        )
                        let saved = persistMutation {
                            if let workoutExercise = set.workoutExercise {
                                workoutSets(for: workoutExercise).forEach { workoutSet in
                                    workoutSet.weightValue = metricWeight
                                }
                            } else {
                                set.weightValue = metricWeight
                            }
                        }
                        if saved {
                            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
                            activeSheet = nil
                        }
                    }
                )
            }

        case .warmups(let set):
            utilitySheet(
                title: "Warm-Up Calculator",
                subtitle: "",
                systemImage: "flame",
                detents: [.large]
            ) {
                WarmupCalculatorView(
                    unit: settingsStore.weightUnit,
                    workingWeight: max(displayWeight(for: set), settingsStore.weightUnit.barbellWeight),
                    onAdd: { recommendations in addWarmupSets(recommendations, before: set) }
                )
            }
        }
    }

    private func utilitySheet<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        detents: Set<PresentationDetent>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        IronUtilitySheet(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            onClose: { activeSheet = nil },
            content: content
        )
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)    }

    /// The logger is presented as a sheet, so it owns its own bar. Glass over the
    /// scrolling set list is the one place a floating layer belongs here; an
    /// opaque fill made this read as a third stacked panel above the header.
    private var workoutTopBar: some View {
        HStack(spacing: 10) {
            Button(action: onMinimize) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize Workout")

            Text(usesAccessibilityHeaderLayout ? "Workout" : "Log Workout")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 4)

            restTimerTopBarButton

            Button("Finish") { showingFinishEditor = true }
                .ironProminentGlassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .disabled(workoutExercises.isEmpty)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .frame(height: workoutTopBarHeight)
        .background(.bar)
    }

    /// Timer control beside Finish: a compact timer glyph at rest, and the
    /// live countdown once a rest is running.
    private var restTimerTopBarButton: some View {
        Button { activeSheet = .restTimer } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let remaining = restTimerStore.restTimerRemainingTime {
                    Text(restTimerCountdownText(remaining))
                        .font(.ironMetric(.subheadline, weight: .semibold))
                        .foregroundStyle(restTimerTint)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: Int(remaining))
                        .padding(.horizontal, 10)
                        .accessibilityValue(remaining <= 0 ? "Finished" : restTimerTimeText(remaining))
                } else {
                    Image(systemName: "timer")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IronTheme.metricTime)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: IronTheme.controlHeight, minHeight: IronTheme.controlHeight)
        .background(restTimerTint.opacity(0.18), in: Capsule())
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(restTimerTint)
        .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: restTimerStore.isPaused)
        .accessibilityLabel("Rest timer")
    }

    /// Paused rest keeps the warning tint so it reads differently from a live countdown.
    private var restTimerTint: Color {
        restTimerStore.isPaused ? IronTheme.warning : IronTheme.metricTime
    }

    private func personalRecordBannerView(_ banner: PersonalRecordBanner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "medal.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 1) {
                Text("Personal Record")
                    .font(.footnote.weight(.semibold))
                Text("\(banner.exerciseTitle) · \(banner.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .ironLiquidGlassPill(tint: .clear)
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 7)
        .accessibilityElement(children: .combine)
        .task(id: banner.id) {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) { personalRecordBanner = nil }
        }
    }

    /// Options and discard share one row of matching glass buttons so the end of
    /// the log does not trail off into a lone red text link.
    private var workoutBottomActions: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .workoutOptions
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .ironGlassButtonStyle()

            Button(role: .destructive) {
                showingDiscardConfirmation = true
            } label: {
                Label("Discard", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .ironGlassButtonStyle()
            .tint(.red)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var sessionHeader: some View {
        VStack(spacing: 0) {
            watchSyncBanner

            Divider()
            workoutSummary
                .frame(height: workoutSummaryHeight)
        }
        // A plain conditional swap with the compact pill. An offset-and-clip reveal
        // let individual children linger outside the clip during the transition.
        .frame(height: sessionHeaderExpandedHeight)
        .background(Color(.systemGroupedBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    private var watchSyncColor: Color {
        guard settingsStore.watchCompanion else { return IronTheme.secondaryText }
        guard watchConnection.isPaired else { return IronTheme.secondaryText }
        guard watchConnection.isWatchAppInstalled else { return IronTheme.warning }
        return watchConnection.isReachable ? IronTheme.success : IronTheme.warning
    }

    private var watchSyncTitle: String {
        guard settingsStore.watchCompanion else { return "Saved locally on this iPhone" }
        guard watchConnection.isPaired else { return "Saved on iPhone · Watch not paired" }
        guard watchConnection.isWatchAppInstalled else { return "Saved on iPhone · Install Iron on Watch" }
        if watchConnection.isReachable { return "Live Sync Active" }
        return watchConnection.isActivated
            ? "Watch offline · changes queued"
            : "Watch sync preparing"
    }

    private var watchSyncSystemImage: String {
        guard settingsStore.watchCompanion,
              watchConnection.isPaired,
              watchConnection.isWatchAppInstalled else {
            return "iphone"
        }
        return "applewatch"
    }

    private func setSessionHeaderCollapsed(_ collapsed: Bool) {
        guard collapsed != isSessionHeaderCollapsed else { return }

        withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
            isSessionHeaderCollapsed = collapsed
        }
    }

    private var watchSyncBanner: some View {
        let color = watchSyncColor

        return HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(watchSyncTitle)
                .font(.subheadline)
                .lineLimit(usesAccessibilityHeaderLayout ? 2 : 1)
                .minimumScaleFactor(0.75)
            Spacer()
            Image(systemName: watchSyncSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            Button {
                setSessionHeaderCollapsed(!isSessionHeaderCollapsed)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isSessionHeaderCollapsed ? 180 : 0))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel(isSessionHeaderCollapsed ? "Expand workout summary" : "Collapse workout summary")
        }
        .padding(.leading, IronTheme.horizontalPadding)
        .padding(.trailing, IronTheme.horizontalPadding)
        .frame(height: watchSyncBannerHeight)
    }

    private var workoutSummary: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            HStack(spacing: 0) {
                Button(action: { activeSheet = .workoutTime }) {
                    summaryValue(
                        "Duration",
                        workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00",
                        tint: IronTheme.metricTime,
                        systemImage: "pencil"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit workout duration")
                .accessibilityValue(workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                summaryValue("Volume", workoutVolumeNumber, tint: IronTheme.metricVolume, unit: settingsStore.weightUnit.unit.symbol)
                summaryValue("Sets", "\(workout.numberOfCompletedSets ?? 0)", tint: IronTheme.metricSets)

                if !usesAccessibilityHeaderLayout {
                    liveMuscleMap
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.vertical, workoutSummaryVerticalPadding)
        }
    }

    private var collapsedWorkoutSummaryPill: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            Button(action: { setSessionHeaderCollapsed(false) }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)

                    Text(workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(workoutVolumeTitle)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("\(workout.numberOfCompletedSets ?? 0) sets")

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .font(.ironMetric(.caption))
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: workoutVolumeTitle)
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: workout.numberOfCompletedSets)
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: Int(workout.safeDuration))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            // Keep the compact summary optically above the exercise rows. A clear
            // glass tint preserves refraction without reintroducing an opaque white card.
            .ironLiquidGlassPill(tint: .clear)
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 7)
            .accessibilityLabel("Expand workout summary")
            .accessibilityValue(
                "\(workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00"), \(workoutVolumeTitle), \(workout.numberOfCompletedSets ?? 0) sets"
            )
        }
    }

    private func summaryValue(
        _ label: String,
        _ value: String,
        tint: Color,
        unit: String? = nil,
        systemImage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(label)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.ironMetric(.callout))
                    .foregroundStyle(IronTheme.primaryText)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: value)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedExerciseMuscles: (primary: [Muscle], secondary: [Muscle]) {
        var primary: [Muscle] = []
        var secondary: [Muscle] = []

        for workoutExercise in workoutExercises {
            guard workoutSets(for: workoutExercise).contains(where: \.isCompleted),
                  let exercise = workoutExercise.exercise(in: exerciseStore.exercises) else { continue }

            for muscle in exercise.primaryMuscle.compactMap(mapMuscle) where !primary.contains(muscle) {
                primary.append(muscle)
            }
            for muscle in exercise.secondaryMuscle.compactMap(mapMuscle)
                where !primary.contains(muscle) && !secondary.contains(muscle) {
                secondary.append(muscle)
            }
        }

        return (primary, secondary)
    }

    private var liveMuscleMap: some View {
        let muscles = completedExerciseMuscles
        return HStack(spacing: 2) {
            liveMuscleBody(side: .front, muscles: muscles)
            liveMuscleBody(side: .back, muscles: muscles)
        }
        .frame(height: muscleMapHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            muscles.primary.isEmpty && muscles.secondary.isEmpty
                ? "No muscles logged yet"
                : "Muscles trained in completed sets"
        )
    }

    private func liveMuscleBody(
        side: BodySide,
        muscles: (primary: [Muscle], secondary: [Muscle])
    ) -> some View {
        let style = BodyViewStyle(
            defaultFillColor: Color(.tertiaryLabel).opacity(0.35),
            strokeColor: Color(.separator),
            strokeWidth: 0.5,
            selectionColor: IronTheme.accent,
            selectionStrokeColor: IronTheme.accent,
            selectionStrokeWidth: 1,
            headColor: Color(.tertiaryLabel).opacity(0.45),
            hairColor: Color(.quaternaryLabel)
        )
        return BodyView(gender: .male, side: side, style: style)
            .highlight(muscles.secondary, color: IronTheme.accent, opacity: 0.42)
            .highlight(muscles.primary, color: IronTheme.accent)
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

    @ViewBuilder
    private var workoutMetadata: some View {
        if workout.title != nil || workout.comment != nil {
            VStack(spacing: 0) {
                if workout.title != nil {
                    TextField(suggestedWorkoutTitle, text: workoutTitle)
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 11)
                }
                if workout.comment != nil {
                    TextField("Workout notes", text: workoutComment)
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.vertical, 10)
            .overlay(Divider(), alignment: .bottom)
        }
    }

    private var emptyWorkoutState: some View {
        ContentUnavailableView {
            Label("Start with an Exercise", systemImage: "figure.strengthtraining.traditional")
        } description: {
            Text("Add exercises, then log weight, reps, and effort directly on this screen.")
        } actions: {
            Button("Add Exercises") { showingExerciseSelector = true }
                .ironProminentGlassButtonStyle()
                .buttonBorderShape(.capsule)
        }
        .padding(.top, 24)
    }

    private func workoutExerciseSection(_ workoutExercise: WorkoutExercise, index: Int) -> some View {
        let exercise = workoutExercise.exercise(in: exerciseStore.exercises)
        let sets = workoutSets(for: workoutExercise)
        let isBarbell = exercise?.type == .barbell
        let usesDuration = sets.contains { $0.durationValue != nil }

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let exercise = exercise {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 50)
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "dumbbell.fill").foregroundStyle(.secondary))
                }

                if let exercise = exercise {
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)

                            if workoutExercise.supersetUuid != nil {
                                Label("Superset", systemImage: "link")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .draggable(workoutExercise.objectID.uriRepresentation().absoluteString)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to open. Touch and hold, then drag to reorder.")
                } else {
                    Text("Unknown Exercise")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Menu {
                    exerciseMenuItems(
                        for: workoutExercise,
                        sets: sets,
                        isBarbell: isBarbell && !usesDuration
                    )
                } label: {
                    Label("Exercise Actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
            }

            TextField("Add notes here…", text: exerciseCommentBinding(for: workoutExercise))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 9)

            restTimerMenu(for: workoutExercise)
                .padding(.vertical, 13)

            setTableHeader(
                usesDuration: usesDuration
            )

            ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, set in
                InlineWorkoutSetRow(
                    set: set,
                    index: setIndex,
                    usesDuration: usesDuration,
                    isBarbell: isBarbell && !usesDuration,
                    previousTitle: previousSetTitle(for: workoutExercise, at: setIndex),
                    onOpenPlateCalculator: { activeSheet = .plates(set) },
                    onToggleCompleted: { toggleCompleted(set, in: workoutExercise) },
                    onDelete: { deleteSet(set, from: workoutExercise) },
                    onChanged: {
                        let saved = save()
                        if saved {
                            workout.objectWillChange.send()
                            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
                        }
                        return saved
                    },
                    allowsSwipeToDelete: true,
                    isCurrent: sets.first(where: { !$0.isCompleted })?.objectID == set.objectID
                )
                .environmentObject(settingsStore)
                .transition(
                    reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    )
                )

                if isRestPillVisible,
                   restPillExerciseID == workoutExercise.objectID,
                   restPillSetID == set.objectID {
                    activeRestTimerStrip
                        .padding(.vertical, 6)
                        .transition(restPillTransition)
                }
            }
            .animation(
                IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion),
                value: sets.count
            )

            if isRestPillVisible,
               restPillExerciseID == workoutExercise.objectID,
               !sets.contains(where: { $0.objectID == restPillSetID }) {
                activeRestTimerStrip
                    .padding(.vertical, 6)
                    .transition(restPillTransition)
            }

            Button {
                addSet(to: workoutExercise)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .ironGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .padding(.top, 12)
        }
        .padding(14)
        // One continuous grouped container per exercise. The previous layout
        // stacked five full-bleed rules per block, which is what made the
        // logger read as a flat spreadsheet instead of an Apple surface.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 14)
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first,
                  let source = workoutExercises.firstIndex(where: {
                      $0.objectID.uriRepresentation().absoluteString == payload
                  }),
                  source != index else { return false }
            return moveWorkoutExercise(from: source, to: index)
        }
    }

    @ViewBuilder
    private func exerciseMenuItems(
        for workoutExercise: WorkoutExercise,
        sets: [WorkoutSet],
        isBarbell: Bool
    ) -> some View {
        Button("Replace", systemImage: "arrow.triangle.2.circlepath") {
            exercisePendingReplacement = workoutExercise
            showingExerciseSelector = true
        }

        Button("Superset", systemImage: "link") {
            supersetExercise = workoutExercise
        }

        if isBarbell,
           settingsStore.showPlateCalculator || settingsStore.showWarmUpCalculator,
           let workingSet = sets.first(where: { $0.tagValue != .warmUp }) ?? sets.first {
            Section("Calculators") {
                if settingsStore.showPlateCalculator {
                    Button("Plate Calculator", systemImage: "plusminus") {
                        activeSheet = .plates(workingSet)
                    }
                }
                if settingsStore.showWarmUpCalculator {
                    Button("Warm-up Calculator", systemImage: "flame") {
                        activeSheet = .warmups(workingSet)
                    }
                }
            }
        }

        Section {
            Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                exercisePendingRemoval = workoutExercise
            }
        }
    }

    private func setTableHeader(usesDuration: Bool) -> some View {
        HStack(spacing: InlineWorkoutSetLayout.spacing) {
            Text("Set").frame(width: InlineWorkoutSetLayout.setWidth)
            Text("Previous").frame(width: InlineWorkoutSetLayout.previousWidth, alignment: .center)
            if usesDuration {
                Text("Duration")
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "dumbbell")
                        .accessibilityHidden(true)
                    Text(settingsStore.weightUnit.unit.symbol)
                }
                .frame(maxWidth: .infinity)
                Text("Reps").frame(width: InlineWorkoutSetLayout.repetitionsWidth)
            }
            if settingsStore.logRPE {
                Text("RPE").frame(width: InlineWorkoutSetLayout.rpeWidth)
            }
            Image(systemName: "checkmark")
                .frame(width: InlineWorkoutSetLayout.completionWidth)
                .accessibilityHidden(true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private var activeRestTimerExercise: WorkoutExercise? {
        guard restTimerStore.restTimerRemainingTime != nil else { return nil }

        return workoutExercises.max { lhs, rhs in
            latestCompletedSetDate(in: lhs) < latestCompletedSetDate(in: rhs)
        } ?? workoutExercises.first
    }

    private func latestCompletedSetDate(in workoutExercise: WorkoutExercise) -> Date {
        workoutSets(for: workoutExercise)
            .compactMap(\.completedAt)
            .max() ?? .distantPast
    }

    private struct RestPillTimerSnapshot: Equatable {
        let end: Date?
        let duration: TimeInterval?
        let isPaused: Bool
    }

    private var restPillTimerSnapshot: RestPillTimerSnapshot {
        RestPillTimerSnapshot(
            end: restTimerStore.restTimerEnd,
            duration: restTimerStore.restTimerDuration,
            isPaused: restTimerStore.isPaused
        )
    }

    private var restPillTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    /// Presentation follows the shared timer; no timer or notification work is delayed.
    /// This task is cancelled on adjustment, pause, skip, restart, or dismissal.
    @MainActor
    private func updateRestPillPresentation() async {
        let snapshot = restPillTimerSnapshot
        guard let remaining = restTimerStore.restTimerRemainingTime, remaining > 0,
              let exercise = activeRestTimerExercise else {
            withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
                isRestPillVisible = false
            }
            return
        }

        if !reduceMotion, let revealDate = restPillRevealsAt {
            do {
                try await Task.sleep(for: .seconds(max(0, revealDate.timeIntervalSinceNow)))
            } catch { return }
        }
        guard !Task.isCancelled else { return }

        restRingPulses = false
        withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
            restPillExerciseID = exercise.objectID
            restPillSetID = workoutSets(for: exercise)
                .filter(\.isCompleted)
                .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }?
                .objectID
            isRestPillVisible = true
        }

        guard !snapshot.isPaused, let end = snapshot.end else { return }
        do {
            try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        } catch { return }
        guard !Task.isCancelled, restPillTimerSnapshot == snapshot else { return }

        // Pulse during removal, without holding the pill or delaying the next action.
        restEndFeedback += 1
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            restRingPulses = true
        }
        withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
            isRestPillVisible = false
        }
    }

    private var activeRestTimerStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = restTimerStore.restTimerRemainingTime ?? 0
            let duration = restTimerStore.restTimerDuration ?? 0
            let countdown = restTimerCountdownText(remaining)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    activeRestTimerReadout(remaining: remaining, duration: duration, countdown: countdown)
                    activeRestTimerControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    activeRestTimerReadout(remaining: remaining, duration: duration, countdown: countdown)
                    activeRestTimerControls
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                IronTheme.metricTimeContainer,
                in: RoundedRectangle(cornerRadius: IronTheme.heroCornerRadius, style: .continuous)
            )
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: countdown)
        }
    }

    private func activeRestTimerReadout(remaining: TimeInterval, duration: TimeInterval, countdown: String) -> some View {
        Button(action: { activeSheet = .restTimer }) {
            HStack(spacing: 8) {
                IronRestRing(progress: duration > 0 ? remaining / duration : 0)
                    .scaleEffect(reduceMotion || !restRingPulses ? 1 : 1.12)
                    .opacity(reduceMotion && restRingPulses ? 0.5 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countdown)
                        .font(.ironMetric(.title3))
                        .foregroundStyle(IronTheme.metricTime)
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    Text("Rest of \(restTimerTimeText(duration))")
                        .font(.caption2)
                        .foregroundStyle(IronTheme.secondaryText)
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .frame(minHeight: IronTheme.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(restTimerStore.isPaused ? "Rest timer paused" : "Rest timer")
        .accessibilityValue("\(countdown) remaining of \(restTimerTimeText(duration))")
        .accessibilityHint("Opens the rest timer dial")
    }

    private var activeRestTimerControls: some View {
        HStack(spacing: 0) {
            activeTimerControl(title: "−15", label: "Subtract 15 seconds") {
                adjustActiveRestTimer(by: -15)
            }
            Spacer(minLength: 4)
            activeTimerControl(
                systemImage: restTimerStore.isPaused ? "play.fill" : "pause.fill",
                label: restTimerStore.isPaused ? "Resume rest timer" : "Pause rest timer"
            ) {
                restTimerStore.isPaused ? restTimerStore.resume() : restTimerStore.pause()
                WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
            }
            Spacer(minLength: 4)
            activeTimerControl(title: "+15", label: "Add 15 seconds") {
                adjustActiveRestTimer(by: 15)
            }
            Spacer(minLength: 4)
            activeTimerControl(systemImage: "forward.end.fill", label: "Skip rest", action: stopActiveRestTimer)
        }
        .frame(minWidth: IronTheme.iconButtonSize * 4 + 12)
    }

    private func restTimerTimeText(_ remaining: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: abs(remaining.rounded(.up))) ?? "0:00"
    }

    private func restTimerCountdownText(_ remaining: TimeInterval) -> String {
        restTimerTimeText(max(remaining, 0))
    }

    private func activeTimerControl(
        title: String = "",
        systemImage: String? = nil,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.ironMetric(.caption))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
            .background(IronTheme.field, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(IronTheme.primaryText)
        .accessibilityLabel(label)
    }

    private func adjustActiveRestTimer(by interval: TimeInterval) {
        restTimerStore.adjust(by: interval)
        WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
    }

    private func stopActiveRestTimer() {
        restTimerStore.cancel()
        WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
    }

    private func restTimerMenu(for workoutExercise: WorkoutExercise) -> some View {
        Button {
            restTimerEditorExercise = workoutExercise
        } label: {
            HStack(spacing: 7) {
                Label("Rest Timer", systemImage: "timer")
                Spacer()
                Text(restTimerTitle(for: workoutExercise))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rest timer for \(restTimerTitle(for: workoutExercise))")
        .accessibilityHint("Opens the rest duration picker")
    }

    private var finishWorkoutSheet: some View {
        NavigationStack {
            Form {
                finishHeaderSection
                finishSummarySection
                finishSessionSection
                finishEffortSection
                finishRecordsSection
                finishSyncSection
                finishTitleSection
                finishTimingSection
                finishNotesSection
                finishMediaSection
                finishExerciseSummarySection
                finishDiscardSection
            }
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingFinishEditor = false }
                        .disabled(isFinishingWorkout)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFinishingWorkout ? "Saving…" : "Save", action: finishWorkout)
                        .fontWeight(.semibold)
                        .disabled(isLoadingFinishMedia || isFinishingWorkout)
                }
            }
        }
        .onAppear(perform: prepareFinishEditor)
        .alert("Workout Not Saved", isPresented: Binding(
            get: { persistenceError != nil && showingFinishEditor },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
        .alert("Discard this workout?", isPresented: $showingFinishDiscardConfirmation) {
            Button("Discard Workout", role: .destructive) {
                showingFinishDiscardConfirmation = false
                cancelWorkout()
            }
            Button("Cancel", role: .cancel) { showingFinishDiscardConfirmation = false }
        } message: {
            Text("This workout and its logged sets will be permanently deleted.")
        }
        .onChange(of: finishMediaItem) { _, item in
            guard let item = item else { return }
            Task { await importFinishMedia(item) }
        }
        .sheet(isPresented: $showingVisibilityInfo) {
            finishVisibilityInfoSheet
        }
        .sheet(isPresented: $showingFinishStartDateEditor) {
            IronDateTimePickerSheet(
                title: "Workout started",
                subtitle: "Duration stays the same; Iron adjusts the finish time automatically.",
                initialDate: finishStartDate,
                range: Date.distantPast...Date()
            ) { newDate in
                finishStartDate = newDate
            }
        }
    }

    private var finishHeaderSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IronTheme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(IronTheme.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(finishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? suggestedWorkoutTitle : finishTitle)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(finishDateRange)
                        .font(.subheadline)
                        .foregroundStyle(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var finishDateRange: String {
        if Calendar.current.isDate(finishStartDate, inSameDayAs: finishEndDate) {
            return "\(finishStartDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(finishStartDate.formatted(date: .omitted, time: .shortened))–\(finishEndDate.formatted(date: .omitted, time: .shortened))"
        }
        return "\(finishStartDate.formatted(date: .abbreviated, time: .shortened))–\(finishEndDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private var finishSummarySection: some View {
        Section {
            // Keep the 3 × 2 grid and complete numerals at every text size.
            // Large accessibility sizes can scroll instead of clipping values.
            ViewThatFits(in: .horizontal) {
                finishMetricsGrid
                ScrollView(.horizontal) { finishMetricsGrid }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Session Summary")
        } footer: {
            Text("Review the session, then tap Save to add it to your history.")
        }
    }

    private var finishMetricsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                finishMetric("Duration", value: IronDurationFormat.title(finishDuration), color: IronTheme.metricTime, index: 0)
                finishMetric("Volume", value: workoutVolumeNumber, unit: settingsStore.weightUnit.unit.symbol, color: IronTheme.metricVolume, index: 1)
                finishMetric("Sets", value: "\(finishRecap.setCount)", color: IronTheme.metricSets, index: 2)
            }
            GridRow {
                finishMetric("Exercises", value: "\(finishRecap.exerciseCount)", color: IronTheme.accent, index: 3)
                finishMetric("Avg RPE", value: finishRecap.averageRPE, color: IronTheme.metricEffort, index: 4)
                finishMetric("Records", value: "\(finishRecap.records.count)", color: IronTheme.metricRecord, index: 5)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func finishMetric(_ title: String, value: String, unit: String? = nil, color: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(IronTheme.primaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                finishMetricValue(value, color: color)
                if let unit { Text(unit).font(.caption).foregroundStyle(IronTheme.secondaryText) }
            }
        }
        .frame(minWidth: 80, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value == "–" ? "No rated sets" : "\(value)\(unit.map { " \($0)" } ?? "")")
        .ironStaggeredEntrance(index: index)
    }

    private func finishMetricValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.ironMetric(.title3))
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .fixedSize(horizontal: true, vertical: false)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: value)
    }

    private var finishSessionSection: some View {
        Section {
            if finishRecap.setCount == 0 {
                Text("No completed sets yet")
                    .foregroundStyle(IronTheme.secondaryText)
            } else {
                IronSessionStrip(
                    groups: finishRecap.groups,
                    accessibilityLabel: finishRecap.accessibilitySummary,
                    sessionStart: finishStartDate,
                    volumeUnit: settingsStore.weightUnit.unit.symbol
                )
                    .padding(.vertical, 6)
            }
        } header: {
            Text("Session")
        } footer: {
            Text("Bar height shows set volume. The track shows work and rest, estimating 40 seconds for sets without a recorded duration.")
        }
    }

    @ViewBuilder
    private var finishRecordsSection: some View {
        if !finishRecap.records.isEmpty {
            Section("Personal Records") {
                ForEach(finishRecap.records) { record in
                    FinishWorkoutRecordRow(record: record)
                }
            }
        }
    }

    private var finishTitleSection: some View {
        Section {
            TextField(suggestedWorkoutTitle, text: $finishTitle)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Title")
        } footer: {
            Text("Leave blank to keep \(suggestedWorkoutTitle).")
        }
    }

    private var suggestedWorkoutTitle: String {
        workout.generatedTitle(in: exerciseStore.exercises) ?? "Workout"
    }

    private var finishEffortSection: some View {
        Section {
            FinishWorkoutEffortControl(rating: sessionEffortSelection)
        } footer: {
            Text("Rate your overall session from 1 (easy) to 10 (all out), or leave it unrated.")
        }
    }

    /// Zero represents an unrated session; saving maps it to the model's nil value.
    private var sessionEffortSelection: Binding<Int> {
        Binding(
            get: { min(max(Int(sessionEffort.rounded()), 0), 10) },
            set: { sessionEffort = Double(min(max($0, 0), 10)) }
        )
    }

    private var finishNotesSection: some View {
        Section {
            TextField(
                "What went well? Add context for your future self…",
                text: workoutComment,
                axis: .vertical
            )
            .lineLimit(4...10)
        } header: {
            Text("Notes")
        }
    }

    private var finishMediaSection: some View {
        Section {
            if finishMediaURL != nil {
                finishMediaPreview
            }

            PhotosPicker(
                selection: $finishMediaItem,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label(
                    finishMediaURL == nil ? "Add Photo or Video" : "Replace Media",
                    systemImage: finishMediaURL == nil ? "plus" : "arrow.triangle.2.circlepath"
                )
            }
            .disabled(isLoadingFinishMedia)

            if isLoadingFinishMedia {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving media…")
                        .foregroundStyle(.secondary)
                }
            }

            if let finishMediaError = finishMediaError {
                Text(finishMediaError)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Media")
        } footer: {
            Text("One photo or video per workout. It stays on this device.")
        }
    }

    private var finishMediaPreview: some View {
        HStack(spacing: 12) {
            Group {
                if finishMediaKind == .image,
                   let url = finishMediaURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: finishMediaKind == .video ? "video.fill" : "photo.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(finishMediaKind == .video ? "Video attached" : "Photo attached")

            Spacer()

            Button("Remove", role: .destructive, action: removeFinishMedia)
                .buttonStyle(.borderless)
        }
    }

    private var finishTimingSection: some View {
        Section {
            Button {
                showingFinishStartDateEditor = true
            } label: {
                LabeledContent("Started", value: finishStartDate.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            Text("Timing")
        } footer: {
            Text("Duration stays \(workoutDurationFormatter.string(from: finishDuration) ?? "0:00"); the finish time becomes \(finishEndDate.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private var finishSyncSection: some View {
        Section {
            Toggle(isOn: $syncWithHealth) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sync with Apple Health")
                    Text(syncWithHealth ? "Exports when you save" : "Export off for this session")
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                }
            }

            Toggle("Update Linked Workout", isOn: $updateLinkedRoutine)
                .disabled(workout.workoutRoutine == nil)

            Button {
                showingVisibilityInfo = true
            } label: {
                LabeledContent("Visibility", value: "Private")
            }
            .accessibilityHint("Iron workouts are private. Tap to learn why.")
        } header: {
            Text("Saving")
        } footer: {
            Text(workout.workoutRoutine == nil
                 ? "This session was not started from a saved workout."
                 : "Completed weights and reps are written back to \(workout.workoutRoutine?.displayTitle ?? "the linked workout").")
        }
    }

    private var finishExerciseSummarySection: some View {
        Section("Exercises") {
            ForEach(workoutExercises) { workoutExercise in
                let exercise = workoutExercise.exercise(in: exerciseStore.exercises)
                HStack(spacing: 12) {
                    if let exercise = exercise {
                        ExerciseDiagramThumbnail(exercise: exercise, size: 38)
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 38, height: 38)
                            .overlay(Image(systemName: "dumbbell.fill").foregroundStyle(.secondary))
                    }

                    Text(exercise?.title ?? "Unknown exercise")

                    Spacer()

                    Text("\(workoutExercise.numberOfCompletedSets ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(exercise?.title ?? "Unknown exercise"), \(workoutExercise.numberOfCompletedSets ?? 0) completed sets")
            }
        }
    }

    private var finishDiscardSection: some View {
        Section {
            Button("Discard Workout", role: .destructive) {
                showingFinishDiscardConfirmation = true
            }
            .accessibilityHint("Permanently deletes this workout and its logged sets.")
        }
    }

    private var finishEndDate: Date {
        finishStartDate.addingTimeInterval(max(finishDuration, 0))
    }

    private var finishVisibilityInfoSheet: some View {
        IronUtilitySheet(
            title: "Private by design",
            subtitle: "Visibility for every finished workout",
            systemImage: "lock.fill",
            onClose: { showingVisibilityInfo = false }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Iron has no social feed or public profiles. Finished workouts are always saved as Private · Only you, so your training history stays on this device and in your personal backups.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Only you can see it")
                            .font(.subheadline.weight(.semibold))
                        Text("There is nothing else to publish or configure.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(IronTheme.success)
                }

                Spacer(minLength: 0)
            }
            .padding(IronTheme.horizontalPadding)
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)    }

    private let workoutDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private var workoutVolumeNumber: String {
        let displayWeight = WeightUnit.convert(
            weight: workout.totalCompletedWeight ?? 0,
            from: .metric,
            to: settingsStore.weightUnit
        )
        return settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: displayWeight)) ?? "0"
    }

    private var workoutVolumeTitle: String {
        WeightUnit.format(
            weight: workout.totalCompletedWeight ?? 0,
            from: .metric,
            to: settingsStore.weightUnit
        )
    }

    private func workoutSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func exerciseCommentBinding(for workoutExercise: WorkoutExercise) -> Binding<String> {
        Binding(
            get: { workoutExercise.comment ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                workoutExercise.comment = trimmed.isEmpty ? nil : value
                save()
            }
        )
    }

    @discardableResult
    private func addExercises(_ selection: [Exercise]) -> Bool {
        let saved = persistMutation {
            for exercise in selection {
                let workoutExercise = WorkoutExercise.create(context: managedObjectContext)
                workout.addToWorkoutExercises(workoutExercise)
                workoutExercise.exerciseUuid = exercise.uuid
                workoutExercise.addToWorkoutSets(createDefaultWorkoutSets(for: workoutExercise, exercise: exercise))
            }
        }
        if saved {
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        }
        return saved
    }

    @discardableResult
    private func applyExerciseSelection(_ selection: [Exercise]) -> Bool {
        let saved: Bool
        if let target = exercisePendingReplacement, let replacement = selection.first {
            saved = persistMutation {
                target.exerciseUuid = replacement.uuid
            }
            if saved {
                exercisePendingReplacement = nil
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }
        } else {
            saved = addExercises(selection)
        }
        if saved {
            showingExerciseSelector = false
        }
        return saved
    }

    private func supersetCandidateTitle(_ workoutExercise: WorkoutExercise) -> String {
        workoutExercise.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise"
    }

    @discardableResult
    private func assignSuperset(between source: WorkoutExercise, and candidate: WorkoutExercise) -> Bool {
        let existingIDs = Set([source.supersetUuid, candidate.supersetUuid].compactMap { $0 })
        let supersetID = source.supersetUuid ?? candidate.supersetUuid ?? UUID()

        let saved = persistMutation {
            for workoutExercise in workoutExercises {
                let belongsToExistingGroup = workoutExercise.supersetUuid.map(existingIDs.contains) ?? false
                if workoutExercise.objectID == source.objectID
                    || workoutExercise.objectID == candidate.objectID
                    || belongsToExistingGroup {
                    workoutExercise.supersetUuid = supersetID
                }
            }
        }
        if saved {
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        return saved
    }

    @discardableResult
    private func removeFromSuperset(_ source: WorkoutExercise) -> Bool {
        let previousID = source.supersetUuid
        let saved = persistMutation {
            source.supersetUuid = nil

            if let previousID {
                let remaining = workoutExercises.filter { $0.supersetUuid == previousID }
                if remaining.count < 2 {
                    remaining.forEach { $0.supersetUuid = nil }
                }
            }
        }
        if saved {
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        return saved
    }

    private func createDefaultWorkoutSets(for workoutExercise: WorkoutExercise, exercise: Exercise) -> NSOrderedSet {
        let history = settingsStore.prefillPreviousValues
            ? (try? managedObjectContext.fetch(workoutExercise.historyFetchRequest)) ?? []
            : []
        let recentSets = history.first?.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
        let numberOfSets = max(recentSets.count, 3)

        let sets: [WorkoutSet] = (0..<numberOfSets).map { index in
            let set = WorkoutSet.create(context: managedObjectContext)
            let previous = recentSets.indices.contains(index) ? recentSets[index] : recentSets.last
            if let previous = previous {
                if let duration = previous.durationValue, previous.distanceValue == nil {
                    set.durationValue = duration
                    set.weightValue = 0
                    set.repetitionsValue = 0
                } else {
                    set.weightValue = previous.weightValue
                    set.repetitionsValue = previous.repetitionsValue
                }
                set.rpeValue = previous.rpeValue
                set.tagValue = previous.tagValue
            } else {
                set.repetitionsValue = 5
                if exercise.type == .barbell {
                    set.weightValue = WeightUnit.convert(
                        weight: settingsStore.weightUnit.barbellWeight,
                        from: settingsStore.weightUnit,
                        to: .metric
                    )
                }
            }
            set.isCompleted = false
            return set
        }
        return NSOrderedSet(array: sets)
    }

    @discardableResult
    private func addSet(to workoutExercise: WorkoutExercise) -> Bool {
        var saved = false
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            saved = persistMutation {
                let existingSets = workoutSets(for: workoutExercise)
                let set = WorkoutSet.create(context: managedObjectContext)
                set.workoutExercise = workoutExercise

                if let source = existingSets.last ?? latestHistorySet(for: workoutExercise, at: existingSets.count) {
                    if let duration = source.durationValue, source.distanceValue == nil {
                        set.durationValue = duration
                    } else {
                        set.weightValue = source.weightValue
                        set.repetitionsValue = source.repetitionsValue
                    }
                    set.rpeValue = source.rpeValue
                    set.tagValue = source.tagValue
                } else {
                    set.repetitionsValue = 5
                }
                set.isCompleted = false
            }
        }
        if saved { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
        return saved
    }

    @discardableResult
    private func deleteSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) -> Bool {
        var saved = false
        withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
            saved = persistMutation {
                workoutExercise.removeFromWorkoutSets(set)
                managedObjectContext.delete(set)
            }
        }
        if saved { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
        return saved
    }

    @discardableResult
    private func deleteWorkoutExercise(_ workoutExercise: WorkoutExercise) -> Bool {
        let saved = persistMutation {
            workout.removeFromWorkoutExercises(workoutExercise)
            managedObjectContext.delete(workoutExercise)
        }
        if saved { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
        return saved
    }

    @discardableResult
    private func moveWorkoutExercise(from source: Int, to destination: Int) -> Bool {
        guard source != destination,
              workoutExercises.indices.contains(source),
              workoutExercises.indices.contains(destination) else { return false }
        let saved = persistMutation {
            var exercises = workoutExercises
            let exercise = exercises.remove(at: source)
            exercises.insert(exercise, at: destination)
            workout.workoutExercises = NSOrderedSet(array: exercises)
        }
        if saved {
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        return saved
    }

    private func toggleCompleted(_ set: WorkoutSet, in workoutExercise: WorkoutExercise) {
        let justCompleted = !set.isCompleted
        do {
            try managedObjectContext.persistMutation(save: { try managedObjectContext.save() }) {
                set.isCompleted = justCompleted
                set.completedAt = justCompleted ? Date() : nil
                if justCompleted {
                    set.weightValue = max(set.weightValue, 0)
                    set.repetitionsValue = max(set.repetitionsValue, 0)
                    workout.start = workout.start ?? Date()
                }
            }
        } catch {
            persistenceError = "The set was not changed. \(error.localizedDescription)"
            return
        }

        // Summary metrics and the next current row derive from child-set values.
        workout.objectWillChange.send()

        if justCompleted {
            let isRecord = settingsStore.personalRecordAlerts && set.isPersonalRecord == true

            // Ordinary completion feedback is owned by the row's shared modifier.
            if settingsStore.workoutHaptics, isRecord {
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                feedback.notificationOccurred(.warning)
            }
            if settingsStore.workoutSounds {
                IronSoundPlayer.shared.play(isRecord ? .setRecord : .setComplete)
            }
            if isRecord {
                announcePersonalRecord(for: set, in: workoutExercise)
            }

            if settingsStore.autoStartRestTimer {
                restPillRevealsAt = Date().addingTimeInterval(0.38)
                restTimerStore.start(duration: restTimerDuration(for: workoutExercise))
            }
        } else {
            restTimerStore.cancel()
        }

        if justCompleted, settingsStore.supersetAutoScroll {
            advanceThroughSuperset(from: workoutExercise)
        }

        if justCompleted {
            WorkoutLiveActivityManager.shared.setCompleted(
                set,
                in: workoutExercise,
                workout: workout
            )
        } else {
            WorkoutLiveActivityManager.shared.startOrUpdate(
                for: workout,
                preservingTransition: false
            )
        }
    }

    private func announcePersonalRecord(for set: WorkoutSet, in workoutExercise: WorkoutExercise) {
        let title = workoutExercise.exercise(in: exerciseStore.exercises)?.title ?? "Personal Record"
        let detail = set.resultTitle(weightUnit: settingsStore.weightUnit)
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            personalRecordBanner = PersonalRecordBanner(exerciseTitle: title, detail: detail)
        }
    }

    /// Moves the log to the next unfinished exercise in the same superset so the
    /// user can keep alternating without scrolling by hand.
    private func advanceThroughSuperset(from workoutExercise: WorkoutExercise) {
        guard let supersetUuid = workoutExercise.supersetUuid else { return }
        let partners = workoutExercises.filter { $0.supersetUuid == supersetUuid }
        guard partners.count > 1,
              let currentIndex = partners.firstIndex(of: workoutExercise) else { return }

        let rotated = partners[(currentIndex + 1)...] + partners[..<currentIndex]
        guard let next = rotated.first(where: { partner in
            workoutSets(for: partner).contains { !$0.isCompleted }
        }) else { return }
        scrollTarget = next.id
    }

    @discardableResult
    private func setRestTimer(_ duration: TimeInterval?, for workoutExercise: WorkoutExercise) -> Bool {
        persistMutation {
            workoutExercise.restTimerDurationValue = duration
        }
    }

    @discardableResult
    private func setTrackingMode(usesDuration: Bool, for workoutExercise: WorkoutExercise) -> Bool {
        let sets = workoutSets(for: workoutExercise)
        guard !sets.contains(where: \.isCompleted) else { return false }

        let saved = persistMutation {
            for set in sets {
                if usesDuration {
                    set.durationValue = set.durationValue ?? 60
                    set.distanceValue = nil
                    set.weightValue = 0
                    set.repetitionsValue = 0
                } else {
                    set.durationValue = nil
                    set.distanceValue = nil
                    if set.repetitionsValue == 0 {
                        set.repetitionsValue = 5
                    }
                }
            }
        }
        if saved { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
        return saved
    }

    private func restTimerDuration(for workoutExercise: WorkoutExercise) -> TimeInterval {
        if let duration = workoutExercise.restTimerDurationValue { return duration }
        return workoutDefaultRestTimerDuration(for: workoutExercise)
    }

    private func workoutDefaultRestTimerDuration(for workoutExercise: WorkoutExercise) -> TimeInterval {
        switch workoutExercise.exercise(in: exerciseStore.exercises)?.type {
        case .barbell: return settingsStore.defaultRestTimeBarbellBased
        case .dumbbell: return settingsStore.defaultRestTimeDumbbellBased
        default: return settingsStore.defaultRestTime
        }
    }

    private func restTimerTitle(for workoutExercise: WorkoutExercise) -> String {
        restTimerDurationFormatter.string(from: restTimerDuration(for: workoutExercise)) ?? "0:00"
    }

    private func latestHistorySet(for workoutExercise: WorkoutExercise, at index: Int) -> WorkoutSet? {
        guard let history = try? managedObjectContext.fetch(workoutExercise.historyFetchRequest),
              let previousExercise = history.first,
              let previousSets = previousExercise.workoutSets?.array.compactMap({ $0 as? WorkoutSet }),
              !previousSets.isEmpty else { return nil }
        return previousSets.indices.contains(index) ? previousSets[index] : previousSets.last
    }

    private func previousSetTitle(for workoutExercise: WorkoutExercise, at index: Int) -> String {
        guard let set = latestHistorySet(for: workoutExercise, at: index) else { return "—" }
        return set.resultTitle(weightUnit: settingsStore.weightUnit)
    }

    private func displayWeight(for set: WorkoutSet) -> Double {
        WeightUnit.convert(weight: set.weightValue, from: .metric, to: settingsStore.weightUnit)
    }

    @discardableResult
    private func addWarmupSets(_ recommendations: [WarmupRecommendation], before workingSet: WorkoutSet) -> Bool {
        guard let workoutExercise = workingSet.workoutExercise,
              let index = workoutExercise.workoutSets?.index(of: workingSet),
              index != NSNotFound else { return false }

        let saved = persistMutation {
            var insertionIndex = index
            for recommendation in recommendations {
                let set = WorkoutSet.create(context: managedObjectContext)
                set.tagValue = .warmUp
                set.weightValue = WeightUnit.convert(
                    weight: recommendation.weight,
                    from: settingsStore.weightUnit,
                    to: .metric
                )
                set.repetitionsValue = Int16(recommendation.repetitions)
                set.isCompleted = false
                workoutExercise.insertIntoWorkoutSets(set, at: insertionIndex)
                insertionIndex += 1
            }
        }
        if saved {
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            activeSheet = nil
        }
        return saved
    }

    private func prepareFinishEditor() {
        if let named = workout.title ?? workout.workoutPlanAndRoutineTitle(),
           !named.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finishTitle = named
        } else {
            finishTitle = workout.generatedTitle(in: exerciseStore.exercises) ?? ""
        }
        finishStartDate = workout.safeStart
        finishDuration = max(workout.safeDuration, 0)
        sessionEffort = workout.sessionEffortValue ?? 0
        finishRecap = FinishWorkoutRecap(workout: workout, exercises: exerciseStore.exercises, weightUnit: settingsStore.weightUnit)
        syncWithHealth = UserDefaults.standard.object(forKey: "Iron.finishWorkout.syncWithHealth") as? Bool ?? true
        updateLinkedRoutine = false
        finishMediaError = nil
        isFinishingWorkout = false

        if let workoutUUID = workout.uuid,
           let mediaURL = FinishWorkoutMediaStore.existingURL(for: workoutUUID) {
            finishMediaURL = mediaURL
            finishMediaKind = FinishWorkoutMediaKind(url: mediaURL)
        } else {
            finishMediaURL = nil
            finishMediaKind = .image
        }
    }

    private func importFinishMedia(_ item: PhotosPickerItem) async {
        let workoutUUID = workout.uuid
        let contentType = item.supportedContentTypes.first
        let mediaKind: FinishWorkoutMediaKind = contentType?.conforms(to: .movie) == true ? .video : .image
        let fileExtension = contentType?.preferredFilenameExtension ?? (mediaKind == .video ? "mov" : "jpg")

        await MainActor.run {
            isLoadingFinishMedia = true
            finishMediaError = nil
        }

        do {
            guard let workoutUUID = workoutUUID else {
                throw FinishWorkoutMediaError.missingWorkoutIdentifier
            }
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw FinishWorkoutMediaError.unreadableMedia
            }
            let mediaURL = try FinishWorkoutMediaStore.save(
                data: data,
                for: workoutUUID,
                fileExtension: fileExtension
            )

            await MainActor.run {
                finishMediaURL = mediaURL
                finishMediaKind = mediaKind
                finishMediaItem = nil
                isLoadingFinishMedia = false
            }
        } catch {
            await MainActor.run {
                finishMediaItem = nil
                isLoadingFinishMedia = false
                finishMediaError = "Could not save that media. Try another photo or video."
            }
        }
    }

    private func removeFinishMedia() {
        if let workoutUUID = workout.uuid {
            FinishWorkoutMediaStore.remove(for: workoutUUID)
        }
        finishMediaItem = nil
        finishMediaURL = nil
        finishMediaKind = .image
        finishMediaError = nil
    }

    private func updateLinkedRoutineFromCompletedSets() {
        guard let routine = workout.workoutRoutine else { return }
        let routineExercises = routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []

        for workoutExercise in workoutExercises {
            guard let exerciseUUID = workoutExercise.exerciseUuid,
                  let routineExercise = routineExercises.first(where: { $0.exerciseUuid == exerciseUUID }) else {
                continue
            }

            let completedSets = workoutSets(for: workoutExercise).filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }

            var routineSets = routineExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
            for (index, completedSet) in completedSets.enumerated() {
                let routineSet: WorkoutRoutineSet
                if routineSets.indices.contains(index) {
                    routineSet = routineSets[index]
                } else {
                    routineSet = WorkoutRoutineSet.create(context: managedObjectContext)
                    routineSet.workoutRoutineExercise = routineExercise
                    routineSets.append(routineSet)
                }

                if let duration = completedSet.durationValue, completedSet.distanceValue == nil {
                    routineSet.weightValue = nil
                    routineSet.minRepetitionsValue = nil
                    routineSet.maxRepetitionsValue = nil
                    routineSet.durationValue = duration
                } else {
                    routineSet.weightValue = completedSet.weightValue
                    routineSet.minRepetitionsValue = completedSet.repetitionsValue
                    routineSet.maxRepetitionsValue = completedSet.repetitionsValue
                    routineSet.durationValue = nil
                }
                routineSet.tagValue = completedSet.tagValue
            }
            routineExercise.workoutRoutineSets = NSOrderedSet(array: routineSets)
        }
    }

    private func finishWorkout() {
        guard !isFinishingWorkout, !isLoadingFinishMedia else { return }
        isFinishingWorkout = true
        defer { isFinishingWorkout = false }

        let trimmedTitle = finishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = workout.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try workout.finish(syncToHealth: syncWithHealth) {
                workout.title = trimmedTitle.isEmpty
                    ? workout.generatedTitle(in: exerciseStore.exercises)
                    : trimmedTitle
                workout.comment = trimmedComment.isEmpty ? nil : trimmedComment
                workout.start = finishStartDate
                workout.end = finishEndDate
                workout.sessionEffortValue = sessionEffort > 0 ? sessionEffort : nil
                if updateLinkedRoutine { updateLinkedRoutineFromCompletedSets() }
            }
        } catch {
            persistenceError = "Your workout is still active. Iron could not save it: \(error.localizedDescription)"
            return
        }
        UserDefaults.standard.set(syncWithHealth, forKey: "Iron.finishWorkout.syncWithHealth")
        showingFinishEditor = false

        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
        IronSoundPlayer.shared.play(.workoutFinish)

        UserDefaults.standard.finishedWorkoutsCount += 1
        if UserDefaults.standard.finishedWorkoutsCount == 6,
           let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    private func cancelWorkout() {
        let workoutUUID = workout.uuid
        do {
            try workout.cancel()
        } catch {
            persistenceError = "Your workout has not been discarded. \(error.localizedDescription)"
            return
        }
        activeSheet = nil
        showingFinishEditor = false
        if let workoutUUID {
            FinishWorkoutMediaStore.remove(for: workoutUUID)
        }
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.warning)
    }

    @discardableResult
    private func persistMutation(_ mutation: () -> Void) -> Bool {
        do {
            try CurrentWorkoutPersistence.perform(
                in: managedObjectContext,
                save: { try managedObjectContext.save() },
                mutation: mutation
            )
            return true
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    /// Inline controls update their managed values before invoking `onChanged`.
    /// Keep those edits available for retry, but suppress downstream effects
    /// until the context is durably saved.
    @discardableResult
    private func save() -> Bool {
        guard managedObjectContext.hasChanges else { return true }
        do {
            try managedObjectContext.save()
            return true
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }
}

/// Capture the recap once when the editor opens. Record classification queries
/// stay out of the body so scrubbing effort does no Core Data work.
private struct FinishWorkoutRecap {
    struct Record: Identifiable {
        let id: NSManagedObjectID
        let exerciseName: String
        let title: String
        let setSummary: String
    }

    var setCount = 0
    var exerciseCount = 0
    var averageRPE = "–"
    var groups: [IronSessionStrip.ExerciseGroup] = []
    var records: [Record] = []
    var accessibilitySummary = "No completed sets."

    init() {}

    init(workout: Workout, exercises: [Exercise], weightUnit: WeightUnit) {
        let workoutExercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
        var entries: [(set: WorkoutSet, exercise: WorkoutExercise, order: Int)] = []
        for exercise in workoutExercises {
            let sets = exercise.workoutSets?.array as? [WorkoutSet] ?? []
            if sets.contains(where: \.isCompleted) { exerciseCount += 1 }
            for set in sets where set.isCompleted {
                entries.append((set, exercise, entries.count))
            }
        }
        // Legacy timestamps fall back to session start, then relationship order.
        let fallback = workout.start ?? .distantPast
        entries.sort {
            let lhs = $0.set.completedAt ?? fallback
            let rhs = $1.set.completedAt ?? fallback
            return lhs == rhs ? $0.order < $1.order : lhs < rhs
        }
        setCount = entries.count
        let rpes = entries.compactMap { $0.set.rpeValue }.filter { $0 > 0 }
        if !rpes.isEmpty {
            averageRPE = (rpes.reduce(0, +) / Double(rpes.count))
                .formatted(.number.precision(.fractionLength(0...1)))
        }

        let maximumVolume = entries.map { Self.volume(of: $0.set) }.max() ?? 0
        var groupExercise: NSManagedObjectID?
        var groupLabel = ""
        var bars: [IronSessionStrip.Set] = []
        var historyByExercise: [NSManagedObjectID: [WorkoutSet]] = [:]
        var warmUpCount = 0
        for entry in entries {
            let name = entry.exercise.exercise(in: exercises)?.title ?? "Unknown exercise"
            if groupExercise != entry.exercise.objectID {
                if !bars.isEmpty { groups.append(.init(label: groupLabel, sets: bars)) }
                groupExercise = entry.exercise.objectID
                groupLabel = name
                bars = []
            }

            let isRecord = entry.set.isPersonalRecord == true
            let isWarmUp = entry.set.tagValue == .warmUp
            if isWarmUp { warmUpCount += 1 }
            let volume = Self.volume(of: entry.set)
            bars.append(.init(
                relativeVolume: volume > 0 && maximumVolume > 0 ? volume / maximumVolume : 0.45,
                kind: isWarmUp ? .warmUp : isRecord ? .record : .normal,
                completedAt: entry.set.completedAt,
                duration: entry.set.durationValue,
                volume: WeightUnit.convert(weight: volume, from: .metric, to: weightUnit),
                result: entry.set.resultTitle(weightUnit: weightUnit),
                rpe: entry.set.rpeValue
            ))

            if isRecord {
                let id = entry.exercise.objectID
                if historyByExercise[id] == nil, let context = workout.managedObjectContext,
                   let history = try? context.fetch(entry.exercise.historyFetchRequest) {
                    historyByExercise[id] = history.flatMap {
                        ($0.workoutSets?.array as? [WorkoutSet] ?? []).filter(\.isCompleted)
                    }
                }
                let precedingSets = entries.filter {
                    $0.order < entry.order && $0.exercise.exerciseUuid == entry.exercise.exerciseUuid
                }.map(\.set)
                let priorSets = historyByExercise[id].map { $0 + precedingSets }
                records.append(.init(
                    id: entry.set.objectID,
                    exerciseName: name,
                    title: Self.recordTitle(for: entry.set, priorSets: priorSets, weightUnit: weightUnit),
                    setSummary: entry.set.resultTitle(weightUnit: weightUnit)
                ))
            }
        }
        if !bars.isEmpty { groups.append(.init(label: groupLabel, sets: bars)) }
        let exerciseSummary = groups.map { "\($0.label), \($0.sets.count) sets" }.joined(separator: "; ")
        accessibilitySummary = "Session timeline in completion order: \(setCount) completed sets, \(warmUpCount) warm-up sets, \(records.count) personal records. \(exerciseSummary). Bar height shows set volume. The activity track shows work and rest, estimating 40 seconds for sets without a recorded duration."
    }

    private static func volume(of set: WorkoutSet) -> Double {
        guard set.durationValue == nil else { return 0 }
        let volume = set.weightValue * Double(set.repetitionsValue)
        return volume.isFinite && volume > 0 ? volume : 0
    }

    private static func recordTitle(for set: WorkoutSet, priorSets: [WorkoutSet]?, weightUnit: WeightUnit) -> String {
        // isPersonalRecord means a weight/repetition improvement, not necessarily
        // an estimated 1RM record. Only name a more specific record with evidence.
        guard let priorSets, !priorSets.isEmpty else { return "New personal record" }
        if let maximum = priorSets.map(\.weightValue).max(), set.weightValue > maximum {
            return "Heaviest weight"
        }
        let atWeight = priorSets.filter { $0.weightValue == set.weightValue }
        if let maximum = atWeight.map(\.repetitionsValue).max(), set.repetitionsValue > maximum {
            let weight = WeightUnit.format(weight: set.weightValue, from: .metric, to: weightUnit)
            return "Most reps at \(weight)"
        }
        return "New personal record"
    }
}

private struct FinishWorkoutRecordRow: View {
    let record: FinishWorkoutRecap.Record
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.metricRecord)
                .modifier(if: !reduceMotion) {
                    $0.symbolEffect(.bounce, options: .nonRepeating, value: hasAppeared)
                }
                .frame(width: 36, height: 36)
                .background(IronTheme.metricRecordContainer, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.exerciseName)
                    .font(.body.weight(.semibold))
                Text(record.title)
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.secondaryText)
                Text(record.setSummary)
                    .font(.ironMetric(.caption, weight: .semibold))
                    .foregroundStyle(IronTheme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .opacity(hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: hasAppeared)
        .accessibilityElement(children: .combine)
        .onAppear { hasAppeared = true }
    }
}

/// Completion-only control. The history editor keeps its existing effort picker.
private struct FinishWorkoutEffortControl: View {
    @Binding var rating: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var numeralHeight: CGFloat = 18
    @State private var hasAppeared = false
    @State private var dragIsHorizontal: Bool?

    private var graphHeight: CGFloat { 56 + 8 + numeralHeight }

    private var ratingTitle: String {
        switch rating {
        case 1...3: return "\(rating) · Easy"
        case 4...6: return "\(rating) · Moderate"
        case 7...8: return "\(rating) · Hard"
        case 9...10: return "\(rating) · All Out"
        default: return "Not rated"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How hard was it?").font(.headline)
                    Spacer(minLength: 8)
                    ratingLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("How hard was it?").font(.headline)
                    ratingLabel
                }
            }

            // Geometry measures the touch range only; the segments are a plain stack.
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(1...10, id: \.self) { level in
                        FinishWorkoutEffortBar(level: level, rating: rating, hasAppeared: hasAppeared)
                    }
                }
                .frame(height: graphHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    select(at: value.location.x, width: proxy.size.width)
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Lock intent once so a vertical scroll never turns
                            // into a rating change when the finger veers sideways.
                            if dragIsHorizontal == nil {
                                dragIsHorizontal = abs(value.translation.width) > abs(value.translation.height)
                            }
                            guard dragIsHorizontal == true else { return }
                            select(at: value.location.x, width: proxy.size.width)
                        }
                        .onEnded { _ in dragIsHorizontal = nil }
                )
            }
            .frame(height: graphHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session effort")
            .accessibilityValue(rating == 0 ? "Not rated" : "\(ratingTitle), out of 10")
            .accessibilityHint("Swipe up or down to adjust. Zero leaves the session unrated.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(rating + 1, 10)
                case .decrement: rating = max(rating - 1, 0)
                default: break
                }
            }

            if rating > 0 {
                Button("Clear rating") { rating = 0 }
                    .font(.subheadline)
                    .frame(minHeight: IronTheme.controlHeight)
                    .buttonStyle(.borderless)
                    .accessibilityHint("Leaves session effort unrated")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        // Entrance plays once; List prefetching can call onDisappear before the
        // row is ever shown, so never reset the flag there.
        .onAppear { hasAppeared = true }
        .onDisappear { dragIsHorizontal = nil }
    }

    private var ratingLabel: some View {
        Text(ratingTitle)
            .font(.ironMetric(.subheadline))
            .foregroundStyle(IronTheme.metricEffort)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: rating)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func select(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let level = min(max(Int((x / width * 10).rounded(.down)) + 1, 1), 10)
        if level != rating { rating = level }
    }
}

private struct FinishWorkoutEffortBar: View {
    let level: Int
    let rating: Int
    let hasAppeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionScale: CGFloat = 1

    private var isFilled: Bool { level <= rating }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
    }

    var body: some View {
        VStack(spacing: 5) {
            shape
                .fill(IronTheme.tertiaryFill)
                .overlay { shape.strokeBorder(IronTheme.outline.opacity(0.5), lineWidth: 0.5) }
                .overlay {
                    shape.fill(IronTheme.metricEffort.opacity(0.55 + 0.45 * Double(level - 1) / 9))
                        .opacity(isFilled ? 1 : 0)
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: isFilled)
                }
                .frame(height: 56 * (0.14 + 0.86 * Double(level) / 10))
                .scaleEffect(y: selectionScale, anchor: .bottom)
                .scaleEffect(y: hasAppeared || reduceMotion ? 1 : 0, anchor: .bottom)
                .frame(height: 56, alignment: .bottom)
            Text("\(level)")
                .font(.caption2.weight(level == rating ? .bold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(level == rating ? IronTheme.metricEffort : IronTheme.secondaryText)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .opacity(hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(
            IronMotion.snappy.delay(Double(level - 1) * 0.04), reduceMotion: reduceMotion
        ), value: hasAppeared)
        .task(id: isFilled) {
            guard isFilled, !reduceMotion else { selectionScale = 1; return }
            selectionScale = 0.9
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                selectionScale = 1
            }
        }
    }
}

enum CurrentWorkoutPersistence {
    static func perform(
        in context: NSManagedObjectContext,
        save: () throws -> Void,
        mutation: () -> Void
    ) throws {
        try context.persistMutation(save: save, mutation: mutation)
    }
}

private enum FinishWorkoutMediaKind: Equatable {
    case image
    case video

    init(url: URL) {
        let videoExtensions = Set(["mov", "mp4", "m4v", "avi", "hevc"])
        self = videoExtensions.contains(url.pathExtension.lowercased()) ? .video : .image
    }
}

private enum FinishWorkoutMediaError: LocalizedError {
    case missingWorkoutIdentifier
    case unreadableMedia

    var errorDescription: String? {
        switch self {
        case .missingWorkoutIdentifier:
            return "This workout does not have an identifier yet."
        case .unreadableMedia:
            return "The selected media could not be read."
        }
    }
}

enum FinishWorkoutMediaStore {
    private static let directoryName = "IronWorkoutMedia"

    static func existingURL(for workoutUUID: UUID) -> URL? {
        guard let directoryURL = directoryURL(createIfNeeded: false),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        return files.first {
            $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(workoutUUID.uuidString) == .orderedSame
        }
    }

    @discardableResult
    static func save(data: Data, for workoutUUID: UUID, fileExtension: String) throws -> URL {
        guard let directoryURL = directoryURL(createIfNeeded: true) else {
            throw FinishWorkoutMediaError.unreadableMedia
        }

        remove(for: workoutUUID)
        let safeExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let mediaURL = directoryURL
            .appendingPathComponent(workoutUUID.uuidString, isDirectory: false)
            .appendingPathExtension(safeExtension.isEmpty ? "bin" : safeExtension)
        try data.write(to: mediaURL, options: [.atomic])
        return mediaURL
    }

    static func remove(for workoutUUID: UUID) {
        guard let mediaURL = existingURL(for: workoutUUID) else { return }
        try? FileManager.default.removeItem(at: mediaURL)
    }

    private static func directoryURL(createIfNeeded: Bool) -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directoryURL = applicationSupportURL.appendingPathComponent(directoryName, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return directoryURL
    }
}

enum InlineWorkoutSetLayout {
    static let spacing: CGFloat = 4
    static let completedChromeExpansion: CGFloat = 6
    static let setWidth: CGFloat = 36
    static let previousWidth: CGFloat = 72
    static let repetitionsWidth: CGFloat = 48
    static let rpeWidth: CGFloat = 42
    static let completionWidth: CGFloat = 40
}

struct InlineWorkoutSetRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var set: WorkoutSet

    let index: Int
    let usesDuration: Bool
    let isBarbell: Bool
    let previousTitle: String
    let onOpenPlateCalculator: () -> Void
    let onToggleCompleted: () -> Void
    let onDelete: () -> Bool
    let onChanged: () -> Bool
    var allowsSwipeToDelete = false
    var isCurrent = false

    @State private var isRaisedCurrent = false
    @State private var completionBounce = 0
    @State private var checkReveal: CGFloat = 0

    private var valueColor: Color {
        return set.isCompleted || isRaisedCurrent ? IronTheme.primaryText : IronTheme.secondaryText
    }

    private var badgeColor: Color {
        if set.tagValue == .warmUp { return IronTheme.metricSets }
        return set.isCompleted || isRaisedCurrent ? IronTheme.accent : IronTheme.secondaryText
    }

    private var badgeFill: Color {
        if set.tagValue == .warmUp { return IronTheme.metricSetsContainer }
        if set.isCompleted { return IronTheme.accentSoft }
        return isRaisedCurrent ? .clear : IronTheme.field
    }

    private var completionFeedbackEnabled: Bool {
        settingsStore.workoutHaptics
            && !(settingsStore.personalRecordAlerts && set.isPersonalRecord == true)
    }

    private var completionImage: some View {
        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                set.isCompleted ? IronTheme.onAccent : (isRaisedCurrent ? IronTheme.accent : IronTheme.tertiaryText),
                IronTheme.accent
            )
            .font(.system(size: 28, weight: .semibold))
    }

    @ViewBuilder
    private var completionSymbol: some View {
        if reduceMotion {
            completionImage.contentTransition(.opacity)
        } else {
            ZStack {
                // Keep the blue disc visible while the symbol's white check draws in.
                Circle()
                    .fill(IronTheme.accent)
                    .opacity(set.isCompleted ? 1 : 0)
                completionImage
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, options: .nonRepeating, value: completionBounce)
                    .mask {
                        Rectangle()
                            .scaleEffect(x: set.isCompleted ? checkReveal : 1, anchor: .leading)
                    }
            }
            .frame(width: 28, height: 28)
        }
    }

    @State private var showingRPEPicker = false
    @State private var showingDurationPicker = false
    @State private var showingDurationSaveError = false
    @State private var inlineTimerStart: Date?

    /// Timed sets can be run like a stopwatch instead of dialling in a target
    /// first: tap to start, tap to bank the elapsed time.
    @ViewBuilder
    private var durationControl: some View {
        if settingsStore.inlineSetTimer, !set.isCompleted {
            TimelineView(.periodic(from: Date(), by: 0.5)) { context in
                Button(action: toggleInlineTimer) {
                    durationLabel(
                        text: inlineTimerText(now: context.date),
                        isRunning: inlineTimerStart != nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inlineTimerStart == nil ? "Start set timer" : "Stop set timer")
            }
            .contextMenu {
                Button("Enter Duration", systemImage: "keyboard") { showingDurationPicker = true }
            }
        } else {
            Button(action: { showingDurationPicker = true }) {
                durationLabel(
                    text: restTimerDurationFormatter.string(from: set.durationValue ?? 60) ?? "1:00",
                    isRunning: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set duration")
        }
    }

    private func durationLabel(text: String, isRunning: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isRunning ? "stop.fill" : "stopwatch")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(
                    isRunning ? IronTheme.danger : (set.isCompleted || isRaisedCurrent ? IronTheme.metricTime : IronTheme.secondaryText)
                )
            Text(text)
                .font(.ironMetric(.subheadline))
                .foregroundColor(valueColor)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: text)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func inlineTimerText(now: Date) -> String {
        guard let inlineTimerStart else {
            return restTimerDurationFormatter.string(from: set.durationValue ?? 0) ?? "0:00"
        }
        let elapsed = max(0, now.timeIntervalSince(inlineTimerStart))
        return restTimerDurationFormatter.string(from: elapsed) ?? "0:00"
    }

    private func toggleInlineTimer() {
        if let inlineTimerStart {
            set.durationValue = max(1, (Date().timeIntervalSince(inlineTimerStart)).rounded())
            self.inlineTimerStart = nil
            _ = onChanged()
        } else {
            inlineTimerStart = Date()
        }
    }
    @State private var weightText = ""
    @State private var repetitionsText = ""
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeStartOffset: CGFloat = 0
    @State private var isSwipingSet = false
    @State private var isPerformingSwipeDelete = false
    @State private var measuredRowWidth: CGFloat = 0
    @FocusState private var focusedField: EntryField?

    private let deleteActionWidth: CGFloat = 76
    private let deleteRevealOverlap: CGFloat = 18

    private var fullSwipeDeleteThreshold: CGFloat {
        effectiveRowWidth * 0.55
    }

    private var effectiveRowWidth: CGFloat {
        if measuredRowWidth > 0 {
            return measuredRowWidth
        }
        return max(
            deleteActionWidth,
            UIScreen.main.bounds.width - (IronTheme.horizontalPadding * 2)
        )
    }

    private enum EntryField: Hashable {
        case weight
        case repetitions
    }

    private var weightTextBinding: Binding<String> {
        Binding(
            get: { weightText },
            set: { proposedValue in
                let sanitizedValue = sanitizedDecimalInput(proposedValue)
                guard proposedValue.isEmpty || !sanitizedValue.isEmpty else { return }
                weightText = sanitizedValue

                guard let displayValue = weightFormatter.number(from: sanitizedValue)?.doubleValue else {
                    if sanitizedValue.isEmpty, set.weightValue != 0 {
                        set.weightValue = 0
                        _ = onChanged()
                    }
                    return
                }

                let metricValue = min(
                    max(WeightUnit.convert(weight: displayValue, from: settingsStore.weightUnit, to: .metric), 0),
                    WorkoutSet.MAX_WEIGHT
                )
                if abs(set.weightValue - metricValue) > 0.000_001 {
                    set.weightValue = metricValue
                    _ = onChanged()
                }
            }
        )
    }

    private var repetitionsTextBinding: Binding<String> {
        Binding(
            get: { repetitionsText },
            set: { proposedValue in
                let sanitizedValue = sanitizedIntegerInput(proposedValue)
                guard proposedValue.isEmpty || !sanitizedValue.isEmpty else { return }
                repetitionsText = sanitizedValue

                let value = min(
                    max(Int(sanitizedValue) ?? 0, 0),
                    Int(WorkoutSet.MAX_REPETITIONS)
                )
                if set.repetitionsValue != Int16(value) {
                    set.repetitionsValue = Int16(value)
                    _ = onChanged()
                }
            }
        )
    }

    private var weightFormatter: NumberFormatter {
        settingsStore.weightUnit.numberFormatter
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if allowsSwipeToDelete, deleteRevealWidth > 0.5 {
                swipeDeleteAction
            }

            HStack(spacing: InlineWorkoutSetLayout.spacing) {
            Menu {
                setTypeMenuItems
            } label: {
                Text(setLabel)
                    .font(.ironMetric(.callout, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .frame(width: 30, height: 30)
                    .background(badgeFill, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(IronTheme.accent, lineWidth: 1.5)
                            .opacity(isRaisedCurrent && !set.isCompleted && set.tagValue != .warmUp ? 1 : 0)
                    }
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.controlHeight)
                    .contentShape(Rectangle())
                    .frame(width: InlineWorkoutSetLayout.setWidth)
            }
            .accessibilityLabel("Set type")
            .accessibilityValue(set.tagValue?.title ?? "Normal set")

            Text(previousTitle)
                .font(.ironMetric(.caption, weight: .semibold))
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(width: InlineWorkoutSetLayout.previousWidth, alignment: .center)

            if usesDuration {
                setField {
                    durationControl
                }
            } else {
                setField(isFocused: focusedField == .weight) {
                    TextField("0", text: weightTextBinding)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Weight in \(settingsStore.weightUnit.unit.symbol)")
                }

                setField(
                    width: InlineWorkoutSetLayout.repetitionsWidth,
                    isFocused: focusedField == .repetitions
                ) {
                    TextField("0", text: repetitionsTextBinding)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .repetitions)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Repetitions")
                }
            }

            if settingsStore.logRPE {
                Button(action: { showingRPEPicker = true }) {
                    Group {
                        if let rpe = set.rpeValue {
                            Text(String(format: "%g", rpe))
                        } else if set.isCompleted {
                            Text("–")
                        } else {
                            Image(systemName: "gauge.with.dots.needle.50percent")
                        }
                    }
                    .font(.ironMetric(.caption, weight: .semibold))
                    .foregroundStyle(set.rpeValue != nil || (!set.isCompleted && isRaisedCurrent) ? IronTheme.metricEffort : IronTheme.secondaryText)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.controlHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(IronTheme.metricEffortContainer)
                            .opacity(isRaisedCurrent && !set.isCompleted ? 1 : 0)
                    )
                    .contentShape(Rectangle())
                    .frame(width: InlineWorkoutSetLayout.rpeWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rpeAccessibilityLabel)
                .accessibilityHint("Opens the effort selector")
            }

            Button {
                withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                    onToggleCompleted()
                }
            } label: {
                completionSymbol
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.controlHeight)
                    .contentShape(Rectangle())
                    .frame(width: InlineWorkoutSetLayout.completionWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                set.isCompleted
                    ? "Set \(index + 1) completed"
                    : "Mark set \(index + 1) complete"
            )
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
            .accessibilityRemoveTraits(.isSelected)
            .accessibilityAddTraits(set.isCompleted ? .isSelected : [])
            }
            // Every state uses the same insets and columns. Only the fills change.
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, InlineWorkoutSetLayout.completedChromeExpansion)
            .background {
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.field)
                    .opacity(isRaisedCurrent && !set.isCompleted ? 1 : 0)
            }
            .ironSetCompletion(isComplete: set.isCompleted, feedbackEnabled: completionFeedbackEnabled)
            .padding(.horizontal, -InlineWorkoutSetLayout.completedChromeExpansion)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: set.isCompleted)
            .padding(.vertical, 2)
            .offset(x: swipeOffset)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        measuredRowWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        measuredRowWidth = width
                    }
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(swipeDeleteGesture)
        .onAppear {
            synchronizeEntryText()
            isRaisedCurrent = isCurrent && !set.isCompleted
            checkReveal = set.isCompleted ? 1 : 0
        }
        .onChange(of: isCurrent) { _, current in
            withAnimation(IronMotion.preferred(
                current ? IronMotion.snappy.delay(0.18) : IronMotion.snappy,
                reduceMotion: reduceMotion
            )) {
                isRaisedCurrent = current && !set.isCompleted
            }
        }
        .onChange(of: set.isCompleted) { _, isCompleted in
            if focusedField != .weight { weightText = formattedWeight }
            if isCompleted {
                completionBounce += 1
                withAnimation(IronMotion.preferred(IronMotion.snappy.delay(0.12), reduceMotion: reduceMotion)) {
                    checkReveal = 1
                }
            } else {
                checkReveal = 0
            }
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                isRaisedCurrent = isCurrent && !isCompleted
            }
            // Banking the elapsed time on completion keeps a running stopwatch
            // from being silently discarded.
            guard isCompleted, inlineTimerStart != nil else { return }
            toggleInlineTimer()
        }
        .onChange(of: set.weightValue) { _, _ in
            guard focusedField != .weight else { return }
            weightText = formattedWeight
        }
        .onChange(of: set.repetitionsValue) { _, _ in
            guard focusedField != .repetitions else { return }
            repetitionsText = formattedRepetitions
        }
        .onChange(of: settingsStore.weightUnit) { _, _ in
            guard focusedField != .weight else { return }
            weightText = formattedWeight
        }
        .onChange(of: focusedField) { _, newValue in
            weightText = formattedWeight
            if newValue != .repetitions {
                repetitionsText = formattedRepetitions
            }
        }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .weight, settingsStore.showPlateCalculator {
                        Button("Plate Calculator", systemImage: "plusminus", action: openPlateCalculator)
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Calculates the plates to load for this set")
                    }

                    Spacer()

                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .accessibilityLabel("Dismiss number pad")
                }
            }
        }
        .sheet(isPresented: $showingRPEPicker) {
            RPEPickerSheet(set: set, onChanged: onChanged)
        }
        .sheet(isPresented: $showingDurationPicker) {
            IronDurationPickerSheet(
                initialDuration: set.durationValue ?? 60,
                shouldDismiss: { !showingDurationSaveError }
            ) { duration in
                set.durationValue = duration
                set.distanceValue = nil
                set.weightValue = 0
                set.repetitionsValue = 0
                showingDurationSaveError = !onChanged()
            }
            .alert("Duration Not Saved", isPresented: $showingDurationSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your duration could not be saved. Keep this sheet open and try again.")
            }
        }
    }

    private var rpeAccessibilityLabel: String {
        guard let rpe = set.rpeValue else { return "Set RPE" }
        return "RPE \(String(format: "%g", rpe))"
    }

    @ViewBuilder
    private var setTypeMenuItems: some View {
        Picker("Set Type", selection: setTagBinding) {
            Label("Normal Set", systemImage: "number").tag(WorkoutSetTag?.none)
            ForEach(WorkoutSetTag.allCases, id: \.self) { tag in
                Label(tag.title.capitalized, systemImage: setTypeIcon(for: tag))
                    .tag(WorkoutSetTag?.some(tag))
            }
        }

        Section {
            Button("Delete Set", systemImage: "trash", role: .destructive) {
                _ = onDelete()
            }
        }
    }

    private var setTagBinding: Binding<WorkoutSetTag?> {
        Binding(
            get: { set.tagValue },
            set: {
                set.tagValue = $0
                _ = onChanged()
            }
        )
    }

    private func setTypeIcon(for tag: WorkoutSetTag) -> String {
        switch tag {
        case .warmUp: return "flame"
        case .dropSet: return "arrow.down.right"
        case .failure: return "bolt.fill"
        }
    }

    private var setLabel: String {
        switch set.tagValue {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        case nil: return "\(index + 1)"
        }
    }

    private var formattedWeight: String {
        let displayValue = WeightUnit.convert(
            weight: set.weightValue,
            from: .metric,
            to: settingsStore.weightUnit
        )
        let formatter = focusedField == .weight ? weightFormatter : settingsStore.weightUnit.displayNumberFormatter
        return formatter.string(from: NSNumber(value: displayValue)) ?? "0"
    }

    private var formattedRepetitions: String {
        String(Int(set.repetitionsValue))
    }

    private func synchronizeEntryText() {
        weightText = formattedWeight
        repetitionsText = formattedRepetitions
    }

    private func sanitizedDecimalInput(_ proposedValue: String) -> String {
        let decimalSeparator = weightFormatter.decimalSeparator
            ?? Locale.current.decimalSeparator
            ?? "."
        let maximumFractionDigits = settingsStore.weightUnit.maximumFractionDigits
        var result = ""
        var hasDecimalSeparator = false
        var fractionDigitCount = 0

        for character in proposedValue {
            if let digit = character.wholeNumberValue {
                if hasDecimalSeparator {
                    guard fractionDigitCount < maximumFractionDigits else { continue }
                    fractionDigitCount += 1
                }
                result.append(contentsOf: String(digit))
            } else if (character == "." || character == "," || String(character) == decimalSeparator),
                      maximumFractionDigits > 0,
                      !hasDecimalSeparator {
                if result.isEmpty {
                    result = "0"
                }
                result.append(contentsOf: decimalSeparator)
                hasDecimalSeparator = true
            }
        }

        if let value = weightFormatter.number(from: result)?.doubleValue {
            let maximumDisplayWeight = WeightUnit.convert(
                weight: WorkoutSet.MAX_WEIGHT,
                from: .metric,
                to: settingsStore.weightUnit
            )
            if value > maximumDisplayWeight {
                return weightFormatter.string(from: NSNumber(value: maximumDisplayWeight)) ?? result
            }
        }
        return result
    }

    private func sanitizedIntegerInput(_ proposedValue: String) -> String {
        let digits = proposedValue.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(WorkoutSet.MAX_REPETITIONS)))
    }

    private func openPlateCalculator() {
        focusedField = nil
        DispatchQueue.main.async(execute: onOpenPlateCalculator)
    }

    private func setField<Content: View>(
        width: CGFloat? = nil,
        isFocused: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.ironMetric(.callout))
            .foregroundColor(valueColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 46)
            .frame(width: width)
            .background(
                Capsule(style: .continuous)
                    .fill(isFocused ? IronTheme.accentSoft : IronTheme.tertiaryFill)
                    .opacity(!set.isCompleted && (isRaisedCurrent || isFocused) ? 1 : 0)
                    .overlay {
                        if isFocused && !set.isCompleted {
                            Capsule(style: .continuous)
                                .stroke(IronTheme.accent, lineWidth: 2)
                        }
                    }
            )
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: isFocused)
    }

    private var swipeDeleteAction: some View {
        Button(action: performSwipeDelete) {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                    .fill(IronTheme.danger)

                HStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Delete")
                        .font(.system(size: 12, weight: .bold))
                }
                .fixedSize()
                .foregroundColor(IronTheme.onMedia)
                .frame(width: deleteRevealWidth)
                .opacity(deleteRevealWidth >= 52 ? 1 : deleteRevealWidth / 52)
                .scaleEffect(reduceMotion || deleteRevealWidth >= 52 ? 1 : 0.82)
            }
            .frame(width: deleteRevealWidth + deleteRevealOverlap, height: 52)
        }
        .buttonStyle(.plain)
        .frame(width: deleteRevealWidth + deleteRevealOverlap, height: 52)
        .contentShape(Rectangle())
        .clipped()
        .allowsHitTesting(deleteRevealWidth >= deleteActionWidth * 0.8)
        .accessibilityLabel("Delete set \(index + 1)")
        .accessibilityHidden(deleteRevealWidth < deleteActionWidth * 0.8)
    }

    private var deleteRevealWidth: CGFloat {
        max(0, -swipeOffset)
    }

    private var swipeDeleteGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard allowsSwipeToDelete else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                guard horizontal < 0 || swipeOffset < 0 else { return }

                if !isSwipingSet {
                    isSwipingSet = true
                    swipeStartOffset = swipeOffset
                    focusedField = nil
                }

                swipeOffset = min(
                    0,
                    max(-effectiveRowWidth, swipeStartOffset + horizontal)
                )
            }
            .onEnded { value in
                guard allowsSwipeToDelete else { return }
                guard isSwipingSet else { return }
                let projectedOffset = swipeStartOffset + value.predictedEndTranslation.width
                isSwipingSet = false

                if swipeOffset <= -fullSwipeDeleteThreshold {
                    performSwipeDelete()
                } else {
                    withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                        swipeOffset = projectedOffset < -deleteActionWidth * 0.42
                            ? -deleteActionWidth
                            : 0
                    }
                }
            }
    }

    private func performSwipeDelete() {
        guard !isPerformingSwipeDelete else { return }
        isPerformingSwipeDelete = true
        focusedField = nil

        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            swipeOffset = -effectiveRowWidth
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
                if !onDelete() {
                    swipeOffset = 0
                    isPerformingSwipeDelete = false
                }
            }
        }
    }
}

private struct RPEPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var set: WorkoutSet
    let onChanged: () -> Bool

    @State private var selection: Double
    @State private var showingSaveError = false

    init(set: WorkoutSet, onChanged: @escaping () -> Bool) {
        self.set = set
        self.onChanged = onChanged
        _selection = State(initialValue: set.rpeValue ?? 7)
    }

    var body: some View {
        IronUtilitySheet(
            title: "Set effort",
            subtitle: "Rating of perceived exertion",
            systemImage: "gauge.with.dots.needle.50percent",
            onClose: { dismiss() }
        ) {
            List {
                Section {
                    // A wheel is the platform control for picking one value from
                    // an ordered scale, and it reads the selected RPE without the
                    // bespoke carousel's custom scroll math.
                    Picker("RPE", selection: $selection) {
                        ForEach(Array(RPE.allowedValues), id: \.self) { value in
                            Text(String(format: "%g", value))
                                .font(.ironMetric(.body, weight: .semibold))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 130)
                } footer: {
                    Text(RPE.title(selection) ?? "Choose how many repetitions you had left in reserve.")
                }

                Section {
                    Button("Apply RPE \(String(format: "%g", selection))") {
                        set.rpeValue = selection
                        if onChanged() { dismiss() } else { showingSaveError = true }
                    }
                    .fontWeight(.semibold)

                    if set.rpeValue != nil {
                        Button("Clear RPE", role: .destructive) {
                            set.rpeValue = nil
                            if onChanged() { dismiss() } else { showingSaveError = true }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .alert("Effort Not Saved", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your effort change has not been saved. Try applying it again before closing.")
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#if DEBUG
struct WorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        CurrentWorkoutView(workout: MockWorkoutData.metricRandom.currentWorkout)
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
