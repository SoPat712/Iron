//
//  WorkoutSessionManager.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 05.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import HealthKit
import Combine
import os.log

class WorkoutSessionManager: NSObject, ObservableObject {
    static let healthStore = HKHealthStore()
    
    var objectWillChange = ObservableObjectPublisher()
    
    var restTimerEnd: Date? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    var keepRestTimerRunning: Bool = false {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    var selectedSetText: String? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    private var _burnedCalories: Double? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    private var _mostRecentHeartRate: Double? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    private var _mostRecentHeartRateDate: Date? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    private var _startDate: Date? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    var startDate: Date? {
        get {
            _startDate ?? workoutBuilder.startDate
        }
        set {
            assert(newValue != nil)
            if newValue != startDate {
                print("overwriting startDate=\(startDate?.description ?? "nil") with \(newValue?.description ?? "nil")")
                _startDate = newValue
            } else {
                print("keeping startDate=\(startDate?.description ?? "nil") new value would be \(newValue?.description ?? "nil")")
            }
        }
    }
    
    private var _endDate: Date? {
        willSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    var endDate: Date? {
        get {
            _endDate ?? workoutBuilder.endDate
        }
        set {
            if newValue != endDate {
                print("overwriting endDate=\(endDate?.description ?? "nil") with \(newValue?.description ?? "nil")")
                _endDate = newValue
            } else {
                print("keeping endDate=\(endDate?.description ?? "nil") new value would be \(newValue?.description ?? "nil")")
            }
        }
    }
    
    private let workoutSession: HKWorkoutSession
    private let workoutBuilder: HKLiveWorkoutBuilder
    private var recoveredWorkoutID: UUID?
    private var pendingEnd: (date: Date, completion: (Result<HKWorkout, Error>) -> Void)?
    private var isFinalizingCollection = false
    private var isSavingWorkout = false

    var isFinalizingWorkout: Bool { pendingEnd != nil || isFinalizingCollection || isSavingWorkout }
    
    init(session: HKWorkoutSession) {
        workoutSession = session
        workoutBuilder = session.associatedWorkoutBuilder()
        
        super.init()
        
        workoutSession.delegate = self
        workoutBuilder.delegate = self
        
        // needs to be set again after active workout session recovery
        workoutBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: Self.healthStore, workoutConfiguration: workoutSession.workoutConfiguration)
        os_log("Types to collect: %@", type: .debug, workoutBuilder.dataSource?.typesToCollect ?? "nil")
    }
    
    // make sure everything that modifies the session or the builder runs on this serial queue
    static let accessQueue = DispatchQueue(label: "com.kabouzeid.workoutsessionmanagerqueue", qos: .userInitiated, target: .global(qos: .userInitiated))
    
    static func perform(_ block: @escaping () -> Void) {
        accessQueue.async {
            block()
        }
    }
    
    static func performAndWait(_ block: () -> Void) {
        accessQueue.sync {
            block()
        }
    }
    
    var state: HKWorkoutSessionState {
        workoutSession.state
    }
    
    var workoutConfiguration: HKWorkoutConfiguration {
        workoutSession.workoutConfiguration
    }

    func togglePause() {
        dispatchPrecondition(condition: .onQueue(Self.accessQueue))
        if state == .running { workoutSession.pause() }
        else if state == .paused { workoutSession.resume() }
    }
    
    var uuid: UUID? {
        if let uuidString = workoutBuilder.metadata[HKMetadataKeyExternalUUID] as? String,
           let uuid = UUID(uuidString: uuidString) { return uuid }
        return recoveredWorkoutID
    }

    /// A recovered live builder may not expose its existing metadata yet, and
    /// adding it again can fail while collection is running. Reuse the durable
    /// active projection locally; leave HealthKit's recording/metadata intact.
    func associateRecoveredWorkout(_ uuid: UUID) {
        dispatchPrecondition(condition: .onQueue(Self.accessQueue))
        guard self.uuid == nil, state == .running || state == .paused else { return }
        recoveredWorkoutID = uuid
    }
    
    func setUuid(_ uuid: UUID) throws {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        defer {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        try Self.requestWorkoutPermissions().get() // request permissions -- apparently needed for addMetadata
        let uuidSemaphore = DispatchSemaphore(value: 0)
        var uuidError: Error?
        workoutBuilder.addMetadata([HKMetadataKeyExternalUUID : uuid.uuidString], completion: { (success, error) in
            defer { uuidSemaphore.signal() }
            if !success {
                uuidError = error ?? NSError()
            }
        })
        uuidSemaphore.wait()
        if let error = uuidError {
            throw error
        }
    }
    
    func setTitle(_ title: String) throws { // there doesn't seem to be a way to undo this
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        try Self.requestWorkoutPermissions().get() // request permissions -- apparently needed for addMetadata
        let semaphore = DispatchSemaphore(value: 0)
        var _error: Error?
        workoutBuilder.addMetadata([HKMetadataKeyWorkoutBrandName : title], completion: { (success, error) in
            defer { semaphore.signal() }
            if !success {
                _error = error ?? NSError()
            }
        })
        semaphore.wait()
        if let error = _error {
            throw error
        }
    }
    
    func updateStartDate(_ startDate: Date) {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        // TODO safe the date in the workout meta data or shared prefs so it can be restored
        self.startDate = startDate
    }
    
    func updateEndDate(_ endDate: Date?) {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        // TODO safe the date in the workout meta data or shared prefs so it can be restored
        self.endDate = endDate
    }
    
    func prepare() {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        // prepare the workout
        workoutSession.prepare()
    }
    
    /**
     prepare() does not necessarily need to be called before
     */
    func start(start: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        // request permissions
        do {
            try Self.requestWorkoutPermissions().get()
        } catch {
            completion(.failure(error))
            return
        }
        
        defer {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        workoutSession.startActivity(with: start)
        os_log("Beginning collection")
        workoutBuilder.beginCollection(withStart: start, completion: { (success, error) in
            guard success else {
                completion(.failure(error ?? GenericError(description: "Could not begin collection of health samples")))
                return
            }
            completion(.success(()))
        })
    }
    
    func discard() {
        print(#function)
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        
        defer {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        let endCompletion = pendingEnd?.completion
        pendingEnd = nil
        isFinalizingCollection = false
        isSavingWorkout = false
        workoutSession.end()
        workoutBuilder.discardWorkout()
        endCompletion?(.failure(GenericError(description: "The workout was discarded while saving.")))
    }
    
    func end(end: Date, completion: @escaping (Result<HKWorkout, Error>) -> Void) {
        dispatchPrecondition(condition: DispatchPredicate.onQueue(Self.accessQueue))
        guard pendingEnd == nil else {
            completion(.failure(GenericError(description: "The workout is already being saved.")))
            return
        }
        guard state == .running || state == .paused || state == .stopped else {
            completion(.failure(GenericError(description: "The workout session is no longer active.")))
            return
        }
        pendingEnd = (end, completion)
        if state == .stopped {
            finalizeStoppedWorkout()
        } else {
            // Keep the session alive until the builder has saved its final
            // sensor samples. The delegate continues only after `.stopped`.
            workoutSession.stopActivity(with: end)
        }
    }

    private func finalizeStoppedWorkout() {
        dispatchPrecondition(condition: .onQueue(Self.accessQueue))
        guard let pendingEnd, !isFinalizingCollection else { return }
        isFinalizingCollection = true
        workoutBuilder.endCollection(withEnd: pendingEnd.date) { success, error in
            Self.perform {
                guard self.pendingEnd != nil, !self.isSavingWorkout else { return }
                guard success else {
                    self.completeEnd(.failure(error ?? GenericError(description: "Could not finish collecting workout samples.")))
                    return
                }
                // Read final statistics rather than assuming a last delegate
                // callback refreshed the UI's cached energy/heart rate.
                self.burnedCalories = self.getBurnedCalories(workoutBuilder: self.workoutBuilder)
                self.mostRecentHeartRate = self.getMostRecentHeartRate(workoutBuilder: self.workoutBuilder)
                self.mostRecentHeartRateDate = self.getMostRecentHeartRateDate(workoutBuilder: self.workoutBuilder)
                self.isSavingWorkout = true
                self.workoutBuilder.finishWorkout { workout, error in
                    Self.perform {
                        guard self.pendingEnd != nil else { return }
                        if let workout {
                            // A time edit remains in Light's projection. Keep
                            // HealthKit's actual sensor window and associations;
                            // replacing it with a totals-only copy loses detail.
                            self.completeEnd(.success(workout))
                        } else {
                            self.completeEnd(.failure(error ?? GenericError(description: "Could not save the workout in Apple Health.")))
                        }
                    }
                }
            }
        }
    }

    private func completeEnd(_ result: Result<HKWorkout, Error>) {
        dispatchPrecondition(condition: .onQueue(Self.accessQueue))
        guard let completion = pendingEnd?.completion else { return }
        pendingEnd = nil
        isFinalizingCollection = false
        isSavingWorkout = false
        workoutSession.end()
        DispatchQueue.main.async { self.objectWillChange.send() }
        completion(result)
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
//        print(#function)
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Self.perform {
            if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate),
               collectedTypes.contains(heartRate) {
                self.mostRecentHeartRate = self.getMostRecentHeartRate(workoutBuilder: workoutBuilder)
                self.mostRecentHeartRateDate = self.getMostRecentHeartRateDate(workoutBuilder: workoutBuilder)
            }
            if let activeEnergyBurned = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
               collectedTypes.contains(activeEnergyBurned) {
                self.burnedCalories = self.getBurnedCalories(workoutBuilder: workoutBuilder)
            }
            self.publishLiveMetrics()
        }
    }
}

extension WorkoutSessionManager {
    func publishLiveMetrics() {
        dispatchPrecondition(condition: .onQueue(Self.accessQueue))
        guard let uuid, state != .notStarted, state != .prepared else { return }
        let metrics = WatchWorkoutMetrics(
            workoutID: uuid,
            state: state == .running ? .running : (state == .paused ? .paused : .ended),
            heartRate: mostRecentHeartRate, heartRateDate: mostRecentHeartRateDate,
            activeEnergyKilocalories: burnedCalories
        )
        DispatchQueue.main.async { PhoneConnectionManager.shared.sendWorkoutMetrics(metrics) }
    }

    private func getBurnedCalories(workoutBuilder: HKWorkoutBuilder) -> Double? {
        guard let burnedCalories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        return workoutBuilder.statistics(for: burnedCalories)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }
    
    private func getMostRecentHeartRate(workoutBuilder: HKWorkoutBuilder) -> Double? {
        guard let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return workoutBuilder.statistics(for: heartRate)?.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
    }
    
    private func getMostRecentHeartRateDate(workoutBuilder: HKWorkoutBuilder) -> Date? {
        guard let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return workoutBuilder.statistics(for: heartRate)?.mostRecentQuantityDateInterval()?.end
    }
    
    var burnedCalories: Double? {
        get {
            if let burnedCalories = _burnedCalories {
                return burnedCalories
            }
            guard let burnedCalories = getBurnedCalories(workoutBuilder: workoutBuilder) else { return nil }
            _burnedCalories = burnedCalories
            return burnedCalories
        }
        set {
            _burnedCalories = newValue
        }
    }
    
    var mostRecentHeartRate: Double? {
        get {
            if let mostRecentHeartRate = _mostRecentHeartRate {
                return mostRecentHeartRate
            }
            guard let mostRecentHeartRate = getMostRecentHeartRate(workoutBuilder: workoutBuilder) else { return nil }
            _mostRecentHeartRate = mostRecentHeartRate
            return mostRecentHeartRate
        }
        set {
            _mostRecentHeartRate = newValue
        }
    }
    
    var mostRecentHeartRateDate: Date? {
        get {
            if let mostRecentHeartRateDate = _mostRecentHeartRateDate {
                return mostRecentHeartRateDate
            }
            guard let mostRecentHeartRateDate = getMostRecentHeartRateDate(workoutBuilder: workoutBuilder) else { return nil }
            _mostRecentHeartRateDate = mostRecentHeartRateDate
            return mostRecentHeartRateDate
        }
        set {
            _mostRecentHeartRateDate = newValue
        }
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        os_log("Workout session state changed to %@ from %@", toState.name, fromState.name)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        Self.perform { self.publishLiveMetrics() }
        WorkoutSessionManagerStore.shared.notifySyncStateChanged()
        if toState == .stopped {
            Self.perform { self.finalizeStoppedWorkout() }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        os_log("Workout session did fail with error: %@", error.localizedDescription)
        
        // Keep the iPhone's durable workout state informed before discarding
        // HealthKit's failed session. The local projection remains available
        // for the user to retry or discard explicitly.
        WorkoutSessionManager.perform {
            if self.pendingEnd != nil {
                self.completeEnd(.failure(error))
            } else {
                if let uuid = self.uuid {
                    WorkoutSessionManagerStore.shared.recordHealthKitFailure(
                        uuid: uuid, message: error.localizedDescription)
                }
                self.discard()
            }
        }
    }
}

// MARK: - Permissions
extension WorkoutSessionManager {
    private static func requestPermissions(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(GenericError(description: "HealthKit is not available on this device.")))
            return
        }
        
        Self.healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            guard success else {
                completion(.failure(error ?? GenericError(description: "Requesting authorization failed")))
                return
            }
            completion(.success(()))
        }
    }
    
    private static func requestWorkoutPermissions(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) else { completion(.failure(NSError())); return }
        guard let activeEnergyBurned = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { completion(.failure(NSError())); return }
        let share: Set = [HKObjectType.workoutType()]
        let read = Set([heartRate, activeEnergyBurned])
        
        Self.requestPermissions(toShare: share, read: read, completion: completion)
    }
    
    static func requestWorkoutPermissions() -> Result<Void, Error> {
        let permissionSemaphore = DispatchSemaphore(value: 0)
        var permissionsResult: Result<Void, Error>?
        requestWorkoutPermissions { result in
            defer { permissionSemaphore.signal() }
            permissionsResult = result
        }
        permissionSemaphore.wait()
        precondition(permissionsResult != nil)
        return permissionsResult!
    }
}

extension HKWorkoutSessionState {
    var name: String {
        switch self {
        case .ended:
            return "ended"
        case .notStarted:
            return "not started"
        case .paused:
            return "paused"
        case .prepared:
            return "prepared"
        case .running:
            return "running"
        case .stopped:
            return "stopped"
        @unknown default:
            return "unknown (\(rawValue))"
        }
    }
}
