import Foundation

/// Curated name equivalences, never a fuzzy merge of workout history.
public struct ExerciseCatalogMetadata {
    private let uniqueNames: [String: Exercise]

    public init(exercises: [Exercise], preferredAliases: [String: UUID] = [:]) {
        var candidates: [String: [Exercise]] = [:]
        for exercise in exercises {
            for name in [exercise.title] + exercise.alias {
                let key = Self.nameKey(name)
                guard !key.isEmpty else { continue }
                if !(candidates[key] ?? []).contains(where: { $0.uuid == exercise.uuid }) {
                    candidates[key, default: []].append(exercise)
                }
            }
        }
        var names = candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
        // Reviewed import mappings take precedence over coincidental duplicate
        // catalog names. Templates may improve text while retaining the same UUID.
        let byID = exercises.reduce(into: [UUID: Exercise]()) { $0[$1.uuid] = $1 }
        for (name, id) in preferredAliases {
            if let exercise = byID[id] { names[Self.nameKey(name)] = exercise }
        }
        uniqueNames = names
    }

    public static func addingAliases(_ aliases: [String: UUID], to exercises: [Exercise]) -> [Exercise] {
        let byID = Dictionary(grouping: aliases.keys, by: { aliases[$0]! })
        return exercises.map { exercise in
            guard let names = byID[exercise.uuid] else { return exercise }
            return copy(exercise, aliases: Array(Set(exercise.alias + names)).sorted())
        }
    }

    /// Update known records in place and append new canonical definitions. Legacy
    /// exercises absent upstream stay available to every existing workout UUID.
    public static func updatingCatalog(_ exercises: [Exercise], with templates: [Exercise]) -> [Exercise] {
        let updates = Dictionary(uniqueKeysWithValues: templates.map { ($0.uuid, $0) })
        let existingIDs = Set(exercises.map(\.uuid))
        return exercises.map { updates[$0.uuid] ?? $0 }
            + templates.filter { !existingIDs.contains($0.uuid) }
    }

    /// Enrich old empty import definitions in memory. Keep the user's UUID/name and
    /// all workout relationships; do not rewrite the custom file or merge histories.
    public func enriching(_ exercise: Exercise) -> Exercise {
        guard exercise.isCustom,
              exercise.primaryMuscle.isEmpty, exercise.secondaryMuscle.isEmpty,
              exercise.pdfPaths.isEmpty,
              exercise.imageFilename == nil, exercise.animationFilename == nil,
              let template = uniqueNames[Self.nameKey(exercise.title)] else { return exercise }

        // Respect a custom equipment choice that contradicts the catalog template.
        let equipment = Set(template.equipment.map(Self.nameKey))
        guard exercise.equipment.allSatisfy({ equipment.contains(Self.nameKey($0)) }) else { return exercise }
        return Exercise(
            uuid: exercise.uuid, everkineticId: exercise.everkineticId,
            title: exercise.title, alias: exercise.alias,
            description: exercise.description ?? template.description,
            primaryMuscle: template.primaryMuscle, secondaryMuscle: template.secondaryMuscle,
            equipment: exercise.equipment.isEmpty ? template.equipment : exercise.equipment,
            steps: exercise.steps.isEmpty ? template.steps : exercise.steps,
            tips: exercise.tips.isEmpty ? template.tips : exercise.tips,
            references: exercise.references.isEmpty ? template.references : exercise.references,
            pdfPaths: template.pdfPaths,
            imageFilename: template.imageFilename, animationFilename: template.animationFilename
        )
    }

    public static func nameKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func copy(_ exercise: Exercise, aliases: [String]) -> Exercise {
        Exercise(
            uuid: exercise.uuid, everkineticId: exercise.everkineticId,
            title: exercise.title, alias: aliases, description: exercise.description,
            primaryMuscle: exercise.primaryMuscle, secondaryMuscle: exercise.secondaryMuscle,
            equipment: exercise.equipment, steps: exercise.steps, tips: exercise.tips,
            references: exercise.references, pdfPaths: exercise.pdfPaths,
            imageFilename: exercise.imageFilename, animationFilename: exercise.animationFilename
        )
    }
}
