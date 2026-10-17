//
//  DeveloperSettings.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

#if DEBUG

import SwiftUI
import CoreData
import WorkoutDataKit

struct DeveloperSettings: View {
    @State private var activityItems: [Any]?
    @State private var showingPlanConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        List {
            if let statusMessage {
                Section {
                    LabeledContent {
                        Button("Dismiss", systemImage: "xmark") { self.statusMessage = nil }
                            .labelStyle(.iconOnly)
                    } label: {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                Button("Create Sample Workouts", systemImage: "plus") {
                    showingPlanConfirmation = true
                }

                Button("Seed Sample History", systemImage: "clock.arrow.circlepath") {
                    seedSampleHistory()
                }
            } header: {
                Text("Sample Data")
            } footer: {
                Text("Sample workouts adds Workout A and Workout B with ready-to-edit 5×5 sets. Seed history fills completed workouts and body measurements so populated screens can be reviewed.")
            }

            Section {
                LabeledContent("Database", value: databaseSummary)
                Button("Share Database Snapshot", systemImage: "square.and.arrow.up") {
                    shareFile(url: WorkoutDataStorage.groupStoreURL)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("These controls are available only in development builds. Exported databases can contain your complete local training history.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Developer")
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func seedSampleHistory() {
        IronSampleDataSeeder.seed(reset: false)
        statusMessage = "Sample history and measurements were added."
    }

    private var databaseSummary: String {
        let url = WorkoutDataStorage.groupStoreURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return url.lastPathComponent
        }
        return "\(url.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))"
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

/// Populates a development build with training history and body measurements so
/// every screen can be reviewed with realistic content.
enum IronSampleDataSeeder {
    static func seed(reset: Bool, includeActiveWorkout: Bool = false) {
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        let unit = SettingsStore.shared.weightUnit

        if reset {
            deleteAllWorkouts(in: context)
        }

        MockWorkoutData.seedHistory(
            into: context,
            unit: unit,
            includeActiveWorkout: includeActiveWorkout
        )
        context.saveOrCrash()
        seedBodyMeasurements(reset: reset)
    }

    private static func deleteAllWorkouts(in context: NSManagedObjectContext) {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        for workout in (try? context.fetch(request)) ?? [] {
            context.delete(workout)
        }
        let planRequest: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
        for plan in (try? context.fetch(planRequest)) ?? [] {
            context.delete(plan)
        }
        context.saveOrCrash()
    }

    private static func seedBodyMeasurements(reset: Bool) {
        let store = BodyMetricsStore.shared
        if reset {
            store.delete(at: IndexSet(store.entries.indices))
        }

        // Weekly entries over three months so the Home panel shows a current
        // value and the dashboard chart has a readable slope.
        for week in 0..<12 {
            guard let date = Calendar.current.date(
                byAdding: .day, value: -week * 7, to: Date()
            ) else { continue }

            let progress = Double(week)
            let entry = BodyMeasurementEntry(
                date: date,
                values: [
                    BodyMeasurementKind.bodyWeight.rawValue: 84 + progress * 0.35,
                    BodyMeasurementKind.bodyFat.rawValue: 16 + progress * 0.2,
                    BodyMeasurementKind.waist.rawValue: 82 + progress * 0.3,
                    BodyMeasurementKind.chest.rawValue: 104 - progress * 0.15,
                    BodyMeasurementKind.leftBicep.rawValue: 37 - progress * 0.08,
                    BodyMeasurementKind.rightBicep.rawValue: 37.2 - progress * 0.08
                ]
            )
            store.save(entry, exportToHealth: false)
        }
    }
}

struct DeveloperSettings_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperSettings()
    }
}

#endif
