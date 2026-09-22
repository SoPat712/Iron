//
//  StartWorkoutView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 19.07.19.
//  Rebuilt for Iron's focused workout experience.
//

import SwiftUI
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

/// Keeps plan edits isolated until the user explicitly taps Create or Update.
/// A child context gives Cancel real meaning without rolling back unrelated
/// workout changes in the app's shared view context.
final class WorkoutPlanEditorSession: ObservableObject {
    let context: NSManagedObjectContext
    let routine: WorkoutRoutine
    let isNew: Bool

    private let parentContext: NSManagedObjectContext
    private let route: WorkoutPlanEditorRoute

    init(parentContext: NSManagedObjectContext, route: WorkoutPlanEditorRoute) {
        self.parentContext = parentContext
        self.route = route

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.parent = parentContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context

        switch route.kind {
        case .create(let containerID):
            let container: WorkoutPlan
            if let containerID,
               let existing = try? context.existingObject(with: containerID) as? WorkoutPlan {
                container = existing
            } else {
                container = WorkoutPlan.create(context: context)
            }

            let routine = WorkoutRoutine.create(context: context)
            routine.workoutPlan = container
            self.routine = routine
            self.isNew = true

        case .edit(let planID):
            guard let routine = try? context.existingObject(with: planID) as? WorkoutRoutine else {
                preconditionFailure("Could not load plan editor object")
            }
            self.routine = routine
            self.isNew = false

        case .duplicate(let planID):
            guard let source = try? context.existingObject(with: planID) as? WorkoutRoutine else {
                preconditionFailure("Could not load plan to duplicate")
            }
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

private struct WorkoutPlanEditorHost: View {
    @StateObject private var session: WorkoutPlanEditorSession
    @State private var persistenceError: String?

    let onDismiss: () -> Void

    init(
        parentContext: NSManagedObjectContext,
        route: WorkoutPlanEditorRoute,
        onDismiss: @escaping () -> Void
    ) {
        _session = StateObject(
            wrappedValue: WorkoutPlanEditorSession(parentContext: parentContext, route: route)
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
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
}

struct StartWorkoutView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @FetchRequest(fetchRequest: StartWorkoutView.fetchRequest) private var workoutPlans
    @FetchRequest(fetchRequest: Workout.currentWorkoutFetchRequest) private var currentWorkouts

    var onOpenCurrentWorkout: () -> Void = {}

    @State private var planToDelete: WorkoutRoutine?
    @State private var planEditorRoute: WorkoutPlanEditorRoute?
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
            ZStack {
                IronScreenBackground()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if currentWorkouts.isEmpty {
                                quickStartCard
                            }
                            IronSectionTitle(title: "Saved workouts", detail: "\(plans.count) total")

                            if plans.isEmpty {
                                emptyPlansCard
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                                        SavedWorkoutRow(
                                            workout: plan,
                                            onEdit: {
                                                planEditorRoute = WorkoutPlanEditorRoute(
                                                    kind: .edit(planID: plan.objectID)
                                                )
                                            },
                                            onDuplicate: { duplicate(plan) },
                                            onDelete: { requestDelete(plan) },
                                            canStartWorkout: currentWorkouts.isEmpty,
                                            isActiveWorkout: activeRoutineObjectID == plan.objectID,
                                            onWorkoutStarted: onOpenCurrentWorkout,
                                            onFailure: { persistenceError = $0.localizedDescription }
                                        )

                                        if index < plans.count - 1 {
                                            IronHairline(opacity: 0.44)
                                                .padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                                        .fill(IronTheme.surface)
                                )
                            }

                            Button(action: newPlan) {
                                Label("Create workout", systemImage: "plus.rectangle.on.folder.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(IronSecondaryButtonStyle())
                        }
                        .padding(IronTheme.horizontalPadding)
                        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
                    }
                }
            }
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: newPlan) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New workout")
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
                .presentationBackground(IronTheme.modalSurface)
            }
        }
        .confirmationDialog(
            planToDelete.map { "Delete \($0.displayTitle)?" } ?? "Delete workout?",
            isPresented: Binding(
                get: { planToDelete != nil },
                set: { if !$0 { planToDelete = nil } }
            ),
            titleVisibility: .visible
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
        .alert("Workout Not Saved", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick start")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("Start an empty workout and add exercises as you train.")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(IronTheme.accent)
            }
            Button(action: startEmptyWorkout) {
                Label("Start empty workout", systemImage: "play.fill")
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    private var emptyPlansCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("No workouts yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Create a workout for push/pull/legs, upper/lower, or any split you train.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
            Button("Create your first workout", action: newPlan)
                .buttonStyle(IronPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: IronTheme.cornerRadius).fill(IronTheme.surface))
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
    let points: [WorkoutPlanTrendPoint]
    let valueFormatter: (Double) -> String
    let metricTitle: String
    let volumeFormatter: (Double) -> String

    @State private var selectedPointID: WorkoutPlanTrendPoint.ID?

    private var upperValue: Double {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private func xPosition(index: Int, width: CGFloat) -> CGFloat {
        guard points.count > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(points.count - 1) * width
    }

    private func yPosition(value: Double, height: CGFloat) -> CGFloat {
        height - (max(value, 0) / upperValue * height)
    }

    private var selectedPoint: WorkoutPlanTrendPoint? {
        guard let selectedPointID else { return nil }
        return points.first { $0.id == selectedPointID }
    }

    private func nearestPointID(
        to location: CGPoint,
        labelWidth: CGFloat,
        plotWidth: CGFloat
    ) -> WorkoutPlanTrendPoint.ID? {
        guard !points.isEmpty else { return nil }
        guard points.count > 1 else { return points[0].id }

        let clampedX = min(max(location.x - labelWidth, 0), plotWidth)
        let progress = clampedX / plotWidth
        let index = Int((progress * CGFloat(points.count - 1)).rounded())
        return points[min(max(index, 0), points.count - 1)].id
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

        withAnimation(.easeOut(duration: 0.12)) {
            selectedPointID = points[targetIndex].id
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                let labelWidth: CGFloat = 50
                let plotWidth = max(geometry.size.width - labelWidth - 4, 1)
                let plotHeight = max(geometry.size.height - 8, 1)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { index in
                        let fraction = Double(index) / 2
                        let y = plotHeight * CGFloat(fraction)

                        Path { path in
                            path.move(to: CGPoint(x: labelWidth, y: y))
                            path.addLine(to: CGPoint(x: labelWidth + plotWidth, y: y))
                        }
                        .stroke(IronTheme.outline.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

                        Text(valueFormatter(upperValue * (1 - fraction)))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundColor(IronTheme.tertiaryText)
                            .frame(width: labelWidth - 6, alignment: .trailing)
                            .position(x: (labelWidth - 6) / 2, y: max(y, 6))
                    }

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let position = CGPoint(
                                x: labelWidth + xPosition(index: index, width: plotWidth),
                                y: yPosition(value: point.value, height: plotHeight)
                            )
                            if index == 0 { path.move(to: position) }
                            else { path.addLine(to: position) }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [IronTheme.accent.opacity(0.62), IronTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                    if let selectedPoint,
                       let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
                        let selectedX = labelWidth + xPosition(index: selectedIndex, width: plotWidth)
                        Path { path in
                            path.move(to: CGPoint(x: selectedX, y: 0))
                            path.addLine(to: CGPoint(x: selectedX, y: plotHeight))
                        }
                        .stroke(
                            IronTheme.accent.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                    }

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let isSelected = point.id == selectedPoint?.id
                        Circle()
                            .fill(
                                isSelected
                                    ? IronTheme.background
                                    : (index == points.count - 1 ? IronTheme.accent : IronTheme.surface)
                            )
                            .overlay(
                                Circle().stroke(
                                    IronTheme.accent,
                                    lineWidth: isSelected ? 2.5 : 2
                                )
                            )
                            .frame(
                                width: isSelected ? 12 : (index == points.count - 1 ? 10 : 8),
                                height: isSelected ? 12 : (index == points.count - 1 ? 10 : 8)
                            )
                            .shadow(
                                color: isSelected ? IronTheme.accent.opacity(0.3) : .clear,
                                radius: isSelected ? 5 : 0
                            )
                            .position(
                                x: labelWidth + xPosition(index: index, width: plotWidth),
                                y: yPosition(value: point.value, height: plotHeight)
                            )
                    }

                    if let selectedPoint,
                       let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
                        let selectedPosition = CGPoint(
                            x: labelWidth + xPosition(index: selectedIndex, width: plotWidth),
                            y: yPosition(value: selectedPoint.value, height: plotHeight)
                        )
                        selectionTooltip(
                            for: selectedPoint,
                            at: selectedPosition,
                            in: geometry.size
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectedPointID = nearestPointID(
                                to: value.location,
                                labelWidth: labelWidth,
                                plotWidth: plotWidth
                            )
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Training trend chart with \(points.count) sessions")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(
                    "Tap or drag across the chart to select a session. Use previous and next session actions to explore the chart."
                )
                .accessibilityAction(named: Text("Previous session")) {
                    adjustSelection(.decrement)
                }
                .accessibilityAction(named: Text("Next session")) {
                    adjustSelection(.increment)
                }
                .onChange(of: points.map(\.id)) { _, identifiers in
                    if let selectedPointID, !identifiers.contains(selectedPointID) {
                        self.selectedPointID = nil
                    }
                }
            }
            .frame(height: 142)

            HStack {
                Text(points.first.map { Self.dateFormatter.string(from: $0.date) } ?? "")
                Spacer()
                Text(points.count > 2 ? "\(points.count) sessions" : "")
                Spacer()
                Text(points.last.map { Self.dateFormatter.string(from: $0.date) } ?? "")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(IronTheme.tertiaryText)
            .padding(.leading, 50)
        }
    }

    private func selectionTooltip(
        for point: WorkoutPlanTrendPoint,
        at position: CGPoint,
        in size: CGSize
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(dateLabel(point.date))
                .font(.caption.weight(.semibold))
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(spacing: 6) {
                Text(metricTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
                Spacer(minLength: 4)
                Text(valueFormatter(point.value))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.accent)
            }

            HStack(spacing: 8) {
                tooltipMetric(durationLabel(point.duration), label: "TIME")
                tooltipMetric(volumeFormatter(point.totalVolume), label: "VOLUME")
                tooltipMetric("\(point.completedSets)", label: "SETS")
                tooltipMetric("\(point.repetitions)", label: "REPS")
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .stroke(IronTheme.accent.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: IronTheme.background.opacity(0.28), radius: 8, y: 3)
        .position(
            x: min(max(position.x, 110), max(size.width - 110, 110)),
            y: position.y < 62
                ? min(position.y + 60, size.height - 42)
                : max(position.y - 60, 42)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tooltipMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.45)
                .foregroundColor(IronTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

private struct WorkoutPlanDetailView: View {
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
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    planHero
                        .padding(.bottom, 22)
                    sectionSeparator
                    trendSection
                        .padding(.vertical, 22)
                    sectionSeparator
                    exerciseSection
                        .padding(.vertical, 22)

                    if !completedWorkouts.isEmpty {
                        sectionSeparator
                        recentSessionsSection
                            .padding(.top, 22)
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, isActiveWorkout ? 184 : 120)
            }
        }
        .navigationTitle(plan.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
    }

    private var planHero: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.accentSoft)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text(plan.comment?.isEmpty == false
                         ? plan.comment!
                         : "\(planExercises.count) exercise\(planExercises.count == 1 ? "" : "s") · Saved workout")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                heroMetric("\(completedWorkouts.count)", label: "SESSIONS")
                heroMetricDivider
                heroMetric(latestWorkoutDate, label: "LAST TRAINED")
                heroMetricDivider
                heroMetric(displayWeight(totalVolume), label: "TOTAL VOLUME")
            }

            Button(action: startWorkout) {
                Label(
                    isActiveWorkout
                        ? "Resume workout"
                        : (canStartWorkout ? "Start workout" : "Finish current workout first"),
                    systemImage: isActiveWorkout || canStartWorkout ? "play.fill" : "lock.fill"
                )
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .disabled(!isActiveWorkout && (!canStartWorkout || planExercises.isEmpty))
            .opacity(isActiveWorkout || (canStartWorkout && !planExercises.isEmpty) ? 1 : 0.52)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous).fill(IronTheme.surface))
    }

    private func heroMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(IronTheme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var heroMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.55))
            .frame(width: 1, height: 38)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(
                title: "Training trend",
                detail: completedWorkouts.isEmpty ? "NO HISTORY" : "LAST \(min(completedWorkouts.count, 8))"
            )

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(latestMetricValue)
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                    Text("Latest \(selectedMetric.title.lowercased())")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
                Spacer()
                Image(systemName: selectedMetric.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(IronTheme.accentSoft))
            }

            if trendPoints.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(IronTheme.accent)
                    Text("Complete this workout to start its trend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("Volume, repetitions, and duration will appear here after your first saved session.")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 132)
                .padding(.vertical, 8)
            } else {
                WorkoutPlanTrendChart(
                    points: trendPoints,
                    valueFormatter: chartValueLabel,
                    metricTitle: selectedMetric.title,
                    volumeFormatter: displayWeight
                )
            }

            Picker("Trend metric", selection: $selectedMetric) {
                ForEach(WorkoutPlanTrendMetric.allCases) { metric in
                    Text(metric.title)
                        .tag(metric)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Exercises", detail: "\(planExercises.count) TOTAL")

            if planExercises.isEmpty {
                Button(action: onEdit) {
                    Label("Add exercises to this workout", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IronSecondaryButtonStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(planExercises.enumerated()), id: \.element.id) { index, planExercise in
                        planExerciseRow(planExercise, index: index)
                        if index < planExercises.count - 1 {
                            IronHairline().padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func planExerciseRow(_ planExercise: WorkoutRoutineExercise, index: Int) -> some View {
        let exercise = planExercise.exercise(in: exerciseStore.exercises)
        let sets = planExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []

        return VStack(alignment: .leading, spacing: 11) {
            planExerciseHeader(planExercise, exercise: exercise, index: index)

            if sets.isEmpty {
                Text("No target sets")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("SET")
                            .frame(width: 42, alignment: .center)
                        Text("TARGET")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.65)
                    .foregroundColor(IronTheme.tertiaryText)
                    .frame(height: 28)

                    ForEach(Array(sets.prefix(4).enumerated()), id: \.element.id) { setIndex, set in
                        targetSetPreviewRow(set, index: setIndex)
                    }

                    if sets.count > 4 {
                        Text("+\(sets.count - 4) more target set\(sets.count - 4 == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(IronTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func planExerciseHeader(
        _ planExercise: WorkoutRoutineExercise,
        exercise: Exercise?,
        index: Int
    ) -> some View {
        if let exercise {
            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                HStack(spacing: 12) {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.title)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(IronTheme.accent)
                            .lineLimit(2)
                        Text(planExercise.restTimerDurationValue.map(restTimerText) ?? "Workout default rest")
                            .font(.caption)
                            .foregroundColor(IronTheme.accent)
                    }

                    Spacer(minLength: 8)

                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundColor(IronTheme.tertiaryText)
                        .frame(minWidth: 20)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens exercise details")
        } else {
            HStack(spacing: 12) {
                Circle()
                    .fill(IronTheme.raisedSurface)
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "dumbbell.fill").foregroundColor(IronTheme.accent))
                Text("Unknown exercise")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)

                Spacer(minLength: 8)

                Text("\(index + 1)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.tertiaryText)
            }
        }
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Recent sessions", detail: "\(completedWorkouts.count) TOTAL")

            VStack(spacing: 0) {
                ForEach(Array(completedWorkouts.prefix(4).enumerated()), id: \.element.id) { index, workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(IronTheme.onAccent)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(IronTheme.success))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Workout.dateFormatter.string(from: workout.start, fallback: "Unknown date"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(IronTheme.primaryText)
                                Text("\(workout.numberOfCompletedSets ?? 0) sets · \(displayWeight(workout.totalCompletedWeight ?? 0))")
                                    .font(.caption)
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                            Spacer()
                            Text(workout.duration.flatMap { Workout.durationFormatter.string(from: $0) } ?? "—")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundColor(IronTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(IronTheme.tertiaryText)
                        }
                        .frame(minHeight: 62)
                    }
                    .buttonStyle(.plain)

                    if index < min(completedWorkouts.count, 4) - 1 {
                        IronHairline().padding(.leading, 58)
                    }
                }
            }
        }
    }

    private var sectionSeparator: some View {
        IronHairline(opacity: 0.52)
    }

    private func targetSetPreviewRow(_ set: WorkoutRoutineSet, index: Int) -> some View {
        HStack(spacing: 10) {
            Text(targetSetLabel(set, index: index))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(set.tagValue == .warmUp ? IronTheme.warning : IronTheme.primaryText)
                .frame(width: 42, height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(IronTheme.raisedSurface)
                )

            Text(targetSetText(set))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40)
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

    private var latestMetricValue: String {
        guard let latestWorkout else { return "—" }
        return chartValueLabel(metricValue(for: latestWorkout))
    }

    private func chartValueLabel(_ value: Double) -> String {
        switch selectedMetric {
        case .volume:
            let suffix = settingsStore.weightUnit == .metric ? "kg" : "lb"
            return value >= 1_000
                ? String(format: "%.1fk %@", value / 1_000, suffix)
                : String(format: "%.0f %@", value, suffix)
        case .repetitions:
            return String(format: "%.0f", value)
        case .duration:
            if value >= 60 { return String(format: "%.1fh", value / 60) }
            return String(format: "%.0fm", value)
        }
    }

    private var latestWorkoutDate: String {
        guard let date = latestWorkout?.start else { return "—" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private func displayWeight(_ kilograms: Double) -> String {
        let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        let suffix = settingsStore.weightUnit == .metric ? "kg" : "lb"
        if display >= 10_000 { return String(format: "%.1fk %@", display / 1_000, suffix) }
        return String(format: display >= 100 ? "%.0f %@" : "%.1f %@", display, suffix)
    }

    private func restTimerText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return "Rest \(formatter.string(from: duration) ?? "Off")"
    }

    private func targetSetText(_ set: WorkoutRoutineSet) -> String {
        if let duration = set.durationValue {
            let durationTitle = targetDurationText(duration)
            guard let kilograms = set.weightValue else { return durationTitle }
            let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
            let weight = settingsStore.weightUnit.numberFormatter.string(from: NSNumber(value: display)) ?? "—"
            return "\(weight) · \(durationTitle)"
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

        guard let kilograms = set.weightValue else { return repetitions }
        let display = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        let weight = settingsStore.weightUnit.numberFormatter.string(from: NSNumber(value: display)) ?? "—"
        return "\(weight) × \(repetitions)"
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

    var body: some View {
        HStack(spacing: 10) {
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
                HStack(spacing: 12) {
                    Image(systemName: isActiveWorkout ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(IronTheme.accentSoft))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(workout.displayTitle)
                                .font(.body.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                                .lineLimit(1)

                            if isActiveWorkout {
                                Text("ACTIVE")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(IronTheme.accent)
                            }
                        }

                        Text(workout.comment?.isEmpty == false ? workout.comment! : workoutSummary)
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens workout details")

            if workoutExercises.isEmpty {
                Button(action: onEdit) {
                    Text("Add")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: start) {
                    Text(isActiveWorkout ? "Resume" : "Start")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isActiveWorkout && !canStartWorkout)
            }

            Menu {
                Button(action: onEdit) {
                    Label("Edit Workout", systemImage: "pencil")
                }
                Button(action: onDuplicate) {
                    Label("Duplicate Workout", systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Workout actions")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
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
