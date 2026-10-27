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
    private var cachedLibrary: WatchWorkoutLibrary?
    private let libraryURL: URL

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "watchWorkoutStore.v1",
        libraryURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchWorkoutLibrary.json"),
        encode: @escaping (WatchWorkoutPersistedState) -> Data? = { WatchWorkoutWire.encode($0) }
    ) {
        self.libraryURL = libraryURL
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.encode = encode
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = WatchWorkoutWire.decode(WatchWorkoutPersistedState.self, from: data) {
            state = decoded
        } else {
            state = WatchWorkoutPersistedState()
        }
        cachedLibrary = (try? Data(contentsOf: libraryURL))
            .flatMap { WatchWorkoutWire.decode(WatchWorkoutLibrary.self, from: $0) }
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
        if state.outbox.contains(where: { ids.contains($0.id) && [.workoutFinished, .savedWorkoutUpserted, .savedWorkoutDeleted].contains($0.kind) }) {
            try persistLibraryLocked(libraryLocked())
        }
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

    func library() -> WatchWorkoutLibrary {
        lock.lock(); defer { lock.unlock() }
        return libraryLocked()
    }

    func replaceLibrary(_ incoming: WatchWorkoutLibrary) throws {
        lock.lock(); defer { lock.unlock() }
        guard incoming.schemaVersion <= WatchWorkoutWire.schemaVersion,
              incoming.generatedAt >= (cachedLibrary?.generatedAt ?? .distantPast) else { return }
        if let previous = cachedLibrary?.revision, let incomingRevision = incoming.revision,
           incomingRevision <= previous { return }
        let previous = cachedLibrary
        cachedLibrary = incoming
        do { try persistLibraryLocked(libraryLocked()) }
        catch { cachedLibrary = previous; throw error }
    }

    private func libraryLocked() -> WatchWorkoutLibrary {
        var library = cachedLibrary ?? WatchBundledLibrary.load()
        let libraryEvents = state.outbox.filter { [.savedWorkoutUpserted, .savedWorkoutDeleted, .workoutFinished].contains($0.kind) }
        guard !libraryEvents.isEmpty else { return library }
        for event in libraryEvents.sorted(by: { $0.sequence < $1.sequence }) {
            if event.kind == .savedWorkoutUpserted, let saved = event.savedWorkout {
                library.savedWorkouts.removeAll { $0.id == saved.id }
                library.savedWorkouts.append(saved)
            } else if event.kind == .savedWorkoutDeleted {
                library.savedWorkouts.removeAll { $0.id == event.workoutID }
            } else if event.kind == .workoutFinished, let snapshot = event.snapshot {
                library.history.removeAll { $0.workoutID == snapshot.workoutID }
                library.history.insert(snapshot, at: 0)
            }
        }
        library.history.sort { ($0.endDate ?? $0.startDate) > ($1.endDate ?? $1.startDate) }
        return library
    }

    private func persistLibraryLocked(_ library: WatchWorkoutLibrary) throws {
        guard let data = WatchWorkoutWire.encode(library) else { throw WatchWorkoutPersistenceError.encodingFailed }
        try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: libraryURL, options: .atomic)
        cachedLibrary = library
    }
}

class WorkoutSessionManagerStore: ObservableObject {
    static let shared = WorkoutSessionManagerStore()

    struct PersistenceFailure: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }
    
    let objectWillChange = PassthroughSubject<Void, Never>()
    private var automaticRecordingAttemptedFor: UUID?
    private var restExpiry: DispatchWorkItem?
    private var lastRestAlertEnd: Date?

    private(set) var recordingError: String? {
        didSet { DispatchQueue.main.async { self.objectWillChange.send() } }
    }
    private(set) var isRecoveringRecording = true {
        didSet { DispatchQueue.main.async { self.objectWillChange.send() } }
    }
    private(set) var isStartingRecording = false {
        didSet { DispatchQueue.main.async { self.objectWillChange.send() } }
    }

    var library: WatchWorkoutLibrary { WatchWorkoutStore.shared.library() }
    var preferredWeightUnit: WatchWorkoutWeightUnit {
        UserDefaults.standard.string(forKey: "watch.preferredWeightUnit")
            .flatMap(WatchWorkoutWeightUnit.init(rawValue:)) ?? library.weightUnit
    }

    func finishRecordingRecovery() {
        WorkoutSessionManager.perform {
            self.isRecoveringRecording = false
            if let snapshot = self.workoutSnapshot { self.applyLocalRest(snapshot) }
            self.ensureAutomaticRecording()
        }
    }

    func applyLibrary(_ library: WatchWorkoutLibrary) {
        WorkoutSessionManager.perform {
            do {
                try WatchWorkoutStore.shared.replaceLibrary(library)
                self.notifySyncStateChanged()
            } catch { self.recordPersistenceFailure(error) }
        }
    }

    private(set) var persistenceFailure: PersistenceFailure? {
        didSet {
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    func clearRecordingError() {
        WorkoutSessionManager.perform { self.recordingError = nil }
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
        refreshRecordingDiagnostic()
    }

    /// A read-only support snapshot for development builds. This never starts,
    /// stops or changes a HealthKit session, and contains no workout notes.
    func refreshRecordingDiagnostic() {
        #if DEBUG && !targetEnvironment(simulator)
        WorkoutSessionManager.perform {
            let manager = self.workoutSessionManager
            var state: [String: Any] = [
                "capturedAt": Date().timeIntervalSince1970,
                "recovering": self.isRecoveringRecording,
                "starting": self.isStartingRecording,
                "hasSnapshot": self.workoutSnapshot != nil,
                "isFinished": self.workoutSnapshot?.isFinishedRecord ?? false
            ]
            state["workoutID"] = self.workoutSnapshot?.workoutID.uuidString
            state["sessionWorkoutID"] = manager?.uuid?.uuidString
            state["sessionState"] = manager?.state.name
            state["recordingError"] = self.recordingError
            state["heartRate"] = manager?.mostRecentHeartRate
            state["heartRateDate"] = manager?.mostRecentHeartRateDate?.timeIntervalSince1970
            state["activeEnergyKilocalories"] = manager?.burnedCalories
            guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
            try? data.write(to: directory.appendingPathComponent("LightRecordingState.json"), options: .atomic)
        }
        #endif
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
        afterExerciseID: UUID? = nil,
        savedWorkout: WatchSavedWorkout? = nil,
        removedExerciseIDs: [UUID]? = nil, removedSetIDs: [UUID]? = nil,
        fieldChanges: WatchWorkoutFieldChanges? = WatchWorkoutFieldChanges()
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
                    snapshot: (eventSnapshot ?? ([.savedWorkoutUpserted, .savedWorkoutDeleted].contains(kind) ? nil : persistedSnapshot)).map(Self.compactSnapshot),
                    tag: tag,
                    catalogExerciseUuid: catalogExerciseUuid,
                    afterExerciseID: afterExerciseID,
                    savedWorkout: savedWorkout,
                    removedExerciseIDs: removedExerciseIDs, removedSetIDs: removedSetIDs,
                    fieldChanges: fieldChanges
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
                           afterExerciseID: UUID? = nil,
                           savedWorkout: WatchSavedWorkout? = nil,
                           removedExerciseIDs: [UUID]? = nil, removedSetIDs: [UUID]? = nil,
                           fieldChanges: WatchWorkoutFieldChanges? = WatchWorkoutFieldChanges()) -> WatchWorkoutEvent {
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
                          afterExerciseID: afterExerciseID,
                          savedWorkout: savedWorkout,
                          removedExerciseIDs: removedExerciseIDs, removedSetIDs: removedSetIDs,
                          fieldChanges: fieldChanges)
    }

    private static func compactSnapshot(_ snapshot: WatchWorkoutSnapshot) -> WatchWorkoutSnapshot {
        var copy = snapshot
        copy.library = nil
        for index in copy.exercises.indices { copy.exercises[index].imageData = nil }
        return copy
    }
}

extension WorkoutSessionManagerStore {
    func applyWorkoutSnapshot(_ snapshot: WatchWorkoutSnapshot) {
        WorkoutSessionManager.perform {
            guard snapshot.schemaVersion <= WatchWorkoutWire.schemaVersion else {
                os_log("Ignoring unsupported workout snapshot version=%d", type: .error, snapshot.schemaVersion)
                return
            }
            if let manager = self.workoutSessionManager, manager.isFinalizingWorkout, manager.uuid != snapshot.workoutID { return }
            let pending = WatchWorkoutStore.shared.pendingEvents().filter { $0.workoutID == snapshot.workoutID }
            guard !pending.contains(where: { $0.kind == .workoutFinished || $0.kind == .workoutDiscarded }) else { return }
            if let current = self.workoutSnapshot, !current.isFinishedRecord {
                guard current.workoutID == snapshot.workoutID, pending.isEmpty else { return }
            }
            let explicitUnit = UserDefaults.standard.string(forKey: "watch.preferredWeightUnit")
                .flatMap(WatchWorkoutWeightUnit.init(rawValue:))
            let snapshot = WatchWorkoutEditing.converting(snapshot, to: explicitUnit ?? snapshot.weightUnit ?? self.preferredWeightUnit)
            let replaced: Bool
            do {
                replaced = try WatchWorkoutStore.shared.replaceSnapshot(snapshot)
            } catch {
                self.recordPersistenceFailure(error)
                return
            }
            guard replaced else { return }
            self.publishSnapshot(snapshot)
            self.applyLocalRest(snapshot)

            if let manager = self.workoutSessionManager,
               manager.uuid == snapshot.workoutID {
                manager.updateStartDate(snapshot.startDate)
                manager.updateEndDate(snapshot.endDate)
                manager.restTimerEnd = snapshot.restTimerEnd
                manager.keepRestTimerRunning = snapshot.keepRestTimerRunning
                manager.selectedSetText = snapshot.selectedSetText
            }
            self.ensureAutomaticRecording()
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
            snapshot.isFinished = true
            snapshot.title = title ?? snapshot.title
            snapshot.sessionEffort = sessionEffort.map { min(max($0, 1), 10) }
                ?? snapshot.sessionEffort
            snapshot.activeEnergyKilocalories = self.workoutSessionManager?.burnedCalories
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
        recordingError = message
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
            if let snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord {
                workoutSessionManager.associateRecoveredWorkout(snapshot.workoutID)
            }
            self.workoutSessionManager = workoutSessionManager
            self.isRecoveringRecording = false
            if let uuid = workoutSessionManager.uuid {
                if let snapshot = self.workoutSnapshot,
                   snapshot.workoutID == uuid {
                    workoutSessionManager.updateStartDate(snapshot.startDate)
                    workoutSessionManager.updateEndDate(snapshot.endDate)
                    workoutSessionManager.restTimerEnd = snapshot.restTimerEnd
                    workoutSessionManager.keepRestTimerRunning = snapshot.keepRestTimerRunning
                    workoutSessionManager.selectedSetText = snapshot.selectedSetText
                    self.applyLocalRest(snapshot)
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
                if state == .stopped && !workoutSessionManager.isFinalizingWorkout {
                    workoutSessionManager.discard()
                    self.workoutSessionManager = nil
                } else if state != .ended && state != .notStarted {
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
            defer { self.refreshRecordingDiagnostic() }
            guard !self.isStartingRecording else { return }
            guard self.workoutSnapshot == nil || self.workoutSnapshot?.workoutID == uuid else {
                self.recordingError = "Finish the workout already on this Watch before starting another."
                return
            }
            guard self.workoutSnapshot?.isFinishedRecord != true else { return }
            if self.workoutSnapshot == nil {
                guard self.persistSnapshot(.placeholder(workoutID: uuid, startDate: start)) else { return }
            }
            guard !self.isRecoveringRecording else { return }
            self.automaticRecordingAttemptedFor = uuid
            if let manager = self.workoutSessionManager,
               manager.state == .running || manager.state == .paused {
                guard manager.uuid == uuid || manager.uuid == nil else {
                    self.recordingError = "Another Watch recording is still running. Finish it before starting this workout."
                    return
                }
                if manager.uuid == nil {
                    do { try manager.setUuid(uuid) }
                    catch { self.recordingError = error.localizedDescription; return }
                }
                manager.updateStartDate(start)
                self.recordingError = nil
                manager.publishLiveMetrics()
                return
            }
            if let manager = self.workoutSessionManager, manager.state == .stopped {
                if manager.isFinalizingWorkout {
                    self.recordingError = "Your previous recording is still being saved."
                    return
                }
                manager.discard()
                self.workoutSessionManager = nil
            }
            self.isStartingRecording = true
            self.recordingError = nil
            let manager: WorkoutSessionManager
            do {
                if let existing = self.workoutSessionManager,
                   existing.state == .prepared || existing.state == .notStarted {
                    manager = existing
                } else {
                    let configuration = HKWorkoutConfiguration()
                    configuration.activityType = .traditionalStrengthTraining
                    let session = try HKWorkoutSession(healthStore: WorkoutSessionManager.healthStore,
                                                       configuration: configuration)
                    manager = WorkoutSessionManager(session: session)
                    self.workoutSessionManager = manager
                }
                try manager.setUuid(uuid)
            } catch {
                self.isStartingRecording = false
                self.recordingError = error.localizedDescription
                self.workoutSessionManager?.discard()
                self.workoutSessionManager = nil
                return
            }
            // Keep Light's display start, but never invent sensor data for the
            // time before this Watch actually begins recording.
            manager.start(start: max(start, Date())) { result in
                WorkoutSessionManager.perform {
                    defer { self.refreshRecordingDiagnostic() }
                    self.isStartingRecording = false
                    switch result {
                    case .success:
                        manager.updateStartDate(start)
                        manager.publishLiveMetrics()
                        WKInterfaceDevice.current().play(.start)
                    case .failure(let error):
                        self.recordingError = error.localizedDescription
                        manager.discard()
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

            if notifyPhone, self.workoutSnapshot?.isFinishedRecord == true { return }

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
                snapshot.isFinished = true
                snapshot.activeEnergyKilocalories = self.workoutSessionManager?.burnedCalories
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
                        DispatchQueue.main.async { PhoneConnectionManager.shared.requestCurrentSnapshotIfReady() }
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

// MARK: - Watch-first training
extension WorkoutSessionManagerStore {
    func updateCurrent(_ mutation: @escaping (inout WatchWorkoutSnapshot) -> Void) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord else { return }
            let previous = snapshot
            mutation(&snapshot)
            WatchWorkoutEditing.normalize(&snapshot)
            guard snapshot != previous, self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            snapshot.selectedSetText = snapshot.selectedSet?.set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.commitEvent(snapshotChange: .replace(snapshot), workoutID: snapshot.workoutID,
                                   kind: .workoutStructureUpdated, eventSnapshot: snapshot,
                                   removedExerciseIDs: previous.exercises.map(\.id).filter { oldID in
                                       !snapshot.exercises.contains { $0.id == oldID }
                                   },
                                   removedSetIDs: previous.exercises.flatMap(\.sets).map(\.id).filter { oldID in
                                       !snapshot.exercises.flatMap(\.sets).contains { $0.id == oldID }
                                   }, fieldChanges: .between(previous: previous, next: snapshot)) else { return }
            self.applyLocalRest(snapshot)
        }
    }

    func selectSet(_ id: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, snapshot.selectedSetID != id,
                  snapshot.exercises.flatMap(\.sets).contains(where: { $0.id == id }) else { return }
            snapshot.selectedSetID = id
            snapshot.selectedSetText = snapshot.selectedSet?.set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            snapshot.updatedAt = Date()
            guard self.advanceRevision(&snapshot) else { return }
            self.persistSnapshot(snapshot)
        }
    }

    func completeSet(exerciseID: UUID, setID: UUID) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord,
                  let exercise = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let set = snapshot.exercises[exercise].sets.firstIndex(where: { $0.id == setID }) else { return }
            snapshot.exercises[exercise].sets[set].completed.toggle()
            let completed = snapshot.exercises[exercise].sets[set].completed
            snapshot.selectedSetID = completed ? WatchWorkoutEditing.nextSet(in: snapshot, after: setID) : setID
            if completed {
                snapshot.restTimerEnd = Date().addingTimeInterval(snapshot.exercises[exercise].restTimerDuration ?? 60)
                snapshot.pausedRestRemaining = nil
            } else {
                snapshot.restTimerEnd = nil
                snapshot.pausedRestRemaining = nil
            }
            snapshot.updatedAt = Date()
            snapshot.selectedSetText = snapshot.selectedSet?.set.displayText(weightUnit: snapshot.weightUnit ?? .kilogram)
            guard self.advanceRevision(&snapshot),
                  self.commitEvent(snapshotChange: .replace(snapshot), workoutID: snapshot.workoutID,
                                   kind: .setCompletionChanged, exerciseID: exerciseID, setID: setID,
                                   completed: completed, eventSnapshot: snapshot) else { return }
            self.applyLocalRest(snapshot)
            WKInterfaceDevice.current().play(completed ? .success : .click)
        }
    }

    func addExercise(_ pick: WatchExercisePick, after: UUID? = nil) {
        updateCurrent { snapshot in
            let index = after.flatMap { id in snapshot.exercises.firstIndex { $0.id == id } }.map { $0 + 1 }
                ?? snapshot.exercises.count
            let set = WatchWorkoutSet(order: 1, reps: 8)
            let exercise = WatchWorkoutExercise(order: index + 1, name: pick.name, sets: [set],
                                               restTimerDuration: 90, muscleGroup: pick.muscle,
                                               exerciseUuid: pick.id, imageURL: pick.imageURL)
            snapshot.exercises.insert(exercise, at: index)
            if snapshot.selectedSetID == nil { snapshot.selectedSetID = set.id }
        }
    }

    func startBlankWorkout(title: String = "Workout") {
        begin(WatchWorkoutEditing.newWorkout(exercises: [], title: title, unit: preferredWeightUnit))
    }

    func startWorkout(from saved: WatchSavedWorkout) {
        var snapshot = WatchWorkoutEditing.newWorkout(exercises: saved.exercises, title: saved.title,
                                                      unit: saved.weightUnit, sourceSavedWorkoutID: saved.id)
        snapshot.comment = saved.comment
        begin(WatchWorkoutEditing.converting(snapshot, to: preferredWeightUnit))
    }

    func repeatWorkout(_ history: WatchWorkoutSnapshot) {
        var snapshot = WatchWorkoutEditing.newWorkout(exercises: history.exercises,
                                                      title: history.title ?? "Workout",
                                                      unit: history.weightUnit ?? preferredWeightUnit)
        snapshot.comment = history.comment
        begin(WatchWorkoutEditing.converting(snapshot, to: preferredWeightUnit))
    }

    private func begin(_ snapshot: WatchWorkoutSnapshot) {
        WorkoutSessionManager.perform {
            guard self.workoutSnapshot == nil else {
                self.recordingError = "Finish your current workout first."
                return
            }
            guard self.commitEvent(snapshotChange: .replace(snapshot), workoutID: snapshot.workoutID,
                                   kind: .workoutCreated, eventSnapshot: snapshot) else { return }
            self.startWorkoutSession(start: snapshot.startDate, uuid: snapshot.workoutID)
        }
    }

    /// A live workout owns a HealthKit recording automatically. Recovery gets
    /// first chance to reuse the existing builder before we create anything.
    /// A failed automatic attempt stays visible and requires an explicit retry.
    func ensureAutomaticRecording() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--light-watch-demo") { return }
        #endif
        WorkoutSessionManager.perform {
            defer { self.refreshRecordingDiagnostic() }
            guard !self.isRecoveringRecording, !self.isStartingRecording,
                  let snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord else { return }
            if let manager = self.workoutSessionManager {
                if manager.state == .running || manager.state == .paused {
                    if manager.uuid == snapshot.workoutID { return }
                    if manager.uuid != nil {
                        self.recordingError = "A different Watch recording is still running. Finish it before starting another."
                        return
                    }
                }
                if manager.state == .stopped && manager.isFinalizingWorkout { return }
            }
            guard self.automaticRecordingAttemptedFor != snapshot.workoutID else { return }
            self.automaticRecordingAttemptedFor = snapshot.workoutID
            self.startWorkoutSession(start: snapshot.startDate, uuid: snapshot.workoutID)
        }
    }

    func startRecording() {
        WorkoutSessionManager.perform {
            guard !self.isRecoveringRecording, let snapshot = self.workoutSnapshot,
                  !snapshot.isFinishedRecord else { return }
            self.automaticRecordingAttemptedFor = snapshot.workoutID
            self.startWorkoutSession(start: snapshot.startDate, uuid: snapshot.workoutID)
        }
    }

    func toggleWorkoutPause() {
        WorkoutSessionManager.perform { self.workoutSessionManager?.togglePause() }
    }

    func setPreferredWeightUnit(_ unit: WatchWorkoutWeightUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: "watch.preferredWeightUnit")
        updateCurrent { $0 = WatchWorkoutEditing.converting($0, to: unit) }
        notifySyncStateChanged()
    }

    func saveWorkout(_ saved: WatchSavedWorkout, completion: @escaping (Bool) -> Void = { _ in }) {
        WorkoutSessionManager.perform {
            guard !saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                DispatchQueue.main.async { completion(false) }; return
            }
            let success = self.commitEvent(workoutID: saved.id, kind: .savedWorkoutUpserted, savedWorkout: saved)
            self.notifySyncStateChanged()
            DispatchQueue.main.async { completion(success) }
        }
    }

    func deleteSavedWorkout(id: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        WorkoutSessionManager.perform {
            let success = self.commitEvent(workoutID: id, kind: .savedWorkoutDeleted)
            self.notifySyncStateChanged()
            DispatchQueue.main.async { completion(success) }
        }
    }

    func saveCurrentAsWorkout(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let snapshot = workoutSnapshot else { completion(false); return }
        saveAsWorkout(snapshot, completion: completion)
    }

    func saveAsWorkout(_ snapshot: WatchWorkoutSnapshot, completion: @escaping (Bool) -> Void = { _ in }) {
        let template = WatchWorkoutEditing.newWorkout(exercises: snapshot.exercises,
            title: snapshot.title ?? "Workout", unit: snapshot.weightUnit ?? preferredWeightUnit)
        saveWorkout(WatchSavedWorkout(id: UUID(), title: template.title ?? "Workout",
            exercises: template.exercises, weightUnit: template.weightUnit ?? preferredWeightUnit,
            comment: snapshot.comment, updatedAt: Date()), completion: completion)
    }

    func finishWorkout(effort: Double?) {
        WorkoutSessionManager.perform {
            guard let snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord,
                  snapshot.exercises.flatMap(\.sets).contains(where: \.completed) else { return }
            self.endWorkoutSession(start: snapshot.startDate, end: Date(), title: snapshot.title,
                                   uuid: snapshot.workoutID, sessionEffort: effort)
        }
    }

    func discardWorkout() {
        guard let snapshot = workoutSnapshot else { return }
        discardWorkoutSession(uuid: snapshot.workoutID)
    }

    func adjustRest(by interval: TimeInterval) {
        changeRest { snapshot in
            if let paused = snapshot.pausedRestRemaining {
                snapshot.pausedRestRemaining = max(0, paused + interval)
            } else if let end = snapshot.restTimerEnd {
                snapshot.restTimerEnd = max(end, Date()).addingTimeInterval(interval)
            }
        }
    }

    func toggleRestPause() {
        changeRest { snapshot in
            if let paused = snapshot.pausedRestRemaining {
                snapshot.restTimerEnd = Date().addingTimeInterval(paused)
                snapshot.pausedRestRemaining = nil
            } else if let end = snapshot.restTimerEnd {
                snapshot.pausedRestRemaining = max(0, end.timeIntervalSinceNow)
                snapshot.restTimerEnd = nil
            }
        }
    }

    func skipRest() {
        changeRest { $0.restTimerEnd = nil; $0.pausedRestRemaining = nil }
    }

    private func changeRest(_ mutation: @escaping (inout WatchWorkoutSnapshot) -> Void) {
        WorkoutSessionManager.perform {
            guard var snapshot = self.workoutSnapshot, !snapshot.isFinishedRecord else { return }
            mutation(&snapshot)
            if let paused = snapshot.pausedRestRemaining, paused <= 0 { snapshot.pausedRestRemaining = nil }
            if let end = snapshot.restTimerEnd, end <= Date() { snapshot.restTimerEnd = nil }
            guard self.advanceRevision(&snapshot) else { return }
            snapshot.updatedAt = Date()
            guard self.commitEvent(snapshotChange: .replace(snapshot), workoutID: snapshot.workoutID,
                                   kind: .restTimerUpdated, restTimerEnd: snapshot.restTimerEnd,
                                   keepRestTimerRunning: snapshot.keepRestTimerRunning,
                                   eventSnapshot: snapshot) else { return }
            self.applyLocalRest(snapshot)
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func applyLocalRest(_ snapshot: WatchWorkoutSnapshot) {
        restExpiry?.cancel()
        if let manager = workoutSessionManager, manager.uuid == snapshot.workoutID {
            manager.restTimerEnd = snapshot.restTimerEnd
            manager.keepRestTimerRunning = snapshot.keepRestTimerRunning
        }
        guard !snapshot.isFinishedRecord, snapshot.pausedRestRemaining == nil,
              let end = snapshot.restTimerEnd else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let current = self.workoutSnapshot,
                  current.workoutID == snapshot.workoutID, current.restTimerEnd == end,
                  current.pausedRestRemaining == nil, !current.isFinishedRecord else { return }
            if self.lastRestAlertEnd != end {
                self.lastRestAlertEnd = end
                DispatchQueue.main.async { WKInterfaceDevice.current().play(.notification) }
            }
            if current.keepRestTimerRunning { self.notifySyncStateChanged() }
            else { self.skipRest() }
        }
        restExpiry = work
        WorkoutSessionManager.accessQueue.asyncAfter(deadline: .now() + max(0, end.timeIntervalSinceNow), execute: work)
    }
}
