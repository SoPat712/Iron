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
    @State private var finishTitle = ""
    @State private var sessionEffort = 7.0
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
    @State private var restTimerEditorExercise: WorkoutExercise?
    @State private var exercisePendingRemoval: WorkoutExercise?
    @State private var exercisePendingReplacement: WorkoutExercise?
    @State private var supersetExercise: WorkoutExercise?
    @State private var personalRecordBanner: PersonalRecordBanner?
    @State private var scrollTarget: NSManagedObjectID?
    @State private var runningSetTimers: [NSManagedObjectID: Date] = [:]

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
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(2)
                        }

                        if let banner = personalRecordBanner {
                            personalRecordBannerView(banner)
                                .padding(.horizontal, IronTheme.horizontalPadding)
                                .padding(.top, isSessionHeaderCollapsed ? 62 : 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(3)
                        }
                    }
                }
                .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: $showingExerciseSelector) {
            AddExercisesSheet(
                exercises: exerciseStore.shownExercises,
                recentExercises: AddExercisesSheet.loadRecentExercises(
                    context: managedObjectContext,
                    exercises: exerciseStore.shownExercises
                ),
                title: exercisePendingReplacement == nil ? "Add Exercise" : "Replace Exercise",
                actionTitle: exercisePendingReplacement == nil ? "Add" : "Replace",
                maximumSelectionCount: exercisePendingReplacement == nil ? nil : 1,
                onDismiss: {
                    showingExerciseSelector = false
                    exercisePendingReplacement = nil
                },
                onAdd: applyExerciseSelection
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)        }
        .sheet(isPresented: $showingFinishEditor) {
            finishWorkoutSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)                .interactiveDismissDisabled(isLoadingFinishMedia || isFinishingWorkout)
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
        .sheet(item: $restTimerEditorExercise) { workoutExercise in
            let inheritedDuration = workoutDefaultRestTimerDuration(for: workoutExercise)
            IronDurationPickerSheet(
                title: "Rest timer",
                subtitle: "Recovery after each completed set",
                systemImage: "timer",
                initialDuration: workoutExercise.restTimerDurationValue ?? inheritedDuration,
                minimumDuration: 30,
                maximumDuration: 600,
                durationStep: 15,
                presets: [30, 45, 60, 90, 120, 150, 180, 240, 300],
                secondaryActionTitle: workoutExercise.restTimerDurationValue == nil
                    ? "Keep workout default · \(restTimerDurationFormatter.string(from: inheritedDuration) ?? "0:00")"
                    : "Use workout default · \(restTimerDurationFormatter.string(from: inheritedDuration) ?? "0:00")",
                onSecondaryAction: {
                    setRestTimer(nil, for: workoutExercise)
                },
                onApply: { duration in
                    setRestTimer(duration, for: workoutExercise)
                }
            )
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
                        assignSuperset(between: source, and: candidate)
                        supersetExercise = nil
                    }
                }

                if source.supersetUuid != nil {
                    Button("Remove from Superset", role: .destructive) {
                        removeFromSuperset(source)
                        supersetExercise = nil
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
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = settingsStore.keepScreenAwakeDuringWorkout
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
                    save()
                    activeSheet = nil
                }
            }

        case .restTimer:
            NavigationStack {
                RestTimerView()
                    .environmentObject(restTimerStore)
                    .navigationTitle("Rest Timer")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
            }
            // The timer is deliberately a half-height utility sheet. Its dial
            // and four controls are sized to fit without a second pull-up.
            .presentationDetents([.medium])
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
                        if let workoutExercise = set.workoutExercise {
                            workoutSets(for: workoutExercise).forEach { workoutSet in
                                workoutSet.weightValue = metricWeight
                            }
                        } else {
                            set.weightValue = metricWeight
                        }
                        save()
                        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
                        activeSheet = nil
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
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 4)
                        .accessibilityValue(remaining <= 0 ? "Finished" : restTimerTimeText(remaining))
                } else {
                    Image(systemName: "timer")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                }
            }
        }
        // Keep the timer discoverable beside Finish. A capsule outline gives
        // it the same affordance as the other toolbar controls without adding
        // another filled panel to the workout header.
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(restTimerStore.isPaused ? .orange : .accentColor)
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    (restTimerStore.isPaused ? Color.orange : Color.accentColor).opacity(0.42),
                    lineWidth: 0.8
                )
        }
        .accessibilityLabel("Rest timer")
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
            withAnimation(IronMotion.snappy) { personalRecordBanner = nil }
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
                        tint: IronTheme.accent,
                        systemImage: "pencil"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit workout duration")
                .accessibilityValue(workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                summaryValue("Volume", workoutVolumeTitle)
                summaryValue("Sets", "\(workout.numberOfCompletedSets ?? 0)")

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
                .font(.caption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
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
        tint: Color = IronTheme.primaryText,
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
            .font(.caption)
            .foregroundStyle(systemImage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            Text(value)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
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
            if activeRestTimerExercise?.objectID == workoutExercise.objectID {
                activeRestTimerStrip
                    .padding(.bottom, 14)
            }

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
                        save()
                        if !set.isCompleted {
                            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
                        }
                    },
                    allowsSwipeToDelete: true
                )
                .environmentObject(settingsStore)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    )
                )
            }
            .animation(
                IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion),
                value: sets.count
            )

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
            moveWorkoutExercise(from: source, to: index)
            return true
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

    private enum ActiveRestTimerMetrics {
        static let containerHeight: CGFloat = 46
        static let controlHeight: CGFloat = 32
        static let iconControlWidth: CGFloat = 36
        static let textControlWidth: CGFloat = 50
        static let countdownWidth: CGFloat = 74
        static let contentSpacing: CGFloat = 4
        static let minimumControlGap: CGFloat = 4
        static let horizontalPadding: CGFloat = 10
    }

    private var activeRestTimerStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let remaining = restTimerStore.restTimerRemainingTime {
                HStack(spacing: ActiveRestTimerMetrics.contentSpacing) {
                    Button(action: { activeSheet = .restTimer }) {
                        Text(restTimerCountdownText(remaining))
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .contentTransition(.numericText())
                        .foregroundColor(IronTheme.accent)
                        .frame(width: ActiveRestTimerMetrics.countdownWidth, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rest timer")
                    .accessibilityValue(remaining <= 0 ? "Finished" : restTimerTimeText(remaining))

                    HStack(spacing: 0) {
                        activeTimerControl(title: "−15", systemImage: nil, label: "Subtract 15 seconds") {
                            adjustActiveRestTimer(by: -15)
                        }
                        Spacer(minLength: ActiveRestTimerMetrics.minimumControlGap)
                        activeTimerControl(
                            title: "",
                            systemImage: restTimerStore.isPaused ? "play.fill" : "pause.fill",
                            label: restTimerStore.isPaused ? "Resume rest timer" : "Pause rest timer"
                        ) {
                            restTimerStore.isPaused ? restTimerStore.resume() : restTimerStore.pause()
                            WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
                        }
                        Spacer(minLength: ActiveRestTimerMetrics.minimumControlGap)
                        activeTimerControl(title: "+15", systemImage: nil, label: "Add 15 seconds") {
                            adjustActiveRestTimer(by: 15)
                        }
                        Spacer(minLength: ActiveRestTimerMetrics.minimumControlGap)
                        activeTimerControl(
                            title: "",
                            systemImage: "xmark",
                            label: "Stop rest timer",
                            tint: .red,
                            action: stopActiveRestTimer
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, ActiveRestTimerMetrics.horizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: ActiveRestTimerMetrics.containerHeight)
                // The live countdown is the one thing on this screen that must
                // stay readable at a glance mid-set, so it floats on glass.
                .ironLiquidGlassPill(tint: .clear)
            }
        }
    }

    private func restTimerTimeText(_ remaining: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: abs(remaining.rounded(.up))) ?? "0:00"
    }

    private func restTimerCountdownText(_ remaining: TimeInterval) -> String {
        restTimerTimeText(max(remaining, 0))
    }

    private func activeTimerControl(
        title: String,
        systemImage: String?,
        label: String,
        tint: Color = IronTheme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if title.isEmpty, let systemImage {
                    Image(systemName: systemImage)
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }

            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(
                width: title.isEmpty
                    ? ActiveRestTimerMetrics.iconControlWidth
                    : ActiveRestTimerMetrics.textControlWidth,
                height: ActiveRestTimerMetrics.controlHeight
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .foregroundStyle(tint)
        .tint(tint)
        .ironLiquidGlassPill(tint: tint.opacity(0.06))
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
                finishSummarySection
                finishTitleSection
                finishEffortSection
                finishNotesSection
                finishMediaSection
                finishTimingSection
                finishSyncSection
                finishExerciseSummarySection
                finishDiscardSection
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingFinishEditor = false }
                        .disabled(isFinishingWorkout)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFinishingWorkout ? "Saving…" : "Finish", action: finishWorkout)
                        .fontWeight(.semibold)
                        .disabled(isLoadingFinishMedia || isFinishingWorkout)
                }
            }
        }
        .onAppear(perform: prepareFinishEditor)
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

    private var finishSummarySection: some View {
        Section {
            LabeledContent("Duration", value: workoutDurationFormatter.string(from: finishDuration) ?? "0:00")
                .monospacedDigit()
            LabeledContent("Volume", value: workoutVolumeTitle)
                .monospacedDigit()
            LabeledContent("Completed Sets", value: "\(workout.numberOfCompletedSets ?? 0)")
                .monospacedDigit()
        } header: {
            Text("Session Summary")
        } footer: {
            Text("Review the session, then tap Finish to save it to your history.")
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
            EffortRatingGraph(rating: sessionEffortSelection)
                .padding(.vertical, 6)
        } header: {
            Text("Session Effort")
        } footer: {
            Text(effortLabel)
        }
    }

    /// The effort picker writes back into the same 1–10 scale the rest of the
    /// app stores, so the segmented control stays the source of truth.
    private var sessionEffortSelection: Binding<Int> {
        Binding(
            get: { Int(sessionEffort.rounded()) },
            set: { sessionEffort = Double($0) }
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
            Toggle("Sync with Apple Health", isOn: $syncWithHealth)

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
                showingDiscardConfirmation = true
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

    private var effortLabel: String {
        switch sessionEffort {
        case 1...2: return "Very light — plenty left in the tank"
        case 3...4: return "Light and comfortable"
        case 5...6: return "Solid training effort"
        case 7...8: return "Hard, productive work"
        case 9: return "Near your limit"
        default: return "All-out effort"
        }
    }

    private let workoutDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

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

    private func addExercises(_ selection: [Exercise]) {
        for exercise in selection {
            let workoutExercise = WorkoutExercise.create(context: managedObjectContext)
            workout.addToWorkoutExercises(workoutExercise)
            workoutExercise.exerciseUuid = exercise.uuid
            workoutExercise.addToWorkoutSets(createDefaultWorkoutSets(for: workoutExercise, exercise: exercise))
        }
        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
    }

    private func applyExerciseSelection(_ selection: [Exercise]) {
        if let target = exercisePendingReplacement, let replacement = selection.first {
            target.exerciseUuid = replacement.uuid
            exercisePendingReplacement = nil
            save()
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        } else {
            addExercises(selection)
        }
        showingExerciseSelector = false
    }

    private func supersetCandidateTitle(_ workoutExercise: WorkoutExercise) -> String {
        workoutExercise.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise"
    }

    private func assignSuperset(between source: WorkoutExercise, and candidate: WorkoutExercise) {
        let existingIDs = Set([source.supersetUuid, candidate.supersetUuid].compactMap { $0 })
        let supersetID = source.supersetUuid ?? candidate.supersetUuid ?? UUID()

        for workoutExercise in workoutExercises {
            let belongsToExistingGroup = workoutExercise.supersetUuid.map(existingIDs.contains) ?? false
            if workoutExercise.objectID == source.objectID
                || workoutExercise.objectID == candidate.objectID
                || belongsToExistingGroup {
                workoutExercise.supersetUuid = supersetID
            }
        }

        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func removeFromSuperset(_ source: WorkoutExercise) {
        let previousID = source.supersetUuid
        source.supersetUuid = nil

        if let previousID {
            let remaining = workoutExercises.filter { $0.supersetUuid == previousID }
            if remaining.count < 2 {
                remaining.forEach { $0.supersetUuid = nil }
            }
        }

        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        UISelectionFeedbackGenerator().selectionChanged()
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

    private func addSet(to workoutExercise: WorkoutExercise) {
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
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
            save()
        }
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
    }

    private func deleteSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            workoutExercise.removeFromWorkoutSets(set)
            managedObjectContext.delete(set)
            save()
        }
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
    }

    private func deleteWorkoutExercise(_ workoutExercise: WorkoutExercise) {
        workout.removeFromWorkoutExercises(workoutExercise)
        managedObjectContext.delete(workoutExercise)
        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
    }

    private func moveWorkoutExercise(from source: Int, to destination: Int) {
        guard source != destination,
              workoutExercises.indices.contains(source),
              workoutExercises.indices.contains(destination) else { return }
        var exercises = workoutExercises
        let exercise = exercises.remove(at: source)
        exercises.insert(exercise, at: destination)
        workout.workoutExercises = NSOrderedSet(array: exercises)
        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func toggleCompleted(_ set: WorkoutSet, in workoutExercise: WorkoutExercise) {
        let justCompleted = !set.isCompleted
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            restTimerStore.cancel()
        } else {
            set.weightValue = max(set.weightValue, 0)
            set.repetitionsValue = max(set.repetitionsValue, 0)
            set.isCompleted = true
            set.completedAt = Date()
            workout.start = workout.start ?? Date()

            let isRecord = settingsStore.personalRecordAlerts && set.isPersonalRecord == true

            if settingsStore.workoutHaptics {
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                feedback.notificationOccurred(isRecord ? .warning : .success)
            }
            if settingsStore.workoutSounds {
                AudioServicesPlaySystemSound(isRecord ? 1025 : 1103)
            }
            if isRecord {
                announcePersonalRecord(for: set, in: workoutExercise)
            }

            if settingsStore.autoStartRestTimer {
                restTimerStore.start(duration: restTimerDuration(for: workoutExercise))
            }
        }
        save()

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
        withAnimation(IronMotion.snappy) {
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

    private func setRestTimer(_ duration: TimeInterval?, for workoutExercise: WorkoutExercise) {
        workoutExercise.restTimerDurationValue = duration
        save()
    }

    private func setTrackingMode(usesDuration: Bool, for workoutExercise: WorkoutExercise) {
        let sets = workoutSets(for: workoutExercise)
        guard !sets.contains(where: \.isCompleted) else { return }

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
        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
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

    private func addWarmupSets(_ recommendations: [WarmupRecommendation], before workingSet: WorkoutSet) {
        guard let workoutExercise = workingSet.workoutExercise,
              let index = workoutExercise.workoutSets?.index(of: workingSet),
              index != NSNotFound else { return }

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
        save()
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        activeSheet = nil
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
        sessionEffort = workout.sessionEffortValue ?? 7
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

        let trimmedTitle = finishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = workout.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        workout.title = trimmedTitle.isEmpty
            ? workout.generatedTitle(in: exerciseStore.exercises)
            : trimmedTitle
        workout.comment = trimmedComment.isEmpty ? nil : trimmedComment
        workout.start = finishStartDate
        workout.end = finishEndDate
        workout.sessionEffortValue = sessionEffort
        if updateLinkedRoutine {
            updateLinkedRoutineFromCompletedSets()
        }
        UserDefaults.standard.set(syncWithHealth, forKey: "Iron.finishWorkout.syncWithHealth")
        save()
        showingFinishEditor = false
        workout.finishOrCrash(syncToHealth: syncWithHealth)

        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
        AudioServicesPlaySystemSound(1103)

        UserDefaults.standard.finishedWorkoutsCount += 1
        if UserDefaults.standard.finishedWorkoutsCount == 6,
           let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    private func cancelWorkout() {
        activeSheet = nil
        showingFinishEditor = false
        if let workoutUUID = workout.uuid {
            FinishWorkoutMediaStore.remove(for: workoutUUID)
        }
        workout.cancelOrCrash()
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.warning)
    }

    private func save() {
        guard managedObjectContext.hasChanges else { return }
        managedObjectContext.saveOrCrash()
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
    static let setWidth: CGFloat = 36
    static let previousWidth: CGFloat = 72
    static let repetitionsWidth: CGFloat = 48
    static let rpeWidth: CGFloat = 42
    static let completionWidth: CGFloat = 40
}

private struct CompletedSetGlassChrome: ViewModifier {
    let isCompleted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCompleted {
            content
                .background(IronTheme.successContainer, in: Capsule(style: .continuous))
                .ironLiquidGlassPill(tint: IronTheme.success.opacity(0.10))
        } else {
            content
        }
    }
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
    let onDelete: () -> Void
    let onChanged: () -> Void
    var allowsSwipeToDelete = false

    @State private var showingRPEPicker = false
    @State private var showingDurationPicker = false
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
                    set.isCompleted
                        ? IronTheme.onSuccessContainer
                        : (isRunning ? .red : IronTheme.accent)
                )
            Text(text)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.primaryText)
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
            onChanged()
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
                        onChanged()
                    }
                    return
                }

                let metricValue = min(
                    max(WeightUnit.convert(weight: displayValue, from: settingsStore.weightUnit, to: .metric), 0),
                    WorkoutSet.MAX_WEIGHT
                )
                if abs(set.weightValue - metricValue) > 0.000_001 {
                    set.weightValue = metricValue
                    onChanged()
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
                    onChanged()
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
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundColor(
                        set.isCompleted
                            ? IronTheme.onSuccessContainer
                            : (set.tagValue == .warmUp ? IronTheme.warning : IronTheme.primaryText)
                    )
                    .frame(width: InlineWorkoutSetLayout.setWidth, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(set.isCompleted ? IronTheme.successControl : Color(.tertiarySystemFill))
                    )
            }
            .accessibilityLabel("Set type")

            Text(previousTitle)
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.secondaryText)
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
                        } else {
                            Image(systemName: "gauge.with.dots.needle.50percent")
                        }
                    }
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(
                        set.isCompleted
                            ? IronTheme.onSuccessContainer
                            : (set.rpeValue == nil ? IronTheme.secondaryText : IronTheme.accent)
                    )
                    .frame(width: InlineWorkoutSetLayout.rpeWidth, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(set.isCompleted ? IronTheme.successControl : Color(.tertiarySystemFill))
                    )
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
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(
                        set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.secondaryText
                    )
                    // Completing a set is the most repeated action in the app, so
                    // it gets the one piece of overshoot motion in the logger.
                    .scaleEffect(set.isCompleted ? 1.12 : 1)
                    .frame(width: InlineWorkoutSetLayout.completionWidth, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(set.isCompleted ? IronTheme.successControl : Color(.tertiarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, completed in completed }
            .accessibilityLabel(
                set.isCompleted
                    ? "Set \(index + 1) completed"
                    : "Mark set \(index + 1) complete"
            )
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
            .accessibilityRemoveTraits(.isSelected)
            .accessibilityAddTraits(set.isCompleted ? .isSelected : [])
            }
            // Completion changes only the chrome. The table columns keep the
            // same geometry, while the green treatment remains inset from the
            // exercise card and rounds into a true glass capsule.
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .modifier(CompletedSetGlassChrome(isCompleted: set.isCompleted))
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
        .onAppear(perform: synchronizeEntryText)
        .onChange(of: set.isCompleted) { _, isCompleted in
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
            if newValue != .weight {
                weightText = formattedWeight
            }
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
                initialDuration: set.durationValue ?? 60
            ) { duration in
                set.durationValue = duration
                set.distanceValue = nil
                set.weightValue = 0
                set.repetitionsValue = 0
                onChanged()
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
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var setTagBinding: Binding<WorkoutSetTag?> {
        Binding(
            get: { set.tagValue },
            set: {
                set.tagValue = $0
                onChanged()
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
        return weightFormatter.string(from: NSNumber(value: displayValue)) ?? "0"
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
            .font(.system(size: 16, weight: .medium).monospacedDigit())
            .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.primaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 46)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                    .fill(
                        set.isCompleted
                            ? IronTheme.successControl
                            : (isFocused ? IronTheme.accentSoft : Color(.tertiarySystemFill))
                    )
                    // The focus ring is the only stroke left on a set field; the
                    // resting outline was pure decoration on top of a filled shape.
                    .overlay {
                        if isFocused && !set.isCompleted {
                            RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
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
                .scaleEffect(deleteRevealWidth >= 52 ? 1 : 0.82)
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
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

        withAnimation(.snappy(duration: 0.28)) {
            swipeOffset = -effectiveRowWidth
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.snappy(duration: 0.22)) {
                onDelete()
            }
        }
    }
}

private struct RPEPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var set: WorkoutSet
    let onChanged: () -> Void

    @State private var selection: Double

    init(set: WorkoutSet, onChanged: @escaping () -> Void) {
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
                                .monospacedDigit()
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
                        onChanged()
                        dismiss()
                    }
                    .fontWeight(.semibold)

                    if set.rpeValue != nil {
                        Button("Clear RPE", role: .destructive) {
                            set.rpeValue = nil
                            onChanged()
                            dismiss()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
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
