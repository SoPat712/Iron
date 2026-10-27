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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var exerciseStore: ExerciseStore

    private let exercises: [Exercise]
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
        recentExercises: [Exercise] = [],
        title: String = "Add Exercise",
        actionTitle: String = "Add",
        maximumSelectionCount: Int? = nil,
        onDismiss: (() -> Void)? = nil,
        shouldDismiss: @escaping () -> Bool = { true },
        onAdd: @escaping ([Exercise]) -> Void
    ) {
        self.exercises = exercises
        // Kept as an initializer argument for existing callers. Recents now
        // come from the live shared cache, rather than a presentation snapshot.
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

    private var matchingExercises: [Exercise] {
        let matches = ExerciseStore.filter(exercises: availableExercises, using: search)
            .filter { selectedMuscleGroup == nil || $0.muscleGroup == selectedMuscleGroup }
            .filter { selectedEquipment == nil || $0.equipment.contains(selectedEquipment!) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return exerciseStore.orderedByRecency(matches)
    }

    private var recentExercises: [Exercise] {
        matchingExercises.filter { exerciseStore.lastPerformedDates[$0.uuid] != nil }
    }

    /// Search and filters use a flat list with exactly the same recency order.
    private var showsRecentSection: Bool {
        search.isEmpty
            && selectedMuscleGroup == nil
            && selectedEquipment == nil
            && !recentExercises.isEmpty
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
    
    static func loadRecentExercises(context: NSManagedObjectContext, exercises: [Exercise], maxCount: Int = .max) -> [Exercise] {
        guard maxCount > 0 else { return [] }
        // Compatibility for CurrentWorkoutView and other existing callers.
        // No history fetch runs on presentation or on a search keystroke.
        let store = ExerciseStore.shared
        store.observeWorkoutHistory(in: context)
        return Array(store.orderedByRecency(exercises)
            .filter { store.lastPerformedDates[$0.uuid] != nil }
            .prefix(maxCount))
    }

    var body: some View {
        NavigationStack {
            List {
                if matchingExercises.isEmpty {
                    emptyState
                } else if showsRecentSection {
                    Section("Recent") {
                        ForEach(recentExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }

                    let recentSet = Set(recentExercises)
                    Section("All Exercises") {
                        ForEach(matchingExercises.filter { !recentSet.contains($0) }) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                } else {
                    Section {
                        ForEach(matchingExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    } footer: {
                        Text("\(matchingExercises.count) exercises")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: resetAndDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle, action: addSelectedExercises)
                        .fontWeight(.semibold)
                        .disabled(exerciseSelectorSelection.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        Picker("Muscle", selection: $selectedMuscleGroup) {
                            Text("All Muscles").tag(String?.none)
                            ForEach(muscleGroups, id: \.self) { group in
                                Text(group.capitalized).tag(String?.some(group))
                            }
                        }
                    } label: {
                        Text(selectedMuscleGroup?.capitalized ?? "Muscle")
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Filter by muscle group")

                    Menu {
                        Picker("Equipment", selection: $selectedEquipment) {
                            Text("All Equipment").tag(String?.none)
                            ForEach(equipment, id: \.self) { item in
                                Text(item.capitalized).tag(String?.some(item))
                            }
                        }
                    } label: {
                        Text(selectedEquipment?.capitalized ?? "Equipment")
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Filter by equipment")

                    Spacer()

                    Button("Create Exercise", systemImage: "plus") {
                        showingCreateExercise = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showingCreateExercise) {
            CreateCustomExerciseSheet(
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
    private var emptyState: some View {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label("No matching exercises", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Try a different muscle group or equipment.")
            } actions: {
                Button("Clear Filters") {
                    selectedMuscleGroup = nil
                    selectedEquipment = nil
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let selectionNumber = exerciseSelectorSelection.firstIndex(of: exercise).map { $0 + 1 }
        let muscleTitle = exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized
        let equipmentTitle = exercise.equipment.first?.capitalized

        return HStack(spacing: 12) {
            Button(action: { toggle(exercise) }) {
                HStack(spacing: 12) {
                    selectionIndicator(number: selectionNumber)

                    ExerciseDiagramThumbnail(exercise: exercise, size: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.title)
                            .font(.headline)
                            .foregroundStyle(IronTheme.primaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 2) {
                                    ExerciseLibraryTag(title: muscleTitle)
                                    if let equipmentTitle {
                                        ExerciseLibraryTag(title: equipmentTitle)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                HStack(spacing: 6) {
                                    ExerciseLibraryTag(title: muscleTitle)
                                    if let equipmentTitle {
                                        ExerciseLibraryTag(title: equipmentTitle)
                                    }
                                }
                                .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                    if let lastPerformed = exerciseStore.lastPerformedDates[exercise.uuid],
                       !dynamicTypeSize.isAccessibilitySize {
                        ExerciseRecencyCaption(date: lastPerformed)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { detailExercise = exercise }) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("View \(exercise.title) details")
        }
    }

    /// Ordered selection mirrors Photos: a numbered fill when the order matters,
    /// a plain checkmark when only one exercise can be chosen.
    @ViewBuilder
    private func selectionIndicator(number: Int?) -> some View {
        if let number {
            if maximumSelectionCount == 1 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            } else {
                Text("\(number)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.tint))
                    .accessibilityLabel("Selection \(number)")
            }
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Not selected")
        }
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
