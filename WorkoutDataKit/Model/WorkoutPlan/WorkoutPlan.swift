//
//  WorkoutPlan.swift
//  WorkoutDataKit
//
//  Created by Karim Abou Zeid on 21.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import CoreData

extension WorkoutPlan {
    public var id: NSManagedObjectID { self.objectID }
}

public class WorkoutPlan: NSManagedObject, Codable {
    public class func create(context: NSManagedObjectContext) -> WorkoutPlan {
        let workoutPlan = WorkoutPlan(context: context)
        workoutPlan.uuid = UUID()
        return workoutPlan
    }
    
    public var displayTitle: String {
        title ?? "Workouts"
    }
    
    public func duplicate(context: NSManagedObjectContext) -> WorkoutPlan {
        let workoutPlanCopy = WorkoutPlan.create(context: context)
        workoutPlanCopy.title = self.title
        let sourceRoutines = self.workoutRoutines?.array.compactMap { $0 as? WorkoutRoutine } ?? []
        let copiedRoutines = sourceRoutines.map { workoutRoutine -> WorkoutRoutine in
            let workoutRoutineCopy = WorkoutRoutine.create(context: context)
            workoutRoutineCopy.title = workoutRoutine.title
            workoutRoutineCopy.comment = workoutRoutine.comment
            let sourceExercises = workoutRoutine.workoutRoutineExercises?.array
                .compactMap { $0 as? WorkoutRoutineExercise } ?? []
            let copiedPairs = sourceExercises.map { source -> (WorkoutRoutineExercise, WorkoutRoutineExercise) in
                let copy = WorkoutRoutineExercise.create(context: context)
                copy.exerciseUuid = source.exerciseUuid
                copy.comment = source.comment
                copy.restTimerDurationValue = source.restTimerDurationValue
                return (source, copy)
            }
            var copiedGroupIDBySourceID = [UUID: UUID]()
            for (source, copy) in copiedPairs {
                if let sourceGroupID = source.supersetUuid {
                    let copiedGroupID = copiedGroupIDBySourceID[sourceGroupID] ?? UUID()
                    copiedGroupIDBySourceID[sourceGroupID] = copiedGroupID
                    copy.supersetUuid = copiedGroupID
                }
                let sourceSets = source.workoutRoutineSets?.array.compactMap { $0 as? WorkoutRoutineSet } ?? []
                let copiedSets = sourceSets.map { sourceSet -> WorkoutRoutineSet in
                    let copiedSet = WorkoutRoutineSet.create(context: context)
                    copiedSet.maxRepetitions = sourceSet.maxRepetitions
                    copiedSet.minRepetitions = sourceSet.minRepetitions
                    copiedSet.tagValue = sourceSet.tagValue
                    copiedSet.comment = sourceSet.comment
                    copiedSet.weightValue = sourceSet.weightValue
                    copiedSet.durationValue = sourceSet.durationValue
                    return copiedSet
                }
                copy.workoutRoutineSets = NSOrderedSet(array: copiedSets)
            }
            workoutRoutineCopy.workoutRoutineExercises = NSOrderedSet(array: copiedPairs.map(\.1))
            return workoutRoutineCopy
        }
        workoutPlanCopy.workoutRoutines = NSOrderedSet(array: copiedRoutines)
        return workoutPlanCopy
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case uuid
        case title
        case routines
    }
    
    required convenience public init(from decoder: Decoder) throws {
        guard let contextKey = CodingUserInfoKey.managedObjectContextKey,
            let context = decoder.userInfo[contextKey] as? NSManagedObjectContext,
            let entity = NSEntityDescription.entity(forEntityName: "WorkoutPlan", in: context)
            else {
            throw CodingUserInfoKey.DecodingError.managedObjectContextMissing
        }
        self.init(entity: entity, insertInto: context)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid) ?? UUID() // make sure we always have an UUID
        title = try container.decodeIfPresent(String.self, forKey: .title)
        workoutRoutines = NSOrderedSet(array: try container.decodeIfPresent([WorkoutRoutine].self, forKey: .routines) ?? [])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid ?? UUID(), forKey: .uuid)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(workoutRoutines?.array.compactMap { $0 as? WorkoutRoutine }, forKey: .routines)
    }
}
