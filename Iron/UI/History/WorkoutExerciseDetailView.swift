//
//  WorkoutExerciseDetailView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 23.06.19.
//  Rebuilt around Iron's inline set editor.
//

import SwiftUI
import CoreData
import UIKit
import WorkoutDataKit

enum HistorySetTrackingValues {
    static func copy(from source: WorkoutSet, to destination: WorkoutSet) {
        destination.durationValue = source.durationValue
        destination.distanceValue = source.distanceValue
        if source.durationValue != nil, source.distanceValue == nil {
            destination.weightValue = 0
            destination.repetitionsValue = 0
        } else {
            destination.weightValue = source.weightValue
            destination.repetitionsValue = source.repetitionsValue
        }
        destination.rpeValue = source.rpeValue
        destination.tagValue = source.tagValue
    }
}

struct WorkoutExerciseDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var restTimerStore: RestTimerStore
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @FetchRequest(fetchRequest: WorkoutExercise.fetchRequest()) private var workoutExerciseHistory
    @ObservedObject var workoutExercise: WorkoutExercise

    @State private var showExerciseInfo = false
    @State private var showAllExerciseHistory = false
    @State private var showingRestTimerEditor = false
    @State private var plateCalculatorSet: WorkoutSet?
    @State private var persistenceError: String?

    init(workoutExercise: WorkoutExercise) {
        self.workoutExercise = workoutExercise
        _workoutExerciseHistory = FetchRequest(fetchRequest: workoutExercise.historyFetchRequest)
    }

    private var exercise: Exercise? {
        workoutExercise.exercise(in: exerciseStore.exercises)
    }

    private var workoutSets: [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private var previousSessions: [WorkoutExercise] {
        workoutExerciseHistory.filter { $0.objectID != workoutExercise.objectID }
    }

    private var isCurrentWorkout: Bool {
        workoutExercise.workout?.isCurrentWorkout ?? false
    }

    private var commentBinding: Binding<String> {
        Binding(
            get: { workoutExercise.comment ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                workoutExercise.comment = trimmed.isEmpty ? nil : value
                save()
            }
        )
    }

    var body: some View {
        List {
            overviewSection
            setsSection
            previousSessionsSection
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, IronTheme.floatingWorkoutBottomClearance, for: .scrollContent)
        .navigationTitle(exercise?.title ?? "Exercise Log")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if exercise != nil {
                    Button("Exercise Details", systemImage: "info.circle") { showExerciseInfo = true }
                        .labelStyle(.iconOnly)
                }

                if isCurrentWorkout {
                    Button("Rest Timer", systemImage: "timer") { showingRestTimerEditor = true }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .alert("Workout Not Saved", isPresented: Binding(
            get: {
                persistenceError != nil
                    && !showingRestTimerEditor
                    && plateCalculatorSet == nil
            },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Please try again.")
        }
        .navigationDestination(isPresented: $showExerciseInfo) {
            if let exercise {
                ExerciseDetailView(exercise: exercise)
                    .environmentObject(settingsStore)
            }
        }
        .sheet(isPresented: $showAllExerciseHistory) {
            if let exercise {
                IronUtilitySheet(
                    title: "Exercise History",
                    subtitle: "",
                    systemImage: "clock.arrow.circlepath",
                    onClose: { showAllExerciseHistory = false }
                ) {
                    ExerciseHistoryView(exercise: exercise)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingRestTimerEditor) {
            RestTimerConfigurationSheet(
                title: "Rest Timer",
                subtitle: "Recovery after each completed set",
                initialDuration: workoutExercise.restTimerDurationValue ?? restTimerDuration,
                secondaryActionTitle: "Use Workout Default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")",
                onSecondaryAction: { setRestTimer(nil) },
                shouldDismiss: { persistenceError == nil },
                onApply: { duration in setRestTimer(duration) }
            )
            .alert("Workout Not Saved", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "Please try again.")
            }
        }
        .sheet(item: $plateCalculatorSet) { set in
            IronUtilitySheet(
                title: "Plate Calculator",
                subtitle: "",
                systemImage: "plusminus",
                onClose: { plateCalculatorSet = nil }
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: max(displayWeight(for: set), settingsStore.weightUnit.barbellWeight),
                    onApply: { value in
                        performMutation(failureMessage: "The plate-calculator weight was not saved.") {
                            set.weightValue = WeightUnit.convert(
                                weight: value,
                                from: settingsStore.weightUnit,
                                to: .metric
                            )
                        } onSuccess: {
                            plateCalculatorSet = nil
                        }
                    }
                )
            }
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
        .onDisappear { _ = save() }
    }

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            if let exercise {
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                        .environmentObject(settingsStore)
                } label: {
                    HStack(spacing: 12) {
                        ExerciseDiagramThumbnail(exercise: exercise, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.title)
                                .lineLimit(2)
                            Text(exerciseContextText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            LabeledContent("Sets") {
                Text("\(workoutExercise.numberOfCompletedSets ?? 0) of \(workoutSets.count)").font(.ironMetric(.body, weight: .semibold))
            }
            LabeledContent(sessionWorkLabel.capitalized) {
                Text(sessionWorkValue).font(.ironMetric(.body, weight: .semibold))
            }
        } header: {
            Text("Overview")
        } footer: {
            Text(sessionContextText)
        }
        .monospacedDigit()
    }

    private var exerciseContextText: String {
        guard let exercise else { return "Exercise details unavailable" }
        let muscle = exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized
        guard let equipment = exercise.equipment.first, !equipment.isEmpty else { return muscle }
        return "\(muscle) · \(equipment.capitalized)"
    }

    private var sessionContextText: String {
        if isCurrentWorkout { return "Current workout" }
        guard let start = workoutExercise.workout?.start else { return "Completed session" }
        return start.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var completedWorkoutSets: [WorkoutSet] {
        workoutSets.filter(\.isCompleted)
    }

    private var sessionWorkValue: String {
        let totalDistance = completedWorkoutSets.compactMap(\.distanceValue).reduce(0, +)
        if totalDistance > 0 { return formatDistance(totalDistance) }

        let totalDuration = completedWorkoutSets.compactMap(\.durationValue).reduce(0, +)
        if totalDuration > 0 { return formatDuration(totalDuration) }

        if let volume = workoutExercise.totalCompletedWeight, volume > 0 {
            return WeightUnit.format(weight: volume, from: .metric, to: settingsStore.weightUnit)
        }

        let repetitions = workoutExercise.numberOfCompletedRepetitions ?? 0
        return repetitions > 0 ? "\(repetitions)" : "—"
    }

    private var sessionWorkLabel: String {
        if completedWorkoutSets.contains(where: { $0.distanceValue != nil }) { return "distance" }
        if completedWorkoutSets.contains(where: { $0.durationValue != nil }) { return "duration" }
        if (workoutExercise.totalCompletedWeight ?? 0) > 0 { return "volume" }
        return "reps"
    }

    @ViewBuilder
    private var setsSection: some View {
        let usesDuration = workoutSets.contains { $0.durationValue != nil }
        let isBarbell = exercise?.type == .barbell && !usesDuration

        Section {
            TextField("Exercise Notes", text: commentBinding, axis: .vertical)
                .lineLimit(1...4)

            if isCurrentWorkout {
                Button {
                    showingRestTimerEditor = true
                } label: {
                    LabeledContent(
                        "Rest Timer",
                        value: restTimerDurationFormatter.string(from: restTimerDuration) ?? "Off"
                    )
                }
            }

            ForEach(Array(workoutSets.enumerated()), id: \.element.id) { index, set in
                InlineWorkoutSetRow(
                    set: set,
                    index: index,
                    usesDuration: usesDuration,
                    isBarbell: isBarbell,
                    previousTitle: previousSetTitle(at: index),
                    onOpenPlateCalculator: { plateCalculatorSet = set },
                    onToggleCompleted: { toggleCompleted(set) },
                    onDelete: { delete(set) },
                    onChanged: save,
                    allowsSwipeToDelete: true
                )
                .environmentObject(settingsStore)
            }

            Button("Add Set", systemImage: "plus", action: addSet)
        } header: {
            Text(isCurrentWorkout ? "Log Sets" : "Session Sets")
        }
    }

    @ViewBuilder
    private var previousSessionsSection: some View {
        Section {
            if previousSessions.isEmpty {
                Text("The next time you train this exercise, your previous sets appear here for quick comparison.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previousSessions.prefix(8), id: \.objectID) { session in
                    previousSessionRow(session)
                }

                if previousSessions.count > 8, let exercise {
                    Button("View All \(previousSessions.count) Sessions", systemImage: "clock.arrow.circlepath") {
                        showAllExerciseHistory = true
                    }
                    .accessibilityHint("Opens the complete history for \(exercise.title)")
                }
            }
        } header: {
            Text(previousSessions.isEmpty ? "First Session" : "Previous Sessions")
        }
    }

    private func previousSessionRow(_ session: WorkoutExercise) -> some View {
        let sets = session.workoutSets?.array as? [WorkoutSet] ?? []
        let summary = sets
            .map { $0.resultTitle(weightUnit: settingsStore.weightUnit) }
            .joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(Workout.dateFormatter.string(from: session.workout?.start, fallback: "Unknown date"))
                if sets.contains(where: { $0.isPersonalRecord ?? false }) {
                    Image(systemName: "medal.fill")
                        .font(.caption)
                        .foregroundStyle(IronTheme.metricRecord)
                }
                Spacer(minLength: 4)
                Text(previousSessionResult(session))
                    .font(.ironMetric(.caption, weight: .semibold))
                    .foregroundStyle(IronTheme.secondaryText)
            }

            Text(sets.isEmpty ? "No sets" : summary)
                .font(.ironMetric(.caption, weight: .semibold))
                .foregroundStyle(IronTheme.secondaryText)
                .lineLimit(2)

            if let comment = session.comment, !comment.isEmpty {
                Text(comment)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func previousSessionResult(_ session: WorkoutExercise) -> String {
        let sets = (session.workoutSets?.array as? [WorkoutSet] ?? []).filter(\.isCompleted)
        let totalDistance = sets.compactMap(\.distanceValue).reduce(0, +)
        if totalDistance > 0 { return formatDistance(totalDistance) }

        let totalDuration = sets.compactMap(\.durationValue).reduce(0, +)
        if totalDuration > 0 { return formatDuration(totalDuration) }

        if let volume = session.totalCompletedWeight, volume > 0 {
            return WeightUnit.format(weight: volume, from: .metric, to: settingsStore.weightUnit)
        }

        let repetitions = session.numberOfCompletedRepetitions ?? 0
        return repetitions > 0 ? "\(repetitions) reps" : "—"
    }

    private var restTimerDuration: TimeInterval {
        if let customDuration = workoutExercise.restTimerDurationValue {
            return customDuration
        }
        return workoutDefaultRestTimerDuration
    }

    private var workoutDefaultRestTimerDuration: TimeInterval {
        switch exercise?.type {
        case .barbell:
            return settingsStore.defaultRestTimeBarbellBased
        case .dumbbell:
            return settingsStore.defaultRestTimeDumbbellBased
        default:
            return settingsStore.defaultRestTime
        }
    }

    private func setRestTimer(_ duration: TimeInterval?) {
        performMutation(failureMessage: "The rest-timer setting was not saved.") {
            workoutExercise.restTimerDurationValue = duration
        }
    }

    private func previousSetTitle(at index: Int) -> String {
        for session in previousSessions {
            guard let sets = session.workoutSets?.array as? [WorkoutSet], sets.indices.contains(index) else { continue }
            return sets[index].resultTitle(weightUnit: settingsStore.weightUnit)
        }
        return "—"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(max(seconds, 0).rounded())
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formatDistance(_ meters: Double) -> String {
        switch settingsStore.weightUnit {
        case .metric:
            if meters >= 1_000 { return String(format: "%.2f km", meters / 1_000) }
            return String(format: "%.0f m", meters)
        case .imperial:
            let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles).value
            if miles >= 0.1 { return String(format: "%.2f mi", miles) }
            let feet = Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
            return String(format: "%.0f ft", feet)
        }
    }

    private func displayWeight(for set: WorkoutSet) -> Double {
        WeightUnit.convert(
            weight: set.weightValue,
            from: .metric,
            to: settingsStore.weightUnit
        )
    }

    private func addSet() {
        performMutation(failureMessage: "The set was not added.") {
            let previous = workoutSets.last
            let set = WorkoutSet.create(context: managedObjectContext)
            set.workoutExercise = workoutExercise

            if let previous {
                copyTrackingValues(from: previous, to: set)
            } else if let priorSession = previousSessions.first,
                      let priorSet = priorSession.workoutSets?.firstObject as? WorkoutSet {
                copyTrackingValues(from: priorSet, to: set)
            } else {
                set.repetitionsValue = 5
                if exercise?.type == .barbell {
                    set.weightValue = WeightUnit.convert(
                        weight: settingsStore.weightUnit.barbellWeight,
                        from: settingsStore.weightUnit,
                        to: .metric
                    )
                }
            }

            if !isCurrentWorkout {
                set.isCompleted = true
                set.completedAt = workoutExercise.workout?.end
            }
        }
    }

    private func copyTrackingValues(from source: WorkoutSet, to destination: WorkoutSet) {
        HistorySetTrackingValues.copy(from: source, to: destination)
    }

    private func toggleCompleted(_ set: WorkoutSet) {
        let isCompleting = !set.isCompleted
        let completionDate = Date()
        performMutation(failureMessage: "The set completion was not saved.") {
            if set.isCompleted {
                set.isCompleted = false
                set.completedAt = nil
            } else {
                set.isCompleted = true
                set.completedAt = completionDate
                workoutExercise.workout?.start = workoutExercise.workout?.start ?? completionDate
            }
        } onSuccess: {
            if isCompleting && isCurrentWorkout {
                restTimerStore.start(duration: restTimerDuration)
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
            }
        }
    }

    @discardableResult
    private func delete(_ set: WorkoutSet) -> Bool {
        performMutation(failureMessage: "The set was not removed.") {
            workoutExercise.removeFromWorkoutSets(set)
            managedObjectContext.delete(set)
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

    @discardableResult
    private func performMutation(
        failureMessage: String,
        mutation: () throws -> Void,
        onSuccess: () -> Void = {}
    ) -> Bool {
        persistenceError = nil
        do {
            try HistoryMutationPersistence.perform(
                context: managedObjectContext,
                mutation: mutation,
                onSuccess: onSuccess
            )
            return true
        } catch {
            persistenceError = "\(failureMessage) \(error.localizedDescription)"
            return false
        }
    }
}

#if DEBUG
struct WorkoutExerciseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutExerciseDetailView(workoutExercise: MockWorkoutData.metricRandom.workoutExercise)
                .mockEnvironment(weightUnit: .metric)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
