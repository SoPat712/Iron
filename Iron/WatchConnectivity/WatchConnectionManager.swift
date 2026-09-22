//
//  WatchConnectionManager.swift
//  Iron
//
//  Created by Karim Abou Zeid on 02.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import WatchConnectivity
import CoreData
import Combine
import HealthKit
import WorkoutDataKit
import UIKit
import Intents
import os.log

/// The following behaviour was tested on watchOS 6.2 and iOS 13.4:
/// When the watch app is not reachable, data often won't arrive until the app is opened. Sometimes the data arrives, but then the watch only answers when the watch app is opened.

/// - BUG:
///     When using the intents extension, and the app is completely closed and then launched by Siri in the background, the app restarts *every* time before receiving a message from the watch. Because of that, when the prepared message arrives, the app is restarted and the preparedHandler is nil.
///     I think this is a bug, because when the app was already in background before that, this doesn't happen.
///     Tested on iOS 13.4, watchOS 6.2, Xcode 11.

class WatchConnectionManager: NSObject, ObservableObject {
    static let shared = WatchConnectionManager()

    /// Drives every phone surface that displays pairing, installation, or
    /// reachability. WCSession changes arrive through delegate callbacks, so
    /// expose a lightweight revision instead of leaving settings stale until
    /// the user manually refreshes.
    @Published private(set) var connectionRevision = 0
    
    private let session = WCSession.default

    private struct EventLedger: Codable {
        var recentEventIDs: [UUID] = []
        var latestSequenceByField: [String: Int64] = [:]
    }

    private static let eventLedgerDefaultsKey = "watchWorkoutEventLedger.v1"
    private var eventLedger: EventLedger
    private var selectedWatchSetUuid: UUID?
    private var pendingSnapshot: WatchWorkoutSnapshot?
    private var lastSnapshotRevision: Int64 = 0

    private override init() {
        if let data = UserDefaults.standard.data(forKey: Self.eventLedgerDefaultsKey),
           let ledger = WatchWorkoutWire.decode(EventLedger.self, from: data) {
            eventLedger = ledger
        } else {
            eventLedger = EventLedger()
        }
        super.init()
    }
    
    func activateSession() {
        guard WCSession.isSupported() else {
            os_log("WatchConnectivity is not supported on this device", log: .watch, type: .error)
            return
        }
        session.delegate = self
        session.activate()
    }

    /// Re-reads the current pairing/install/reachability state for settings.
    /// An already-activated WCSession does not need a synthetic delay: publish
    /// its current values immediately. Otherwise the activation delegate will
    /// publish when WatchConnectivity has actually completed the request.
    func refreshConnectionStatus() {
        guard WCSession.isSupported() else {
            publishConnectionStatus()
            return
        }

        session.delegate = self
        if session.activationState == .activated {
            publishConnectionStatus()
        } else {
            session.activate()
        }
    }
    
    var isReachable: Bool {
        session.isReachable
    }
    
    var isActivated: Bool {
        session.activationState == .activated
    }

    var isPaired: Bool {
        session.isPaired
    }

    var isWatchAppInstalled: Bool {
        session.isWatchAppInstalled
    }

    private func publishConnectionStatus() {
        DispatchQueue.main.async {
            self.connectionRevision &+= 1
        }
    }
    
    typealias PrepareHandler = (() -> Void)
    private var preparedHandler: PrepareHandler?
    
    typealias StartWatchCompanionErrorHandler = ((Error) -> Void)
    
    let selectedSetChangePublisher = PassthroughSubject<(WorkoutSet?, UUID), Never>()
    var selectedSetChangePublisherCancellable: Cancellable?
    var selectedSetCancellable: Cancellable?
}

extension WatchConnectionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        os_log("Session activation completed isActivated=%@ error=%@", log: .watch, type: .info, String(describing: activationState == .activated), error?.localizedDescription ?? "nil") // printing activationState directly doesn't work
        publishConnectionStatus()
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            if let snapshot = self.pendingSnapshot {
                self.sendWorkoutSnapshot(snapshot)
            } else {
                self.syncCurrentWorkoutSnapshot()
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        os_log("Session did become inactive", log: .watch, type: .debug)
        publishConnectionStatus()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        os_log("Session was deactivated", log: .watch, type: .debug)
        publishConnectionStatus()
        // connect to the new Apple Watch
        os_log("Reactivating session", log: .watch, type: .debug)
        activateSession()
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        os_log("Received applicationContext=%@", log: .watch, type: .debug, applicationContext)
        
        receive(message: applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        os_log("Received userInfo=%@", log: .watch, type: .debug, userInfo)
        
        receive(message: userInfo)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        os_log("Received message=%@", log: .watch, type: .debug, message)
        
        receive(message: message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        os_log("Received message=%@", log: .watch, type: .debug, message)
        
        receive(message: message, replyHandler: replyHandler)
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        os_log("Session reachability did change isReachable=%@", log: .watch, type: .debug, String(describing: session.isReachable))
        publishConnectionStatus()
        guard session.isReachable else { return }
        DispatchQueue.main.async {
            self.syncCurrentWorkoutSnapshot()
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        os_log(
            "Watch state changed paired=%@ installed=%@",
            log: .watch,
            type: .debug,
            String(describing: session.isPaired),
            String(describing: session.isWatchAppInstalled)
        )
        publishConnectionStatus()
    }
}

extension WatchConnectionManager {
    private func receive(message: [String : Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        if let eventData = message[PayloadKey.workoutEvent] as? Data,
           let event = WatchWorkoutWire.decode(WatchWorkoutEvent.self, from: eventData) {
            handleWorkoutEvent(event, replyHandler: replyHandler)
        } else if let prepared = message[PayloadKey.preparedWorkoutSession] as? Bool, prepared {
            handlePreparedWorkoutSessionMessage()
            replyHandler?([:])
        } else {
            replyHandler?([:])
        }
    }
    
    private func handlePreparedWorkoutSessionMessage() {
        os_log("Handling prepared workout session message", log: .watch)
        
        guard let preparedHandler = self.preparedHandler else {
            // if we receive this message and no one is listening for this, tell the watch to unprepare
            os_log("No prepare handler is set", log: .watch, type: .error)
            ignorePreparedWatchWorkout()
            return
        }
        
        preparedHandler()
        self.preparedHandler = nil
    }
}

// MARK: - Durable watch edits
extension WatchConnectionManager {
    struct DeferredWatchEventEffects {
        let perform: () -> Void

        static var none: DeferredWatchEventEffects { DeferredWatchEventEffects(perform: {}) }
    }

    /// Captures only changes made by one Watch event. Pre-existing unsaved user
    /// edits are processed before the temporary undo group begins and therefore
    /// survive an event save failure.
    static func persistWatchEventMutation(
        in context: NSManagedObjectContext,
        save: () throws -> Void,
        mutation: () throws -> DeferredWatchEventEffects
    ) throws -> DeferredWatchEventEffects {
        try context.persistMutation(save: save, mutation: mutation)
    }

    static func commitWatchEventMutation(
        in context: NSManagedObjectContext,
        save: () throws -> Void,
        mutation: () throws -> DeferredWatchEventEffects,
        didPersist: () -> Void
    ) throws {
        let effects = try persistWatchEventMutation(
            in: context,
            save: save,
            mutation: mutation
        )
        effects.perform()
        didPersist()
    }

    private func handleWorkoutEvent(_ event: WatchWorkoutEvent,
                                    replyHandler: (([String: Any]) -> Void)?) {
        guard event.schemaVersion <= WatchWorkoutWire.schemaVersion else {
            os_log("Ignoring unsupported Watch workout event version=%d", log: .watch, type: .error, event.schemaVersion)
            replyHandler?([:])
            return
        }

        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        context.perform {
            if self.eventLedger.recentEventIDs.contains(event.id) {
                self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                return
            }

            let fieldKey = self.sequenceFieldKey(for: event)
            if let lastSequence = self.eventLedger.latestSequenceByField[fieldKey],
               lastSequence >= event.sequence {
                self.recordProcessed(event, fieldKey: fieldKey)
                self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                return
            }

            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "uuid == %@", event.workoutID as NSUUID)

            do {
                guard let workout = try context.fetch(request).first else {
                    // The workout may have been removed on the phone while the
                    // watch was offline. Acknowledge so it does not retry forever.
                    self.recordProcessed(event, fieldKey: fieldKey)
                    self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                    return
                }

                try Self.commitWatchEventMutation(
                    in: context,
                    save: {
                        if context.hasChanges { try context.save() }
                    },
                    mutation: { try self.applyWatchEventModelMutation(event, to: workout, in: context) },
                    didPersist: {
                        self.recordProcessed(event, fieldKey: fieldKey)
                        self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                    }
                )

                if event.kind != .workoutDiscarded,
                   !workout.isDeleted,
                   workout.isCurrentWorkout {
                    self.sendWorkoutSnapshot(self.makeSnapshot(for: workout))
                }
            } catch {
                os_log("Could not apply Watch workout event %@: %@", log: .watch, type: .error,
                       event.id.uuidString, error.localizedDescription)
                // No acknowledgement: the durable Watch outbox will retry.
                replyHandler?([:])
            }
        }
    }

    func applyWatchEventModelMutation(
        _ event: WatchWorkoutEvent,
        to workout: Workout,
        in context: NSManagedObjectContext
    ) throws -> DeferredWatchEventEffects {
        switch event.kind {
        case .setUpdated:
            guard workout.isCurrentWorkout,
                  let set = workoutSet(with: event.setID, in: workout) else { return .none }
            apply(weight: event.weight, reps: event.reps, rpe: event.rpe,
                  unit: event.weightUnit, to: set)
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setCompletionChanged:
            guard workout.isCurrentWorkout,
                  let set = workoutSet(with: event.setID, in: workout),
                  let completed = event.completed else { return .none }
            set.isCompleted = completed
            set.completedAt = completed ? (set.completedAt ?? event.createdAt) : nil
            if completed, let workoutExercise = set.workoutExercise {
                let restTimerDuration = workoutExercise.restTimerDurationValue
                    ?? defaultRestTimerDuration(for: workoutExercise)
                let restTimerEnd = event.createdAt.addingTimeInterval(restTimerDuration)
                return DeferredWatchEventEffects {
                    // This applies one atomic timer snapshot and intentionally
                    // does not echo a Watch-originated timer back to the Watch.
                    RestTimerStore.shared.applyWatchUpdate(end: restTimerEnd)
                    WorkoutLiveActivityManager.shared.setCompleted(
                        set,
                        in: workoutExercise,
                        workout: workout
                    )
                }
            } else {
                return DeferredWatchEventEffects {
                    RestTimerStore.shared.cancel()
                    WorkoutLiveActivityManager.shared.startOrUpdate(
                        for: workout,
                        preservingTransition: false
                    )
                }
            }
        case .restTimerUpdated:
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects {
                RestTimerStore.shared.applyWatchUpdate(end: event.restTimerEnd)
                WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
            }

        case .workoutFinished:
            guard workout.isCurrentWorkout else { return .none }
            if let snapshot = event.snapshot {
                apply(snapshot, to: workout)
            }
            let start = event.startDate ?? event.snapshot?.startDate ?? workout.safeStart
            let requestedEnd = event.endDate ?? event.snapshot?.endDate ?? Date()
            workout.start = start
            workout.end = max(requestedEnd, start)
            if let title = event.title ?? event.snapshot?.title {
                workout.title = title
            }
            if let effort = event.sessionEffort ?? event.snapshot?.sessionEffort {
                workout.sessionEffortValue = effort
            }
            workout.deleteExercisesWhereAllSetsAreUncompleted()
            workout.deleteUncompletedSets()
            workout.isCurrentWorkout = false
            return DeferredWatchEventEffects { [weak self] in
                self?.currentWatchWorkoutUuid = nil
                RestTimerStore.shared.cancel()
                WorkoutLiveActivityManager.shared.end(for: workout, completed: true)
            }

        case .workoutDiscarded:
            guard workout.isCurrentWorkout else { return .none }
            let activityEndSnapshot = WorkoutLiveActivityManager.shared.endSnapshot(for: workout)
            let workoutID = workout.uuid
            context.delete(workout)
            return DeferredWatchEventEffects { [weak self] in
                self?.currentWatchWorkoutUuid = nil
                RestTimerStore.shared.cancel()
                WorkoutLiveActivityManager.shared.end(using: activityEndSnapshot, completed: false)
                self?.deleteStartWorkoutInteractionDonation(workoutID: workoutID)
            }

        case .workoutFailed:
            // Keep the phone's workout intact, but allow a fresh HealthKit
            // session to be prepared the next time the apps reconnect.
            let shouldClearWatchWorkout = workout.isCurrentWorkout
            return DeferredWatchEventEffects { [weak self] in
                if shouldClearWatchWorkout {
                    self?.currentWatchWorkoutUuid = nil
                }
                os_log("Watch reported a failed workout session", log: .watch, type: .error)
            }

        case .setAdded:
            guard workout.isCurrentWorkout,
                  let workoutExercise = workoutExercise(with: event.exerciseID, in: workout) else { return .none }
            if let setID = event.setID, workoutSet(with: setID, in: workout) != nil {
                return .none
            }
            let set = WorkoutSet.create(context: context)
            if let setID = event.setID {
                set.uuid = setID
            }
            set.workoutExercise = workoutExercise
            apply(weight: event.weight, reps: event.reps, rpe: event.rpe,
                  unit: event.weightUnit, to: set)
            set.isCompleted = false
            let selectedSetID = set.uuid
            return DeferredWatchEventEffects { [weak self] in
                self?.selectedWatchSetUuid = selectedSetID
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setDeleted:
            guard workout.isCurrentWorkout,
                  let set = workoutSet(with: event.setID, in: workout),
                  let workoutExercise = set.workoutExercise,
                  (workoutExercise.workoutSets?.count ?? 0) > 1 else { return .none }
            let replacementSelectedSetID: UUID? = selectedWatchSetUuid == set.uuid
                ? (workoutExercise.workoutSets?.array as? [WorkoutSet])?
                    .first { $0.uuid != set.uuid }?.uuid
                : selectedWatchSetUuid
            context.delete(set)
            return DeferredWatchEventEffects { [weak self] in
                self?.selectedWatchSetUuid = replacementSelectedSetID
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setTagChanged:
            guard workout.isCurrentWorkout,
                  let set = workoutSet(with: event.setID, in: workout) else { return .none }
            set.tagValue = event.tag.flatMap { WorkoutSetTag(rawValue: $0) }
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .exerciseAdded:
            return addExercise(from: event, to: workout, in: context)

        case .exerciseReplaced:
            guard workout.isCurrentWorkout,
                  let workoutExercise = workoutExercise(with: event.exerciseID, in: workout),
                  let catalogID = event.catalogExerciseUuid,
                  ExerciseStore.find(in: ExerciseStore.shared.exercises, with: catalogID) != nil else { return .none }
            workoutExercise.exerciseUuid = catalogID
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .exerciseDeleted:
            guard workout.isCurrentWorkout,
                  let workoutExercise = workoutExercise(with: event.exerciseID, in: workout),
                  orderedExercises(in: workout).count > 1 else { return .none }
            context.delete(workoutExercise)
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }
        }
    }

    private func addExercise(from event: WatchWorkoutEvent,
                             to workout: Workout,
                             in context: NSManagedObjectContext) -> DeferredWatchEventEffects {
        guard workout.isCurrentWorkout,
              let catalogID = event.catalogExerciseUuid,
              ExerciseStore.find(in: ExerciseStore.shared.exercises, with: catalogID) != nil else { return .none }
        if let exerciseID = event.exerciseID, workoutExercise(with: exerciseID, in: workout) != nil {
            return .none
        }

        let workoutExercise = WorkoutExercise.create(context: context)
        if let exerciseID = event.exerciseID {
            workoutExercise.uuid = exerciseID
        }
        workoutExercise.exerciseUuid = catalogID
        insert(workoutExercise, in: workout, after: event.afterExerciseID)
        workoutExercise.restTimerDurationValue = defaultRestTimerDuration(for: workoutExercise)

        let set = WorkoutSet.create(context: context)
        if let setID = event.setID {
            set.uuid = setID
        }
        set.workoutExercise = workoutExercise
        apply(weight: event.weight, reps: event.reps ?? 5, rpe: event.rpe,
              unit: event.weightUnit, to: set)
        set.isCompleted = false
        let selectedSetID = set.uuid
        return DeferredWatchEventEffects { [weak self] in
            self?.selectedWatchSetUuid = selectedSetID
            WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
        }
    }

    private func defaultRestTimerDuration(
        for workoutExercise: WorkoutExercise
    ) -> TimeInterval {
        switch workoutExercise.exercise(in: ExerciseStore.shared.exercises)?.type {
        case .barbell:
            return SettingsStore.shared.defaultRestTimeBarbellBased
        case .dumbbell:
            return SettingsStore.shared.defaultRestTimeDumbbellBased
        default:
            return SettingsStore.shared.defaultRestTime
        }
    }

    private func deleteStartWorkoutInteractionDonation(workoutID: UUID?) {
        guard let workoutID else { return }
        os_log("Deleting start workout interaction with uuid=%@", log: .siri, workoutID as NSUUID)
        INInteraction.delete(with: [workoutID.uuidString]) { error in
            if let error {
                os_log("Deleting interaction failed: %@", log: .siri, type: .error, error.localizedDescription)
            } else {
                os_log("Successfully deleted interaction with uuid=%@", log: .siri, type: .info, workoutID as NSUUID)
            }
        }
    }

    private func apply(_ snapshot: WatchWorkoutSnapshot, to workout: Workout) {
        if let effort = snapshot.sessionEffort {
            workout.sessionEffortValue = effort
        }
        let exercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.compactMap { exercise in
            exercise.uuid.map { ($0, exercise) }
        })

        for watchExercise in snapshot.exercises {
            guard let exercise = exerciseByID[watchExercise.id] else { continue }
            let sets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
            let setByID = Dictionary(uniqueKeysWithValues: sets.compactMap { set in
                set.uuid.map { ($0, set) }
            })
            for watchSet in watchExercise.sets {
                guard let set = setByID[watchSet.id] else { continue }
                apply(weight: watchSet.weight, reps: watchSet.reps, rpe: watchSet.rpe,
                      unit: snapshot.weightUnit, to: set)
                set.isCompleted = watchSet.completed
                set.completedAt = watchSet.completed ? (set.completedAt ?? snapshot.updatedAt) : nil
                set.tagValue = watchSet.tag.flatMap { WorkoutSetTag(rawValue: $0) }
            }
        }
    }

    private func apply(weight: Double?, reps: Int?, rpe: Double?,
                       unit: WatchWorkoutWeightUnit?, to set: WorkoutSet) {
        set.weight = weight.map { NSNumber(value: canonicalWeight($0, unit: unit)) }
        set.repetitions = reps.map { NSNumber(value: min(max($0, 0), Int(WorkoutSet.MAX_REPETITIONS))) }
        set.rpeValue = rpe
    }

    private func orderedExercises(in workout: Workout) -> [WorkoutExercise] {
        workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
    }

    private func workoutExercise(with id: UUID?, in workout: Workout) -> WorkoutExercise? {
        guard let id else { return nil }
        return orderedExercises(in: workout).first { $0.uuid == id }
    }

    private func insert(_ workoutExercise: WorkoutExercise,
                        in workout: Workout,
                        after afterID: UUID?) {
        workout.addToWorkoutExercises(workoutExercise)
        guard let afterID,
              var ordered = workout.workoutExercises?.array as? [WorkoutExercise],
              let afterIndex = ordered.firstIndex(where: { $0.uuid == afterID }),
              let currentIndex = ordered.firstIndex(where: { $0.objectID == workoutExercise.objectID }) else { return }
        let exercise = ordered.remove(at: currentIndex)
        let adjustedAfter = currentIndex <= afterIndex ? afterIndex - 1 : afterIndex
        ordered.insert(exercise, at: min(adjustedAfter + 1, ordered.count))
        workout.workoutExercises = NSOrderedSet(array: ordered)
    }

    private func workoutSet(with id: UUID?, in workout: Workout) -> WorkoutSet? {
        guard let id = id else { return nil }
        return orderedExercises(in: workout)
            .flatMap { $0.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? [] }
            .first { $0.uuid == id }
    }

    private func canonicalWeight(_ value: Double, unit: WatchWorkoutWeightUnit?) -> Double {
        guard unit == .pound else { return value }
        return WeightUnit.convert(weight: value, from: .imperial, to: .metric)
    }

    private func sequenceFieldKey(for event: WatchWorkoutEvent) -> String {
        switch event.kind {
        case .setUpdated:
            return "\(event.workoutID.uuidString):\(event.setID?.uuidString ?? "unknown"):values"
        case .setCompletionChanged:
            return "\(event.workoutID.uuidString):\(event.setID?.uuidString ?? "unknown"):completion"
        case .restTimerUpdated:
            return "\(event.workoutID.uuidString):timer"
        case .workoutFinished, .workoutDiscarded, .workoutFailed:
            return "\(event.workoutID.uuidString):lifecycle"
        case .setAdded, .setDeleted, .setTagChanged,
             .exerciseAdded, .exerciseReplaced, .exerciseDeleted:
            return "\(event.workoutID.uuidString):\(event.id.uuidString):\(event.kind.rawValue)"
        }
    }

    private func recordProcessed(_ event: WatchWorkoutEvent, fieldKey: String) {
        eventLedger.recentEventIDs.append(event.id)
        if eventLedger.recentEventIDs.count > 512 {
            eventLedger.recentEventIDs.removeFirst(eventLedger.recentEventIDs.count - 512)
        }
        eventLedger.latestSequenceByField[fieldKey] = max(
            event.sequence,
            eventLedger.latestSequenceByField[fieldKey] ?? Int64.min)
        if eventLedger.latestSequenceByField.count > 2_048 {
            let keysToRemove = Array(eventLedger.latestSequenceByField.keys.prefix(
                eventLedger.latestSequenceByField.count - 2_048))
            for key in keysToRemove {
                eventLedger.latestSequenceByField.removeValue(forKey: key)
            }
        }
        if let data = WatchWorkoutWire.encode(eventLedger) {
            UserDefaults.standard.set(data, forKey: Self.eventLedgerDefaultsKey)
        }
    }

    private func acknowledge(eventID: UUID,
                             replyHandler: (([String: Any]) -> Void)?) {
        guard let data = WatchWorkoutWire.encode(WatchWorkoutEventAck(eventIDs: [eventID])) else {
            replyHandler?([:])
            return
        }
        let payload: [String: Any] = [PayloadKey.workoutEventAck: data]
        if let replyHandler = replyHandler {
            replyHandler(payload)
            return
        }
        guard isActivated else { return }
        session.transferUserInfo(payload)
        if isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension WatchConnectionManager {
    /// Publishes the complete current workout through application context (the
    /// durable latest value) and an immediate message when the Watch is reachable.
    func syncCurrentWorkoutSnapshot() {
        guard SettingsStore.shared.watchCompanion,
              let currentWatchWorkoutUuid = currentWatchWorkoutUuid else { return }
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        context.perform {
            do {
                guard let workout = try context.fetch(Workout.currentWorkoutFetchRequest).first,
                      workout.uuid == currentWatchWorkoutUuid else { return }
                self.sendWorkoutSnapshot(self.makeSnapshot(for: workout))
            } catch {
                os_log("Could not create Watch workout snapshot: %@", log: .watch, type: .error,
                       error.localizedDescription)
            }
        }
    }

    private func makeSnapshot(for workout: Workout) -> WatchWorkoutSnapshot {
        let now = Date()
        let workoutID = workout.uuid ?? UUID()
        if workout.uuid == nil { workout.uuid = workoutID }

        let appWeightUnit = SettingsStore.shared.weightUnit
        let wireWeightUnit: WatchWorkoutWeightUnit = appWeightUnit == .imperial ? .pound : .kilogram
        let displayWeight: (NSNumber?) -> Double? = { weight in
            guard let kilograms = weight?.doubleValue else { return nil }
            return WeightUnit.convert(weight: kilograms, from: .metric, to: appWeightUnit)
        }

        let workoutExercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
        let watchExercises: [WatchWorkoutExercise] = workoutExercises.enumerated().map { exerciseIndex, workoutExercise in
            let exerciseID = workoutExercise.uuid ?? UUID()
            if workoutExercise.uuid == nil { workoutExercise.uuid = exerciseID }

            let previousExercise = (try? workoutExercise.managedObjectContext?
                .fetch(workoutExercise.historyFetchRequest).first) ?? nil
            let previousSets = previousExercise?.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
            let sets = workoutExercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
            let watchSets = sets.enumerated().map { setIndex, set -> WatchWorkoutSet in
                let setID = set.uuid ?? UUID()
                if set.uuid == nil { set.uuid = setID }
                let previousSet = previousSets.indices.contains(setIndex)
                    ? previousSets[setIndex]
                    : previousSets.last
                return WatchWorkoutSet(
                    id: setID,
                    order: setIndex + 1,
                    weight: displayWeight(set.weight),
                    reps: set.repetitions?.intValue,
                    rpe: set.rpeValue,
                    previousWeight: displayWeight(previousSet?.weight),
                    previousReps: previousSet?.repetitions?.intValue,
                    completed: set.isCompleted,
                    tag: set.tagValue?.rawValue)
            }
            let catalog = workoutExercise.exercise(in: ExerciseStore.shared.exercises)
            let title = catalog?.title ?? "Exercise"
            let restTimerDuration = workoutExercise.restTimerDurationValue
                ?? defaultRestTimerDuration(for: workoutExercise)
            return WatchWorkoutExercise(id: exerciseID, order: exerciseIndex + 1,
                                        name: title, sets: watchSets,
                                        restTimerDuration: restTimerDuration,
                                        muscleGroup: catalog?.muscleGroup,
                                        exerciseUuid: workoutExercise.exerciseUuid,
                                        imageURL: catalog?.imageURL?.absoluteString,
                                        imageData: catalog?.imageURL == nil
                                            ? catalog.flatMap(WatchExerciseThumbnailEncoder.jpeg(for:))
                                            : nil)
        }

        let allSets = watchExercises.flatMap(\.sets)
        let selectedID = selectedWatchSetUuid.flatMap { selected in
            allSets.contains(where: { $0.id == selected }) ? selected : nil
        } ?? allSets.first(where: { !$0.completed })?.id ?? allSets.first?.id
        let selectedText = allSets.first(where: { $0.id == selectedID })
            .map { $0.displayText(weightUnit: wireWeightUnit) }

        let timestampRevision = Int64(now.timeIntervalSince1970 * 1_000)
        lastSnapshotRevision = max(lastSnapshotRevision + 1, timestampRevision)
        return WatchWorkoutSnapshot(
            workoutID: workoutID,
            title: workout.displayTitle(in: ExerciseStore.shared.exercises),
            startDate: workout.start ?? now,
            endDate: workout.end,
            exercises: watchExercises,
            selectedSetID: selectedID,
            selectedSetText: selectedText,
            restTimerEnd: RestTimerStore.shared.restTimerEnd,
            keepRestTimerRunning: SettingsStore.shared.keepRestTimerRunning,
            weightUnit: wireWeightUnit,
            sessionEffort: workout.sessionEffortValue,
            library: makeLibrary(for: workoutExercises),
            revision: lastSnapshotRevision,
            updatedAt: now)
    }

    private func makeLibrary(for workoutExercises: [WorkoutExercise]) -> [WatchExercisePick] {
        var picks: [WatchExercisePick] = []
        var seen = Set<UUID>()

        func append(_ exercise: Exercise) {
            guard seen.insert(exercise.uuid).inserted else { return }
            picks.append(WatchExercisePick(id: exercise.uuid, name: exercise.title, muscle: exercise.muscleGroup, imageURL: exercise.imageURL?.absoluteString))
        }

        for workoutExercise in workoutExercises {
            if let exercise = workoutExercise.exercise(in: ExerciseStore.shared.exercises) {
                append(exercise)
            }
        }
        for exercise in ExerciseStore.shared.shownExercises.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if picks.count >= 120 { break }
            append(exercise)
        }
        return picks
    }

    private enum WatchExerciseThumbnailEncoder {
        static func jpeg(for exercise: Exercise) -> Data? {
            guard let path = exercise.pdfPaths.first else { return nil }
            let url = ExerciseStore.defaultBuiltInExercisesResourceURL.appendingPathComponent(path)
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
            let pageRect = page.getBoxRect(.mediaBox)
            let edge: CGFloat = 120
            let scale = min(edge / pageRect.width, edge / pageRect.height)
            let renderSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let renderer = UIGraphicsImageRenderer(size: renderSize)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: renderSize))
                context.cgContext.translateBy(x: 0, y: renderSize.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                context.cgContext.drawPDFPage(page)
            }
            return image.jpegData(compressionQuality: 0.72)
        }
    }

    private func sendWorkoutSnapshot(_ snapshot: WatchWorkoutSnapshot) {
        pendingSnapshot = snapshot
        guard isActivated,
              let data = WatchWorkoutWire.encode(snapshot) else { return }
        let payload: [String: Any] = [PayloadKey.workoutSnapshot: data]
        do {
            try session.updateApplicationContext(payload)
            pendingSnapshot = nil
        } catch {
            os_log("Could not update Watch application context: %@", log: .watch, type: .error,
                   error.localizedDescription)
        }
        if isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                os_log("Could not immediately send Watch workout snapshot: %@", log: .watch,
                       type: .debug, error.localizedDescription)
            }
        }
    }

    /// wrapper to send either via message or transfer, depending on what's available
    private func sendUserInfo(userInfo: [String : Any]) {
        assert(isActivated)
        if isReachable {
            os_log("Messaging userInfo=%@", log: .watch, type: .debug, userInfo)
            session.sendMessage(userInfo, replyHandler: nil) { error in
                os_log("Messaging not possible, falling back to transfering", log: .watch, type: .fault)
                self.session.transferUserInfo(userInfo)
            }
        } else {
            os_log("Transfering userInfo=%@", log: .watch, type: .debug, userInfo)
            session.transferUserInfo(userInfo)
        }
    }
    
    
    /// - NOTE: If in the prepare handler a workout session isn't started, a ignorePreparedWorkoutSession should be send
    func prepareWatchWorkout(startWatchCompanionErrorHandler: StartWatchCompanionErrorHandler? = nil, preparedHandler: @escaping PrepareHandler) {
        os_log("Preparing watch app", log: .watch, type: .default)
        guard isActivated else {
            // makes no sense to prepare the workout if we can't send messages
            os_log("Session is not activated, skip preparing watch app", log: .watch, type: .info)
            return
        }
        self.preparedHandler = preparedHandler // set here, because the prepare message can be received even before startWatchApp() completion fires
        os_log("Using HKHealthStore to open watch app", log: .watch, type: .default)
        HealthManager.shared.healthStore.startWatchApp(with: HealthManager.shared.workoutConfiguration) { success, error in
            guard success else {
                // This happens when app is in background (e.g. when started from an intent)
                os_log("HKHealthStore could not open watch app: %@", log: .watch, type: .fault, error?.localizedDescription ?? "nil")
                startWatchCompanionErrorHandler?(error ?? GenericError(description: "Opening the watch app was unsuccessful"))
                return
            }
            os_log("Successfully opened watch app", log: .watch, type: .info)
        }
    }
    
    /// Tells the watch that it should not expect an answer to its prepared message
    func ignorePreparedWatchWorkout() {
        os_log("Notifying watch app that prepared message was ignored", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip notifying watch app", log: .watch, type: .info)
            return
        }
        sendUserInfo(userInfo: [PayloadKey.ignoredPreparedWorkoutSession : true])
    }
    
    func startWatchWorkout(start: Date, uuid: UUID) {
        os_log("Starting watch workout", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip starting watch workout", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != nil {
            os_log("Overwriting currentWatchWorkoutUuid", log: .watch, type: .error)
        }
        sendUserInfo(userInfo: [PayloadKey.startWorkoutSession : [PayloadKey.Arg.start : start, PayloadKey.Arg.uuid : uuid.uuidString]])
        currentWatchWorkoutUuid = uuid
        syncCurrentWorkoutSnapshot()
    }
    
    func updateWatchWorkoutStart(start: Date, uuid: UUID) {
        os_log("Updating watch workout start date", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip updating watch workout start date", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
            os_log("Sending update watch workout start date for different uuid", log: .watch, type: .error)
        }
        sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionStart : [PayloadKey.Arg.start : start, PayloadKey.Arg.uuid : uuid.uuidString]])
        syncCurrentWorkoutSnapshot()
    }
    
    func updateWatchWorkoutEnd(end: Date?, uuid: UUID) {
        os_log("Updating watch workout end date", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip updating watch workout end date", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
            os_log("Sending update watch workout end date for different uuid", log: .watch, type: .error)
        }
        if let end = end {
            sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionEnd : [PayloadKey.Arg.end : end, PayloadKey.Arg.uuid : uuid.uuidString]])
        } else {
            sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionEnd : [PayloadKey.Arg.uuid : uuid.uuidString]])
        }
        syncCurrentWorkoutSnapshot()
    }
    
    func updateWatchWorkoutRestTimer(end: Date?, keepRunning: Bool?, uuid: UUID) {
        os_log("Updating watch workout rest timer end", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip updating watch workout rest timer end", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
            os_log("Sending update watch workout rest timer end for different uuid", log: .watch, type: .error)
        }
        
        var args: [String : Any] = [PayloadKey.Arg.uuid : uuid.uuidString]
        if let end = end {
            args[PayloadKey.Arg.end] = end
        }
        if let keepRunning = keepRunning {
            args[PayloadKey.Arg.keepRestTimerRunning] = keepRunning
        }
        
        sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionRestTimer : args])
        syncCurrentWorkoutSnapshot()
    }
    
    func updateWatchWorkoutSelectedSet(text: String?, uuid: UUID) {
        os_log("Updating watch workout selected set", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip updating watch workout selected set", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
            os_log("Sending update watch workout selected set for different uuid", log: .watch, type: .error)
        }
        if let text = text {
            sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionSelectedSet : [PayloadKey.Arg.text : text, PayloadKey.Arg.uuid : uuid.uuidString]])
        } else {
            sendUserInfo(userInfo: [PayloadKey.updateWorkoutSessionSelectedSet : [PayloadKey.Arg.uuid : uuid.uuidString]])
        }
        syncCurrentWorkoutSnapshot()
    }
    
    func finishWatchWorkout(start: Date, end: Date, title: String?, uuid: UUID) {
        os_log("Finishing watch workout", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip finishing watch workout", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
             os_log("Sending finish watch workout for different uuid", log: .watch, type: .error)
        }
        if let title = title {
            sendUserInfo(userInfo: [PayloadKey.endWorkoutSession : [PayloadKey.Arg.start : start, PayloadKey.Arg.end : end, PayloadKey.Arg.title: title, PayloadKey.Arg.uuid : uuid.uuidString]])
        } else {
            sendUserInfo(userInfo: [PayloadKey.endWorkoutSession : [PayloadKey.Arg.start : start, PayloadKey.Arg.end : end, PayloadKey.Arg.uuid : uuid.uuidString]])
        }
        currentWatchWorkoutUuid = nil
    }
    
    func discardWatchWorkout(uuid: UUID) {
        os_log("Discarding watch workout", log: .watch, type: .default)
        
        guard isActivated else {
            os_log("Session is not activated, skip discarding watch workout", log: .watch, type: .info)
            return
        }
        if currentWatchWorkoutUuid != uuid {
            os_log("Sending discard watch workout for different uuid", log: .watch, type: .error)
        }
        sendUserInfo(userInfo: [PayloadKey.discardWorkoutSession : [PayloadKey.Arg.uuid : uuid.uuidString]])
        currentWatchWorkoutUuid = nil
    }
    
    var currentWatchWorkoutUuid: UUID? {
        get {
            UserDefaults.standard.watchWorkoutUuid
        }
        set {
            UserDefaults.standard.watchWorkoutUuid = newValue
        }
    }
}

extension WatchConnectionManager {
    func prepareAndStartWatchWorkout(workout: Workout, startWatchCompanionErrorHandler: StartWatchCompanionErrorHandler? = nil) {
        prepareWatchWorkout(startWatchCompanionErrorHandler: startWatchCompanionErrorHandler) {
            self.startWatchWorkout(workout: workout)
        }
    }
    
    private func startWatchWorkout(workout: Workout) {
        guard let context = workout.managedObjectContext else {
            os_log("Workout context is nil", log: .watch, type: .error)
            self.ignorePreparedWatchWorkout()
            return
        }
        
        context.perform {
            guard workout.isCurrentWorkout else {
                os_log("Workout is no longer current workout", log: .watch, type: .error)
                self.ignorePreparedWatchWorkout()
                return
            }
            guard let start = workout.start else {
                os_log("Start not set on workout", log: .watch, type: .error)
                self.ignorePreparedWatchWorkout()
                assertionFailure("start should always be set at this point")
                return
            }
            guard let uuid = workout.uuid else {
                os_log("UUID not set on workout", log: .watch, type: .error)
                self.ignorePreparedWatchWorkout()
                assertionFailure("uuid is a required property")
                return
            }
            self.startWatchWorkout(start: start, uuid: uuid)
        }
    }
}

extension WatchConnectionManager {
    func updateAndObserveWatchWorkoutSelectedSet(workoutSet: WorkoutSet?, uuid: UUID) {
        selectedWatchSetUuid = workoutSet?.uuid
        if selectedSetChangePublisherCancellable == nil {
            selectedSetChangePublisherCancellable = selectedSetChangePublisher
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .drop { self.currentWatchWorkoutUuid != $0.1 }
                .map { ($0.0?.resultTitle(weightUnit: SettingsStore.shared.weightUnit), $0.1) }
                .removeDuplicates { $0.0 == $1.0 }
                .sink { self.updateWatchWorkoutSelectedSet(text: $0.0, uuid: $0.1) }
        }
        
        selectedSetChangePublisher.send((workoutSet, uuid))
        selectedSetCancellable = workoutSet?.objectWillChange
            .map { _ in (workoutSet, uuid) }
            .subscribe(selectedSetChangePublisher)
    }
}
