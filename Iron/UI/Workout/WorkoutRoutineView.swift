//
//  WorkoutRoutineView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 21.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

/// A focused editor for one saved workout plan.
///
/// Editable values stay close to the exercise they describe, using a dense
/// separator-led canvas with Cupertino controls for direct input.
struct WorkoutRoutineView: View {
    @EnvironmentObject var exerciseStore: ExerciseStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var workoutRoutine: WorkoutRoutine

    let isNew: Bool
    let autosavesChanges: Bool
    let onCancel: (() -> Void)?
    let onCommit: (() -> Void)?

    @State private var showExerciseSelector = false
    @State private var workoutRoutineTitleInput: String?
    @State private var workoutRoutineCommentInput: String?
    @State private var routineExerciseToDelete: WorkoutRoutineExercise?

    init(
        workoutRoutine: WorkoutRoutine,
        isNew: Bool = false,
        autosavesChanges: Bool = true,
        onCancel: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self.workoutRoutine = workoutRoutine
        self.isNew = isNew
        self.autosavesChanges = autosavesChanges
        self.onCancel = onCancel
        self.onCommit = onCommit
    }

    private var workoutRoutineTitle: Binding<String> {
        Binding(
            // A plan without a custom title still has a real fallback title
            // (Workout A, Workout B, …). Present that value as editable text instead
            // of making the field look accidentally empty.
            get: { workoutRoutineTitleInput ?? workoutRoutine.displayTitle },
            set: { workoutRoutineTitleInput = $0 }
        )
    }

    private var workoutRoutineComment: Binding<String> {
        Binding(
            get: { workoutRoutineCommentInput ?? workoutRoutine.comment ?? "" },
            set: { workoutRoutineCommentInput = $0 }
        )
    }

    private var workoutRoutineExercises: [WorkoutRoutineExercise] {
        workoutRoutine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
    }

    private var exerciseSelectorSheet: some View {
        AddExercisesSheet(
            exercises: exerciseStore.shownExercises,
            recentExercises: AddExercisesSheet.loadRecentExercises(
                context: managedObjectContext,
                exercises: exerciseStore.shownExercises
            ),
            onAdd: { selection in
                for exercise in selection {
                    let routineExercise = WorkoutRoutineExercise.create(context: managedObjectContext)
                    routineExercise.workoutRoutine = workoutRoutine
                    routineExercise.exerciseUuid = exercise.uuid
                }
                recordDraftChange()
            }
        )
    }

    private func recordDraftChange() {
        managedObjectContext.processPendingChanges()
        if autosavesChanges {
            managedObjectContext.saveOrCrash()
        }
    }

    private func saveRoutineFields() {
        if let input = workoutRoutineTitleInput {
            let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
            workoutRoutineTitleInput = title
            workoutRoutine.title = title.isEmpty ? nil : title
        }
        if let input = workoutRoutineCommentInput {
            let comment = input.trimmingCharacters(in: .whitespacesAndNewlines)
            workoutRoutineCommentInput = comment
            workoutRoutine.comment = comment.isEmpty ? nil : comment
        }
        recordDraftChange()
    }

    private func sets(for routineExercise: WorkoutRoutineExercise) -> [WorkoutRoutineSet] {
        routineExercise.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
    }

    private func addSet(to routineExercise: WorkoutRoutineExercise) {
        let previousSet = sets(for: routineExercise).last
        let routineSet = WorkoutRoutineSet.create(context: managedObjectContext)
        routineSet.workoutRoutineExercise = routineExercise
        if let duration = previousSet?.durationValue {
            routineSet.durationValue = duration
        } else {
            routineSet.minRepetitionsValue = previousSet?.minRepetitionsValue ?? 5
            routineSet.maxRepetitionsValue = previousSet?.maxRepetitionsValue ?? 5
            routineSet.weightValue = previousSet?.weightValue
        }
        recordDraftChange()
    }

    private func deleteSet(_ routineSet: WorkoutRoutineSet) {
        routineSet.workoutRoutineExercise?.removeFromWorkoutRoutineSets(routineSet)
        managedObjectContext.delete(routineSet)
        recordDraftChange()
    }

    private func moveSet(in routineExercise: WorkoutRoutineExercise, from source: Int, to destination: Int) {
        let currentSets = sets(for: routineExercise)
        guard source != destination,
              currentSets.indices.contains(source),
              currentSets.indices.contains(destination) else { return }

        var reordered = currentSets
        let routineSet = reordered.remove(at: source)
        reordered.insert(routineSet, at: destination)
        routineExercise.workoutRoutineSets = NSOrderedSet(array: reordered)
        recordDraftChange()
    }

    private func deleteExercise(_ routineExercise: WorkoutRoutineExercise) {
        routineExercise.workoutRoutine?.removeFromWorkoutRoutineExercises(routineExercise)
        managedObjectContext.delete(routineExercise)
        recordDraftChange()
    }

    private func moveExercise(from source: Int, to destination: Int) {
        guard source != destination,
              workoutRoutineExercises.indices.contains(source),
              workoutRoutineExercises.indices.contains(destination) else { return }

        var reordered = workoutRoutineExercises
        let routineExercise = reordered.remove(at: source)
        reordered.insert(routineExercise, at: destination)
        workoutRoutine.workoutRoutineExercises = NSOrderedSet(array: reordered)
        recordDraftChange()
    }

    private func exerciseCard(_ routineExercise: WorkoutRoutineExercise, index: Int) -> some View {
        WorkoutRoutineExerciseCard(
            routineExercise: routineExercise,
            exercise: routineExercise.exercise(in: exerciseStore.exercises),
            sets: sets(for: routineExercise),
            index: index,
            exerciseCount: workoutRoutineExercises.count,
            onSave: recordDraftChange,
            onMoveUp: { moveExercise(from: index, to: index - 1) },
            onMoveDown: { moveExercise(from: index, to: index + 1) },
            onDelete: { routineExerciseToDelete = routineExercise },
            onAddSet: { addSet(to: routineExercise) },
            onDeleteSet: { deleteSet($0) },
            onMoveSet: { source, destination in
                moveSet(in: routineExercise, from: source, to: destination)
            }
        )
    }

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WORKOUT DETAILS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(IronTheme.secondaryText)

                        TextField("Workout title", text: workoutRoutineTitle, onEditingChanged: { isEditing in
                            if !isEditing { saveRoutineFields() }
                        })
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(IronTheme.primaryText)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 52)

                        TextEditor(text: workoutRoutineComment)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(IronTheme.primaryText)
                            .frame(minHeight: 72, maxHeight: 108)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                    .fill(IronTheme.raisedSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                    .stroke(IronTheme.outline.opacity(0.45), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if workoutRoutineComment.wrappedValue.isEmpty {
                                    Text("Workout notes")
                                        .font(.system(size: 15))
                                        .foregroundColor(IronTheme.tertiaryText)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                    .overlay(IronHairline(opacity: 0.48), alignment: .bottom)

                    IronSectionTitle(
                        title: "Exercises",
                        detail: workoutRoutineExercises.isEmpty ? nil : "\(workoutRoutineExercises.count)"
                    )
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    if workoutRoutineExercises.isEmpty {
                        emptyExercisesCard
                            .padding(.horizontal, IronTheme.horizontalPadding)
                    } else {
                        ForEach(Array(workoutRoutineExercises.enumerated()), id: \.element.id) { index, routineExercise in
                            exerciseCard(routineExercise, index: index)
                        }
                    }
                }
                // The primary Add Exercise action is inset over the bottom of
                // the editor. Keep the final Add Set control fully scrollable
                // above it instead of letting the two actions visually stack.
                .padding(.bottom, 104)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: { showExerciseSelector = true }) {
                Label("Add Exercise", systemImage: "plus")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(IronTheme.background.opacity(0.96))
            .overlay(IronHairline(), alignment: .top)
        }
        .navigationTitle(isNew ? "New Workout" : "Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancelEditor)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Update", action: commitEditor)
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showExerciseSelector) {
            exerciseSelectorSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(IronTheme.modalSurface)
        }
        .confirmationDialog(
            "Remove exercise from workout?",
            isPresented: Binding(
                get: { routineExerciseToDelete != nil },
                set: { if !$0 { routineExerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                guard let routineExercise = routineExerciseToDelete else { return }
                routineExerciseToDelete = nil
                deleteExercise(routineExercise)
            }
            Button("Cancel", role: .cancel) {
                routineExerciseToDelete = nil
            }
        } message: {
            Text("Its target sets, rest timer, and workout notes will be removed. Completed workout history is not affected.")
        }
        .ironScreen()
    }

    private func cancelEditor() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func commitEditor() {
        saveRoutineFields()
        if let onCommit {
            onCommit()
        } else {
            managedObjectContext.saveOrCrash()
            dismiss()
        }
    }

    private var emptyExercisesCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(IronTheme.accent)
            Text("No exercises yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Add an exercise to start setting targets and rest times.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .stroke(IronTheme.outline.opacity(0.36), lineWidth: 1)
        )
    }
}

private struct WorkoutRoutineExerciseCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var routineExercise: WorkoutRoutineExercise
    @State private var showingRestTimerEditor = false
    let exercise: Exercise?
    let sets: [WorkoutRoutineSet]
    let index: Int
    let exerciseCount: Int
    let onSave: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutRoutineSet) -> Void
    let onMoveSet: (Int, Int) -> Void

    private var notes: Binding<String> {
        Binding(
            get: { routineExercise.comment ?? "" },
            set: { routineExercise.comment = $0.isEmpty ? nil : $0 }
        )
    }

    private var restTimerTitle: String {
        guard let duration = routineExercise.restTimerDurationValue,
              let formatted = restTimerDurationFormatter.string(from: duration) else {
            return "Workout default"
        }
        return "Rest \(formatted)"
    }

    private var usesDuration: Bool {
        sets.contains { $0.durationValue != nil }
    }

    private var workoutDefaultRestTimerDuration: TimeInterval {
        switch exercise?.type {
        case .barbell: return settingsStore.defaultRestTimeBarbellBased
        case .dumbbell: return settingsStore.defaultRestTimeDumbbellBased
        default: return settingsStore.defaultRestTime
        }
    }

    private var trackingTitle: String {
        usesDuration ? "Track duration" : "Track weight & reps"
    }

    private var exercisePopupActions: [IronPopupAction] {
        var actions: [IronPopupAction] = []
        if index > 0 {
            actions.append(IronPopupAction(title: "Move Up", systemImage: "arrow.up", action: onMoveUp))
        }
        if index < exerciseCount - 1 {
            actions.append(IronPopupAction(title: "Move Down", systemImage: "arrow.down", action: onMoveDown))
        }
        actions.append(IronPopupAction(
            title: "Delete Exercise",
            systemImage: "trash",
            role: .destructive,
            action: onDelete
        ))
        return actions
    }

    private var trackingPopupActions: [IronPopupAction] {
        [
            IronPopupAction(
                title: "Weight & Reps",
                systemImage: "dumbbell.fill",
                isSelected: !usesDuration
            ) {
                setTrackingMode(usesDuration: false)
            },
            IronPopupAction(
                title: "Duration",
                systemImage: "stopwatch.fill",
                isSelected: usesDuration
            ) {
                setTrackingMode(usesDuration: true)
            }
        ]
    }

    private func setTrackingMode(usesDuration: Bool) {
        for set in sets {
            if usesDuration {
                set.durationValue = set.durationValue ?? 60
                set.weightValue = nil
                set.minRepetitionsValue = nil
                set.maxRepetitionsValue = nil
            } else {
                set.durationValue = nil
                if set.minRepetitionsValue == nil, set.maxRepetitionsValue == nil {
                    set.minRepetitionsValue = 5
                    set.maxRepetitionsValue = 5
                }
            }
        }
        onSave()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let exercise = exercise {
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise).ironScreen()) {
                        HStack(spacing: 11) {
                            ExerciseDiagramThumbnail(exercise: exercise, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(IronTheme.accent)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 11) {
                        Circle()
                            .fill(IronTheme.accentSoft)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "dumbbell.fill")
                                    .foregroundColor(IronTheme.accent)
                            )
                        Text("Unknown Exercise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(IronTheme.primaryText)
                    }
                }

                Spacer(minLength: 4)

                IronPopupMenu(title: "Exercise actions", actions: exercisePopupActions) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                        .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                }
                .accessibilityLabel("Actions for \(exercise?.title ?? "exercise")")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("EXERCISE NOTES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundColor(IronTheme.secondaryText)
                TextEditor(text: notes)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14))
                    .foregroundColor(IronTheme.primaryText)
                    .frame(minHeight: 48, maxHeight: 78)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.raisedSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .stroke(IronTheme.outline.opacity(0.45), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if notes.wrappedValue.isEmpty {
                            Text("Add a cue or setup note")
                                .font(.system(size: 14))
                                .foregroundColor(IronTheme.tertiaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Button(action: { showingRestTimerEditor = true }) {
                HStack(spacing: 7) {
                    Image(systemName: "timer")
                    Text(restTimerTitle)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(IronTheme.accent)
                .frame(minHeight: IronTheme.controlHeight)
                .padding(.horizontal, 12)
                .background(Capsule(style: .continuous).fill(IronTheme.accentSoft))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a radial rest-duration picker")

            if !sets.isEmpty {
                IronPopupMenu(title: "Track sets by", actions: trackingPopupActions, arrowEdge: .bottom) {
                    HStack(spacing: 7) {
                        Image(systemName: usesDuration ? "stopwatch.fill" : "dumbbell.fill")
                        Text(trackingTitle)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .frame(minHeight: IronTheme.controlHeight)
                    .padding(.horizontal, 12)
                    .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))
                    .contentShape(Rectangle())
                }
            }

            if sets.isEmpty {
                Text("No target sets")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(IronTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Text("SET")
                        .frame(width: 45, alignment: .center)
                    if usesDuration {
                        Text("DURATION")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text(settingsStore.weightUnit.unit.symbol.uppercased())
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("REPS")
                            .frame(width: 78, alignment: .center)
                    }
                    Text("")
                        .frame(width: 44)
                }
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundColor(IronTheme.secondaryText)

                ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, routineSet in
                    WorkoutRoutineSetRow(
                        routineSet: routineSet,
                        index: setIndex,
                        usesDuration: usesDuration,
                        onSave: onSave,
                        onDelete: { onDeleteSet(routineSet) },
                        onMoveUp: { onMoveSet(setIndex, setIndex - 1) },
                        onMoveDown: { onMoveSet(setIndex, setIndex + 1) },
                        setCount: sets.count
                    )
                }
            }

            Button(action: onAddSet) {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(IronSecondaryButtonStyle())
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(IronTheme.background)
        .overlay(IronHairline(opacity: 0.48), alignment: .bottom)
        .onDisappear(perform: onSave)
        .sheet(isPresented: $showingRestTimerEditor) {
            RestTimerConfigurationSheet(
                title: "Rest timer",
                subtitle: "Recovery after each completed set",
                initialDuration: routineExercise.restTimerDurationValue ?? workoutDefaultRestTimerDuration,
                secondaryActionTitle: routineExercise.restTimerDurationValue == nil
                    ? "Keep workout default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")"
                    : "Use workout default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")",
                onSecondaryAction: {
                    routineExercise.restTimerDurationValue = nil
                    onSave()
                },
                onApply: { duration in
                    routineExercise.restTimerDurationValue = duration
                    onSave()
                }
            )
        }
    }
}

private struct WorkoutRoutineSetRow: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var routineSet: WorkoutRoutineSet
    @State private var weightInput: String?
    @State private var repetitionsInput: String?
    @State private var showingDurationPicker = false
    @State private var showingPlateCalculator = false
    @FocusState private var focusedField: EntryField?
    let index: Int
    let usesDuration: Bool
    let onSave: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let setCount: Int

    private enum EntryField: Hashable {
        case weight
        case repetitions
    }

    private var displayedWeightTitle: String {
        guard let weight = routineSet.weightValue else { return "" }
        let displayWeight = WeightUnit.convert(
            weight: weight,
            from: .metric,
            to: settingsStore.weightUnit
        )
        return settingsStore.weightUnit.numberFormatter.string(from: NSNumber(value: displayWeight)) ?? ""
    }

    private var weightText: Binding<String> {
        Binding(
            get: { weightInput ?? displayedWeightTitle },
            set: { input in
                let sanitized = sanitizedDecimalInput(input)
                guard input.isEmpty || !sanitized.isEmpty else { return }
                weightInput = sanitized
                updateWeight(from: sanitized)
            }
        )
    }

    private var repetitionsText: Binding<String> {
        Binding(
            get: { repetitionsInput ?? repetitionsTitle },
            set: { input in
                let sanitized = sanitizedIntegerInput(input)
                guard input.isEmpty || !sanitized.isEmpty else { return }
                repetitionsInput = sanitized
                updateRepetitions(from: sanitized)
            }
        )
    }

    private var plateCalculatorTarget: Double {
        max(
            routineSet.weightValue.map {
                WeightUnit.convert(weight: $0, from: .metric, to: settingsStore.weightUnit)
            } ?? 0,
            settingsStore.weightUnit.barbellWeight
        )
    }

    private func updateWeight(from input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            routineSet.weightValue = nil
            return
        }
        let parsed = settingsStore.weightUnit.numberFormatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let parsed = parsed else { return }
        routineSet.weightValue = WeightUnit.convert(
            weight: min(max(parsed, 0), maximumDisplayWeight),
            from: settingsStore.weightUnit,
            to: .metric
        )
    }

    private var maximumDisplayWeight: Double {
        WeightUnit.convert(
            weight: WorkoutSet.MAX_WEIGHT,
            from: .metric,
            to: settingsStore.weightUnit
        )
    }

    private func sanitizedDecimalInput(_ proposedValue: String) -> String {
        let formatter = settingsStore.weightUnit.numberFormatter
        let decimalSeparator = formatter.decimalSeparator
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

        if let value = formatter.number(from: result)?.doubleValue,
           value > maximumDisplayWeight {
            return formatter.string(from: NSNumber(value: maximumDisplayWeight)) ?? result
        }
        return result
    }

    private func sanitizedIntegerInput(_ proposedValue: String) -> String {
        let digits = proposedValue.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(WorkoutSet.MAX_REPETITIONS)))
    }

    private var repetitionsTitle: String {
        if let min = routineSet.minRepetitionsValue, let max = routineSet.maxRepetitionsValue {
            return min == max ? "\(max)" : "\(min)-\(max)"
        }
        if let min = routineSet.minRepetitionsValue { return "\(min)+" }
        if let max = routineSet.maxRepetitionsValue { return "<\(max)" }
        return ""
    }

    private func updateRepetitions(from input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            routineSet.minRepetitionsValue = nil
            routineSet.maxRepetitionsValue = nil
            return
        }

        guard let parsed = Int(value) else { return }
        let repetitions = Int16(min(max(parsed, 0), Int(WorkoutSet.MAX_REPETITIONS)))
        routineSet.minRepetitionsValue = repetitions
        routineSet.maxRepetitionsValue = repetitions
    }

    private var tagTitle: String {
        routineSet.tagValue?.title.capitalized ?? "Tag"
    }

    private var tagColor: Color {
        switch routineSet.tagValue {
        case .warmUp: return IronTheme.warning
        case .dropSet: return IronTheme.accent
        default: return IronTheme.secondaryText
        }
    }

    private var setPopupActions: [IronPopupAction] {
        var actions: [IronPopupAction] = []
        if index > 0 {
            actions.append(IronPopupAction(title: "Move Set Up", systemImage: "arrow.up", action: onMoveUp))
        }
        if index < setCount - 1 {
            actions.append(IronPopupAction(title: "Move Set Down", systemImage: "arrow.down", action: onMoveDown))
        }

        actions.append(IronPopupAction(
            title: "Normal Set",
            systemImage: "number",
            isSelected: routineSet.tagValue == nil
        ) {
            routineSet.tagValue = nil
            onSave()
        })
        actions += WorkoutRoutineSet.supportedTags.map { tag in
            IronPopupAction(
                id: "tag-\(tag.rawValue)",
                title: tag.title.capitalized,
                systemImage: tagIcon(for: tag),
                isSelected: routineSet.tagValue == tag
            ) {
                routineSet.tagValue = tag
                onSave()
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

    private func tagIcon(for tag: WorkoutSetTag) -> String {
        switch tag {
        case .warmUp: return "flame"
        case .dropSet: return "arrow.down.right"
        case .failure: return "bolt.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(routineSet.tagValue == .warmUp ? "W" : "\(index + 1)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundColor(routineSet.tagValue == .warmUp ? IronTheme.warning : IronTheme.primaryText)
                .frame(width: 45, height: IronTheme.controlHeight, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                        .fill(routineSet.tagValue == .warmUp ? IronTheme.warning.opacity(0.14) : IronTheme.raisedSurface)
                )

            if usesDuration {
                Button(action: { showingDurationPicker = true }) {
                    HStack(spacing: 7) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(IronTheme.accent)
                        Text(restTimerDurationFormatter.string(from: routineSet.durationValue ?? 60) ?? "1:00")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundColor(IronTheme.primaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(IronTheme.raisedSurface)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set duration")
            } else {
                TextField("—", text: weightText, onEditingChanged: { isEditing in
                    if isEditing {
                        weightInput = displayedWeightTitle
                    } else {
                        weightInput = nil
                        onSave()
                    }
                })
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .weight)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                        .fill(IronTheme.raisedSurface)
                )

                TextField("—", text: repetitionsText, onEditingChanged: { isEditing in
                    if isEditing {
                        repetitionsInput = repetitionsTitle
                    } else {
                        repetitionsInput = nil
                        onSave()
                    }
                })
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .repetitions)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9)
                .frame(width: 78)
                .frame(minHeight: IronTheme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                        .fill(IronTheme.raisedSurface)
                )
            }

            IronPopupMenu(title: "Set actions", actions: setPopupActions, arrowEdge: .bottom) {
                Image(systemName: routineSet.tagValue == nil ? "tag" : "tag.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tagColor)
                    .frame(width: 44, height: IronTheme.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.pillCornerRadius, style: .continuous)
                            .fill(IronTheme.raisedSurface)
                    )
            }
            .accessibilityLabel(tagTitle)
        }
        .sheet(isPresented: $showingDurationPicker) {
            IronDurationPickerSheet(
                initialDuration: routineSet.durationValue ?? 60
            ) { duration in
                routineSet.durationValue = duration
                onSave()
            }
        }
        .sheet(isPresented: $showingPlateCalculator) {
            IronUtilitySheet(
                title: "Plate calculator",
                subtitle: "Load each side of the bar",
                systemImage: "circle.grid.cross",
                onClose: { showingPlateCalculator = false }
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: plateCalculatorTarget,
                    onApply: { value in
                        routineSet.weightValue = WeightUnit.convert(
                            weight: value,
                            from: settingsStore.weightUnit,
                            to: .metric
                        )
                        weightInput = nil
                        onSave()
                        showingPlateCalculator = false
                    }
                )
            }
            .presentationDetents([.fraction(0.78)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(IronTheme.modalSurface)
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
    }

    private func openPlateCalculator() {
        focusedField = nil
        DispatchQueue.main.async {
            showingPlateCalculator = true
        }
    }
}

#if DEBUG
struct WorkoutRoutineView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutRoutineView(workoutRoutine: MockWorkoutData.metric.workoutRoutine)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
