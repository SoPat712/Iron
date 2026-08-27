//
//  HealthManager.swift
//  Iron
//
//  Created by Karim Abou Zeid on 02.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import HealthKit
import WorkoutDataKit
import os.log

class HealthManager {
    static let shared = HealthManager()
    
    let healthStore: HKHealthStore
    
    private init() {
        self.healthStore = HKHealthStore()
    }
}

extension HealthManager {
    enum AccessState: Equatable {
        case unavailable
        case notDetermined
        case needsReview
        case ready
    }

    enum AuthorizationError: LocalizedError {
        case unavailable
        case denied

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Health is not available on this device."
            case .denied:
                return "Iron could not access Apple Health. You can review access in the Health app or iPhone Settings."
            }
        }
    }

    // completion is called on a background queue!
    private func requestPermissions(
        toShare typesToShare: Set<HKSampleType>?,
        read typesToRead: Set<HKObjectType>?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        os_log("Requesting HealthKit permissions share=%@ read=%@", log: .health, type: .default, typesToShare ?? [], typesToRead ?? [])
        
        guard HKHealthStore.isHealthDataAvailable() else {
            os_log("HealthKit is not available on this device", log: .health, type: .error)
            completion(.failure(AuthorizationError.unavailable))
            return
        }
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            guard success else {
                os_log("Could not request health authorization: %@", log: .health, type: .fault, error?.localizedDescription ?? "nil")
                completion(.failure(error ?? AuthorizationError.denied))
                return
            }
            completion(.success(()))
        }
    }
    
    // completion is called on a background queue!
    func requestReadBodyWeightPermission(completion: @escaping (Result<Void, Error>) -> Void) {
        let read = Set([
            HKObjectType.quantityType(forIdentifier: .bodyMass)
        ].compactMap { $0 })
        requestPermissions(toShare: nil, read: read, completion: completion)
    }

    /// Requests the body-composition types Iron can exchange with Apple Health.  Limb and
    /// chest circumferences remain local because HealthKit has no matching quantity types.
    func requestBodyMeasurementPermission(completion: @escaping (Result<Void, Error>) -> Void) {
        let identifiers: [HKQuantityTypeIdentifier] = [.bodyMass, .height, .bodyFatPercentage, .waistCircumference]
        let quantityTypes = identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        requestPermissions(
            toShare: Set<HKSampleType>(quantityTypes),
            read: Set<HKObjectType>(quantityTypes),
            completion: completion
        )
    }
    
    // completion is called on a background queue!
    func requestShareWorkoutPermission(completion: @escaping (Result<Void, Error>) -> Void) {
        let workoutType = HKObjectType.workoutType()
        requestPermissions(toShare: [workoutType], read: [workoutType], completion: completion)
    }

    /// Requests every category Iron currently exchanges with Apple Health in a
    /// single, intentional setup step. HealthKit does not reveal read access,
    /// so the connection state below reflects the categories Iron can write.
    func requestWorkoutAndBodyMeasurementPermission(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let workoutType = HKObjectType.workoutType()
        let quantityTypes = bodyMeasurementTypes
        let shareTypes: [HKSampleType] = [workoutType] + quantityTypes.map { $0 as HKSampleType }
        let readTypes: [HKObjectType] = [workoutType] + quantityTypes.map { $0 as HKObjectType }
        requestPermissions(
            toShare: Set(shareTypes),
            read: Set(readTypes),
            completion: completion
        )
    }

    var accessState: AccessState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }

        let shareTypes: [HKSampleType] = [HKObjectType.workoutType()]
            + bodyMeasurementTypes.map { $0 as HKSampleType }
        let statuses = shareTypes.map(healthStore.authorizationStatus(for:))
        if statuses.allSatisfy({ $0 == .notDetermined }) {
            return .notDetermined
        }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            return .ready
        }
        return .needsReview
    }

    private var bodyMeasurementTypes: [HKQuantityType] {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .height,
            .bodyFatPercentage,
            .waistCircumference
        ]
        return identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
    }
}

extension HealthManager {
    enum WorkoutSyncOutcome {
        case saved
        case updated
        case alreadyPresent
    }

    enum WorkoutSyncError: LocalizedError {
        case missingWorkoutData

        var errorDescription: String? {
            "The workout is missing the information Apple Health needs."
        }
    }

    var workoutConfiguration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        return configuration
    }
    
    func saveWorkout(workout: Workout, exerciseStore: ExerciseStore) {
        syncWorkoutIfNeeded(workout: workout, exerciseStore: exerciseStore) { result in
            if case .failure(let error) = result {
                os_log("Could not save Apple Health workout: %@", log: .health, type: .error, error.localizedDescription)
            }
        }
    }

    /// Adds a completed workout to Apple Health only when a sample with Iron's
    /// stable workout identifier is not already present. This makes the detail
    /// screen's Sync action safe to retry.
    func syncWorkoutIfNeeded(
        workout: Workout,
        exerciseStore: ExerciseStore,
        completion: @escaping (Result<WorkoutSyncOutcome, Error>) -> Void
    ) {
        requestShareWorkoutPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            DispatchQueue.main.async {
                guard let uuid = workout.uuid,
                      let start = workout.start,
                      let end = workout.end,
                      let duration = workout.duration else {
                    completion(.failure(WorkoutSyncError.missingWorkoutData))
                    return
                }

                let workoutTitle = workout.optionalDisplayTitle(in: exerciseStore.exercises)
                var metadata: [String : Any] = [HKMetadataKeyExternalUUID : uuid.uuidString]
                if let workoutTitle {
                    metadata[HKMetadataKeyWorkoutBrandName] = workoutTitle
                }
                let hkWorkout = HKWorkout(activityType: self.workoutConfiguration.activityType, start: start, end: end, duration: duration, totalEnergyBurned: nil, totalDistance: nil, device: .local(), metadata: metadata)

                let uuidPredicate = HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeyExternalUUID,
                    allowedValues: [uuid.uuidString]
                )
                let sourcePredicate = HKQuery.predicateForObjects(from: .default())
                let predicate = NSCompoundPredicate(
                    andPredicateWithSubpredicates: [uuidPredicate, sourcePredicate]
                )
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }

                    let existingSamples = (samples as? [HKWorkout]) ?? []
                    if existingSamples.count == 1,
                       self.healthWorkout(
                            existingSamples[0],
                            matchesStart: start,
                            end: end,
                            title: workoutTitle
                       ) {
                        DispatchQueue.main.async { completion(.success(.alreadyPresent)) }
                        return
                    }

                    let saveReconciledWorkout: (WorkoutSyncOutcome) -> Void = { outcome in
                        self.healthStore.save(hkWorkout) { success, error in
                            DispatchQueue.main.async {
                                if success {
                                    completion(.success(outcome))
                                } else {
                                    completion(.failure(error ?? AuthorizationError.denied))
                                }
                            }
                        }
                    }

                    guard !existingSamples.isEmpty else {
                        saveReconciledWorkout(.saved)
                        return
                    }

                    // HealthKit samples are immutable. Remove every prior Iron-owned
                    // match first, then save one canonical replacement. This also
                    // repairs duplicates created by older Iron builds.
                    self.healthStore.delete(existingSamples) { success, error in
                        guard success else {
                            DispatchQueue.main.async {
                                completion(.failure(error ?? AuthorizationError.denied))
                            }
                            return
                        }
                        saveReconciledWorkout(.updated)
                    }
                }
                self.healthStore.execute(query)
            }
        }
    }

    private func healthWorkout(
        _ sample: HKWorkout,
        matchesStart start: Date,
        end: Date,
        title: String?
    ) -> Bool {
        let sampleTitle = sample.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        return sample.workoutActivityType == workoutConfiguration.activityType
            && approximatelyEqual(date1: sample.startDate, date2: start)
            && approximatelyEqual(date1: sample.endDate, date2: end)
            && sampleTitle == title
    }
    
    func deleteWorkout(workout: Workout) {
        guard let uuid = workout.uuid else { return }
        
        let uuidPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [uuid.uuidString])
        let sourcePredicate = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [uuidPredicate, sourcePredicate])
        
        os_log("Deleting HealthKit workout with uuid=%@", log: .health, uuid as NSUUID)
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: 1,
            sortDescriptors: nil) { (query, samples, error) in
                if let error = error {
                    os_log("Could not query HealthKit workout with uuid=%@: %@", log: .health, type: .fault, uuid as NSUUID, error.localizedDescription)
                    return
                }
                guard let workoutSample = samples?.first as? HKWorkout else {
                    os_log("No HealthKit workout with uuid=%@", log: .health, type: .fault, uuid as NSUUID)
                    return
                }
                
                self.healthStore.delete(workoutSample) { success, error in
                    guard success else {
                        os_log("Could not delete HealthKit workout with uuid=%@: %@", log: .health, type: .fault, uuid as NSUUID, error?.localizedDescription ?? "nil")
                        return
                    }
                    os_log("Successfully deleted HealthKit workout with uuid=%@", log: .health, type: .info, uuid as NSUUID)
                }
        }
        healthStore.execute(query)
    }

    /// Reconciles the HealthKit samples owned by this local measurement entry.
    /// Each supported field receives its own stable external identifier so edits
    /// replace Iron's prior value instead of appending another Health sample.
    func saveBodyMeasurements(_ entry: BodyMeasurementEntry) {
        reconcileBodyMeasurements(entry, shouldSaveCurrentValues: true)
    }

    /// Removes only HealthKit samples previously exported for this Iron entry.
    /// HealthKit additionally limits deletion to objects saved by this app.
    func deleteBodyMeasurements(_ entry: BodyMeasurementEntry) {
        reconcileBodyMeasurements(entry, shouldSaveCurrentValues: false)
    }

    private func reconcileBodyMeasurements(
        _ entry: BodyMeasurementEntry,
        shouldSaveCurrentValues: Bool
    ) {
        requestBodyMeasurementPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    os_log("Could not authorize body measurement sync: %@", log: .health, type: .error, error.localizedDescription)
                }
                return
            }

            let supportedValues: [(HKQuantityTypeIdentifier, Double?, HKUnit)] = [
                (.bodyMass, entry[.bodyWeight], .gramUnit(with: .kilo)),
                (.height, entry[.height].map { $0 / 100 }, .meter()),
                (.bodyFatPercentage, entry[.bodyFat].map { $0 / 100 }, .percent()),
                (.waistCircumference, entry[.waist].map { $0 / 100 }, .meter())
            ]
            let samples = supportedValues.compactMap { identifier, value, unit in
                self.bodySample(
                    identifier: identifier,
                    value: value,
                    unit: unit,
                    date: entry.date,
                    externalIdentifier: self.bodyMeasurementExternalIdentifier(
                        entryID: entry.id,
                        quantityIdentifier: identifier
                    )
                )
            }

            let deletionGroup = DispatchGroup()
            let resultLock = NSLock()
            var deletionFailed = false

            for (identifier, _, _) in supportedValues {
                guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
                let externalIdentifier = self.bodyMeasurementExternalIdentifier(
                    entryID: entry.id,
                    quantityIdentifier: identifier
                )
                let predicate = HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeyExternalUUID,
                    allowedValues: [externalIdentifier]
                )

                deletionGroup.enter()
                self.healthStore.deleteObjects(of: type, predicate: predicate) { success, _, error in
                    if !success {
                        resultLock.lock()
                        deletionFailed = true
                        resultLock.unlock()
                        os_log(
                            "Could not replace Iron body measurement %@ in HealthKit: %@",
                            log: .health,
                            type: .error,
                            identifier.rawValue,
                            error?.localizedDescription ?? "unknown error"
                        )
                    }
                    deletionGroup.leave()
                }
            }

            deletionGroup.notify(queue: .global(qos: .utility)) {
                resultLock.lock()
                let canContinue = !deletionFailed
                resultLock.unlock()

                guard canContinue, shouldSaveCurrentValues, !samples.isEmpty else { return }
                self.healthStore.save(samples) { success, error in
                    if !success {
                        os_log(
                            "Could not save body measurements to HealthKit: %@",
                            log: .health,
                            type: .error,
                            error?.localizedDescription ?? "unknown error"
                        )
                    }
                }
            }
        }
    }

    private func bodyMeasurementExternalIdentifier(
        entryID: UUID,
        quantityIdentifier: HKQuantityTypeIdentifier
    ) -> String {
        "com.joshpatra.iron.body-measurement.\(entryID.uuidString).\(quantityIdentifier.rawValue)"
    }

    private func bodySample(
        identifier: HKQuantityTypeIdentifier,
        value: Double?,
        unit: HKUnit,
        date: Date,
        externalIdentifier: String
    ) -> HKQuantitySample? {
        guard let value = value,
              value > 0,
              let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeyExternalUUID: externalIdentifier
        ]
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date, metadata: metadata)
    }

    struct BodyMeasurementRead {
        let values: [BodyMeasurementKind: Double]
        let date: Date?
    }

    func fetchLatestBodyMeasurements(completion: @escaping (Result<BodyMeasurementRead, Error>) -> Void) {
        requestBodyMeasurementPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }
            let requested: [(BodyMeasurementKind, HKQuantityTypeIdentifier, HKUnit, Double)] = [
                (.bodyWeight, .bodyMass, .gramUnit(with: .kilo), 1),
                (.height, .height, .meter(), 100),
                (.bodyFat, .bodyFatPercentage, .percent(), 100),
                (.waist, .waistCircumference, .meter(), 100)
            ]
            let group = DispatchGroup()
            let lock = NSLock()
            var values: [BodyMeasurementKind: Double] = [:]
            var newestDate: Date?
            var firstError: Error?

            for (kind, identifier, unit, multiplier) in requested {
                guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
                group.enter()
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                    defer { group.leave() }
                    if let error {
                        lock.lock()
                        if firstError == nil { firstError = error }
                        lock.unlock()
                        return
                    }
                    guard let sample = samples?.first as? HKQuantitySample else { return }
                    lock.lock()
                    values[kind] = sample.quantity.doubleValue(for: unit) * multiplier
                    newestDate = max(newestDate ?? sample.endDate, sample.endDate)
                    lock.unlock()
                }
                self.healthStore.execute(query)
            }

            group.notify(queue: .main) {
                if values.isEmpty, let firstError {
                    completion(.failure(firstError))
                } else {
                    completion(.success(BodyMeasurementRead(values: values, date: newestDate)))
                }
            }
        }
    }
}

import CoreData
extension HealthManager {
    enum UpdateError: Error {
        case noSuccess
        case noHKWorkouts
    }
    
    struct WorkoutUpdates {
        let created: Int
        let deleted: Int
        let modified: Int
    }
    
    func updateHealthWorkouts(managedObjectContext: NSManagedObjectContext, exerciseStore: ExerciseStore, completion: @escaping (Result<WorkoutUpdates, Error>) -> Void) {
        os_log("Updating HealthKit workouts", log: .health, type: .default)
        
        self.requestShareWorkoutPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    completion(.failure(error))
                }
                return
            }
            DispatchQueue.global(qos: .background).async {
                let workoutPredicate = HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining)
                let sourcePredicate = HKQuery.predicateForObjects(from: .default())
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, sourcePredicate])
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
                
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]) { query, samples, error in
                        if let error = error {
                            os_log("Could not query the HealthKit workout: %@", log: .health, type: .fault, error.localizedDescription)
                            completion(.failure(error))
                            return
                        }
                        guard let workoutSamples = samples as? [HKWorkout] else {
                            os_log("Could not cast to HealthKit workouts", log: .health, type: .fault)
                            completion(.failure(UpdateError.noHKWorkouts))
                            return
                        }
                        
                        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                        backgroundContext.parent = managedObjectContext
                        
                        backgroundContext.perform {
                            do {
                                let request: NSFetchRequest<Workout> = Workout.fetchRequest()
                                request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
                                request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
                                let workouts = try backgroundContext.fetch(request)
                                
                                let group = DispatchGroup()
                                var _success = true
                                var _error: Error? = nil
                                let resultLock = NSLock()
                                func recordResult(success: Bool, error: Error?) {
                                    resultLock.lock()
                                    _success = _success && success
                                    if let error, _error == nil {
                                        _error = error
                                    }
                                    resultLock.unlock()
                                }
                                
                                // delete HealthKit workout samples that are not in the database
                                let workoutSamplesToDelete = workoutSamples.filter { workoutSample in
                                    guard let externalUuid = workoutSample.externalUuid else { return true } // if the uuid is missing --> delete
                                    // if there is no workout for this uuid --> delete
                                    return !workouts.contains { $0.uuid == externalUuid }
                                }
                                os_log("Deleting HealthKit workouts: %@", log: .health, type: .info, workoutSamplesToDelete)
                                if !workoutSamplesToDelete.isEmpty {
                                    group.enter()
                                    self.healthStore.delete(workoutSamplesToDelete) { success, error in
                                        recordResult(success: success, error: error)
                                        group.leave()
                                    }
                                }
                                let deletedCount = workoutSamplesToDelete.count
                                
                                // save workouts that are missing from HealthKit
                                let workoutSamplesToSave: [HKWorkout] = workouts.filter { workout in
                                    guard let uuid = workout.uuid else { return false } // if the uuid is missing (should never happen) --> don't save
                                    // if there is no workout sample for this uuid --> save
                                    return !workoutSamples.contains { $0.externalUuid == uuid }
                                }
                                .compactMap { workout in
                                    guard let uuid = workout.uuid, let start = workout.start, let end = workout.end, let duration = workout.duration else { return nil } // should never fail
                                    var metadata: [String : Any] = [HKMetadataKeyExternalUUID : uuid.uuidString]
                                    if let title = workout.optionalDisplayTitle(in: exerciseStore.exercises) {
                                        metadata[HKMetadataKeyWorkoutBrandName] = title
                                    }
                                    return HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end, duration: duration, totalEnergyBurned: nil, totalDistance: nil, device: .local(), metadata: metadata)
                                }
                                os_log("Saving HealthKit workouts %@", log: .health, type: .info, workoutSamplesToSave)
                                if !workoutSamplesToSave.isEmpty {
                                    group.enter()
                                    self.healthStore.save(workoutSamplesToSave) { success, error in
                                        recordResult(success: success, error: error)
                                        group.leave()
                                    }
                                }
                                let createdCount = workoutSamplesToSave.count
                                
                                // update start / end times
                                let workoutSamplesToModify: [(HKWorkout, Workout)] = workouts.compactMap { workout in
                                    guard let uuid = workout.uuid else { return nil }
                                    guard let workoutSample = workoutSamples.first(where: { $0.externalUuid == uuid }) else { return nil }
                                    return (workoutSample, workout)
                                }
                                .filter {
                                    let currentTitle = $0.0.metadata?[HKMetadataKeyWorkoutBrandName] as? String
                                    let desiredTitle = $0.1.optionalDisplayTitle(in: exerciseStore.exercises)
                                    return !self.approximatelyEqual(date1: $0.0.startDate, date2: $0.1.safeStart)
                                        || !self.approximatelyEqual(date1: $0.0.endDate, date2: $0.1.safeEnd)
                                        || currentTitle != desiredTitle
                                }
                                os_log("Modifying HealthKit workouts %@", log: .health, type: .info, workoutSamplesToModify)
                                var modifiedCount = 0
                                if !workoutSamplesToModify.isEmpty {
                                    let modifiedWorkoutSamples = workoutSamplesToModify.compactMap { workoutSample, workout -> HKWorkout? in
                                        guard let start = workout.start, let end = workout.end, let duration = workout.duration else { return nil }
                                        
                                        var metadata = workoutSample.metadata ?? [:]
                                        if let title = workout.optionalDisplayTitle(in: exerciseStore.exercises) {
                                            metadata[HKMetadataKeyWorkoutBrandName] = title
                                        } else {
                                            metadata.removeValue(forKey: HKMetadataKeyWorkoutBrandName)
                                        }
                                        
                                        return HKWorkout(activityType: workoutSample.workoutActivityType, start: start, end: end, duration: duration, totalEnergyBurned: workoutSample.totalEnergyBurned, totalDistance: workoutSample.totalDistance, device: workoutSample.device, metadata: metadata)
                                    }
                                    
                                    group.enter()
                                    self.healthStore.delete(workoutSamplesToModify.map { $0.0 }) { success, error in
                                        recordResult(success: success, error: error)
                                        guard success else {
                                            group.leave()
                                            return
                                        }
                                        self.healthStore.save(modifiedWorkoutSamples) { success, error in
                                            recordResult(success: success, error: error)
                                            group.leave()
                                        }
                                    }
                                    modifiedCount = modifiedWorkoutSamples.count
                                }
                                
                                group.wait()
                                resultLock.lock()
                                let succeeded = _success
                                let recordedError = _error
                                resultLock.unlock()
                                if succeeded {
                                    os_log("Successfully updated HealthKit workouts", log: .health, type: .default)
                                    completion(.success((WorkoutUpdates(created: createdCount, deleted: deletedCount, modified: modifiedCount))))
                                } else if let error = recordedError {
                                    os_log("Could not update HealthKit workouts: %@", log: .health, type: .error, error.localizedDescription)
                                    completion(.failure(error))
                                } else {
                                    os_log("Could not update HealthKit workouts", log: .health, type: .error)
                                    completion(.failure(UpdateError.noSuccess))
                                }
                            } catch {
                                os_log("Could not update HealthKit workouts: %@", log: .health, type: .error, error.localizedDescription)
                                completion(.failure(error))
                            }
                        }
                }
                self.healthStore.execute(query)
            }
        }
    }
    
    private func approximatelyEqual(date1: Date, date2: Date) -> Bool {
        abs(date1.timeIntervalSince(date2)) < 1
    }
}

extension HKWorkout {
    var externalUuid: UUID? {
        guard let externalUuidString = metadata?[HKMetadataKeyExternalUUID] as? String else { return nil }
        return UUID(uuidString: externalUuidString)
    }
}
