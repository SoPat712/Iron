import XCTest
import CoreData
import WorkoutDataKit
@testable import Iron

final class WatchCompanionSyncTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }
    private let manager = WatchConnectionManager.shared

    override func setUp() {
        super.setUp()
        container = setUpInMemoryNSPersistentContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func snapshot(
        workoutID: UUID = UUID(),
        exerciseID: UUID = UUID(),
        setID: UUID = UUID(),
        completed: Bool = false,
        endDate: Date? = nil,
        supersetID: UUID? = nil
    ) -> WatchWorkoutSnapshot {
        let set = WatchWorkoutSet(
            id: setID, order: 1, weight: 100, reps: 8, rpe: 8.5,
            completed: completed, tag: WorkoutSetTag.warmUp.rawValue,
            duration: 75, distance: 400, comment: "Controlled tempo",
            minTargetReps: 6, maxTargetReps: 10)
        let exercise = WatchWorkoutExercise(
            id: exerciseID, order: 1, name: "Watch exercise", sets: [set],
            restTimerDuration: 90, exerciseUuid: UUID(), supersetID: supersetID,
            comment: "Keep shoulders down")
        return WatchWorkoutSnapshot(
            workoutID: workoutID, title: "Watch session",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: endDate, exercises: [exercise], weightUnit: .kilogram,
            revision: 4, updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            comment: "Watch note")
    }

    func testWatchCreatedHydrationIsIdempotentAndComplete() throws {
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        workout.healthExportState = "watch"
        let groupID = UUID()
        let source = snapshot(workoutID: workout.uuid!, supersetID: groupID)

        manager.applyComplete(source, to: workout, in: context)
        manager.applyComplete(source, to: workout, in: context)

        let exercises = workout.workoutExercises?.array as? [WorkoutExercise]
        let sets = exercises?.first?.workoutSets?.array as? [WorkoutSet]
        XCTAssertEqual(exercises?.count, 1)
        XCTAssertEqual(sets?.count, 1)
        XCTAssertEqual(exercises?.first?.supersetUuid, groupID)
        XCTAssertEqual(exercises?.first?.comment, "Keep shoulders down")
        XCTAssertEqual(sets?.first?.durationValue, 75)
        XCTAssertEqual(sets?.first?.distanceValue, 400)
        XCTAssertEqual(sets?.first?.minTargetRepetitionsValue, 6)
        XCTAssertEqual(sets?.first?.maxTargetRepetitionsValue, 10)
        XCTAssertEqual(sets?.first?.comment, "Controlled tempo")
        XCTAssertEqual(workout.comment, "Watch note")
        try context.save()
    }

    func testConcurrentPhoneWorkoutRemainsCurrentWhenWatchWorkoutIsHydrated() throws {
        let phone = Workout.create(context: context)
        phone.isCurrentWorkout = true
        phone.start = Date(timeIntervalSince1970: 1_700_000_000)
        let watchID = UUID()
        let source = snapshot(workoutID: watchID)
        let event = WatchWorkoutEvent(
            workoutID: watchID, sequence: 1, kind: .workoutCreated,
            snapshot: source)

        let hydrated = try manager.resolveWorkout(for: event, in: context)

        XCTAssertTrue(phone.isCurrentWorkout)
        XCTAssertNil(hydrated, "Conflicting unfinished Watch data must be deferred, not inserted")
        let workoutsRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        XCTAssertEqual(try context.fetch(workoutsRequest).map(\.uuid), [phone.uuid])
        try context.save()
    }

    func testFinishedSnapshotRecoversUnknownWorkoutAndAllSets() throws {
        let workoutID = UUID()
        let exerciseID = UUID()
        let first = WatchWorkoutSet(id: UUID(), order: 1, weight: 70, reps: 5, completed: true)
        let second = WatchWorkoutSet(id: UUID(), order: 2, weight: 72.5, reps: 4,
                                     completed: true, duration: 45)
        let end = Date(timeIntervalSince1970: 1_700_000_600)
        var source = snapshot(workoutID: workoutID, exerciseID: exerciseID,
                              completed: true, endDate: end)
        source.exercises[0].sets = [first, second]
        let event = WatchWorkoutEvent(
            workoutID: workoutID, sequence: 9, kind: .workoutFinished,
            endDate: end, snapshot: source)

        let hydrated = try XCTUnwrap(manager.resolveWorkout(for: event, in: context))
        _ = try manager.applyWatchEventModelMutation(event, to: hydrated, in: context)

        XCTAssertEqual(hydrated.end, end)
        XCTAssertFalse(hydrated.isCurrentWorkout)
        XCTAssertEqual(hydrated.healthExportState, "watch")
        let sets = (hydrated.workoutExercises?.firstObject as? WorkoutExercise)?
            .workoutSets?.array as? [WorkoutSet]
        XCTAssertEqual(sets?.compactMap(\.uuid), [first.id, second.id])
        XCTAssertEqual(sets?.last?.durationValue, 45)
        try context.save()
    }

    func testSavedWorkoutUpsertAndDeletePreserveSupportedTemplateFields() throws {
        let routineID = UUID()
        let groupID = UUID()
        let set = WatchWorkoutSet(
            id: UUID(), order: 1, weight: 225, reps: nil, completed: false,
            tag: WorkoutSetTag.warmUp.rawValue, duration: 60, distance: 1_000,
            comment: "Pause at bottom", minTargetReps: 3, maxTargetReps: 5)
        let exercise = WatchWorkoutExercise(
            id: UUID(), order: 1, name: "Template exercise", sets: [set],
            restTimerDuration: 120, exerciseUuid: UUID(), supersetID: groupID,
            comment: "Brace")
        let saved = WatchSavedWorkout(
            id: routineID, title: "Heavy day", exercises: [exercise],
            weightUnit: .pound, comment: "Template note", updatedAt: Date())
        let upsert = WatchWorkoutEvent(
            workoutID: routineID, sequence: 1, kind: .savedWorkoutUpserted,
            savedWorkout: saved)

        _ = try manager.applySavedWorkoutEvent(upsert, in: context)
        try context.save()

        let request: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", routineID as NSUUID)
        let routine = try XCTUnwrap(context.fetch(request).first)
        let storedExercise = try XCTUnwrap(routine.workoutRoutineExercises?.firstObject as? WorkoutRoutineExercise)
        let storedSet = try XCTUnwrap(storedExercise.workoutRoutineSets?.firstObject as? WorkoutRoutineSet)
        XCTAssertNotNil(routine.workoutPlan)
        XCTAssertEqual(routine.comment, "Template note")
        XCTAssertEqual(storedExercise.supersetUuid, groupID)
        XCTAssertEqual(storedExercise.restTimerDurationValue, 120)
        XCTAssertEqual(storedExercise.comment, "Brace")
        XCTAssertEqual(storedSet.durationValue, 60)
        XCTAssertEqual(storedSet.minRepetitionsValue, 3)
        XCTAssertEqual(storedSet.maxRepetitionsValue, 5)
        XCTAssertEqual(storedSet.comment, "Pause at bottom")
        XCTAssertEqual(storedSet.weightValue ?? 0, 102.058, accuracy: 0.01)

        let deleted = WatchWorkoutEvent(
            workoutID: routineID, sequence: 2, kind: .savedWorkoutDeleted)
        _ = try manager.applySavedWorkoutEvent(deleted, in: context)
        try context.save()
        XCTAssertTrue(try context.fetch(request).isEmpty)
    }

    func testImportedWorkoutNeverBecomesWatchHealthOwned() throws {
        let workout = Workout.create(context: context)
        workout.importSource = "hevy"
        workout.isCurrentWorkout = false
        workout.start = Date(timeIntervalSince1970: 1_700_000_000)
        workout.end = Date(timeIntervalSince1970: 1_700_000_300)
        let source = snapshot(workoutID: workout.uuid!, completed: true,
                              endDate: workout.end)
        manager.applyComplete(source, to: workout, in: context)
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 3, kind: .workoutFailed,
            endDate: workout.end, snapshot: source)

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)

        XCTAssertEqual(workout.importSource, "hevy")
        XCTAssertNil(workout.healthExportState)
        XCTAssertEqual(workout.healthExportEligibility, .imported)
    }
}

final class WatchCompanionSyncRegressionTests: XCTestCase {
    private let manager = WatchConnectionManager.shared

    func testPhoneOwnedStructureDeletionSurvivesWhileUnrelatedPhoneExerciseRemains() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        workout.healthExportState = nil
        let original = WorkoutExercise.create(context: context)
        let removed = WorkoutSet.create(context: context)
        removed.uuid = UUID()
        let removedID = removed.uuid!
        let kept = WorkoutSet.create(context: context)
        kept.uuid = UUID()
        removed.workoutExercise = original
        kept.workoutExercise = original
        original.workoutSets = NSOrderedSet(array: [removed, kept])
        original.workout = workout

        let phoneAdded = WorkoutExercise.create(context: context)
        let phoneAddedSet = WorkoutSet.create(context: context)
        phoneAddedSet.uuid = UUID()
        phoneAddedSet.workoutExercise = phoneAdded
        phoneAdded.workoutSets = NSOrderedSet(array: [phoneAddedSet])
        phoneAdded.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [original, phoneAdded])

        let snapshotExercise = WatchWorkoutExercise(
            id: original.uuid!, order: 1, name: "Original", sets: [
                WatchWorkoutSet(id: kept.uuid!, order: 1, weight: 50, reps: 5)
            ])
        let snapshot = WatchWorkoutSnapshot(
            workoutID: workout.uuid!, startDate: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [snapshotExercise], updatedAt: Date(timeIntervalSince1970: 1_700_000_010))
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 1, kind: .workoutStructureUpdated,
            snapshot: snapshot, removedSetIDs: [removedID])

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)
        context.processPendingChanges()

        let originalSetIDs = (original.workoutSets?.array as? [WorkoutSet] ?? []).compactMap(\.uuid)
        XCTAssertFalse(originalSetIDs.contains(removedID))
        let remainingRemoved = try context.fetch(WorkoutSet.fetchRequest()).filter { $0.uuid == removedID }
        XCTAssertTrue(remainingRemoved.isEmpty)
        XCTAssertEqual(originalSetIDs, [kept.uuid!])
        let workoutExerciseIDs = (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).compactMap(\.uuid)
        XCTAssertEqual(Set(workoutExerciseIDs), Set([original.uuid!, phoneAdded.uuid!]))
        XCTAssertFalse(phoneAdded.isDeleted)
        XCTAssertEqual((phoneAdded.workoutSets?.firstObject as? WorkoutSet)?.uuid, phoneAddedSet.uuid)
    }

    func testMaskedStructuralDeletionStillRemovesExplicitSet() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        let exercise = WorkoutExercise.create(context: context)
        let removed = WorkoutSet.create(context: context)
        let kept = WorkoutSet.create(context: context)
        let removedID = removed.uuid!
        removed.workoutExercise = exercise
        kept.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [removed, kept])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])
        let snapshot = WatchWorkoutSnapshot(
            workoutID: workout.uuid!, startDate: workout.safeStart,
            exercises: [WatchWorkoutExercise(
                id: exercise.uuid!, order: 1, name: "Exercise",
                sets: [WatchWorkoutSet(id: kept.uuid!, order: 1, weight: 50, reps: 5)])])
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 2, kind: .workoutStructureUpdated,
            snapshot: snapshot, removedSetIDs: [removedID],
            fieldChanges: WatchWorkoutFieldChanges())

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)
        context.processPendingChanges()

        let remainingRemoved = try context.fetch(WorkoutSet.fetchRequest()).filter { $0.uuid == removedID }
        XCTAssertTrue(remainingRemoved.isEmpty)
        XCTAssertEqual((exercise.workoutSets?.array as? [WorkoutSet])?.compactMap(\.uuid), [kept.uuid!])
    }

    func testMaskedUnrelatedEditDoesNotResurrectPhoneDeletedExerciseOrSet() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        let exercise = WorkoutExercise.create(context: context)
        let set = WorkoutSet.create(context: context)
        set.comment = "Before"
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])

        let phoneDeletedSetID = UUID()
        let phoneDeletedExerciseID = UUID()
        let staleSet = WatchWorkoutSet(id: phoneDeletedSetID, order: 2, weight: 40, reps: 8)
        let staleExercise = WatchWorkoutExercise(
            id: phoneDeletedExerciseID, order: 2, name: "Deleted on phone",
            sets: [WatchWorkoutSet(order: 1, weight: 20, reps: 10)])
        let originalSet = WatchWorkoutSet(id: set.uuid!, order: 1, weight: 60, reps: 5,
                                          comment: "Before")
        let originalExercise = WatchWorkoutExercise(
            id: exercise.uuid!, order: 1, name: "Kept", sets: [originalSet, staleSet])
        let previous = WatchWorkoutSnapshot(
            workoutID: workout.uuid!, exercises: [originalExercise, staleExercise])
        var next = previous
        next.exercises[0].sets[0].comment = "Watch edit"
        let changes = WatchWorkoutFieldChanges.between(previous: previous, next: next)
        XCTAssertEqual(changes.addedExerciseIDs, [])
        XCTAssertEqual(changes.addedSetIDs, [])
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 3, kind: .workoutStructureUpdated,
            snapshot: next, fieldChanges: changes)

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)
        context.processPendingChanges()

        XCTAssertEqual((workout.workoutExercises?.array as? [WorkoutExercise])?.compactMap(\.uuid),
                       [exercise.uuid!])
        XCTAssertEqual((exercise.workoutSets?.array as? [WorkoutSet])?.compactMap(\.uuid),
                       [set.uuid!])
        XCTAssertEqual(set.comment, "Watch edit")
    }

    func testMaskedExplicitWatchExerciseAndSetAdditionsAreCreated() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        let exercise = WorkoutExercise.create(context: context)
        let set = WorkoutSet.create(context: context)
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])

        let originalExercise = WatchWorkoutExercise(
            id: exercise.uuid!, order: 1, name: "Existing",
            sets: [WatchWorkoutSet(id: set.uuid!, order: 1, weight: 50, reps: 5)])
        let previous = WatchWorkoutSnapshot(workoutID: workout.uuid!, exercises: [originalExercise])
        let addedSet = WatchWorkoutSet(order: 2, weight: 55, reps: 4, comment: "Added set")
        let addedExercise = WatchWorkoutExercise(
            order: 2, name: "Added exercise",
            sets: [WatchWorkoutSet(order: 1, weight: 25, reps: 12)],
            exerciseUuid: UUID(), comment: "Added exercise note")
        var next = previous
        next.exercises[0].sets.append(addedSet)
        next.exercises.append(addedExercise)
        WatchWorkoutEditing.normalize(&next)
        let changes = WatchWorkoutFieldChanges.between(previous: previous, next: next)
        XCTAssertEqual(Set(changes.addedExerciseIDs ?? []), [addedExercise.id])
        XCTAssertEqual(Set(changes.addedSetIDs ?? []),
                       Set([addedSet.id, addedExercise.sets[0].id]))
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 4, kind: .workoutStructureUpdated,
            snapshot: next, fieldChanges: changes)

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)
        context.processPendingChanges()

        let exercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
        XCTAssertEqual(exercises.compactMap(\.uuid), [exercise.uuid!, addedExercise.id])
        let existingSets = exercise.workoutSets?.array as? [WorkoutSet] ?? []
        XCTAssertEqual(existingSets.compactMap(\.uuid), [set.uuid!, addedSet.id])
        XCTAssertEqual(existingSets.last?.comment, "Added set")
        let createdExercise = try XCTUnwrap(exercises.last)
        XCTAssertEqual(createdExercise.comment, "Added exercise note")
        XCTAssertEqual((createdExercise.workoutSets?.firstObject as? WorkoutSet)?.uuid,
                       addedExercise.sets[0].id)
    }

    func testMaskedUnrelatedEditPreservesConcurrentPhoneSetValuesAndNotes() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        workout.title = "Phone title"
        workout.comment = "Phone workout note"
        let exercise = WorkoutExercise.create(context: context)
        exercise.comment = "Phone exercise note"
        exercise.restTimerDurationValue = 60
        let set = WorkoutSet.create(context: context)
        set.weight = 140
        set.repetitions = 11
        set.comment = "Phone set note"
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])

        let watchSet = WatchWorkoutSet(id: set.uuid!, order: 1, weight: 80, reps: 5,
                                       comment: "Stale Watch note")
        let watchExercise = WatchWorkoutExercise(
            id: exercise.uuid!, order: 1, name: "Exercise", sets: [watchSet],
            restTimerDuration: 120, comment: "Stale exercise note")
        let snapshot = WatchWorkoutSnapshot(
            workoutID: workout.uuid!, title: "Stale title", startDate: workout.safeStart,
            exercises: [watchExercise], comment: "Stale workout note")
        let changes = WatchWorkoutFieldChanges(
            exercises: [exercise.uuid!.uuidString: ["restTimerDuration"]])
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 2, kind: .workoutStructureUpdated,
            snapshot: snapshot, fieldChanges: changes)

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)

        XCTAssertEqual(workout.title, "Phone title")
        XCTAssertEqual(workout.comment, "Phone workout note")
        XCTAssertEqual(exercise.comment, "Phone exercise note")
        XCTAssertEqual(exercise.restTimerDurationValue, 120)
        XCTAssertEqual(set.weight?.doubleValue, 140)
        XCTAssertEqual(set.repetitions?.intValue, 11)
        XCTAssertEqual(set.comment, "Phone set note")
    }

    func testUnitOnlyConversionMaskDoesNotOverwriteConcurrentPhoneWeight() throws {
        let exerciseID = UUID()
        let setID = UUID()
        let kilograms = WatchWorkoutSnapshot(
            workoutID: UUID(), exercises: [WatchWorkoutExercise(
                id: exerciseID, order: 1, name: "Exercise",
                sets: [WatchWorkoutSet(id: setID, order: 1, weight: 100, reps: 5)])],
            weightUnit: .kilogram)
        let pounds = WatchWorkoutEditing.converting(kilograms, to: .pound)
        let changes = WatchWorkoutFieldChanges.between(previous: kilograms, next: pounds)
        XCTAssertFalse(changes.sets[setID.uuidString]?.contains("weight") == true)

        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        workout.isCurrentWorkout = true
        let exercise = WorkoutExercise.create(context: context)
        exercise.uuid = exerciseID
        let set = WorkoutSet.create(context: context)
        set.uuid = setID
        set.weight = 130
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])
        var incoming = pounds
        incoming.workoutID = workout.uuid!
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 3, kind: .workoutStructureUpdated,
            snapshot: incoming, fieldChanges: changes)

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)

        XCTAssertEqual(set.weight?.doubleValue, 130)
    }

    func testModernFinishPreservesKnownConcurrentPhoneGraphAndMetadata() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let workout = Workout.create(context: context)
        let originalStart = Date(timeIntervalSince1970: 1_700_000_000)
        workout.isCurrentWorkout = true
        workout.start = originalStart
        workout.title = "Phone title"
        workout.comment = "Phone note"
        let exercise = WorkoutExercise.create(context: context)
        exercise.comment = "Phone exercise"
        let set = WorkoutSet.create(context: context)
        set.weight = 150
        set.repetitions = 9
        set.isCompleted = false
        set.comment = "Phone set"
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = workout
        workout.workoutExercises = NSOrderedSet(array: [exercise])

        let end = originalStart.addingTimeInterval(600)
        let staleSnapshot = WatchWorkoutSnapshot(
            workoutID: workout.uuid!, title: "Stale Watch title",
            startDate: originalStart.addingTimeInterval(30), endDate: end,
            exercises: [], sessionEffort: 8, comment: "Stale Watch note", isFinished: true)
        let event = WatchWorkoutEvent(
            workoutID: workout.uuid!, sequence: 4, kind: .workoutFinished,
            endDate: end, sessionEffort: 8, snapshot: staleSnapshot,
            fieldChanges: WatchWorkoutFieldChanges())

        _ = try manager.applyWatchEventModelMutation(event, to: workout, in: context)

        XCTAssertEqual(workout.start, originalStart)
        XCTAssertEqual(workout.end, end)
        XCTAssertEqual(workout.title, "Phone title")
        XCTAssertEqual(workout.comment, "Phone note")
        XCTAssertEqual(workout.sessionEffortValue, 8)
        XCTAssertFalse(workout.isCurrentWorkout)
        XCTAssertEqual(workout.healthExportState, "watch")
        XCTAssertFalse(exercise.isDeleted)
        XCTAssertFalse(set.isDeleted)
        XCTAssertEqual(set.weight?.doubleValue, 150)
        XCTAssertEqual(set.repetitions?.intValue, 9)
        XCTAssertEqual(set.comment, "Phone set")
    }

    func testFixedDisplayEndDateMarkedActiveDoesNotDisplacePhoneCurrent() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let phone = Workout.create(context: context)
        phone.isCurrentWorkout = true
        phone.start = Date(timeIntervalSince1970: 1_700_000_000)
        let phoneID = phone.uuid!
        let watchID = UUID()
        let fixedEnd = Date(timeIntervalSince1970: 1_700_000_300)
        var snapshot = WatchWorkoutSnapshot(
            workoutID: watchID, title: "Fixed display", startDate: phone.start!,
            endDate: fixedEnd, updatedAt: fixedEnd, isFinished: false)
        snapshot.isFinished = false
        let event = WatchWorkoutEvent(
            workoutID: watchID, sequence: 1, kind: .workoutCreated, snapshot: snapshot)

        manager.currentWatchWorkoutUuid = nil
        XCTAssertFalse(snapshot.isFinishedRecord)
        XCTAssertNil(try manager.resolveWorkout(for: event, in: context))
        XCTAssertTrue(phone.isCurrentWorkout)
        XCTAssertEqual(try context.fetch(Workout.currentWorkoutFetchRequest).map(\.uuid), [phoneID])

        context.delete(phone)
        context.processPendingChanges()
        let hydrated = try XCTUnwrap(manager.resolveWorkout(for: event, in: context))
        XCTAssertTrue(hydrated.isCurrentWorkout)
        XCTAssertEqual(hydrated.end, fixedEnd)
        XCTAssertEqual(hydrated.healthExportState, "watch")
    }

    func testFinishedWatchEventLeavesImportedWorkoutUntouched() throws {
        let container = setUpInMemoryNSPersistentContainer()
        let context = container.viewContext
        let imported = Workout.create(context: context)
        imported.importSource = "hevy"
        imported.isCurrentWorkout = false
        imported.start = Date(timeIntervalSince1970: 1_700_000_000)
        let originalEnd = Date(timeIntervalSince1970: 1_700_000_120)
        imported.end = originalEnd
        imported.title = "Imported title"
        let exercise = WorkoutExercise.create(context: context)
        let set = WorkoutSet.create(context: context)
        set.uuid = UUID()
        set.workoutExercise = exercise
        exercise.workoutSets = NSOrderedSet(array: [set])
        exercise.workout = imported
        imported.workoutExercises = NSOrderedSet(array: [exercise])

        let snapshot = WatchWorkoutSnapshot(
            workoutID: imported.uuid!, title: "Watch replacement", startDate: imported.start!,
            endDate: originalEnd.addingTimeInterval(600),
            exercises: [], updatedAt: originalEnd, isFinished: true)
        let event = WatchWorkoutEvent(
            workoutID: imported.uuid!, sequence: 2, kind: .workoutFinished,
            endDate: snapshot.endDate, snapshot: snapshot)

        _ = try manager.applyWatchEventModelMutation(event, to: imported, in: context)

        XCTAssertEqual(imported.importSource, "hevy")
        XCTAssertEqual(imported.title, "Imported title")
        XCTAssertEqual(imported.end, originalEnd)
        XCTAssertNil(imported.healthExportState)
        XCTAssertEqual(imported.healthExportEligibility, .imported)
        XCTAssertEqual((imported.workoutExercises?.firstObject as? WorkoutExercise)?.uuid, exercise.uuid)
    }
}
