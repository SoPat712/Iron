//
//  GeneralTests.swift
//  IronTests
//
//  Created by Karim Abou Zeid on 14.01.18.
//  Copyright © 2018 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import CoreData
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

final class WatchWorkoutPersistenceTests: XCTestCase {
    private func snapshot(weight: Double? = 40) -> WatchWorkoutSnapshot {
        let set = WatchWorkoutSet(order: 1, weight: weight, reps: 5)
        let exercise = WatchWorkoutExercise(order: 1, name: "Squat", sets: [set])
        return WatchWorkoutSnapshot(
            workoutID: UUID(),
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            exercises: [exercise],
            selectedSetID: set.id,
            revision: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    private func event(
        workoutID: UUID,
        sequence: Int64,
        kind: WatchWorkoutEventKind = .setUpdated
    ) -> WatchWorkoutEvent {
        WatchWorkoutEvent(
            workoutID: workoutID, sequence: sequence, kind: kind,
            createdAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    func testLegacyPersistedStateKeysRemainDecodable() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "snapshot": NSNull(),
            "outbox": [],
            "nextSequence": 7
        ])

        let decoded = try XCTUnwrap(
            WatchWorkoutWire.decode(WatchWorkoutPersistedState.self, from: data)
        )
        XCTAssertNil(decoded.snapshot)
        XCTAssertTrue(decoded.outbox.isEmpty)
        XCTAssertEqual(decoded.nextSequence, 7)

        let reencoded = try XCTUnwrap(WatchWorkoutWire.encode(decoded))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["outbox", "nextSequence"])

        let populated = WatchWorkoutPersistedState(snapshot: snapshot())
        let populatedData = try XCTUnwrap(WatchWorkoutWire.encode(populated))
        let populatedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: populatedData) as? [String: Any]
        )
        XCTAssertEqual(
            Set(populatedObject.keys),
            ["snapshot", "outbox", "nextSequence"]
        )
    }

    func testSnapshotEventAndSequenceArePreparedTogether() throws {
        let oldSnapshot = snapshot()
        var newSnapshot = oldSnapshot
        newSnapshot.revision += 1
        let current = WatchWorkoutPersistedState(snapshot: oldSnapshot)

        let prepared = try WatchWorkoutPersistence.prepareEvent(
            current: current,
            snapshotChange: .replace(newSnapshot)
        ) { sequence, persistedSnapshot in
            self.event(
                workoutID: persistedSnapshot?.workoutID ?? oldSnapshot.workoutID,
                sequence: sequence
            )
        }

        XCTAssertEqual(prepared.state.snapshot, newSnapshot)
        XCTAssertEqual(prepared.state.nextSequence, 1)
        XCTAssertEqual(prepared.state.outbox, [prepared.result])
        XCTAssertEqual(prepared.result.sequence, 1)
        XCTAssertEqual(
            WatchWorkoutWire.decode(WatchWorkoutPersistedState.self, from: prepared.data),
            prepared.state
        )
    }

    func testInjectedEncodeFailureLeavesCandidateUnpublished() {
        let original = WatchWorkoutPersistedState(snapshot: snapshot(), nextSequence: 4)

        XCTAssertThrowsError(try WatchWorkoutPersistence.prepare(
            current: original,
            encode: { _ in nil }
        ) { candidate in
            candidate.snapshot = nil
            candidate.nextSequence = 9
        }) { error in
            XCTAssertEqual(error as? WatchWorkoutPersistenceError, .encodingFailed)
        }
        XCTAssertNotNil(original.snapshot)
        XCTAssertEqual(original.nextSequence, 4)
        XCTAssertTrue(original.outbox.isEmpty)
    }

    func testNonFinitePayloadFailsRealJSONEncoding() {
        let original = WatchWorkoutPersistedState(snapshot: snapshot())
        let invalid = snapshot(weight: .nan)

        XCTAssertThrowsError(try WatchWorkoutPersistence.prepare(
            current: original
        ) { candidate in
            candidate.snapshot = invalid
        }) { error in
            XCTAssertEqual(error as? WatchWorkoutPersistenceError, .encodingFailed)
        }
        XCTAssertEqual(original.snapshot?.exercises.first?.sets.first?.weight, 40)
    }

    func testDiscardClearsSnapshotAndQueuesEventAtomically() throws {
        let currentSnapshot = snapshot()
        let current = WatchWorkoutPersistedState(snapshot: currentSnapshot, nextSequence: 2)

        let prepared = try WatchWorkoutPersistence.prepareEvent(
            current: current,
            snapshotChange: .replace(nil)
        ) { sequence, _ in
            self.event(
                workoutID: currentSnapshot.workoutID,
                sequence: sequence,
                kind: .workoutDiscarded
            )
        }

        XCTAssertNil(prepared.state.snapshot)
        XCTAssertEqual(prepared.state.nextSequence, 3)
        XCTAssertEqual(prepared.state.outbox.map(\.kind), [.workoutDiscarded])
    }

    func testEventOnlyEncodeFailureDoesNotConsumeSequence() {
        let currentSnapshot = snapshot()
        let original = WatchWorkoutPersistedState(snapshot: currentSnapshot, nextSequence: 12)

        XCTAssertThrowsError(try WatchWorkoutPersistence.prepareEvent(
            current: original,
            snapshotChange: .keep,
            encode: { _ in nil }
        ) { sequence, _ in
            self.event(workoutID: currentSnapshot.workoutID, sequence: sequence)
        })
        XCTAssertEqual(original.nextSequence, 12)
        XCTAssertTrue(original.outbox.isEmpty)
    }

    func testAcknowledgementFailureRetainsEventsAndSuccessRemovesOnlyRequestedIDs() throws {
        let workoutID = UUID()
        let first = event(workoutID: workoutID, sequence: 1)
        let second = event(workoutID: workoutID, sequence: 2)
        let original = WatchWorkoutPersistedState(outbox: [first, second], nextSequence: 2)

        XCTAssertThrowsError(try WatchWorkoutPersistence.prepare(
            current: original,
            encode: { _ in nil }
        ) { candidate in
            candidate.outbox.removeAll { $0.id == first.id }
        })
        XCTAssertEqual(original.outbox, [first, second])

        let acknowledged = try WatchWorkoutPersistence.prepare(current: original) { candidate in
            candidate.outbox.removeAll { $0.id == first.id }
        }
        XCTAssertEqual(acknowledged.state.outbox, [second])
        XCTAssertEqual(acknowledged.state.nextSequence, 2)
    }

    func testSequenceOverflowThrowsWithoutMutation() {
        let currentSnapshot = snapshot()
        let original = WatchWorkoutPersistedState(
            snapshot: currentSnapshot,
            nextSequence: .max
        )

        XCTAssertThrowsError(try WatchWorkoutPersistence.prepareEvent(
            current: original,
            snapshotChange: .keep
        ) { sequence, _ in
            self.event(workoutID: currentSnapshot.workoutID, sequence: sequence)
        }) { error in
            XCTAssertEqual(error as? WatchWorkoutPersistenceError, .sequenceOverflow)
        }
        XCTAssertEqual(original.nextSequence, .max)
        XCTAssertTrue(original.outbox.isEmpty)
    }

    func testRevisionOverflowThrowsWithoutWrapping() {
        var currentSnapshot = snapshot()
        currentSnapshot.revision = .max

        XCTAssertThrowsError(
            try WatchWorkoutPersistence.incrementRevision(&currentSnapshot)
        ) { error in
            XCTAssertEqual(error as? WatchWorkoutPersistenceError, .revisionOverflow)
        }
        XCTAssertEqual(currentSnapshot.revision, .max)
    }
}

final class BodyWeightSampleSelectionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000)

    private func sample(offset: TimeInterval) -> HKQuantitySample {
        let date = referenceDate.addingTimeInterval(offset)
        return HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80),
            start: date,
            end: date
        )
    }

    func testNearbyPastSampleWinsOverMoreDistantFutureSample() {
        let past = sample(offset: -600)
        let future = sample(offset: 3_600)
        XCTAssertEqual(BodyWeightFetcher.closestSample(to: referenceDate, in: [future, past]), past)
    }

    func testNearbyFutureSampleWinsOverMoreDistantPastSample() {
        let past = sample(offset: -3_600)
        let future = sample(offset: 600)
        XCTAssertEqual(BodyWeightFetcher.closestSample(to: referenceDate, in: [past, future]), future)
    }

    func testEmptyQueryHasNoClosestSample() {
        XCTAssertNil(BodyWeightFetcher.closestSample(to: referenceDate, in: []))
    }
}

final class HistoryMutationPersistenceTests: XCTestCase {
    private struct SaveFailure: Error {}

    private func makeHistoryGraph(
        in context: NSManagedObjectContext
    ) throws -> (Workout, WorkoutExercise, WorkoutSet) {
        let workout = Workout.create(context: context)
        workout.title = "Original"
        workout.start = Date(timeIntervalSinceReferenceDate: 1_000)
        workout.end = Date(timeIntervalSinceReferenceDate: 2_000)
        workout.isCurrentWorkout = false
        let workoutExercise = WorkoutExercise.create(context: context)
        workout.addToWorkoutExercises(workoutExercise)
        let set = WorkoutSet.create(context: context)
        workoutExercise.addToWorkoutSets(set)
        set.isCompleted = true
        try context.save()
        return (workout, workoutExercise, set)
    }

    func testFailedMutationRollsBackOnlyItsChangesAndSkipsEffects() throws {
        let context = setUpInMemoryNSPersistentContainer().viewContext
        let (workout, workoutExercise, set) = try makeHistoryGraph(in: context)
        workout.comment = "Unrelated pending edit"
        var effectCount = 0

        XCTAssertThrowsError(try HistoryMutationPersistence.perform(
            context: context,
            save: { throw SaveFailure() },
            mutation: {
                set.isCompleted = false
                let inserted = WorkoutSet.create(context: context)
                workoutExercise.addToWorkoutSets(inserted)
            },
            onSuccess: { effectCount += 1 }
        ))

        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(workoutExercise.workoutSets?.count, 1)
        XCTAssertEqual(workout.comment, "Unrelated pending edit")
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(effectCount, 0)
    }

    func testRetryPersistsMutationAndRunsEffectOnce() throws {
        let context = setUpInMemoryNSPersistentContainer().viewContext
        let (_, _, set) = try makeHistoryGraph(in: context)
        var effectCount = 0

        XCTAssertThrowsError(try HistoryMutationPersistence.perform(
            context: context,
            save: { throw SaveFailure() },
            mutation: { set.repetitionsValue = 8 },
            onSuccess: { effectCount += 1 }
        ))
        XCTAssertEqual(set.repetitionsValue, 0)

        try HistoryMutationPersistence.perform(
            context: context,
            mutation: { set.repetitionsValue = 8 },
            onSuccess: { effectCount += 1 }
        )

        XCTAssertEqual(set.repetitionsValue, 8)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(effectCount, 1)
    }

    func testFailedDeletionRestoresObjectAndRelationship() throws {
        let context = setUpInMemoryNSPersistentContainer().viewContext
        let (_, workoutExercise, set) = try makeHistoryGraph(in: context)

        XCTAssertThrowsError(try HistoryMutationPersistence.perform(
            context: context,
            save: { throw SaveFailure() }
        ) {
            workoutExercise.removeFromWorkoutSets(set)
            context.delete(set)
        })

        XCTAssertFalse(set.isDeleted)
        XCTAssertEqual(workoutExercise.workoutSets?.count, 1)
        XCTAssertTrue(workoutExercise.workoutSets?.contains(set) == true)
    }

    func testTrackingCopyPreservesDurationAndDistanceTogether() {
        let context = setUpInMemoryNSPersistentContainer().viewContext
        let source = WorkoutSet.create(context: context)
        source.durationValue = 75
        source.distanceValue = 400
        source.weightValue = 20
        source.repetitionsValue = 6
        source.rpeValue = 8.5
        source.tagValue = .dropSet
        let destination = WorkoutSet.create(context: context)

        HistorySetTrackingValues.copy(from: source, to: destination)

        XCTAssertEqual(destination.durationValue, 75)
        XCTAssertEqual(destination.distanceValue, 400)
        XCTAssertEqual(destination.weightValue, 20)
        XCTAssertEqual(destination.repetitionsValue, 6)
        XCTAssertEqual(destination.rpeValue, 8.5)
        XCTAssertEqual(destination.tagValue, .dropSet)
    }
}

final class HealthSampleReconciliationTests: XCTestCase {
    private struct Sample: Equatable {
        let id: UUID
        let matches: Bool
    }

    private enum CleanupError: Error, Equatable {
        case failed
    }

    private let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let middleID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private func reconcile(_ samples: [Sample]) -> HealthManager.ExistingSampleReconciliation<Sample> {
        HealthManager.reconcileExistingSamples(
            samples,
            matches: { $0.matches },
            stableID: { $0.id }
        )
    }

    func testSingleMatchingSampleCompletesWithoutDeletingAnything() throws {
        let canonical = Sample(id: lowID, matches: true)
        let decision = reconcile([canonical])
        var deleteCalled = false
        var result: Result<Void, Error>?

        XCTAssertTrue(HealthManager.completeUsingReusableSample(
            decision,
            delete: { _, _ in deleteCalled = true },
            completion: { result = $0 }
        ))

        XCTAssertEqual(decision.reusable, canonical)
        XCTAssertTrue(decision.surplus.isEmpty)
        XCTAssertFalse(deleteCalled)
        try XCTUnwrap(result).get()
    }

    func testCanonicalMatchingSampleIsIndependentOfQueryOrder() {
        let low = Sample(id: lowID, matches: true)
        let middle = Sample(id: middleID, matches: false)
        let high = Sample(id: highID, matches: true)

        let forward = reconcile([high, middle, low])
        let reversed = reconcile([low, middle, high])

        XCTAssertEqual(forward.reusable, low)
        XCTAssertEqual(reversed.reusable, low)
        XCTAssertEqual(Set(forward.surplus.map(\.id)), Set([middleID, highID]))
        XCTAssertEqual(Set(reversed.surplus.map(\.id)), Set([middleID, highID]))
    }

    func testPartialCleanupRetryKeepsCanonicalAndOnlyReturnsRemainingSurplus() {
        let canonical = Sample(id: lowID, matches: true)
        let firstSurplus = Sample(id: middleID, matches: false)
        let remainingSurplus = Sample(id: highID, matches: false)
        let initial = reconcile([firstSurplus, canonical, remainingSurplus])

        XCTAssertEqual(initial.reusable, canonical)
        XCTAssertEqual(Set(initial.surplus.map(\.id)), Set([middleID, highID]))

        let retry = reconcile([remainingSurplus, canonical])
        XCTAssertEqual(retry.reusable, canonical)
        XCTAssertEqual(retry.surplus, [remainingSurplus])
    }

    func testEmptyAndNoMatchRequireReplacementWithoutInventingCleanup() {
        let empty = reconcile([])
        XCTAssertNil(empty.reusable)
        XCTAssertTrue(empty.surplus.isEmpty)

        let samples = [
            Sample(id: lowID, matches: false),
            Sample(id: middleID, matches: false)
        ]
        let noMatch = reconcile(samples)
        XCTAssertNil(noMatch.reusable)
        XCTAssertEqual(noMatch.surplus, samples)
    }

    func testCleanupFailureDeletesOnlySurplusAndCannotSave() {
        let canonical = Sample(id: lowID, matches: true)
        let surplus = Sample(id: middleID, matches: false)
        let decision = reconcile([surplus, canonical])
        var deleted: [Sample] = []
        var result: Result<Void, Error>?

        let handled = HealthManager.completeUsingReusableSample(
            decision,
            delete: { samples, completion in
                deleted = samples
                completion(.failure(CleanupError.failed))
            },
            completion: { result = $0 }
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(deleted, [surplus])
        XCTAssertFalse(deleted.contains(canonical))
        XCTAssertThrowsError(try result?.get()) { error in
            XCTAssertEqual(error as? CleanupError, .failed)
        }
    }

    func testNoMatchIsNotHandledAsCleanup() {
        let decision = reconcile([Sample(id: lowID, matches: false)])
        var deleted = false
        var completed = false

        let handled = HealthManager.completeUsingReusableSample(
            decision,
            delete: { _, _ in deleted = true },
            completion: { _ in completed = true }
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(deleted)
        XCTAssertFalse(completed)
    }
}
