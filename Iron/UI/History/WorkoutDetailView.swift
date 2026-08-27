//
//  WorkoutDetailView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 22.06.19.
//  Rebuilt as Iron's editable workout summary.
//

import SwiftUI
import AVKit
import UIKit
import WorkoutDataKit

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var sceneState: SceneState

    @ObservedObject var workout: Workout

    @State private var showingExerciseSelectorSheet = false
    @State private var activityItems: [Any]?
    @State private var workoutToDelete: Workout?
    @State private var workoutExerciseToDelete: WorkoutExercise?
    @State private var showingRepeatBlocked = false
    @State private var showingDetailsEditor = false
    @State private var showingMediaPreview = false
    @State private var healthSyncState = WorkoutHealthSyncState.idle
    @State private var showingShareUnavailable = false

    private var workoutExercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    private var popupActions: [IronPopupAction] {
        [
            IronPopupAction(title: "Edit Workout", systemImage: "pencil") {
                showingDetailsEditor = true
            },
            IronPopupAction(title: "Share", systemImage: "square.and.arrow.up") {
                guard let logText = workout.logText(
                    in: exerciseStore.exercises,
                    weightUnit: settingsStore.weightUnit
                ) else {
                    showingShareUnavailable = true
                    return
                }
                activityItems = [logText]
            },
            IronPopupAction(title: "Repeat", systemImage: "arrow.clockwise") {
                repeatWorkout(blank: false)
            },
            IronPopupAction(title: "Repeat with Blank Sets", systemImage: "doc") {
                repeatWorkout(blank: true)
            },
            IronPopupAction(title: "Delete Workout", systemImage: "trash", role: .destructive) {
                workoutToDelete = workout
            }
        ]
    }

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    summaryCard
                        .padding(.bottom, 10)

                    completionContextCard

                    IronHairline(opacity: 0.5)
                        .padding(.horizontal, IronTheme.horizontalPadding)

                    detailsCard

                    IronHairline(opacity: 0.5)
                        .padding(.horizontal, IronTheme.horizontalPadding)

                    timingCard

                    IronSectionTitle(title: "Exercises", detail: "\(workoutExercises.count) total")
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    if workoutExercises.isEmpty {
                        emptyExercisesCard
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                                exerciseCard(workoutExercise, index: index)

                                if index < workoutExercises.count - 1 {
                                    IronHairline(opacity: 0.5)
                                        .padding(.horizontal, IronTheme.horizontalPadding)
                                }
                            }
                        }
                    }

                    Button(action: { showingExerciseSelectorSheet = true }) {
                        Label("Add Exercises", systemImage: "plus")
                    }
                    .buttonStyle(IronSecondaryButtonStyle())
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 12)
                }
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .navigationTitle(workout.displayTitle(in: exerciseStore.exercises))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IronPopupMenu(title: "Workout actions", actions: popupActions) {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExerciseSelectorSheet) {
            AddExercisesSheet(
                exercises: exerciseStore.shownExercises,
                recentExercises: AddExercisesSheet.loadRecentExercises(
                    context: managedObjectContext,
                    exercises: exerciseStore.shownExercises
                ),
                usesModalSurface: true,
                onAdd: addExercises
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(IronTheme.modalSurface)
        }
        .sheet(isPresented: $showingDetailsEditor) {
            CompletedWorkoutDetailsEditor(
                title: workout.displayTitle(in: exerciseStore.exercises),
                comment: workout.comment ?? "",
                effort: workout.sessionEffortValue,
                start: workout.safeStart,
                end: workout.safeEnd,
                onCancel: { showingDetailsEditor = false },
                onSave: { title, comment, effort, start, end in
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    workout.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                    workout.comment = trimmedComment.isEmpty ? nil : trimmedComment
                    workout.sessionEffortValue = effort
                    workout.safeStart = start
                    workout.safeEnd = end
                    save()
                    showingDetailsEditor = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(IronTheme.modalSurface)
        }
        .fullScreenCover(isPresented: $showingMediaPreview) {
            workoutMediaPreview
        }
        .confirmationDialog(
            "Remove exercise?",
            isPresented: Binding(
                get: { workoutExerciseToDelete != nil },
                set: { if !$0 { workoutExerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                guard let workoutExercise = workoutExerciseToDelete else { return }
                workoutExerciseToDelete = nil
                delete(workoutExercise)
            }
            Button("Cancel", role: .cancel) {
                workoutExerciseToDelete = nil
            }
        } message: {
            Text("The exercise and every logged set beneath it will be removed from this workout.")
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
                dismiss()
                workout.deleteOrCrash()
            }
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
        } message: {
            Text("This removes the workout, every logged set, and Iron's matching Apple Health workout.")
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
        .onDisappear(perform: save)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(IronTheme.onAccent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(IronTheme.success))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.displayTitle(in: exerciseStore.exercises))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(2)

                    Text(workout.safeStart.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text("Completed")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.success)
            }

            IronHairline(opacity: 0.48)

            HStack(spacing: 0) {
                summaryMetric(
                    value: Workout.durationFormatter.string(from: workout.safeDuration) ?? "—",
                    label: "Duration"
                )
                summaryDivider
                summaryMetric(
                    value: WeightUnit.format(
                        weight: workout.totalCompletedWeight ?? 0,
                        from: .metric,
                        to: settingsStore.weightUnit
                    ),
                    label: "Volume"
                )
                summaryDivider
                summaryMetric(value: "\(workout.numberOfCompletedSets ?? 0)", label: "Sets")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundColor(IronTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(IronTheme.outline)
            .frame(width: 1, height: 34)
    }

    private var completionContextCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            IronSectionTitle(title: "Session")
                .padding(.bottom, 6)

            contextRow(
                title: "Session effort",
                subtitle: workout.sessionEffortValue.map { "\(Int($0))/10 · \(effortLabel(for: $0))" } ?? "Not rated yet",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: IronTheme.accent,
                trailingTitle: "Edit",
                action: { showingDetailsEditor = true }
            )

            contextDivider

            contextRow(
                title: "Saved workout",
                subtitle: workout.workoutRoutine?.displayTitle ?? "One-off workout",
                systemImage: "list.bullet.rectangle.portrait",
                tint: IronTheme.accent
            )

            contextDivider

            contextRow(
                title: "Visibility",
                subtitle: "Private · Only you",
                systemImage: "lock.fill",
                tint: IronTheme.accent
            )

            contextDivider

            contextRow(
                title: "Apple Health",
                subtitle: healthSyncState.subtitle,
                systemImage: "heart.fill",
                tint: healthSyncTint,
                trailingTitle: healthSyncState.actionTitle,
                showsProgress: healthSyncState == .syncing,
                action: healthSyncState == .syncing ? nil : syncWorkoutToHealth
            )

            contextDivider

            contextRow(
                title: "Workout media",
                subtitle: workoutMediaURL == nil ? "No photo or video attached" : "Saved privately on this device",
                systemImage: workoutMediaURL == nil ? "photo" : "photo.fill",
                tint: IronTheme.accent,
                trailingTitle: workoutMediaURL == nil ? nil : "View",
                action: workoutMediaURL == nil ? nil : { showingMediaPreview = true }
            )
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 16)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IronSectionTitle(title: "Workout details")
                Spacer()
                Button(action: { showingDetailsEditor = true }) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(IronCompactPillButtonStyle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TITLE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(IronTheme.tertiaryText)
                Text(workout.displayTitle(in: exerciseStore.exercises))
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
            }

            IronHairline()

            VStack(alignment: .leading, spacing: 4) {
                Text("NOTES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(IronTheme.tertiaryText)
                Text((workout.comment?.isEmpty == false ? workout.comment : nil) ?? "No notes for this workout")
                    .font(.body)
                    .foregroundColor(workout.comment?.isEmpty == false ? IronTheme.primaryText : IronTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 20)
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IronSectionTitle(title: "Timing")
                Spacer()
                Text(Workout.durationFormatter.string(from: workout.safeDuration) ?? "—")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.accent)
            }

            IronDateTimeButton(
                title: "Started",
                systemImage: "play.fill",
                date: workout.safeStart,
                action: { showingDetailsEditor = true }
            )

            IronHairline()

            IronDateTimeButton(
                title: "Finished",
                systemImage: "stop.fill",
                date: workout.safeEnd,
                action: { showingDetailsEditor = true }
            )
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func contextRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        trailingTitle: String? = nil,
        showsProgress: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                contextRowContent(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: tint,
                    trailingTitle: trailingTitle,
                    showsProgress: showsProgress,
                    isActionable: true
                )
            }
            .buttonStyle(.plain)
        } else {
            contextRowContent(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint,
                trailingTitle: trailingTitle,
                showsProgress: showsProgress,
                isActionable: false
            )
        }
    }

    private func contextRowContent(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        trailingTitle: String?,
        showsProgress: Bool,
        isActionable: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if showsProgress {
                ProgressView()
                    .tint(IronTheme.accent)
            } else if let trailingTitle {
                HStack(spacing: 5) {
                    Text(trailingTitle)
                        .font(.caption.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(IronTheme.accent)
            } else if isActionable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.tertiaryText)
            }
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private var contextDivider: some View {
        IronHairline()
            .padding(.leading, 48)
    }

    private var healthSyncTint: Color {
        switch healthSyncState {
        case .idle, .syncing:
            return IronTheme.accent
        case .synced:
            return IronTheme.success
        case .failed:
            return IronTheme.danger
        }
    }

    private var workoutMediaURL: URL? {
        guard let workoutUUID = workout.uuid else { return nil }
        return FinishWorkoutMediaStore.existingURL(for: workoutUUID)
    }

    private var workoutMediaIsVideo: Bool {
        guard let url = workoutMediaURL else { return false }
        return Set(["mov", "mp4", "m4v", "avi", "hevc"]).contains(url.pathExtension.lowercased())
    }

    private var workoutMediaPreview: some View {
        ZStack {
            IronTheme.mediaBackdrop.ignoresSafeArea()

            if workoutMediaIsVideo, let url = workoutMediaURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea(edges: .horizontal)
            } else if let url = workoutMediaURL,
                      let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(edges: .horizontal)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { showingMediaPreview = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(IronTheme.onMedia)
                            .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                            .background(Circle().fill(IronTheme.mediaControlSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close media")
                }
                .padding()
                Spacer()
            }
        }
    }

    private func effortLabel(for value: Double) -> String {
        switch value {
        case 1...2: return "Very light"
        case 3...4: return "Comfortable"
        case 5...6: return "Solid effort"
        case 7...8: return "Hard work"
        case 9: return "Near limit"
        default: return "All-out"
        }
    }

    private func syncWorkoutToHealth() {
        healthSyncState = .syncing
        HealthManager.shared.syncWorkoutIfNeeded(
            workout: workout,
            exerciseStore: exerciseStore
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    healthSyncState = .synced
                case .failure:
                    healthSyncState = .failed
                }
            }
        }
    }

    private var emptyExercisesCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("No exercises in this workout")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Add an exercise to record or correct this session.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func exerciseCard(_ workoutExercise: WorkoutExercise, index: Int) -> some View {
        let exercise = workoutExercise.exercise(in: exerciseStore.exercises)
        let sets = workoutSets(for: workoutExercise)

        return HStack(alignment: .top, spacing: 0) {
            NavigationLink(
                destination: WorkoutExerciseDetailView(workoutExercise: workoutExercise)
                    .environmentObject(settingsStore)
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 12) {
                        if let exercise {
                            ExerciseDiagramThumbnail(exercise: exercise, size: 48)
                        } else {
                            Circle()
                                .fill(IronTheme.raisedSurface)
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: "dumbbell").foregroundColor(IronTheme.accent))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise?.title ?? "Unknown exercise")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(IronTheme.accent)
                                .lineLimit(2)
                            Text("\(sets.count) sets")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }

                        Spacer(minLength: 8)
                    }

                    if let comment = workoutExercise.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.subheadline)
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(2)
                    }

                    if !sets.isEmpty {
                        HStack(spacing: 10) {
                            Text("SET")
                                .frame(width: 36, alignment: .center)
                            Text("RESULT")
                            Spacer()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(IronTheme.tertiaryText)

                        VStack(spacing: 0) {
                            ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, set in
                                if setIndex > 0 {
                                    IronHairline(opacity: 0.42)
                                        .padding(.leading, 46)
                                }

                            HStack {
                                Text(set.tagValue?.title.first.map(String.init) ?? "\(setIndex + 1)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundColor(set.tagValue?.color ?? IronTheme.secondaryText)
                                    .frame(width: 36, height: 34)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(IronTheme.raisedSurface)
                                    )
                                Text(set.logTitle(weightUnit: settingsStore.weightUnit))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(IronTheme.primaryText)
                                Spacer()
                                if set.isPersonalRecord ?? false {
                                    Image(systemName: "medal.fill")
                                        .font(.caption)
                                        .foregroundColor(IronTheme.success)
                                }
                            }
                            .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            IronPopupMenu(
                title: "Exercise actions",
                actions: exerciseActions(for: workoutExercise, index: index),
                arrowEdge: .bottom
            ) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(IronTheme.primaryText)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                    .background(Circle().fill(IronTheme.raisedSurface))
            }
            .padding(.top, 8)
            .padding(.leading, 4)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func exerciseActions(for workoutExercise: WorkoutExercise, index: Int) -> [IronPopupAction] {
        var actions: [IronPopupAction] = []
        if index > 0 {
            actions.append(IronPopupAction(title: "Move Earlier", systemImage: "arrow.up") {
                moveExercise(from: index, to: index - 1)
            })
        }
        if index < workoutExercises.count - 1 {
            actions.append(IronPopupAction(title: "Move Later", systemImage: "arrow.down") {
                moveExercise(from: index, to: index + 1)
            })
        }
        actions.append(
            IronPopupAction(title: "Remove Exercise", systemImage: "trash", role: .destructive) {
                workoutExerciseToDelete = workoutExercise
            }
        )
        return actions
    }

    private func workoutSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func addExercises(_ selection: [Exercise]) {
        for exercise in selection {
            let workoutExercise = WorkoutExercise.create(context: managedObjectContext)
            workout.addToWorkoutExercises(workoutExercise)
            workoutExercise.exerciseUuid = exercise.uuid
        }
        save()
    }

    private func delete(_ workoutExercise: WorkoutExercise) {
        workout.removeFromWorkoutExercises(workoutExercise)
        managedObjectContext.delete(workoutExercise)
        save()
    }

    private func moveExercise(from source: Int, to destination: Int) {
        guard source != destination, workoutExercises.indices.contains(source), workoutExercises.indices.contains(destination) else { return }
        var reordered = workoutExercises
        let item = reordered.remove(at: source)
        reordered.insert(item, at: destination)
        workout.workoutExercises = NSOrderedSet(array: reordered)
        save()
    }

    private func save() {
        managedObjectContext.saveOrCrash()
    }

    private func repeatWorkout(blank: Bool) {
        let didStart: Bool
        if blank {
            didStart = Self.repeatWorkoutBlank(
                workout: workout,
                settingsStore: settingsStore,
                sceneState: sceneState
            )
        } else {
            didStart = Self.repeatWorkout(
                workout: workout,
                settingsStore: settingsStore,
                sceneState: sceneState
            )
        }

        if !didStart {
            showingRepeatBlocked = true
        }
    }
}

private enum WorkoutHealthSyncState: Equatable {
    case idle
    case syncing
    case synced
    case failed

    var subtitle: String {
        switch self {
        case .idle: return "Check and sync this workout"
        case .syncing: return "Checking Apple Health…"
        case .synced: return "Synced with Apple Health"
        case .failed: return "Could not sync · try again"
        }
    }

    var actionTitle: String? {
        switch self {
        case .idle: return "Sync"
        case .failed: return "Retry"
        case .syncing, .synced: return nil
        }
    }
}

private struct CompletedWorkoutDetailsEditor: View {
    private enum DateEditor: String, Identifiable {
        case started
        case finished

        var id: String { rawValue }
    }

    @State private var title: String
    @State private var comment: String
    @State private var effort: Double?
    @State private var start: Date
    @State private var end: Date
    @State private var dateEditor: DateEditor?

    let onCancel: () -> Void
    let onSave: (String, String, Double?, Date, Date) -> Void

    init(
        title: String,
        comment: String,
        effort: Double?,
        start: Date,
        end: Date,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, Double?, Date, Date) -> Void
    ) {
        _title = State(initialValue: title)
        _comment = State(initialValue: comment)
        _effort = State(initialValue: effort)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IronModalBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        identitySection

                        IronHairline(opacity: 0.5)
                            .padding(.horizontal, IronTheme.horizontalPadding)

                        effortSection

                        IronHairline(opacity: 0.5)
                            .padding(.horizontal, IronTheme.horizontalPadding)

                        timingSection
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") { onSave(title, comment, effort, start, end) }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $dateEditor) { editor in
            IronDateTimePickerSheet(
                title: editor == .started ? "Workout started" : "Workout finished",
                subtitle: editor == .started
                    ? "Choose when this session began."
                    : "Choose when this session ended.",
                initialDate: editor == .started ? start : end,
                range: editor == .started
                    ? Date.distantPast...min(end, Date())
                    : min(start, Date())...Date()
            ) { newDate in
                if editor == .started {
                    start = newDate
                } else {
                    end = newDate
                }
            }
        }
        .ironScreen()
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorSectionHeader(
                "Workout details",
                subtitle: "Keep the name and notes useful for future you."
            )

            TextField("Workout title", text: $title)
                .font(.body.weight(.semibold))
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .frame(minHeight: IronTheme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .stroke(IronTheme.outline.opacity(0.45), lineWidth: 1)
                )

            ZStack(alignment: .topLeading) {
                if comment.isEmpty {
                    Text("What went well? Add context for your future self…")
                        .font(.body)
                        .foregroundColor(IronTheme.tertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $comment)
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                    .frame(minHeight: 128)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .stroke(IronTheme.outline.opacity(0.45), lineWidth: 1)
            )
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 20)
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                editorSectionHeader(
                    "Session effort",
                    subtitle: effort.map { effortLabel(for: $0) } ?? "Optional"
                )
                Spacer()
                Text(effort.map { "\(Int($0))/10" } ?? "—")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundColor(effort == nil ? IronTheme.tertiaryText : IronTheme.accent)
            }

            IronEffortCarousel(selection: $effort)

            if effort != nil {
                Button("Clear effort rating") { effort = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 20)
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            editorSectionHeader(
                "Timing",
                subtitle: "Duration \(Workout.durationFormatter.string(from: end.timeIntervalSince(start)) ?? "—")"
            )

            IronDateTimeButton(
                title: "Started",
                systemImage: "play.fill",
                date: start,
                action: { dateEditor = .started }
            )

            IronDateTimeButton(
                title: "Finished",
                systemImage: "stop.fill",
                date: end,
                action: { dateEditor = .finished }
            )
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 20)
    }

    private func editorSectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(IronTheme.secondaryText)
        }
    }

    private func effortLabel(for value: Double) -> String {
        switch value {
        case 1...2: return "Very light — plenty left in the tank"
        case 3...4: return "Light and comfortable"
        case 5...6: return "Solid training effort"
        case 7...8: return "Hard, productive work"
        case 9: return "Near your limit"
        default: return "All-out effort"
        }
    }
}

// MARK: Actions
extension WorkoutDetailView {
    @discardableResult
    static func repeatWorkout(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) -> Bool {
        guard let context = workout.managedObjectContext else { return false }
        guard let count = try? context.count(for: Workout.currentWorkoutFetchRequest), count == 0 else {
            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.prepare()
            feedbackGenerator.notificationOccurred(.error)
            return false
        }
        guard let newWorkout = workout.copyForRepeat(blank: false) else { return false }

        newWorkout.startOrCrash()
        sceneState.selectedTab = .workout
        sceneState.isCurrentWorkoutExpanded = true
        return true
    }

    @discardableResult
    static func repeatWorkoutBlank(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) -> Bool {
        guard let context = workout.managedObjectContext else { return false }
        guard let count = try? context.count(for: Workout.currentWorkoutFetchRequest), count == 0 else {
            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.prepare()
            feedbackGenerator.notificationOccurred(.error)
            return false
        }
        guard let newWorkout = workout.copyForRepeat(blank: true) else { return false }

        newWorkout.startOrCrash()
        sceneState.selectedTab = .workout
        sceneState.isCurrentWorkoutExpanded = true
        return true
    }
}

#if DEBUG
struct WorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutDetailView(workout: MockWorkoutData.metricRandom.workout)
                .mockEnvironment(weightUnit: .metric)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
