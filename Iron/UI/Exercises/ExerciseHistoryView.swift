//
//  ExerciseHistoryView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 06.07.19.
//  Rebuilt for Iron's focused exercise history.
//

import SwiftUI
import CoreData
import WorkoutDataKit

struct ExerciseHistoryView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @FetchRequest(fetchRequest: WorkoutExercise.fetchRequest()) private var history

    let exercise: Exercise
    private let usesModalSurface: Bool
    private let onOpenWorkout: () -> Void
    private let onCloseWorkout: () -> Void

    init(
        exercise: Exercise,
        usesModalSurface: Bool = false,
        onOpenWorkout: @escaping () -> Void = {},
        onCloseWorkout: @escaping () -> Void = {}
    ) {
        self.exercise = exercise
        self.usesModalSurface = usesModalSurface
        self.onOpenWorkout = onOpenWorkout
        self.onCloseWorkout = onCloseWorkout
        _history = FetchRequest(fetchRequest: WorkoutExercise.historyFetchRequest(of: exercise.uuid, until: nil))
    }

    private var completedHistory: [WorkoutExercise] {
        history.filter { ($0.numberOfCompletedSets ?? 0) > 0 }
    }

    var body: some View {
        ZStack {
            shellBackground

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    IronSectionTitle(title: "Recent sessions", detail: "\(completedHistory.count) total")
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 12)

                    if completedHistory.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(completedHistory) { workoutExercise in
                                sessionLink(workoutExercise)
                            }
                        }
                        .padding(.horizontal, IronTheme.horizontalPadding)
                    }
                }
                .padding(.bottom, 40)
            }
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("No exercise history yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Completed sets for \(exercise.title) will appear here.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, IronTheme.horizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    @ViewBuilder
    private func sessionLink(_ workoutExercise: WorkoutExercise) -> some View {
        if let workout = workoutExercise.workout {
            NavigationLink(
                destination: WorkoutDetailView(workout: workout)
                    .onAppear(perform: onOpenWorkout)
                    .onDisappear(perform: onCloseWorkout)
            ) {
                sessionCard(workoutExercise)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full workout")
        } else {
            sessionCard(workoutExercise)
        }
    }

    private func sessionCard(_ workoutExercise: WorkoutExercise) -> some View {
        let sets = workoutSets(for: workoutExercise)
        let completedCount = sets.filter(\.isCompleted).count
        let isFullyCompleted = !sets.isEmpty && completedCount == sets.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Workout.dateFormatter.string(from: workoutExercise.workout?.start, fallback: "Unknown date"))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("\(completedCount) completed of \(sets.count) sets")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
                Spacer()
                HStack(spacing: 9) {
                    Label(
                        isFullyCompleted ? "Complete" : "Partial",
                        systemImage: isFullyCompleted ? "checkmark.circle.fill" : "circle.lefthalf.filled"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isFullyCompleted ? IronTheme.success : IronTheme.warning)

                    if workoutExercise.workout != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.tertiaryText)
                    }
                }
            }
            .padding(16)

            if let comment = workoutExercise.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            IronHairline()

            HStack {
                Text("SET").frame(width: 42, alignment: .leading)
                Text("RESULT")
                Spacer()
                Text("RPE").frame(width: 52, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundColor(IronTheme.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                historySetRow(set, index: index)

                if index < sets.count - 1 {
                    IronHairline()
                        .padding(.leading, 58)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous))
    }

    private func historySetRow(_ set: WorkoutSet, index: Int) -> some View {
        HStack(spacing: 10) {
            Text(set.tagValue?.title.first.map(String.init) ?? "\(index + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundColor(set.tagValue?.color ?? IronTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.raisedSurface)
                )

            Text(set.resultTitle(weightUnit: settingsStore.weightUnit))
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundColor(set.isCompleted ? IronTheme.primaryText : IronTheme.secondaryText)

            if set.isPersonalRecord ?? false {
                Image(systemName: "medal.fill")
                    .font(.caption)
                    .foregroundColor(IronTheme.warning)
            }

            Spacer()

            Text(rpeText(set.rpeValue))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundColor(set.rpeValue == nil ? IronTheme.tertiaryText : IronTheme.secondaryText)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func workoutSets(for workoutExercise: WorkoutExercise) -> [WorkoutSet] {
        workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
    }

    private func rpeText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

}

#if DEBUG
struct ExerciseHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseHistoryView(exercise: ExerciseStore.shared.exercises.first(where: { $0.everkineticId == 42 })!)
            .mockEnvironment(weightUnit: .metric)
            .preferredColorScheme(.dark)
    }
}
#endif
