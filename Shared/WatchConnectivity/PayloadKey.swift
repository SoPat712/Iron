//
//  PayloadKey.swift
//  Iron
//
//  Created by Karim Abou Zeid on 04.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

enum PayloadKey {
    // phone --> watch
    // calls healthStore.startWatchApp()
    
    // phone <-- watch
    // Args: true
    static let preparedWorkoutSession = "preparedWorkoutSession" // sent to confirm that healthStore.startWatchApp() resulted in a prepare
    
    // phone --> watch
    // Args: true
    static let ignoredPreparedWorkoutSession = "ignoredPreparedWorkoutSession" // send if the prepared message came to late, i.e. after the workout was already canceled / finished
    
    // phone --> watch
    // Args: [start: Date, uuid: UUID]
    static let startWorkoutSession = "startWorkoutSession"
    
    // phone --> watch
    // Args: [start: Date, uuid: UUID]
    static let updateWorkoutSessionStart = "updateWorkoutSessionStart"
    
    // phone --> watch
    // Args: [end: Date?, uuid: UUID]
    static let updateWorkoutSessionEnd = "updateWorkoutSessionEnd"
    
    // phone --> watch
    // Args: [end: Date?, keepRestTimerRunning: Bool?, uuid: UUID]
    static let updateWorkoutSessionRestTimer = "updateWorkoutSessionRestTimer"
    
    // phone --> watch
    // Args: [text: String, uuid: UUID] // TODO: replace with [reps: Int, weight: Double, uuid: UUID]
    static let updateWorkoutSessionSelectedSet = "updateWorkoutSessionSelectedSet"
    
    // phone --> watch
    // Args: [start: Date, end: Date, title: String?, uuid: UUID]
    static let endWorkoutSession = "endWorkoutSession"
    
    // phone --> watch
    // Args: [uuid: UUID]
    static let discardWorkoutSession = "discardWorkoutSession"

    // phone <--> watch
    // Args: Data containing a WatchWorkoutSnapshot / WatchWorkoutEventAck
    static let workoutSnapshot = "workoutSnapshot"
    static let workoutEventAck = "workoutEventAck"

    // watch --> phone
    // Args: Data containing a WatchWorkoutEvent
    static let workoutEvent = "workoutEvent"
    
    enum Arg {
        static let start = "start" // Date
        static let end = "end" // Date
        static let keepRestTimerRunning = "keepRestTimerRunning" // Bool
        static let text = "text" // String
        static let title = "title" // String
        static let uuid = "uuid" // UUID
        static let data = "data" // Data
    }
}

/// The wire format is deliberately kept in the shared target.  WatchConnectivity
/// only transports property-list values, so snapshots/events are carried as JSON
/// Data and can be sent through either application context, message, or user info.
enum WatchWorkoutWire {
    static let schemaVersion = 1

    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}

struct WatchWorkoutSet: Codable, Identifiable, Equatable {
    let id: UUID
    var order: Int
    var weight: Double?
    var reps: Int?
    var rpe: Double?
    var previousWeight: Double?
    var previousReps: Int?
    var completed: Bool

    init(id: UUID = UUID(), order: Int, weight: Double? = nil, reps: Int? = nil,
         rpe: Double? = nil, previousWeight: Double? = nil,
         previousReps: Int? = nil, completed: Bool = false) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.previousWeight = previousWeight
        self.previousReps = previousReps
        self.completed = completed
    }

    var displayText: String {
        let weightText = positiveWeight.map(Self.numberText)
        let repsText = positiveReps.map(String.init)

        switch (weightText, repsText) {
        case let (.some(weight), .some(reps)):
            return "\(weight) × \(reps)"
        case let (.some(weight), .none):
            return weight
        case let (.none, .some(reps)):
            return "\(reps) reps"
        case (.none, .none):
            return "—"
        }
    }

    func displayText(weightUnit: WatchWorkoutWeightUnit) -> String {
        guard let weight = positiveWeight else { return displayText }
        let weightText = Self.numberText(weight)
        if let reps = positiveReps {
            return "\(weightText) \(weightUnit.symbol) × \(reps)"
        }
        return "\(weightText) \(weightUnit.symbol)"
    }

    func previousDisplayText(weightUnit: WatchWorkoutWeightUnit) -> String? {
        let previousWeight = self.previousWeight.flatMap { $0 > 0 ? $0 : nil }
        let previousReps = self.previousReps.flatMap { $0 > 0 ? $0 : nil }

        switch (previousWeight, previousReps) {
        case let (.some(weight), .some(reps)):
            return "\(Self.numberText(weight)) \(weightUnit.symbol) × \(reps)"
        case let (.some(weight), .none):
            return "\(Self.numberText(weight)) \(weightUnit.symbol)"
        case let (.none, .some(reps)):
            return "\(reps) reps"
        case (.none, .none):
            return nil
        }
    }

    private var positiveWeight: Double? {
        weight.flatMap { $0 > 0 ? $0 : nil }
    }

    private var positiveReps: Int? {
        reps.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func numberText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}

enum WatchWorkoutWeightUnit: String, Codable {
    case kilogram
    case pound

    var symbol: String {
        switch self {
        case .kilogram: return "kg"
        case .pound: return "lb"
        }
    }
}

struct WatchWorkoutExercise: Codable, Identifiable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var sets: [WatchWorkoutSet]
    /// Optional so snapshots written by older phone builds remain decodable.
    /// Keeping the configured recovery duration with the exercise lets the
    /// watch start its timer even while the phone is unreachable.
    var restTimerDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        order: Int,
        name: String,
        sets: [WatchWorkoutSet],
        restTimerDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.sets = sets
        self.restTimerDuration = restTimerDuration
    }
}

struct WatchWorkoutSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var workoutID: UUID
    var title: String?
    var startDate: Date
    var endDate: Date?
    var exercises: [WatchWorkoutExercise]
    var selectedSetID: UUID?
    var selectedSetText: String?
    var restTimerEnd: Date?
    var keepRestTimerRunning: Bool
    /// Optional so snapshots persisted by an older build remain decodable.
    var weightUnit: WatchWorkoutWeightUnit?
    /// Overall workout effort (1...10). Optional to keep persisted v1
    /// snapshots and snapshots from older phone/watch builds decodable.
    var sessionEffort: Double?
    var revision: Int64
    var updatedAt: Date

    init(workoutID: UUID, title: String? = nil, startDate: Date = Date(),
         endDate: Date? = nil, exercises: [WatchWorkoutExercise] = [],
         selectedSetID: UUID? = nil, selectedSetText: String? = nil,
         restTimerEnd: Date? = nil, keepRestTimerRunning: Bool = false,
         weightUnit: WatchWorkoutWeightUnit? = .kilogram,
         sessionEffort: Double? = nil,
         revision: Int64 = 0, updatedAt: Date = Date()) {
        self.schemaVersion = WatchWorkoutWire.schemaVersion
        self.workoutID = workoutID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.exercises = exercises
        self.selectedSetID = selectedSetID
        self.selectedSetText = selectedSetText
        self.restTimerEnd = restTimerEnd
        self.keepRestTimerRunning = keepRestTimerRunning
        self.weightUnit = weightUnit
        self.sessionEffort = sessionEffort
        self.revision = revision
        self.updatedAt = updatedAt
    }

    var selectedSet: (exercise: WatchWorkoutExercise, set: WatchWorkoutSet)? {
        guard let selectedSetID = selectedSetID else { return nil }
        for exercise in exercises {
            if let set = exercise.sets.first(where: { $0.id == selectedSetID }) {
                return (exercise, set)
            }
        }
        return nil
    }

    static func placeholder(workoutID: UUID, startDate: Date) -> WatchWorkoutSnapshot {
        let set = WatchWorkoutSet(order: 1)
        let exercise = WatchWorkoutExercise(order: 1, name: "Workout", sets: [set])
        return WatchWorkoutSnapshot(workoutID: workoutID, startDate: startDate,
                                    exercises: [exercise], selectedSetID: set.id)
    }
}

enum WatchWorkoutEventKind: String, Codable {
    case setUpdated
    case setCompletionChanged
    case restTimerUpdated
    case workoutFinished
    case workoutDiscarded
    case workoutFailed
}

struct WatchWorkoutEvent: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let workoutID: UUID
    let sequence: Int64
    let createdAt: Date
    let kind: WatchWorkoutEventKind
    var exerciseID: UUID?
    var setID: UUID?
    var weight: Double?
    var reps: Int?
    var rpe: Double?
    var completed: Bool?
    var restTimerEnd: Date?
    var keepRestTimerRunning: Bool?
    var startDate: Date?
    var endDate: Date?
    var title: String?
    /// The unit used for `weight`. Optional for compatibility with queued v1 events.
    var weightUnit: WatchWorkoutWeightUnit?
    /// Overall workout effort (1...10) captured when finishing on Apple Watch.
    /// Optional for compatibility with queued events from older builds.
    var sessionEffort: Double?
    /// Finish events include the watch's complete durable projection so a final
    /// set edit cannot be lost if WatchConnectivity delivers packets out of order.
    var snapshot: WatchWorkoutSnapshot?

    init(workoutID: UUID, sequence: Int64, kind: WatchWorkoutEventKind,
         exerciseID: UUID? = nil, setID: UUID? = nil, weight: Double? = nil,
         reps: Int? = nil, rpe: Double? = nil, completed: Bool? = nil,
         restTimerEnd: Date? = nil, keepRestTimerRunning: Bool? = nil,
         startDate: Date? = nil, endDate: Date? = nil, title: String? = nil,
         weightUnit: WatchWorkoutWeightUnit? = nil,
         sessionEffort: Double? = nil,
         snapshot: WatchWorkoutSnapshot? = nil,
         id: UUID = UUID(), createdAt: Date = Date()) {
        self.schemaVersion = WatchWorkoutWire.schemaVersion
        self.id = id
        self.workoutID = workoutID
        self.sequence = sequence
        self.createdAt = createdAt
        self.kind = kind
        self.exerciseID = exerciseID
        self.setID = setID
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completed = completed
        self.restTimerEnd = restTimerEnd
        self.keepRestTimerRunning = keepRestTimerRunning
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.weightUnit = weightUnit
        self.sessionEffort = sessionEffort
        self.snapshot = snapshot
    }
}

struct WatchWorkoutEventAck: Codable {
    let schemaVersion: Int
    let eventIDs: [UUID]

    init(eventIDs: [UUID]) {
        self.schemaVersion = WatchWorkoutWire.schemaVersion
        self.eventIDs = eventIDs
    }
}
