//
//  AddExercisesSheet.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 03.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit
import CoreData

struct AddExercisesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore

    private let exercises: [Exercise]
    private let recentExercises: [Exercise]
    private let usesModalSurface: Bool
    private let title: String
    private let actionTitle: String
    private let maximumSelectionCount: Int?
    let onAdd: ([Exercise]) -> Void
    private let onDismiss: (() -> Void)?
    private let shouldDismiss: () -> Bool

    @State private var exerciseSelectorSelection: [Exercise] = []
    @State private var search = ""
    @State private var selectedMuscleGroup: String?
    @State private var selectedEquipment: String?
    @State private var detailExercise: Exercise?
    @State private var showingCreateExercise = false

    init(
        exercises: [Exercise],
        recentExercises: [Exercise],
        usesModalSurface: Bool = false,
        title: String = "Add Exercise",
        actionTitle: String = "Add",
        maximumSelectionCount: Int? = nil,
        onDismiss: (() -> Void)? = nil,
        shouldDismiss: @escaping () -> Bool = { true },
        onAdd: @escaping ([Exercise]) -> Void
    ) {
        self.exercises = exercises
        self.recentExercises = recentExercises
        self.usesModalSurface = usesModalSurface
        self.title = title
        self.actionTitle = actionTitle
        self.maximumSelectionCount = maximumSelectionCount
        self.onDismiss = onDismiss
        self.shouldDismiss = shouldDismiss
        self.onAdd = onAdd
    }

    private var muscleGroups: [String] {
        Array(Set(availableExercises.map { $0.muscleGroup })).sorted()
    }

    private var equipment: [String] {
        var counts: [String: Int] = [:]
        availableExercises.forEach { exercise in
            exercise.equipment.forEach { counts[$0, default: 0] += 1 }
        }
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    private var availableExercises: [Exercise] {
        exerciseStore.shownExercises.isEmpty ? exercises : exerciseStore.shownExercises
    }

    private var equipmentPopupActions: [IronPopupAction] {
        [IronPopupAction(
            title: "All Equipment",
            systemImage: "dumbbell.fill",
            isSelected: selectedEquipment == nil
        ) { selectedEquipment = nil }] + equipment.map { item in
            IronPopupAction(
                id: "equipment-\(item)",
                title: item.capitalized,
                systemImage: "dumbbell",
                isSelected: selectedEquipment == item
            ) { selectedEquipment = item }
        }
    }

    private var musclePopupActions: [IronPopupAction] {
        [IronPopupAction(
            title: "All Muscles",
            systemImage: "figure.strengthtraining.traditional",
            isSelected: selectedMuscleGroup == nil
        ) { selectedMuscleGroup = nil }] + muscleGroups.map { group in
            IronPopupAction(
                id: "muscle-\(group)",
                title: group.capitalized,
                systemImage: "figure.strengthtraining.traditional",
                isSelected: selectedMuscleGroup == group
            ) { selectedMuscleGroup = group }
        }
    }

    private var filteredExercises: [Exercise] {
        let matches = ExerciseStore.filter(exercises: availableExercises, using: search)
            .filter { selectedMuscleGroup == nil || $0.muscleGroup == selectedMuscleGroup }
            .filter { selectedEquipment == nil || $0.equipment.contains(selectedEquipment!) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        guard search.isEmpty, selectedMuscleGroup == nil, selectedEquipment == nil else { return matches }
        let recentSet = Set(recentExercises)
        return recentExercises + matches.filter { !recentSet.contains($0) }
    }

    private func resetAndDismiss() {
        guard shouldDismiss() else { return }
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
        self.exerciseSelectorSelection.removeAll()
        self.search = ""
    }
    
    static func loadRecentExercises(context: NSManagedObjectContext, exercises: [Exercise], maxCount: Int = 7) -> [Exercise] {
        guard maxCount > 0 else { return [] }
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        guard let workouts = try? context.fetch(request) else { return [] }
        var recentExercises = [Exercise]()
        for workout in workouts {
            if let workoutExercises = workout.workoutExercises?.array as? [WorkoutExercise] {
                for workoutExercise in workoutExercises {
                    if let exercise = workoutExercise.exercise(in: exercises) {
                        if !recentExercises.contains(exercise) {
                            recentExercises.append(exercise)
                            if recentExercises.count >= maxCount {
                                return recentExercises
                            }
                        }
                    }
                }
            }
        }
        return recentExercises
    }

    var body: some View {
        NavigationStack {
            ZStack {
                shellBackground

                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            IronPopupMenu(title: "Equipment", actions: equipmentPopupActions) {
                                filterControl(
                                    title: selectedEquipment?.capitalized ?? "All Equipment",
                                    icon: "dumbbell.fill",
                                    active: selectedEquipment != nil
                                )
                            }

                            IronPopupMenu(title: "Muscle group", actions: musclePopupActions) {
                                filterControl(
                                    title: selectedMuscleGroup?.capitalized ?? "All Muscles",
                                    icon: "figure.strengthtraining.traditional",
                                    active: selectedMuscleGroup != nil
                                )
                            }
                        }
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    HStack {
                        Text(search.isEmpty && selectedMuscleGroup == nil && selectedEquipment == nil && !recentExercises.isEmpty
                             ? "Recent first"
                             : "\(filteredExercises.count) results")
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.secondaryText)
                        Spacer()
                        if !exerciseSelectorSelection.isEmpty {
                            HStack(spacing: 8) {
                                Text("\(exerciseSelectorSelection.count) selected")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(IronTheme.secondaryText)

                                Button(action: addSelectedExercises) {
                                    Text(confirmationTitle)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityHint("Adds the selected exercises to the workout")
                            }
                        } else {
                            Button(action: { showingCreateExercise = true }) {
                                Label("Create", systemImage: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(IronTheme.accent)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Create custom exercise")
                        }
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.vertical, 8)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredExercises) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: resetAndDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        confirmationTitle,
                        action: addSelectedExercises
                    )
                    .fontWeight(.semibold)
                    .disabled(exerciseSelectorSelection.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingCreateExercise) {
            CreateCustomExerciseSheet(
                usesModalSurface: usesModalSurface,
                onDismiss: { showingCreateExercise = false }
            )
            .environmentObject(exerciseStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailExercise) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .ironScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { detailExercise = nil }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var shellBackground: some View {
        if usesModalSurface {
            IronModalBackground()
        } else {
            IronScreenBackground()
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let selected = exerciseSelectorSelection.contains(exercise)
        let selectionNumber = exerciseSelectorSelection.firstIndex(of: exercise).map { $0 + 1 }
        return HStack(spacing: 12) {
            Button(action: { toggle(exercise) }) {
                HStack(spacing: 13) {
                    ExerciseDiagramThumbnail(exercise: exercise, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(2)
                        Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                    }
                    Spacer()
                    if let selectionNumber = selectionNumber {
                        Text("\(selectionNumber)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(IronTheme.onAccent)
                            .frame(width: 25, height: 25)
                            .background(Circle().fill(IronTheme.accent))
                            .accessibilityLabel("Selection \(selectionNumber)")
                    } else {
                        Image(systemName: "circle")
                            .font(.title3.weight(.bold))
                            .foregroundColor(IronTheme.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { detailExercise = exercise }) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundColor(IronTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(exercise.title) details")
        }
        .ironTonalListRow(isSelected: selected)
    }

    private func toggle(_ exercise: Exercise) {
        if let index = exerciseSelectorSelection.firstIndex(of: exercise) {
            exerciseSelectorSelection.remove(at: index)
        } else if maximumSelectionCount == 1 {
            exerciseSelectorSelection = [exercise]
        } else {
            exerciseSelectorSelection.append(exercise)
        }

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }

    private func addSelectedExercises() {
        guard !exerciseSelectorSelection.isEmpty else { return }
        onAdd(exerciseSelectorSelection)
        resetAndDismiss()
    }

    private var confirmationTitle: String {
        guard !exerciseSelectorSelection.isEmpty else { return actionTitle }
        return maximumSelectionCount == 1
            ? actionTitle
            : "\(actionTitle) \(exerciseSelectorSelection.count)"
    }

    private func filterControl(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(active ? IronTheme.accent : IronTheme.secondaryText)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundColor(IronTheme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(active ? IronTheme.accentSoft : IronTheme.raisedSurface)
        )
    }
}

struct AddExercisesSheet_Previews: PreviewProvider {
    static var previews: some View {
//        Color.clear.sheet(isPresented: .constant(true)) {
        AddExercisesSheet(
            exercises: ExerciseStore.shared.shownExercises,
            recentExercises: [],
            onAdd: { _ in }
        )
        .environmentObject(ExerciseStore.shared)
//        }
    }
}
