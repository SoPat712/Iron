//
//  WorkoutPlanView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 21.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

/// The editor for a saved workout plan.
///
/// Plans are edited relatively infrequently, while the card layout keeps the title,
/// routine summaries, and the destructive controls visually separate in both
/// light and dark appearances.
struct WorkoutPlanView: View {
    @EnvironmentObject var exerciseStore: ExerciseStore
    @Environment(\.managedObjectContext) var managedObjectContext

    @ObservedObject var workoutPlan: WorkoutPlan

    @State private var workoutPlanTitleInput: String?
    @State private var routineToDelete: WorkoutRoutine?

    private var workoutPlanTitle: Binding<String> {
        Binding(
            get: { workoutPlanTitleInput ?? workoutPlan.title ?? "" },
            set: { workoutPlanTitleInput = $0 }
        )
    }

    private var workoutRoutines: [WorkoutRoutine] {
        workoutPlan.workoutRoutines?.array as? [WorkoutRoutine] ?? []
    }

    private func saveWorkoutPlanTitle() {
        guard let input = workoutPlanTitleInput else { return }
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        workoutPlanTitleInput = title
        workoutPlan.title = title.isEmpty ? nil : title
        managedObjectContext.saveOrCrash()
    }

    private func createWorkoutRoutine() {
        let workoutRoutine = WorkoutRoutine.create(context: managedObjectContext)
        workoutRoutine.workoutPlan = workoutPlan
        managedObjectContext.saveOrCrash()
    }

    private func moveRoutine(from source: Int, to destination: Int) {
        guard source != destination,
              workoutRoutines.indices.contains(source),
              workoutRoutines.indices.contains(destination) else { return }

        var reordered = workoutRoutines
        let routine = reordered.remove(at: source)
        reordered.insert(routine, at: destination)
        workoutPlan.workoutRoutines = NSOrderedSet(array: reordered)
        managedObjectContext.saveOrCrash()
    }

    /// Returns true when deleting a routine also removes the user's saved plan
    /// exercises. This preserves the confirmation behavior of the old editor.
    private func needsConfirmBeforeDelete(_ routine: WorkoutRoutine) -> Bool {
        (routine.workoutRoutineExercises?.count ?? 0) > 0
    }

    private func requestDelete(_ routine: WorkoutRoutine) {
        if needsConfirmBeforeDelete(routine) {
            routineToDelete = routine
        } else {
            delete(routine)
        }
    }

    private func delete(_ routine: WorkoutRoutine) {
        managedObjectContext.delete(routine)
        managedObjectContext.saveOrCrash()
    }

    private func routinePopupActions(_ routine: WorkoutRoutine, index: Int) -> [IronPopupAction] {
        var actions: [IronPopupAction] = []
        if index > 0 {
            actions.append(IronPopupAction(title: "Move Up", systemImage: "arrow.up") {
                moveRoutine(from: index, to: index - 1)
            })
        }
        if index < workoutRoutines.count - 1 {
            actions.append(IronPopupAction(title: "Move Down", systemImage: "arrow.down") {
                moveRoutine(from: index, to: index + 1)
            })
        }
        actions.append(IronPopupAction(
            title: "Delete Workout",
            systemImage: "trash",
            role: .destructive
        ) {
            requestDelete(routine)
        })
        return actions
    }

    private func routineRow(_ routine: WorkoutRoutine, index: Int) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: WorkoutRoutineView(workoutRoutine: routine)) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.accentSoft)
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(IronTheme.accent)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(routine.displayTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(1)
                        Text(routine.subtitle(in: exerciseStore.exercises))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            IronPopupMenu(title: "Workout actions", actions: routinePopupActions(routine, index: index)) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(routine.displayTitle)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WORKOUT DETAILS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(IronTheme.secondaryText)

                        TextField("Workout title", text: workoutPlanTitle, onEditingChanged: { isEditing in
                            if !isEditing { saveWorkoutPlanTitle() }
                        })
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(IronTheme.primaryText)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                .fill(IronTheme.field)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            IronSectionTitle(title: "Workouts", detail: "\(workoutRoutines.count)")
                        }

                        if workoutRoutines.isEmpty {
                            emptyRoutinesCard
                        } else {
                            ForEach(Array(workoutRoutines.enumerated()), id: \.element.id) { index, routine in
                                routineRow(routine, index: index)
                            }
                        }

                        Button(action: createWorkoutRoutine) {
                            Label("Add Workout", systemImage: "plus")
                        }
                        .buttonStyle(IronPrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .navigationTitle(workoutPlan.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { saveWorkoutPlanTitle() }
            }
        }
        .alert(item: $routineToDelete) { routine in
            Alert(
                title: Text("Delete \(routine.displayTitle)?"),
                message: Text("This will remove the exercises saved in this workout and cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(routine)
                },
                secondaryButton: .cancel()
            )
        }
        .onDisappear {
            saveWorkoutPlanTitle()
        }
        .ironScreen()
    }

    private var emptyRoutinesCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(IronTheme.accent)
            Text("No workouts yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Add a workout to start choosing exercises.")
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
    }
}

#if DEBUG
struct WorkoutPlanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutPlanView(workoutPlan: MockWorkoutData.metric.workoutPlan)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
