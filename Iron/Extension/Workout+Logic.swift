//
//  Workout+Logic.swift
//  Iron
//
//  Created by Karim Abou Zeid on 21.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import ActivityKit
import UIKit
import WorkoutDataKit
import os.log

extension Workout {
    // TODO: would be better when SettingsStore, WatchConnectionManager, RestTimerStore etc are injected

    enum StartError: LocalizedError {
        case workoutAlreadyActive
        case workoutUnavailable

        var errorDescription: String? {
            switch self {
            case .workoutAlreadyActive:
                return "A workout is already active. Finish or discard it before starting another."
            case .workoutUnavailable:
                return "This workout is no longer available."
            }
        }
    }

    /// Create the log and its sets inside the save boundary so a failed start
    /// cannot leave an orphan history entry or partially copied routine.
    static func startNew(
        in context: NSManagedObjectContext,
        routine: WorkoutRoutine? = nil,
        save: (() throws -> Void)? = nil
    ) throws -> Workout {
        if let routine, routine.managedObjectContext !== context || routine.isDeleted {
            throw StartError.workoutUnavailable
        }
        return try startCreatedWorkout(in: context, save: save) {
            routine?.createWorkout(context: context) ?? Workout.create(context: context)
        }
    }

    static func startRepeating(_ source: Workout, blank: Bool, save: (() throws -> Void)? = nil) throws -> Workout {
        guard let context = source.managedObjectContext, !source.isDeleted else {
            throw StartError.workoutUnavailable
        }
        return try startCreatedWorkout(in: context, save: save) {
            guard let copy = source.copyForRepeat(blank: blank) else { throw StartError.workoutUnavailable }
            return copy
        }
    }

    private static func startCreatedWorkout(
        in context: NSManagedObjectContext,
        save: (() throws -> Void)?,
        create: () throws -> Workout
    ) throws -> Workout {
        guard try context.count(for: Workout.currentWorkoutFetchRequest) == 0 else {
            throw StartError.workoutAlreadyActive
        }
        let workout = try context.persistMutation(save: { try save?() ?? context.save() }) {
            let workout = try create()
            workout.start = Date()
            workout.isCurrentWorkout = true
            return workout
        }
        workout.didStart(startWatchCompanionErrorHandler: nil)
        return workout
    }
    
    func start(startWatchCompanionErrorHandler: WatchConnectionManager.StartWatchCompanionErrorHandler? = nil,
               save: (() throws -> Void)? = nil) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to start workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to start workout without context")
            return
        }

        try context.persistMutation(save: { try save?() ?? context.save() }) {
            start = Date()
            isCurrentWorkout = true
        }

        didStart(startWatchCompanionErrorHandler: startWatchCompanionErrorHandler)
    }

    private func didStart(startWatchCompanionErrorHandler: WatchConnectionManager.StartWatchCompanionErrorHandler?) {
        WorkoutLiveActivityManager.shared.startOrUpdate(for: self)
        
        if SettingsStore.shared.watchCompanion {
            WatchConnectionManager.shared.prepareAndStartWatchWorkout(workout: self, startWatchCompanionErrorHandler: startWatchCompanionErrorHandler)
        }
        
        // TODO: move this to the current workout view controller, or maybe even when a notification is scheduled?
        NotificationManager.shared.requestAuthorization()
        
        if (workoutExercises?.count ?? 0) == 0 && workoutRoutine == nil {
            // only donate when we start an empty workout
            // we don't have apropriate intent parameters for other workouts yet
            Shortcuts.donateStartWorkoutInteraction(for: self)
        }
    }
    
    func cancel(save: (() throws -> Void)? = nil) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to cancel workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to cancel workout without context")
            return
        }
        
        let workoutID = uuid
        let activitySnapshot = WorkoutLiveActivityManager.shared.endSnapshot(for: self)
        try context.persistMutation(save: { try save?() ?? context.save() }) {
            context.delete(self)
        }

        RestTimerStore.shared.cancel()
        WorkoutLiveActivityManager.shared.end(using: activitySnapshot, completed: false)
        
        if WatchConnectionManager.shared.currentWatchWorkoutUuid != nil, let uuid = workoutID {
            WatchConnectionManager.shared.discardWatchWorkout(uuid: uuid)
        }
        
        // the user did not go through with the workout, we should remove our previous donation
        if let workoutID { Shortcuts.deleteStartWorkoutInteractionDonation(uuid: workoutID) }
    }
    
    func finish() throws {
        try finish(syncToHealth: true)
    }

    /// Finishes the local workout while allowing the completion editor to opt
    /// out of phone-originated HealthKit export. A workout already running on
    /// Apple Watch must still be ended on the watch; watchOS owns that active
    /// HealthKit session.
    func finish(syncToHealth: Bool, save: (() throws -> Void)? = nil,
                updatingValues: () -> Void = {}) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to finish workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to finish workout without context")
            return
        }
        
        try context.persistMutation(save: { try save?() ?? context.save() }) {
            updatingValues()
            deleteExercisesWhereAllSetsAreUncompleted()
            deleteUncompletedSets()
            start = safeStart
            end = safeEnd
            isCurrentWorkout = false
        }

        RestTimerStore.shared.cancel()
        WorkoutLiveActivityManager.shared.end(for: self, completed: true)
        
        // save workout in Health or tell Apple Watch to finish the workout
        if let watchWorkoutUuid = WatchConnectionManager.shared.currentWatchWorkoutUuid {
            if syncToHealth, watchWorkoutUuid != uuid {
                os_log("currentWatchWorkoutUuid=%@ but workout uuid=%@, saving HealthKit workout on phone too to be safe", log: .watch, type: .error, watchWorkoutUuid.uuidString, uuid?.uuidString ?? "nil")
                HealthManager.shared.saveWorkout(workout: self, exerciseStore: ExerciseStore.shared)
            }
            if let start = start, let end = end, let uuid = uuid {
                WatchConnectionManager.shared.finishWatchWorkout(start: start, end: end, title: optionalDisplayTitle(in: ExerciseStore.shared.exercises), uuid: uuid)
            }
        } else if syncToHealth {
            HealthManager.shared.saveWorkout(workout: self, exerciseStore: ExerciseStore.shared)
        }
    }
    
    func delete(save: (() throws -> Void)? = nil) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to delete workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to delete workout without context")
            return
        }
        
        let workoutID = uuid
        try context.persistMutation(save: { try save?() ?? context.save() }) {
            context.delete(self)
        }
        if let workoutID {
            HealthManager.shared.deleteWorkout(uuid: workoutID)
            Shortcuts.deleteStartWorkoutInteractionDonation(uuid: workoutID)
        }
    }
    
    func copyForRepeat(blank: Bool) -> Workout? {
        guard let context = managedObjectContext else {
            os_log("Attempt to copy workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to copy workout without context")
            return nil
        }
        
        // create the workout
        let newWorkout = Workout.create(context: context)
        
        if let workoutExercises = workoutExercises?.compactMap({ $0 as? WorkoutExercise }) {
            // copy the exercises
            for workoutExercise in workoutExercises {
                let newWorkoutExercise = WorkoutExercise.create(context: context)
                newWorkoutExercise.workout = newWorkout
                newWorkoutExercise.exerciseUuid = workoutExercise.exerciseUuid
                
                if let workoutSets = workoutExercise.workoutSets?.compactMap({ $0 as? WorkoutSet }) {
                    // copy the sets
                    for workoutSet in workoutSets {
                        let newWorkoutSet = WorkoutSet.create(context: context)
                        newWorkoutSet.workoutExercise = newWorkoutExercise
                        newWorkoutSet.isCompleted = false
                        if !blank {
                            let repetitions = workoutSet.repetitionsValue
                            newWorkoutSet.minTargetRepetitionsValue = repetitions
                            newWorkoutSet.maxTargetRepetitionsValue = repetitions
                            // don't copy weight, RPE, tag, comment, etc.
                        }
                    }
                }
            }
        }
        
        return newWorkout
    }
}

/// Owns Iron's single active workout Live Activity and translates Core Data models into a
/// compact, value-only ActivityKit payload. The widget extension never opens the live workout.
final class WorkoutLiveActivityManager {
    static let shared = WorkoutLiveActivityManager()

    private let activityOperationLock = NSLock()
    private var activityOperation: Task<Void, Never>?

    private struct PendingConfirmationTransition {
        let token: UUID
        let confirmationUntil: Date
        var workItem: DispatchWorkItem?
        var backgroundTaskIdentifier: UIBackgroundTaskIdentifier
    }

    private struct ConfirmationTransitionResources {
        let workItem: DispatchWorkItem?
        let backgroundTaskIdentifier: UIBackgroundTaskIdentifier
    }

    struct EndSnapshot {
        let workoutID: String
        let completedSets: Int
        let totalSets: Int
        let fallbackSet: WorkoutActivityAttributes.SetSnapshot?
    }

    private let confirmationTransitionLock = NSLock()
    private var pendingConfirmationTransitions: [String: PendingConfirmationTransition] = [:]

    private init() {}

    func startOrUpdate(for workout: Workout, preservingTransition: Bool = true) {
        let workoutID = identifier(for: workout)
        let existingActivity = activity(for: workoutID)
        let state = reconciledState(
            for: workout,
            priorState: preservingTransition ? existingActivity?.content.state : nil,
            now: Date(),
            restTimerStart: RestTimerStore.shared.restTimerStart,
            restTimerEnd: RestTimerStore.shared.restTimerEnd,
            pausedRestRemaining: pausedRestRemaining
        )
        synchronizeConfirmationTransition(for: workoutID, state: state)
        publish(
            attributes: existingActivity?.attributes ?? attributes(for: workout),
            state: state
        )
    }

    func setCompleted(
        _ set: WorkoutSet,
        in workoutExercise: WorkoutExercise,
        workout: Workout,
        confirmationDuration: TimeInterval = 10
    ) {
        let attributes = attributes(for: workout)
        let completedSnapshot = snapshot(for: set, in: workoutExercise)
        let nextSnapshot = nextIncompleteSnapshot(after: set, in: workout)
        let now = Date()
        let confirmationUntil = now.addingTimeInterval(confirmationDuration)
        let restTimerStart = RestTimerStore.shared.restTimerStart
        let restTimerEnd = RestTimerStore.shared.restTimerEnd
        let counts = setCounts(in: workout)
        let completedState = WorkoutActivityAttributes.ContentState(
            phase: .setCompleted,
            displaySet: completedSnapshot,
            nextSet: nextSnapshot,
            confirmationUntil: confirmationUntil,
            restTimerStart: restTimerStart,
            restTimerEnd: restTimerEnd,
            completedSets: counts.completed,
            totalSets: counts.total,
            pausedRestRemaining: pausedRestRemaining
        )

        let transitionToken = replacePendingConfirmationTransition(
            for: attributes.workoutID,
            confirmationUntil: confirmationUntil
        )
        publish(attributes: attributes, state: completedState)
        scheduleConfirmationTransition(
            for: attributes.workoutID,
            confirmationUntil: confirmationUntil,
            token: transitionToken
        )
    }

    /// Preserve the 10-second confirmation phase while a timer is adjusted or arrives from Watch.
    func refreshRestTimer(for workout: Workout) {
        startOrUpdate(for: workout, preservingTransition: true)
    }

    func refreshCurrentWorkoutRestTimer() {
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        guard let workout = (try? context.fetch(Workout.currentWorkoutFetchRequest))?.first else { return }
        refreshRestTimer(for: workout)
    }

    func end(for workout: Workout, completed: Bool) {
        end(using: endSnapshot(for: workout), completed: completed)
    }

    /// Captures every Core Data value needed to end an activity before a
    /// workout is durably deleted.
    func endSnapshot(for workout: Workout) -> EndSnapshot {
        let counts = setCounts(in: workout)
        return EndSnapshot(
            workoutID: identifier(for: workout),
            completedSets: counts.completed,
            totalSets: counts.total,
            fallbackSet: currentPayload(for: workout)?.state.displaySet
        )
    }

    func end(using snapshot: EndSnapshot, completed: Bool) {
        cancelPendingConfirmationTransition(for: snapshot.workoutID)
        let dismissalPolicy: ActivityUIDismissalPolicy = completed
            ? .after(Date().addingTimeInterval(30))
            : .immediate

        enqueueActivityOperation {
            guard let activity = self.activity(for: snapshot.workoutID) else { return }
            let finalState = WorkoutActivityAttributes.ContentState(
                phase: .finished,
                displaySet: activity.content.state.visibleSet(at: Date()) ?? snapshot.fallbackSet,
                nextSet: nil,
                confirmationUntil: nil,
                restTimerStart: nil,
                restTimerEnd: nil,
                completedSets: snapshot.completedSets,
                totalSets: snapshot.totalSets
            )
            let content = ActivityContent(
                state: finalState,
                staleDate: nil,
                relevanceScore: 100
            )
            await activity.end(content, dismissalPolicy: dismissalPolicy)
        }
    }

    private typealias Payload = (
        attributes: WorkoutActivityAttributes,
        state: WorkoutActivityAttributes.ContentState
    )

    private func currentPayload(for workout: Workout) -> Payload? {
        return (
            attributes: attributes(for: workout),
            state: reconciledState(
                for: workout,
                priorState: nil,
                now: Date(),
                restTimerStart: RestTimerStore.shared.restTimerStart,
                restTimerEnd: RestTimerStore.shared.restTimerEnd,
                pausedRestRemaining: pausedRestRemaining
            )
        )
    }

    /// Rebuilds value snapshots from Core Data so ActivityKit never republishes
    /// stale set results, ordering, identifiers, or counts.
    func reconciledState(
        for workout: Workout,
        priorState: WorkoutActivityAttributes.ContentState?,
        now: Date,
        restTimerStart: Date?,
        restTimerEnd: Date?,
        pausedRestRemaining: TimeInterval? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        let flattened = flattenedSets(in: workout)
        let counts = setCounts(in: workout)
        let anchor = priorState?.displaySet?.setID.flatMap { anchorID in
            flattened.first { setIdentifier($0.set) == anchorID && $0.set.isCompleted }
        }
        let confirmationUntil: Date? = {
            guard priorState?.phase == .setCompleted,
                  anchor != nil,
                  let deadline = priorState?.confirmationUntil,
                  deadline > now else { return nil }
            return deadline
        }()

        let next: (exercise: WorkoutExercise, set: WorkoutSet)?
        if let anchor,
           let anchorIndex = flattened.firstIndex(where: { $0.set.objectID == anchor.set.objectID }) {
            let after = flattened.dropFirst(anchorIndex + 1).first { !$0.set.isCompleted }
            next = after ?? flattened.first { !$0.set.isCompleted }
        } else {
            next = flattened.first { !$0.set.isCompleted }
        }

        let anchorSnapshot = anchor.map { snapshot(for: $0.set, in: $0.exercise) }
        let nextSnapshot = next.map { snapshot(for: $0.set, in: $0.exercise) }
        let fallbackSnapshot = flattened.last.map { snapshot(for: $0.set, in: $0.exercise) }
        let hasRunningTimer = nextSnapshot != nil
            && restTimerStart != nil
            && restTimerEnd.map { $0 > now } == true
        let pausedRemaining = pausedRestRemaining.flatMap {
            nextSnapshot != nil && $0.isFinite && $0 > 0 ? $0 : nil
        }

        let phase: WorkoutActivityAttributes.Phase
        if confirmationUntil != nil {
            phase = .setCompleted
        } else if flattened.isEmpty {
            phase = .currentSet
        } else if nextSnapshot == nil {
            phase = .finished
        } else if hasRunningTimer || pausedRemaining != nil {
            phase = .resting
        } else {
            phase = .currentSet
        }

        return WorkoutActivityAttributes.ContentState(
            phase: phase,
            // Keep the completed anchor across repeated reconciliations. The
            // widget uses nextSet while resting/current, while displaySet is
            // the stable basis for finding the next set again after edits.
            displaySet: anchorSnapshot ?? nextSnapshot ?? fallbackSnapshot,
            nextSet: nextSnapshot,
            confirmationUntil: confirmationUntil,
            restTimerStart: hasRunningTimer ? restTimerStart : nil,
            restTimerEnd: hasRunningTimer ? restTimerEnd : nil,
            completedSets: counts.completed,
            totalSets: counts.total,
            pausedRestRemaining: pausedRemaining
        )
    }

    private var pausedRestRemaining: TimeInterval? {
        RestTimerStore.shared.isPaused ? RestTimerStore.shared.restTimerRemainingTime : nil
    }

    private func synchronizeConfirmationTransition(
        for workoutID: String,
        state: WorkoutActivityAttributes.ContentState
    ) {
        guard state.phase == .setCompleted, let confirmationUntil = state.confirmationUntil else {
            cancelPendingConfirmationTransition(for: workoutID)
            return
        }
        ensureConfirmationTransition(for: workoutID, confirmationUntil: confirmationUntil)
    }

    private func publish(
        attributes: WorkoutActivityAttributes,
        state: WorkoutActivityAttributes.ContentState
    ) {
        if state.phase != .setCompleted || state.confirmationUntil == nil {
            cancelPendingConfirmationTransition(for: attributes.workoutID)
        }

        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: state),
            relevanceScore: 100
        )

        enqueueActivityOperation {
            await ExerciseMediaStore.shared.prepareLiveActivityArtwork(
                fileNames: [state.displaySet?.artworkFileName, state.nextSet?.artworkFileName].compactMap { $0 }
            )
            if let activity = self.activity(for: attributes.workoutID) {
                await activity.update(content)
                return
            }

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let canCreateActivity = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
            guard canCreateActivity else { return }
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                os_log(
                    "Could not start workout Live Activity: %@",
                    log: .workoutData,
                    type: .error,
                    error.localizedDescription
                )
            }
        }
    }

    private func ensureConfirmationTransition(
        for workoutID: String,
        confirmationUntil: Date
    ) {
        guard !hasPendingConfirmationTransition(for: workoutID) else { return }
        let transitionToken = replacePendingConfirmationTransition(
            for: workoutID,
            confirmationUntil: confirmationUntil
        )
        scheduleConfirmationTransition(
            for: workoutID,
            confirmationUntil: confirmationUntil,
            token: transitionToken
        )
    }

    /// Schedule exactly one app-side transition for the current confirmation phase. The
    /// background task keeps the app alive while the short confirmation window expires,
    /// including when the user locks the phone immediately after completing a set.
    private func scheduleConfirmationTransition(
        for workoutID: String,
        confirmationUntil: Date,
        token: UUID
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.performConfirmationTransition(
                for: workoutID,
                confirmationUntil: confirmationUntil,
                token: token
            )
        }

        confirmationTransitionLock.lock()
        guard var pending = pendingConfirmationTransitions[workoutID],
              pending.token == token,
              pending.confirmationUntil == confirmationUntil else {
            confirmationTransitionLock.unlock()
            workItem.cancel()
            return
        }
        pending.workItem = workItem
        pendingConfirmationTransitions[workoutID] = pending
        confirmationTransitionLock.unlock()

        let backgroundTaskIdentifier = beginBackgroundTask(for: workoutID, token: token)

        confirmationTransitionLock.lock()
        guard var current = pendingConfirmationTransitions[workoutID],
              current.token == token,
              current.confirmationUntil == confirmationUntil else {
            confirmationTransitionLock.unlock()
            workItem.cancel()
            endBackgroundTask(backgroundTaskIdentifier)
            return
        }
        current.backgroundTaskIdentifier = backgroundTaskIdentifier
        pendingConfirmationTransitions[workoutID] = current
        confirmationTransitionLock.unlock()

        let delay = max(0, confirmationUntil.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performConfirmationTransition(
        for workoutID: String,
        confirmationUntil: Date,
        token: UUID
    ) {
        enqueueActivityOperation {
            defer {
                self.finishConfirmationTransition(for: workoutID, token: token)
            }

            guard self.hasPendingConfirmationTransition(
                for: workoutID,
                confirmationUntil: confirmationUntil,
                token: token
            ), let activity = self.activity(for: workoutID) else { return }

            let existing = activity.content.state
            guard existing.phase == .setCompleted,
                  existing.confirmationUntil == confirmationUntil,
                  Date() >= confirmationUntil else { return }

            let now = Date()
            let phase: WorkoutActivityAttributes.Phase
            if existing.nextSet == nil {
                phase = .finished
            } else if existing.isRestPaused || existing.restTimerEnd.map({ now < $0 }) == true {
                phase = .resting
            } else {
                phase = .currentSet
            }

            let state = WorkoutActivityAttributes.ContentState(
                phase: phase,
                displaySet: existing.displaySet,
                nextSet: existing.nextSet,
                confirmationUntil: nil,
                restTimerStart: phase == .finished ? nil : existing.restTimerStart,
                restTimerEnd: phase == .finished ? nil : existing.restTimerEnd,
                completedSets: existing.completedSets,
                totalSets: existing.totalSets,
                pausedRestRemaining: phase == .finished ? nil : existing.pausedRestRemaining
            )
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: self.staleDate(for: state),
                    relevanceScore: 100
                )
            )
        }
    }

    /// Ask ActivityKit to invalidate the presentation at each time-driven phase boundary.
    /// The widget reads `context.isStale`, which gives the system a supported reason to
    /// re-render even while the containing app is suspended.
    private func staleDate(
        for state: WorkoutActivityAttributes.ContentState
    ) -> Date? {
        switch state.phase {
        case .setCompleted:
            return state.confirmationUntil
        case .resting:
            return state.restTimerEnd
        case .currentSet, .finished:
            return nil
        }
    }

    private func beginBackgroundTask(
        for workoutID: String,
        token: UUID
    ) -> UIBackgroundTaskIdentifier {
        let begin = {
            UIApplication.shared.beginBackgroundTask(withName: "Workout Live Activity confirmation") { [weak self] in
                self?.confirmationTransitionExpired(for: workoutID, token: token)
            }
        }
        if Thread.isMainThread {
            return begin()
        }
        return DispatchQueue.main.sync(execute: begin)
    }

    private func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid else { return }
        if Thread.isMainThread {
            UIApplication.shared.endBackgroundTask(identifier)
        } else {
            DispatchQueue.main.sync {
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
    }

    private func confirmationTransitionExpired(for workoutID: String, token: UUID) {
        guard let resources = removePendingConfirmationTransition(
            for: workoutID,
            token: token
        ) else { return }
        resources.workItem?.cancel()
        endBackgroundTask(resources.backgroundTaskIdentifier)
    }

    private func finishConfirmationTransition(for workoutID: String, token: UUID) {
        guard let resources = removePendingConfirmationTransition(
            for: workoutID,
            token: token
        ) else { return }
        resources.workItem?.cancel()
        endBackgroundTask(resources.backgroundTaskIdentifier)
    }

    private func replacePendingConfirmationTransition(
        for workoutID: String,
        confirmationUntil: Date
    ) -> UUID {
        let token = UUID()
        let pending = PendingConfirmationTransition(
            token: token,
            confirmationUntil: confirmationUntil,
            workItem: nil,
            backgroundTaskIdentifier: .invalid
        )

        confirmationTransitionLock.lock()
        let previous = pendingConfirmationTransitions.updateValue(
            pending,
            forKey: workoutID
        )
        confirmationTransitionLock.unlock()

        cancelConfirmationTransitionResources(previous.map {
            ConfirmationTransitionResources(
                workItem: $0.workItem,
                backgroundTaskIdentifier: $0.backgroundTaskIdentifier
            )
        })
        return token
    }

    private func cancelPendingConfirmationTransition(for workoutID: String) {
        let resources = removePendingConfirmationTransition(for: workoutID)
        cancelConfirmationTransitionResources(resources)
    }

    private func cancelConfirmationTransitionResources(
        _ resources: ConfirmationTransitionResources?
    ) {
        resources?.workItem?.cancel()
        if let backgroundTaskIdentifier = resources?.backgroundTaskIdentifier {
            endBackgroundTask(backgroundTaskIdentifier)
        }
    }

    private func hasPendingConfirmationTransition(for workoutID: String) -> Bool {
        confirmationTransitionLock.lock()
        defer { confirmationTransitionLock.unlock() }
        return pendingConfirmationTransitions[workoutID] != nil
    }

    private func hasPendingConfirmationTransition(
        for workoutID: String,
        confirmationUntil: Date,
        token: UUID
    ) -> Bool {
        confirmationTransitionLock.lock()
        defer { confirmationTransitionLock.unlock() }
        guard let pending = pendingConfirmationTransitions[workoutID] else { return false }
        return pending.token == token && pending.confirmationUntil == confirmationUntil
    }

    private func removePendingConfirmationTransition(
        for workoutID: String,
        token: UUID? = nil
    ) -> ConfirmationTransitionResources? {
        confirmationTransitionLock.lock()
        guard let pending = pendingConfirmationTransitions[workoutID],
              token == nil || pending.token == token else {
            confirmationTransitionLock.unlock()
            return nil
        }
        pendingConfirmationTransitions.removeValue(forKey: workoutID)
        confirmationTransitionLock.unlock()
        return ConfirmationTransitionResources(
            workItem: pending.workItem,
            backgroundTaskIdentifier: pending.backgroundTaskIdentifier
        )
    }

    /// ActivityKit requests, updates, and endings must retain call order. In particular,
    /// a workout can be cancelled before the asynchronous initial request has returned.
    private func enqueueActivityOperation(
        _ operation: @escaping () async -> Void
    ) {
        activityOperationLock.lock()
        let previousOperation = activityOperation
        let nextOperation = Task {
            await previousOperation?.value
            await operation()
        }
        activityOperation = nextOperation
        activityOperationLock.unlock()
    }

    private func activity(for workoutID: String) -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first {
            $0.attributes.workoutID == workoutID
        }
    }

    private func attributes(for workout: Workout) -> WorkoutActivityAttributes {
        WorkoutActivityAttributes(
            workoutID: identifier(for: workout),
            workoutTitle: workout.displayTitle(in: ExerciseStore.shared.exercises),
            workoutStart: workout.start ?? Date()
        )
    }

    private func identifier(for workout: Workout) -> String {
        workout.uuid?.uuidString ?? workout.objectID.uriRepresentation().absoluteString
    }

    private func setIdentifier(_ set: WorkoutSet) -> String {
        set.uuid?.uuidString ?? set.objectID.uriRepresentation().absoluteString
    }

    private func snapshot(
        for set: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> WorkoutActivityAttributes.SetSnapshot {
        let sets = workoutExercise.workoutSets?.array.compactMap { $0 as? WorkoutSet }
            .filter { !$0.isDeleted } ?? []
        let setIndex = sets.firstIndex { $0.objectID == set.objectID } ?? 0
        let exercise = workoutExercise.exercise(in: ExerciseStore.shared.exercises)
        let exerciseName = exercise?.title ?? "Exercise"
        let artworkFileName = [exercise?.imageURL, exercise?.animationURL]
            .compactMap { $0 }
            .compactMap { ExerciseMediaStore.shared.liveActivityArtworkFileName(for: $0) }
            .first
        return WorkoutActivityAttributes.SetSnapshot(
            setID: set.uuid?.uuidString ?? set.objectID.uriRepresentation().absoluteString,
            exerciseName: exerciseName,
            setNumber: setIndex + 1,
            setCount: max(sets.count, 1),
            result: set.resultTitle(weightUnit: SettingsStore.shared.weightUnit),
            artworkFileName: artworkFileName
        )
    }

    private func nextIncompleteSnapshot(
        after set: WorkoutSet,
        in workout: Workout
    ) -> WorkoutActivityAttributes.SetSnapshot? {
        let flattened = flattenedSets(in: workout)
        guard let completedIndex = flattened.firstIndex(where: { $0.set.objectID == set.objectID }) else {
            return flattened.first(where: { !$0.set.isCompleted }).map {
                snapshot(for: $0.set, in: $0.exercise)
            }
        }

        let after = flattened.dropFirst(completedIndex + 1).first(where: { !$0.set.isCompleted })
        let next = after ?? flattened.first(where: { !$0.set.isCompleted })
        return next.map { snapshot(for: $0.set, in: $0.exercise) }
    }

    private func flattenedSets(
        in workout: Workout
    ) -> [(exercise: WorkoutExercise, set: WorkoutSet)] {
        let exercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise }
            .filter { !$0.isDeleted } ?? []
        return exercises.flatMap { exercise in
            let sets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet }
                .filter { !$0.isDeleted } ?? []
            return sets.map { (exercise, $0) }
        }
    }

    private func setCounts(in workout: Workout) -> (completed: Int, total: Int) {
        let sets = flattenedSets(in: workout).map(\.set)
        return (sets.filter(\.isCompleted).count, sets.count)
    }
}

/// Entry point used by Live Activity App Intents. `LiveActivityIntent` runs in the
/// containing app process, so this keeps notifications, Watch sync, the in-app timer,
/// and ActivityKit content on the same source of truth.
@available(iOS 17.0, *)
@MainActor
enum WorkoutLiveActivityIntentHandler {
    static func completeSet(workoutID: String, setID: String) {
        guard let workout = matchingCurrentWorkout(workoutID: workoutID),
              let (workoutExercise, set) = matchingSet(setID: setID, in: workout),
              !set.isCompleted,
              let context = set.managedObjectContext else { return }

        do {
            try persistCompletion(set: set, workout: workout, at: Date()) {
                try context.save()
            }
        } catch {
            os_log(
                "Could not complete workout set from Live Activity: %@",
                log: .workoutData,
                type: .error,
                error.localizedDescription
            )
            return
        }

        if SettingsStore.shared.autoStartRestTimer {
            RestTimerStore.shared.start(duration: restTimerDuration(for: workoutExercise))
        }
        WatchConnectionManager.shared.syncCurrentWorkoutSnapshot()
        WorkoutLiveActivityManager.shared.setCompleted(
            set,
            in: workoutExercise,
            workout: workout
        )
    }

    /// Mutates and saves only the fields owned by the completion action. A
    /// failed save restores those fields without rolling back unrelated edits
    /// already pending in the managed object context.
    static func persistCompletion(
        set: WorkoutSet,
        workout: Workout,
        at date: Date,
        save: () throws -> Void
    ) throws {
        let previousIsCompleted = set.isCompleted
        let previousCompletedAt = set.completedAt
        let previousWorkoutStart = workout.start

        set.isCompleted = true
        set.completedAt = date
        workout.start = workout.start ?? date

        do {
            try save()
        } catch {
            set.isCompleted = previousIsCompleted
            set.completedAt = previousCompletedAt
            workout.start = previousWorkoutStart
            throw error
        }
    }

    static func adjustRestTimer(workoutID: String, by interval: TimeInterval) {
        guard let workout = matchingCurrentWorkout(workoutID: workoutID) else { return }
        RestTimerStore.shared.adjust(by: interval)
        WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
    }

    static func skipRestTimer(workoutID: String) {
        guard let workout = matchingCurrentWorkout(workoutID: workoutID) else { return }
        RestTimerStore.shared.cancel()
        WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
    }

    static func resumeRestTimer(workoutID: String) {
        guard let workout = matchingCurrentWorkout(workoutID: workoutID),
              RestTimerStore.shared.isPaused else { return }
        RestTimerStore.shared.resume()
        WorkoutLiveActivityManager.shared.refreshRestTimer(for: workout)
    }

    private static func matchingSet(
        setID: String,
        in workout: Workout
    ) -> (WorkoutExercise, WorkoutSet)? {
        let exercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise }
            .filter { !$0.isDeleted } ?? []
        for exercise in exercises {
            let sets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet }
                .filter { !$0.isDeleted } ?? []
            if let set = sets.first(where: {
                ($0.uuid?.uuidString ?? $0.objectID.uriRepresentation().absoluteString) == setID
            }) {
                return (exercise, set)
            }
        }
        return nil
    }

    private static func restTimerDuration(for workoutExercise: WorkoutExercise) -> TimeInterval {
        if let duration = workoutExercise.restTimerDurationValue { return duration }
        switch workoutExercise.exercise(in: ExerciseStore.shared.exercises)?.type {
        case .barbell:
            return SettingsStore.shared.defaultRestTimeBarbellBased
        case .dumbbell:
            return SettingsStore.shared.defaultRestTimeDumbbellBased
        default:
            return SettingsStore.shared.defaultRestTime
        }
    }

    private static func matchingCurrentWorkout(workoutID: String) -> Workout? {
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        guard let workout = try? context.fetch(Workout.currentWorkoutFetchRequest).first else {
            return nil
        }
        let identifier = workout.uuid?.uuidString
            ?? workout.objectID.uriRepresentation().absoluteString
        return identifier == workoutID ? workout : nil
    }
}

import CoreData
extension Workout {
    func startOrCrash(startWatchCompanionErrorHandler: WatchConnectionManager.StartWatchCompanionErrorHandler? = nil) {
        do {
            os_log("Starting workout", log: .workoutData)
            try start(startWatchCompanionErrorHandler: startWatchCompanionErrorHandler)
        } catch {
            let errorDescription = NSManagedObjectContext.descriptionWithDetailedErrors(error: error as NSError)
            os_log("Could not start workout: %@", log: .workoutData, type: .error, errorDescription)
            fatalError("Could not start workout: \(errorDescription)")
        }
    }
    
    func cancelOrCrash() {
        do {
            os_log("Cancelling workout", log: .workoutData)
            try cancel()
        } catch {
            let errorDescription = NSManagedObjectContext.descriptionWithDetailedErrors(error: error as NSError)
            os_log("Could not cancel workout: %@", log: .workoutData, type: .error, errorDescription)
            fatalError("Could not cancel workout: \(errorDescription)")
        }
    }
    
    func finishOrCrash() {
        finishOrCrash(syncToHealth: true)
    }

    func finishOrCrash(syncToHealth: Bool) {
        do {
            os_log("Finishing workout", log: .workoutData)
            try finish(syncToHealth: syncToHealth)
        } catch {
            let errorDescription = NSManagedObjectContext.descriptionWithDetailedErrors(error: error as NSError)
            os_log("Could not finish workout: %@", log: .workoutData, type: .error, errorDescription)
            fatalError("Could not finish workout: \(errorDescription)")
        }
    }
    
    func deleteOrCrash() {
        do {
            os_log("Deleting workout", log: .workoutData)
            try delete()
        } catch {
            let errorDescription = NSManagedObjectContext.descriptionWithDetailedErrors(error: error as NSError)
            os_log("Could not delete workout: %@", log: .workoutData, type: .error, errorDescription)
            fatalError("Could not delete workout: \(errorDescription)")
        }
    }
}
