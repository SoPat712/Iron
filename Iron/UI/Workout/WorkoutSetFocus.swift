//
//  WorkoutSetFocus.swift
//  Iron
//
//  The one set that should receive the focused editor in the active workout.
//

import CoreData
import WorkoutDataKit

/// Identifies the single set that is currently promoted for focused entry.
///
/// A superset is treated as one ordered unit. Within that unit, the next round
/// is the lowest incomplete set index among its members; the original exercise
/// order breaks ties. This keeps alternating groups in round-robin order while
/// never jumping over an unfinished set in an individual exercise.
struct WorkoutSetFocus: Equatable {
    let exerciseID: NSManagedObjectID
    let setID: NSManagedObjectID

    private struct Unit {
        var members: [WorkoutExercise]
    }

    private struct Candidate {
        let setIndex: Int
        let memberIndex: Int
        let exercise: WorkoutExercise
        let set: WorkoutSet

        func precedes(_ other: Candidate) -> Bool {
            if setIndex != other.setIndex { return setIndex < other.setIndex }
            return memberIndex < other.memberIndex
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.exerciseID == rhs.exerciseID && lhs.setID == rhs.setID
    }

    /// Returns the next set to focus without changing the Core Data graph.
    ///
    /// Exercises with the same non-nil superset UUID share a unit even when
    /// they are separated in the workout's ordered relationship. Exercises
    /// without a superset remain independent units in their first-appearance
    /// order.
    static func next(in workout: Workout) -> Self? {
        guard workout.isCurrentWorkout else { return nil }

        let exercises = (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).filter { !$0.isDeleted }
        guard !exercises.isEmpty else { return nil }

        var units: [Unit] = []
        var supersetUnitIndex: [UUID: Int] = [:]

        for exercise in exercises {
            if let supersetID = exercise.supersetUuid {
                if let unitIndex = supersetUnitIndex[supersetID] {
                    units[unitIndex].members.append(exercise)
                } else {
                    supersetUnitIndex[supersetID] = units.count
                    units.append(Unit(members: [exercise]))
                }
            } else {
                units.append(Unit(members: [exercise]))
            }
        }

        for unit in units {
            var candidate: Candidate?

            for (memberIndex, exercise) in unit.members.enumerated() {
                let sets = (exercise.workoutSets?.array as? [WorkoutSet] ?? []).filter { !$0.isDeleted }
                guard let setIndex = sets.firstIndex(where: { !$0.isCompleted }) else { continue }
                let set = sets[setIndex]

                let memberCandidate = Candidate(
                    setIndex: setIndex,
                    memberIndex: memberIndex,
                    exercise: exercise,
                    set: set
                )
                if let current = candidate {
                    if memberCandidate.precedes(current) { candidate = memberCandidate }
                } else {
                    candidate = memberCandidate
                }
            }

            if let candidate {
                return Self(exerciseID: candidate.exercise.objectID, setID: candidate.set.objectID)
            }
        }

        return nil
    }
}
