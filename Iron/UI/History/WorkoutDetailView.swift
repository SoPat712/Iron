//
//  WorkoutDetailView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 22.06.19.
//  Rebuilt as Iron's editable workout summary.
//

import SwiftUI
import AVKit
import CoreData
import UIKit
import WorkoutDataKit

enum HistoryMutationPersistence {
    static func perform(
        context: NSManagedObjectContext,
        save: (() throws -> Void)? = nil,
        mutation: () throws -> Void,
        onSuccess: () -> Void = {}
    ) throws {
        try context.persistMutation(
            save: {
                if let save { try save() }
                else { try context.save() }
            },
            mutation: mutation
        )
        onSuccess()
    }
}

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
    @State private var persistenceError: String?

    private var workoutExercises: [WorkoutExercise] {
        workout.workoutExercises?.array as? [WorkoutExercise] ?? []
    }

    var body: some View {
        List {
            summarySection
            sessionSection
            detailsSection
            exercisesSection
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, IronTheme.floatingWorkoutBottomClearance, for: .scrollContent)
        .navigationTitle(workout.displayTitle(in: exerciseStore.exercises))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Workout", systemImage: "pencil") { showingDetailsEditor = true }
                    Button("Share", systemImage: "square.and.arrow.up", action: shareWorkout)
                    Divider()
                    Button("Repeat", systemImage: "arrow.clockwise") { repeatWorkout(blank: false) }
                    Button("Repeat with Blank Sets", systemImage: "doc") { repeatWorkout(blank: true) }
                    Divider()
                    Button("Delete Workout", systemImage: "trash", role: .destructive) { workoutToDelete = workout }
                } label: {
                    Label("Workout Actions", systemImage: "ellipsis.circle")
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
                shouldDismiss: { persistenceError == nil },
                onAdd: addExercises
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .alert("Workout Not Saved", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
        }
        .sheet(isPresented: $showingDetailsEditor) {
            CompletedWorkoutDetailsEditor(
                title: workout.displayTitle(in: exerciseStore.exercises),
                comment: workout.comment ?? "",
                effort: workout.sessionEffortValue,
                start: workout.safeStart,
                end: workout.safeEnd,
                persistenceError: $persistenceError,
                onCancel: { showingDetailsEditor = false },
                onSave: { title, comment, effort, start, end in
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    performMutation(
                        failureMessage: "The workout details were not updated."
                    ) {
                        workout.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                        workout.comment = trimmedComment.isEmpty ? nil : trimmedComment
                        workout.sessionEffortValue = effort
                        workout.safeStart = start
                        workout.safeEnd = end
                    } onSuccess: {
                        showingDetailsEditor = false
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingMediaPreview) {
            workoutMediaPreview
        }
        .alert("Workout Not Saved", isPresented: Binding(
            get: {
                persistenceError != nil
                    && !showingExerciseSelectorSheet
                    && !showingDetailsEditor
            },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
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
                do {
                    try workout.delete()
                    dismiss()
                } catch {
                    persistenceError = "The workout was not deleted. \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
        } message: {
            Text(workout.healthExportEligibility != .eligible
                ? "This removes the workout and every logged set from Iron."
                : "This removes the workout, every logged set, and Iron's matching Apple Health workout.")
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
        .onDisappear { _ = save() }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(Workout.durationFormatter.string(from: workout.safeDuration) ?? "—")
                    .font(.ironMetric(.body))
            } label: {
                Text("Duration")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(IronTheme.metricTime)
            .ironStaggeredEntrance(index: 0)

            LabeledContent {
                let volume = WeightUnit.convert(
                    weight: workout.totalCompletedWeight ?? 0,
                    from: .metric, to: settingsStore.weightUnit
                )
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(settingsStore.weightUnit.displayNumberFormatter.string(from: volume as NSNumber) ?? "—")
                        .font(.ironMetric(.body))
                    Text(settingsStore.weightUnit.unit.symbol)
                        .font(.caption)
                        .foregroundStyle(IronTheme.secondaryText)
                }
            } label: {
                Text("Volume")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(IronTheme.metricVolume)
            .ironStaggeredEntrance(index: 1)

            LabeledContent {
                Text("\(workout.numberOfCompletedSets ?? 0)")
                    .font(.ironMetric(.body))
            } label: {
                Text("Sets")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(IronTheme.metricSets)
            .ironStaggeredEntrance(index: 2)
        } header: {
            Text("Summary")
        } footer: {
            Text(workout.safeStart.formatted(date: .complete, time: .shortened))
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section("Session") {
            Button {
                showingDetailsEditor = true
            } label: {
                LabeledContent {
                    if let effort = workout.sessionEffortValue, effort > 0 {
                        (Text("\(Int(effort))/10").font(.ironMetric(.body))
                         + Text(" · \(effortLabel(for: effort))"))
                            .foregroundStyle(IronTheme.metricEffort)
                    } else {
                        Text("Not Rated").foregroundStyle(IronTheme.secondaryText)
                    }
                } label: {
                    Text("Effort")
                        .fontWeight(.semibold)
                        .foregroundStyle(IronTheme.metricEffort)
                }
            }

            LabeledContent("Saved Workout", value: workout.workoutRoutine?.displayTitle ?? "One-Off Workout")

            appleHealthRow

            if workoutMediaURL != nil {
                Button("View Workout Media", systemImage: "photo") {
                    showingMediaPreview = true
                }
            }
        }
    }

    @ViewBuilder
    private var appleHealthRow: some View {
        if let source = workout.importSource {
            let origin = source == "hevy" ? "Imported from Hevy" : (source == "sample" ? "Sample data" : "Imported workout")
            Text(source == "sample" ? "Sample data · Not sent" : "\(origin) · Not sent to Apple Health")
                .foregroundStyle(.secondary)
        } else if workout.healthExportState == "exported" || workout.healthExportState == "watch" {
            Label("Saved to Apple Health", systemImage: "checkmark.circle")
        } else if workout.healthExportEligibility == .eligible {
            if workout.healthExportState == "pending" {
                HStack {
                    Text("Waiting to save to Apple Health")
                    Spacer()
                    if healthSyncState == .syncing {
                        ProgressView()
                    } else {
                        Button("Retry", action: syncWorkoutToHealth)
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            } else {
                Button(action: syncWorkoutToHealth) {
                    HStack {
                        Text("Save to Apple Health")
                        if healthSyncState == .syncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(healthSyncState == .syncing)
            }
            if healthSyncState == .failed {
                Text("Could not save. Try again when Apple Health is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Not sent to Apple Health").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            LabeledContent("Title", value: workout.displayTitle(in: exerciseStore.exercises))

            if let comment = workout.comment, !comment.isEmpty {
                Text(comment)
                    .foregroundStyle(.secondary)
            }

            DatePicker("Started", selection: .constant(workout.safeStart), displayedComponents: [.date, .hourAndMinute])
                .disabled(true)
            DatePicker("Finished", selection: .constant(workout.safeEnd), displayedComponents: [.date, .hourAndMinute])
                .disabled(true)

            Button("Edit Workout Details", systemImage: "pencil") {
                showingDetailsEditor = true
            }
        } header: {
            Text("Details")
        } footer: {
            if workout.comment?.isEmpty != false {
                Text("No notes for this workout.")
            }
        }
    }

    @ViewBuilder
    private var exercisesSection: some View {
        Section {
            if workoutExercises.isEmpty {
                ContentUnavailableView(
                    "No Exercises",
                    systemImage: "dumbbell",
                    description: Text("Add an exercise to record or correct this session.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    exerciseRow(workoutExercise, index: index)
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    moveExercise(from: from, to: destination > from ? destination - 1 : destination)
                }
            }

            Button("Add Exercises", systemImage: "plus") {
                showingExerciseSelectorSheet = true
            }
        } header: {
            Text("Exercises")
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
                    Button("Close", systemImage: "xmark") { showingMediaPreview = false }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(.white)
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
        guard workout.healthExportEligibility == .eligible else { return }
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

    private func exerciseRow(_ workoutExercise: WorkoutExercise, index: Int) -> some View {
        let exercise = workoutExercise.exercise(in: exerciseStore.exercises)
        let sets = workoutSets(for: workoutExercise)
        let setSummary = sets
            .map { $0.logTitle(weightUnit: settingsStore.weightUnit) }
            .joined(separator: ", ")

        return NavigationLink {
            WorkoutExerciseDetailView(workoutExercise: workoutExercise)
                .environmentObject(settingsStore)
        } label: {
            HStack(spacing: 12) {
                if let exercise {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exercise?.title ?? "Unknown Exercise")
                            .lineLimit(2)
                        if sets.contains(where: { $0.isPersonalRecord ?? false }) {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(IronTheme.metricRecord)
                                .accessibilityLabel("Personal record")
                        }
                    }

                    Text(sets.isEmpty ? "No sets" : setSummary)
                        .font(.ironMetric(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let comment = workoutExercise.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                workoutExerciseToDelete = workoutExercise
            }
        }
        .contextMenu {
            if index > 0 {
                Button("Move Earlier", systemImage: "arrow.up") { moveExercise(from: index, to: index - 1) }
            }
            if index < workoutExercises.count - 1 {
                Button("Move Later", systemImage: "arrow.down") { moveExercise(from: index, to: index + 1) }
            }
            Divider()
            Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                workoutExerciseToDelete = workoutExercise
            }
        }
    }

    private func workoutSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func addExercises(_ selection: [Exercise]) {
        performMutation(failureMessage: "The exercises were not added.") {
            for exercise in selection {
                let workoutExercise = WorkoutExercise.create(context: managedObjectContext)
                workout.addToWorkoutExercises(workoutExercise)
                workoutExercise.exerciseUuid = exercise.uuid
            }
        }
    }

    private func delete(_ workoutExercise: WorkoutExercise) {
        performMutation(failureMessage: "The exercise was not removed.") {
            workout.removeFromWorkoutExercises(workoutExercise)
            managedObjectContext.delete(workoutExercise)
        }
    }

    private func moveExercise(from source: Int, to destination: Int) {
        guard source != destination, workoutExercises.indices.contains(source), workoutExercises.indices.contains(destination) else { return }
        performMutation(failureMessage: "The exercises were not reordered.") {
            var reordered = workoutExercises
            let item = reordered.remove(at: source)
            reordered.insert(item, at: destination)
            workout.workoutExercises = NSOrderedSet(array: reordered)
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try managedObjectContext.save()
            return true
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    private func performMutation(
        failureMessage: String,
        mutation: () throws -> Void,
        onSuccess: () -> Void = {}
    ) {
        persistenceError = nil
        do {
            try HistoryMutationPersistence.perform(
                context: managedObjectContext,
                mutation: mutation,
                onSuccess: onSuccess
            )
        } catch {
            persistenceError = "\(failureMessage) \(error.localizedDescription)"
        }
    }

    private func shareWorkout() {
        guard let logText = workout.logText(
            in: exerciseStore.exercises,
            weightUnit: settingsStore.weightUnit
        ) else {
            showingShareUnavailable = true
            return
        }
        activityItems = [logText]
    }

    private func repeatWorkout(blank: Bool) {
        do {
            let didStart: Bool
            if blank {
                didStart = try Self.repeatWorkoutBlank(
                    workout: workout,
                    settingsStore: settingsStore,
                    sceneState: sceneState
                )
            } else {
                didStart = try Self.repeatWorkout(
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

private enum WorkoutHealthSyncState: Equatable {
    case idle
    case syncing
    case synced
    case failed
}

private struct CompletedWorkoutDetailsEditor: View {
    @State private var title: String
    @State private var comment: String
    @State private var effort: Double?
    @State private var start: Date
    @State private var end: Date
    @Binding private var persistenceError: String?

    let onCancel: () -> Void
    let onSave: (String, String, Double?, Date, Date) -> Void

    init(
        title: String,
        comment: String,
        effort: Double?,
        start: Date,
        end: Date,
        persistenceError: Binding<String?>,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, Double?, Date, Date) -> Void
    ) {
        _title = State(initialValue: title)
        _comment = State(initialValue: comment)
        _effort = State(initialValue: effort)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _persistenceError = persistenceError
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Workout Details")
                } footer: {
                    Text("Keep the name and notes useful for future you.")
                }

                Section {
                    EffortRatingGraph(
                        rating: Binding(
                            get: { effort.map { Int($0.rounded()) } ?? 0 },
                            set: { effort = $0 == 0 ? nil : Double($0) }
                        ),
                        allowsUnrated: true
                    )
                    .padding(.vertical, 4)
                } header: {
                    Text("Session Effort")
                } footer: {
                    if let effort {
                        Text(effortLabel(for: effort))
                    } else {
                        Text("Leave unrated, or drag across the graph.")
                    }
                }

                Section {
                    DatePicker(
                        "Started",
                        selection: $start,
                        in: Date.distantPast...min(end, Date()),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Finished",
                        selection: $end,
                        in: min(start, Date())...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Duration \(Workout.durationFormatter.string(from: end.timeIntervalSince(start)) ?? "—")")
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
            .alert("Workout Not Saved", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
        }
    }

    private func effortLabel(for value: Double) -> String {
        switch value {
        case 1...2: return "Very Light"
        case 3...4: return "Light"
        case 5...6: return "Solid"
        case 7...8: return "Hard"
        case 9: return "Near Limit"
        default: return "All-Out"
        }
    }
}

// MARK: Actions
extension WorkoutDetailView {
    @discardableResult
    static func repeatWorkout(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) throws -> Bool {
        do {
            _ = try Workout.startRepeating(workout, blank: false)
        } catch Workout.StartError.workoutAlreadyActive {
            return false
        }
        sceneState.selectedTab = .workout
        sceneState.isCurrentWorkoutExpanded = true
        return true
    }

    @discardableResult
    static func repeatWorkoutBlank(workout: Workout, settingsStore: SettingsStore, sceneState: SceneState) throws -> Bool {
        do {
            _ = try Workout.startRepeating(workout, blank: true)
        } catch Workout.StartError.workoutAlreadyActive {
            return false
        }
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
