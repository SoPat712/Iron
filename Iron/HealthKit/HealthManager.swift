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

    final class MutationCoordinator {
        typealias Mutation = (@escaping () -> Void) -> Void

        private let lock = NSLock()
        private var pending: [Mutation] = []
        private var isRunning = false

        func enqueue(_ mutation: @escaping Mutation) {
            lock.lock()
            pending.append(mutation)
            let next = takeNextIfIdleLocked()
            lock.unlock()
            if let next { run(next) }
        }

        private func takeNextIfIdleLocked() -> Mutation? {
            guard !isRunning, !pending.isEmpty else { return nil }
            isRunning = true
            return pending.removeFirst()
        }

        private func run(_ mutation: @escaping Mutation) {
            let finishLock = NSLock()
            var didFinish = false
            mutation { [weak self] in
                finishLock.lock()
                guard !didFinish else {
                    finishLock.unlock()
                    return
                }
                didFinish = true
                finishLock.unlock()
                self?.mutationFinished()
            }
        }

        private func mutationFinished() {
            lock.lock()
            isRunning = false
            let next = takeNextIfIdleLocked()
            lock.unlock()
            if let next { run(next) }
        }
    }
    
    let healthStore: HKHealthStore
    private let mutationCoordinator = MutationCoordinator()
    
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
    struct ExistingSampleReconciliation<Sample> {
        let reusable: Sample?
        let surplus: [Sample]
    }

    static func reconcileExistingSamples<Sample>(
        _ samples: [Sample],
        matches: (Sample) -> Bool,
        stableID: (Sample) -> UUID
    ) -> ExistingSampleReconciliation<Sample> {
        let reusable = samples
            .filter(matches)
            .min { stableID($0).uuidString < stableID($1).uuidString }
        guard let reusable else {
            return ExistingSampleReconciliation(reusable: nil, surplus: samples)
        }
        let reusableID = stableID(reusable)
        return ExistingSampleReconciliation(
            reusable: reusable,
            surplus: samples.filter { stableID($0) != reusableID }
        )
    }

    /// Returns false only when the caller still needs to create a replacement.
    /// A reusable matching sample is retained while exact surplus objects are
    /// deleted through the same error-reporting path as other removals.
    @discardableResult
    static func completeUsingReusableSample<Sample>(
        _ reconciliation: ExistingSampleReconciliation<Sample>,
        delete: @escaping ([Sample], @escaping (Result<Void, Error>) -> Void) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> Bool {
        guard reconciliation.reusable != nil else { return false }
        coordinateReplacement(
            oldObjects: reconciliation.surplus,
            replacements: [Sample](),
            intent: .delete,
            save: { _, _ in assertionFailure("Delete-only reconciliation must not save") },
            delete: delete,
            completion: completion
        )
        return true
    }

    enum ReplacementIntent {
        case replace
        case delete
    }

    /// Save immutable replacements before deleting the exact old objects
    /// returned by the preceding query. Empty replacements are safe no-ops
    /// unless the caller explicitly requests deletion.
    static func coordinateReplacement<Old, New>(
        oldObjects: [Old],
        replacements: [New],
        intent: ReplacementIntent,
        save: @escaping ([New], @escaping (Result<Void, Error>) -> Void) -> Void,
        delete: @escaping ([Old], @escaping (Result<Void, Error>) -> Void) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func deleteOldObjects() {
            guard !oldObjects.isEmpty else {
                completion(.success(()))
                return
            }
            delete(oldObjects, completion)
        }

        switch intent {
        case .delete:
            deleteOldObjects()
        case .replace:
            guard !replacements.isEmpty else {
                completion(.success(()))
                return
            }
            save(replacements) { result in
                switch result {
                case .success:
                    deleteOldObjects()
                case .failure:
                    completion(result)
                }
            }
        }
    }

    static func replacementMetadata(
        copying priorMetadata: [String: Any]?,
        externalUUID: String,
        title: String?
    ) -> [String: Any] {
        var metadata = priorMetadata ?? [:]
        // This is a new independent sample, not a HealthKit sync-version update.
        // Reusing the old sync identity/version can cause HealthKit to ignore it.
        metadata.removeValue(forKey: HKMetadataKeySyncIdentifier)
        metadata.removeValue(forKey: HKMetadataKeySyncVersion)
        metadata[HKMetadataKeyExternalUUID] = externalUUID
        if let title {
            metadata[HKMetadataKeyWorkoutBrandName] = title
        } else {
            metadata.removeValue(forKey: HKMetadataKeyWorkoutBrandName)
        }
        return metadata
    }

    static func isValidWorkoutInterval(start: Date, end: Date, duration: TimeInterval) -> Bool {
        start.timeIntervalSinceReferenceDate.isFinite
            && end.timeIntervalSinceReferenceDate.isFinite
            && duration.isFinite
            && end >= start
            && duration >= 0
    }

    static func workoutFieldsMatch(
        existingStart: Date,
        existingEnd: Date,
        existingDuration: TimeInterval,
        existingTitle: String?,
        desiredStart: Date,
        desiredEnd: Date,
        desiredDuration: TimeInterval,
        desiredTitle: String?
    ) -> Bool {
        abs(existingStart.timeIntervalSince(desiredStart)) < 1
            && abs(existingEnd.timeIntervalSince(desiredEnd)) < 1
            && abs(existingDuration - desiredDuration) < 1
            && existingTitle == desiredTitle
    }

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
        let context = workout.managedObjectContext
        let workoutID = workout.objectID
        mutationCoordinator.enqueue { finish in
            guard let context else {
                finish()
                DispatchQueue.main.async {
                    completion(.failure(WorkoutSyncError.missingWorkoutData))
                }
                return
            }
            self.performSyncWorkoutIfNeeded(
                workoutID: workoutID,
                context: context,
                exerciseStore: exerciseStore
            ) { result in
                finish()
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    private func performSyncWorkoutIfNeeded(
        workoutID: NSManagedObjectID,
        context: NSManagedObjectContext,
        exerciseStore: ExerciseStore,
        completion: @escaping (Result<WorkoutSyncOutcome, Error>) -> Void
    ) {
        requestShareWorkoutPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    completion(.failure(error))
                }
                return
            }

            context.perform {
                guard !workoutID.isTemporaryID,
                      let workout = (try? context.existingObject(with: workoutID)) as? Workout,
                      !workout.isDeleted,
                      !workout.isCurrentWorkout,
                      let uuid = workout.uuid,
                      let start = workout.start,
                      let end = workout.end,
                      let duration = workout.duration,
                      Self.isValidWorkoutInterval(start: start, end: end, duration: duration) else {
                    completion(.failure(WorkoutSyncError.missingWorkoutData))
                    return
                }

                let workoutTitle = workout.optionalDisplayTitle(in: exerciseStore.exercises)
                var metadata: [String : Any] = [HKMetadataKeyExternalUUID : uuid.uuidString]
                if let workoutTitle {
                    metadata[HKMetadataKeyWorkoutBrandName] = workoutTitle
                }
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
                        completion(.failure(error))
                        return
                    }

                    let existingSamples = (samples as? [HKWorkout]) ?? []
                    let reconciliation = Self.reconcileExistingSamples(
                        existingSamples,
                        matches: {
                            self.healthWorkout(
                                $0,
                                matchesStart: start,
                                end: end,
                                duration: duration,
                                title: workoutTitle
                            )
                        },
                        stableID: { $0.uuid }
                    )
                    let reusedOutcome: WorkoutSyncOutcome = reconciliation.surplus.isEmpty
                        ? .alreadyPresent
                        : .updated
                    if Self.completeUsingReusableSample(
                        reconciliation,
                        delete: { surplus, deleted in
                            self.healthStore.delete(surplus) { success, error in
                                deleted(success
                                    ? .success(())
                                    : .failure(error ?? AuthorizationError.denied))
                            }
                        },
                        completion: { result in
                            completion(result.map { reusedOutcome })
                        }
                    ) {
                        return
                    }

                    let prior = existingSamples.first
                    let replacementMetadata = Self.replacementMetadata(
                        copying: prior?.metadata ?? metadata,
                        externalUUID: uuid.uuidString,
                        title: workoutTitle
                    )
                    let reconciledWorkout = HKWorkout(
                        activityType: self.workoutConfiguration.activityType,
                        start: start,
                        end: end,
                        duration: duration,
                        totalEnergyBurned: prior?.totalEnergyBurned,
                        totalDistance: prior?.totalDistance,
                        device: prior?.device ?? .local(),
                        metadata: replacementMetadata
                    )
                    let outcome: WorkoutSyncOutcome = existingSamples.isEmpty ? .saved : .updated
                    Self.coordinateReplacement(
                        oldObjects: existingSamples,
                        replacements: [reconciledWorkout],
                        intent: .replace,
                        save: { replacements, saved in
                            self.healthStore.save(replacements) { success, error in
                                saved(success
                                    ? .success(())
                                    : .failure(error ?? AuthorizationError.denied))
                            }
                        },
                        delete: { oldObjects, deleted in
                            self.healthStore.delete(oldObjects) { success, error in
                                deleted(success
                                    ? .success(())
                                    : .failure(error ?? AuthorizationError.denied))
                            }
                        },
                        completion: { result in
                            completion(result.map { outcome })
                        }
                    )
                }
                self.healthStore.execute(query)
            }
        }
    }

    private func healthWorkout(
        _ sample: HKWorkout,
        matchesStart start: Date,
        end: Date,
        duration: TimeInterval,
        title: String?
    ) -> Bool {
        let sampleTitle = sample.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        return sample.workoutActivityType == workoutConfiguration.activityType
            && Self.workoutFieldsMatch(
                existingStart: sample.startDate,
                existingEnd: sample.endDate,
                existingDuration: sample.duration,
                existingTitle: sampleTitle,
                desiredStart: start,
                desiredEnd: end,
                desiredDuration: duration,
                desiredTitle: title
            )
    }
    
    func deleteWorkout(workout: Workout) {
        guard let uuid = workout.uuid else { return }
        deleteWorkout(uuid: uuid)
    }

    /// Value-only deletion entry point for callers that have already durably
    /// removed the Core Data workout.
    func deleteWorkout(uuid: UUID) {
        mutationCoordinator.enqueue { finish in
            self.performDeleteWorkout(uuid: uuid, completion: finish)
        }
    }

    private func performDeleteWorkout(uuid: UUID, completion: @escaping () -> Void) {
        let uuidPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [uuid.uuidString])
        let sourcePredicate = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [uuidPredicate, sourcePredicate])
        
        os_log("Deleting HealthKit workout with uuid=%@", log: .health, uuid as NSUUID)
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil) { (query, samples, error) in
                if let error = error {
                    os_log("Could not query HealthKit workout with uuid=%@: %@", log: .health, type: .fault, uuid as NSUUID, error.localizedDescription)
                    completion()
                    return
                }
                let workoutSamples = (samples as? [HKWorkout]) ?? []
                guard !workoutSamples.isEmpty else {
                    os_log("No HealthKit workout with uuid=%@", log: .health, type: .fault, uuid as NSUUID)
                    completion()
                    return
                }
                
                self.healthStore.delete(workoutSamples) { success, error in
                    guard success else {
                        os_log("Could not delete HealthKit workout with uuid=%@: %@", log: .health, type: .fault, uuid as NSUUID, error?.localizedDescription ?? "nil")
                        completion()
                        return
                    }
                    os_log("Successfully deleted HealthKit workout with uuid=%@", log: .health, type: .info, uuid as NSUUID)
                    completion()
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

    private struct BodyReplacementPlan {
        let identifier: HKQuantityTypeIdentifier
        let type: HKQuantityType
        let externalIdentifier: String
        let replacement: HKQuantitySample?
        let intent: ReplacementIntent
    }

    private func reconcileBodyMeasurements(
        _ entry: BodyMeasurementEntry,
        shouldSaveCurrentValues: Bool
    ) {
        mutationCoordinator.enqueue { finish in
            self.performReconcileBodyMeasurements(
                entry,
                shouldSaveCurrentValues: shouldSaveCurrentValues,
                completion: finish
            )
        }
    }

    private func performReconcileBodyMeasurements(
        _ entry: BodyMeasurementEntry,
        shouldSaveCurrentValues: Bool,
        completion: @escaping () -> Void
    ) {
        requestBodyMeasurementPermission { authorization in
            guard case .success = authorization else {
                if case .failure(let error) = authorization {
                    os_log("Could not authorize body measurement sync: %@", log: .health, type: .error, error.localizedDescription)
                }
                completion()
                return
            }

            let supportedValues: [(HKQuantityTypeIdentifier, Double?, HKUnit)] = [
                (.bodyMass, entry[.bodyWeight], .gramUnit(with: .kilo)),
                (.height, entry[.height].map { $0 / 100 }, .meter()),
                (.bodyFatPercentage, entry[.bodyFat].map { $0 / 100 }, .percent()),
                (.waistCircumference, entry[.waist].map { $0 / 100 }, .meter())
            ]
            let plans: [BodyReplacementPlan] = supportedValues.compactMap { identifier, value, unit in
                guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
                let externalIdentifier = self.bodyMeasurementExternalIdentifier(
                    entryID: entry.id,
                    quantityIdentifier: identifier
                )
                if !shouldSaveCurrentValues || value == nil {
                    return BodyReplacementPlan(
                        identifier: identifier,
                        type: type,
                        externalIdentifier: externalIdentifier,
                        replacement: nil,
                        intent: .delete
                    )
                }
                guard let replacement = self.bodySample(
                    identifier: identifier,
                    value: value,
                    unit: unit,
                    date: entry.date,
                    externalIdentifier: externalIdentifier
                ) else {
                    // A present but invalid value is a construction failure,
                    // not an instruction to erase the previous Health sample.
                    return nil
                }
                return BodyReplacementPlan(
                    identifier: identifier,
                    type: type,
                    externalIdentifier: externalIdentifier,
                    replacement: replacement,
                    intent: .replace
                )
            }

            let queryGroup = DispatchGroup()
            let resultLock = NSLock()
            var oldSamplesByIdentifier: [String: [HKQuantitySample]] = [:]
            var queryError: Error?

            for plan in plans {
                let identifierPredicate = HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeyExternalUUID,
                    allowedValues: [plan.externalIdentifier]
                )
                let sourcePredicate = HKQuery.predicateForObjects(from: .default())
                let predicate = NSCompoundPredicate(
                    andPredicateWithSubpredicates: [identifierPredicate, sourcePredicate]
                )
                queryGroup.enter()
                let query = HKSampleQuery(
                    sampleType: plan.type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    resultLock.lock()
                    if let error {
                        if queryError == nil { queryError = error }
                    } else {
                        oldSamplesByIdentifier[plan.externalIdentifier] =
                            (samples as? [HKQuantitySample]) ?? []
                    }
                    resultLock.unlock()
                    queryGroup.leave()
                }
                self.healthStore.execute(query)
            }

            queryGroup.notify(queue: .global(qos: .utility)) {
                resultLock.lock()
                let capturedError = queryError
                let capturedOldSamples = oldSamplesByIdentifier
                resultLock.unlock()

                guard capturedError == nil else {
                    os_log(
                        "Could not query prior Iron body measurements in HealthKit: %@",
                        log: .health,
                        type: .error,
                        capturedError?.localizedDescription ?? "unknown error"
                    )
                    completion()
                    return
                }

                let replacementGroup = DispatchGroup()
                for plan in plans {
                    replacementGroup.enter()
                    Self.coordinateReplacement(
                        oldObjects: capturedOldSamples[plan.externalIdentifier] ?? [],
                        replacements: plan.replacement.map { [$0] } ?? [],
                        intent: plan.intent,
                        save: { replacements, saved in
                            self.healthStore.save(replacements) { success, error in
                                saved(success
                                    ? .success(())
                                    : .failure(error ?? AuthorizationError.denied))
                            }
                        },
                        delete: { oldObjects, deleted in
                            self.healthStore.delete(oldObjects) { success, error in
                                deleted(success
                                    ? .success(())
                                    : .failure(error ?? AuthorizationError.denied))
                            }
                        },
                        completion: { result in
                            if case .failure(let error) = result {
                                os_log(
                                    "Could not reconcile Iron body measurement %@ in HealthKit: %@",
                                    log: .health,
                                    type: .error,
                                    plan.identifier.rawValue,
                                    error.localizedDescription
                                )
                            }
                            replacementGroup.leave()
                        }
                    )
                }
                replacementGroup.notify(queue: .global(qos: .utility)) {
                    if plans.isEmpty {
                        os_log(
                            "No supported body measurement values to reconcile",
                            log: .health,
                            type: .info
                        )
                    }
                    completion()
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
              value.isFinite,
              value > 0,
              date.timeIntervalSinceReferenceDate.isFinite,
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
        mutationCoordinator.enqueue { finish in
            self.performUpdateHealthWorkouts(
                managedObjectContext: managedObjectContext,
                exerciseStore: exerciseStore
            ) { result in
                completion(result)
                finish()
            }
        }
    }

    private func performUpdateHealthWorkouts(
        managedObjectContext: NSManagedObjectContext,
        exerciseStore: ExerciseStore,
        completion: @escaping (Result<WorkoutUpdates, Error>) -> Void
    ) {
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
                                request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
                                let allLocalWorkouts = try backgroundContext.fetch(request)
                                let workouts = allLocalWorkouts.filter { !$0.isCurrentWorkout }
                                
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
                                
                                // An unfinished phone workout may already have a Watch
                                // Health sample. It is not an orphan to remove during sync.
                                let localWorkoutIDs = Set(allLocalWorkouts.compactMap(\.uuid))
                                // Delete only Iron samples with a valid external ID whose
                                // local workout no longer exists. Never claim unpaired data.
                                let workoutSamplesToDelete = workoutSamples.filter { workoutSample in
                                    guard let externalUuid = workoutSample.externalUuid else { return false }
                                    return !localWorkoutIDs.contains(externalUuid)
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
                                
                                let samplesByID = Dictionary(grouping: workoutSamples.compactMap { sample in
                                    sample.externalUuid.map { ($0, sample) }
                                }, by: { $0.0 }).mapValues { $0.map(\.1) }
                                var workoutSamplesToSave: [HKWorkout] = []
                                var workoutReplacementPlans: [(old: [HKWorkout], new: HKWorkout)] = []
                                var workoutCleanupPlans: [ExistingSampleReconciliation<HKWorkout>] = []

                                for workout in workouts {
                                    guard let uuid = workout.uuid,
                                          let start = workout.start,
                                          let end = workout.end,
                                          let duration = workout.duration,
                                          Self.isValidWorkoutInterval(
                                            start: start,
                                            end: end,
                                            duration: duration
                                          ) else {
                                        // Invalid local data must not delete a valid old sample.
                                        continue
                                    }
                                    let existing = samplesByID[uuid] ?? []
                                    let title = workout.optionalDisplayTitle(in: exerciseStore.exercises)
                                    let reconciliation = Self.reconcileExistingSamples(
                                        existing,
                                        matches: {
                                            self.healthWorkout(
                                                $0,
                                                matchesStart: start,
                                                end: end,
                                                duration: duration,
                                                title: title
                                            )
                                        },
                                        stableID: { $0.uuid }
                                    )
                                    if reconciliation.reusable != nil {
                                        if !reconciliation.surplus.isEmpty {
                                            workoutCleanupPlans.append(reconciliation)
                                        }
                                        continue
                                    }

                                    let prior = existing.first
                                    let metadata = Self.replacementMetadata(
                                        copying: prior?.metadata,
                                        externalUUID: uuid.uuidString,
                                        title: title
                                    )
                                    let replacement = HKWorkout(
                                        activityType: prior?.workoutActivityType ?? .traditionalStrengthTraining,
                                        start: start,
                                        end: end,
                                        duration: duration,
                                        totalEnergyBurned: prior?.totalEnergyBurned,
                                        totalDistance: prior?.totalDistance,
                                        device: prior?.device ?? .local(),
                                        metadata: metadata
                                    )
                                    if existing.isEmpty {
                                        workoutSamplesToSave.append(replacement)
                                    } else {
                                        // Replace every duplicate old object only after the
                                        // canonical replacement has saved successfully.
                                        workoutReplacementPlans.append((existing, replacement))
                                    }
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
                                os_log("Modifying HealthKit workouts %@", log: .health, type: .info, workoutReplacementPlans.map(\.new))
                                for plan in workoutReplacementPlans {
                                    group.enter()
                                    Self.coordinateReplacement(
                                        oldObjects: plan.old,
                                        replacements: [plan.new],
                                        intent: .replace,
                                        save: { replacements, saved in
                                            self.healthStore.save(replacements) { success, error in
                                                saved(success
                                                    ? .success(())
                                                    : .failure(error ?? AuthorizationError.denied))
                                            }
                                        },
                                        delete: { oldObjects, deleted in
                                            self.healthStore.delete(oldObjects) { success, error in
                                                deleted(success
                                                    ? .success(())
                                                    : .failure(error ?? AuthorizationError.denied))
                                            }
                                        },
                                        completion: { result in
                                            switch result {
                                            case .success:
                                                recordResult(success: true, error: nil)
                                            case .failure(let error):
                                                recordResult(success: false, error: error)
                                            }
                                            group.leave()
                                        }
                                    )
                                }
                                for cleanup in workoutCleanupPlans {
                                    group.enter()
                                    _ = Self.completeUsingReusableSample(
                                        cleanup,
                                        delete: { surplus, deleted in
                                            self.healthStore.delete(surplus) { success, error in
                                                deleted(success
                                                    ? .success(())
                                                    : .failure(error ?? AuthorizationError.denied))
                                            }
                                        },
                                        completion: { result in
                                            switch result {
                                            case .success:
                                                recordResult(success: true, error: nil)
                                            case .failure(let error):
                                                recordResult(success: false, error: error)
                                            }
                                            group.leave()
                                        }
                                    )
                                }
                                let modifiedCount = workoutReplacementPlans.count + workoutCleanupPlans.count
                                
                                group.notify(queue: .global(qos: .background)) {
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
