//
//  WorkoutSessionManagerStore.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 09.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import HealthKit
import Combine
import WatchKit
import os.log

/// Durable watch-side projection and at-least-once event outbox.  HealthKit
/// owns sensor samples; this store owns the workout the user is editing.
final class WatchWorkoutStore {
    static let shared = WatchWorkoutStore()

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let encode: (WatchWorkoutPersistedState) -> Data?
    private let lock = NSLock()
    private var state: WatchWorkoutPersistedState

    private init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "watchWorkoutStore.v1",
        encode: @escaping (WatchWorkoutPersistedState) -> Data? = { WatchWorkoutWire.encode($0) }
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.encode = encode
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = WatchWorkoutWire.decode(WatchWorkoutPersistedState.self, from: data) {
            state = decoded
        } else {
            state = WatchWorkoutPersistedState()
        }
    }

    private func commitLocked<Result>(
        _ mutation: (inout WatchWorkoutPersistedState) throws -> Result
    ) throws -> Result {
        let prepared = try WatchWorkoutPersistence.prepare(
            current: state,
            encode: encode,
            mutation: mutation
        )
        defaults.set(prepared.data, forKey: defaultsKey)
        state = prepared.state
        return prepared.result
    }

    func snapshot() -> WatchWorkoutSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return state.snapshot
    }

    /// Newer revisions win, while a new workout UUID always replaces the old
    /// projection. This makes stale application-context deliveries harmless.
    @discardableResult
    func replaceSnapshot(_ snapshot: WatchWorkoutSnapshot) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let current = state.snapshot,
           current.workoutID == snapshot.workoutID,
           (current.revision > snapshot.revision ||
            (current.revision == snapshot.revision && current.updatedAt > snapshot.updatedAt)) {
            return false
        }
        try commitLocked { $0.snapshot = snapshot }
        return true
    }

    @discardableResult
    func commitEvent(
        snapshotChange: WatchWorkoutSnapshotChange,
        makeEvent: (Int64, WatchWorkoutSnapshot?) -> WatchWorkoutEvent
    ) throws -> WatchWorkoutEvent {
        lock.lock(); defer { lock.unlock() }
        let prepared = try WatchWorkoutPersistence.prepareEvent(
            current: state,
            snapshotChange: snapshotChange,
            encode: encode,
            makeEvent: makeEvent
        )
        defaults.set(prepared.data, forKey: defaultsKey)
        state = prepared.state
        return prepared.result
    }

    func pendingEvents() -> [WatchWorkoutEvent] {
        lock.lock(); defer { lock.unlock() }
        return state.outbox
    }

    func acknowledge(eventIDs: [UUID]) throws {
        guard !eventIDs.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let ids = Set(eventIDs)
        try commitLocked { $0.outbox.removeAll { ids.contains($0.id) } }
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try commitLocked {
            $0.snapshot = nil
            $0.outbox.removeAll()
        }
    }

    func clearSnapshot() throws {
        lock.lock(); defer { lock.unlock() }
        try commitLocked { $0.snapshot = nil }
    }
}

class WorkoutSessionManagerStore: ObservableObject {
    static let shared = WorkoutSessionManagerStore()

    struct PersistenceFailure: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }
    
    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var persistenceFailure: PersistenceFailure? {
        didSet {
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    func clearPersistenceFailure() {
        WorkoutSessionManager.perform {
            self.persistenceFailure = nil
        }
    }

    func reportPersistenceFailure(_ error: Error) {
        WorkoutSessionManager.perform {
            self.recordPersistenceFailure(error)
        }
    }

    private func recordPersistenceFailure(_ error: Error) {
        os_log("Could not persist watch workout change: %@", type: .error, error.localizedDescription)
        persistenceFailure = PersistenceFailure(message: error.localizedDescription)
    }

    private func advanceRevision(_ snapshot: inout WatchWorkoutSnapshot) -> Bool {
        do {
            try WatchWorkoutPersistence.incrementRevision(&snapshot)
            return true
        } catch {
            recordPersistenceFailure(error)
            return false
        }
    }
    
    private var _workoutSessionManager: WorkoutSessionManager? {
        didSet { // don't use willSet, somehow this is sometimes to early in this case
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    var workoutSessionManager: WorkoutSessionManager? {
        get {
            return _workoutSessionManager
        }
        set {
            dispatchPrecondition(condition: DispatchPredicate.onQueue(WorkoutSessionManager.accessQueue))
            _workoutSessionManager = newValue
        }
    }

    private var _workoutSnapshot: WatchWorkoutSnapshot? = WatchWorkoutStore.shared.snapshot() {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    var workoutSnapshot: WatchWorkoutSnapshot? {
        _workoutSnapshot
    }

    private func publishSnapshot(_ snapshot: WatchWorkoutSnapshot?) {
        _workoutSnapshot = snapshot
    }

    /// Refreshes UI that derives its state from the durable event outbox.
    /// The outbox intentionally lives outside the published snapshot so it
    /// survives archiving a finished workout.
    func notifySyncStateChanged() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    @discardableResult
    private func archiveSnapshot(workoutID: UUID) -> Bool {
        guard self.workoutSnapshot?.workoutID == workoutID else { return true }
        do {
            try WatchWorkoutStore.shared.clearSnapshot()
            publishSnapshot(nil)
            return true
        } catch {
            recordPersistenceFailure(error)
            return false
        }
    }

    @discardableResult
    private func persistSnapshot(_ snapshot: WatchWorkoutSnapshot) -> Bool {
        do {
            guard try WatchWorkoutStore.shared.replaceSnapshot(snapshot) else { return false }
            publishSnapshot(snapshot)
            return true
        } catch {
            recordPersistenceFailure(error)
            return false
        }
    }

    @discardableResult
    private func commitEvent(
        snapshotChange: WatchWorkoutSnapshotChange = .keep,
        workoutID: UUID,
        kind: WatchWorkoutEventKind,
        exerciseID: UUID? = nil,
        setID: UUID? = nil,
        weight: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        completed: Bool? = nil,
        restTimerEnd: Date? = nil,
        keepRestTimerRunning: Bool? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        title: String? = nil,
        sessionEffort: Double? = nil,
        eventSnapshot: WatchWorkoutSnapshot? = nil,
        tag: String? = nil,
        catalogExerciseUuid: UUID? = nil,
        afterExerciseID: UUID? = nil
    ) -> Bool {
        do {
            _ = try WatchWorkoutStore.shared.commitEvent(
                snapshotChange: snapshotChange
            ) { sequence, persistedSnapshot in
                self.makeEvent(
                    sequence: sequence,
                    weightUnit: persistedSnapshot?.weightUnit,
                    workoutID: workoutID,
                    kind: kind,
                    exerciseID: exerciseID,
                    setID: setID,
                    weight: weight,
                    reps: reps,
                    rpe: rpe,
                    completed: completed,
                    restTimerEnd: restTimerEnd,
                    keepRestTimerRunning: keepRestTimerRunning,
                    startDate: startDate,
                    endDate: endDate,
                    title: title,
                    sessionEffort: sessionEffort,
                    snapshot: eventSnapshot,
                    tag: tag,
                    catalogExerciseUuid: catalogExerciseUuid,
                    afterExerciseID: afterExerciseID
                )
            }
            if case .replace(let snapshot) = snapshotChange {
                publishSnapshot(snapshot)
            }
            DispatchQueue.main.async {
                PhoneConnectionManager.shared.flushEventOutbox()
            }
            return true
        } catch {
            recordPersistenceFailure(error)
            return false
        }
    }

    private func makeEvent(sequence: Int64, weightUnit: WatchWorkoutWeightUnit?,
                           workoutID: UUID, kind: WatchWorkoutEventKind,
                           exerciseID: UUID? = nil, setID: UUID? = nil,
                           weight: Double? = nil, reps: Int? = nil,
                           rpe: Double? = nil, completed: Bool? = nil,
                           restTimerEnd: Date? = nil,
                           keepRestTimerRunning: Bool? = nil,
                           startDate: Date? = nil, endDate: Date? = nil,
                           title: String? = nil,
                           sessionEffort: Double? = nil,
                           snapshot: WatchWorkoutSnapshot? = nil,
                           tag: String? = nil,
                           catalogExerciseUuid: UUID? = nil,
                           afterExerciseID: UUID? = nil) -> WatchWorkoutEvent {
        WatchWorkoutEvent(workoutID: workoutID,
                          sequence: sequence,
                          kind: kind, exerciseID: exerciseID, setID: setID,
                          weight: weight, reps: reps, rpe: rpe,
                          completed: completed, restTimerEnd: restTimerEnd,
                          keepRestTimerRunning: keepRestTimerRunning,
                          startDate: startDate, endDate: endDate, title: title,
                          weightUnit: weightUnit,
                          sessionEffort: sessionEffort,
                          snapshot: snapshot,
                          tag: tag,
                          catalogExerciseUuid: catalogExerciseUuid,
                          afterExerciseID: afterExerciseID)
    }
}

extension WorkoutSessionManagerStore {
    func applyWorkoutSnapshot(_ snapshot: WatchWorkoutSnapshot) {
        WorkoutSessionManager.perform {
            guard snapshot.schemaVersion <= WatchWorkoutWire.schemaVersion else {
                os_log("Ignoring unsupported workout snapshot version=%d", type: .error, snapshot.schemaVersion)
                return
            }
            let replaced: Bool
            do {
                replaced = try WatchWorkoutStore.shared.replaceSnapshot(snapshot)
            } catch {
                self.recordPersistenceFailure(error)
                return
            }
            guard replaced else { return }
            self.publishSnapshot(snapshot)

            if let manager = self.workoutSessionManager,
               manager.uuid == snapshot.workoutID {
                manager.updateStartDate(snapshot.startDate)
                manager.updateEndDate(snapshot.endDate)
                manager.restTimerEnd = snapshot.restTimerEnd
                manager.keepRestTimerRunning = snapshot.keepRestTimerRunning
                manager.selectedSetText = snapshot.selectedSetText
            }
        }
    }

    func updateSet(workoutID: UUID, exerciseID: UUID, setID: UUID,
                   weight: Double?, reps: Int?, rpe: Double?) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = snapshot.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }

            var set = snapshot.exercises[exerciseIndex].sets[setIndex]
            guard set.weight != weight || set.reps != reps || set.rpe != rpe else {
                return
            }
            set.weight = weight
            set.reps = reps
            set.rpe = rpe
            snapshot.exercises[exerciseIndex].sets[setIndex] = set
            snapshot.selectedSetID = setID
            snapshot.selectedSetText = set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .setUpdated,
                             exerciseID: exerciseID, setID: setID,
                             weight: weight, reps: reps, rpe: rpe)
        }
    }

    func toggleSet(workoutID: UUID, exerciseID: UUID, setID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = snapshot.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }

            var set = snapshot.exercises[exerciseIndex].sets[setIndex]
            set.completed.toggle()
            snapshot.exercises[exerciseIndex].sets[setIndex] = set
            snapshot.selectedSetID = setID
            snapshot.selectedSetText = set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .setCompletionChanged,
                             exerciseID: exerciseID, setID: setID,
                             completed: set.completed)
        }
    }

    func addSet(workoutID: UUID, exerciseID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            let source = snapshot.exercises[exerciseIndex].sets.last
            var set = WatchWorkoutSet(
                order: snapshot.exercises[exerciseIndex].sets.count + 1,
                weight: source?.weight,
                reps: source?.reps ?? 5,
                rpe: source?.rpe,
                previousWeight: source?.previousWeight ?? source?.weight,
                previousReps: source?.previousReps ?? source?.reps,
                completed: false,
                tag: nil
            )
            snapshot.exercises[exerciseIndex].sets.append(set)
            snapshot.selectedSetID = set.id
            snapshot.selectedSetText = set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .setAdded,
                             exerciseID: exerciseID, setID: set.id,
                             weight: set.weight, reps: set.reps, rpe: set.rpe)
        }
    }

    func deleteSet(workoutID: UUID, exerciseID: UUID, setID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }),
                  snapshot.exercises[exerciseIndex].sets.count > 1,
                  let setIndex = snapshot.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
            snapshot.exercises[exerciseIndex].sets.remove(at: setIndex)
            for index in snapshot.exercises[exerciseIndex].sets.indices {
                snapshot.exercises[exerciseIndex].sets[index].order = index + 1
            }
            let remaining = snapshot.exercises[exerciseIndex].sets
            snapshot.selectedSetID = remaining[min(setIndex, remaining.count - 1)].id
            snapshot.selectedSetText = remaining.first { $0.id == snapshot.selectedSetID }
                .map { $0.displayText(weightUnit: snapshot.weightUnit ?? .kilogram) }
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .setDeleted,
                             exerciseID: exerciseID, setID: setID)
        }
    }

    func updateSetTag(workoutID: UUID, exerciseID: UUID, setID: UUID, tag: String?) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = snapshot.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
            snapshot.exercises[exerciseIndex].sets[setIndex].tag = tag
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .setTagChanged,
                             exerciseID: exerciseID, setID: setID, tag: tag)
        }
    }

    func addExercise(workoutID: UUID, afterExerciseID: UUID, catalogExerciseUuid: UUID, name: String, muscleGroup: String?, imageURL: String?) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == afterExerciseID }) else { return }
            let set = WatchWorkoutSet(order: 1, reps: 5)
            let exercise = WatchWorkoutExercise(
                order: exerciseIndex + 2,
                name: name,
                sets: [set],
                restTimerDuration: snapshot.exercises[exerciseIndex].restTimerDuration,
                muscleGroup: muscleGroup,
                exerciseUuid: catalogExerciseUuid,
                imageURL: imageURL
            )
            snapshot.exercises.insert(exercise, at: exerciseIndex + 1)
            for index in snapshot.exercises.indices {
                snapshot.exercises[index].order = index + 1
            }
            snapshot.selectedSetID = set.id
            snapshot.selectedSetText = set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .exerciseAdded,
                             exerciseID: exercise.id, setID: set.id,
                             catalogExerciseUuid: catalogExerciseUuid,
                             afterExerciseID: afterExerciseID)
        }
    }

    func replaceExercise(workoutID: UUID, exerciseID: UUID, catalogExerciseUuid: UUID, name: String, muscleGroup: String?, imageURL: String?) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            snapshot.exercises[exerciseIndex].exerciseUuid = catalogExerciseUuid
            snapshot.exercises[exerciseIndex].name = name
            snapshot.exercises[exerciseIndex].muscleGroup = muscleGroup
            snapshot.exercises[exerciseIndex].imageURL = imageURL
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .exerciseReplaced,
                             exerciseID: exerciseID,
                             catalogExerciseUuid: catalogExerciseUuid)
        }
    }

    func deleteExercise(workoutID: UUID, exerciseID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot,
                  snapshot.workoutID == workoutID,
                  snapshot.exercises.count > 1,
                  let exerciseIndex = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            snapshot.exercises.remove(at: exerciseIndex)
            for index in snapshot.exercises.indices {
                snapshot.exercises[index].order = index + 1
            }
            let fallback = snapshot.exercises[min(exerciseIndex, snapshot.exercises.count - 1)]
            snapshot.selectedSetID = fallback.sets.first?.id
            snapshot.selectedSetText = fallback.sets.first
                .map { $0.displayText(weightUnit: snapshot.weightUnit ?? .kilogram) }
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: workoutID, kind: .exerciseDeleted,
                             exerciseID: exerciseID)
        }
    }

    func startRestTimer(workoutID: UUID, duration: TimeInterval = 60) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.workoutID == workoutID else { return }
            snapshot.restTimerEnd = Date().addingTimeInterval(duration)
            snapshot.keepRestTimerRunning = true
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            guard self.commitEvent(snapshotChange: .replace(snapshot),
                                   workoutID: workoutID, kind: .restTimerUpdated,
                                   restTimerEnd: snapshot.restTimerEnd,
                                   keepRestTimerRunning: true) else { return }
            if let manager = self.workoutSessionManager, manager.uuid == workoutID {
                manager.restTimerEnd = snapshot.restTimerEnd
                manager.keepRestTimerRunning = true
            }
        }
    }

    func stopRestTimer(workoutID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.workoutID == workoutID else { return }
            snapshot.restTimerEnd = nil
            snapshot.keepRestTimerRunning = false
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            guard self.commitEvent(snapshotChange: .replace(snapshot),
                                   workoutID: workoutID, kind: .restTimerUpdated,
                                   restTimerEnd: nil,
                                   keepRestTimerRunning: false) else { return }
            if let manager = self.workoutSessionManager, manager.uuid == workoutID {
                manager.restTimerEnd = nil
                manager.keepRestTimerRunning = false
            }
        }
    }

    func finishPersistedWorkout(start: Date, end: Date, title: String?, uuid: UUID,
                                sessionEffort: Double? = nil) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid else { return }
            snapshot.startDate = start
            snapshot.endDate = end
            snapshot.title = title ?? snapshot.title
            snapshot.sessionEffort = sessionEffort.map { min(max($0, 1), 10) }
                ?? snapshot.sessionEffort
            snapshot.updatedAt = Date()
            guard self.advanceRevision(&snapshot) else { return }
            self.commitEvent(snapshotChange: .replace(snapshot),
                             workoutID: uuid, kind: .workoutFinished,
                             startDate: start, endDate: end, title: title,
                             sessionEffort: snapshot.sessionEffort,
                             eventSnapshot: snapshot)
        }
    }

    func discardPersistedWorkout(uuid: UUID) {
        WorkoutSessionManager.perform {
            guard let snapshot = self.workoutSnapshot, snapshot.workoutID == uuid else { return }
            self.commitEvent(snapshotChange: .replace(nil),
                             workoutID: uuid, kind: .workoutDiscarded,
                             startDate: snapshot.startDate,
                             endDate: snapshot.endDate,
                             title: snapshot.title)
        }
    }

    func recordHealthKitFailure(uuid: UUID, message: String) {
        WorkoutSessionManager.perform {
            self.recordHealthKitFailureOnAccessQueue(uuid: uuid, message: message)
        }
    }

    @discardableResult
    private func recordHealthKitFailureOnAccessQueue(uuid: UUID, message: String) -> Bool {
        guard let snapshot = workoutSnapshot, snapshot.workoutID == uuid else { return false }
        return commitEvent(workoutID: uuid, kind: .workoutFailed,
                           startDate: snapshot.startDate, endDate: snapshot.endDate,
                           title: message, eventSnapshot: snapshot)
    }

    func ensureWorkoutProjection(uuid: UUID, start: Date) {
        WorkoutSessionManager.perform {
            var snapshot = self.workoutSnapshot
            if snapshot?.workoutID != uuid {
                snapshot = WatchWorkoutSnapshot.placeholder(workoutID: uuid, startDate: start)
            } else {
                snapshot?.startDate = start
                snapshot?.endDate = nil
                snapshot?.updatedAt = Date()
            }
            if let snapshot = snapshot {
                self.persistSnapshot(snapshot)
            }
        }
    }

    func recoverWorkoutSession(workoutSession: HKWorkoutSession,
                               completion: (() -> Void)? = nil) {
        WorkoutSessionManager.perform {
            assert(self.workoutSessionManager == nil)
            // TODO: also recover custom start / end dates
            let workoutSessionManager = WorkoutSessionManager(session: workoutSession) // documentation says this must happen immediately
            self.workoutSessionManager = workoutSessionManager
            if let uuid = workoutSessionManager.uuid {
                if let snapshot = self.workoutSnapshot,
                   snapshot.workoutID == uuid {
                    workoutSessionManager.updateStartDate(snapshot.startDate)
                    workoutSessionManager.updateEndDate(snapshot.endDate)
                    workoutSessionManager.restTimerEnd = snapshot.restTimerEnd
                    workoutSessionManager.keepRestTimerRunning = snapshot.keepRestTimerRunning
                    workoutSessionManager.selectedSetText = snapshot.selectedSetText
                } else {
                    // HealthKit can restore a valid session after the durable
                    // projection was lost or replaced. Always synthesize a
                    // minimal editable projection so Finish and Discard remain
                    // available instead of stranding the workout.
                    let recovered = WatchWorkoutSnapshot.placeholder(
                        workoutID: uuid,
                        startDate: workoutSessionManager.startDate ?? Date())
                    self.persistSnapshot(recovered)
                }
            }
            completion?()
        }
    }
    
    
    /// - Parameters:
    ///   - completion: When the result is successful, the `workoutSessionManager` is set and the workout session is in a state other than `.ended` or `.notStarted`.
    ///                 If a workout session that is not `.ended` or `.notStarted` existed, nothing is done. Otherwise a new workout session is prepared.
    func ensurePreparedWorkoutSession(configuration: HKWorkoutConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        WorkoutSessionManager.perform {
            os_log("Ensuring prepared workout session")
            // check if there already is a current workout session
            if let workoutSessionManager = self.workoutSessionManager {
                let state = workoutSessionManager.state
                os_log("Workout session manager with state=%@ exists", type: .debug, state.name)
                // only create a new session if the current session is not running
                guard state == .ended || state == .notStarted else {
                    // there already is a running workout session, startWorkout will take care of it
                    os_log("Keeping workout session with state=%@", state.name)
                    completion(.success(()))
                    return
                }
            }
            
            let workoutSession: HKWorkoutSession
            do {
                os_log("Creating new workout session")
                workoutSession = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore, configuration: configuration)
            } catch {
                completion(.failure(error))
                return
            }
            
            self.workoutSessionManager = WorkoutSessionManager(session: workoutSession)
            self.workoutSessionManager?.prepare()
            
            completion(.success(()))
        }
    }
    
    /**
     Starts a `WorkoutSessionManager`, creating/reusing/overwriting any existing `workoutSessionManager` as necessary.
     - Postcondition
     If an error occured, `workoutSessionManager` is set to `nil`, otherwise `workoutSessionManager.uuid` is set to `uuid` and the `workoutSessionManager` is being started.
     */
    func startWorkoutSession(start: Date, uuid: UUID) {
        WorkoutSessionManager.perform {
            os_log("Starting workout session start=%@ uuid=%@", start as NSDate, uuid as NSUUID)

            // Keep the durable projection in sync even when the HealthKit
            // session is later interrupted or the watch is offline.
            var projection = self.workoutSnapshot
            if projection?.workoutID != uuid {
                projection = WatchWorkoutSnapshot.placeholder(workoutID: uuid, startDate: start)
            } else {
                projection?.startDate = start
                projection?.endDate = nil
                projection?.updatedAt = Date()
            }
            if let projection = projection {
                guard self.persistSnapshot(projection) else { return }
            }
            
            // 1. make sure we have a workout session manager, create it if necessary
            
            var workoutSessionManager: WorkoutSessionManager
            if let manager = self.workoutSessionManager {
                workoutSessionManager = manager
            } else {
                os_log("No workout session manager is set", type: .info)
                
                let workoutConfiguration = HKWorkoutConfiguration()
                workoutConfiguration.activityType = .traditionalStrengthTraining
                
                // create a new workout session manager
                do {
                    os_log("Creating workout session")
                    let session = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore, configuration: workoutConfiguration)
                    workoutSessionManager = WorkoutSessionManager(session: session)
                    self.workoutSessionManager = workoutSessionManager
                } catch {
                    os_log("Could not create new workout session: %@", type: .error, error.localizedDescription)
                    return
                }
            }
            
            // 2. What if the session is not .prepared or .notStarted ?
            
            if let currentUuid = workoutSessionManager.uuid {
                // consider workout session manager as started
                os_log("Workout session manager already has uuid, treating as already started", type: .fault, workoutSessionManager.state.name)
                
                if currentUuid == uuid {
                    
                    // 2.1 If the workout session manager has the same uuid, reuse the manager or create a new if the state is .ended
                    
                    os_log("Workout session manager uuid=%@ matches new uuid", type: .fault, currentUuid as NSUUID, workoutSessionManager.state.name)
                    switch workoutSessionManager.state {
                    case .prepared, .notStarted:
                        break
                    case .ended:
                        // we can have a ended workout session manager that was not set to nil when it was ended by the OS
                        os_log("Discarding workout session manager")
                        workoutSessionManager.discard()
                        self.workoutSessionManager = nil
                        
                        // create a new workout session manager
                        do {
                            os_log("Creating workout session")
                            let session = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore, configuration: workoutSessionManager.workoutConfiguration)
                            workoutSessionManager = WorkoutSessionManager(session: session)
                            self.workoutSessionManager = workoutSessionManager
                        } catch {
                            os_log("Could not create new workout session: %@", type: .error, error.localizedDescription)
                            return
                        }
                    default:
                        // the session is not ended and was already started, reuse it
                        os_log("Falling back to just updating the start date for workout session manager")
                        workoutSessionManager.updateStartDate(start)
                        return
                    }
                    
                } else {
                    
                    // 2.2 If the workout session manager has a different uuid, create a new manager
                    
                    os_log("Workout session manager uuid=%@ differs from new uuid=%@", type: .fault, (currentUuid as NSUUID?) ?? "nil", uuid as NSUUID)
                    
                    os_log("Discarding workout session manager")
                    workoutSessionManager.discard()
                    self.workoutSessionManager = nil
                    
                    do {
                        os_log("Creating workout session")
                        let session = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore, configuration: workoutSessionManager.workoutConfiguration)
                        workoutSessionManager = WorkoutSessionManager(session: session)
                        self.workoutSessionManager = workoutSessionManager
                    } catch {
                        os_log("Could not create new workout session: %@", type: .error, error.localizedDescription)
                        return
                    }
                }
            } else {
                // consider workout as not started
                switch workoutSessionManager.state {
                case .prepared, .notStarted:
                    break
                default:
                    os_log("Discarding workout session manager without uuid state=%@", type: .fault, workoutSessionManager.state.name)
                    assertionFailure("This should not happen, because a workout gets assigned a UUID when it is started")
                    workoutSessionManager.discard()
                    self.workoutSessionManager = nil
                    
                    // create a new workout session manager
                    do {
                        os_log("Creating workout session")
                        let session = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore, configuration: workoutSessionManager.workoutConfiguration)
                        workoutSessionManager = WorkoutSessionManager(session: session)
                        self.workoutSessionManager = workoutSessionManager
                    } catch {
                        os_log("Could not create new workout session: %@", type: .error, error.localizedDescription)
                        return
                    }
                }
            }
            
            // 3. Set the UUID
            
            assert(workoutSessionManager.state == .prepared || workoutSessionManager.state == .notStarted)
            
            do {
                os_log("Setting uuid=%@ for workout session manager", uuid as NSUUID)
                try workoutSessionManager.setUuid(uuid)
            } catch {
                os_log("Could not set uuid: %@", type: .error, error.localizedDescription)
                os_log("Discarding workout session manager", type: .info)
                workoutSessionManager.discard()
                self.workoutSessionManager = nil
                return
            }
            
            // 4. Start!
            
            os_log("Starting workout session manager")
            workoutSessionManager.start(start: start) { result in
                switch result {
                case .success:
                    WKInterfaceDevice.current().play(.start)
                    // TODO send confirmation to phone
                    os_log("Successfully started workout session manager")
                case .failure(let error):
                    WKInterfaceDevice.current().play(.failure)
                    os_log("Could not start workout session manager: %@", type: .error, error.localizedDescription)
                    WorkoutSessionManager.perform {
                        os_log("Discarding workout session manager", type: .info)
                        workoutSessionManager.discard()
                        self.workoutSessionManager = nil
                    }
                }
            }
        }
    }
    
    func endWorkoutSession(start: Date, end: Date, title: String?, uuid: UUID,
                           sessionEffort: Double? = nil,
                           notifyPhone: Bool = true) {
        WorkoutSessionManager.perform {
            os_log("Ending workout session start=%@ end=%@ title=%@ uuid=%@", start as NSDate, end as NSDate, title ?? "nil", uuid as NSUUID)

            // Queue the finish before HealthKit finalization so a process
            // termination cannot lose the explicit user action.
            var finishSnapshot = self.workoutSnapshot
            if notifyPhone,
               finishSnapshot == nil,
               self.workoutSessionManager?.uuid == uuid {
                finishSnapshot = WatchWorkoutSnapshot.placeholder(
                    workoutID: uuid,
                    startDate: self.workoutSessionManager?.startDate ?? start
                )
            }
            if notifyPhone,
               finishSnapshot?.workoutID != uuid {
                self.recordPersistenceFailure(WatchWorkoutPersistenceError.missingProjection)
                return
            }
            if var snapshot = finishSnapshot, snapshot.workoutID == uuid {
                snapshot.startDate = start
                snapshot.endDate = end
                snapshot.title = title ?? snapshot.title
                snapshot.sessionEffort = sessionEffort.map { min(max($0, 1), 10) }
                    ?? snapshot.sessionEffort
                guard self.advanceRevision(&snapshot) else { return }
                snapshot.updatedAt = Date()
                let persisted = notifyPhone
                    ? self.commitEvent(snapshotChange: .replace(snapshot),
                                       workoutID: uuid, kind: .workoutFinished,
                                       startDate: start, endDate: end, title: title,
                                       sessionEffort: snapshot.sessionEffort,
                                       eventSnapshot: snapshot)
                    : self.persistSnapshot(snapshot)
                guard persisted else { return }
            }
            
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted workout finish locally", type: .info)
                // Queue the existing failure event before removing its snapshot.
                guard self.recordHealthKitFailureOnAccessQueue(uuid: uuid, message: "No HealthKit session was available to save this workout.") else { return }
                self.archiveSnapshot(workoutID: uuid)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                // should not happen normally, but maybe could happen?
                if workoutSessionManager.uuid == nil {
                    os_log("Attempt to end workout session manager that has no UUID", type: .fault)
                } else {
                    os_log("Attempt to end workout session manager with different UUID", type: .fault)
                }
                return
            }
            
            workoutSessionManager.updateStartDate(start)

            if let title = title {
                do {
                    os_log("Setting title for workout session manager")
                    try workoutSessionManager.setTitle(title)
                } catch {
                    os_log("Could not set title: %@", type: .error, error.localizedDescription)
                    // continue though
                }
            }
            
            os_log("Ending workout session manager")
            workoutSessionManager.end(end: end) { result in
                WorkoutSessionManager.perform {
                    switch result {
                    case .success:
                        WKInterfaceDevice.current().play(.stop)
                        self.workoutSessionManager = nil
                        self.archiveSnapshot(workoutID: uuid)
                        os_log("Successfully ended workout session manager", type: .info)
                    case .failure(let error):
                        WKInterfaceDevice.current().play(.failure)
                        os_log("Could not end workout session manager: %@", type: .error, error.localizedDescription)
                        os_log("Discarding workout session manager", type: .info)
                        workoutSessionManager.discard()
                        self.workoutSessionManager = nil
                        guard self.recordHealthKitFailureOnAccessQueue(uuid: uuid, message: error.localizedDescription) else { return }
                        // The finish event was durably queued before HealthKit
                        // finalization. Archive the editor even if HealthKit
                        // fails so the user cannot submit the finish twice.
                        self.archiveSnapshot(workoutID: uuid)
                    }
                }
            }
        }
    }
    
    func updateWorkoutSessionStart(start: Date, uuid: UUID) {
        WorkoutSessionManager.perform {
            os_log("Updating workout session start=%@ uuid=%@", start as NSDate, uuid as NSUUID)
            if var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                snapshot.startDate = start
                guard self.advanceRevision(&snapshot) else { return }
                snapshot.updatedAt = Date()
                guard self.persistSnapshot(snapshot) else { return }
            }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted start time locally", type: .info)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                if workoutSessionManager.uuid == nil {
                    print("warning: attempt to update start for workout with no UUID")
                } else {
                    print("warning: attempt to update start for workout with different UUID")
                }
                return
            }
            
            workoutSessionManager.updateStartDate(start)
        }
    }
    
    func updateWorkoutSessionEnd(end: Date?, uuid: UUID) {
        WorkoutSessionManager.perform {
            os_log("Updating workout session end=%@ uuid=%@", (end as NSDate?) ?? "nil", uuid as NSUUID)
            if var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                snapshot.endDate = end
                guard self.advanceRevision(&snapshot) else { return }
                snapshot.updatedAt = Date()
                guard self.persistSnapshot(snapshot) else { return }
            }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted end time locally", type: .info)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                // should not happen normally, but maybe could happen?
                if workoutSessionManager.uuid == nil {
                    os_log("Attempt to update end for workout session manager that has no UUID", type: .fault)
                } else {
                    os_log("Attempt to update end for workout session manager with different UUID", type: .fault)
                }
                return
            }
            
            workoutSessionManager.updateEndDate(end)
        }
    }
    
    func discardWorkoutSession(uuid: UUID, notifyPhone: Bool = true) {
        WorkoutSessionManager.perform {
            os_log("Discarding workout session uuid=%@", uuid as NSUUID)
            var discardSnapshot = self.workoutSnapshot
            if notifyPhone,
               discardSnapshot == nil,
               self.workoutSessionManager?.uuid == uuid {
                discardSnapshot = WatchWorkoutSnapshot.placeholder(
                    workoutID: uuid,
                    startDate: self.workoutSessionManager?.startDate ?? Date()
                )
            }
            if notifyPhone,
               discardSnapshot?.workoutID != uuid {
                self.recordPersistenceFailure(WatchWorkoutPersistenceError.missingProjection)
                return
            }
            if let snapshot = discardSnapshot, snapshot.workoutID == uuid {
                let persisted = notifyPhone
                    ? self.commitEvent(snapshotChange: .replace(nil),
                                       workoutID: uuid, kind: .workoutDiscarded,
                                       startDate: snapshot.startDate,
                                       endDate: snapshot.endDate,
                                       title: snapshot.title)
                    : self.archiveSnapshot(workoutID: uuid)
                guard persisted else { return }
            }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; discarded persisted workout locally", type: .info)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                // should not happen normally, but maybe could happen?
                if workoutSessionManager.uuid == nil {
                    os_log("Attempt to discard workout session manager that has no UUID", type: .fault)
                } else {
                    os_log("Attempt to discard workout session manager with different UUID", type: .fault)
                }
                return
            }
            
            workoutSessionManager.discard()
            self.workoutSessionManager = nil
            print("success: discarded workout session")
        }
    }
    
    func discardUnstartedWorkoutSession() {
        WorkoutSessionManager.perform {
            os_log("Discarding unstarted workout session")
            guard let workoutSessionManager = self.workoutSessionManager else {
                // invalid
                // should not happen normally, but can happen
                os_log("Attempt to discard unstarted workout session while no workout session manager is set", type: .fault)
                return
            }
            
            // make sure no UUID is set
            if let uuid = workoutSessionManager.uuid {
                // can happen, but something probably went wrong before
                os_log("Attempt to discard unstarted workout session with uuid=%@", type: .fault, uuid as NSUUID)
                return // treat a workout session with a UUID as started, return here!
            }
            
            guard workoutSessionManager.state == .prepared || workoutSessionManager.state == .notStarted else {
                // can happen, but something probably went wrong before
                os_log("Attempt to discard unstarted workout session with state=%@", type: .fault, workoutSessionManager.state.name)
                return
            }
            
            workoutSessionManager.discard()
            self.workoutSessionManager = nil
            os_log("Discarded unstarted workout session", type: .info)
        }
    }
    
    func discardWorkoutSession() {
        WorkoutSessionManager.perform {
            os_log("Discarding workout session")
            let managerID = self.workoutSessionManager?.uuid
            var discardSnapshot = self.workoutSnapshot
            if let snapshotID = discardSnapshot?.workoutID,
               let managerID,
               snapshotID != managerID {
                self.recordPersistenceFailure(WatchWorkoutPersistenceError.missingProjection)
                return
            }
            if discardSnapshot == nil, let managerID {
                discardSnapshot = WatchWorkoutSnapshot.placeholder(
                    workoutID: managerID,
                    startDate: self.workoutSessionManager?.startDate ?? Date()
                )
            }
            guard let snapshot = discardSnapshot else {
                self.recordPersistenceFailure(WatchWorkoutPersistenceError.missingProjection)
                return
            }
            guard self.commitEvent(snapshotChange: .replace(nil),
                                   workoutID: snapshot.workoutID, kind: .workoutDiscarded,
                                   startDate: snapshot.startDate,
                                   endDate: snapshot.endDate,
                                   title: snapshot.title) else { return }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; discarded persisted workout locally", type: .info)
                return
            }
            
            workoutSessionManager.discard()
            self.workoutSessionManager = nil
            print("success: discarded workout session")
        }
    }
    
    func updateWorkoutSessionRestTimer(end: Date?, keepRunning: Bool?, uuid: UUID) {
        WorkoutSessionManager.perform {
            os_log("Updating workout session rest timer end=%@ keepRunning=%@ uuid=%@", (end as NSDate?) ?? "nil", keepRunning.map { String(describing: $0) } ?? "nil", uuid as NSUUID)
            if var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                snapshot.restTimerEnd = end
                if let keepRunning = keepRunning {
                    snapshot.keepRestTimerRunning = keepRunning
                }
                guard self.advanceRevision(&snapshot) else { return }
                snapshot.updatedAt = Date()
                guard self.persistSnapshot(snapshot) else { return }
            }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted rest timer locally", type: .info)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                // should not happen normally, but maybe could happen?
                if workoutSessionManager.uuid == nil {
                    os_log("Attempt to update rest timer for workout session manager that has no UUID", type: .fault)
                } else {
                    os_log("Attempt to update rest timer for workout session manager with different UUID", type: .fault)
                }
                return
            }
            
            workoutSessionManager.restTimerEnd = end
            if let keepRunning = keepRunning {
                workoutSessionManager.keepRestTimerRunning = keepRunning
            }

        }
    }
    
    func updateWorkoutSessionSelectedSetText(text: String?, uuid: UUID) {
        WorkoutSessionManager.perform {
            os_log("Updating workout session selected text=%@ uuid=%@", text ?? "nil", uuid as NSUUID)
            if var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                snapshot.selectedSetText = text
                guard self.advanceRevision(&snapshot) else { return }
                snapshot.updatedAt = Date()
                guard self.persistSnapshot(snapshot) else { return }
            }
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted selected set text locally", type: .info)
                return
            }
            
            // make sure the message means the current workout
            guard workoutSessionManager.uuid == uuid else {
                // invalid
                // should not happen normally, but maybe could happen?
                if workoutSessionManager.uuid == nil {
                    os_log("Attempt to update selected text for workout session manager that has no UUID", type: .fault)
                } else {
                    os_log("Attempt to update selected text for workout session manager with different UUID", type: .fault)
                }
                return
            }
            
            workoutSessionManager.selectedSetText = text
        }
    }
}
