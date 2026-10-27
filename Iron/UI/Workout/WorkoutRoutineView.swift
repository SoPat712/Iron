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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    var body: some View {
        List {
            Section("Workout Details") {
                TextField("Title", text: workoutRoutineTitle)
                    .textInputAutocapitalization(.words)
                    .onSubmit(saveRoutineFields)

                TextField("Notes", text: workoutRoutineComment, axis: .vertical)
                    .lineLimit(1...5)
            }

            if workoutRoutineExercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Exercises", systemImage: "dumbbell")
                    } description: {
                        Text("Add an exercise to start setting targets and rest times.")
                    } actions: {
                        Button("Add Exercise") { showExerciseSelector = true }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(Array(workoutRoutineExercises.enumerated()), id: \.element.id) { index, routineExercise in
                    WorkoutRoutineExerciseSection(
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
            }

            Section {
                Button("Add Exercise", systemImage: "plus") {
                    showExerciseSelector = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion), value: workoutRoutineExercises.map(\.objectID))
        .scrollDismissesKeyboard(.interactively)
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

}

private struct WorkoutRoutineExerciseSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        Section {
            if let exercise {
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    HStack(spacing: 12) {
                        ExerciseDiagramThumbnail(exercise: exercise, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.title)
                                .font(.headline)
                                .foregroundStyle(IronTheme.primaryText)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(IronTheme.secondaryText)
                        }
                    }
                }
            }

            TextField("Exercise Notes", text: notes, axis: .vertical)
                .lineLimit(1...4)
                .onSubmit(onSave)

            Button {
                showingRestTimerEditor = true
            } label: {
                LabeledContent("Rest Timer") {
                    Text(restTimerTitle)
                        .font(.ironMetric(.subheadline, weight: .semibold))
                        .foregroundStyle(IronTheme.metricTime)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }
            }
            .accessibilityHint("Opens the rest duration picker")

            if !sets.isEmpty {
                Picker("Target", selection: Binding(
                    get: { usesDuration },
                    set: { setTrackingMode(usesDuration: $0) }
                )) {
                    Text("Weight & Reps").tag(false)
                    Text("Duration").tag(true)
                }
            }

            ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, routineSet in
                WorkoutRoutineSetRow(
                    routineSet: routineSet,
                    index: setIndex,
                    usesDuration: usesDuration,
                    onSave: onSave,
                    onDelete: { onDeleteSet(routineSet) }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
            .onMove { source, destination in
                guard let from = source.first else { return }
                onMoveSet(from, destination > from ? destination - 1 : destination)
            }
            .onDelete { offsets in
                for offset in offsets where sets.indices.contains(offset) {
                    onDeleteSet(sets[offset])
                }
            }

            Button("Add Set", systemImage: "plus", action: onAddSet)
        } header: {
            HStack {
                Text(exercise?.title ?? "Unknown Exercise")
                Spacer()
                Menu {
                    if index > 0 {
                        Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                    }
                    if index < exerciseCount - 1 {
                        Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                    }
                    Divider()
                    Button("Delete Exercise", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .accessibilityLabel("Actions for \(exercise?.title ?? "exercise")")
            }
        } footer: {
            if sets.isEmpty {
                Text("No target sets yet.")
            }
        }
        .animation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion), value: sets.map(\.objectID))
        .onDisappear(perform: onSave)
        .sheet(isPresented: $showingRestTimerEditor) {
            RestTimerConfigurationSheet(
                title: "Rest Timer",
                subtitle: "Recovery after each completed set",
                initialDuration: routineExercise.restTimerDurationValue ?? workoutDefaultRestTimerDuration,
                secondaryActionTitle: "Use Workout Default · \(restTimerDurationFormatter.string(from: workoutDefaultRestTimerDuration) ?? "0:00")",
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        let formatter = focusedField == .weight ? settingsStore.weightUnit.numberFormatter : settingsStore.weightUnit.displayNumberFormatter
        return formatter.string(from: NSNumber(value: displayWeight)) ?? ""
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

    private var setLabel: String {
        switch routineSet.tagValue {
        case .warmUp: return "Warm-Up"
        case .dropSet: return "Drop Set"
        case .failure: return "Failure"
        case nil: return "Set \(index + 1)"
        }
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var setLabelView: some View {
        Text(setLabel)
            .font(.ironMetric(.subheadline, weight: .semibold))
            .foregroundStyle(IronTheme.metricSets)
            .lineLimit(1)
    }

    private var weightField: some View {
        TextField("—", text: weightText, onEditingChanged: { isEditing in
            if isEditing {
                weightInput = displayedWeightTitle
            } else {
                weightInput = nil
                onSave()
            }
        })
        .font(.ironMetric(.body, weight: .semibold))
        .foregroundStyle(IronTheme.metricVolume)
        .keyboardType(.decimalPad)
        .focused($focusedField, equals: .weight)
        .multilineTextAlignment(.trailing)
        .frame(width: usesAccessibilityLayout ? nil : 62)
        .frame(maxWidth: usesAccessibilityLayout ? .infinity : nil)
        .frame(minHeight: IronTheme.controlHeight)
        .accessibilityLabel("Weight")
    }

    private var repetitionsField: some View {
        TextField("—", text: repetitionsText, onEditingChanged: { isEditing in
            if isEditing {
                repetitionsInput = repetitionsTitle
            } else {
                repetitionsInput = nil
                onSave()
            }
        })
        .font(.ironMetric(.body, weight: .semibold))
        .foregroundStyle(IronTheme.metricSets)
        .keyboardType(.numberPad)
        .focused($focusedField, equals: .repetitions)
        .multilineTextAlignment(.trailing)
        .frame(width: usesAccessibilityLayout ? nil : 46)
        .frame(maxWidth: usesAccessibilityLayout ? .infinity : nil)
        .frame(minHeight: IronTheme.controlHeight)
        .accessibilityLabel("Repetitions")
    }

    private var weightUnitLabel: some View {
        Text(settingsStore.weightUnit.unit.symbol)
            .font(.caption)
            .foregroundStyle(IronTheme.secondaryText)
    }

    private var repetitionsUnitLabel: some View {
        Text("reps")
            .font(.caption)
            .foregroundStyle(IronTheme.secondaryText)
    }

    private var durationControl: some View {
        Button {
            showingDurationPicker = true
        } label: {
            Text(restTimerDurationFormatter.string(from: routineSet.durationValue ?? 60) ?? "1:00")
                .font(.ironMetric(.body, weight: .semibold))
                .foregroundStyle(IronTheme.metricTime)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: routineSet.durationValue)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .frame(minHeight: IronTheme.controlHeight)
        .accessibilityLabel("Set duration")
    }

    @ViewBuilder
    private var setValueControls: some View {
        if usesDuration {
            durationControl
        } else if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Weight") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        weightField
                        weightUnitLabel
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                LabeledContent("Repetitions") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        repetitionsField
                        repetitionsUnitLabel
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 6) {
                weightField
                weightUnitLabel
                repetitionsField
                repetitionsUnitLabel
            }
        }
    }

    var body: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 8) {
                    setLabelView
                    setValueControls
                }
            } else {
                HStack(spacing: 12) {
                    setLabelView
                    Spacer(minLength: 8)
                    setValueControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Picker("Set Type", selection: Binding(
                get: { routineSet.tagValue },
                set: { newValue in
                    routineSet.tagValue = newValue
                    onSave()
                }
            )) {
                Text("Normal").tag(WorkoutSetTag?.none)
                ForEach(WorkoutRoutineSet.supportedTags, id: \.self) { tag in
                    Text(tag.title.capitalized).tag(WorkoutSetTag?.some(tag))
                }
            }
            Divider()
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
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
                title: "Plate Calculator",
                subtitle: "",
                systemImage: "plusminus",
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .weight {
                        Button("Plate Calculator", systemImage: "plusminus", action: openPlateCalculator)
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Calculates the plates to load for this set")
                    }

                    Spacer()

                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
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
