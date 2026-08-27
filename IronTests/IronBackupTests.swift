//
//  IronBackupTests.swift
//  IronTests
//
//  Created by Karim Abou Zeid on 25.03.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import CoreData
import WorkoutDataKit
@testable import Iron

class IronBackupTests: XCTestCase {
    var persistenContainer: NSPersistentContainer!
    var userDefaults: UserDefaults!
    var exerciseStore: ExerciseStore!
    var customExercisesURL: URL!

    override func setUpWithError() throws {
        // reset test folder
        let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("test", isDirectory: true)
        if FileManager.default.fileExists(atPath: testFolder.path) {
            try! FileManager.default.removeItem(at: testFolder)
        }
        try! FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        
        // reset user defaults
        UserDefaults().removePersistentDomain(forName: "test")
        userDefaults = UserDefaults(suiteName: "test")
        
        // in memory persistent container
        persistenContainer = setUpInMemoryNSPersistentContainer()
        
        // exercise store in test folder
        customExercisesURL = testFolder.appendingPathComponent("custom_exercises.json")
        exerciseStore = ExerciseStore(customExercisesURL: customExercisesURL)
    }

    override func tearDownWithError() throws {
        persistenContainer.viewContext.reset()
        persistenContainer = nil
    }
    
    func testImportIronBackupV1() {
        let context = persistenContainer.viewContext
        
        let data = backupData(name: "v1")
        XCTAssertNoThrow(try IronBackup.restoreBackupData(data: data, managedObjectContext: context, exerciseStore: exerciseStore))
        
        let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        let workouts = try! context.fetch(workoutRequest)
        XCTAssertEqual(workouts.count, 209) // sanity check
        
        XCTAssertEqual(exerciseStore.customExercises.count, 4) // sanity check
    }

    func testImportIronBackupV2() {
        let context = persistenContainer.viewContext
        
        let data = backupData(name: "v2")
        XCTAssertNoThrow(try IronBackup.restoreBackupData(data: data, managedObjectContext: context, exerciseStore: exerciseStore))
        
        let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        let workouts = try! context.fetch(workoutRequest)
        XCTAssertEqual(workouts.count, 246) // sanity check
        
        XCTAssertEqual(exerciseStore.customExercises.count, 5) // sanity check
    }
    
    func testImportIronBackupV3() {
        let context = persistenContainer.viewContext

        let data = backupData(name: "v3")
        XCTAssertNoThrow(try IronBackup.restoreBackupData(data: data, managedObjectContext: context, exerciseStore: exerciseStore))

        let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        let workouts = try! context.fetch(workoutRequest)
        XCTAssertEqual(workouts.count, 246) // sanity check
        
        let workoutPlanRequest: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
        let workoutPlans = try! context.fetch(workoutPlanRequest)
        XCTAssertEqual(workoutPlans.count, 1) // sanity check
        
        XCTAssertEqual(exerciseStore.customExercises.count, 5) // sanity check
    }
    
    func testExportIronBackup() {
        let context = persistenContainer.viewContext
        createTestWorkoutData(context: context)
        try! context.save()
        
        XCTAssertNoThrow(try IronBackup.createBackupData(
            managedObjectContext: context,
            exerciseStore: exerciseStore,
            userDefaults: userDefaults
        ))
    }

    func testExportAndRestoreBodyMeasurements() throws {
        let context = persistenContainer.viewContext
        let original = BodyMeasurementEntry(
            date: Date(timeIntervalSince1970: 1_720_000_000),
            values: [
                BodyMeasurementKind.bodyWeight.rawValue: 82.4,
                BodyMeasurementKind.waist.rawValue: 81.2
            ]
        )
        let measurementData = try JSONEncoder().encode([original])
        userDefaults.set(measurementData, forKey: IronBackup.bodyMeasurementsStorageKey)

        let backupData = try IronBackup.createBackupData(
            managedObjectContext: context,
            exerciseStore: exerciseStore,
            userDefaults: userDefaults
        )
        userDefaults.removeObject(forKey: IronBackup.bodyMeasurementsStorageKey)

        try IronBackup.restoreBackupData(
            data: backupData,
            managedObjectContext: context,
            exerciseStore: exerciseStore,
            userDefaults: userDefaults
        )

        let restoredStore = BodyMetricsStore(userDefaults: userDefaults)
        XCTAssertEqual(restoredStore.entries, [original])
    }

    func testCustomExerciseInstructionsPersistAcrossCreateAndUpdate() throws {
        let created = try exerciseStore.createCustomExercise(
            title: "Test Split Squat",
            description: "A stable unilateral squat.",
            primaryMuscle: ["quadriceps"],
            secondaryMuscle: ["glutes"],
            type: .dumbbell,
            steps: ["Stand in a split stance.", "Lower under control."],
            tips: ["Keep the front foot planted."]
        )

        XCTAssertEqual(created.steps, ["Stand in a split stance.", "Lower under control."])
        XCTAssertEqual(created.tips, ["Keep the front foot planted."])

        let updated = try exerciseStore.updateCustomExercise(
            with: created.uuid,
            title: "Test Rear-Foot-Elevated Split Squat",
            description: "Rear foot elevated.",
            primaryMuscle: ["quadriceps"],
            secondaryMuscle: ["glutes", "hamstrings"],
            type: .dumbbell,
            steps: ["Elevate the rear foot.", "Descend until the front thigh is parallel."],
            tips: ["Brace before each rep.", "Drive through the full front foot."]
        )

        XCTAssertEqual(updated.title, "Test Rear-Foot-Elevated Split Squat")
        XCTAssertEqual(updated.steps.count, 2)
        XCTAssertEqual(updated.tips.count, 2)

        let reloadedStore = ExerciseStore(customExercisesURL: customExercisesURL)
        let reloaded = try XCTUnwrap(reloadedStore.find(with: created.uuid))
        XCTAssertEqual(reloaded, updated)

        let deleted = try reloadedStore.deleteCustomExercise(with: created.uuid)
        XCTAssertEqual(deleted, updated)
        let afterDeletionStore = ExerciseStore(customExercisesURL: customExercisesURL)
        XCTAssertNil(afterDeletionStore.find(with: created.uuid))
    }

    func testCustomExerciseMutationReportsPersistenceFailures() {
        let unavailableStore = ExerciseStore(customExercisesURL: nil)

        XCTAssertThrowsError(
            try unavailableStore.createCustomExercise(
                title: "Unsaved Exercise",
                description: nil,
                primaryMuscle: ["quadriceps"],
                secondaryMuscle: [],
                type: .other
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ExerciseStore.CustomExerciseMutationError.storageUnavailable.localizedDescription
            )
        }
        XCTAssertTrue(unavailableStore.customExercises.isEmpty)
    }
}

extension IronBackupTests {
    private func backupData(name: String) -> Data {
        let url = Bundle.init(for: Self.self).bundleURL.appendingPathComponent("iron_backups").appendingPathComponent(name).appendingPathExtension("ironbackup")
        precondition(FileManager.default.fileExists(atPath: url.path), "File \(url.path) does not exist")
        return try! Data(contentsOf: url)
    }
}
