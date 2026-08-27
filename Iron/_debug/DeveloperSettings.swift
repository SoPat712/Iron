//
//  DeveloperSettings.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

#if DEBUG

import SwiftUI
import WorkoutDataKit

struct DeveloperSettings: View {
    @State private var activityItems: [Any]?
    @State private var showingPlanConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Developer tools")
                            .font(.title2.weight(.bold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Create repeatable test data and inspect Iron's local store.")
                            .font(.subheadline)
                            .foregroundColor(IronTheme.secondaryText)
                    }

                    if let statusMessage {
                        statusBanner(statusMessage)
                    }

                    sampleDataSection
                    diagnosticsSection

                    Label {
                        Text("These controls are available only in development builds. Exported databases can contain your complete local training history.")
                    } icon: {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(IronTheme.warning)
                    }
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                }
                .padding(IronTheme.horizontalPadding)
                .padding(.bottom, 112)
            }
        }
        .ironDestinationScreen(title: "Developer")
        .ironScreen()
        .ironActivitySheet(activityItems: $activityItems)
        .sheet(isPresented: $showingPlanConfirmation) {
            IronConfirmationSheet(
                title: "Create sample workouts?",
                message: "This adds two editable sample workouts. Existing saved workouts are not changed.",
                confirmTitle: "Create Sample Workouts",
                systemImage: "square.stack.3d.up.fill",
                secondaryTitle: "Cancel",
                onCancel: { showingPlanConfirmation = false },
                onConfirm: {
                    showingPlanConfirmation = false
                    createDefaultWorkoutPlans()
                    statusMessage = "StrongLifts 5×5 sample workouts were added."
                }
            )
            .presentationDetents([.height(410), .medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
    }

    private var sampleDataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Sample data", detail: "WORKOUTS")
            IronCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(IronTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(IronTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("StrongLifts test workouts")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text("Adds Workout A and Workout B with ready-to-edit 5×5 sets for exercising saved-workout and live-session flows.")
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        showingPlanConfirmation = true
                    } label: {
                        Label("Create sample workouts", systemImage: "plus")
                    }
                    .buttonStyle(IronSecondaryButtonStyle())
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Diagnostics", detail: "LOCAL DATA")
            IronCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "cylinder.split.1x2.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(IronTheme.success)
                            .frame(width: 42, height: 42)
                            .background(IronTheme.success.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Core Data database")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text(databaseSummary)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(IronTheme.secondaryText)
                        }
                    }

                    Button {
                        shareFile(url: WorkoutDataStorage.groupStoreURL)
                    } label: {
                        Label("Share database snapshot", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                }
            }
        }
    }

    private var databaseSummary: String {
        let url = WorkoutDataStorage.groupStoreURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return url.lastPathComponent
        }
        return "\(url.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))"
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(IronTheme.success)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Spacer(minLength: 0)
            Button {
                statusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.success.opacity(0.12))
        )
    }

    private func shareFile(url: URL) {
        self.activityItems = [url]
    }
}

func toUuid(_ id: Int) -> UUID? {
    ExerciseStore.shared.exercises.first { $0.everkineticId == id }?.uuid
}

func niceWeight(weight: Double, unit: WeightUnit) -> Double {
    let weightInUnit = WeightUnit.convert(weight: weight, from: .metric, to: unit)
    let nice = weightInUnit - weightInUnit.truncatingRemainder(dividingBy: unit.barbellIncrement)
    return WeightUnit.convert(weight: nice, from: unit, to: .metric)
}

func createDefaultWorkoutPlans() {
    let context = WorkoutDataStorage.shared.persistentContainer.viewContext
    let unit = SettingsStore.shared.weightUnit

    let create5x5 = { (weight: Double) -> [WorkoutRoutineSet] in
        (0..<5).map { _ -> WorkoutRoutineSet in
            let set = WorkoutRoutineSet.create(context: context)
            set.minRepetitionsValue = 5
            set.maxRepetitionsValue = 5
            return set
        }
    }

    let workoutRoutineExerciseSquatA = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseSquatA.exerciseUuid = toUuid(122) // squat
    workoutRoutineExerciseSquatA.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 120, unit: unit)))

    let workoutRoutineExerciseBenchA = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseBenchA.exerciseUuid = toUuid(42) // bench
    workoutRoutineExerciseBenchA.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 80, unit: unit)))

    let workoutRoutineExerciseRowA = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseRowA.exerciseUuid = toUuid(298) // row
    workoutRoutineExerciseRowA.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 60, unit: unit)))

    let workoutRoutineA = WorkoutRoutine.create(context: context)
    workoutRoutineA.title = "Workout A"
    workoutRoutineA.workoutRoutineExercises = NSOrderedSet(arrayLiteral: workoutRoutineExerciseSquatA, workoutRoutineExerciseBenchA, workoutRoutineExerciseRowA)

    let workoutRoutineExerciseSquatB = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseSquatB.exerciseUuid = toUuid(122) // squat
    workoutRoutineExerciseSquatB.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 120, unit: unit)))

    let workoutRoutineExerciseBenchB = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseBenchB.exerciseUuid = toUuid(9001) // press
    workoutRoutineExerciseBenchB.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 65, unit: unit)))

    let workoutRoutineExerciseRowB = WorkoutRoutineExercise.create(context: context)
    workoutRoutineExerciseRowB.exerciseUuid = toUuid(99) // deadlift
    workoutRoutineExerciseRowB.workoutRoutineSets = NSOrderedSet(array: create5x5(niceWeight(weight: 140, unit: unit)))

    let workoutRoutineB = WorkoutRoutine.create(context: context)
    workoutRoutineB.title = "Workout B"
    workoutRoutineB.workoutRoutineExercises = NSOrderedSet(arrayLiteral: workoutRoutineExerciseSquatB, workoutRoutineExerciseBenchB, workoutRoutineExerciseRowB)

    let workoutPlan = WorkoutPlan.create(context: context)
    workoutPlan.title = "StrongLifts 5x5"
    workoutPlan.workoutRoutines = NSOrderedSet(arrayLiteral: workoutRoutineA, workoutRoutineB)
    context.saveOrCrash()
}

struct DeveloperSettings_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperSettings()
    }
}

#endif
