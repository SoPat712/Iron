//
//  IronApp.swift
//  IronWatch WatchKit Extension
//
//  Created by Karim Abou Zeid on 27.05.22.
//

import SwiftUI

@main
struct IronApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    init() {
        #if DEBUG && targetEnvironment(simulator)
        WatchFocusDemo.seedIfRequested()
        #endif
    }

    @SceneBuilder var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG && targetEnvironment(simulator)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("--large-watch-text") { size = .accessibility3 }
                }
                .transformEnvironment(\.isLuminanceReduced) { value in
                    if ProcessInfo.processInfo.arguments.contains("--watch-aod-demo") { value = true }
                }
                .transformEnvironment(\.redactionReasons) { reasons in
                    if ProcessInfo.processInfo.arguments.contains("--watch-aod-demo") { reasons.insert(.privacy) }
                }
                #endif
                .preferredColorScheme(.dark)
                .tint(IronTheme.accent)
        }
    }
}

import HealthKit
import os.log

class AppDelegate: NSObject, WKApplicationDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "watch")
    
    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        Self.logger.log("Checking whether active workout session can be recovered")
        handleActiveWorkoutRecovery() // somehow this isn't automatically called by the system?! last checked watchOS 8
        _ = NotificationManager.shared
    }

    func handle(_ userActivity: NSUserActivity) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .lightOpenWorkout, object: nil)
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                refreshConnectivity()
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Re-attach the delegate and drain Iron's durable event outbox
                // before releasing the connectivity wake-up. This lets edits
                // made offline progress without requiring a foreground launch.
                refreshConnectivity()
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                // Be sure to complete the relevant-shortcut task once you're done.
                relevantShortcutTask.setTaskCompletedWithSnapshot(false)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                // Be sure to complete the intent-did-run task once you're done.
                intentDidRunTask.setTaskCompletedWithSnapshot(false)
            default:
                // make sure to complete unhandled task types
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func refreshConnectivity() {
        let connection = PhoneConnectionManager.shared
        if !connection.isActivated {
            connection.activateSession()
        }
        connection.flushEventOutbox()
    }
    
    func handleActiveWorkoutRecovery() {
        Self.logger.log("Recovering active workout session")
        WorkoutSessionManager.healthStore.recoverActiveWorkoutSession { workoutSession, error in
            guard let workoutSession = workoutSession else {
                WorkoutSessionManagerStore.shared.finishRecordingRecovery()
                if let error = error {
                    Self.logger.error("Could not recover active workout session: \(error.localizedDescription)")
                } else {
                    Self.logger.info("No active workout session to recover")
                }
                PhoneConnectionManager.shared.activateSession()
                return
            }
            Self.logger.info("Successfully recovered active workout session")
            WorkoutSessionManagerStore.shared.recoverWorkoutSession(workoutSession: workoutSession) {
                PhoneConnectionManager.shared.activateSession()
            }
        }
    }
    
    /// from `HKHealthStore.startWatchApp`
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        PhoneConnectionManager.shared.handlePrepareWorkoutSession(workoutConfiguration)
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Disposable simulator fixtures. Never present in a device or Release build.
private enum WatchFocusDemo {
    static func seedIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--light-watch-demo"), args.indices.contains(flag + 1) else { return }
        let mode = args[flag + 1]
        let catalog = WatchBundledLibrary.load().exercises
        let group = UUID()
        func exercise(_ name: String, index: Int) -> WatchWorkoutExercise {
            let pick = catalog.first { $0.name.localizedCaseInsensitiveContains(name) }
            return WatchWorkoutExercise(order: index, name: pick?.name ?? name,
                sets: (1...3).map { WatchWorkoutSet(order: $0, weight: 135, reps: 8,
                    previousWeight: 130, previousReps: 8, completed: index == 1 && $0 == 1) },
                restTimerDuration: 90, muscleGroup: pick?.muscle, exerciseUuid: pick?.id, imageURL: pick?.imageURL,
                supersetID: group, comment: "Controlled tempo")
        }
        let exercises = [exercise("Barbell Bench Press", index: 1), exercise("Dumbbell Row", index: 2)]
        var snapshot = WatchWorkoutSnapshot(workoutID: UUID(), title: "Upper Body", startDate: Date().addingTimeInterval(-240),
            exercises: exercises, restTimerEnd: mode == "rest" ? Date().addingTimeInterval(90) : nil, weightUnit: .pound)
        snapshot.selectedSetID = WatchWorkoutEditing.nextSet(in: snapshot)
        if mode == "empty" { snapshot.exercises = [] }
        if mode == "complete" {
            for e in snapshot.exercises.indices { for s in snapshot.exercises[e].sets.indices { snapshot.exercises[e].sets[s].completed = true } }
        }
        var history = snapshot
        history.workoutID = UUID(); history.startDate = Date().addingTimeInterval(-90_000)
        history.endDate = history.startDate.addingTimeInterval(2_400); history.isFinished = true
        let saved = WatchSavedWorkout(id: UUID(), title: "Upper Body", exercises: exercises, weightUnit: .pound,
            comment: "Saved workout", updatedAt: Date())
        do {
            try WatchWorkoutStore.shared.clear()
            try WatchWorkoutStore.shared.replaceLibrary(WatchWorkoutLibrary(generatedAt: Date(), exercises: catalog,
                savedWorkouts: [saved], history: [history], weightUnit: .pound))
            if mode != "home" { try WatchWorkoutStore.shared.replaceSnapshot(snapshot) }
        } catch { assertionFailure("Could not prepare Watch fixture: \(error)") }
    }
}
#endif

extension Notification.Name {
    static let lightOpenWorkout = Notification.Name("Light.openWorkout")
}
