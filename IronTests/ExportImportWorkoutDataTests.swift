//
//  ExportImportWorkoutDataTests.swift
//  IronTests
//
//  Created by Karim Abou Zeid on 26.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import CoreData
import WorkoutDataKit
@testable import Iron

class ExportImportWorkoutDataTests: XCTestCase {
    var persistenContainer: NSPersistentContainer!
    
    var encoder: JSONEncoder {
        guard let contextKey = CodingUserInfoKey.managedObjectContextKey else { fatalError() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.userInfo[contextKey] = persistenContainer.viewContext
        return encoder
    }
    
    var decoder: JSONDecoder {
        guard let contextKey = CodingUserInfoKey.managedObjectContextKey else { fatalError() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[contextKey] = persistenContainer.viewContext
        return decoder
    }

    override func setUp() {
        super.setUp()
        persistenContainer = setUpInMemoryNSPersistentContainer()
    }

    override func tearDown() {
        persistenContainer.viewContext.reset()
        persistenContainer = nil
        super.tearDown()
    }

    func testReadWorkoutData() {
        let workoutDataUrl = Bundle.init(for: Self.self).bundleURL.appendingPathComponent("workout_data.json")
        precondition(FileManager.default.fileExists(atPath: workoutDataUrl.path))
        
        // check that start and end is not nil
        let workouts = try! decoder.decode([Workout].self, from: Data(contentsOf: workoutDataUrl))
        XCTAssertFalse(workouts.isEmpty)
        for workout in workouts {
            XCTAssertNotNil(workout.start)
            XCTAssertNotNil(workout.end)
            XCTAssertFalse(workout.isCurrentWorkout)
        }
        
        // check that workout is set
        let exercises = workouts.compactMap { $0.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } }.flatMap { $0 }
        XCTAssertFalse(exercises.isEmpty)
        for exercise in exercises {
            XCTAssertNotNil(exercise.workout)
        }
        
        // check that workoutExercise is set
        let sets = exercises.compactMap { $0.workoutSets?.array.compactMap { $0 as? WorkoutSet } }.flatMap { $0 }
        XCTAssertFalse(sets.isEmpty)
        for set in sets {
            XCTAssertNotNil(set.workoutExercise)
            XCTAssert(set.isCompleted)
        }
        
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    func testReadWorkoutDataStartEndMissing() {
        let workoutDataUrl = Bundle.init(for: Self.self).bundleURL.appendingPathComponent("workout_data_start_end_missing.json")
        precondition(FileManager.default.fileExists(atPath: workoutDataUrl.path))
        
        // cannot read if a workout doesn't have a start / end value
        XCTAssertThrowsError(try decoder.decode([Workout].self, from: Data(contentsOf: workoutDataUrl)))
    }
    
    func testExportWorkoutWithoutStartEnd() {
        let workout = Workout.create(context: persistenContainer.viewContext)
        // no start / end is set
        // encoding shouldn't crash but set safeStart and safeEnd
        let data = try! encoder.encode([workout])
        
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        persistenContainer.viewContext.delete(workout)
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
        
        let workouts = try! decoder.decode([Workout].self, from: data)
        for workout in workouts {
            // decoded workouts must always have start end assigned
            XCTAssertNotNil(workout.start)
            XCTAssertNotNil(workout.end)
        }
        
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }

    func testHevyCSVWorkoutImportExportAndDuplicateProtection() throws {
        let exercise = try XCTUnwrap(ExerciseStore.shared.exercises.first)
        let exerciseTitle = exercise.title.replacingOccurrences(of: "\"", with: "\"\"")
        let header = "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_lbs\",\"reps\",\"distance_miles\",\"duration_seconds\",\"rpe\""
        let rowOne = "\"Push, Pull\",\"17 Aug 2026, 08:16\",\"17 Aug 2026, 08:35\",\"Good \"\"session\"\"\",\"\(exerciseTitle)\",,\"First line\\nSecond line\",0,\"warmup\",135,5,,,"
        let rowTwo = "\"Push, Pull\",\"17 Aug 2026, 08:16\",\"17 Aug 2026, 08:35\",\"Good \"\"session\"\"\",\"\(exerciseTitle)\",,\"First line\\nSecond line\",1,\"normal\",225,8,,,7.5"
        let data = try XCTUnwrap((header + "\r\n" + rowOne + "\n" + rowTwo + "\r\n").data(using: .utf8))

        let parsed = try HevyCSV.parse(data: data)
        XCTAssertEqual(parsed.records.count, 2)
        XCTAssertEqual(parsed.records.first?.title, "Push, Pull")

        let result = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared
        )
        XCTAssertEqual(result.importedWorkouts, 1)
        XCTAssertEqual(result.importedSets, 2)

        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        let workout = try XCTUnwrap(persistenContainer.viewContext.fetch(request).first)
        let workoutExercise = try XCTUnwrap(workout.workoutExercises?.firstObject as? WorkoutExercise)
        let sets = try XCTUnwrap(workoutExercise.workoutSets?.array as? [WorkoutSet])
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].tagValue, .warmUp)
        XCTAssertEqual(sets[1].rpeValue, 7.5)
        XCTAssertEqual(sets[1].weightValue, Measurement(value: 225, unit: UnitMass.pounds).converted(to: .kilograms).value, accuracy: 0.0001)
        XCTAssertEqual(workoutExercise.comment, "First line\nSecond line")

        let duplicateResult = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared
        )
        XCTAssertEqual(duplicateResult.importedWorkouts, 0)
        XCTAssertEqual(duplicateResult.skippedDuplicateWorkouts, 1)

        let exported = try HevyCSV.exportData(workouts: [workout], exercises: ExerciseStore.shared.exercises, weightUnit: .imperial)
        let reparsed = try HevyCSV.parse(data: exported)
        XCTAssertEqual(reparsed.records.count, 2)
        XCTAssertEqual(reparsed.records[1].repetitions, 8)
        XCTAssertEqual(reparsed.records[1].rpe, 7.5)
    }

    func testHevyCSVSkipsNonfiniteAndOverflowingNumbersWithoutCrashing() throws {
        let header = "title,start_time,end_time,exercise_title,set_index,weight_kg,reps,distance_km,duration_seconds,rpe"
        let prefix = "Push,2026-08-17T08:16:00Z,2026-08-17T08:35:00Z,Bench Press,"
        let invalidFields = [
            "0,100,NaN,,,", "0,100,inf,,,", "0,100,1e100,,,",
            "1e100,100,8,,,", "NaN,100,8,,,", "0,NaN,8,,,",
            "0,100,8,1e308,,", "0,100,8,,inf,", "0,100,8,,,NaN"
        ]
        let rows = invalidFields.map { prefix + $0 }
            + [prefix + "0,100,8,,60,8"]
        let data = Data(([header] + rows).joined(separator: "\n").utf8)

        let document = try HevyCSV.parse(data: data)

        XCTAssertEqual(document.skippedRows, invalidFields.count)
        XCTAssertEqual(document.records.count, 1)
        XCTAssertEqual(document.records.first?.repetitions, 8)
        XCTAssertEqual(document.records.first?.weightKilograms, 100)
    }

    func testMeasurementInputRejectsNonfiniteAndConvertedOverflow() {
        for raw in ["NaN", "inf", "-1", "0", "1e309", "1e308"] {
            XCTAssertNil(BodyMeasurementKind.height.validatedCanonicalValue(from: raw, weightUnit: .imperial))
        }
        XCTAssertEqual(BodyMeasurementKind.bodyWeight.validatedCanonicalValue(from: "82,5", weightUnit: .metric), 82.5)
    }

    func testInvalidMeasurementDoesNotReplacePersistedEntry() throws {
        let suiteName = "InvalidMeasurementSave.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyMetricsStore(userDefaults: defaults)
        let original = BodyMeasurementEntry(values: [BodyMeasurementKind.bodyWeight.rawValue: 80])
        XCTAssertTrue(store.save(original, exportToHealth: false))
        for invalid in [Double.nan, Double.infinity, -1, 0] {
            var edited = original
            edited[.bodyWeight] = invalid
            XCTAssertFalse(store.save(edited, exportToHealth: false))
            XCTAssertEqual(store.entries, [original])
            XCTAssertEqual(BodyMetricsStore(userDefaults: defaults).entries, [original])
        }
    }

    func testHevyMeasurementImportSkipsNonfiniteAndOverflowingValues() throws {
        let suiteName = "HevyInvalidMeasurements.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyMetricsStore(userDefaults: defaults)
        let data = Data("""
        date,weight_kg,height_in
        2026-08-17T08:00:00Z,NaN,
        2026-08-18T08:00:00Z,inf,
        2026-08-19T08:00:00Z,80,1e308
        2026-08-20T08:00:00Z,80,70
        """.utf8)

        let result = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: store
        )

        XCTAssertEqual(result.skippedRows, 3)
        XCTAssertEqual(result.importedMeasurements, 1)
        XCTAssertEqual(store.entries.first?[.bodyWeight], 80)
        XCTAssertEqual(BodyMetricsStore(userDefaults: defaults).entries, store.entries)
    }

    func testHevyCSVBatchPreflightsEveryFileBeforeWriting() throws {
        let exercise = try XCTUnwrap(ExerciseStore.shared.exercises.first)
        let exerciseTitle = exercise.title.replacingOccurrences(of: "\"", with: "\"\"")
        let header = "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\""
        let row = "\"Push\",\"17 Aug 2026, 08:16\",\"17 Aug 2026, 08:35\",,\"\(exerciseTitle)\",,,0,normal,100,8,,,8"
        let validWorkout = try XCTUnwrap((header + "\n" + row + "\n").data(using: .utf8))
        let malformedSecondFile = try XCTUnwrap("not,a,hevy,export\n".data(using: .utf8))

        XCTAssertThrowsError(
            try HevyCSV.importData(
                [validWorkout, malformedSecondFile],
                into: persistenContainer.viewContext,
                exerciseStore: .shared
            )
        )

        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        XCTAssertTrue(try persistenContainer.viewContext.fetch(request).isEmpty)
    }

    func testHevyCSVBatchCombinesWorkoutAndMeasurementFiles() throws {
        let exercise = try XCTUnwrap(ExerciseStore.shared.exercises.first)
        let exerciseTitle = exercise.title.replacingOccurrences(of: "\"", with: "\"\"")
        let workoutHeader = "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\""
        let workoutRow = "\"Push\",\"17 Aug 2026, 08:16\",\"17 Aug 2026, 08:35\",,\"\(exerciseTitle)\",,,0,normal,100,8,,,8"
        let workoutData = try XCTUnwrap((workoutHeader + "\n" + workoutRow + "\n").data(using: .utf8))

        let measurementHeader = "\"date\",\"weight_lbs\",\"waist_in\""
        let measurementRow = "\"21 Mar 2022, 00:00\",182,32"
        let measurementData = try XCTUnwrap((measurementHeader + "\n" + measurementRow + "\n").data(using: .utf8))

        let suiteName = "HevyCSVBatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let measurementStore = BodyMetricsStore(userDefaults: defaults)

        let result = try HevyCSV.importData(
            [workoutData, measurementData],
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: measurementStore
        )

        XCTAssertEqual(result.importedWorkouts, 1)
        XCTAssertEqual(result.importedSets, 1)
        XCTAssertEqual(result.importedMeasurements, 1)
        XCTAssertEqual(measurementStore.entries.count, 1)
    }

    func testHevyMeasurementCSVImportExportAndDuplicateProtection() throws {
        let suiteName = "HevyMeasurementCSVTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyMetricsStore(userDefaults: defaults)

        let header = "\"date\",\"weight_lbs\",\"fat_percent\",\"height_in\",\"neck_in\",\"shoulder_in\",\"chest_in\",\"left_bicep_in\",\"right_bicep_in\",\"left_forearm_in\",\"right_forearm_in\",\"abdomen_in\",\"waist_in\",\"hips_in\",\"left_thigh_in\",\"right_thigh_in\",\"left_calf_in\",\"right_calf_in\""
        let first = "\"21 Mar 2022, 00:00\",182,18,70,15,,40,,,,,34,32,,,,,"
        let second = "\"31 Mar 2022, 00:00\",180.6,,,,,,,,,,,,,,,,"
        let data = try XCTUnwrap((header + "\r\n" + first + "\n" + second + "\r\n").data(using: .utf8))

        let result = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: store
        )
        XCTAssertEqual(result.importedMeasurements, 2)
        XCTAssertEqual(store.entries.count, 2)
        let oldest = try XCTUnwrap(store.entries.last)
        XCTAssertEqual(oldest[.bodyWeight]!, Measurement(value: 182, unit: UnitMass.pounds).converted(to: .kilograms).value, accuracy: 0.0001)
        XCTAssertEqual(oldest[.height]!, Measurement(value: 70, unit: UnitLength.inches).converted(to: .centimeters).value, accuracy: 0.0001)
        XCTAssertEqual(oldest[.waist]!, Measurement(value: 32, unit: UnitLength.inches).converted(to: .centimeters).value, accuracy: 0.0001)
        XCTAssertEqual(oldest[.bodyFat], 18)

        let duplicateResult = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: store
        )
        XCTAssertEqual(duplicateResult.skippedDuplicateMeasurements, 2)
        XCTAssertEqual(store.entries.count, 2)

        let exported = try HevyCSV.exportMeasurementData(entries: store.entries, weightUnit: .imperial)
        let secondDefaultsName = "HevyMeasurementCSVTests.\(UUID().uuidString)"
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: secondDefaultsName))
        defer { secondDefaults.removePersistentDomain(forName: secondDefaultsName) }
        let secondStore = BodyMetricsStore(userDefaults: secondDefaults)
        let roundTripResult = try HevyCSV.importData(
            exported,
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: secondStore
        )
        XCTAssertEqual(roundTripResult.importedMeasurements, 2)
        XCTAssertEqual(secondStore.entries.count, 2)
        let roundTrippedOldest = try XCTUnwrap(secondStore.entries.last)
        XCTAssertEqual(roundTrippedOldest[.height]!, oldest[.height]!, accuracy: 0.0001)
    }

    func testHevyHeightOnlyMeasurementCSVIsRecognized() throws {
        let suiteName = "HevyHeightOnlyCSVTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyMetricsStore(userDefaults: defaults)
        let data = try XCTUnwrap(
            "\"date\",\"height_cm\"\n\"24 Aug 2026, 09:30\",182.5\n".data(using: .utf8)
        )

        let result = try HevyCSV.importData(
            data,
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: store
        )

        XCTAssertEqual(result.importedMeasurements, 1)
        XCTAssertEqual(store.entries.first?[.height], 182.5)
    }

    func testMeasurementImportHandlesStoredDatesOutsideIntegerRange() throws {
        let suiteName = "HevyExtremeStoredDate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BodyMetricsStore(userDefaults: defaults)
        let existing = BodyMeasurementEntry(
            date: Date(timeIntervalSince1970: 1e100),
            values: [BodyMeasurementKind.bodyWeight.rawValue: 80]
        )
        XCTAssertTrue(store.save(existing, exportToHealth: false))

        let result = try HevyCSV.importData(
            Data("date,weight_kg\n2026-08-17T08:00:00Z,82\n".utf8),
            into: persistenContainer.viewContext,
            exerciseStore: .shared,
            bodyMetricsStore: store
        )

        XCTAssertEqual(result.importedMeasurements, 1)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.entries.contains { $0.id == existing.id })
    }
}
