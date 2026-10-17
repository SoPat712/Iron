//
//  StartWorkoutView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 19.07.19.
//  Rebuilt for Iron's focused workout experience.
//

import SwiftUI
import Charts
import CoreData
import WorkoutDataKit

struct WorkoutPlanEditorRoute: Identifiable {
    enum Kind {
        case create(containerID: NSManagedObjectID?)
        case edit(planID: NSManagedObjectID)
        case duplicate(planID: NSManagedObjectID)
    }

    let id = UUID()
    let kind: Kind
}

/// Portable, versioned representation for one saved workout. The wrapper keeps
/// shared files self-describing without coupling the import contract to the
/// Core Data container used by the app.
struct SavedWorkoutDocument: Codable {
    static let currentVersion = 1

    let version: Int
    let workout: WorkoutRoutine

    init(workout: WorkoutRoutine) {
        version = Self.currentVersion
        self.workout = workout
    }
}

private struct SavedWorkoutImportResult: Identifiable {
    let id = UUID()
    let importedTitle: String?
    let error: Error?

    var alertTitle: String {
        error == nil ? "Workout imported" : "Could not import workout"
    }

    var message: String {
        if let error {
            return error.localizedDescription
        }
        return "\(importedTitle ?? "Saved workout") is now available in the Workout tab."
    }
}

/// Keeps plan edits isolated until the user explicitly taps Create or Update.
/// A child context gives Cancel real meaning without rolling back unrelated
/// workout changes in the app's shared view context.
final class WorkoutPlanEditorSession: ObservableObject {
    let context: NSManagedObjectContext
    let routine: WorkoutRoutine
    let isNew: Bool

    private let parentContext: NSManagedObjectContext
    private let route: WorkoutPlanEditorRoute

    init(parentContext: NSManagedObjectContext, route: WorkoutPlanEditorRoute) throws {
        self.parentContext = parentContext
        self.route = route

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.parent = parentContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context

        // Resolve against the parent first: a child may still see a snapshot
        // for an object that has been deleted but not yet saved by its parent.
        func load<T: NSManagedObject>(_ id: NSManagedObjectID, as type: T.Type) throws -> T {
            guard let source = try? parentContext.existingObject(with: id) as? T,
                  !source.isDeleted,
                  let draft = try? context.existingObject(with: id) as? T,
                  !draft.isDeleted else {
                throw WorkoutPlanEditorLoadError.unavailable
            }
            return draft
        }

        switch route.kind {
        case .create(let containerID):
            let container: WorkoutPlan
            if let containerID {
                container = try load(containerID, as: WorkoutPlan.self)
            } else {
                container = WorkoutPlan.create(context: context)
            }

            let routine = WorkoutRoutine.create(context: context)
            routine.workoutPlan = container
            self.routine = routine
            self.isNew = true

        case .edit(let planID):
            self.routine = try load(planID, as: WorkoutRoutine.self)
            self.isNew = false

        case .duplicate(let planID):
            let source = try load(planID, as: WorkoutRoutine.self)
            self.routine = source.duplicate(context: context)
            self.isNew = true
        }
    }

    func commit(save: (() throws -> Void)? = nil) throws {
        // Do not save the child into its parent: a failed parent save would
        // leave the child clean and unable to retry its draft. Copy the draft
        // into one reversible parent mutation instead.
        let draft = SavedWorkoutDraft(routine)
        try parentContext.persistMutation(save: { try save?() ?? parentContext.save() }) {
            let target: WorkoutRoutine
            switch route.kind {
            case .edit(let planID):
                guard let existing = try parentContext.existingObject(with: planID) as? WorkoutRoutine,
                      !existing.isDeleted else { throw SavedWorkoutDraftError.missingWorkout }
                target = existing
            case .create(let containerID):
                let container: WorkoutPlan
                if let containerID {
                    guard let existing = try parentContext.existingObject(with: containerID) as? WorkoutPlan,
                          !existing.isDeleted else { throw SavedWorkoutDraftError.missingWorkout }
                    container = existing
                } else {
                    container = WorkoutPlan.create(context: parentContext)
                }
                target = WorkoutRoutine.create(context: parentContext)
                target.workoutPlan = container
            case .duplicate(let planID):
                guard let source = try parentContext.existingObject(with: planID) as? WorkoutRoutine,
                      !source.isDeleted else { throw SavedWorkoutDraftError.missingWorkout }
                target = WorkoutRoutine.create(context: parentContext)
                target.workoutPlan = source.workoutPlan
            }
            draft.apply(to: target, in: parentContext)
        }
    }

    func cancel() {
        context.rollback()
    }
}

enum WorkoutPlanEditorLoadError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "This saved workout or folder is no longer available. Close this editor and select a workout again."
    }
}

private enum SavedWorkoutDraftError: LocalizedError {
    case missingWorkout

    var errorDescription: String? {
        "The saved workout is no longer available. Your draft is still open."
    }
}

/// Copies only the editable plan graph. Existing object identities, the folder,
/// and links from completed workouts are retained when editing a saved workout.
private struct SavedWorkoutDraft {
    private struct Record {
        let objectID: NSManagedObjectID
        let attributes: [String: Any]

        init(_ object: NSManagedObject) {
            objectID = object.objectID
            let keys = object.entity.attributesByName.filter { !$0.value.isTransient }.map(\.key)
            attributes = object.dictionaryWithValues(forKeys: keys)
        }
    }

    private struct ExerciseDraft {
        let record: Record
        let sets: [Record]
    }

    private let record: Record
    private let exercises: [ExerciseDraft]

    init(_ routine: WorkoutRoutine) {
        record = Record(routine)
        exercises = (routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []).map {
            ExerciseDraft(record: Record($0), sets: ($0.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []).map(Record.init))
        }
    }

    func apply(to routine: WorkoutRoutine, in context: NSManagedObjectContext) {
        routine.setValuesForKeys(record.attributes)
        let previousExercises = routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
        let updatedExercises = exercises.map { draft -> WorkoutRoutineExercise in
            let exercise = previousExercises.first { $0.objectID == draft.record.objectID }
                ?? WorkoutRoutineExercise.create(context: context)
            exercise.setValuesForKeys(draft.record.attributes)
            let previousSets = exercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
            let updatedSets = draft.sets.map { setDraft -> WorkoutRoutineSet in
                let set = previousSets.first { $0.objectID == setDraft.objectID }
                    ?? WorkoutRoutineSet.create(context: context)
                set.setValuesForKeys(setDraft.attributes)
                return set
            }
            exercise.workoutRoutineSets = NSOrderedSet(array: updatedSets)
            for set in previousSets where !updatedSets.contains(set) { context.delete(set) }
            return exercise
        }
        routine.workoutRoutineExercises = NSOrderedSet(array: updatedExercises)
        for exercise in previousExercises where !updatedExercises.contains(exercise) { context.delete(exercise) }
    }
}

enum SavedWorkoutImporter {
    @discardableResult
    static func importData(
        _ data: Data,
        into parentContext: NSManagedObjectContext,
        save: (() throws -> Void)? = nil
    ) throws -> String {
        let importContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        importContext.parent = parentContext
        importContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        defer { importContext.rollback() }

        let decoder = JSONDecoder()
        if let contextKey = CodingUserInfoKey.managedObjectContextKey {
            decoder.userInfo[contextKey] = importContext
        }
        let document = try decoder.decode(SavedWorkoutDocument.self, from: data)
        guard document.version == SavedWorkoutDocument.currentVersion else {
            throw SavedWorkoutImportError.unsupportedVersion(document.version)
        }

        let importedTitle = document.workout.displayTitle
        let draft = SavedWorkoutDraft(document.workout)
        try parentContext.persistMutation(
            save: {
                if let save { try save() }
                else { try parentContext.save() }
            },
            mutation: {
                let container = WorkoutPlan.create(context: parentContext)
                container.title = "Imported Workouts"
                let routine = WorkoutRoutine.create(context: parentContext)
                routine.workoutPlan = container
                draft.apply(to: routine, in: parentContext)
            }
        )
        return importedTitle
    }
}

private final class WorkoutPlanEditorPresentation: ObservableObject {
    let result: Result<WorkoutPlanEditorSession, Error>

    init(parentContext: NSManagedObjectContext, route: WorkoutPlanEditorRoute) {
        result = Result { try WorkoutPlanEditorSession(parentContext: parentContext, route: route) }
    }
}

private struct WorkoutPlanEditorHost: View {
    @StateObject private var presentation: WorkoutPlanEditorPresentation
    @State private var persistenceError: String?

    let onDismiss: () -> Void

    init(
        parentContext: NSManagedObjectContext,
        route: WorkoutPlanEditorRoute,
        onDismiss: @escaping () -> Void
    ) {
        _presentation = StateObject(
            wrappedValue: WorkoutPlanEditorPresentation(parentContext: parentContext, route: route)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            switch presentation.result {
            case .success(let session):
                editor(session)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Workout Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onDismiss)
                    }
                }
            }
        }
    }

    private func editor(_ session: WorkoutPlanEditorSession) -> some View {
        WorkoutRoutineView(
            workoutRoutine: session.routine,
            isNew: session.isNew,
            autosavesChanges: false,
            onCancel: {
                session.cancel()
                onDismiss()
            },
            onCommit: {
                do {
                    try session.commit()
                    onDismiss()
                } catch {
                    persistenceError = "Your workout could not be saved. Try again. \(error.localizedDescription)"
                }
            }
        )
        .environment(\.managedObjectContext, session.context)
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

struct StartWorkoutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @FetchRequest(fetchRequest: StartWorkoutView.fetchRequest) private var workoutPlans
    @FetchRequest(fetchRequest: Workout.currentWorkoutFetchRequest) private var currentWorkouts

    var onOpenCurrentWorkout: () -> Void = {}

    @State private var planToDelete: WorkoutRoutine?
    @State private var planEditorRoute: WorkoutPlanEditorRoute?
    @State private var activityItems: [Any]?
    @State private var isShowingWorkoutImporter = false
    @State private var importResult: SavedWorkoutImportResult?
    @State private var persistenceError: String?

    static var fetchRequest: NSFetchRequest<WorkoutPlan> {
        let request: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutPlan.title, ascending: true)]
        return request
    }

    /// `WorkoutPlan` is retained as a persistence container for backwards
    /// compatibility. The user-facing plans are its saved workout entries.
    private var plans: [WorkoutRoutine] {
        workoutPlans.flatMap { $0.workoutRoutines?.array as? [WorkoutRoutine] ?? [] }
    }

    private var activeRoutineObjectID: NSManagedObjectID? {
        currentWorkouts.first?.workoutRoutine?.objectID
    }

    var body: some View {
        NavigationStack {
            List {
                if currentWorkouts.isEmpty {
                    Section {
                        quickStartCard
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }

                Section {
                    if plans.isEmpty {
                        Button(action: newPlan) {
                            Label("Create Your First Workout", systemImage: "plus")
                        }
                    } else {
                        ForEach(plans, id: \.id) { plan in
                            SavedWorkoutRow(
                                workout: plan,
                                onEdit: {
                                    planEditorRoute = WorkoutPlanEditorRoute(
                                        kind: .edit(planID: plan.objectID)
                                    )
                                },
                                onDuplicate: { duplicate(plan) },
                                onDelete: { requestDelete(plan) },
                                onExport: { exportWorkout(plan) },
                                canStartWorkout: currentWorkouts.isEmpty,
                                isActiveWorkout: activeRoutineObjectID == plan.objectID,
                                onWorkoutStarted: onOpenCurrentWorkout,
                                onFailure: { persistenceError = $0.localizedDescription }
                            )
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                } header: {
                    Text("Saved Workouts")
                } footer: {
                    if plans.isEmpty {
                        Text("Save a workout for push/pull/legs, upper/lower, or any split you train.")
                    }
                }

                if !plans.isEmpty {
                    Section {
                        Button(action: newPlan) {
                            Label("Create Workout", systemImage: "plus")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion), value: plans.map(\.objectID))
            .contentMargins(.bottom, IronTheme.floatingWorkoutBottomClearance, for: .scrollContent)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Workout", systemImage: "plus", action: newPlan)
                        Button("Import Workout", systemImage: "square.and.arrow.down") {
                            isShowingWorkoutImporter = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create or import workout")
                }
            }
            .sheet(item: $planEditorRoute) { route in
                WorkoutPlanEditorHost(
                    parentContext: managedObjectContext,
                    route: route,
                    onDismiss: { planEditorRoute = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert(
            planToDelete.map { "Delete \($0.displayTitle)?" } ?? "Delete workout?",
            isPresented: Binding(
                get: { planToDelete != nil },
                set: { if !$0 { planToDelete = nil } }
            )
        ) {
            Button("Delete Workout", role: .destructive) {
                guard let plan = planToDelete else { return }
                planToDelete = nil
                delete(plan)
            }
            Button("Cancel", role: .cancel) {
                planToDelete = nil
            }
        } message: {
            Text("This removes the exercises, targets, and notes saved in this workout. Your completed workout history is not affected.")
        }
        .ironActivitySheet(activityItems: $activityItems)
        .fileImporter(
            isPresented: $isShowingWorkoutImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importWorkout
        )
        .alert(item: $importResult) { result in
            Alert(
                title: Text(result.alertTitle),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
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

    /// The empty-workout path deserves more than a list row: it is the entry
    /// point for anyone not training a saved routine today.
    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quick Start")
                    .font(.title2.weight(.bold))
                Spacer()
                Image(systemName: "dumbbell.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }

            Text("Start an empty log and add exercises as you train.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: startEmptyWorkout) {
                Label("Start Empty Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startEmptyWorkout() {
        do {
            _ = try Workout.startNew(in: managedObjectContext)
            onOpenCurrentWorkout()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func newPlan() {
        planEditorRoute = WorkoutPlanEditorRoute(
            kind: .create(containerID: workoutPlans.first?.objectID)
        )
    }

    private func duplicate(_ plan: WorkoutRoutine) {
        planEditorRoute = WorkoutPlanEditorRoute(
            kind: .duplicate(planID: plan.objectID)
        )
    }

    private func requestDelete(_ plan: WorkoutRoutine) {
        planToDelete = plan
    }

    private func delete(_ plan: WorkoutRoutine) {
        do {
            try managedObjectContext.persistMutation(save: { try managedObjectContext.save() }) {
                managedObjectContext.delete(plan)
            }
        } catch {
            persistenceError = "The saved workout was not deleted. \(error.localizedDescription)"
        }
    }

    private func exportWorkout(_ workout: WorkoutRoutine) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let exercisesKey = CodingUserInfoKey.exercisesKey {
                encoder.userInfo[exercisesKey] = exerciseStore.exercises
            }
            let data = try encoder.encode(SavedWorkoutDocument(workout: workout))
            let filename = sanitizedFilename(workout.displayTitle) + ".ironworkout.json"
            activityItems = [try temporaryFile(data: data, name: filename)]
        } catch {
            importResult = SavedWorkoutImportResult(importedTitle: nil, error: error)
        }
    }

    private func importWorkout(_ selection: Result<[URL], Error>) {
        if case .failure(let error) = selection,
           (error as NSError).code == NSUserCancelledError {
            return
        }

        do {
            guard let url = try selection.get().first else { return }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)

            let importedTitle = try SavedWorkoutImporter.importData(
                data,
                into: managedObjectContext
            )
            importResult = SavedWorkoutImportResult(
                importedTitle: importedTitle,
                error: nil
            )
        } catch {
            importResult = SavedWorkoutImportResult(importedTitle: nil, error: error)
        }
    }

    private func sanitizedFilename(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let sanitized = title.components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Iron Workout" : sanitized
    }

    private func temporaryFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum SavedWorkoutImportError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This Iron workout file uses version \(version), which this build cannot import yet."
        }
    }
}

private enum WorkoutPlanTrendMetric: String, CaseIterable, Identifiable {
    case volume
    case repetitions
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volume: return "Volume"
        case .repetitions: return "Reps"
        case .duration: return "Duration"
        }
    }

    var color: Color {
        switch self {
        case .volume: return IronTheme.metricVolume
        case .repetitions: return IronTheme.metricSets
        case .duration: return IronTheme.metricTime
        }
    }

    var icon: String {
        switch self {
        case .volume: return "scalemass.fill"
        case .repetitions: return "arrow.triangle.2.circlepath"
        case .duration: return "timer"
        }
    }
}

private struct WorkoutPlanTrendPoint: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let value: Double
    let duration: TimeInterval?
    let totalVolume: Double
    let completedSets: Int
    let repetitions: Int
}

private struct WorkoutPlanTrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let points: [WorkoutPlanTrendPoint]
    let valueFormatter: (Double) -> String
    let valueText: (Double) -> Text
    let metricTitle: String
    let metricColor: Color
    let volumeFormatter: (Double) -> String

    @State private var selectedPointID: WorkoutPlanTrendPoint.ID?

    private var selectedPoint: WorkoutPlanTrendPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    private func dateLabel(_ date: Date) -> String {
        Workout.dateFormatter.string(from: date)
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        return Workout.durationFormatter.string(from: duration) ?? "—"
    }

    private var accessibilityValue: String {
        guard let selectedPoint,
              let index = points.firstIndex(where: { $0.id == selectedPoint.id }) else {
            let sessionLabel = points.count == 1 ? "1 session" : String(points.count) + " sessions"
            return sessionLabel + ". Select a session to hear its details."
        }

        return dateLabel(selectedPoint.date) + ", "
            + metricTitle + " " + valueFormatter(selectedPoint.value) + "; "
            + "duration " + durationLabel(selectedPoint.duration) + ", "
            + "volume " + volumeFormatter(selectedPoint.totalVolume) + ", "
            + String(selectedPoint.completedSets) + " sets, "
            + String(selectedPoint.repetitions) + " repetitions; session "
            + String(index + 1) + " of " + String(points.count)
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }

        let currentIndex = selectedPointID.flatMap { id in
            points.firstIndex { $0.id == id }
        }
        let targetIndex: Int
        switch direction {
        case .increment:
            targetIndex = min((currentIndex ?? -1) + 1, points.count - 1)
        case .decrement:
            targetIndex = max((currentIndex ?? points.count) - 1, 0)
        @unknown default:
            return
        }

        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
            selectedPointID = points[targetIndex].id
        }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(metricTitle, hasAppeared || reduceMotion ? point.value : 0)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

            AreaMark(
                x: .value("Date", point.date),
                y: .value(metricTitle, hasAppeared || reduceMotion ? point.value : 0)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [metricColor.opacity(0.25), metricColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            PointMark(
                x: .value("Date", point.date),
                y: .value(metricTitle, hasAppeared || reduceMotion ? point.value : 0)
            )
            .symbolSize(point.id == selectedPointID ? 90 : 34)

            if let selectedPoint, selectedPoint.id == point.id {
                RuleMark(x: .value("Date", selectedPoint.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit, y: .disabled)) {
                        selectionCallout(for: selectedPoint)
                    }
            }
        }
        .foregroundStyle(metricColor)
        .chartYScale(domain: 0...max((points.map(\.value).max() ?? 0) * 1.1, 1))
        .opacity(!reduceMotion || hasAppeared ? 1 : 0)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: hasAppeared)
        .onAppear { hasAppeared = true }
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: metricTitle)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(valueFormatter(raw))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                if let date = value.as(Date.self), date == points.last?.date {
                    AxisGridLine()
                }
            }
        }
        .chartXSelection(value: Binding(
            get: { selectedPoint?.date },
            set: { newDate in
                guard let newDate else {
                    selectedPointID = nil
                    return
                }
                selectedPointID = points.min {
                    abs($0.date.timeIntervalSince(newDate)) < abs($1.date.timeIntervalSince(newDate))
                }?.id
            }
        ))
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training trend chart with \(points.count) sessions")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction(adjustSelection)
    }

    private func selectionCallout(for point: WorkoutPlanTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateLabel(point.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            valueText(point.value)
                .font(.ironMetric(.subheadline, weight: .semibold))
                .foregroundStyle(metricColor)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: point.id)
            (Text("\(point.completedSets) sets · \(point.repetitions) reps").foregroundColor(IronTheme.metricSets)
             + Text(" · ").foregroundColor(IronTheme.secondaryText)
             + Text(durationLabel(point.duration)).foregroundColor(IronTheme.metricTime))
                .font(.ironMetric(.caption2, weight: .semibold))
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct WorkoutPlanDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var plan: WorkoutRoutine
    let canStartWorkout: Bool
    let isActiveWorkout: Bool
    let onEdit: () -> Void
    let onWorkoutStarted: () -> Void
    let onFailure: (Error) -> Void

    @State private var selectedMetric: WorkoutPlanTrendMetric = .volume

    private var planExercises: [WorkoutRoutineExercise] {
        plan.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
    }

    private var completedWorkouts: [Workout] {
        (plan.workouts?.compactMap { $0 as? Workout } ?? [])
            .filter { !$0.isCurrentWorkout && ($0.hasCompletedSets ?? false) }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    private var chartWorkouts: [Workout] {
        Array(completedWorkouts.prefix(8).reversed())
    }

    private var trendPoints: [WorkoutPlanTrendPoint] {
        chartWorkouts.map { workout in
            WorkoutPlanTrendPoint(
                id: workout.objectID,
                date: workout.start ?? .distantPast,
                value: metricValue(for: workout),
                duration: workout.duration,
                totalVolume: workout.totalCompletedWeight ?? 0,
                completedSets: workout.numberOfCompletedSets ?? 0,
                repetitions: totalRepetitions(for: workout)
            )
        }
    }

    private var totalVolume: Double {
        completedWorkouts.reduce(0) { $0 + ($1.totalCompletedWeight ?? 0) }
    }

    private var latestWorkout: Workout? { completedWorkouts.first }

    var body: some View {
        List {
            Section {
                Button(action: startWorkout) {
                    Label(
                        isActiveWorkout
                            ? "Resume Workout"
                            : (canStartWorkout ? "Start Workout" : "Finish Current Workout First"),
                        systemImage: isActiveWorkout || canStartWorkout ? "play.fill" : "lock.fill"
                    )
                }
                .fontWeight(.semibold)
                .disabled(!isActiveWorkout && (!canStartWorkout || planExercises.isEmpty))
            } footer: {
                if let comment = plan.comment, !comment.isEmpty {
                    Text(comment)
                }
            }

            Section("Summary") {
                LabeledContent("Sessions") {
                    Text("\(completedWorkouts.count)")
                        .font(.ironMetric(.body))
                        .foregroundStyle(IronTheme.accent)
                }
                LabeledContent("Last Trained", value: latestWorkoutDate)
                LabeledContent("Total Volume") {
                    volumeText(totalVolume).font(.ironMetric(.body))
                }
            }
            .monospacedDigit()

            trendSection

            exerciseSection

            if !completedWorkouts.isEmpty {
                Section("Recent Sessions") {
                    ForEach(completedWorkouts.prefix(4), id: \.objectID) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date"))
                                (Text("\(workout.numberOfCompletedSets ?? 0) sets").foregroundColor(IronTheme.metricSets)
                                 + Text(" · ").foregroundColor(IronTheme.secondaryText)
                                 + volumeText(workout.totalCompletedWeight ?? 0)
                                 + Text(" · ").foregroundColor(IronTheme.secondaryText)
                                 + Text(workout.duration.flatMap { Workout.durationFormatter.string(from: $0) } ?? "—").foregroundColor(IronTheme.metricTime))
                                    .font(.ironMetric(.caption, weight: .semibold))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, isActiveWorkout ? IronTheme.floatingWorkoutBottomClearance : 24, for: .scrollContent)
        .navigationTitle(plan.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        Section {
            if trendPoints.isEmpty {
                ContentUnavailableView(
                    "No Trend Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Volume, repetitions, and duration appear here after your first saved session.")
                )
                .listRowBackground(Color.clear)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    metricValueText(latestWorkout.map(metricValue(for:)) ?? 0)
                        .font(.ironMetric(.title2))
                        .foregroundStyle(selectedMetric.color)
                        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedMetric)
                        .contentTransition(reduceMotion ? .opacity : .numericText())

                    WorkoutPlanTrendChart(
                        points: trendPoints,
                        valueFormatter: chartValueLabel,
                        valueText: metricValueText,
                        metricTitle: selectedMetric.title,
                        metricColor: selectedMetric.color,
                        volumeFormatter: displayWeight
                    )
                }
                .padding(.vertical, 6)

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(WorkoutPlanTrendMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        } header: {
            Text("Training Trend")
        } footer: {
            if !trendPoints.isEmpty {
                Text("Latest \(selectedMetric.title.lowercased()) across your last \(trendPoints.count) session\(trendPoints.count == 1 ? "" : "s").")
            }
        }
    }

    @ViewBuilder
    private var exerciseSection: some View {
        Section("Exercises") {
            if planExercises.isEmpty {
                Button("Add Exercises", systemImage: "plus", action: onEdit)
            } else {
                ForEach(planExercises, id: \.id) { planExercise in
                    planExerciseRow(planExercise)
                }
            }
        }
    }

    @ViewBuilder
    private func planExerciseRow(_ planExercise: WorkoutRoutineExercise) -> some View {
        let exercise = planExercise.exercise(in: exerciseStore.exercises)
        let sets = planExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
        let summary: Text = sets.isEmpty
            ? Text("No target sets").foregroundColor(IronTheme.secondaryText)
            : sets.enumerated().map { targetSetSummary($0.element, index: $0.offset) }
                .reduce(Text("")) { result, next in result + next + Text("  ") }

        if let exercise {
            NavigationLink {
                ExerciseDetailView(exercise: exercise)
            } label: {
                HStack(spacing: 12) {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.title)
                            .lineLimit(2)
                        summary
                            .font(.ironMetric(.caption, weight: .semibold))
                            .lineLimit(2)
                        if let rest = planExercise.restTimerDurationValue {
                            Text(restTimerText(rest))
                                .font(.ironMetric(.caption2, weight: .semibold))
                                .foregroundStyle(IronTheme.metricTime)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unknown Exercise")
                summary
                    .font(.ironMetric(.caption, weight: .semibold))
            }
        }
    }

    private func targetSetSummary(_ set: WorkoutRoutineSet, index: Int) -> Text {
        Text(targetSetLabel(set, index: index) + ": ").foregroundColor(IronTheme.metricSets)
            + targetSetText(set)
    }

    private func targetSetLabel(_ set: WorkoutRoutineSet, index: Int) -> String {
        switch set.tagValue {
        case .warmUp: return "W"
        case .dropSet: return "D"
        case .failure: return "F"
        case nil: return "\(index + 1)"
        }
    }

    private func startWorkout() {
        if isActiveWorkout {
            onWorkoutStarted()
            return
        }
        guard canStartWorkout, !planExercises.isEmpty else { return }
        do {
            _ = try Workout.startNew(in: managedObjectContext, routine: plan)
            onWorkoutStarted()
        } catch {
            onFailure(error)
        }
    }

    private func metricValue(for workout: Workout) -> Double {
        switch selectedMetric {
        case .volume:
            return WeightUnit.convert(
                weight: workout.totalCompletedWeight ?? 0,
                from: .metric,
                to: settingsStore.weightUnit
            )
        case .repetitions:
            return Double(totalRepetitions(for: workout))
        case .duration:
            return (workout.duration ?? 0) / 60
        }
    }

    private func totalRepetitions(for workout: Workout) -> Int {
        (workout.workoutExercises?.array as? [WorkoutExercise] ?? [])
            .reduce(0) { $0 + ($1.numberOfCompletedRepetitions ?? 0) }
    }

    private func chartValueLabel(_ value: Double) -> String {
        switch selectedMetric {
        case .volume:
            return (settingsStore.weightUnit.displayNumberFormatter.string(from: value as NSNumber) ?? "—")
                + " " + settingsStore.weightUnit.unit.symbol
        case .repetitions:
            return String(format: "%.0f", value)
        case .duration:
            if value >= 60 { return String(format: "%.1fh", value / 60) }
            return String(format: "%.0fm", value)
        }
    }

    private func metricValueText(_ value: Double) -> Text {
        if selectedMetric == .volume {
            return Text(settingsStore.weightUnit.displayNumberFormatter.string(from: value as NSNumber) ?? "—")
                .foregroundColor(IronTheme.metricVolume)
                + Text(" " + settingsStore.weightUnit.unit.symbol)
                    .font(.caption).foregroundColor(IronTheme.secondaryText)
        }
        return Text(chartValueLabel(value)).foregroundColor(selectedMetric.color)
    }

    private var latestWorkoutDate: String {
        guard let date = latestWorkout?.start else { return "—" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private func displayWeight(_ kilograms: Double) -> String {
        WeightUnit.format(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
    }

    private func volumeText(_ kilograms: Double) -> Text {
        let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        return Text(settingsStore.weightUnit.displayNumberFormatter.string(from: display as NSNumber) ?? "—")
            .foregroundColor(IronTheme.metricVolume)
            + Text(" " + settingsStore.weightUnit.unit.symbol).font(.caption).foregroundColor(IronTheme.secondaryText)
    }

    private func restTimerText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return "Rest \(formatter.string(from: duration) ?? "Off")"
    }

    private func targetSetText(_ set: WorkoutRoutineSet) -> Text {
        if let duration = set.durationValue {
            let durationTitle = targetDurationText(duration)
            guard let kilograms = set.weightValue else { return Text(durationTitle).foregroundColor(IronTheme.metricTime) }
            let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
            let weight = settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: display)) ?? "—"
            return Text(weight).foregroundColor(IronTheme.metricVolume)
                + Text(" " + settingsStore.weightUnit.unit.symbol).font(.caption2).foregroundColor(IronTheme.secondaryText)
                + Text(" · ") + Text(durationTitle).foregroundColor(IronTheme.metricTime)
        }

        let repetitions: String
        if let min = set.minRepetitionsValue, let max = set.maxRepetitionsValue {
            repetitions = min == max ? "\(max)" : "\(min)-\(max)"
        } else if let min = set.minRepetitionsValue {
            repetitions = "\(min)+"
        } else if let max = set.maxRepetitionsValue {
            repetitions = "<\(max)"
        } else {
            repetitions = "—"
        }

        guard let kilograms = set.weightValue else { return Text(repetitions).foregroundColor(IronTheme.metricSets) }
        let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        let weight = settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: display)) ?? "—"
        return Text(weight).foregroundColor(IronTheme.metricVolume)
            + Text(" " + settingsStore.weightUnit.unit.symbol).font(.caption2).foregroundColor(IronTheme.secondaryText)
            + Text(" × ") + Text(repetitions).foregroundColor(IronTheme.metricSets)
    }

    private func targetDurationText(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(max(seconds, 0).rounded())
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct SavedWorkoutRow: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @ObservedObject var workout: WorkoutRoutine
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let canStartWorkout: Bool
    let isActiveWorkout: Bool
    let onWorkoutStarted: () -> Void
    let onFailure: (Error) -> Void

    private var workoutExercises: [WorkoutRoutineExercise] {
        workout.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
    }

    private var workoutSummary: String {
        guard !workoutExercises.isEmpty else { return "No exercises" }

        let names = workoutExercises
            .compactMap { $0.exercise(in: exerciseStore.exercises)?.title }
        let preview = names.prefix(2).joined(separator: " · ")
        let count = "\(workoutExercises.count) exercise\(workoutExercises.count == 1 ? "" : "s")"
        return preview.isEmpty ? count : "\(count) · \(preview)"
    }

    private var canStart: Bool {
        !workoutExercises.isEmpty && (isActiveWorkout || canStartWorkout)
    }

    var body: some View {
        HStack(spacing: 12) {
            startButton

            NavigationLink {
                WorkoutPlanDetailView(
                    plan: workout,
                    canStartWorkout: canStartWorkout,
                    isActiveWorkout: isActiveWorkout,
                    onEdit: onEdit,
                    onWorkoutStarted: onWorkoutStarted,
                    onFailure: onFailure
                )
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.displayTitle)
                            .lineLimit(1)
                        Text(workout.comment?.isEmpty == false ? workout.comment! : workoutSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if isActiveWorkout {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Edit", systemImage: "pencil", action: onEdit)
                .tint(.gray)
        }
        .swipeActions(edge: .leading) {
            if workoutExercises.isEmpty {
                Button("Add Exercises", systemImage: "plus", action: onEdit)
                    .tint(.accentColor)
            } else {
                Button(isActiveWorkout ? "Resume" : "Start", systemImage: "play.fill", action: start)
                    .tint(.accentColor)
                    .disabled(!isActiveWorkout && !canStartWorkout)
            }
        }
        .contextMenu {
            if !workoutExercises.isEmpty {
                Button(isActiveWorkout ? "Resume Workout" : "Start Workout", systemImage: "play.fill", action: start)
                    .disabled(!isActiveWorkout && !canStartWorkout)
            }
            Button("Edit Workout", systemImage: "pencil", action: onEdit)
            Button("Duplicate Workout", systemImage: "doc.on.doc", action: onDuplicate)
            Button("Share Workout", systemImage: "square.and.arrow.up", action: onExport)
            Divider()
            Button("Delete Workout", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    /// Starting is the primary reason to open this screen, so it gets a visible
    /// control rather than living only in the swipe and context menus.
    private var startButton: some View {
        Button(action: start) {
            Image(systemName: isActiveWorkout ? "figure.strengthtraining.traditional" : "play.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(canStart ? AnyShapeStyle(IronTheme.onAccent) : AnyShapeStyle(.tertiary))
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(canStart ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)))
                }
        }
        .buttonStyle(.borderless)
        .disabled(!canStart)
        .accessibilityLabel(isActiveWorkout ? "Resume \(workout.displayTitle)" : "Start \(workout.displayTitle)")
    }

    private func start() {
        if isActiveWorkout {
            onWorkoutStarted()
            return
        }
        do {
            _ = try Workout.startNew(in: managedObjectContext, routine: workout)
            onWorkoutStarted()
        } catch {
            onFailure(error)
        }
    }
}

#if DEBUG
struct StartWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        StartWorkoutView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
