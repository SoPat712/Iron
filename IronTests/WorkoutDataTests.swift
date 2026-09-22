//
//  WorkoutDataTests.swift
//  IronTests
//
//  Created by Karim Abou Zeid on 15.02.18.
//  Copyright © 2018 Karim Abou Zeid Software. All rights reserved.
//

import XCTest
import CoreData
import Combine
import WorkoutDataKit
@testable import Iron

class WorkoutDataTests: XCTestCase {
    var persistenContainer: NSPersistentContainer!
    
    var testWorkouts: [Workout]!
    var testWorkoutExercises: [WorkoutExercise]!
    var testWorkoutSets: [WorkoutSet]!
    
    var testCurrentWorkout: Workout!
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        persistenContainer = setUpInMemoryNSPersistentContainer()

        createTestWorkoutData(context: persistenContainer.viewContext)
        testCurrentWorkout = createTestCurrentWorkout(context: persistenContainer.viewContext)
        
        testWorkouts = try? persistenContainer.viewContext.fetch(Workout.fetchRequest())
        testWorkoutExercises = try? persistenContainer.viewContext.fetch(WorkoutExercise.fetchRequest())
        testWorkoutSets = try? persistenContainer.viewContext.fetch(WorkoutSet.fetchRequest())

        XCTAssertNotNil(testWorkouts)
        XCTAssertTrue(testWorkouts.count > 0)
        XCTAssertTrue(testWorkouts.count == 2) // might change in future
        XCTAssertNotNil(testWorkoutExercises)
        XCTAssertTrue(testWorkoutExercises.count > 0)
        XCTAssertNotNil(testWorkoutSets)
        XCTAssertTrue(testWorkoutSets.count > 0)
        
        XCTAssertNotNil(testCurrentWorkout)
        
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        persistenContainer.viewContext.reset()
        persistenContainer = nil
        
        testWorkouts = nil
        testWorkoutExercises = nil
        testWorkoutSets = nil
        testCurrentWorkout = nil
        
        super.tearDown()
    }
    
    func testWorkoutExerciseNumberOfCompletedSets() {
        for workoutExercise in testWorkoutExercises {
            let count = workoutExercise.workoutSets?.filter({ (set) -> Bool in
                (set as! WorkoutSet).isCompleted == true
            }).count
            XCTAssertTrue(workoutExercise.numberOfCompletedSets == count)
        }
    }
    
    func testRelationshipDeleteRules() {
        for workout in testWorkouts {
            let workoutExercises = workout.workoutExercises!.array.map { $0 as! WorkoutExercise }
            
            let workoutExercise = workoutExercises.first!
            let workoutSets = workoutExercise.workoutSets!.array.map { $0 as! WorkoutSet }
            
            // set deletion doesn't delete exercise
            let workoutSet = workoutSets.first!
            persistenContainer.viewContext.delete(workoutSet)
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
            XCTAssertNil(workoutSet.managedObjectContext)
            XCTAssertNotNil(workoutExercise.managedObjectContext)
            
            // exercise deletion doesn't delete workout, but deletes sets
            persistenContainer.viewContext.delete(workoutExercise)
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
            XCTAssertNil(workoutExercise.managedObjectContext)
            XCTAssertTrue(workoutSets.reduce(true, { $0 && $1.managedObjectContext == nil }))
            XCTAssertNotNil(workout.managedObjectContext)

            // workout deletion deletes exercises
            persistenContainer.viewContext.delete(workout)
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
            XCTAssertNil(workout.managedObjectContext)
            XCTAssertTrue(workoutExercises.reduce(true, { $0 && $1.managedObjectContext == nil }))
        }
    }
    
    func uncompletedSetsSwift(workout: Workout) -> [WorkoutSet]? {
        return workout.workoutExercises?
            .compactMap { $0 as? WorkoutExercise }
            .compactMap { $0.workoutSets?.array as? [WorkoutSet] }
            .flatMap { $0 }
            .filter { !$0.isCompleted }
    }
    
    func uncompletedSetsFetch(workout: Workout) -> [WorkoutSet]? {
        let fetchRequest: NSFetchRequest<WorkoutSet> = WorkoutSet.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "\(#keyPath(WorkoutSet.workoutExercise.workout)) == %@ AND \(#keyPath(WorkoutSet.isCompleted)) == %@", workout, NSNumber(booleanLiteral: false))
        return try? workout.managedObjectContext?.fetch(fetchRequest)
    }
    
    func testUncompletedSets() {
        for workout in testWorkouts {
            XCTAssertEqual(Set(uncompletedSetsSwift(workout: workout) ?? []), Set(uncompletedSetsFetch(workout: workout) ?? []))
        }
    }
    
    func testUncompletedSetsSwift() {
        self.measure {
            for workout in testWorkouts {
                _ = uncompletedSetsSwift(workout: workout)
            }
        }
    }
    
    func testUncompletedSetsFetch() {
        self.measure {
            for workout in testWorkouts {
                _ = uncompletedSetsFetch(workout: workout)
            }
        }
    }
    
    func testDeleteUncompletedSets() {
        testCurrentWorkout.deleteUncompletedSets()
        XCTAssertTrue(
            testCurrentWorkout.workoutExercises?
                .compactMap { $0 as? WorkoutExercise }
                .compactMap { $0.workoutSets?.array as? [WorkoutSet] }
                .flatMap { $0 }
                .filter { !$0.isCompleted }
                .isEmpty ?? true
        )
    }
    
    func testDeleteExercisesWhereAllSetsAreUncompleted() {
        testCurrentWorkout.deleteExercisesWhereAllSetsAreUncompleted()
        XCTAssertTrue(
            testCurrentWorkout.workoutExercises?
                .compactMap { $0 as? WorkoutExercise }
                .compactMap { $0.workoutSets?.array as? [WorkoutSet] }
                .filter { $0.reduce(true, { $0 && !$1.isCompleted }) }
                .isEmpty ?? true
        )
    }
    
    func testStartEndValidation() {
        for workout in testWorkouts {
            if let start = workout.start, let end = workout.end {
                workout.start = end
                workout.end = start
                XCTAssertThrowsError(try persistenContainer.viewContext.save())
                
                workout.start = nil
                workout.end = end
                XCTAssertThrowsError(try persistenContainer.viewContext.save())
                
                workout.start = start
                workout.end = nil
                if workout.isCurrentWorkout {
                    XCTAssertNoThrow(try persistenContainer.viewContext.save())
                } else {
                    XCTAssertThrowsError(try persistenContainer.viewContext.save())
                }
            }
        }
    }
    
    func testUuidRequired() {
        for workout in testWorkouts {
            workout.uuid = nil
            XCTAssertThrowsError(try persistenContainer.viewContext.save())
            workout.uuid = UUID()
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
        }
        
        for workoutExercise in testWorkoutExercises {
            workoutExercise.uuid = nil
            XCTAssertThrowsError(try persistenContainer.viewContext.save())
            workoutExercise.uuid = UUID()
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
        }
        
        for workoutSet in testWorkoutSets{
            workoutSet.uuid = nil
            XCTAssertThrowsError(try persistenContainer.viewContext.save())
            workoutSet.uuid = UUID()
            XCTAssertNoThrow(try persistenContainer.viewContext.save())
        }
        
        // TODO: also for workout plans
    }
    
    func testCurrentWorkoutValidation() {
        XCTAssertEqual(try persistenContainer.viewContext.count(for: Workout.currentWorkoutFetchRequest), 1)
        let workout = createTestCurrentWorkout(context: persistenContainer.viewContext)
        XCTAssertEqual(try persistenContainer.viewContext.count(for: Workout.currentWorkoutFetchRequest), 2)
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        persistenContainer.viewContext.delete(workout)
        XCTAssertEqual(try persistenContainer.viewContext.count(for: Workout.currentWorkoutFetchRequest), 1)
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
        persistenContainer.viewContext.delete(testCurrentWorkout)
        XCTAssertEqual(try persistenContainer.viewContext.count(for: Workout.currentWorkoutFetchRequest), 0)
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
        _ = createTestCurrentWorkout(context: persistenContainer.viewContext)
        XCTAssertEqual(try persistenContainer.viewContext.count(for: Workout.currentWorkoutFetchRequest), 1)
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    func testWorkoutIsCompletedValidation() {
        testCurrentWorkout.isCurrentWorkout = false
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        testCurrentWorkout.isCurrentWorkout = true
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
        
        for workoutSet in testWorkoutSets {
            if let workout = workoutSet.workoutExercise?.workout, !workout.isCurrentWorkout {
                workoutSet.isCompleted = false
                XCTAssertThrowsError(try persistenContainer.viewContext.save())
                workoutSet.isCompleted = true
                XCTAssertNoThrow(try persistenContainer.viewContext.save())
            }
        }
    }
    
    func testDetachedWorkoutExercise() {
        let workoutExercise = WorkoutExercise.create(context: persistenContainer.viewContext)
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        workoutExercise.workout = testWorkouts.first
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    func testDetachedWorkoutSet() {
        let workoutSet = WorkoutSet.create(context: persistenContainer.viewContext)
        workoutSet.isCompleted = true
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        workoutSet.workoutExercise = testWorkoutExercises.first
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    func testUncompletedSet() {
        let workoutSet = WorkoutSet.create(context: persistenContainer.viewContext)
        workoutSet.isCompleted = false
        workoutSet.workoutExercise = testCurrentWorkout.workoutExercises?.firstObject as? WorkoutExercise
        XCTAssertNotNil(workoutSet.workoutExercise)
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
        workoutSet.workoutExercise = testWorkoutExercises.first { !$0.workout!.isCurrentWorkout }
        XCTAssertThrowsError(try persistenContainer.viewContext.save())
        workoutSet.isCompleted = true
        XCTAssertNoThrow(try persistenContainer.viewContext.save())
    }
    
    func testWorkoutIsCompleted() {
        for workout in testWorkouts {
            if !workout.isCurrentWorkout {
                XCTAssertTrue(workout.isCompleted!)
            }
        }
    }
    
    func testWorkoutHasCompletedSets() {
        let workout = Workout.create(context: persistenContainer.viewContext)
        XCTAssertFalse(workout.hasCompletedSets!)
        
        let exercise = WorkoutExercise.create(context: persistenContainer.viewContext)
        workout.addToWorkoutExercises(exercise)
        XCTAssertFalse(workout.hasCompletedSets!)
        
        let set = WorkoutSet.create(context: persistenContainer.viewContext)
        exercise.addToWorkoutSets(set)
        XCTAssertFalse(workout.hasCompletedSets!)
        
        set.isCompleted = true
        XCTAssertTrue(workout.hasCompletedSets!)
        
        for workout in testWorkouts {
            XCTAssertTrue(workout.hasCompletedSets!)
        }
    }

    func testWorkoutStartedFromPlanUsesPlanNameWithoutPersistenceContainerTitle() {
        let context = persistenContainer.viewContext
        let persistedContainer = WorkoutPlan.create(context: context)
        persistedContainer.title = "Workout Plan"

        let plan = WorkoutRoutine.create(context: context)
        plan.title = "Pull"
        persistedContainer.addToWorkoutRoutines(plan)

        let workout = plan.createWorkout(context: context)

        XCTAssertEqual(workout.title, "Pull")
        XCTAssertEqual(workout.displayTitle(in: []), "Pull")

        plan.title = "Renamed later"
        XCTAssertEqual(workout.displayTitle(in: []), "Pull")
    }

    func testWorkoutStartedFromUnnamedPlanSnapshotsFallbackName() {
        let context = persistenContainer.viewContext
        let persistedContainer = WorkoutPlan.create(context: context)
        let plan = WorkoutRoutine.create(context: context)
        persistedContainer.addToWorkoutRoutines(plan)

        let workout = plan.createWorkout(context: context)

        XCTAssertEqual(workout.title, "Workout A")
        XCTAssertEqual(workout.displayTitle(in: []), "Workout A")
    }
    
    func testSendObjectsWillChange() {
        let workout = Workout.create(context: persistenContainer.viewContext)
        let workoutExercise1 = WorkoutExercise.create(context: persistenContainer.viewContext)
        let workoutExercise2 = WorkoutExercise.create(context: persistenContainer.viewContext)
        let workoutSet1_1 = WorkoutSet.create(context: persistenContainer.viewContext)
        let workoutSet1_2 = WorkoutSet.create(context: persistenContainer.viewContext)
        let workoutSet2_1 = WorkoutSet.create(context: persistenContainer.viewContext)
        let workoutSet2_2 = WorkoutSet.create(context: persistenContainer.viewContext)
        
        workout.start = Date()
        workout.end = Date()
        workoutSet1_1.isCompleted = true
        workoutSet1_2.isCompleted = true
        workoutSet2_1.isCompleted = true
        workoutSet2_2.isCompleted = true
        
        workoutExercise1.addToWorkoutSets([workoutSet1_1, workoutSet1_2])
        workoutExercise2.addToWorkoutSets([workoutSet2_1, workoutSet2_2])
        workout.addToWorkoutExercises([workoutExercise1, workoutExercise2])
        
        try! persistenContainer.viewContext.save()
        
        var cancellables = Set<AnyCancellable>()
        persistenContainer.viewContext.publisher.sink { WorkoutDataStorage.sendObjectsWillChange(changes: $0) }.store(in: &cancellables)
        
        var expectations = changeExpectations(reason: "increment weight", objects: [
            (workoutSet1_1.workoutExercise!.workout!, true),
            (workoutSet1_1.workoutExercise!, true),
            (workoutSet1_1, true),
            (workoutSet1_2, false),
            (workoutSet2_1, false),
            (workoutSet2_2, false)
        ], store: &cancellables)
        workoutSet1_1.weightValue += 1
        wait(for: expectations, timeout: 1)
        
        expectations = changeExpectations(reason: "set exercise uuid", objects: [
            (workoutExercise1.workout!, true),
            (workoutExercise1, true),
            (workoutExercise2, false),
            (workoutSet1_1, true),
            (workoutSet1_2, true),
            (workoutSet2_1, false),
            (workoutSet2_2, false)
        ], store: &cancellables)
        workoutExercise1.exerciseUuid = UUID()
        wait(for: expectations, timeout: 1)
        
        expectations = changeExpectations(reason: "set workout title", objects: [
            (workout, true),
            (workoutExercise1, true),
            (workoutExercise2, true),
            (workoutSet1_1, true),
            (workoutSet1_2, true),
            (workoutSet2_1, true),
            (workoutSet2_2, true)
        ], store: &cancellables)
        workout.title = "Test"
        wait(for: expectations, timeout: 1)
    }

    func testWatchWorkoutSetDisplayTextUsesOnlyRelevantUnits() {
        let weighted = WatchWorkoutSet(order: 1, weight: 65, reps: 8)
        XCTAssertEqual(weighted.displayText(weightUnit: .kilogram), "65 kg × 8")

        let fractional = WatchWorkoutSet(order: 2, weight: 37.5, reps: 9)
        XCTAssertEqual(fractional.displayText(weightUnit: .pound), "37.5 lb × 9")

        let bodyweight = WatchWorkoutSet(order: 3, weight: 0, reps: 5)
        XCTAssertEqual(bodyweight.displayText(weightUnit: .pound), "5 reps")

        let previousBodyweight = WatchWorkoutSet(
            order: 4,
            weight: 0,
            reps: 8,
            previousWeight: 0,
            previousReps: 6
        )
        XCTAssertEqual(previousBodyweight.previousDisplayText(weightUnit: .pound), "6 reps")
    }
    
    private func changeExpectations(reason: String = "", objects: [(NSManagedObject, Bool)], store: inout Set<AnyCancellable>) -> [XCTestExpectation] {
        objects.map {
            let expectation = XCTestExpectation(description: "\($0.0.entity.name ?? "object") for \(reason)")
            expectation.isInverted = !$0.1
            $0.0.objectWillChange.sink { _ in expectation.fulfill() }.store(in: &store)
            return expectation
        }
    }
}

@available(iOS 16.1, *)
final class WorkoutLiveActivityStateTests: XCTestCase {
    private let completedSet = WorkoutActivityAttributes.SetSnapshot(
        setID: "completed-set",
        exerciseName: "Deadlift (Barbell)",
        setNumber: 1,
        setCount: 4,
        result: "135 lb × 5 reps"
    )
    private let nextSet = WorkoutActivityAttributes.SetSnapshot(
        setID: "next-set",
        exerciseName: "Deadlift (Barbell)",
        setNumber: 2,
        setCount: 4,
        result: "135 lb × 5 reps"
    )

    func testCompletionAdvancesToRestThenNextSet() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let state = WorkoutActivityAttributes.ContentState(
            phase: .setCompleted,
            displaySet: completedSet,
            nextSet: nextSet,
            confirmationUntil: now.addingTimeInterval(10),
            restTimerStart: now,
            restTimerEnd: now.addingTimeInterval(70),
            completedSets: 1,
            totalSets: 4
        )

        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(9.9)), .setCompleted)
        XCTAssertEqual(state.visibleSet(at: now.addingTimeInterval(9.9)), completedSet)
        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(10)), .resting)
        XCTAssertEqual(state.visibleSet(at: now.addingTimeInterval(10)), nextSet)
        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(69.9)), .resting)
        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(70)), .currentSet)
        XCTAssertEqual(state.visibleSet(at: now.addingTimeInterval(70)), nextSet)
    }

    func testFinalSetFinishesAfterConfirmationWithoutAnUnusedRestPhase() {
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let state = WorkoutActivityAttributes.ContentState(
            phase: .setCompleted,
            displaySet: completedSet,
            nextSet: nil,
            confirmationUntil: now.addingTimeInterval(10),
            restTimerStart: now,
            restTimerEnd: now.addingTimeInterval(30),
            completedSets: 4,
            totalSets: 4
        )

        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(10)), .finished)
        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(30)), .finished)
    }

    func testPublishedRestPhaseStillAdvancesIfTheAppSuspends() {
        let now = Date(timeIntervalSinceReferenceDate: 30_000)
        let state = WorkoutActivityAttributes.ContentState(
            phase: .resting,
            displaySet: completedSet,
            nextSet: nextSet,
            confirmationUntil: nil,
            restTimerStart: now,
            restTimerEnd: now.addingTimeInterval(20),
            completedSets: 1,
            totalSets: 4
        )

        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(19.9)), .resting)
        XCTAssertEqual(state.resolvedPhase(at: now.addingTimeInterval(20)), .currentSet)
        XCTAssertEqual(state.visibleSet(at: now.addingTimeInterval(20)), nextSet)
    }

    func testRestProgressClampsAtBothBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        let state = WorkoutActivityAttributes.ContentState(
            phase: .resting,
            displaySet: completedSet,
            nextSet: nextSet,
            confirmationUntil: nil,
            restTimerStart: now,
            restTimerEnd: now.addingTimeInterval(60),
            completedSets: 1,
            totalSets: 4
        )

        XCTAssertEqual(state.restProgress(at: now.addingTimeInterval(-1)), 0)
        XCTAssertEqual(state.restProgress(at: now.addingTimeInterval(30)), 0.5)
        XCTAssertEqual(state.restProgress(at: now.addingTimeInterval(61)), 1)
    }
}

@available(iOS 17.0, *)
final class WorkoutLiveActivityReconciliationTests: XCTestCase {
    private var persistentContainer: NSPersistentContainer!
    private var workout: Workout!
    private var exercise: WorkoutExercise!
    private var sets: [WorkoutSet]!

    override func setUp() {
        super.setUp()
        persistentContainer = setUpInMemoryNSPersistentContainer()
        let context = persistentContainer.viewContext
        workout = Workout.create(context: context)
        workout.start = Date(timeIntervalSinceReferenceDate: 1_000)
        workout.isCurrentWorkout = true
        exercise = WorkoutExercise.create(context: context)
        exercise.workout = workout
        sets = (0..<3).map { index in
            let set = WorkoutSet.create(context: context)
            set.weightValue = Double(100 + index * 10)
            set.repetitionsValue = Int16(5 + index)
            set.isCompleted = index == 0
            set.workoutExercise = exercise
            return set
        }
        workout.workoutExercises = NSOrderedSet(array: [exercise])
        exercise.workoutSets = NSOrderedSet(array: sets)
    }

    override func tearDown() {
        persistentContainer.viewContext.reset()
        persistentContainer = nil
        workout = nil
        exercise = nil
        sets = nil
        super.tearDown()
    }

    private func setID(_ set: WorkoutSet) -> String {
        set.uuid?.uuidString ?? set.objectID.uriRepresentation().absoluteString
    }

    private func snapshot(for set: WorkoutSet, number: Int) -> WorkoutActivityAttributes.SetSnapshot {
        WorkoutActivityAttributes.SetSnapshot(
            setID: setID(set),
            exerciseName: "Exercise",
            setNumber: number,
            setCount: sets.count,
            result: "stale result"
        )
    }

    private func priorState(
        phase: WorkoutActivityAttributes.Phase = .setCompleted,
        confirmationUntil: Date? = Date(timeIntervalSinceReferenceDate: 2_000)
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: phase,
            displaySet: snapshot(for: sets[0], number: 1),
            nextSet: snapshot(for: sets[1], number: 2),
            confirmationUntil: confirmationUntil,
            restTimerStart: nil,
            restTimerEnd: nil,
            completedSets: 1,
            totalSets: 3
        )
    }

    private func reconcile(
        prior: WorkoutActivityAttributes.ContentState?,
        now: Date = Date(timeIntervalSinceReferenceDate: 1_500),
        restTimerStart: Date? = nil,
        restTimerEnd: Date? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutLiveActivityManager.shared.reconciledState(
            for: workout,
            priorState: prior,
            now: now,
            restTimerStart: restTimerStart,
            restTimerEnd: restTimerEnd
        )
    }

    func testReconciliationRefreshesEditedWeightAndRepetitions() {
        sets[1].weightValue = 225
        sets[1].repetitionsValue = 8

        let state = reconcile(prior: priorState())

        XCTAssertEqual(state.nextSet?.setID, setID(sets[1]))
        XCTAssertEqual(
            state.nextSet?.result,
            sets[1].resultTitle(weightUnit: SettingsStore.shared.weightUnit)
        )
        XCTAssertNotEqual(state.nextSet?.result, "stale result")
    }

    func testReconciliationSelectsFollowingSetWhenPriorNextSetWasRemoved() {
        let prior = priorState()
        let removed = sets[1]
        exercise.workoutSets = NSOrderedSet(array: [sets[0], sets[2]])
        persistentContainer.viewContext.delete(removed)
        persistentContainer.viewContext.processPendingChanges()

        let state = reconcile(prior: prior)

        XCTAssertEqual(state.nextSet?.setID, setID(sets[2]))
        XCTAssertEqual(state.nextSet?.setNumber, 2)
        XCTAssertEqual(state.totalSets, 2)
    }

    func testReconciliationIgnoresSetPendingDeletionWithoutRelationshipCleanup() {
        let prior = priorState()
        persistentContainer.viewContext.delete(sets[1])

        let state = reconcile(prior: prior)

        XCTAssertEqual(state.nextSet?.setID, setID(sets[2]))
        XCTAssertEqual(state.nextSet?.setNumber, 2)
        XCTAssertEqual(state.nextSet?.setCount, 2)
        XCTAssertEqual(state.totalSets, 2)
    }

    func testReconciliationDropsConfirmationWhenCompletedAnchorWasRemoved() {
        let prior = priorState()
        let removed = sets[0]
        exercise.workoutSets = NSOrderedSet(array: [sets[1], sets[2]])
        persistentContainer.viewContext.delete(removed)
        persistentContainer.viewContext.processPendingChanges()

        let state = reconcile(prior: prior)

        XCTAssertEqual(state.phase, .currentSet)
        XCTAssertNil(state.confirmationUntil)
        XCTAssertEqual(state.nextSet?.setID, setID(sets[1]))
        XCTAssertEqual(state.completedSets, 0)
        XCTAssertEqual(state.totalSets, 2)
    }

    func testReconciliationUsesCurrentOrderAfterCompletedAnchor() {
        exercise.workoutSets = NSOrderedSet(array: [sets[0], sets[2], sets[1]])

        let state = reconcile(prior: priorState())

        XCTAssertEqual(state.nextSet?.setID, setID(sets[2]))
        XCTAssertEqual(state.nextSet?.setNumber, 2)
    }

    func testRepeatedReconciliationRetainsAnchorWithEarlierIncompleteSet() {
        exercise.workoutSets = NSOrderedSet(array: [sets[1], sets[0], sets[2]])
        let first = reconcile(prior: priorState(phase: .resting, confirmationUntil: nil))

        let second = reconcile(prior: first)

        XCTAssertEqual(first.displaySet?.setID, setID(sets[0]))
        XCTAssertEqual(first.nextSet?.setID, setID(sets[2]))
        XCTAssertEqual(second.displaySet?.setID, setID(sets[0]))
        XCTAssertEqual(second.nextSet?.setID, setID(sets[2]))
    }

    func testReconciliationFinishesWithoutReopeningCompletedSets() {
        sets.forEach { $0.isCompleted = true }

        let state = reconcile(prior: priorState(confirmationUntil: nil))

        XCTAssertEqual(state.phase, .finished)
        XCTAssertNil(state.nextSet)
        XCTAssertNil(state.restTimerStart)
        XCTAssertNil(state.restTimerEnd)
        XCTAssertEqual(state.completedSets, 3)
        XCTAssertEqual(state.totalSets, 3)
    }

    func testReconciliationRestoresActiveRestTimerWithoutPriorActivityState() {
        let now = Date(timeIntervalSinceReferenceDate: 3_000)
        let timerStart = now.addingTimeInterval(-15)
        let timerEnd = now.addingTimeInterval(45)

        let state = reconcile(
            prior: nil,
            now: now,
            restTimerStart: timerStart,
            restTimerEnd: timerEnd
        )

        XCTAssertEqual(state.phase, .resting)
        XCTAssertEqual(state.restTimerStart, timerStart)
        XCTAssertEqual(state.restTimerEnd, timerEnd)
        XCTAssertEqual(state.nextSet?.setID, setID(sets[1]))
    }

    func testDeletingEverySetClearsStaleSnapshotsWithoutFinishingEmptyWorkout() {
        let prior = priorState()
        exercise.workoutSets = NSOrderedSet()
        sets.forEach { persistentContainer.viewContext.delete($0) }

        let state = reconcile(prior: prior)

        XCTAssertEqual(state.phase, .currentSet)
        XCTAssertNil(state.displaySet)
        XCTAssertNil(state.nextSet)
        XCTAssertEqual(state.totalSets, 0)
    }

    @MainActor
    func testFailedCompletionSaveRestoresOwnedFieldsOnly() async {
        enum ExpectedError: Error { case saveFailed }
        let set = sets[1]
        set.repetitionsValue = 12
        let previousCompletedAt = Date(timeIntervalSinceReferenceDate: 500)
        set.completedAt = previousCompletedAt
        workout.start = nil

        do {
            try WorkoutLiveActivityIntentHandler.persistCompletion(
                set: set,
                workout: workout,
                at: Date(timeIntervalSinceReferenceDate: 4_000),
                save: { throw ExpectedError.saveFailed }
            )
            XCTFail("Expected the save to fail")
        } catch ExpectedError.saveFailed {
            // Expected. Assertions below verify the targeted restoration.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(set.isCompleted)
        XCTAssertEqual(set.completedAt, previousCompletedAt)
        XCTAssertNil(workout.start)
        XCTAssertEqual(set.repetitionsValue, 12)
        XCTAssertTrue(persistentContainer.viewContext.hasChanges)
    }
}

final class WatchEventPersistenceTests: XCTestCase {
    private enum ExpectedError: Error { case saveFailed }

    private var persistentContainer: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var workout: Workout!
    private var exercise: WorkoutExercise!
    private var sets: [WorkoutSet]!

    override func setUp() {
        super.setUp()
        persistentContainer = setUpInMemoryNSPersistentContainer()
        context = persistentContainer.viewContext
        workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        workout.start = Date(timeIntervalSinceReferenceDate: 1_000)
        exercise = WorkoutExercise.create(context: context)
        exercise.workout = workout
        sets = (0..<2).map { index in
            let set = WorkoutSet.create(context: context)
            set.weightValue = Double(100 + index * 10)
            set.repetitionsValue = Int16(5 + index)
            set.workoutExercise = exercise
            return set
        }
        workout.workoutExercises = NSOrderedSet(array: [exercise])
        exercise.workoutSets = NSOrderedSet(array: sets)
        try! context.save()
    }

    override func tearDown() {
        context.reset()
        context = nil
        persistentContainer = nil
        workout = nil
        exercise = nil
        sets = nil
        super.tearDown()
    }

    private func event(
        kind: WatchWorkoutEventKind,
        setID: UUID? = nil,
        weight: Double? = nil,
        reps: Int? = nil,
        id: UUID = UUID()
    ) -> WatchWorkoutEvent {
        WatchWorkoutEvent(
            workoutID: workout.uuid!,
            sequence: 1,
            kind: kind,
            exerciseID: exercise.uuid,
            setID: setID,
            weight: weight,
            reps: reps,
            id: id
        )
    }

    func testFailedScalarUpdateRestoresEventFieldsAndPreservesPendingUserEdit() {
        let originalWeight = sets[0].weight
        let originalRepetitions = sets[0].repetitions
        workout.title = "Pending user title"
        var effects = 0
        var acknowledgements = 0
        let update = event(
            kind: .setUpdated,
            setID: sets[0].uuid,
            weight: 225,
            reps: 12
        )

        XCTAssertThrowsError(try WatchConnectionManager.commitWatchEventMutation(
            in: context,
            save: { throw ExpectedError.saveFailed },
            mutation: {
                _ = try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    update,
                    to: self.workout,
                    in: self.context
                )
                return .init(perform: { effects += 1 })
            },
            didPersist: { acknowledgements += 1 }
        ))

        XCTAssertEqual(sets[0].weight, originalWeight)
        XCTAssertEqual(sets[0].repetitions, originalRepetitions)
        XCTAssertEqual(workout.title, "Pending user title")
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(acknowledgements, 0)
        XCTAssertTrue(context.hasChanges)
    }

    func testFailedSetInsertionRemovesInsertedObject() {
        let insertedID = UUID()
        let add = event(kind: .setAdded, setID: insertedID, weight: 140, reps: 8)

        XCTAssertThrowsError(try WatchConnectionManager.persistWatchEventMutation(
            in: context,
            save: { throw ExpectedError.saveFailed },
            mutation: {
                try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    add,
                    to: self.workout,
                    in: self.context
                )
            }
        ))

        let currentSets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
        XCTAssertEqual(currentSets.count, 2)
        XCTAssertFalse(currentSets.contains { $0.uuid == insertedID })
        XCTAssertFalse(context.insertedObjects.contains { ($0 as? WorkoutSet)?.uuid == insertedID })
    }

    func testFailedSetDeletionRestoresDeletedObjectAndRelationship() {
        let deletedID = sets[0].uuid!
        let delete = event(kind: .setDeleted, setID: deletedID)

        XCTAssertThrowsError(try WatchConnectionManager.persistWatchEventMutation(
            in: context,
            save: { throw ExpectedError.saveFailed },
            mutation: {
                try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    delete,
                    to: self.workout,
                    in: self.context
                )
            }
        ))

        let currentSets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
        XCTAssertEqual(currentSets.count, 2)
        XCTAssertTrue(currentSets.contains { $0.uuid == deletedID })
        XCTAssertFalse(sets[0].isDeleted)
    }

    func testFailedEventCanRetryAndOnlyThenPerformEffectsAndAcknowledge() throws {
        let update = event(kind: .setUpdated, setID: sets[0].uuid, weight: 180, reps: 9)
        var effects = 0
        var acknowledgements = 0

        XCTAssertThrowsError(try WatchConnectionManager.commitWatchEventMutation(
            in: context,
            save: { throw ExpectedError.saveFailed },
            mutation: {
                _ = try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    update,
                    to: self.workout,
                    in: self.context
                )
                return .init(perform: { effects += 1 })
            },
            didPersist: { acknowledgements += 1 }
        ))

        try WatchConnectionManager.commitWatchEventMutation(
            in: context,
            save: { try self.context.save() },
            mutation: {
                _ = try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    update,
                    to: self.workout,
                    in: self.context
                )
                return .init(perform: { effects += 1 })
            },
            didPersist: { acknowledgements += 1 }
        )

        XCTAssertEqual(sets[0].weightValue, 180, accuracy: 0.001)
        XCTAssertEqual(sets[0].repetitionsValue, 9)
        XCTAssertEqual(effects, 1)
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testDuplicateSetAddedEventRemainsIdempotent() throws {
        let insertedID = UUID()
        let eventID = UUID()
        let add = event(kind: .setAdded, setID: insertedID, id: eventID)

        for _ in 0..<2 {
            _ = try WatchConnectionManager.persistWatchEventMutation(
                in: context,
                save: { try self.context.save() },
                mutation: {
                    try WatchConnectionManager.shared.applyWatchEventModelMutation(
                        add,
                        to: self.workout,
                        in: self.context
                    )
                }
            )
        }

        let matchingSets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet }
            .filter { $0.uuid == insertedID } ?? []
        XCTAssertEqual(matchingSets.count, 1)
    }

    func testThrowDuringMutationRestoresPendingChangesBeforeUndo() {
        let originalWeight = sets[0].weightValue
        workout.title = "Keep this pending title"
        XCTAssertThrowsError(try WatchConnectionManager.persistWatchEventMutation(
            in: context,
            save: { XCTFail("A throwing mutation cannot be saved") },
            mutation: {
                self.sets[0].weightValue = 999
                throw ExpectedError.saveFailed
            }
        ))
        XCTAssertEqual(sets[0].weightValue, originalWeight)
        XCTAssertEqual(workout.title, "Keep this pending title")
    }

    func testFailedWorkoutDiscardRestoresCascadingRelationships() {
        let originalID = workout.uuid
        let discard = event(kind: .workoutDiscarded)
        workout.title = "Pending title"
        XCTAssertThrowsError(try WatchConnectionManager.persistWatchEventMutation(
            in: context,
            save: { throw ExpectedError.saveFailed },
            mutation: {
                try WatchConnectionManager.shared.applyWatchEventModelMutation(
                    discard, to: self.workout, in: self.context
                )
            }
        ))
        XCTAssertFalse(workout.isDeleted)
        XCTAssertEqual(workout.uuid, originalID)
        XCTAssertEqual(workout.title, "Pending title")
        XCTAssertEqual(workout.workoutExercises?.count, 1)
        XCTAssertEqual(exercise.workoutSets?.count, 2)
        XCTAssertTrue(sets.allSatisfy { !$0.isDeleted })
    }
}

@available(iOS 17.0, *)
final class WorkoutPausedLiveActivityTests: XCTestCase {
    private var next: WorkoutActivityAttributes.SetSnapshot {
        .init(setID: "next", exerciseName: "Bench Press", setNumber: 2, setCount: 3, result: "100 lb × 8")
    }

    private func state(phase: WorkoutActivityAttributes.Phase = .resting) -> WorkoutActivityAttributes.ContentState {
        .init(phase: phase, displaySet: next, nextSet: next,
              confirmationUntil: Date(timeIntervalSince1970: 1_010),
              restTimerStart: nil, restTimerEnd: nil, completedSets: 1, totalSets: 3,
              pausedRestRemaining: 45)
    }

    func testPausedRestDoesNotAdvanceWithWallClockTime() {
        let paused = state()
        XCTAssertEqual(paused.resolvedPhase(at: Date(timeIntervalSince1970: 9_000)), .resting)
        XCTAssertEqual(paused.visibleSet(at: Date()), next)
        XCTAssertNil(paused.restProgress(at: Date()))
        XCTAssertEqual(paused.pausedRestRemaining, 45)
    }

    func testCompletionTransitionsToPausedRestRatherThanCurrentSet() {
        let paused = state(phase: .setCompleted)
        XCTAssertEqual(paused.resolvedPhase(at: Date(timeIntervalSince1970: 1_005)), .setCompleted)
        XCTAssertEqual(paused.resolvedPhase(at: Date(timeIntervalSince1970: 1_020)), .resting)
    }

    func testOlderActivityPayloadStillDecodesWithoutPauseField() throws {
        let encoded = try JSONEncoder().encode(state())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "pausedRestRemaining")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: legacyData)
        XCTAssertNil(decoded.pausedRestRemaining)
        XCTAssertFalse(decoded.isRestPaused)
        XCTAssertEqual(decoded.resolvedPhase(at: Date()), .currentSet)
    }

    func testReconciliationRetainsPausedRestAndClearsItAfterLastSet() {
        let container = setUpInMemoryNSPersistentContainer()
        let workout = Workout.create(context: container.viewContext)
        let exercise = WorkoutExercise.create(context: container.viewContext)
        exercise.workout = workout
        let set = WorkoutSet.create(context: container.viewContext)
        set.workoutExercise = exercise
        let reconcile = {
            WorkoutLiveActivityManager.shared.reconciledState(
                for: workout, priorState: nil, now: Date(), restTimerStart: nil,
                restTimerEnd: nil, pausedRestRemaining: 45
            )
        }
        let paused = reconcile()
        XCTAssertEqual(paused.phase, .resting)
        XCTAssertEqual(paused.pausedRestRemaining, 45)
        set.isCompleted = true
        XCTAssertEqual(reconcile().phase, .finished)
        XCTAssertNil(reconcile().pausedRestRemaining)
    }
}

final class WorkoutLifecyclePersistenceTests: XCTestCase {
    private enum Failure: Error { case save }
    private var container: NSPersistentContainer!
    private var workout: Workout!
    private var exercise: WorkoutExercise!

    override func setUpWithError() throws {
        container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        workout.start = Date(timeIntervalSince1970: 1_000)
        exercise = WorkoutExercise.create(context: context)
        exercise.workout = workout
        for completed in [true, false] {
            let set = WorkoutSet.create(context: context)
            set.workoutExercise = exercise
            set.weightValue = 50
            set.repetitionsValue = 8
            set.isCompleted = completed
        }
        try context.save()
    }

    override func tearDown() {
        container.viewContext.reset()
        container = nil
        workout = nil
        exercise = nil
    }

    func testFailedFinishRestoresUncompletedSetsAndEditorValues() {
        workout.title = "Pending title"
        XCTAssertThrowsError(try workout.finish(syncToHealth: false, save: { throw Failure.save }) {
            self.workout.title = "Changed by finish editor"
            self.workout.end = Date(timeIntervalSince1970: 2_000)
            self.workout.sessionEffortValue = 8
        })
        XCTAssertTrue(workout.isCurrentWorkout)
        XCTAssertNil(workout.end)
        XCTAssertEqual(workout.title, "Pending title")
        XCTAssertEqual(exercise.workoutSets?.count, 2)
        XCTAssertEqual(workout.workoutExercises?.count, 1)
        XCTAssertTrue(container.viewContext.hasChanges)
    }

    func testFailedCancelLeavesWorkoutAndRelationshipsIntact() {
        XCTAssertThrowsError(try workout.cancel(save: { throw Failure.save }))
        XCTAssertFalse(workout.isDeleted)
        XCTAssertTrue(workout.isCurrentWorkout)
        XCTAssertEqual(workout.workoutExercises?.count, 1)
        XCTAssertEqual(exercise.workoutSets?.count, 2)
    }

    func testFailedHistoryDeletionLeavesSavedWorkoutIntact() {
        XCTAssertThrowsError(try workout.delete(save: { throw Failure.save }))
        XCTAssertFalse(workout.isDeleted)
        XCTAssertEqual(exercise.workoutSets?.count, 2)
    }

    func testFailedStartRestoresPriorStartAndStatus() {
        let originalStart = workout.start
        workout.isCurrentWorkout = false
        XCTAssertThrowsError(try workout.start(save: { throw Failure.save }))
        XCTAssertFalse(workout.isCurrentWorkout)
        XCTAssertEqual(workout.start, originalStart)
    }
}
