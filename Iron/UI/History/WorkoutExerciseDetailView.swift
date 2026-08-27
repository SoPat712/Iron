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
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sessionOverviewCard
                        .padding(.bottom, 8)

                    editorCard

                    IronHairline(opacity: 0.5)
                        .padding(.horizontal, IronTheme.horizontalPadding)

                    IronSectionTitle(
                        title: "Previous sessions",
                        detail: previousSessions.isEmpty ? "FIRST SESSION" : "\(previousSessions.count) total"
                    )
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                    if previousSessions.isEmpty {
                        firstSessionCard
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(previousSessions.prefix(8).enumerated()), id: \.element.id) { index, session in
                                previousSessionCard(session)

                                if index < min(previousSessions.count, 8) - 1 {
                                    IronHairline(opacity: 0.46)
                                        .padding(.horizontal, IronTheme.horizontalPadding)
                                }
                            }
                        }

                        if previousSessions.count > 8, let exercise {
                            Button(action: { showAllExerciseHistory = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text("View all \(previousSessions.count) sessions")
                                }
                            }
                            .buttonStyle(IronSecondaryButtonStyle())
                            .padding(.horizontal, IronTheme.horizontalPadding)
                            .padding(.top, 16)
                            .accessibilityHint("Opens the complete history for \(exercise.title)")
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .navigationTitle(exercise?.title ?? "Exercise Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if exercise != nil {
                    Button(action: { showExerciseInfo = true }) {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Exercise details")
                }

                if isCurrentWorkout {
                    restTimerMenu
                }
            }
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
                    title: "Exercise history",
                    subtitle: exercise.title,
                    systemImage: "clock.arrow.circlepath",
                    onClose: { showAllExerciseHistory = false }
                ) {
                    ExerciseHistoryView(
                        exercise: exercise,
                        usesModalSurface: true
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(IronTheme.modalSurface)
            }
        }
        .sheet(isPresented: $showingRestTimerEditor) {
            IronDurationPickerSheet(
                title: "Rest timer",
                subtitle: "Recovery after each completed set",
                systemImage: "timer",
                initialDuration: workoutExercise.restTimerDurationValue ?? restTimerDuration,
                minimumDuration: 30,
                maximumDuration: 600,
                durationStep: 15,
                presets: [30, 45, 60, 90, 120, 150, 180, 240, 300],
                secondaryActionTitle: workoutExercise.restTimerDurationValue == nil
                    ? "Keep workout default · \(restTimerDurationFormatter.string(from: restTimerDuration) ?? "0:00")"
                    : "Use workout default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")",
                onSecondaryAction: { setRestTimer(nil) },
                onApply: { duration in setRestTimer(duration) }
            )
        }
        .sheet(item: $plateCalculatorSet) { set in
            IronUtilitySheet(
                title: "Plate calculator",
                subtitle: "Build each side of the bar",
                systemImage: "circle.grid.cross",
                onClose: { plateCalculatorSet = nil }
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
                        plateCalculatorSet = nil
                    }
                )
            }
            .presentationDetents([.height(680), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(IronTheme.modalSurface)
        }
        .onDisappear(perform: save)
    }

    private var sessionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                if let exercise {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 58)
                } else {
                    Circle()
                        .fill(IronTheme.raisedSurface)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "dumbbell")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(IronTheme.accent)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise?.title ?? "Unknown exercise")
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.accent)
                        .lineLimit(2)

                    Text(exerciseContextText)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                        .lineLimit(1)

                    Label(sessionContextText, systemImage: isCurrentWorkout ? "record.circle" : "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(isCurrentWorkout ? IronTheme.success : IronTheme.tertiaryText)
                }

                Spacer(minLength: 0)
            }

            IronHairline(opacity: 0.48)

            HStack(spacing: 0) {
                overviewMetric(
                    icon: "checkmark.circle",
                    value: "\(workoutExercise.numberOfCompletedSets ?? 0)/\(workoutSets.count)",
                    label: "sets"
                )
                overviewDivider
                overviewMetric(
                    icon: "scalemass",
                    value: sessionWorkValue,
                    label: sessionWorkLabel
                )
                overviewDivider
                overviewMetric(
                    icon: "clock.arrow.circlepath",
                    value: "\(previousSessions.count)",
                    label: "previous"
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .stroke(IronTheme.outline.opacity(0.38), lineWidth: 1)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
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

    private func overviewMetric(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.55)
                .foregroundColor(IronTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(IronTheme.outline)
            .frame(width: 1, height: 32)
    }

    private var editorCard: some View {
        let usesDuration = workoutSets.contains { $0.durationValue != nil }
        let isBarbell = exercise?.type == .barbell && !usesDuration

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                IronSectionTitle(title: isCurrentWorkout ? "Log sets" : "Session sets")
                Spacer()
                Text(isCurrentWorkout ? "LIVE" : "EDITABLE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.7)
                    .foregroundColor(isCurrentWorkout ? IronTheme.success : IronTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(IronTheme.raisedSurface))
            }
            .padding(.bottom, 12)

            TextField("Add notes here…", text: commentBinding)
                .font(.subheadline)
                .foregroundColor(IronTheme.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: IronTheme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                        .fill(IronTheme.field)
                )
                .padding(.bottom, 14)

            if isCurrentWorkout {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text("Rest Timer: \(restTimerDurationFormatter.string(from: restTimerDuration) ?? "Off")")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(
                    Capsule(style: .continuous)
                        .fill(IronTheme.accentSoft)
                )
                .padding(.bottom, 14)
            }

            setTableHeader

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

            Button(action: addSet) {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(IronSecondaryButtonStyle())
            .padding(.top, 10)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 18)
    }

    private var setTableHeader: some View {
        let usesDuration = workoutSets.contains { $0.durationValue != nil }
        return HStack(spacing: InlineWorkoutSetLayout.spacing) {
            Text("SET").frame(width: InlineWorkoutSetLayout.setWidth)
            Text("PREVIOUS").frame(width: InlineWorkoutSetLayout.previousWidth)
            if usesDuration {
                Text("DURATION")
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "dumbbell")
                    Text(settingsStore.weightUnit.unit.symbol.uppercased())
                }
                .frame(maxWidth: .infinity)
                Text("REPS").frame(width: InlineWorkoutSetLayout.repetitionsWidth)
            }
            Text("RPE").frame(width: InlineWorkoutSetLayout.rpeWidth)
            Image(systemName: "checkmark").frame(width: InlineWorkoutSetLayout.completionWidth)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(IronTheme.secondaryText)
        .padding(.bottom, 4)
    }

    private var firstSessionCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(IronTheme.accentSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text("Your first session")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("The next time you train this exercise, Iron will place your previous sets here for quick comparison.")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func previousSessionCard(_ session: WorkoutExercise) -> some View {
        let sets = session.workoutSets?.array as? [WorkoutSet] ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Workout.dateFormatter.string(from: session.workout?.start, fallback: "Unknown date"))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("\(sets.count) sets · \(previousSessionResult(session))")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer()

                if sets.contains(where: { $0.isPersonalRecord ?? false }) {
                    Image(systemName: "medal.fill")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.success)
                }
            }

            if let comment = session.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Text("SET")
                    .frame(width: 34)
                Text("RESULT")
                Spacer()
                Text("EFFORT")
            }
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundColor(IronTheme.tertiaryText)

            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    if index > 0 {
                        IronHairline(opacity: 0.42)
                            .padding(.leading, 44)
                    }

                    HStack(spacing: 10) {
                        Text(set.tagValue?.title.first.map(String.init) ?? "\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(set.tagValue?.color ?? IronTheme.primaryText)
                            .frame(width: 34, height: 32)
                            .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))

                        Text(set.resultTitle(weightUnit: settingsStore.weightUnit))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundColor(IronTheme.primaryText)

                        Spacer()

                        if let rpe = set.rpeValue {
                            Text("RPE \(String(format: "%g", rpe))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundColor(IronTheme.secondaryText)
                        }

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
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 16)
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

    private var restTimerMenu: some View {
        Button(action: { showingRestTimerEditor = true }) {
            Image(systemName: "timer")
        }
        .accessibilityLabel("Rest timer")
        .accessibilityHint("Opens a radial rest-duration picker")
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
        workoutExercise.restTimerDurationValue = duration
        save()
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
        let set = WorkoutSet.create(context: managedObjectContext)
        set.workoutExercise = workoutExercise

        if let previous = workoutSets.dropLast().last {
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
        save()
    }

    private func copyTrackingValues(from source: WorkoutSet, to destination: WorkoutSet) {
        if let duration = source.durationValue, source.distanceValue == nil {
            destination.durationValue = duration
            destination.weightValue = 0
            destination.repetitionsValue = 0
        } else {
            destination.weightValue = source.weightValue
            destination.repetitionsValue = source.repetitionsValue
        }
        destination.rpeValue = source.rpeValue
        destination.tagValue = source.tagValue
    }

    private func toggleCompleted(_ set: WorkoutSet) {
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
        } else {
            set.isCompleted = true
            set.completedAt = Date()
            workoutExercise.workout?.start = workoutExercise.workout?.start ?? Date()

            if isCurrentWorkout {
                restTimerStore.restTimerDuration = restTimerDuration
                restTimerStore.restTimerStart = Date()
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
            }
        }
        save()
    }

    private func delete(_ set: WorkoutSet) {
        workoutExercise.removeFromWorkoutSets(set)
        managedObjectContext.delete(set)
        save()
    }

    private func save() {
        managedObjectContext.saveOrCrash()
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
