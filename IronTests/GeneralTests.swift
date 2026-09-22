//
//  GeneralTests.swift
//  IronTests
//
//  Created by Karim Abou Zeid on 14.01.18.
//  Copyright © 2018 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import WorkoutDataKit
import UserNotifications
import HealthKit
@testable import Iron

class GeneralTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private func loadExercises() -> [Exercise] {
        let data = try! Data(contentsOf: ExerciseStore.defaultBuiltInExercisesURL)
        return try! JSONDecoder().decode([Exercise].self, from: data)
    }
    
    func testEverkineticGroupingSpeed() {
        let exercises = loadExercises()
        self.measure {
            _ = ExerciseStore.splitIntoMuscleGroups(exercises: exercises)
        }
    }
    
    func testEverkineticGrouping() {
        let exercises = loadExercises()
        let groups = ExerciseStore.splitIntoMuscleGroups(exercises: exercises)
        var totalCount = 0
        for group in groups {
            totalCount += group.exercises.count

            for exercise in group.exercises {
                XCTAssert(exercise.muscleGroup == group.title)
            }
        }
        XCTAssert(totalCount == exercises.count)
    }

    func testEverkineticPDFsExist() {
        let exercises = loadExercises()
        for exercise in exercises {
            for pdf in exercise.pdfPaths {
                let url = ExerciseStore.defaultBuiltInExercisesResourceURL.appendingPathComponent(pdf)
                XCTAssertNoThrow(try Data(contentsOf: url))
            }
        }
    }

    func testUniq() {
        var array = ["Hello","Me","That","Me","Hello","Me","as","the"]
        
        let arrayUniqed = array.uniqed()
        XCTAssertEqual(arrayUniqed, ["Hello","Me","That","as","the"])
        
        array.uniq()
        XCTAssertEqual(array, arrayUniqed)
    }
    
    func testSortByFrequency() {
        var array = ["Hello","Me","That","Me","Hello","Me"]
        
        let arraySorted = array.sortedByFrequency()
        XCTAssertEqual(arraySorted, ["That", "Hello", "Hello", "Me", "Me", "Me"])
        
        array.sortByFrequency()
        XCTAssertEqual(array, arraySorted)
    }

    func testWeightUnitConversion() {
        // correct conversion
        XCTAssertEqual(WeightUnit.convert(weight: 20, from: .metric, to: .imperial).rounded(), 44)
        XCTAssertEqual(WeightUnit.convert(weight: 45, from: .imperial, to: .metric).rounded(), 20)
        
        // no precision loss when converting back and forth
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 20, from: .metric, to: .imperial), from: .imperial, to: .metric), 20)
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 127.5, from: .metric, to: .imperial), from: .imperial, to: .metric), 127.5)
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 123980323.59392, from: .metric, to: .imperial), from: .imperial, to: .metric), 123980323.59392)
        
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 45, from: .imperial, to: .metric), from: .metric, to: .imperial), 45)
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 900, from: .imperial, to: .metric), from: .metric, to: .imperial), 900)
        XCTAssertEqual(WeightUnit.convert(weight: WeightUnit.convert(weight: 123980323.59392, from: .imperial, to: .metric), from: .metric, to: .imperial), 123980323.59392)
    }
}

final class RestTimerStoreTests: XCTestCase {
    private final class Effects {
        var notificationUpdates: [(Date?, TimeInterval?)] = []
        var watchUpdates: [Date?] = []
        var scheduledDeadlines: [Date] = []
        var scheduledHandlers: [() -> Void] = []
        var cancellations = 0
        var announcements = 0
    }

    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    private func makeStore(
        now: @escaping () -> Date,
        configureDefaults: ((UserDefaults) -> Void)? = nil
    ) -> (RestTimerStore, Effects) {
        let suiteName = "RestTimerStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        configureDefaults?(defaults)
        let effects = Effects()
        let store = RestTimerStore(
            userDefaults: defaults,
            now: now,
            keepRunning: { false },
            notificationUpdater: { deadline, total in
                effects.notificationUpdates.append((deadline, total))
            },
            watchUpdater: { end in effects.watchUpdates.append(end) },
            expiryScheduler: { deadline, handler in
                effects.scheduledDeadlines.append(deadline)
                effects.scheduledHandlers.append(handler)
                return { effects.cancellations += 1 }
            },
            expiryAnnouncement: { effects.announcements += 1 }
        )
        return (store, effects)
    }

    func testPauseClearsDeadlineAndDoesNotScheduleExpiry() {
        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(now: { currentTime })
        store.start(duration: 90)
        currentTime.addTimeInterval(20)

        store.pause()

        XCTAssertTrue(store.isPaused)
        XCTAssertNil(store.restTimerStart)
        XCTAssertEqual(store.restTimerRemainingTime ?? -1, 70, accuracy: 0.001)
        XCTAssertNil(effects.notificationUpdates.last?.0)
        XCTAssertEqual(effects.scheduledHandlers.count, 1)
        XCTAssertEqual(effects.cancellations, 1)
    }

    func testResumeUsesCapturedRemainingInsteadOfRestartingTotalDuration() {
        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(now: { currentTime })
        store.start(duration: 120)
        currentTime.addTimeInterval(45)
        store.pause()
        currentTime.addTimeInterval(30)

        store.resume()

        XCTAssertFalse(store.isPaused)
        XCTAssertEqual(store.restTimerDuration, 120)
        XCTAssertEqual(store.restTimerRemainingTime ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(store.restTimerEnd, currentTime.addingTimeInterval(75))
        XCTAssertEqual(effects.scheduledDeadlines.last, currentTime.addingTimeInterval(75))
    }

    func testAdjustToZeroCancelsAllTimerState() {
        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(now: { currentTime })
        store.start(duration: 30)

        store.adjust(by: -30)

        XCTAssertNil(store.restTimerStart)
        XCTAssertNil(store.restTimerDuration)
        XCTAssertNil(store.restTimerRemainingTime)
        XCTAssertNil(effects.notificationUpdates.last?.0)
        XCTAssertEqual(effects.announcements, 1)
    }

    func testPositiveAdjustmentRestartsAnExpiredTimerFromNow() {
        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, _) = makeStore(now: { currentTime })
        store.start(duration: 10)
        currentTime.addTimeInterval(15)

        store.adjust(by: 30)

        XCTAssertEqual(store.restTimerStart, currentTime)
        XCTAssertEqual(store.restTimerDuration, 30)
        XCTAssertEqual(store.restTimerRemainingTime ?? -1, 30, accuracy: 0.001)
    }

    func testWatchUpdatePublishesOneEffectBatchWithoutEchoingToWatch() {
        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(now: { currentTime })
        let end = currentTime.addingTimeInterval(45)

        store.applyWatchUpdate(end: end)

        XCTAssertEqual(store.restTimerEnd, end)
        XCTAssertEqual(effects.notificationUpdates.count, 1)
        XCTAssertEqual(effects.scheduledDeadlines, [end])
        XCTAssertTrue(effects.watchUpdates.isEmpty)
    }

    func testCancelledExpiryCallbackCannotAnnounceAfterReplacement() {
        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(now: { currentTime })
        store.start(duration: 30)
        let staleHandler = effects.scheduledHandlers[0]
        store.setRemaining(60)

        staleHandler()

        XCTAssertEqual(effects.announcements, 0)
        XCTAssertEqual(store.restTimerRemainingTime ?? -1, 60, accuracy: 0.001)
    }

    func testInitializationRestoresExpiryForPersistedRunningTimer() {
        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let start = currentTime.addingTimeInterval(-15)
        let (store, effects) = makeStore(
            now: { currentTime },
            configureDefaults: { defaults in
                defaults.restTimerStart = start
                defaults.restTimerDuration = 60
            }
        )

        XCTAssertEqual(store.restTimerRemainingTime ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(effects.scheduledDeadlines, [currentTime.addingTimeInterval(45)])
    }

    func testInitializationDoesNotSchedulePersistedPausedTimer() {
        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, effects) = makeStore(
            now: { currentTime },
            configureDefaults: { defaults in
                defaults.restTimerDuration = 60
                defaults.restTimerPausedRemaining = 20
            }
        )

        XCTAssertTrue(store.isPaused)
        XCTAssertTrue(effects.scheduledDeadlines.isEmpty)
    }

    func testRestTimerSoundRequiresBothAppAndSystemSoundSettings() {
        XCTAssertTrue(NotificationManager.shouldPlayRestTimerSound(
            appSoundsEnabled: true,
            systemSoundSetting: .enabled
        ))
        XCTAssertFalse(NotificationManager.shouldPlayRestTimerSound(
            appSoundsEnabled: false,
            systemSoundSetting: .enabled
        ))
        XCTAssertFalse(NotificationManager.shouldPlayRestTimerSound(
            appSoundsEnabled: true,
            systemSoundSetting: .disabled
        ))
    }
}

final class HealthReplacementCoordinatorTests: XCTestCase {
    private enum ExpectedError: Error, Equatable {
        case save
        case cleanup
    }

    func testReplacementSavesNewObjectsBeforeDeletingExactOldObjects() {
        var operations: [String] = []
        var savedObjects: [Int] = []
        var deletedObjects: [Int] = []
        var result: Result<Void, Error>?

        HealthManager.coordinateReplacement(
            oldObjects: [11, 12],
            replacements: [21],
            intent: .replace,
            save: { objects, completion in
                operations.append("save")
                savedObjects = objects
                completion(.success(()))
            },
            delete: { objects, completion in
                operations.append("delete")
                deletedObjects = objects
                completion(.success(()))
            },
            completion: { result = $0 }
        )

        XCTAssertEqual(operations, ["save", "delete"])
        XCTAssertEqual(savedObjects, [21])
        XCTAssertEqual(deletedObjects, [11, 12])
        XCTAssertNoThrow(try result?.get())
    }

    func testFailedReplacementSaveKeepsOldObjects() {
        var deleted = false
        var capturedError: ExpectedError?

        HealthManager.coordinateReplacement(
            oldObjects: [11],
            replacements: [21],
            intent: .replace,
            save: { _, completion in completion(.failure(ExpectedError.save)) },
            delete: { _, _ in deleted = true },
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error as? ExpectedError
                }
            }
        )

        XCTAssertFalse(deleted)
        XCTAssertEqual(capturedError, .save)
    }

    func testCleanupFailureIsReportedAfterSuccessfulSave() {
        var operations: [String] = []
        var capturedError: ExpectedError?

        HealthManager.coordinateReplacement(
            oldObjects: [11],
            replacements: [21],
            intent: .replace,
            save: { _, completion in
                operations.append("save")
                completion(.success(()))
            },
            delete: { _, completion in
                operations.append("delete")
                completion(.failure(ExpectedError.cleanup))
            },
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error as? ExpectedError
                }
            }
        )

        XCTAssertEqual(operations, ["save", "delete"])
        XCTAssertEqual(capturedError, .cleanup)
    }

    func testEmptyReplacementIsNoOpWithoutExplicitDeleteIntent() {
        var operations: [String] = []
        var succeeded = false

        HealthManager.coordinateReplacement(
            oldObjects: [11],
            replacements: [Int](),
            intent: .replace,
            save: { _, _ in operations.append("save") },
            delete: { _, _ in operations.append("delete") },
            completion: { result in
                if case .success = result { succeeded = true }
            }
        )

        XCTAssertTrue(succeeded)
        XCTAssertTrue(operations.isEmpty)
    }

    func testExplicitDeleteRemovesCapturedOldObjectsWithoutSaving() {
        var saved = false
        var deletedObjects: [Int] = []
        var succeeded = false

        HealthManager.coordinateReplacement(
            oldObjects: [11, 12],
            replacements: [Int](),
            intent: .delete,
            save: { _, _ in saved = true },
            delete: { objects, completion in
                deletedObjects = objects
                completion(.success(()))
            },
            completion: { result in
                if case .success = result { succeeded = true }
            }
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(deletedObjects, [11, 12])
        XCTAssertTrue(succeeded)
    }

    func testReplacementMetadataStripsHealthSyncIdentityAndPreservesOtherMetadata() {
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: "old-sync-id",
            HKMetadataKeySyncVersion: 7,
            HKMetadataKeyExternalUUID: "old-external-id",
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeyWorkoutBrandName: "Old title"
        ]

        let replacement = HealthManager.replacementMetadata(
            copying: metadata,
            externalUUID: "new-external-id",
            title: "New title"
        )

        XCTAssertNil(replacement[HKMetadataKeySyncIdentifier])
        XCTAssertNil(replacement[HKMetadataKeySyncVersion])
        XCTAssertEqual(replacement[HKMetadataKeyExternalUUID] as? String, "new-external-id")
        XCTAssertEqual(replacement[HKMetadataKeyIndoorWorkout] as? Bool, true)
        XCTAssertEqual(replacement[HKMetadataKeyWorkoutBrandName] as? String, "New title")
    }

    func testWorkoutFieldMatchingIncludesDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let end = start.addingTimeInterval(60)

        XCTAssertTrue(HealthManager.workoutFieldsMatch(
            existingStart: start,
            existingEnd: end,
            existingDuration: 60,
            existingTitle: "Workout",
            desiredStart: start,
            desiredEnd: end,
            desiredDuration: 60,
            desiredTitle: "Workout"
        ))
        XCTAssertFalse(HealthManager.workoutFieldsMatch(
            existingStart: start,
            existingEnd: end,
            existingDuration: 30,
            existingTitle: "Workout",
            desiredStart: start,
            desiredEnd: end,
            desiredDuration: 60,
            desiredTitle: "Workout"
        ))
    }

    func testWorkoutIntervalValidationRejectsInvalidDatesAndDurations() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let end = start.addingTimeInterval(60)

        XCTAssertTrue(HealthManager.isValidWorkoutInterval(
            start: start,
            end: end,
            duration: 60
        ))
        XCTAssertFalse(HealthManager.isValidWorkoutInterval(
            start: end,
            end: start,
            duration: 60
        ))
        XCTAssertFalse(HealthManager.isValidWorkoutInterval(
            start: start,
            end: end,
            duration: .nan
        ))
        XCTAssertFalse(HealthManager.isValidWorkoutInterval(
            start: Date(timeIntervalSinceReferenceDate: .infinity),
            end: end,
            duration: 60
        ))
    }
}

final class HealthMutationCoordinatorTests: XCTestCase {
    func testSecondQueryWaitsForFirstCleanup() throws {
        let coordinator = HealthManager.MutationCoordinator()
        var operations: [String] = []
        var finishFirst: (() -> Void)?

        coordinator.enqueue { finish in
            operations.append("first query")
            operations.append("first save")
            finishFirst = {
                operations.append("first cleanup")
                finish()
            }
        }
        coordinator.enqueue { finish in
            operations.append("second query")
            finish()
        }

        XCTAssertEqual(operations, ["first query", "first save"])
        try XCTUnwrap(finishFirst)()
        XCTAssertEqual(
            operations,
            ["first query", "first save", "first cleanup", "second query"]
        )
    }

    func testQueuedSaveThenDeleteEndsDeleted() throws {
        let coordinator = HealthManager.MutationCoordinator()
        var sampleExists = false
        var finishSave: (() -> Void)?

        coordinator.enqueue { finish in
            sampleExists = true
            finishSave = finish
        }
        coordinator.enqueue { finish in
            XCTAssertTrue(sampleExists)
            sampleExists = false
            finish()
        }

        XCTAssertTrue(sampleExists)
        try XCTUnwrap(finishSave)()
        XCTAssertFalse(sampleExists)
    }

    func testFailedJobReleasesNextMutation() throws {
        let coordinator = HealthManager.MutationCoordinator()
        var operations: [String] = []
        var failFirst: (() -> Void)?

        coordinator.enqueue { finish in
            operations.append("first failed")
            failFirst = finish
        }
        coordinator.enqueue { finish in
            operations.append("second started")
            finish()
        }

        XCTAssertEqual(operations, ["first failed"])
        try XCTUnwrap(failFirst)()
        XCTAssertEqual(operations, ["first failed", "second started"])
    }

    func testDuplicateFinishCannotAdvanceQueueTwice() throws {
        let coordinator = HealthManager.MutationCoordinator()
        var operations: [String] = []
        var finishFirst: (() -> Void)?
        var finishSecond: (() -> Void)?

        coordinator.enqueue { finish in
            operations.append("first")
            finishFirst = finish
        }
        coordinator.enqueue { finish in
            operations.append("second")
            finishSecond = finish
        }
        coordinator.enqueue { finish in
            operations.append("third")
            finish()
        }

        let firstCompletion = try XCTUnwrap(finishFirst)
        firstCompletion()
        firstCompletion()
        XCTAssertEqual(operations, ["first", "second"])

        try XCTUnwrap(finishSecond)()
        XCTAssertEqual(operations, ["first", "second", "third"])
    }
}
