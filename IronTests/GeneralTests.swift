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
