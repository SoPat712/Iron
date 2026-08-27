//
//  ExerciseStore.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import os.log

public class ExerciseStore: ObservableObject {
    public static var defaultBuiltInExercisesResourceURL: URL {
        Bundle(for: Self.self).bundleURL.appendingPathComponent("everkinetic-data")
    }
    
    public static var defaultBuiltInExercisesURL: URL {
        defaultBuiltInExercisesResourceURL.appendingPathComponent("exercises.json")
    }
    
    public let builtInExercises: [Exercise]
    
    @Published private(set) public var customExercises: [Exercise]
    
    public var exercises: [Exercise] {
        builtInExercises + customExercises
    }
    
    public var shownExercises: [Exercise] {
        exercises.filter { !isHidden(exercise: $0) }
    }
    
    public var hiddenExercises: [Exercise] {
        exercises.filter { isHidden(exercise: $0) }
    }
    
    private let customExercisesURL: URL?
    
    private let userDefaults: UserDefaults
    
    public init(builtInExercisesURL: URL = ExerciseStore.defaultBuiltInExercisesURL, customExercisesURL: URL?, userDefaults: UserDefaults = UserDefaults.standard) {
        self.userDefaults = userDefaults
        self.customExercisesURL = customExercisesURL
        builtInExercises = Self.loadBuiltInExercises(builtInExercisesURL: builtInExercisesURL)
        customExercises = Self.loadCustomExercises(customExercisesURL: customExercisesURL)
        assert(!customExercises.contains { !$0.isCustom }, "Decoded custom exercise that is not custom.")
    }
    
    private static func loadBuiltInExercises(builtInExercisesURL: URL?) -> [Exercise] {
        guard let builtInExercisesURL = builtInExercisesURL else { fatalError("Built in exercises URL invalid") }
        do {
            return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: builtInExercisesURL))
        } catch {
            fatalError("Error decoding built in exercises: \(error.localizedDescription)")
        }
    }
    
    private static func loadCustomExercises(customExercisesURL: URL?) -> [Exercise] {
        guard let url = customExercisesURL else { return [] }
        do {
            return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        } catch {
            // try to migrate the exercises to the new UUID format
            let success = Self.migrateCustomExercises(customExercisesURL: url)
            guard success else { return [] }
            os_log("Successfully migrated custom exercises", log: .migration, type: .info)
            return (try? JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))) ?? []
        }
    }
}

// MARK: - Hidden Exercises
extension ExerciseStore {
    public func show(exercise: Exercise) {
        assert(!exercise.isCustom, "Makes no sense to show custom exercise.")
        self.objectWillChange.send()
        userDefaults.hiddenExerciseUuids.removeAll { $0 == exercise.uuid }
    }
    
    public func hide(exercise: Exercise) {
        assert(!exercise.isCustom, "Makes no sense to hide custom exercise.")
        guard !isHidden(exercise: exercise) else { return }
        self.objectWillChange.send()
        userDefaults.hiddenExerciseUuids.append(exercise.uuid)
    }
    
    public func isHidden(exercise: Exercise) -> Bool {
        userDefaults.hiddenExerciseUuids.contains(exercise.uuid)
    }
}

// MARK: - Split
extension ExerciseStore {
    public static func splitIntoMuscleGroups(exercises: [Exercise]) -> [ExerciseGroup] {
        var groups = [ExerciseGroup]()
        var nextIndex = 0
        let exercises = exercises.sorted { (a, b) -> Bool in
            a.muscleGroup < b.muscleGroup
        }
        while (exercises.count > nextIndex) {
            let groupName = exercises[nextIndex].muscleGroup
            var muscleGroup = exercises.filter({ (exercise) -> Bool in
                exercise.muscleGroup == groupName
            })
            
            nextIndex = exercises.firstIndex(where: { (exercise) -> Bool in
                exercise.uuid == muscleGroup.last!.uuid
            })! + 1
            
            // do this after nextIndex is set
            muscleGroup = muscleGroup.sorted(by: { (a, b) -> Bool in
                a.title < b.title
            })
            groups.append(ExerciseGroup(title: groupName, exercises: muscleGroup))
        }
        return groups
    }
}

// MARK: - Find
extension ExerciseStore {
    public func find(with uuid: UUID) -> Exercise? {
        Self.find(in: exercises, with: uuid)
    }
    
    public static func find(in exercises: [Exercise], with uuid: UUID?) -> Exercise? {
        guard let uuid = uuid else { return nil }
        return exercises.first { $0.uuid == uuid }
    }
}

// MARK: - Filter
extension ExerciseStore {
    private static func titleMatchesFilter(title: String, filter: String) -> Bool {
        for s in filter.split(separator: " ") {
            if !title.lowercased().contains(s) {
                return false
            }
        }
        return true
    }

    public static func filter(exercises: [Exercise], using filter: String) -> [Exercise] {
        let filter = filter.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !filter.isEmpty else { return exercises }
        
        return exercises.filter { exercise in
            for title in [exercise.title] + exercise.alias {
                if titleMatchesFilter(title: title, filter: filter) {
                    return true
                }
            }
            return false
        }
    }
    
    public static func filter(exerciseGroups: [ExerciseGroup], using filter: String) -> [ExerciseGroup] {
        exerciseGroups
            .map { ExerciseGroup(title: $0.title, exercises: Self.filter(exercises: $0.exercises, using: filter)) }
            .filter { !$0.exercises.isEmpty }
    }
}

// MARK: - Custom Exercises
extension ExerciseStore {
    public enum CustomExerciseMutationError: LocalizedError {
        case invalidTitle
        case duplicateTitle(String)
        case storageUnavailable
        case exerciseNotFound
        case couldNotRead(Error)
        case couldNotWrite(Error)

        public var errorDescription: String? {
            switch self {
            case .invalidTitle:
                return "Enter a name for the exercise."
            case .duplicateTitle(let title):
                return "An exercise named \(title) already exists."
            case .storageUnavailable:
                return "Iron could not access custom-exercise storage."
            case .exerciseNotFound:
                return "This custom exercise no longer exists."
            case .couldNotRead(let error):
                return "Iron could not read your custom exercises: \(error.localizedDescription)"
            case .couldNotWrite(let error):
                return "Iron could not save the custom exercise: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    public func createCustomExercise(
        title: String,
        description: String?,
        primaryMuscle: [String],
        secondaryMuscle: [String],
        type: Exercise.ExerciseType,
        steps: [String] = [],
        tips: [String] = []
    ) throws -> Exercise {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CustomExerciseMutationError.invalidTitle }
        guard !exercises.contains(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else {
            throw CustomExerciseMutationError.duplicateTitle(title)
        }
        
        var description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = description, d.isEmpty {
            description = nil
        }
        
        var customExercises = try loadCustomExercisesForMutation()
        let createdExercise = Exercise(
            uuid: UUID(),
            everkineticId: Exercise.customEverkineticId,
            title: title,
            alias: [],
            description: description,
            primaryMuscle: primaryMuscle,
            secondaryMuscle: secondaryMuscle,
            equipment: type.equipment.map { [$0] } ?? [],
            steps: sanitizedInstructionItems(steps),
            tips: sanitizedInstructionItems(tips),
            references: [],
            pdfPaths: []
        )
        customExercises.append(createdExercise)
        try persistCustomExercises(customExercises)
        return createdExercise
    }

    @discardableResult
    public func updateCustomExercise(
        with uuid: UUID,
        title: String,
        description: String?,
        primaryMuscle: [String],
        secondaryMuscle: [String],
        type: Exercise.ExerciseType,
        steps: [String] = [],
        tips: [String] = []
    ) throws -> Exercise {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CustomExerciseMutationError.invalidTitle }
        guard !exercises.contains(where: {
            $0.uuid != uuid &&
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else {
            throw CustomExerciseMutationError.duplicateTitle(title)
        }
        
        var description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = description, d.isEmpty {
            description = nil
        }
        
        var customExercises = try loadCustomExercisesForMutation()
        guard let index = customExercises.firstIndex(where: { $0.uuid == uuid }) else {
            throw CustomExerciseMutationError.exerciseNotFound
        }
        let existingExercise = customExercises[index]
        let updatedExercise = Exercise(
            uuid: uuid,
            everkineticId: existingExercise.everkineticId,
            title: title,
            alias: existingExercise.alias,
            description: description,
            primaryMuscle: primaryMuscle,
            secondaryMuscle: secondaryMuscle,
            equipment: type.equipment.map { [$0] } ?? [],
            steps: sanitizedInstructionItems(steps),
            tips: sanitizedInstructionItems(tips),
            references: existingExercise.references,
            pdfPaths: existingExercise.pdfPaths,
            imageFilename: existingExercise.imageFilename,
            animationFilename: existingExercise.animationFilename
        )
        customExercises[index] = updatedExercise
        try persistCustomExercises(customExercises)
        return updatedExercise
    }

    private func loadCustomExercisesForMutation() throws -> [Exercise] {
        guard let url = customExercisesURL else {
            throw CustomExerciseMutationError.storageUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        } catch {
            throw CustomExerciseMutationError.couldNotRead(error)
        }
    }

    private func persistCustomExercises(_ exercises: [Exercise]) throws {
        guard let url = customExercisesURL else {
            throw CustomExerciseMutationError.storageUnavailable
        }
        do {
            try JSONEncoder().encode(exercises).write(to: url, options: .atomic)
            customExercises = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        } catch {
            throw CustomExerciseMutationError.couldNotWrite(error)
        }
    }

    private func sanitizedInstructionItems(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    @discardableResult
    public func deleteCustomExercise(with uuid: UUID) throws -> Exercise {
        var customExercises = try loadCustomExercisesForMutation()
        guard let index = customExercises.firstIndex(where: { $0.uuid == uuid }) else {
            throw CustomExerciseMutationError.exerciseNotFound
        }
        let deletedExercise = customExercises.remove(at: index)
        try persistCustomExercises(customExercises)
        return deletedExercise
    }
}

// MARK: - Custom Exercise Migration
extension ExerciseStore {
    private static func migrateCustomExercises(customExercisesURL: URL) -> Bool { // returns true if a migration was made successfully
        do { _ = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: customExercisesURL)) } catch {
            let oldExercises: [ExerciseWithOldId]
            do { oldExercises = try JSONDecoder().decode([ExerciseWithOldId].self, from: Data(contentsOf: customExercisesURL)) } catch { return false }
            let newExercises = oldExercises
                .map {
                    // NOTE: don't overwrite id here, because we still need it in the Core Data migration
                    Exercise(uuid: UUID(), everkineticId: $0.id, title: $0.title, alias: [], description: $0.primer, primaryMuscle: $0.primary, secondaryMuscle: $0.secondary, equipment: $0.equipment, steps: [], tips: [], references: [], pdfPaths: [])
                }
            do { try JSONEncoder().encode(newExercises).write(to: customExercisesURL, options: .atomic) } catch { return false }
            return true
        }
        // no migration needed
        return false
    }
    
    struct ExerciseWithOldId: Codable {
        let id: Int // the old id (before we switched to UUID)
        let title: String
        let primer: String?
        let primary: [String]
        let secondary: [String]
        let equipment: [String]
    }
}

// MARK: - Custom Exercise Restore
extension ExerciseStore {
    enum RestoreError: Error {
        case customExerciseURLIsNil
    }
    public func replaceCustomExercises(with customExercises: [Exercise]) throws {
        guard let url = customExercisesURL else { throw RestoreError.customExerciseURLIsNil }
        try JSONEncoder().encode(customExercises).write(to: url, options: .atomic)
        self.customExercises = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }
}
