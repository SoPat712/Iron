//
//  WorkoutPlan.swift
//  WorkoutDataKit
//
//  Created by Karim Abou Zeid on 21.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import CoreData

extension WorkoutRoutine {
    public var id: NSManagedObjectID { self.objectID }
}

public class WorkoutRoutine: NSManagedObject, Codable {
    public class func create(context: NSManagedObjectContext) -> WorkoutRoutine {
        let workoutRoutine = WorkoutRoutine(context: context)
        workoutRoutine.uuid = UUID()
        return workoutRoutine
    }
    
    public var fallbackTitle: String? {
        guard let index = workoutPlan?.workoutRoutines?.index(of: self), index != NSNotFound else { return nil }
        guard let letters = toLetters(from: index) else { return nil }
        return "Workout \(letters)"
    }
    
    private func toLetters(from index: Int) -> String? {
        guard index >= 0 else { return nil }

        let quotient: Int = index / 26
        let remainder: Int = index % 26
        
        guard let scalar = UnicodeScalar(Int(UnicodeScalar("A").value) + remainder) else {
            assertionFailure("This should never happen")
            return nil
        }
        let letter = String(Character(scalar))
        
        if quotient == 0 {
            return letter
        }
        
        guard let prefix = toLetters(from: quotient - 1) else { return nil }
        return prefix + letter
    }

    
    public var displayTitle: String {
        title ?? fallbackTitle ?? "Workout"
    }

    /// Creates a user-visible plan copy while preserving exercises, targets,
    /// rest timers, set tags, and superset relationships.
    public func duplicate(context: NSManagedObjectContext) -> WorkoutRoutine {
        let copy = WorkoutRoutine.create(context: context)
        copy.title = "\(displayTitle) Copy"
        copy.comment = comment
        copy.workoutPlan = workoutPlan

        let sourceExercises = workoutRoutineExercises?.array
            .compactMap { $0 as? WorkoutRoutineExercise } ?? []
        let copiedPairs = sourceExercises.map { source -> (WorkoutRoutineExercise, WorkoutRoutineExercise) in
            let exerciseCopy = WorkoutRoutineExercise.create(context: context)
            exerciseCopy.exerciseUuid = source.exerciseUuid
            exerciseCopy.comment = source.comment
            exerciseCopy.restTimerDurationValue = source.restTimerDurationValue
            return (source, exerciseCopy)
        }
        var copiedGroupIDBySourceID = [UUID: UUID]()

        for (source, exerciseCopy) in copiedPairs {
            if let sourceGroupID = source.supersetUuid {
                let copiedGroupID = copiedGroupIDBySourceID[sourceGroupID] ?? UUID()
                copiedGroupIDBySourceID[sourceGroupID] = copiedGroupID
                exerciseCopy.supersetUuid = copiedGroupID
            }
            let sourceSets = source.workoutRoutineSets?.array
                .compactMap { $0 as? WorkoutRoutineSet } ?? []
            let copiedSets = sourceSets.map { sourceSet -> WorkoutRoutineSet in
                let setCopy = WorkoutRoutineSet.create(context: context)
                setCopy.maxRepetitions = sourceSet.maxRepetitions
                setCopy.minRepetitions = sourceSet.minRepetitions
                setCopy.tagValue = sourceSet.tagValue
                setCopy.comment = sourceSet.comment
                setCopy.weightValue = sourceSet.weightValue
                setCopy.durationValue = sourceSet.durationValue
                return setCopy
            }
            exerciseCopy.workoutRoutineSets = NSOrderedSet(array: copiedSets)
        }
        copy.workoutRoutineExercises = NSOrderedSet(array: copiedPairs.map(\.1))
        return copy
    }
    
    public func subtitle(in exercises: [Exercise]) -> String {
        let s = workoutRoutineExercises?
            .compactMap { $0 as? WorkoutRoutineExercise }
            .compactMap { $0.exercise(in: exercises)?.title }
            .joined(separator: ", ") ?? ""
        
        return s.isEmpty ? "No exercises" : s
    }
    
    public func createWorkout(context: NSManagedObjectContext) -> Workout {
        let workout = Workout.create(context: context)
        // Keep the identity of the saved workout that launched this session.
        // The relationship remains useful for history and updating targets, but
        // the active session should not lose its visible name if that relationship
        // is refreshed, migrated, or renamed later.
        workout.title = displayTitle
        workout.comment = self.comment
        
        if let workoutRoutineExercises = workoutRoutineExercises?.compactMap({ $0 as? WorkoutRoutineExercise }) {
            // copy the exercises
            for workoutRoutineExercise in workoutRoutineExercises {
                let workoutExercise = WorkoutExercise.create(context: context)
                workout.addToWorkoutExercises(workoutExercise)
                workoutExercise.exerciseUuid = workoutRoutineExercise.exerciseUuid
                workoutExercise.comment = workoutRoutineExercise.comment
                workoutExercise.restTimerDurationValue = workoutRoutineExercise.restTimerDurationValue
                workoutExercise.supersetUuid = workoutRoutineExercise.supersetUuid
                
                if let workoutRoutineSets = workoutRoutineExercise.workoutRoutineSets?.compactMap({ $0 as? WorkoutRoutineSet }) {
                    // copy the sets
                    for workoutRoutineSet in workoutRoutineSets {
                        let workoutSet = WorkoutSet.create(context: context)
                        workoutSet.workoutExercise = workoutExercise
                        workoutSet.isCompleted = false
                        workoutSet.maxTargetRepetitions = workoutRoutineSet.maxRepetitions
                        workoutSet.minTargetRepetitions = workoutRoutineSet.minRepetitions
                        workoutSet.tagValue = workoutRoutineSet.tagValue
                        workoutSet.comment = workoutRoutineSet.comment
                        workoutSet.weightValue = workoutRoutineSet.weightValue ?? 0
                        workoutSet.durationValue = workoutRoutineSet.durationValue
                    }
                }
            }
        }
        
        addToWorkouts(workout)
        return workout
    }
    
    // MARK: - Codable
    
       private enum CodingKeys: String, CodingKey {
           case uuid
           case title
           case comment
           case exercises
       }
       
       required convenience public init(from decoder: Decoder) throws {
           guard let contextKey = CodingUserInfoKey.managedObjectContextKey,
               let context = decoder.userInfo[contextKey] as? NSManagedObjectContext,
               let entity = NSEntityDescription.entity(forEntityName: "WorkoutRoutine", in: context)
               else {
               throw CodingUserInfoKey.DecodingError.managedObjectContextMissing
           }
           self.init(entity: entity, insertInto: context)
           
           let container = try decoder.container(keyedBy: CodingKeys.self)
           uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid) ?? UUID() // make sure we always have an UUID
           title = try container.decodeIfPresent(String.self, forKey: .title)
           comment = try container.decodeIfPresent(String.self, forKey: .comment)
           workoutRoutineExercises = NSOrderedSet(array: try container.decodeIfPresent([WorkoutRoutineExercise].self, forKey: .exercises) ?? [])
       }
       
       public func encode(to encoder: Encoder) throws {
           var container = encoder.container(keyedBy: CodingKeys.self)
           try container.encode(uuid ?? UUID(), forKey: .uuid)
           try container.encodeIfPresent(title, forKey: .title)
           try container.encodeIfPresent(comment, forKey: .comment)
           try container.encodeIfPresent(workoutRoutineExercises?.array.compactMap { $0 as? WorkoutRoutineExercise }, forKey: .exercises)
       }
}
