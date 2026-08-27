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

    private struct PersistedState: Codable {
        var snapshot: WatchWorkoutSnapshot?
        var outbox: [WatchWorkoutEvent]
        var nextSequence: Int64
    }

    private let defaults = UserDefaults.standard
    private let defaultsKey = "watchWorkoutStore.v1"
    private let lock = NSLock()
    private var state: PersistedState

    private init() {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = WatchWorkoutWire.decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState(snapshot: nil, outbox: [], nextSequence: 0)
        }
    }

    private func persistLocked() {
        if let data = WatchWorkoutWire.encode(state) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    func snapshot() -> WatchWorkoutSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return state.snapshot
    }

    /// Newer revisions win, while a new workout UUID always replaces the old
    /// projection. This makes stale application-context deliveries harmless.
    @discardableResult
    func replaceSnapshot(_ snapshot: WatchWorkoutSnapshot) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let current = state.snapshot,
           current.workoutID == snapshot.workoutID,
           (current.revision > snapshot.revision ||
            (current.revision == snapshot.revision && current.updatedAt > snapshot.updatedAt)) {
            return false
        }
        state.snapshot = snapshot
        persistLocked()
        return true
    }

    func nextSequence() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        state.nextSequence += 1
        persistLocked()
        return state.nextSequence
    }

    func enqueue(_ event: WatchWorkoutEvent) {
        lock.lock(); defer { lock.unlock() }
        guard !state.outbox.contains(where: { $0.id == event.id }) else { return }
        state.outbox.append(event)
        persistLocked()
    }

    func pendingEvents() -> [WatchWorkoutEvent] {
        lock.lock(); defer { lock.unlock() }
        return state.outbox
    }

    func acknowledge(eventIDs: [UUID]) {
        guard !eventIDs.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let ids = Set(eventIDs)
        state.outbox.removeAll { ids.contains($0.id) }
        persistLocked()
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        state.snapshot = nil
        state.outbox.removeAll()
        persistLocked()
    }

    func clearSnapshot() {
        lock.lock(); defer { lock.unlock() }
        state.snapshot = nil
        persistLocked()
    }
}

class WorkoutSessionManagerStore: ObservableObject {
    static let shared = WorkoutSessionManagerStore()
    
    let objectWillChange = PassthroughSubject<Void, Never>()
    
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

    private func archiveSnapshot(workoutID: UUID) {
        guard self.workoutSnapshot?.workoutID == workoutID else { return }
        WatchWorkoutStore.shared.clearSnapshot()
        publishSnapshot(nil)
    }

    private func persistSnapshot(_ snapshot: WatchWorkoutSnapshot) {
        WatchWorkoutStore.shared.replaceSnapshot(snapshot)
        publishSnapshot(snapshot)
    }

    private func enqueue(_ event: WatchWorkoutEvent) {
        WatchWorkoutStore.shared.enqueue(event)
        DispatchQueue.main.async {
            PhoneConnectionManager.shared.flushEventOutbox()
        }
    }

    private func makeEvent(workoutID: UUID, kind: WatchWorkoutEventKind,
                           exerciseID: UUID? = nil, setID: UUID? = nil,
                           weight: Double? = nil, reps: Int? = nil,
                           rpe: Double? = nil, completed: Bool? = nil,
                           restTimerEnd: Date? = nil,
                           keepRestTimerRunning: Bool? = nil,
                           startDate: Date? = nil, endDate: Date? = nil,
                           title: String? = nil,
                           sessionEffort: Double? = nil,
                           snapshot: WatchWorkoutSnapshot? = nil) -> WatchWorkoutEvent {
        WatchWorkoutEvent(workoutID: workoutID,
                          sequence: WatchWorkoutStore.shared.nextSequence(),
                          kind: kind, exerciseID: exerciseID, setID: setID,
                          weight: weight, reps: reps, rpe: rpe,
                          completed: completed, restTimerEnd: restTimerEnd,
                          keepRestTimerRunning: keepRestTimerRunning,
                          startDate: startDate, endDate: endDate, title: title,
                          weightUnit: self.workoutSnapshot?.weightUnit,
                          sessionEffort: sessionEffort,
                          snapshot: snapshot)
    }
}

extension WorkoutSessionManagerStore {
    func applyWorkoutSnapshot(_ snapshot: WatchWorkoutSnapshot) {
        WorkoutSessionManager.perform {
            guard snapshot.schemaVersion <= WatchWorkoutWire.schemaVersion else {
                os_log("Ignoring unsupported workout snapshot version=%d", type: .error, snapshot.schemaVersion)
                return
            }
            guard WatchWorkoutStore.shared.replaceSnapshot(snapshot) else { return }
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
            snapshot.revision += 1
            snapshot.updatedAt = Date()
            self.persistSnapshot(snapshot)
            self.enqueue(self.makeEvent(workoutID: workoutID, kind: .setUpdated,
                                        exerciseID: exerciseID, setID: setID,
                                        weight: weight, reps: reps, rpe: rpe))
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
            snapshot.revision += 1
            snapshot.updatedAt = Date()
            self.persistSnapshot(snapshot)
            self.enqueue(self.makeEvent(workoutID: workoutID, kind: .setCompletionChanged,
                                        exerciseID: exerciseID, setID: setID,
                                        completed: set.completed))
        }
    }

    func startRestTimer(workoutID: UUID, duration: TimeInterval = 60) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.workoutID == workoutID else { return }
            snapshot.restTimerEnd = Date().addingTimeInterval(duration)
            snapshot.keepRestTimerRunning = true
            snapshot.revision += 1
            snapshot.updatedAt = Date()
            self.persistSnapshot(snapshot)
            if let manager = self.workoutSessionManager, manager.uuid == workoutID {
                manager.restTimerEnd = snapshot.restTimerEnd
                manager.keepRestTimerRunning = true
            }
            self.enqueue(self.makeEvent(workoutID: workoutID, kind: .restTimerUpdated,
                                        restTimerEnd: snapshot.restTimerEnd,
                                        keepRestTimerRunning: true))
        }
    }

    func stopRestTimer(workoutID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.workoutID == workoutID else { return }
            snapshot.restTimerEnd = nil
            snapshot.keepRestTimerRunning = false
            snapshot.revision += 1
            snapshot.updatedAt = Date()
            self.persistSnapshot(snapshot)
            if let manager = self.workoutSessionManager, manager.uuid == workoutID {
                manager.restTimerEnd = nil
                manager.keepRestTimerRunning = false
            }
            self.enqueue(self.makeEvent(workoutID: workoutID, kind: .restTimerUpdated,
                                        restTimerEnd: nil, keepRestTimerRunning: false))
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
            snapshot.revision += 1
            self.persistSnapshot(snapshot)
            self.enqueue(self.makeEvent(workoutID: uuid, kind: .workoutFinished,
                                        startDate: start, endDate: end, title: title,
                                        sessionEffort: snapshot.sessionEffort,
                                        snapshot: snapshot))
        }
    }

    func discardPersistedWorkout(uuid: UUID) {
        WorkoutSessionManager.perform {
            guard let snapshot = self.workoutSnapshot, snapshot.workoutID == uuid else { return }
            self.enqueue(self.makeEvent(workoutID: uuid, kind: .workoutDiscarded,
                                        startDate: snapshot.startDate,
                                        endDate: snapshot.endDate,
                                        title: snapshot.title))
            WatchWorkoutStore.shared.clearSnapshot()
            self.publishSnapshot(nil)
        }
    }

    func recordHealthKitFailure(uuid: UUID, message: String) {
        WorkoutSessionManager.perform {
            guard let snapshot = self.workoutSnapshot, snapshot.workoutID == uuid else { return }
            self.enqueue(self.makeEvent(workoutID: uuid, kind: .workoutFailed,
                                        startDate: snapshot.startDate,
                                        endDate: snapshot.endDate,
                                        title: message))
        }
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
                self.persistSnapshot(projection)
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
            if var snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                snapshot.startDate = start
                snapshot.endDate = end
                snapshot.title = title ?? snapshot.title
                snapshot.sessionEffort = sessionEffort.map { min(max($0, 1), 10) }
                    ?? snapshot.sessionEffort
                snapshot.revision += 1
                snapshot.updatedAt = Date()
                self.persistSnapshot(snapshot)
                if notifyPhone {
                    self.enqueue(self.makeEvent(workoutID: uuid, kind: .workoutFinished,
                                                startDate: start, endDate: end, title: title,
                                                sessionEffort: snapshot.sessionEffort,
                                                snapshot: snapshot))
                }
            }
            
            guard let workoutSessionManager = self.workoutSessionManager else {
                os_log("No HealthKit session; persisted workout finish locally", type: .info)
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
                snapshot.revision += 1
                snapshot.updatedAt = Date()
                self.persistSnapshot(snapshot)
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
                snapshot.revision += 1
                snapshot.updatedAt = Date()
                self.persistSnapshot(snapshot)
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
            if let snapshot = self.workoutSnapshot, snapshot.workoutID == uuid {
                if notifyPhone {
                    self.enqueue(self.makeEvent(workoutID: uuid, kind: .workoutDiscarded,
                                                startDate: snapshot.startDate,
                                                endDate: snapshot.endDate,
                                                title: snapshot.title))
                }
                WatchWorkoutStore.shared.clearSnapshot()
                self.publishSnapshot(nil)
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
            if let snapshot = self.workoutSnapshot {
                self.enqueue(self.makeEvent(workoutID: snapshot.workoutID, kind: .workoutDiscarded,
                                            startDate: snapshot.startDate,
                                            endDate: snapshot.endDate,
                                            title: snapshot.title))
                WatchWorkoutStore.shared.clearSnapshot()
                self.publishSnapshot(nil)
            }
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
                snapshot.revision += 1
                snapshot.updatedAt = Date()
                self.persistSnapshot(snapshot)
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
                snapshot.revision += 1
                snapshot.updatedAt = Date()
                self.persistSnapshot(snapshot)
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
