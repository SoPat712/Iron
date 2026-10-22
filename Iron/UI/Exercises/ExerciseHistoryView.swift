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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FetchRequest(fetchRequest: WorkoutExercise.fetchRequest()) private var history

    let exercise: Exercise
    private let onOpenWorkout: () -> Void
    private let onCloseWorkout: () -> Void

    init(
        exercise: Exercise,
        onOpenWorkout: @escaping () -> Void = {},
        onCloseWorkout: @escaping () -> Void = {}
    ) {
        self.exercise = exercise
        self.onOpenWorkout = onOpenWorkout
        self.onCloseWorkout = onCloseWorkout
        _history = FetchRequest(fetchRequest: WorkoutExercise.historyFetchRequest(of: exercise.uuid, until: nil))
    }

    private var completedHistory: [WorkoutExercise] {
        history.filter { ($0.numberOfCompletedSets ?? 0) > 0 }
    }

    var body: some View {
        List {
            if completedHistory.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Completed sets for \(exercise.title) will appear here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(completedHistory) { workoutExercise in
                    sessionSection(workoutExercise)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sessionSection(_ workoutExercise: WorkoutExercise) -> some View {
        let sets = workoutExercise.workoutSets?.array as? [WorkoutSet] ?? []
        let completedCount = sets.filter(\.isCompleted).count
        let isFullyCompleted = !sets.isEmpty && completedCount == sets.count

        return Section {
            if let workout = workoutExercise.workout {
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                        .onAppear(perform: onOpenWorkout)
                        .onDisappear(perform: onCloseWorkout)
                } label: {
                    LabeledContent("Workout") {
                        Label(
                            isFullyCompleted ? "Complete" : "Partial",
                            systemImage: isFullyCompleted ? "checkmark.circle.fill" : "circle.lefthalf.filled"
                        )
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(isFullyCompleted ? IronTheme.accent : IronTheme.secondaryText)
                    }
                }
            }

            if let comment = workoutExercise.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                ExerciseHistorySetRow(set: set, index: index)
            }
        } header: {
            Text(Workout.dateFormatter.string(from: workoutExercise.workout?.start, fallback: "Unknown date"))
        } footer: {
            (Text("\(completedCount)").font(.ironMetric(.footnote, weight: .semibold)).foregroundColor(IronTheme.metricSets)
                + Text(" of ")
                + Text("\(sets.count)").font(.ironMetric(.footnote, weight: .semibold)).foregroundColor(IronTheme.metricSets)
                + Text(" sets completed"))
                .font(.caption)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: completedCount)
                .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: sets.count)
        }
    }

}

/// The same completed-set presentation is used in full and inline history.
struct ExerciseHistorySetRow: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var set: WorkoutSet
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(set.tagValue?.title.first.map(String.init) ?? "\(index + 1)")
                .font(.ironMetric(.subheadline, weight: .semibold))
                .foregroundStyle(IronTheme.metricSets)
                .frame(width: 24, alignment: .leading)

            resultText(for: set)
                .opacity(set.isCompleted ? 1 : 0.65)
                .contentTransition(reduceMotion ? .opacity : .numericText())

            if set.isPersonalRecord ?? false {
                Image(systemName: "medal.fill")
                    .font(.caption)
                    .foregroundStyle(IronTheme.metricRecord)
            }

            Spacer()

            Text(rpeText(set.rpeValue))
                .font(.ironMetric(.subheadline, weight: .semibold))
                .foregroundStyle(set.rpeValue == nil ? IronTheme.secondaryText : IronTheme.metricEffort)
                .contentTransition(reduceMotion ? .opacity : .numericText())
        }
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: set.rpeValue)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: set.resultTitle(weightUnit: settingsStore.weightUnit))
    }

    private func resultText(for set: WorkoutSet) -> Text {
        let separator = Text(" · ").foregroundColor(IronTheme.secondaryText)
        if let distance = set.distanceValue {
            let result = distanceText(distance)
            if let duration = set.durationValue {
                return result + separator + metricText(IronDurationFormat.title(duration), color: IronTheme.metricTime)
            }
            return result
        }
        if let duration = set.durationValue {
            let time = metricText(IronDurationFormat.title(duration), color: IronTheme.metricTime)
            return set.weightValue > 0 ? weightText(set.weightValue) + separator + time : time
        }
        if set.weightValue > 0 {
            return weightText(set.weightValue)
                + Text(" × ").foregroundColor(IronTheme.secondaryText)
                + metricText("\(set.repetitionsValue)", color: IronTheme.metricSets)
        }
        if set.repetitionsValue > 0 {
            return metricText("\(set.repetitionsValue)", color: IronTheme.metricSets) + unitText("reps")
        }
        return Text("—").foregroundColor(IronTheme.secondaryText)
    }

    private func weightText(_ kilograms: Double) -> Text {
        let weight = WeightUnit.convert(weight: kilograms, from: .metric, to: settingsStore.weightUnit)
        let number = settingsStore.weightUnit.displayNumberFormatter.string(from: NSNumber(value: weight)) ?? "\(weight)"
        return metricText(number, color: IronTheme.metricVolume) + unitText(settingsStore.weightUnit.unit.symbol)
    }

    private func distanceText(_ meters: Double) -> Text {
        let distance: Double
        let unit: String
        switch settingsStore.weightUnit {
        case .metric:
            distance = meters >= 1_000 ? meters / 1_000 : meters
            unit = meters >= 1_000 ? "km" : "m"
        case .imperial:
            let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles).value
            distance = miles >= 0.1 ? miles : Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
            unit = miles >= 0.1 ? "mi" : "ft"
        }
        let number = distance.formatted(.number.precision(.fractionLength(unit == "km" || unit == "mi" ? 2 : 0)))
        return metricText(number, color: IronTheme.metricTime) + unitText(unit)
    }

    private func metricText(_ value: String, color: Color) -> Text {
        Text(value).font(.ironMetric(.body, weight: .semibold)).foregroundColor(color)
    }

    private func unitText(_ unit: String) -> Text {
        Text(" \(unit)").font(.caption).foregroundColor(IronTheme.secondaryText)
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
