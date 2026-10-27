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

/// Isolated from connection status so sensor updates do not invalidate the
/// complete workout logger. Only the small metrics row observes this object.
final class WatchWorkoutMetricsStore: ObservableObject {
    @Published private(set) var latest: WatchWorkoutMetrics?

    func receive(_ metrics: WatchWorkoutMetrics, workoutID: UUID, now: Date = Date()) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard metrics.accepts(after: latest, for: workoutID, at: now) else { return }
        latest = metrics
    }

    func clear() {
        DispatchQueue.main.async { self.latest = nil }
    }
}

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
    let liveMetrics = WatchWorkoutMetricsStore()
    
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
    private var librarySaveObserver: AnyCancellable?
    private var exerciseLibraryObserver: AnyCancellable?
    private var pendingLibrarySync: DispatchWorkItem?
    private var libraryBuildGeneration: UInt64 = 0
    private var retainedTransferFiles = Set<URL>()

    private struct PendingPrepareRequest {
        let workoutID: UUID
        let preparedHandler: PrepareHandler
        let errorHandler: StartWatchCompanionErrorHandler?
    }
    private var pendingPrepareRequest: PendingPrepareRequest?

    private static let libraryTransferMarker = "ironWorkoutLibrary"
    private static let libraryFilePrefix = "iron-watch-library-"
    private static let snapshotTransferMarker = "ironWorkoutSnapshot"
    private static let snapshotFilePrefix = "iron-watch-snapshot-"
    private static let eventTransferMarker = "ironWorkoutEvent"
    private static let snapshotMessageLimit = 48 * 1024
    private static let deferredWorkoutsFilename = "watch-deferred-workouts-v1.json"

    private struct DeferredWatchWorkouts: Codable {
        var snapshots: [String: WatchWorkoutSnapshot] = [:]
    }

    private override init() {
        if let data = UserDefaults.standard.data(forKey: Self.eventLedgerDefaultsKey),
           let ledger = WatchWorkoutWire.decode(EventLedger.self, from: data) {
            eventLedger = ledger
        } else {
            eventLedger = EventLedger()
        }
        super.init()
        observeLibraryChanges()
    }

    private func observeLibraryChanges() {
        librarySaveObserver = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { notification in
                guard let savedContext = notification.object as? NSManagedObjectContext,
                      savedContext.persistentStoreCoordinator === WorkoutDataStorage.shared.persistentContainer.persistentStoreCoordinator else {
                    return false
                }
                return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
                    (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains {
                        $0 is Workout || $0 is WorkoutExercise || $0 is WorkoutSet ||
                        $0 is WorkoutPlan || $0 is WorkoutRoutine ||
                        $0 is WorkoutRoutineExercise || $0 is WorkoutRoutineSet
                    } == true
                }
            }
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleWorkoutLibrarySync() }

        exerciseLibraryObserver = ExerciseStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleWorkoutLibrarySync() }
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
        DispatchQueue.main.async {
            guard activationState == .activated else {
                if let pending = self.pendingPrepareRequest {
                    self.pendingPrepareRequest = nil
                    pending.errorHandler?(error ?? GenericError(description: "Activating Watch connectivity was unsuccessful"))
                }
                return
            }
            self.resumePendingPrepareRequest()
            if let snapshot = self.pendingSnapshot {
                self.sendWorkoutSnapshot(snapshot)
            } else {
                self.syncCurrentWorkoutSnapshot()
            }
            self.scheduleWorkoutLibrarySync(immediate: true)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        os_log("Session did become inactive", log: .watch, type: .debug)
        publishConnectionStatus()
        liveMetrics.clear()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        os_log("Session was deactivated", log: .watch, type: .debug)
        publishConnectionStatus()
        // connect to the new Apple Watch
        os_log("Reactivating session", log: .watch, type: .debug)
        activateSession()
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        os_log("Received Watch application context", log: .watch, type: .debug)
        
        receive(message: applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        os_log("Received Watch user info", log: .watch, type: .debug)
        
        receive(message: userInfo)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        os_log("Received Watch message", log: .watch, type: .debug)
        
        receive(message: message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        os_log("Received Watch message with reply", log: .watch, type: .debug)
        
        receive(message: message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[Self.eventTransferMarker] as? Bool == true else { return }
        do {
            let data = try Data(contentsOf: file.fileURL)
            guard let event = WatchWorkoutWire.decode(WatchWorkoutEvent.self, from: data) else {
                os_log("Could not decode transferred Watch workout event", log: .watch, type: .error)
                return
            }
            handleWorkoutEvent(event, replyHandler: nil)
        } catch {
            os_log("Could not read transferred Watch workout event: %@", log: .watch, type: .error,
                   error.localizedDescription)
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        os_log("Session reachability did change isReachable=%@", log: .watch, type: .debug, String(describing: session.isReachable))
        publishConnectionStatus()
        guard session.isReachable else { return }
        DispatchQueue.main.async {
            self.syncCurrentWorkoutSnapshot()
            self.scheduleWorkoutLibrarySync(immediate: true)
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
        if session.isPaired && session.isWatchAppInstalled {
            scheduleWorkoutLibrarySync(immediate: true)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let file = fileTransfer.file
        let isLibrary = file.metadata?[Self.libraryTransferMarker] as? Bool == true
        let isSnapshot = file.metadata?[Self.snapshotTransferMarker] as? Bool == true
        guard isLibrary || isSnapshot else { return }
        DispatchQueue.main.async {
            if self.retainedTransferFiles.remove(file.fileURL) != nil {
                try? FileManager.default.removeItem(at: file.fileURL)
            }
            if let error {
                os_log("Watch workout file transfer failed: %@", log: .watch, type: .error,
                       error.localizedDescription)
            }
        }
    }
}

extension WatchConnectionManager {
    private func receive(message: [String : Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        if message[PayloadKey.requestWorkoutLibrary] as? Bool == true {
            scheduleWorkoutLibrarySync(immediate: true)
            replyHandler?([:])
        } else if message[PayloadKey.requestWorkoutSnapshot] as? Bool == true {
            syncCurrentWorkoutSnapshot()
            replyHandler?([:])
        } else if let data = message[PayloadKey.workoutMetrics] as? Data,
           let metrics = WatchWorkoutWire.decode(WatchWorkoutMetrics.self, from: data) {
            DispatchQueue.main.async {
                let context = WorkoutDataStorage.shared.persistentContainer.viewContext
                guard let workout = try? context.fetch(Workout.currentWorkoutFetchRequest).first,
                      workout.isCurrentWorkout, !workout.isImported,
                      workout.uuid == metrics.workoutID else { return }
                self.liveMetrics.receive(metrics, workoutID: metrics.workoutID)
            }
            replyHandler?([:])
        } else if let eventData = message[PayloadKey.workoutEvent] as? Data,
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

            do {
                if event.kind == .savedWorkoutUpserted || event.kind == .savedWorkoutDeleted {
                    try Self.commitWatchEventMutation(
                        in: context,
                        save: { if context.hasChanges { try context.save() } },
                        mutation: { try self.applySavedWorkoutEvent(event, in: context) },
                        didPersist: {
                            self.recordProcessed(event, fieldKey: fieldKey)
                            self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                            self.scheduleWorkoutLibrarySync()
                        }
                    )
                    return
                }

                guard let workout = try self.resolveWorkout(for: event, in: context) else {
                    if event.kind == .workoutDiscarded {
                        try self.removeDeferredWorkout(event.workoutID)
                        self.recordProcessed(event, fieldKey: fieldKey)
                        self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                        return
                    }
                    if let snapshot = event.snapshot, !snapshot.isFinishedRecord,
                       try context.fetch(Workout.currentWorkoutFetchRequest).contains(where: {
                           $0.uuid != event.workoutID
                       }) {
                        try self.persistDeferredWorkout(snapshot)
                        self.recordProcessed(event, fieldKey: fieldKey)
                        self.acknowledge(eventID: event.id, replyHandler: replyHandler)
                        return
                    }
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
                        if event.kind == .workoutFinished || event.kind == .workoutDiscarded {
                            try? self.removeDeferredWorkout(event.workoutID)
                        }
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

    func resolveWorkout(for event: WatchWorkoutEvent,
                        in context: NSManagedObjectContext) throws -> Workout? {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "uuid == %@", event.workoutID as NSUUID)
        if let workout = try context.fetch(request).first { return workout }
        guard let snapshot = event.snapshot,
              event.kind == .workoutCreated || event.kind == .workoutFinished ||
                (event.kind == .workoutFailed && snapshot.isFinishedRecord) else { return nil }

        let hasPhoneCurrent = try context.fetch(Workout.currentWorkoutFetchRequest).contains {
            $0.uuid != event.workoutID
        }
        if !snapshot.isFinishedRecord && hasPhoneCurrent { return nil }
        let workout = Workout.create(context: context)
        workout.uuid = event.workoutID
        workout.importSource = nil
        workout.isCurrentWorkout = !snapshot.isFinishedRecord
        workout.healthExportState = "watch"
        applyComplete(snapshot, to: workout, in: context)
        if workout.isCurrentWorkout { currentWatchWorkoutUuid = workout.uuid }
        return workout
    }

    private var deferredWorkoutsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Iron", isDirectory: true)
            .appendingPathComponent(Self.deferredWorkoutsFilename, isDirectory: false)
    }

    private func readDeferredWorkouts() throws -> DeferredWatchWorkouts {
        guard FileManager.default.fileExists(atPath: deferredWorkoutsURL.path) else {
            return DeferredWatchWorkouts()
        }
        let data = try Data(contentsOf: deferredWorkoutsURL)
        guard let decoded = WatchWorkoutWire.decode(DeferredWatchWorkouts.self, from: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return decoded
    }

    private func writeDeferredWorkouts(_ store: DeferredWatchWorkouts) throws {
        guard let data = WatchWorkoutWire.encode(store) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(
            at: deferredWorkoutsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: deferredWorkoutsURL, options: .atomic)
    }

    private func persistDeferredWorkout(_ snapshot: WatchWorkoutSnapshot) throws {
        var store = try readDeferredWorkouts()
        let key = snapshot.workoutID.uuidString
        if let existing = store.snapshots[key],
           existing.revision > snapshot.revision ||
            (existing.revision == snapshot.revision && existing.updatedAt >= snapshot.updatedAt) {
            return
        }
        var compact = snapshot
        compact.library = nil
        compact.exercises = compact.exercises.map { exercise in
            var exercise = exercise
            exercise.imageData = nil
            return exercise
        }
        store.snapshots[key] = compact
        try writeDeferredWorkouts(store)
    }

    private func removeDeferredWorkout(_ workoutID: UUID) throws {
        var store = try readDeferredWorkouts()
        guard store.snapshots.removeValue(forKey: workoutID.uuidString) != nil else { return }
        try writeDeferredWorkouts(store)
    }

    func applyWatchEventModelMutation(
        _ event: WatchWorkoutEvent,
        to workout: Workout,
        in context: NSManagedObjectContext,
        healthManager: HealthManager = .shared
    ) throws -> DeferredWatchEventEffects {
        switch event.kind {
        case .setUpdated:
            guard acceptsWatchEdits(workout),
                  let set = workoutSet(with: event.setID, in: workout) else { return .none }
            apply(weight: event.weight, reps: event.reps, rpe: event.rpe,
                  unit: event.weightUnit, to: set)
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setCompletionChanged:
            guard acceptsWatchEdits(workout),
                  let set = workoutSet(with: event.setID, in: workout),
                  let completed = event.completed else { return .none }
            set.isCompleted = completed
            set.completedAt = completed ? (set.completedAt ?? event.createdAt) : nil
            guard workout.isCurrentWorkout else { return .none }
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
                RestTimerStore.shared.applyWatchUpdate(
                    end: event.restTimerEnd,
                    pausedRemaining: event.snapshot?.pausedRestRemaining)
                WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
            }

        case .workoutFinished:
            guard workout.isCurrentWorkout || isWatchOwned(workout) else { return .none }
            let wasCurrent = workout.isCurrentWorkout
            if event.fieldChanges != nil {
                applyModernWatchCompletion(event, to: workout, state: "watch")
            } else {
                if let snapshot = event.snapshot, isWatchOwned(workout) {
                    applyComplete(snapshot, to: workout, in: context)
                }
                applyWatchCompletion(event, to: workout, state: "watch")
            }
            return DeferredWatchEventEffects { [weak self] in
                if wasCurrent {
                    self?.currentWatchWorkoutUuid = nil
                    RestTimerStore.shared.cancel()
                    WorkoutLiveActivityManager.shared.end(for: workout, completed: true)
                }
            }

        case .workoutDiscarded:
            guard acceptsWatchEdits(workout) else { return .none }
            let wasCurrent = workout.isCurrentWorkout
            let activityEndSnapshot = wasCurrent ? WorkoutLiveActivityManager.shared.endSnapshot(for: workout) : nil
            let workoutID = workout.uuid
            context.delete(workout)
            return DeferredWatchEventEffects { [weak self] in
                if wasCurrent {
                    self?.currentWatchWorkoutUuid = nil
                    RestTimerStore.shared.cancel()
                    if let activityEndSnapshot {
                        WorkoutLiveActivityManager.shared.end(using: activityEndSnapshot, completed: false)
                    }
                }
                self?.deleteStartWorkoutInteractionDonation(workoutID: workoutID)
            }

        case .workoutFailed:
            // The existing failure event can arrive before the finish event. Its
            // completed snapshot must survive that lifecycle sequence ordering.
            let wasCurrent = workout.isCurrentWorkout
            if event.endDate != nil || event.snapshot?.isFinishedRecord == true {
                if workout.isCurrentWorkout || isWatchOwned(workout) {
                    applyWatchCompletion(event, to: workout, state: "pending", includeEventTitle: false)
                } else if workout.healthExportEligibility == .eligible,
                          workout.healthExportState == "watch" {
                    workout.healthExportState = "pending"
                }
            }
            let shouldClearWatchWorkout = workout.isCurrentWorkout || workout.healthExportState == "pending"
            return DeferredWatchEventEffects { [weak self] in
                if shouldClearWatchWorkout { self?.currentWatchWorkoutUuid = nil }
                if wasCurrent {
                    RestTimerStore.shared.cancel()
                    WorkoutLiveActivityManager.shared.end(for: workout, completed: true)
                }
                if workout.healthExportEligibility == .eligible, workout.healthExportState == "pending" {
                    healthManager.saveWorkout(workout: workout, exerciseStore: .shared)
                }
                os_log("Watch reported a failed workout session", log: .watch, type: .error)
            }

        case .setAdded:
            guard acceptsWatchEdits(workout),
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
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects { [weak self] in
                self?.selectedWatchSetUuid = selectedSetID
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setDeleted:
            guard acceptsWatchEdits(workout),
                  let set = workoutSet(with: event.setID, in: workout),
                  let workoutExercise = set.workoutExercise,
                  (workoutExercise.workoutSets?.count ?? 0) > 1 else { return .none }
            let replacementSelectedSetID: UUID? = selectedWatchSetUuid == set.uuid
                ? (workoutExercise.workoutSets?.array as? [WorkoutSet])?
                    .first { $0.uuid != set.uuid }?.uuid
                : selectedWatchSetUuid
            context.delete(set)
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects { [weak self] in
                self?.selectedWatchSetUuid = replacementSelectedSetID
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .setTagChanged:
            guard acceptsWatchEdits(workout),
                  let set = workoutSet(with: event.setID, in: workout) else { return .none }
            set.tagValue = event.tag.flatMap { WorkoutSetTag(rawValue: $0) }
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .exerciseAdded:
            return addExercise(from: event, to: workout, in: context)

        case .exerciseReplaced:
            guard acceptsWatchEdits(workout),
                  let workoutExercise = workoutExercise(with: event.exerciseID, in: workout),
                  let catalogID = event.catalogExerciseUuid,
                  ExerciseStore.find(in: ExerciseStore.shared.exercises, with: catalogID) != nil else { return .none }
            workoutExercise.exerciseUuid = catalogID
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .exerciseDeleted:
            guard acceptsWatchEdits(workout),
                  let workoutExercise = workoutExercise(with: event.exerciseID, in: workout),
                  orderedExercises(in: workout).count > 1 else { return .none }
            context.delete(workoutExercise)
            guard workout.isCurrentWorkout else { return .none }
            return DeferredWatchEventEffects {
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }

        case .workoutCreated:
            guard acceptsWatchEdits(workout) else { return .none }
            if let snapshot = event.snapshot {
                if isWatchOwned(workout) {
                    applyComplete(snapshot, to: workout, in: context)
                } else {
                    applyNonDestructiveStructure(snapshot, to: workout, in: context)
                }
            }
            return workout.isCurrentWorkout
                ? DeferredWatchEventEffects { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
                : .none

        case .workoutStructureUpdated:
            guard acceptsWatchEdits(workout), let snapshot = event.snapshot else { return .none }
            // Only remove IDs explicitly deleted on the Watch. Missing IDs alone
            // can also mean the phone added something while the Watch was offline.
            let removedExercises = Set(event.removedExerciseIDs ?? [])
            let removedSets = Set(event.removedSetIDs ?? [])
            for exercise in orderedExercises(in: workout) {
                if let id = exercise.uuid, removedExercises.contains(id) { context.delete(exercise) }
                else {
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] {
                        if let id = set.uuid, removedSets.contains(id) { context.delete(set) }
                    }
                }
            }
            context.processPendingChanges()
            if let fieldChanges = event.fieldChanges {
                applyMaskedStructure(snapshot, changes: fieldChanges, to: workout, in: context)
            } else if isWatchOwned(workout) {
                applyComplete(snapshot, to: workout, in: context)
            } else {
                applyNonDestructiveStructure(snapshot, to: workout, in: context)
            }
            return workout.isCurrentWorkout
                ? DeferredWatchEventEffects { WorkoutLiveActivityManager.shared.startOrUpdate(for: workout) }
                : .none

        case .savedWorkoutUpserted, .savedWorkoutDeleted:
            return .none // Handled before Workout lookup because workoutID is a routine ID.
        }
    }

    private func isWatchOwned(_ workout: Workout) -> Bool {
        workout.healthExportState == "watch" && workout.importSource == nil
    }

    private func acceptsWatchEdits(_ workout: Workout) -> Bool {
        workout.isCurrentWorkout || (isWatchOwned(workout) && workout.end == nil)
    }

    private func addExercise(from event: WatchWorkoutEvent,
                             to workout: Workout,
                             in context: NSManagedObjectContext) -> DeferredWatchEventEffects {
        guard acceptsWatchEdits(workout),
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
        guard workout.isCurrentWorkout else { return .none }
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
        workout.comment = snapshot.comment
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
                apply(watchSet, unit: snapshot.weightUnit, updatedAt: snapshot.updatedAt, to: set)
            }
            exercise.restTimerDurationValue = watchExercise.restTimerDuration
            exercise.supersetUuid = watchExercise.supersetID
            exercise.comment = watchExercise.comment
        }
    }

    /// Replaces a Watch-owned projection from its complete durable snapshot.
    /// Phone-owned records use the non-destructive merge below so an unrelated
    /// phone edit cannot be erased by a delayed finish packet.
    func applyComplete(_ snapshot: WatchWorkoutSnapshot, to workout: Workout,
                       in context: NSManagedObjectContext) {
        workout.title = snapshot.title
        workout.comment = snapshot.comment
        workout.start = snapshot.startDate
        workout.end = snapshot.endDate
        workout.sessionEffortValue = snapshot.sessionEffort
        if let routineID = snapshot.sourceSavedWorkoutID {
            let request: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "uuid == %@", routineID as NSUUID)
            workout.workoutRoutine = try? context.fetch(request).first
        }

        let existing = orderedExercises(in: workout)
        let byID = Dictionary(uniqueKeysWithValues: existing.compactMap { exercise in
            exercise.uuid.map { ($0, exercise) }
        })
        var ordered: [WorkoutExercise] = []
        for watchExercise in snapshot.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise = byID[watchExercise.id] ?? WorkoutExercise.create(context: context)
            exercise.uuid = watchExercise.id
            apply(watchExercise, unit: snapshot.weightUnit, updatedAt: snapshot.updatedAt,
                  to: exercise, in: context, replaceSets: true)
            ordered.append(exercise)
        }
        let retainedIDs = Set(snapshot.exercises.map(\.id))
        for exercise in existing where exercise.uuid.map({ !retainedIDs.contains($0) }) ?? true {
            context.delete(exercise)
        }
        workout.workoutExercises = NSOrderedSet(array: ordered)
    }

    private func applyNonDestructiveStructure(_ snapshot: WatchWorkoutSnapshot, to workout: Workout,
                                               in context: NSManagedObjectContext) {
        apply(snapshot, to: workout)
        let existing = orderedExercises(in: workout)
        var byID = Dictionary(uniqueKeysWithValues: existing.compactMap { exercise in
            exercise.uuid.map { ($0, exercise) }
        })
        var ordered: [WorkoutExercise] = []
        for watchExercise in snapshot.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise = byID.removeValue(forKey: watchExercise.id) ?? WorkoutExercise.create(context: context)
            exercise.uuid = watchExercise.id
            apply(watchExercise, unit: snapshot.weightUnit, updatedAt: snapshot.updatedAt,
                  to: exercise, in: context, replaceSets: false)
            ordered.append(exercise)
        }
        ordered.append(contentsOf: existing.filter { byID[$0.uuid ?? UUID()] != nil })
        workout.workoutExercises = NSOrderedSet(array: ordered)
    }

    private func applyMaskedStructure(_ snapshot: WatchWorkoutSnapshot,
                                      changes: WatchWorkoutFieldChanges,
                                      to workout: Workout,
                                      in context: NSManagedObjectContext) {
        let workoutFields = Set(changes.workout)
        if workoutFields.contains("title") { workout.title = snapshot.title }
        if workoutFields.contains("startDate") { workout.start = snapshot.startDate }
        if workoutFields.contains("endDate") { workout.end = snapshot.endDate }
        if workoutFields.contains("comment") { workout.comment = snapshot.comment }
        if workoutFields.contains("sourceSavedWorkoutID") {
            if let routineID = snapshot.sourceSavedWorkoutID {
                let request: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "uuid == %@", routineID as NSUUID)
                workout.workoutRoutine = try? context.fetch(request).first
            } else {
                workout.workoutRoutine = nil
            }
        }

        let existing = orderedExercises(in: workout).filter { !$0.isDeleted }
        var byID = Dictionary(uniqueKeysWithValues: existing.compactMap { exercise in
            exercise.uuid.map { ($0, exercise) }
        })
        var snapshotOrder: [WorkoutExercise] = []
        var newExercises: [WorkoutExercise] = []

        for watchExercise in snapshot.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise: WorkoutExercise
            if let current = byID[watchExercise.id] {
                exercise = current
                applyMaskedExercise(watchExercise, changes: changes, to: exercise,
                                    unit: snapshot.weightUnit, updatedAt: snapshot.updatedAt,
                                    in: context)
            } else {
                guard changes.addedExerciseIDs?.contains(watchExercise.id) == true else {
                    continue
                }
                exercise = WorkoutExercise.create(context: context)
                exercise.uuid = watchExercise.id
                apply(watchExercise, unit: snapshot.weightUnit, updatedAt: snapshot.updatedAt,
                      to: exercise, in: context, replaceSets: true)
                byID[watchExercise.id] = exercise
                newExercises.append(exercise)
            }
            snapshotOrder.append(exercise)
        }

        if changes.exerciseOrder {
            let snapshotIDs = Set(snapshot.exercises.map(\.id))
            let phoneOnly = existing.filter { exercise in
                exercise.uuid.map { !snapshotIDs.contains($0) } ?? true
            }
            workout.workoutExercises = NSOrderedSet(array: snapshotOrder + phoneOnly)
        } else if !newExercises.isEmpty {
            workout.workoutExercises = NSOrderedSet(array: existing + newExercises)
        }
    }

    private func applyMaskedExercise(_ watchExercise: WatchWorkoutExercise,
                                     changes: WatchWorkoutFieldChanges,
                                     to exercise: WorkoutExercise,
                                     unit: WatchWorkoutWeightUnit?,
                                     updatedAt: Date,
                                     in context: NSManagedObjectContext) {
        let fields = Set(changes.exercises[watchExercise.id.uuidString] ?? [])
        if fields.contains("exerciseUuid") { exercise.exerciseUuid = watchExercise.exerciseUuid }
        if fields.contains("restTimerDuration") {
            exercise.restTimerDurationValue = watchExercise.restTimerDuration
        }
        if fields.contains("supersetID") { exercise.supersetUuid = watchExercise.supersetID }
        if fields.contains("comment") { exercise.comment = watchExercise.comment }

        let existing = (exercise.workoutSets?.array as? [WorkoutSet] ?? []).filter { !$0.isDeleted }
        var byID = Dictionary(uniqueKeysWithValues: existing.compactMap { set in
            set.uuid.map { ($0, set) }
        })
        var snapshotOrder: [WorkoutSet] = []
        var newSets: [WorkoutSet] = []
        for watchSet in watchExercise.sets.sorted(by: { $0.order < $1.order }) {
            let set: WorkoutSet
            if let current = byID[watchSet.id] {
                set = current
                applyMaskedSet(watchSet, fields: Set(changes.sets[watchSet.id.uuidString] ?? []),
                               unit: unit, updatedAt: updatedAt, to: set)
            } else {
                guard changes.addedSetIDs?.contains(watchSet.id) == true else {
                    continue
                }
                set = WorkoutSet.create(context: context)
                set.uuid = watchSet.id
                apply(watchSet, unit: unit, updatedAt: updatedAt, to: set)
                byID[watchSet.id] = set
                newSets.append(set)
            }
            snapshotOrder.append(set)
        }

        if changes.setOrder.contains(watchExercise.id) {
            let snapshotIDs = Set(watchExercise.sets.map(\.id))
            let phoneOnly = existing.filter { set in
                set.uuid.map { !snapshotIDs.contains($0) } ?? true
            }
            exercise.workoutSets = NSOrderedSet(array: snapshotOrder + phoneOnly)
        } else if !newSets.isEmpty {
            exercise.workoutSets = NSOrderedSet(array: existing + newSets)
        }
    }

    private func applyMaskedSet(_ watchSet: WatchWorkoutSet, fields: Set<String>,
                                unit: WatchWorkoutWeightUnit?, updatedAt: Date,
                                to set: WorkoutSet) {
        if fields.contains("weight") {
            set.weight = watchSet.weight.map { NSNumber(value: canonicalWeight($0, unit: unit)) }
        }
        if fields.contains("reps") {
            set.repetitions = watchSet.reps.map {
                NSNumber(value: min(max($0, 0), Int(WorkoutSet.MAX_REPETITIONS)))
            }
        }
        if fields.contains("rpe") { set.rpeValue = watchSet.rpe }
        if fields.contains("completed") {
            set.isCompleted = watchSet.completed
            set.completedAt = watchSet.completed ? (set.completedAt ?? updatedAt) : nil
        }
        if fields.contains("tag") {
            set.tagValue = watchSet.tag.flatMap { WorkoutSetTag(rawValue: $0) }
        }
        if fields.contains("duration") { set.durationValue = watchSet.duration }
        if fields.contains("distance") { set.distanceValue = watchSet.distance }
        if fields.contains("comment") { set.comment = watchSet.comment }
        if fields.contains("minTargetReps") {
            set.minTargetRepetitionsValue = watchSet.minTargetReps.map { Int16(clamping: $0) }
        }
        if fields.contains("maxTargetReps") {
            set.maxTargetRepetitionsValue = watchSet.maxTargetReps.map { Int16(clamping: $0) }
        }
    }

    private func apply(_ watchExercise: WatchWorkoutExercise, unit: WatchWorkoutWeightUnit?,
                       updatedAt: Date, to exercise: WorkoutExercise,
                       in context: NSManagedObjectContext, replaceSets: Bool) {
        exercise.exerciseUuid = watchExercise.exerciseUuid
        exercise.restTimerDurationValue = watchExercise.restTimerDuration
        exercise.supersetUuid = watchExercise.supersetID
        exercise.comment = watchExercise.comment
        let existing = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.compactMap { set in
            set.uuid.map { ($0, set) }
        })
        var ordered: [WorkoutSet] = []
        for watchSet in watchExercise.sets.sorted(by: { $0.order < $1.order }) {
            let set = byID.removeValue(forKey: watchSet.id) ?? WorkoutSet.create(context: context)
            set.uuid = watchSet.id
            apply(watchSet, unit: unit, updatedAt: updatedAt, to: set)
            ordered.append(set)
        }
        if replaceSets {
            byID.values.forEach(context.delete)
        } else {
            ordered.append(contentsOf: existing.filter { byID[$0.uuid ?? UUID()] != nil })
        }
        exercise.workoutSets = NSOrderedSet(array: ordered)
    }

    private func apply(_ watchSet: WatchWorkoutSet, unit: WatchWorkoutWeightUnit?,
                       updatedAt: Date, to set: WorkoutSet) {
        apply(weight: watchSet.weight, reps: watchSet.reps, rpe: watchSet.rpe, unit: unit, to: set)
        set.isCompleted = watchSet.completed
        set.completedAt = watchSet.completed ? (set.completedAt ?? updatedAt) : nil
        set.tagValue = watchSet.tag.flatMap { WorkoutSetTag(rawValue: $0) }
        set.durationValue = watchSet.duration
        set.distanceValue = watchSet.distance
        set.comment = watchSet.comment
        set.minTargetRepetitionsValue = watchSet.minTargetReps.map { Int16(clamping: $0) }
        set.maxTargetRepetitionsValue = watchSet.maxTargetReps.map { Int16(clamping: $0) }
    }

    func applySavedWorkoutEvent(_ event: WatchWorkoutEvent,
                                in context: NSManagedObjectContext) throws -> DeferredWatchEventEffects {
        let request: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "uuid == %@", event.workoutID as NSUUID)
        let existing = try context.fetch(request).first
        if event.kind == .savedWorkoutDeleted {
            if let existing { context.delete(existing) }
            return .none
        }
        guard let saved = event.savedWorkout, saved.id == event.workoutID else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let routine = existing ?? WorkoutRoutine.create(context: context)
        routine.uuid = saved.id
        routine.title = saved.title
        routine.comment = saved.comment
        if routine.workoutPlan == nil {
            let planRequest: NSFetchRequest<WorkoutPlan> = WorkoutPlan.fetchRequest()
            planRequest.fetchLimit = 1
            let plan = try context.fetch(planRequest).first ?? WorkoutPlan.create(context: context)
            plan.addToWorkoutRoutines(routine)
        }
        (routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise])?.forEach(context.delete)
        let exercises = saved.exercises.sorted(by: { $0.order < $1.order }).map { watchExercise -> WorkoutRoutineExercise in
            let exercise = WorkoutRoutineExercise.create(context: context)
            exercise.uuid = watchExercise.id
            exercise.exerciseUuid = watchExercise.exerciseUuid
            exercise.comment = watchExercise.comment
            exercise.restTimerDurationValue = watchExercise.restTimerDuration
            exercise.supersetUuid = watchExercise.supersetID
            let sets = watchExercise.sets.sorted(by: { $0.order < $1.order }).map { watchSet -> WorkoutRoutineSet in
                let set = WorkoutRoutineSet.create(context: context)
                set.uuid = watchSet.id
                set.weightValue = watchSet.weight.map { canonicalWeight($0, unit: saved.weightUnit) }
                set.minRepetitionsValue = (watchSet.minTargetReps ?? watchSet.reps).map { Int16(clamping: $0) }
                set.maxRepetitionsValue = (watchSet.maxTargetReps ?? watchSet.reps).map { Int16(clamping: $0) }
                set.tagValue = watchSet.tag.flatMap { WorkoutSetTag(rawValue: $0) }
                set.comment = watchSet.comment
                set.durationValue = watchSet.duration
                return set
            }
            exercise.workoutRoutineSets = NSOrderedSet(array: sets)
            return exercise
        }
        routine.workoutRoutineExercises = NSOrderedSet(array: exercises)
        return .none
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

    private func applyWatchCompletion(_ event: WatchWorkoutEvent, to workout: Workout,
                                      state: String, includeEventTitle: Bool = true) {
        if let snapshot = event.snapshot { apply(snapshot, to: workout) }
        let start = event.startDate ?? event.snapshot?.startDate ?? workout.safeStart
        workout.start = start
        workout.end = max(event.endDate ?? event.snapshot?.endDate ?? Date(), start)
        if let title = (includeEventTitle ? event.title : nil) ?? event.snapshot?.title {
            workout.title = title
        }
        if let effort = event.sessionEffort ?? event.snapshot?.sessionEffort {
            workout.sessionEffortValue = effort
        }
        workout.deleteExercisesWhereAllSetsAreUncompleted()
        workout.deleteUncompletedSets()
        workout.isCurrentWorkout = false
        workout.healthExportState = workout.healthExportEligibility == .eligible ? state : nil
    }

    private func applyModernWatchCompletion(_ event: WatchWorkoutEvent, to workout: Workout,
                                            state: String) {
        let start = workout.safeStart
        workout.end = max(event.endDate ?? event.snapshot?.endDate ?? Date(), start)
        if let effort = event.sessionEffort ?? event.snapshot?.sessionEffort {
            workout.sessionEffortValue = effort
        }
        workout.isCurrentWorkout = false
        workout.healthExportState = workout.healthExportEligibility == .eligible ? state : nil
    }

    private func sequenceFieldKey(for event: WatchWorkoutEvent) -> String {
        switch event.kind {
        case .setUpdated:
            return "\(event.workoutID.uuidString):\(event.setID?.uuidString ?? "unknown"):values"
        case .setCompletionChanged:
            return "\(event.workoutID.uuidString):\(event.setID?.uuidString ?? "unknown"):completion"
        case .restTimerUpdated:
            return "\(event.workoutID.uuidString):timer"
        case .workoutFinished, .workoutDiscarded:
            return "\(event.workoutID.uuidString):lifecycle"
        case .workoutFailed:
            return "\(event.workoutID.uuidString):healthFailure"
        case .workoutCreated, .workoutStructureUpdated:
            return "\(event.workoutID.uuidString):structure"
        case .savedWorkoutUpserted, .savedWorkoutDeleted:
            return "\(event.workoutID.uuidString):savedWorkout"
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
        if (try? readDeferredWorkouts().snapshots.values.contains {
            $0.endDate == nil && $0.workoutID != currentWatchWorkoutUuid
        }) == true {
            // The Watch owns a different active projection that was deferred
            // to preserve the phone's workout. Never overwrite it with the
            // unrelated phone current-workout application context.
            return
        }
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        context.perform {
            do {
                guard let workout = try context.fetch(Workout.currentWorkoutFetchRequest).first,
                      !workout.isImported,
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
                    tag: set.tagValue?.rawValue,
                    duration: set.durationValue,
                    distance: set.distanceValue,
                    comment: set.comment,
                    minTargetReps: set.minTargetRepetitionsValue.map(Int.init),
                    maxTargetReps: set.maxTargetRepetitionsValue.map(Int.init))
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
                                            : nil,
                                        supersetID: workoutExercise.supersetUuid,
                                        comment: workoutExercise.comment)
        }

        let allSets = watchExercises.flatMap(\.sets)
        let focusedSetID = WorkoutSetFocus.next(in: workout).flatMap { focus in
            orderedExercises(in: workout)
                .flatMap { $0.workoutSets?.array as? [WorkoutSet] ?? [] }
                .first { $0.objectID == focus.setID }?.uuid
        }
        let selectedID = selectedWatchSetUuid.flatMap { selected in
            allSets.contains(where: { $0.id == selected }) ? selected : nil
        } ?? focusedSetID ?? allSets.first(where: { !$0.completed })?.id ?? allSets.first?.id
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
            library: nil,
            revision: lastSnapshotRevision,
            updatedAt: now,
            comment: workout.comment,
            sourceSavedWorkoutID: workout.workoutRoutine?.uuid,
            pausedRestRemaining: RestTimerStore.shared.isPaused
                ? RestTimerStore.shared.restTimerRemainingTime
                : nil,
            isFinished: false)
    }

    func scheduleWorkoutLibrarySync(immediate: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleWorkoutLibrarySync(immediate: immediate)
            }
            return
        }
        pendingLibrarySync?.cancel()
        libraryBuildGeneration &+= 1
        let generation = libraryBuildGeneration
        let work = DispatchWorkItem { [weak self] in
            self?.buildAndTransferWorkoutLibrary(generation: generation)
        }
        pendingLibrarySync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.75), execute: work)
    }

    private func buildAndTransferWorkoutLibrary(generation: UInt64) {
        guard SettingsStore.shared.watchCompanion, isActivated else { return }
        let appUnit = SettingsStore.shared.weightUnit
        let wireUnit: WatchWorkoutWeightUnit = appUnit == .imperial ? .pound : .kilogram
        let exerciseCatalog = ExerciseStore.shared.exercises
        let picks = ExerciseStore.shared.shownExercises.map {
            WatchExercisePick(id: $0.uuid, name: $0.title, muscle: $0.muscleGroup,
                              imageURL: $0.imageURL?.absoluteString)
        }
        let context = WorkoutDataStorage.shared.persistentContainer.newBackgroundContext()
        context.undoManager = nil
        context.perform { [weak self] in
            guard let self else { return }
            do {
                let routineRequest: NSFetchRequest<WorkoutRoutine> = WorkoutRoutine.fetchRequest()
                let routines = try context.fetch(routineRequest)
                var saved: [WatchSavedWorkout] = []
                saved.reserveCapacity(routines.count)
                for routine in routines {
                    saved.append(self.makeSavedWorkout(routine, weightUnit: wireUnit,
                                                       appUnit: appUnit, catalog: exerciseCatalog))
                }
                let historyRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                historyRequest.predicate = NSPredicate(format: "isCurrentWorkout == NO AND end != nil")
                historyRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
                let completedWorkouts = try context.fetch(historyRequest)
                var history: [WatchWorkoutSnapshot] = []
                history.reserveCapacity(completedWorkouts.count)
                for workout in completedWorkouts {
                    history.append(self.makeLibrarySnapshot(workout, weightUnit: wireUnit,
                                                            appUnit: appUnit, catalog: exerciseCatalog))
                }
                var library = WatchWorkoutLibrary(generatedAt: Date(), exercises: picks,
                                                  savedWorkouts: saved, history: history,
                                                  weightUnit: wireUnit)
                library.revision = Int64(Date().timeIntervalSince1970 * 1_000_000)
                guard let data = WatchWorkoutWire.encode(library) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.libraryBuildGeneration else { return }
                    self.transferWorkoutLibrary(data)
                }
            } catch {
                os_log("Could not build Watch workout library: %@", log: .watch, type: .error,
                       error.localizedDescription)
            }
        }
    }

    private func makeSavedWorkout(_ routine: WorkoutRoutine, weightUnit: WatchWorkoutWeightUnit,
                                  appUnit: WeightUnit, catalog: [Exercise]) -> WatchSavedWorkout {
        let sourceExercises = routine.workoutRoutineExercises?.array as? [WorkoutRoutineExercise] ?? []
        var exercises: [WatchWorkoutExercise] = []
        exercises.reserveCapacity(sourceExercises.count)
        for (index, source) in sourceExercises.enumerated() {
            let exercise = source.exercise(in: catalog)
            let sourceSets = source.workoutRoutineSets?.array as? [WorkoutRoutineSet] ?? []
            var sets: [WatchWorkoutSet] = []
            sets.reserveCapacity(sourceSets.count)
            for (setIndex, sourceSet) in sourceSets.enumerated() {
                let weight = sourceSet.weightValue.map {
                    WeightUnit.convert(weight: $0, from: .metric, to: appUnit)
                }
                sets.append(WatchWorkoutSet(
                    id: sourceSet.uuid ?? UUID(), order: setIndex + 1,
                    weight: weight, reps: nil, rpe: nil, completed: false,
                    tag: sourceSet.tagValue?.rawValue,
                    duration: sourceSet.durationValue, comment: sourceSet.comment,
                    minTargetReps: sourceSet.minRepetitionsValue.map(Int.init),
                    maxTargetReps: sourceSet.maxRepetitionsValue.map(Int.init)))
            }
            exercises.append(WatchWorkoutExercise(
                id: source.uuid ?? UUID(), order: index + 1,
                name: exercise?.title ?? "Exercise", sets: sets,
                restTimerDuration: source.restTimerDurationValue,
                muscleGroup: exercise?.muscleGroup, exerciseUuid: source.exerciseUuid,
                imageURL: exercise?.imageURL?.absoluteString,
                supersetID: source.supersetUuid, comment: source.comment))
        }
        return WatchSavedWorkout(id: routine.uuid ?? UUID(), title: routine.displayTitle,
                                 exercises: exercises, weightUnit: weightUnit,
                                 comment: routine.comment, updatedAt: Date())
    }

    private func makeLibrarySnapshot(_ workout: Workout, weightUnit: WatchWorkoutWeightUnit,
                                     appUnit: WeightUnit, catalog: [Exercise]) -> WatchWorkoutSnapshot {
        let sourceExercises = workout.workoutExercises?.array as? [WorkoutExercise] ?? []
        var exercises: [WatchWorkoutExercise] = []
        exercises.reserveCapacity(sourceExercises.count)
        for (index, source) in sourceExercises.enumerated() {
            let exercise = source.exercise(in: catalog)
            let sourceSets = source.workoutSets?.array as? [WorkoutSet] ?? []
            var sets: [WatchWorkoutSet] = []
            sets.reserveCapacity(sourceSets.count)
            for (setIndex, set) in sourceSets.enumerated() {
                let weight = set.weight.map {
                    WeightUnit.convert(weight: $0.doubleValue, from: .metric, to: appUnit)
                }
                sets.append(WatchWorkoutSet(
                    id: set.uuid ?? UUID(), order: setIndex + 1,
                    weight: weight, reps: set.repetitions?.intValue, rpe: set.rpeValue,
                    completed: set.isCompleted, tag: set.tagValue?.rawValue,
                    duration: set.durationValue, distance: set.distanceValue,
                    comment: set.comment,
                    minTargetReps: set.minTargetRepetitionsValue.map(Int.init),
                    maxTargetReps: set.maxTargetRepetitionsValue.map(Int.init)))
            }
            exercises.append(WatchWorkoutExercise(
                id: source.uuid ?? UUID(), order: index + 1,
                name: exercise?.title ?? "Exercise", sets: sets,
                restTimerDuration: source.restTimerDurationValue,
                muscleGroup: exercise?.muscleGroup, exerciseUuid: source.exerciseUuid,
                imageURL: exercise?.imageURL?.absoluteString, imageData: nil,
                supersetID: source.supersetUuid, comment: source.comment))
        }
        return WatchWorkoutSnapshot(
            workoutID: workout.uuid ?? UUID(), title: workout.displayTitle(in: catalog),
            startDate: workout.start ?? workout.end ?? Date(), endDate: workout.end,
            exercises: exercises, weightUnit: weightUnit,
            sessionEffort: workout.sessionEffortValue, library: nil,
            revision: 0, updatedAt: workout.end ?? workout.start ?? Date(),
            comment: workout.comment, sourceSavedWorkoutID: workout.workoutRoutine?.uuid)
    }

    private func transferWorkoutLibrary(_ data: Data) {
        guard isActivated else { return }
        cancelOutstandingTransfers(marker: Self.libraryTransferMarker)
        _ = stageTransfer(data, prefix: Self.libraryFilePrefix, metadata: [
            Self.libraryTransferMarker: true,
            PayloadKey.workoutLibrary: true,
            "schemaVersion": WatchWorkoutWire.schemaVersion
        ])
    }

    private func cancelOutstandingTransfers(marker: String) {
        for transfer in session.outstandingFileTransfers
        where transfer.file.metadata?[marker] as? Bool == true {
            transfer.cancel()
        }
    }

    @discardableResult
    private func stageTransfer(_ data: Data, prefix: String,
                               metadata: [String: Any]) -> Bool {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                prefix + UUID().uuidString + ".json", isDirectory: false)
            try data.write(to: url, options: [.atomic])
            retainedTransferFiles.insert(url)
            session.transferFile(url, metadata: metadata)
            return true
        } catch {
            os_log("Could not stage Watch file transfer: %@", log: .watch, type: .error,
                   error.localizedDescription)
            return false
        }
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
        cancelOutstandingTransfers(marker: Self.snapshotTransferMarker)
        if data.count > Self.snapshotMessageLimit {
            if stageTransfer(data, prefix: Self.snapshotFilePrefix, metadata: [
                Self.snapshotTransferMarker: true,
                PayloadKey.workoutSnapshot: true,
                "schemaVersion": WatchWorkoutWire.schemaVersion
            ]) {
                pendingSnapshot = nil
            }
            return
        }
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
    func prepareWatchWorkout(workoutID: UUID? = nil,
                             startWatchCompanionErrorHandler: StartWatchCompanionErrorHandler? = nil,
                             preparedHandler: @escaping PrepareHandler) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.prepareWatchWorkout(workoutID: workoutID,
                                         startWatchCompanionErrorHandler: startWatchCompanionErrorHandler,
                                         preparedHandler: preparedHandler)
            }
            return
        }
        os_log("Preparing watch app", log: .watch, type: .default)
        guard isActivated else {
            guard let workoutID else {
                startWatchCompanionErrorHandler?(
                    GenericError(description: "Watch connectivity is not active"))
                activateSession()
                return
            }
            pendingPrepareRequest = PendingPrepareRequest(
                workoutID: workoutID,
                preparedHandler: preparedHandler,
                errorHandler: startWatchCompanionErrorHandler)
            os_log("Deferring Watch preparation until connectivity activates", log: .watch, type: .info)
            activateSession()
            return
        }
        beginPreparingWatch(startWatchCompanionErrorHandler: startWatchCompanionErrorHandler,
                            preparedHandler: preparedHandler)
    }

    private func beginPreparingWatch(
        startWatchCompanionErrorHandler: StartWatchCompanionErrorHandler?,
        preparedHandler: @escaping PrepareHandler
    ) {
        self.preparedHandler = preparedHandler // set here, because the prepare message can be received even before startWatchApp() completion fires
        os_log("Using HKHealthStore to open watch app", log: .watch, type: .default)
        HealthManager.shared.healthStore.startWatchApp(with: HealthManager.shared.workoutConfiguration) { success, error in
            guard success else {
                // This happens when app is in background (e.g. when started from an intent)
                os_log("HKHealthStore could not open watch app: %@", log: .watch, type: .fault, error?.localizedDescription ?? "nil")
                self.preparedHandler = nil
                startWatchCompanionErrorHandler?(error ?? GenericError(description: "Opening the watch app was unsuccessful"))
                return
            }
            os_log("Successfully opened watch app", log: .watch, type: .info)
        }
    }

    private func resumePendingPrepareRequest() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let pending = pendingPrepareRequest else { return }
        pendingPrepareRequest = nil
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        context.perform {
            do {
                guard let workout = try context.fetch(Workout.currentWorkoutFetchRequest).first,
                      workout.uuid == pending.workoutID,
                      !workout.isImported else {
                    os_log("Discarding stale deferred Watch preparation", log: .watch, type: .info)
                    return
                }
                self.beginPreparingWatch(startWatchCompanionErrorHandler: pending.errorHandler,
                                         preparedHandler: pending.preparedHandler)
            } catch {
                pending.errorHandler?(error)
            }
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
            let previous = UserDefaults.standard.watchWorkoutUuid
            UserDefaults.standard.watchWorkoutUuid = newValue
            if newValue != previous { liveMetrics.clear() }
        }
    }
}

extension WatchConnectionManager {
    func prepareAndStartWatchWorkout(workout: Workout, startWatchCompanionErrorHandler: StartWatchCompanionErrorHandler? = nil) {
        // Historical imports must never become a Watch HealthKit session.
        guard !workout.isImported, let workoutID = workout.uuid else { return }
        prepareWatchWorkout(workoutID: workoutID,
                            startWatchCompanionErrorHandler: startWatchCompanionErrorHandler) {
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
            guard workout.isCurrentWorkout, !workout.isImported else {
                os_log("Workout is no longer an eligible current workout", log: .watch, type: .error)
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
