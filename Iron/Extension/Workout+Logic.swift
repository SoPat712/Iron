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
    
    func start(startWatchCompanionErrorHandler: WatchConnectionManager.StartWatchCompanionErrorHandler? = nil) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to start workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to start workout without context")
            return
        }

        start = Date()
        isCurrentWorkout = true
        try context.save() // this also checks that there is only one currentWorkout

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
    
    func cancel() throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to cancel workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to cancel workout without context")
            return
        }
        
        RestTimerStore.shared.cancel()
        WorkoutLiveActivityManager.shared.end(for: self, completed: false)
        
        if WatchConnectionManager.shared.currentWatchWorkoutUuid != nil, let uuid = uuid {
            WatchConnectionManager.shared.discardWatchWorkout(uuid: uuid)
        }
        
        // the user did not go through with the workout, we should remove our previous donation
        Shortcuts.deleteStartWorkoutInteractionDonation(for: self)
        
        context.delete(self)
        try context.save()
    }
    
    func finish() throws {
        try finish(syncToHealth: true)
    }

    /// Finishes the local workout while allowing the completion editor to opt
    /// out of phone-originated HealthKit export. A workout already running on
    /// Apple Watch must still be ended on the watch; watchOS owns that active
    /// HealthKit session.
    func finish(syncToHealth: Bool) throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to finish workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to finish workout without context")
            return
        }
        
        try context.save() // just in case something goes wrong
        
        RestTimerStore.shared.cancel()
        
        deleteExercisesWhereAllSetsAreUncompleted()
        deleteUncompletedSets()
        start = safeStart // start/end should already be set, but just to be safe
        end = safeEnd
        isCurrentWorkout = false
        try context.save()

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
    
    func delete() throws {
        guard let context = managedObjectContext else {
            os_log("Attempt to delete workout without context", log: .workoutData, type: .error)
            assertionFailure("Attempt to delete workout without context")
            return
        }
        
        HealthManager.shared.deleteWorkout(workout: self)
        
        Shortcuts.deleteStartWorkoutInteractionDonation(for: self)
        
        context.delete(self)
        try context.save()
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

    private let confirmationTransitionLock = NSLock()
    private var pendingConfirmationTransitions: [String: PendingConfirmationTransition] = [:]

    private init() {}

    func startOrUpdate(for workout: Workout, preservingTransition: Bool = true) {
        let workoutID = identifier(for: workout)
        if preservingTransition,
           let activity = activity(for: workoutID) {
            let existing = activity.content.state
            let resolvedPhase = existing.resolvedPhase(at: Date())
            if existing.phase == .setCompleted, let confirmationUntil = existing.confirmationUntil {
                publish(attributes: activity.attributes, state: existing)
                ensureConfirmationTransition(
                    for: workoutID,
                    confirmationUntil: confirmationUntil
                )
                return
            }
            if resolvedPhase == .resting {
                cancelPendingConfirmationTransition(for: workoutID)
                publish(attributes: activity.attributes, state: existing)
                return
            }
        }

        cancelPendingConfirmationTransition(for: workoutID)
        guard let payload = currentPayload(for: workout) else { return }
        publish(attributes: payload.attributes, state: payload.state)
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
            totalSets: counts.total
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
        let workoutID = identifier(for: workout)
        guard let activity = activity(for: workoutID) else {
            cancelPendingConfirmationTransition(for: workoutID)
            guard let payload = currentPayload(for: workout) else { return }
            let restTimerStart = RestTimerStore.shared.restTimerStart
            let restTimerEnd = RestTimerStore.shared.restTimerEnd
            let state = WorkoutActivityAttributes.ContentState(
                phase: restTimerEnd != nil && payload.state.nextSet != nil
                    ? .resting
                    : payload.state.phase,
                displaySet: payload.state.displaySet,
                nextSet: payload.state.nextSet,
                confirmationUntil: nil,
                restTimerStart: restTimerStart,
                restTimerEnd: restTimerEnd,
                completedSets: payload.state.completedSets,
                totalSets: payload.state.totalSets
            )
            publish(attributes: payload.attributes, state: state)
            return
        }

        let existing = activity.content.state
        let resolvedPhase = existing.resolvedPhase(at: Date())
        let restTimerStart = RestTimerStore.shared.restTimerStart
        let restTimerEnd = RestTimerStore.shared.restTimerEnd
        let phase: WorkoutActivityAttributes.Phase
        if resolvedPhase == .setCompleted {
            phase = .setCompleted
        } else if restTimerEnd != nil, existing.nextSet != nil {
            phase = .resting
        } else if resolvedPhase == .resting {
            phase = existing.nextSet == nil ? .finished : .currentSet
        } else {
            phase = resolvedPhase
        }
        let state = WorkoutActivityAttributes.ContentState(
            phase: phase,
            displaySet: existing.displaySet,
            nextSet: existing.nextSet,
            confirmationUntil: phase == .setCompleted ? existing.confirmationUntil : nil,
            restTimerStart: restTimerStart,
            restTimerEnd: restTimerEnd,
            completedSets: existing.completedSets,
            totalSets: existing.totalSets
        )

        let transitionToken: UUID?
        if phase == .setCompleted, let confirmationUntil = existing.confirmationUntil {
            transitionToken = replacePendingConfirmationTransition(
                for: workoutID,
                confirmationUntil: confirmationUntil
            )
        } else {
            cancelPendingConfirmationTransition(for: workoutID)
            transitionToken = nil
        }
        publish(attributes: activity.attributes, state: state)
        if let transitionToken, let confirmationUntil = state.confirmationUntil {
            scheduleConfirmationTransition(
                for: workoutID,
                confirmationUntil: confirmationUntil,
                token: transitionToken
            )
        }
    }

    func refreshCurrentWorkoutRestTimer() {
        let context = WorkoutDataStorage.shared.persistentContainer.viewContext
        guard let workout = (try? context.fetch(Workout.currentWorkoutFetchRequest))?.first else { return }
        refreshRestTimer(for: workout)
    }

    func end(for workout: Workout, completed: Bool) {
        let workoutID = identifier(for: workout)
        cancelPendingConfirmationTransition(for: workoutID)
        let counts = setCounts(in: workout)
        let fallbackSet = currentPayload(for: workout)?.state.displaySet
        let dismissalPolicy: ActivityUIDismissalPolicy = completed
            ? .after(Date().addingTimeInterval(30))
            : .immediate

        enqueueActivityOperation {
            guard let activity = self.activity(for: workoutID) else { return }
            let finalState = WorkoutActivityAttributes.ContentState(
                phase: .finished,
                displaySet: activity.content.state.visibleSet(at: Date()) ?? fallbackSet,
                nextSet: nil,
                confirmationUntil: nil,
                restTimerStart: nil,
                restTimerEnd: nil,
                completedSets: counts.completed,
                totalSets: counts.total
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
        let flattenedSets = flattenedSets(in: workout)
        let current = flattenedSets.first(where: { !$0.set.isCompleted })
        let currentSnapshot = current.map { snapshot(for: $0.set, in: $0.exercise) }
        let fallbackSnapshot = flattenedSets.last.map { snapshot(for: $0.set, in: $0.exercise) }
        let counts = setCounts(in: workout)
        let phase: WorkoutActivityAttributes.Phase = current == nil && !flattenedSets.isEmpty
            ? .finished
            : .currentSet
        return (
            attributes: attributes(for: workout),
            state: WorkoutActivityAttributes.ContentState(
                phase: phase,
                displaySet: currentSnapshot ?? fallbackSnapshot,
                nextSet: currentSnapshot,
                confirmationUntil: nil,
                restTimerStart: nil,
                restTimerEnd: nil,
                completedSets: counts.completed,
                totalSets: counts.total
            )
        )
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
            } else if let restTimerEnd = existing.restTimerEnd, now < restTimerEnd {
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
                totalSets: existing.totalSets
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

    private func snapshot(
        for set: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> WorkoutActivityAttributes.SetSnapshot {
        let sets = workoutExercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
        let setIndex = sets.firstIndex { $0.objectID == set.objectID } ?? 0
        let exerciseName = workoutExercise.exercise(in: ExerciseStore.shared.exercises)?.title ?? "Exercise"
        return WorkoutActivityAttributes.SetSnapshot(
            setID: set.uuid?.uuidString ?? set.objectID.uriRepresentation().absoluteString,
            exerciseName: exerciseName,
            setNumber: setIndex + 1,
            setCount: max(sets.count, 1),
            result: set.resultTitle(weightUnit: SettingsStore.shared.weightUnit)
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
        let exercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
        return exercises.flatMap { exercise in
            let sets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
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

        set.isCompleted = true
        set.completedAt = Date()
        workout.start = workout.start ?? Date()

        if SettingsStore.shared.autoStartRestTimer {
            RestTimerStore.shared.start(duration: restTimerDuration(for: workoutExercise))
        }

        do {
            try context.save()
        } catch {
            os_log(
                "Could not complete workout set from Live Activity: %@",
                log: .workoutData,
                type: .error,
                error.localizedDescription
            )
            return
        }

        WatchConnectionManager.shared.syncCurrentWorkoutSnapshot()
        WorkoutLiveActivityManager.shared.setCompleted(
            set,
            in: workoutExercise,
            workout: workout
        )
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

    private static func matchingSet(
        setID: String,
        in workout: Workout
    ) -> (WorkoutExercise, WorkoutSet)? {
        let exercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
        for exercise in exercises {
            let sets = exercise.workoutSets?.array.compactMap { $0 as? WorkoutSet } ?? []
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
