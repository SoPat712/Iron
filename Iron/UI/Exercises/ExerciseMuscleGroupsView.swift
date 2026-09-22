//
//  ExerciseCategoryView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct ExerciseMuscleGroupsView : View {
    @EnvironmentObject var exerciseStore: ExerciseStore

    @State private var search = ""
    @State private var selectedMuscleGroup: String? = nil
    @State private var selectedEquipment: String? = nil
    @State private var showingCreateExercise = false
    @State private var showingHiddenExercises = false
    @State private var showingCustomExercises = false

    private var muscleGroups: [String] {
        Array(Set(exerciseStore.shownExercises.map { $0.muscleGroup })).sorted()
    }

    private var equipment: [String] {
        var counts: [String: Int] = [:]
        exerciseStore.shownExercises.forEach { exercise in
            exercise.equipment.forEach { counts[$0, default: 0] += 1 }
        }
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    private var filteredExercises: [Exercise] {
        ExerciseStore.filter(exercises: exerciseStore.shownExercises, using: search)
            .filter { selectedMuscleGroup == nil || $0.muscleGroup == selectedMuscleGroup }
            .filter { selectedEquipment == nil || $0.equipment.contains(selectedEquipment!) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            IronScreenBackground()
            if filteredExercises.isEmpty {
                ScrollView(showsIndicators: false) {
                    emptyExerciseState
                }
            } else {
                List {
                    Section {
                        ForEach(filteredExercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                ExerciseLibraryRow(exercise: exercise)
                            }
                        }
                    } header: {
                        if selectedEquipment != nil || selectedMuscleGroup != nil {
                            HStack {
                                Text(activeFilterSummary)
                                Spacer()
                                Button("Clear") {
                                    selectedEquipment = nil
                                    selectedMuscleGroup = nil
                                }
                                .textCase(nil)
                            }
                        }
                    } footer: {
                        Text("\(filteredExercises.count) exercises")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 28)
                }
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Muscle", selection: $selectedMuscleGroup) {
                        Text("All Muscles").tag(String?.none)
                        ForEach(muscleGroups, id: \.self) { group in
                            Text(group.capitalized).tag(String?.some(group))
                        }
                    }
                } label: {
                    Image(systemName: "figure.arms.open")
                        .foregroundStyle(selectedMuscleGroup == nil ? Color.primary : Color.accentColor)
                }
                .accessibilityLabel("Filter by muscle group")
                .accessibilityValue(selectedMuscleGroup?.capitalized ?? "All muscles")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Equipment", selection: $selectedEquipment) {
                        Text("All Equipment").tag(String?.none)
                        ForEach(equipment, id: \.self) { item in
                            Text(item.capitalized).tag(String?.some(item))
                        }
                    }
                } label: {
                    Image(systemName: "dumbbell")
                        .foregroundStyle(selectedEquipment == nil ? Color.primary : Color.accentColor)
                }
                .accessibilityLabel("Filter by equipment")
                .accessibilityValue(selectedEquipment?.capitalized ?? "All equipment")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Create Exercise", systemImage: "plus") {
                        showingCreateExercise = true
                    }

                    Section("Library") {
                        Button("Hidden (\(exerciseStore.hiddenExercises.count))", systemImage: "eye.slash") {
                            showingHiddenExercises = true
                        }
                        Button("Custom (\(exerciseStore.customExercises.count))", systemImage: "square.grid.2x2") {
                            showingCustomExercises = true
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create exercise or manage library")
            }
        }
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search 1,400+ exercises"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .sheet(isPresented: $showingCreateExercise) {
            CreateCustomExerciseSheet(onDismiss: { showingCreateExercise = false })
                .environmentObject(exerciseStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showingHiddenExercises) {
            HiddenExercisesView()
        }
        .navigationDestination(isPresented: $showingCustomExercises) {
            CustomExercisesView()
        }
    }

    private var emptyExerciseState: some View {
        let hasFilters = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedEquipment != nil
            || selectedMuscleGroup != nil

        return VStack(spacing: 10) {
            Image(systemName: hasFilters ? "magnifyingglass" : "eye.slash")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text(hasFilters ? "No matching exercises" : "No exercises available")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text(hasFilters
                ? "Try a different search or clear a filter."
                : "All exercises are hidden. Use Hidden above to restore one.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
    }

    private var activeFilterSummary: String {
        [selectedEquipment?.capitalized, selectedMuscleGroup?.capitalized]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct HiddenExercisesView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @State private var search = ""

    private var filteredExercises: [Exercise] {
        ExerciseStore.filter(exercises: exerciseStore.hiddenExercises, using: search)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            IronScreenBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("\(filteredExercises.count) hidden exercises")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(IronTheme.secondaryText)
                    Spacer()
                    if !search.isEmpty {
                        Button("Clear") { search = "" }
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.accent)
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.vertical, 8)

                ScrollView(showsIndicators: false) {
                    if filteredExercises.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredExercises) { exercise in
                                hiddenExerciseRow(exercise)
                            }
                        }
                        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
                    }
                }
            }
        }
        .ironDestinationScreen(title: "Hidden exercises")
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search hidden exercises"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func hiddenExerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 10) {
            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                HStack(spacing: 13) {
                    ExerciseDiagramThumbnail(exercise: exercise)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(2)
                        Text(exercise.primaryMuscleCommonName.first?.capitalized
                             ?? exercise.muscleGroup.capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    exerciseStore.show(exercise: exercise)
                }
            } label: {
                Label("Restore", systemImage: "eye")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(IronCompactPillButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHint("Returns this exercise to the main library")
        }
        .ironTonalListRow()
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "eye")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text(hasSearch ? "No matching hidden exercises" : "No hidden exercises")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text(hasSearch
                ? "Try a different search."
                : "Exercises you hide from the library will appear here.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
    }
}

private struct AllExercisesView: View {
    @ObservedObject private var filter: ExerciseGroupFilter
    
    init(exerciseGroups: [ExerciseGroup]) {
        self.filter = ExerciseGroupFilter(exerciseGroups: exerciseGroups)
    }
    
    var body: some View {
        ZStack {
            IronScreenBackground()
            MuscleGroupSectionedExercisesView(exerciseGroups: filter.exerciseGroups)
        }
        .ironDestinationScreen(title: "All exercises")
        .searchable(
            text: $filter.filter,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}

#if DEBUG
struct ExerciseCategoryView_Previews : PreviewProvider {
    static var previews: some View {
        ExerciseMuscleGroupsView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
