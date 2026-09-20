//
//  WidgetKind.swift
//  Iron
//
//  Created by Karim Abou Zeid on 12.10.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import WidgetKit
import AppIntents
import os.log
#if canImport(ActivityKit)
import ActivityKit
#endif

enum WidgetKind: String {
    case lastWorkout
}

#if canImport(ActivityKit)
/// The value-only contract shared by Iron and its WidgetKit extension.
/// Keep this payload compact: ActivityKit limits static and dynamic data to 4 KB.
@available(iOS 16.1, *)
struct WorkoutActivityAttributes: ActivityAttributes {
    struct SetSnapshot: Codable, Hashable {
        let setID: String
        let exerciseName: String
        let setNumber: Int
        let setCount: Int
        let result: String
    }

    enum Phase: String, Codable, Hashable {
        case currentSet
        case setCompleted
        case resting
        case finished
    }

    struct ContentState: Codable, Hashable {
        let phase: Phase
        let displaySet: SetSnapshot?
        let nextSet: SetSnapshot?
        let confirmationUntil: Date?
        let restTimerStart: Date?
        let restTimerEnd: Date?
        let completedSets: Int
        let totalSets: Int

        /// Resolve time-driven presentation locally so the Live Activity can advance while
        /// the containing app is suspended. App-side ActivityKit updates still reconcile state.
        func resolvedPhase(at date: Date) -> Phase {
            switch phase {
            case .setCompleted:
                if let confirmationUntil, date < confirmationUntil {
                    return .setCompleted
                }
                guard nextSet != nil else { return .finished }
                if let restTimerEnd, date < restTimerEnd {
                    return .resting
                }
                return .currentSet
            case .resting:
                guard nextSet != nil else { return .finished }
                if let restTimerEnd, date < restTimerEnd {
                    return .resting
                }
                return .currentSet
            case .currentSet, .finished:
                return phase
            }
        }

        func visibleSet(at date: Date) -> SetSnapshot? {
            switch resolvedPhase(at: date) {
            case .setCompleted:
                return displaySet
            case .currentSet, .resting:
                return nextSet ?? displaySet
            case .finished:
                return displaySet
            }
        }

        func restProgress(at date: Date) -> Double? {
            guard let restTimerStart, let restTimerEnd, restTimerEnd > restTimerStart else {
                return nil
            }
            let duration = restTimerEnd.timeIntervalSince(restTimerStart)
            let elapsed = date.timeIntervalSince(restTimerStart)
            return min(max(elapsed / duration, 0), 1)
        }
    }

    let workoutID: String
    let workoutTitle: String
    let workoutStart: Date
}

@available(iOS 17.0, *)
struct CompleteWorkoutSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete Workout Set"
    static var description = IntentDescription("Marks the displayed Iron workout set complete.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Workout ID")
    var workoutID: String

    @Parameter(title: "Set ID")
    var setID: String

    init() {
        workoutID = ""
        setID = ""
    }

    init(workoutID: String, setID: String) {
        self.workoutID = workoutID
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        #if IRON_WIDGET_EXTENSION
        // The system executes this LiveActivityIntent in the containing app.
        #else
        await WorkoutLiveActivityIntentHandler.completeSet(
            workoutID: workoutID,
            setID: setID
        )
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct AdjustWorkoutRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust Workout Rest Timer"
    static var description = IntentDescription("Adds or removes time from Iron's active rest timer.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Workout ID")
    var workoutID: String

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {
        workoutID = ""
        seconds = 0
    }

    init(workoutID: String, seconds: Int) {
        self.workoutID = workoutID
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        #if IRON_WIDGET_EXTENSION
        // LiveActivityIntent is performed by the containing app. This copy exists so
        // the widget extension can archive the button's intent metadata.
        #else
        await WorkoutLiveActivityIntentHandler.adjustRestTimer(
            workoutID: workoutID,
            by: TimeInterval(seconds)
        )
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct SkipWorkoutRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Workout Rest Timer"
    static var description = IntentDescription("Skips Iron's active rest timer.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Workout ID")
    var workoutID: String

    init() {
        workoutID = ""
    }

    init(workoutID: String) {
        self.workoutID = workoutID
    }

    func perform() async throws -> some IntentResult {
        #if IRON_WIDGET_EXTENSION
        // See AdjustWorkoutRestTimerIntent.perform().
        #else
        await WorkoutLiveActivityIntentHandler.skipRestTimer(workoutID: workoutID)
        #endif
        return .result()
    }
}
#endif

@available(iOS 14.0, *)
extension WidgetKind {
    func reloadTimelines() {
        os_log("Reload timeline", log: .widgets, type: .debug)
        WidgetCenter.shared.reloadTimelines(ofKind: rawValue)
    }
}
