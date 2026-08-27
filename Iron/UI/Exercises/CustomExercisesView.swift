//
//  CustomExercisesView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import WorkoutDataKit

struct CustomExercisesView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    
    @State private var activeSheet: SheetType?
    @State private var exerciseToDelete: Exercise?
    @State private var mutationFailure: CustomExerciseSaveFailure?
    
    private enum SheetType: Identifiable {
        case createCustomExercise
        case editCustomExercise(Exercise)
        
        var id: String {
            switch self {
            case .createCustomExercise:
                return "create-custom-exercise"
            case .editCustomExercise(let exercise):
                return "edit-custom-exercise-\(exercise.uuid.uuidString)"
            }
        }
    }
    
    private func sheetView(type: SheetType) -> AnyView {
        switch type {
        case .createCustomExercise:
            return CreateCustomExerciseSheet()
                .environmentObject(exerciseStore)
                .typeErased
        case .editCustomExercise(let exercise):
            return EditCustomExerciseSheet(exercise: exercise)
                .environmentObject(exerciseStore)
                .typeErased
        }
    }
    
    private func delete(_ exercise: Exercise) {
        assert(exercise.isCustom)
        let customExerciseSnapshot = exerciseStore.customExercises
        do {
            try exerciseStore.deleteCustomExercise(with: exercise.uuid)
            try deleteWorkoutExercises(with: exercise.uuid)
            try managedObjectContext.save()

            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.prepare()
            feedbackGenerator.notificationOccurred(.success)
        } catch {
            managedObjectContext.rollback()
            try? exerciseStore.replaceCustomExercises(with: customExerciseSnapshot)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                mutationFailure = CustomExerciseSaveFailure(error: error)
            }
        }
    }

    private func popupActions(for exercise: Exercise) -> [IronPopupAction] {
        assert(exercise.isCustom)
        return [
            IronPopupAction(title: "Edit Exercise", systemImage: "pencil") {
                self.activeSheet = .editCustomExercise(exercise)
            },
            IronPopupAction(
                title: "Delete Exercise",
                systemImage: "trash",
                role: .destructive
            ) {
                self.exerciseToDelete = exercise
            }
        ]
    }

    private func customExerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            NavigationLink(
                destination: ExerciseDetailView(exercise: exercise)
                    .environmentObject(self.settingsStore)
            ) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(IronTheme.accentSoft)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(IronTheme.accent)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(2)
                        Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            IronPopupMenu(title: "Exercise actions", actions: popupActions(for: exercise)) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(exercise.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 70)
    }

    private var customExercisesCard: some View {
        IronCard(padding: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(exerciseStore.customExercises.enumerated()), id: \.element.id) { index, exercise in
                    customExerciseRow(exercise)

                    if index < exerciseStore.customExercises.count - 1 {
                        IronHairline(opacity: 0.5)
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(IronTheme.accent)
            Text("No custom exercises yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Create an exercise to start building your library.")
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

    private var librarySummaryCard: some View {
        IronCard(padding: 14) {
            HStack(spacing: 13) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your exercise library")
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("\(exerciseStore.customExercises.count) custom exercise\(exerciseStore.customExercises.count == 1 ? "" : "s") · private to Iron")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }
        }
    }

    var body: some View {
        ZStack {
            IronScreenBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    librarySummaryCard

                    IronSectionTitle(title: "Custom exercises", detail: "YOUR LIBRARY")

                    if exerciseStore.customExercises.isEmpty {
                        emptyStateCard
                    } else {
                        customExercisesCard
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .background(IronTheme.background)
        .navigationTitle("Custom exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { activeSheet = .createCustomExercise }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create custom exercise")
                .accessibilityHint("Opens the custom exercise editor")
            }
        }
        .sheet(item: $activeSheet) { type in
            self.sheetView(type: type)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(IronTheme.modalSurface)
        }
        .confirmationDialog(
            "Delete \(exerciseToDelete?.title ?? "exercise")?",
            isPresented: Binding(
                get: { exerciseToDelete != nil },
                set: { if !$0 { exerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive) {
                guard let exercise = exerciseToDelete else { return }
                exerciseToDelete = nil
                delete(exercise)
            }
            Button("Cancel", role: .cancel) {
                exerciseToDelete = nil
            }
        } message: {
            Text("This removes the custom exercise and every workout set that uses it. This cannot be undone.")
        }
        .sheet(item: $mutationFailure) { failure in
            IronStatusSheet(
                headerTitle: "Custom Exercises",
                title: "Could not delete exercise",
                message: failure.error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: IronTheme.danger
            )
        }
        .ironScreen()
    }

    private func deleteWorkoutExercises(with uuid: UUID) throws {
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(WorkoutExercise.exerciseUuid)) == %@", uuid as CVarArg)
        let workoutExercises = try managedObjectContext.fetch(request)
        workoutExercises.forEach { managedObjectContext.delete($0) }
    }
}

#if DEBUG
struct CustomExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        CustomExercisesView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
