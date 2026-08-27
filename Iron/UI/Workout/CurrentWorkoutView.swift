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
import MuscleMap
import WorkoutDataKit

private struct CurrentWorkoutScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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

    init(workout: Workout, onMinimize: @escaping () -> Void = {}) {
        self.workout = workout
        self.onMinimize = onMinimize
    }

    private enum SheetType: Identifiable {
        case workoutTime
        case restTimer
        case plates(WorkoutSet)
        case warmups(WorkoutSet)

        var id: String {
            switch self {
            case .workoutTime: return "workout-time"
            case .restTimer: return "rest-timer"
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

    private var workoutSummaryHeight: CGFloat {
        usesAccessibilityHeaderLayout ? 84 : 72
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
                IronScreenBackground()

                VStack(spacing: 0) {
                    workoutTopBar
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            sessionHeader

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

                                    Button(action: { showingExerciseSelector = true }) {
                                        Label("Add Exercises", systemImage: "plus")
                                    }
                                    .buttonStyle(IronSecondaryButtonStyle())
                                    .padding(.horizontal, IronTheme.horizontalPadding)
                                    .padding(.top, 22)

                                    Button(role: .destructive, action: { showingDiscardConfirmation = true }) {
                                        Text("Discard workout")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(IronTheme.danger)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, IronTheme.horizontalPadding)
                                    .padding(.top, 10)
                                    .padding(.bottom, 28)
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
                        }

                        if isSessionHeaderCollapsed {
                            collapsedWorkoutSummaryPill
                                .padding(.horizontal, IronTheme.horizontalPadding)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(2)
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
                usesModalSurface: true,
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
            .presentationDragIndicator(.visible)
            .presentationBackground(IronTheme.modalSurface)
        }
        .sheet(isPresented: $showingFinishEditor) {
            finishWorkoutSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(IronTheme.modalSurface)
                .interactiveDismissDisabled(isLoadingFinishMedia || isFinishingWorkout)
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
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
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
        .confirmationDialog(
            "Remove \(exercisePendingRemovalTitle)?",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            ),
            titleVisibility: .visible
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
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: SheetType) -> some View {
        switch sheet {
        case .workoutTime:
            utilitySheet(
                title: "Workout duration",
                subtitle: "Adjust the session clock without leaving your set log",
                systemImage: "stopwatch",
                detents: [.fraction(0.82), .large]
            ) {
                EditCurrentWorkoutTimeView(workout: workout) {
                    save()
                    activeSheet = nil
                }
            }

        case .restTimer:
            utilitySheet(
                title: "Rest timer",
                subtitle: "Dial in your recovery",
                systemImage: "timer",
                detents: [.height(430)]
            ) {
                RestTimerView()
                    .environmentObject(restTimerStore)
            }

        case .plates(let set):
            utilitySheet(
                title: "Plate calculator",
                subtitle: "Load each side of the bar",
                systemImage: "circle.grid.cross",
                detents: [.fraction(0.78)]
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: max(displayWeight(for: set), settingsStore.weightUnit.barbellWeight),
                    onApply: { value in
                        set.weightValue = WeightUnit.convert(
                            weight: value,
                            from: settingsStore.weightUnit,
                            to: .metric
                        )
                        save()
                        activeSheet = nil
                    }
                )
            }

        case .warmups(let set):
            utilitySheet(
                title: "Warm-up calculator",
                subtitle: "Build up to your working weight",
                systemImage: "flame",
                detents: [.height(620)]
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
        .presentationContentInteraction(.scrolls)
        .presentationBackground(IronTheme.modalSurface)
    }

    private var workoutTopBar: some View {
        HStack(spacing: 10) {
            Button(action: onMinimize) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(IronIconButtonStyle())
            .accessibilityLabel("Minimize workout")

            Text(usesAccessibilityHeaderLayout ? "Workout" : "Log Workout")
                .font(.headline)
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 4)

            Button(action: { activeSheet = .restTimer }) {
                Image(systemName: "timer")
            }
            .buttonStyle(IronIconButtonStyle())
            .accessibilityLabel("Rest timer")

            Button("Finish") { showingFinishEditor = true }
                .buttonStyle(IronCompactPillButtonStyle(prominent: true))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .disabled(workoutExercises.isEmpty)
                .opacity(workoutExercises.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .frame(height: workoutTopBarHeight)
        .background(IronTheme.topBar.ignoresSafeArea(edges: .top))
        .overlay(IronHairline(opacity: 0.30), alignment: .bottom)
    }

    private var sessionHeader: some View {
        VStack(spacing: 0) {
            watchSyncBanner

            IronHairline(opacity: 0.55)
            workoutSummary
                .frame(height: workoutSummaryHeight)
        }
        // The full-size header moves through a clipped reveal window. The metric labels
        // themselves never scale or compress; the compact glass pill is a separate layout.
        .frame(height: sessionHeaderExpandedHeight)
        .offset(y: isSessionHeaderCollapsed ? -sessionHeaderExpandedHeight : 0)
        .frame(height: isSessionHeaderCollapsed ? 0 : sessionHeaderExpandedHeight, alignment: .top)
        .background(IronTheme.background)
        .overlay(IronHairline(), alignment: .bottom)
        .clipped()
        .allowsHitTesting(!isSessionHeaderCollapsed)
        .accessibilityHidden(isSessionHeaderCollapsed)
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

        if reduceMotion {
            isSessionHeaderCollapsed = collapsed
        } else {
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.90)) {
                isSessionHeaderCollapsed = collapsed
            }
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
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(usesAccessibilityHeaderLayout ? 2 : 1)
                .minimumScaleFactor(0.75)
            Spacer()
            Image(systemName: watchSyncSystemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(color)

            Button(action: { setSessionHeaderCollapsed(!isSessionHeaderCollapsed) }) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.secondaryText)
                    .rotationEffect(.degrees(isSessionHeaderCollapsed ? 180 : 0))
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                    .background(Circle().fill(IronTheme.raisedSurface))
            }
            .buttonStyle(.plain)
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
            .padding(.vertical, 12)
        }
    }

    private var collapsedWorkoutSummaryPill: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            Button(action: { setSessionHeaderCollapsed(false) }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(IronTheme.accent)
                        .frame(width: 7, height: 7)

                    Text(workoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                    Text("•")
                        .foregroundColor(IronTheme.tertiaryText)
                    Text(workoutVolumeTitle)
                    Text("•")
                        .foregroundColor(IronTheme.tertiaryText)
                    Text("\(workout.numberOfCompletedSets ?? 0) sets")

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.accent)
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
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
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption)
            .foregroundColor(systemImage == nil ? IronTheme.secondaryText : IronTheme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            Text(value)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundColor(tint)
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
        .frame(height: 54)
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
            defaultFillColor: IronTheme.secondaryText.opacity(0.14),
            strokeColor: IronTheme.secondaryText.opacity(0.16),
            strokeWidth: 0.5,
            selectionColor: IronTheme.accent,
            selectionStrokeColor: IronTheme.accent,
            selectionStrokeWidth: 1,
            headColor: IronTheme.secondaryText.opacity(0.20),
            hairColor: IronTheme.secondaryText.opacity(0.10)
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
                    TextField("Workout title", text: workoutTitle)
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
            .overlay(IronHairline(opacity: 0.45), alignment: .bottom)
        }
    }

    private var emptyWorkoutState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("Start with an exercise")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Add exercises, then log weight, reps and effort directly on this screen.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 42)
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
                        .fill(IronTheme.surface)
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "dumbbell.fill").foregroundColor(IronTheme.accent))
                }

                if let exercise = exercise {
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.title)
                                .font(.body.weight(.semibold))
                                .foregroundColor(IronTheme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)

                            if workoutExercise.supersetUuid != nil {
                                Label("Superset", systemImage: "link")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                        }
                        .draggable(workoutExercise.objectID.uriRepresentation().absoluteString)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to open. Touch and hold, then drag to reorder.")
                } else {
                    Text("Unknown Exercise")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(IronTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                IronPopupMenu(
                    title: "Exercise actions",
                    actions: exercisePopupActions(
                        for: workoutExercise,
                        sets: sets,
                        isBarbell: isBarbell && !usesDuration
                    ),
                    arrowEdge: index == 0 ? .top : .bottom
                ) {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                        .frame(width: 42, height: 42)
                }
            }

            TextField("Add notes here…", text: exerciseCommentBinding(for: workoutExercise))
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
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
                .background {
                    if set.isCompleted {
                        // The completion wash belongs to the table row, not its controls.
                        // Extending the paint through the section inset keeps every column
                        // perfectly stationary while the color reaches both screen edges.
                        Rectangle()
                            .fill(IronTheme.successContainer)
                            .padding(.horizontal, -IronTheme.horizontalPadding)
                    }
                }
            }

            Button(action: { addSet(to: workoutExercise) }) {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(IronSecondaryButtonStyle())
            .padding(.top, 10)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(IronTheme.background)
        .overlay(IronHairline(), alignment: .bottom)
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

    private func exercisePopupActions(
        for workoutExercise: WorkoutExercise,
        sets: [WorkoutSet],
        isBarbell: Bool
    ) -> [IronPopupAction] {
        var actions: [IronPopupAction] = [
            IronPopupAction(title: "Replace", systemImage: "arrow.triangle.2.circlepath") {
                exercisePendingReplacement = workoutExercise
                showingExerciseSelector = true
            },
            IronPopupAction(title: "Superset", systemImage: "link") {
                supersetExercise = workoutExercise
            }
        ]

        if isBarbell, let workingSet = sets.first(where: { $0.tagValue != .warmUp }) ?? sets.first {
            actions.append(IronPopupAction(title: "Plate Calculator", systemImage: "circle.grid.cross") {
                activeSheet = .plates(workingSet)
            })
            actions.append(IronPopupAction(title: "Warm-up Calculator", systemImage: "flame") {
                activeSheet = .warmups(workingSet)
            })
        }
        actions.append(IronPopupAction(
            title: "Remove Exercise",
            systemImage: "trash",
            role: .destructive
        ) {
            exercisePendingRemoval = workoutExercise
        })

        return actions
    }

    private func setTableHeader(usesDuration: Bool) -> some View {
        HStack(spacing: InlineWorkoutSetLayout.spacing) {
            Text("SET").frame(width: InlineWorkoutSetLayout.setWidth)
            Text("PREVIOUS").frame(width: InlineWorkoutSetLayout.previousWidth, alignment: .center)
            if usesDuration {
                Text("DURATION")
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "dumbbell")
                        .accessibilityHidden(true)
                    Text(settingsStore.weightUnit.unit.symbol.uppercased())
                }
                .frame(maxWidth: .infinity)
                Text("REPS").frame(width: InlineWorkoutSetLayout.repetitionsWidth)
            }
            Text("RPE").frame(width: InlineWorkoutSetLayout.rpeWidth)
            Image(systemName: "checkmark")
                .frame(width: InlineWorkoutSetLayout.completionWidth)
                .accessibilityHidden(true)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(IronTheme.secondaryText)
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

    private var activeRestTimerStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let remaining = restTimerStore.restTimerRemainingTime {
                let timeText = restTimerDurationFormatter.string(from: abs(remaining.rounded(.up))) ?? "0:00"
                HStack(spacing: 8) {
                    Button(action: { activeSheet = .restTimer }) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 15, weight: .semibold))
                            Text(remaining < 0 ? "+\(timeText)" : timeText)
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .contentTransition(.numericText())
                        }
                        .foregroundColor(remaining < 0 ? IronTheme.danger : IronTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rest timer")
                    .accessibilityValue(remaining < 0 ? "Over by \(timeText)" : timeText)

                    activeTimerControl(systemImage: "minus", label: "Subtract 15 seconds") {
                        adjustActiveRestTimer(by: -15)
                    }
                    activeTimerControl(systemImage: "plus", label: "Add 15 seconds") {
                        adjustActiveRestTimer(by: 15)
                    }

                    Button(action: stopActiveRestTimer) {
                        Text("Skip")
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip rest timer")
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                        .fill(IronTheme.accentSoft.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                        .stroke(IronTheme.accent.opacity(0.28), lineWidth: 1)
                )
            }
        }
    }

    private func activeTimerControl(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(IronTheme.raisedSurface))
        }
        .buttonStyle(.plain)
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
        Button(action: { restTimerEditorExercise = workoutExercise }) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                Text("Rest Timer: \(restTimerTitle(for: workoutExercise))")
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(IronTheme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rest timer for \(restTimerTitle(for: workoutExercise))")
        .accessibilityHint("Opens a radial rest-duration picker")
    }

    private var finishWorkoutSheet: some View {
        NavigationStack {
            ZStack {
                IronScreenBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        finishIntroCard
                        finishSessionSummaryCard
                        finishEffortCard
                        finishMediaCard
                        finishNotesCard
                        finishStartDateCard
                        finishVisibilityCard
                        finishRoutineSettingsCard
                        finishHealthCard
                        finishExerciseSummaryCard
                        finishSaveActions
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(false)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(IronTheme.topBar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

    private var finishIntroCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundColor(IronTheme.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session complete")
                            .font(.title3.weight(.bold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Make a few final edits before saving it to your history.")
                            .font(.subheadline)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }

                TextField("Workout title", text: $finishTitle)
                    .font(.headline.weight(.semibold))
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.field)
                    )
            }
        }
    }

    private var finishSessionSummaryCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 12) {
                finishSectionLabel("Session summary", systemImage: "chart.bar.xaxis")

                HStack(spacing: 0) {
                    finishSummaryMetric(
                        icon: "clock",
                        value: workoutDurationFormatter.string(from: finishDuration) ?? "0:00",
                        label: "Duration",
                        tint: IronTheme.accent
                    )
                    finishSummaryDivider
                    finishSummaryMetric(
                        icon: "scalemass",
                        value: workoutVolumeTitle,
                        label: "Volume",
                        tint: IronTheme.warning
                    )
                    finishSummaryDivider
                    finishSummaryMetric(
                        icon: "checkmark.circle",
                        value: "\(workout.numberOfCompletedSets ?? 0)",
                        label: "Sets",
                        tint: IronTheme.success
                    )
                }
                .padding(.vertical, 13)
            }
        }
    }

    private var finishEffortCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        finishSectionLabel("Session effort", systemImage: "gauge.with.dots.needle.67percent")
                        Text(effortLabel)
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                    Spacer()
                    Text("\(Int(sessionEffort))/10")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundColor(IronTheme.accent)
                }

                IronEffortCarousel(
                    selection: Binding(
                        get: { sessionEffort },
                        set: { newValue in
                            if let newValue { sessionEffort = newValue }
                        }
                    )
                )
            }
        }
    }

    private var finishMediaCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 12) {
                finishSectionLabel("Workout media", systemImage: "photo.on.rectangle")
                Text("Add one photo or video to remember this session. It stays on this device.")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)

                if finishMediaURL != nil {
                    finishMediaPreview
                }

                PhotosPicker(
                    selection: $finishMediaItem,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Label(
                        finishMediaURL == nil ? "Add photo or video" : "Replace media",
                        systemImage: finishMediaURL == nil ? "plus" : "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(IronSecondaryButtonStyle())
                .disabled(isLoadingFinishMedia)

                if isLoadingFinishMedia {
                    HStack(spacing: 8) {
                        ProgressView().tint(IronTheme.accent)
                        Text("Saving media…")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }

                if let finishMediaError = finishMediaError {
                    Text(finishMediaError)
                        .font(.caption)
                        .foregroundColor(IronTheme.danger)
                }
            }
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
                        .font(.title2.weight(.bold))
                        .foregroundColor(IronTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(IronTheme.accentSoft)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(finishMediaKind == .video ? "Video attached" : "Photo attached")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Saved with this workout")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            }

            Spacer()

            Button("Remove", role: .destructive, action: removeFinishMedia)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
    }

    private var finishNotesCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 10) {
                finishSectionLabel("Description & notes", systemImage: "note.text")

                ZStack(alignment: .topLeading) {
                    if workoutComment.wrappedValue.isEmpty {
                        Text("What went well? Add context for your future self…")
                            .font(.body)
                            .foregroundColor(IronTheme.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: workoutComment)
                        .font(.body)
                        .foregroundColor(IronTheme.primaryText)
                        .frame(minHeight: 116)
                        .scrollContentBackground(.hidden)
                        .padding(2)
                        .background(IronTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous))
                }
            }
        }
    }

    private var finishStartDateCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 12) {
                finishSectionLabel("Start date & time", systemImage: "calendar.badge.clock")

                IronDateTimeButton(
                    title: "Started",
                    systemImage: "play.fill",
                    date: finishStartDate,
                    action: { showingFinishStartDateEditor = true }
                )

                HStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .foregroundColor(IronTheme.accent)
                    Text("Duration stays \(workoutDurationFormatter.string(from: finishDuration) ?? "0:00"); finish time becomes \(finishEndDate.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
            }
        }
    }

    private var finishVisibilityCard: some View {
        finishPanel {
            Button(action: { showingVisibilityInfo = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(IronTheme.accentSoft))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Visibility")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Private · Only you")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundColor(IronTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Iron workouts are private. Tap to learn why.")
        }
    }

    private var finishRoutineSettingsCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 10) {
                finishSectionLabel("Saved workout", systemImage: "arrow.triangle.2.circlepath")

                Toggle(isOn: $updateLinkedRoutine) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Update linked workout")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(workout.workoutRoutine == nil ? IronTheme.tertiaryText : IronTheme.primaryText)
                        Text(workout.workoutRoutine == nil
                             ? "This session was not started from a saved workout."
                             : "Write completed weights and reps back to \(workout.workoutRoutine?.displayTitle ?? "this workout") next time.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }
                .toggleStyle(.switch)
                .tint(IronTheme.accent)
                .disabled(workout.workoutRoutine == nil)

                if workout.workoutRoutine != nil {
                    Text("Only completed sets are used; your saved workout remains editable afterward.")
                        .font(.caption)
                        .foregroundColor(IronTheme.tertiaryText)
                }
            }
        }
    }

    private var finishHealthCard: some View {
        finishPanel {
            Toggle(isOn: $syncWithHealth) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.danger)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(IronTheme.danger.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sync with Apple Health")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(IronTheme.primaryText)
                        Text(syncWithHealth ? "Will save this workout to Apple Health." : "Stored in Iron only for now.")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(IronTheme.accent)
        }
    }

    private var finishExerciseSummaryCard: some View {
        finishPanel {
            VStack(alignment: .leading, spacing: 10) {
                finishSectionLabel("Exercise summary", systemImage: "figure.strengthtraining.traditional")

                ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    let exercise = workoutExercise.exercise(in: exerciseStore.exercises)
                    HStack(spacing: 12) {
                        if let exercise = exercise {
                            ExerciseDiagramThumbnail(exercise: exercise, size: 38)
                        } else {
                            Circle()
                                .fill(IronTheme.raisedSurface)
                                .frame(width: 38, height: 38)
                                .overlay(Image(systemName: "dumbbell.fill").foregroundColor(IronTheme.accent))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise?.title ?? "Unknown exercise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text("\(workoutExercise.numberOfCompletedSets ?? 0) completed sets")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }

                        Spacer()
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(IronTheme.tertiaryText)
                    }

                    if index < workoutExercises.count - 1 {
                        Divider().background(IronTheme.outline)
                    }
                }
            }
        }
    }

    private var finishSaveActions: some View {
        finishPanel {
            Button("Discard workout", role: .destructive) {
                showingDiscardConfirmation = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(IronTheme.danger)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .accessibilityHint("Permanently deletes this workout and its logged sets.")
        }
    }

    private func finishSectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(IronTheme.primaryText)
    }

    private func finishPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
    }

    private func finishSummaryMetric(
        icon: String,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var finishSummaryDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.6))
            .frame(width: 1, height: 42)
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
                IronCard(padding: 14) {
                    Text("Iron has no social feed or public profiles. Finished workouts are always saved as Private · Only you, so your training history stays on this device and in your personal backups.")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                IronCard(padding: 14) {
                    HStack(spacing: 11) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(IronTheme.success)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(IronTheme.success.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Only you can see it")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(IronTheme.primaryText)
                            Text("There is nothing else to publish or configure.")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(IronTheme.horizontalPadding)
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(IronTheme.modalSurface)
    }

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
        let history = (try? managedObjectContext.fetch(workoutExercise.historyFetchRequest)) ?? []
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
        WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
    }

    private func deleteSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        workoutExercise.removeFromWorkoutSets(set)
        managedObjectContext.delete(set)
        save()
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

            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1103)

            restTimerStore.restTimerDuration = restTimerDuration(for: workoutExercise)
            restTimerStore.restTimerStart = Date()
        }
        save()

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
        finishTitle = workout.title ?? workout.workoutPlanAndRoutineTitle() ?? ""
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
        workout.title = trimmedTitle.isEmpty ? nil : trimmedTitle
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

struct InlineWorkoutSetRow: View {
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
            IronPopupMenu(title: "Set type", actions: setTypePopupActions, arrowEdge: .bottom) {
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
                            .fill(set.isCompleted ? IronTheme.successControl : IronTheme.raisedSurface)
                    )
            }

            Text(previousTitle)
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(width: InlineWorkoutSetLayout.previousWidth, alignment: .center)

            if usesDuration {
                setField {
                    Button(action: { showingDurationPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.accent)
                            Text(restTimerDurationFormatter.string(from: set.durationValue ?? 60) ?? "1:00")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundColor(set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.primaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set duration")
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
                        .fill(set.isCompleted ? IronTheme.successControl : IronTheme.raisedSurface)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rpeAccessibilityLabel)
            .accessibilityHint("Opens the effort selector")

            Button(action: onToggleCompleted) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(
                        set.isCompleted ? IronTheme.onSuccessContainer : IronTheme.secondaryText
                    )
                    .frame(width: InlineWorkoutSetLayout.completionWidth, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(set.isCompleted ? IronTheme.successControl : IronTheme.raisedSurface)
                )
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
            .padding(.vertical, 4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.background)

                    if set.isCompleted {
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.successContainer)
                    }
                }
            )
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
        .clipped()
        .simultaneousGesture(swipeDeleteGesture)
        .onAppear(perform: synchronizeEntryText)
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
                    if focusedField == .weight {
                        Button(action: openPlateCalculator) {
                            Image(systemName: "circle.grid.cross")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(
                            IronKeyboardAccessoryButtonStyle(
                                tint: IronTheme.accent
                            )
                        )
                        .accessibilityLabel("Plate calculator")
                        .accessibilityHint("Calculates the plates to load for this set")
                    }

                    Spacer()

                    Button(action: { focusedField = nil }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(IronKeyboardAccessoryButtonStyle())
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

    private var setTypePopupActions: [IronPopupAction] {
        var actions = [
            IronPopupAction(
                title: "Normal Set",
                systemImage: "number",
                isSelected: set.tagValue == nil
            ) {
                set.tagValue = nil
                onChanged()
            }
        ]

        actions += WorkoutSetTag.allCases.map { tag in
            IronPopupAction(
                id: tag.rawValue,
                title: tag.title.capitalized,
                systemImage: setTypeIcon(for: tag),
                isSelected: set.tagValue == tag
            ) {
                set.tagValue = tag
                onChanged()
            }
        }
        actions.append(IronPopupAction(
            title: "Delete Set",
            systemImage: "trash",
            role: .destructive,
            action: onDelete
        ))
        return actions
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
                            : (isFocused ? IronTheme.accentSoft : IronTheme.field)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .stroke(
                                set.isCompleted
                                    ? IronTheme.success.opacity(0.58)
                                    : (isFocused ? IronTheme.accent : IronTheme.outline.opacity(0.55)),
                                lineWidth: isFocused && !set.isCompleted ? 2 : 1
                            )
                    )
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
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
    @State private var carouselSelection: Double?

    init(set: WorkoutSet, onChanged: @escaping () -> Void) {
        self.set = set
        self.onChanged = onChanged
        let initialValue = set.rpeValue ?? 7
        _selection = State(initialValue: initialValue)
        // Start unbound so the first post-layout assignment scrolls the
        // selected effort into the visual center of the carousel.
        _carouselSelection = State(initialValue: nil)
    }

    var body: some View {
        IronUtilitySheet(
            title: "Set effort",
            subtitle: "Rating of perceived exertion",
            systemImage: "gauge.with.dots.needle.50percent",
            onClose: { dismiss() }
        ) {
            VStack(spacing: 12) {
                IronCard(padding: 12) {
                    HStack(spacing: 14) {
                        VStack(spacing: 0) {
                            Text(String(format: "%g", selection))
                                .font(.system(size: 36, weight: .bold).monospacedDigit())
                                .foregroundColor(IronTheme.accent)
                            Text("RPE")
                                .font(.caption2.weight(.bold))
                                .tracking(0.7)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        .frame(width: 76)

                        Rectangle()
                            .fill(IronTheme.outline.opacity(0.5))
                            .frame(width: 1, height: 48)

                        Text(RPE.title(selection) ?? "Choose how many repetitions you had left in reserve.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }

                rpeCarousel

                HStack(spacing: 10) {
                    Button("Clear") {
                        set.rpeValue = nil
                        onChanged()
                        dismiss()
                    }
                    .buttonStyle(IronSecondaryButtonStyle())

                    Button("Apply RPE") {
                        set.rpeValue = selection
                        onChanged()
                        dismiss()
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.bottom, 18)
        }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(IronTheme.modalSurface)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var rpeCarousel: some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(IronTheme.accent.opacity(0.08))
                        .frame(width: 70, height: 76)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(Array(RPE.allowedValues), id: \.self) { value in
                                Button(action: {
                                    withAnimation(.snappy) {
                                        carouselSelection = value
                                        selection = value
                                    }
                                }) {
                                    VStack(spacing: 5) {
                                        Text(String(format: "%g", value))
                                            .font(.system(
                                                size: selection == value ? 24 : 17,
                                                weight: selection == value ? .bold : .semibold
                                            ).monospacedDigit())
                                        Text("RPE")
                                            .font(.system(size: 9, weight: .semibold))
                                            .opacity(selection == value ? 1 : 0)
                                    }
                                    .foregroundColor(selection == value ? IronTheme.onAccent : IronTheme.secondaryText)
                                    .frame(width: 62, height: selection == value ? 70 : 58)
                                    .background(
                                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                            .fill(selection == value ? IronTheme.accent : IronTheme.surface)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(value)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .opacity(phase.isIdentity ? 1 : 0.58)
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(
                        .horizontal,
                        max((geometry.size.width - 62) / 2, 0),
                        for: .scrollContent
                    )
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $carouselSelection, anchor: .center)
                    .onChange(of: carouselSelection) { _, value in
                        guard let value = value else { return }
                        selection = value
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            carouselSelection = selection
                        }
                    }
                }

                HStack {
                    Text("5 · Easy")
                    Spacer()
                    Text("Swipe to select")
                    Spacer()
                    Text("10 · Max")
                }
                .font(.caption2)
                .foregroundColor(IronTheme.tertiaryText)
            }
        }
        .frame(height: 96)
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
