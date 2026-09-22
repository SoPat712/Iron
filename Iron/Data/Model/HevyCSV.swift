//
//  HevyCSV.swift
//  Iron
//
//  Imports and exports the CSV format produced by Hevy's user-facing data export.
//  "Hevy" is used only to identify the compatible file format; Iron is not
//  affiliated with or endorsed by Hevy Studios S.L.
//

import CoreData
import Foundation
import SwiftUI
import WorkoutDataKit

struct HevyCSVRecord: Equatable {
    let sourceRow: Int
    let title: String
    let startTime: Date
    let endTime: Date?
    let description: String
    let exerciseTitle: String
    let supersetID: String?
    let exerciseNotes: String
    let setIndex: Int?
    let setType: String
    let weightKilograms: Double?
    let repetitions: Int
    let distanceMeters: Double?
    let durationSeconds: TimeInterval?
    let rpe: Double?
}

struct HevyCSVDocument {
    let records: [HevyCSVRecord]
    let skippedRows: Int
}

struct HevyCSVImportResult: Identifiable {
    let id = UUID()
    let importedWorkouts: Int
    let importedSets: Int
    let importedMeasurements: Int
    let updatedMeasurements: Int
    let createdExercises: Int
    let skippedDuplicateWorkouts: Int
    let skippedDuplicateMeasurements: Int
    let skippedRows: Int

    var title: String {
        importedWorkouts > 0 || importedMeasurements > 0 || updatedMeasurements > 0
            ? "Import Complete"
            : "Nothing New to Import"
    }

    var detail: String {
        var lines = [String]()
        if importedWorkouts > 0 || importedSets > 0 || skippedDuplicateWorkouts > 0 {
            lines.append("\(importedWorkouts) workout\(importedWorkouts == 1 ? "" : "s") imported")
            lines.append("\(importedSets) set\(importedSets == 1 ? "" : "s") imported")
        }
        if importedMeasurements > 0 {
            lines.append("\(importedMeasurements) measurement entr\(importedMeasurements == 1 ? "y" : "ies") imported")
        }
        if updatedMeasurements > 0 {
            lines.append("\(updatedMeasurements) existing measurement entr\(updatedMeasurements == 1 ? "y" : "ies") updated")
        }
        if createdExercises > 0 {
            lines.append("\(createdExercises) missing exercise\(createdExercises == 1 ? "" : "s") created")
        }
        if skippedDuplicateWorkouts > 0 {
            lines.append("\(skippedDuplicateWorkouts) duplicate workout\(skippedDuplicateWorkouts == 1 ? "" : "s") skipped")
        }
        if skippedDuplicateMeasurements > 0 {
            lines.append("\(skippedDuplicateMeasurements) duplicate measurement entr\(skippedDuplicateMeasurements == 1 ? "y" : "ies") skipped")
        }
        if skippedRows > 0 {
            lines.append("\(skippedRows) malformed row\(skippedRows == 1 ? "" : "s") skipped")
        }
        return lines.joined(separator: "\n")
    }

    func combined(with other: HevyCSVImportResult) -> HevyCSVImportResult {
        HevyCSVImportResult(
            importedWorkouts: importedWorkouts + other.importedWorkouts,
            importedSets: importedSets + other.importedSets,
            importedMeasurements: importedMeasurements + other.importedMeasurements,
            updatedMeasurements: updatedMeasurements + other.updatedMeasurements,
            createdExercises: createdExercises + other.createdExercises,
            skippedDuplicateWorkouts: skippedDuplicateWorkouts + other.skippedDuplicateWorkouts,
            skippedDuplicateMeasurements: skippedDuplicateMeasurements + other.skippedDuplicateMeasurements,
            skippedRows: skippedRows + other.skippedRows
        )
    }
}

struct HevyCSVImportOutcome: Identifiable {
    let id = UUID()
    let result: Result<HevyCSVImportResult, Error>
}

enum HevyCSVError: LocalizedError {
    case unreadableText
    case malformedCSV
    case missingColumns([String])
    case noWorkoutRows
    case couldNotCreateExercise(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "Iron could not read this file as UTF-8 CSV."
        case .malformedCSV:
            return "The CSV contains an unfinished quoted field."
        case .missingColumns(let columns):
            return "This does not look like a Hevy workout export. Missing: \(columns.joined(separator: ", "))."
        case .noWorkoutRows:
            return "The Hevy CSV does not contain any valid workout rows."
        case .couldNotCreateExercise(let title):
            return "Iron could not create the missing exercise “\(title)”."
        }
    }
}

enum HevyCSV {
    private static let requiredColumns = ["title", "start_time", "exercise_title", "set_index"]
    private static let inputDateFormatters: [DateFormatter] = {
        ["d MMM yyyy, HH:mm:ss", "dd MMM yyyy, HH:mm:ss", "d MMM yyyy, HH:mm", "dd MMM yyyy, HH:mm"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }
    }()
    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    private struct WorkoutKey: Hashable {
        let startSecond: Int64
        let normalizedTitle: String
    }

    private struct WorkoutGroup {
        let key: WorkoutKey
        var records: [HevyCSVRecord]
    }

    private struct ExerciseRun {
        var records: [HevyCSVRecord]
    }

    private struct MeasurementDocument {
        let entries: [BodyMeasurementEntry]
        let skippedRows: Int
    }

    static func parse(data: Data) throws -> HevyCSVDocument {
        guard var text = String(data: data, encoding: .utf8) else {
            throw HevyCSVError.unreadableText
        }
        if text.first == "\u{FEFF}" {
            text.removeFirst()
        }

        let rows = try parseRows(text)
        guard let rawHeader = rows.first else { throw HevyCSVError.noWorkoutRows }
        let header = rawHeader.map(normalizeHeader)
        let missingColumns = requiredColumns.filter { !header.contains($0) }
        guard missingColumns.isEmpty else { throw HevyCSVError.missingColumns(missingColumns) }

        var records = [HevyCSVRecord]()
        var skippedRows = 0
        for (offset, fields) in rows.dropFirst().enumerated() {
            guard fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            let values = rowValues(header: header, fields: fields)
            do {
                records.append(try record(values: values, sourceRow: offset + 2))
            } catch {
                skippedRows += 1
            }
        }

        guard !records.isEmpty else { throw HevyCSVError.noWorkoutRows }
        return HevyCSVDocument(records: records, skippedRows: skippedRows)
    }

    static func importData(
        _ data: Data,
        into context: NSManagedObjectContext,
        exerciseStore: ExerciseStore,
        bodyMetricsStore: BodyMetricsStore = .shared
    ) throws -> HevyCSVImportResult {
        if try isMeasurementDocument(data) {
            return try importMeasurementData(data, into: bodyMetricsStore)
        }

        let document = try parse(data: data)
        let groups = workoutGroups(from: document.records)

        var resolvedExercises = [String: Exercise]()
        var createdExerciseNames = Set<String>()
        for record in document.records {
            let key = normalizedName(record.exerciseTitle)
            guard resolvedExercises[key] == nil else { continue }
            if let exercise = matchExercise(named: record.exerciseTitle, in: exerciseStore.exercises) {
                resolvedExercises[key] = exercise
                continue
            }

            do {
                try exerciseStore.createCustomExercise(
                    title: record.exerciseTitle,
                    description: nil,
                    primaryMuscle: [],
                    secondaryMuscle: [],
                    type: inferredExerciseType(from: record.exerciseTitle)
                )
            } catch {
                throw HevyCSVError.couldNotCreateExercise(record.exerciseTitle)
            }
            guard let exercise = matchExercise(named: record.exerciseTitle, in: exerciseStore.exercises) else {
                throw HevyCSVError.couldNotCreateExercise(record.exerciseTitle)
            }
            resolvedExercises[key] = exercise
            createdExerciseNames.insert(key)
        }

        return try context.performAndWait { context in
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(value: true))
            let existingWorkouts = try context.fetch(request)
            var existingKeys = Set(existingWorkouts.map {
                workoutKey(start: $0.safeStart, title: $0.displayTitle(in: exerciseStore.exercises))
            })

            var insertedObjects = [NSManagedObject]()
            var importedWorkouts = 0
            var importedSets = 0
            var skippedDuplicates = 0

            do {
                for group in groups {
                    guard !existingKeys.contains(group.key), let first = group.records.first else {
                        skippedDuplicates += 1
                        continue
                    }

                    let workout = Workout.create(context: context)
                    insertedObjects.append(workout)
                    workout.title = nonempty(first.title) ?? "Workout"
                    workout.comment = nonempty(unescapeNewlines(first.description))
                    workout.start = first.startTime
                    let parsedEnd = group.records.compactMap(\.endTime).max()
                    workout.end = max(parsedEnd ?? first.startTime, first.startTime)
                    workout.isCurrentWorkout = false

                    let exerciseRuns = splitExerciseRuns(group.records)
                    var supersetUUIDs = [String: UUID]()
                    for run in exerciseRuns {
                        guard let firstExerciseRecord = run.records.first,
                              let exercise = resolvedExercises[normalizedName(firstExerciseRecord.exerciseTitle)] else { continue }

                        let workoutExercise = WorkoutExercise.create(context: context)
                        insertedObjects.append(workoutExercise)
                        workoutExercise.exerciseUuid = exercise.uuid
                        workoutExercise.comment = nonempty(unescapeNewlines(firstExerciseRecord.exerciseNotes))
                        if let sourceSupersetID = nonempty(firstExerciseRecord.supersetID) {
                            let uuid = supersetUUIDs[sourceSupersetID] ?? UUID()
                            supersetUUIDs[sourceSupersetID] = uuid
                            workoutExercise.supersetUuid = uuid
                        }
                        workout.addToWorkoutExercises(workoutExercise)

                        for record in run.records.sorted(by: setOrder) {
                            let workoutSet = WorkoutSet.create(context: context)
                            insertedObjects.append(workoutSet)
                            workoutSet.weightValue = max(record.weightKilograms ?? 0, 0)
                            workoutSet.repetitionsValue = Int16(clamping: record.repetitions)
                            workoutSet.durationValue = record.durationSeconds
                            workoutSet.distanceValue = record.distanceMeters
                            workoutSet.rpeValue = record.rpe
                            workoutSet.tagValue = workoutSetTag(for: record.setType)
                            workoutSet.completedAt = workout.end
                            workoutSet.isCompleted = true
                            workoutExercise.addToWorkoutSets(workoutSet)
                            importedSets += 1
                        }
                    }

                    importedWorkouts += 1
                    existingKeys.insert(group.key)
                }

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                insertedObjects.reversed().forEach { object in
                    if !object.isDeleted { context.delete(object) }
                }
                throw error
            }

            return HevyCSVImportResult(
                importedWorkouts: importedWorkouts,
                importedSets: importedSets,
                importedMeasurements: 0,
                updatedMeasurements: 0,
                createdExercises: createdExerciseNames.count,
                skippedDuplicateWorkouts: skippedDuplicates,
                skippedDuplicateMeasurements: 0,
                skippedRows: document.skippedRows
            )
        }
    }

    /// Imports every selected Hevy CSV as one operation. All files are parsed
    /// before the first write so a malformed second file cannot leave the
    /// first file partially imported.
    static func importData(
        _ dataDocuments: [Data],
        into context: NSManagedObjectContext,
        exerciseStore: ExerciseStore,
        bodyMetricsStore: BodyMetricsStore = .shared
    ) throws -> HevyCSVImportResult {
        guard !dataDocuments.isEmpty else { throw HevyCSVError.noWorkoutRows }

        try dataDocuments.forEach(validateImportData)

        var combinedResult: HevyCSVImportResult?
        for data in dataDocuments {
            let result = try importData(
                data,
                into: context,
                exerciseStore: exerciseStore,
                bodyMetricsStore: bodyMetricsStore
            )
            combinedResult = combinedResult.map { $0.combined(with: result) } ?? result
        }
        guard let combinedResult else { throw HevyCSVError.noWorkoutRows }
        return combinedResult
    }

    static func exportMeasurementData(
        entries: [BodyMeasurementEntry],
        weightUnit: WeightUnit
    ) throws -> Data {
        let weightColumn = weightUnit == .imperial ? "weight_lbs" : "weight_kg"
        let lengthSuffix = weightUnit == .imperial ? "in" : "cm"
        let mappings: [(String, BodyMeasurementKind)] = [
            ("height_\(lengthSuffix)", .height),
            ("neck_\(lengthSuffix)", .neck),
            ("shoulder_\(lengthSuffix)", .shoulders),
            ("chest_\(lengthSuffix)", .chest),
            ("left_bicep_\(lengthSuffix)", .leftBicep),
            ("right_bicep_\(lengthSuffix)", .rightBicep),
            ("left_forearm_\(lengthSuffix)", .leftForearm),
            ("right_forearm_\(lengthSuffix)", .rightForearm),
            ("abdomen_\(lengthSuffix)", .abdomen),
            ("waist_\(lengthSuffix)", .waist),
            ("hips_\(lengthSuffix)", .hips),
            ("left_thigh_\(lengthSuffix)", .leftThigh),
            ("right_thigh_\(lengthSuffix)", .rightThigh),
            ("left_calf_\(lengthSuffix)", .leftCalf),
            ("right_calf_\(lengthSuffix)", .rightCalf)
        ]
        let header = ["date", weightColumn, "fat_percent"] + mappings.map { $0.0 }
        var rows = [header]

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let weight = entry[.bodyWeight].map {
                BodyMeasurementKind.bodyWeight.displayValue(from: $0, weightUnit: weightUnit)
            }
            var row = [
                formatDate(entry.date),
                weight.map(formatNumber) ?? "",
                entry[.bodyFat].map(formatNumber) ?? ""
            ]
            row.append(contentsOf: mappings.map { _, kind in
                entry[kind]
                    .map { kind.displayValue(from: $0, weightUnit: weightUnit) }
                    .map(formatNumber) ?? ""
            })
            rows.append(row)
        }

        let csv = rows.enumerated().map { index, row in
            if index == 0 { return row.map(quote).joined(separator: ",") }
            return row.enumerated().map { column, value in
                column == 0 ? quote(value) : value
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        guard let data = csv.data(using: .utf8) else { throw HevyCSVError.unreadableText }
        return data
    }

    static func exportData(
        workouts: [Workout],
        exercises: [Exercise],
        weightUnit: WeightUnit
    ) throws -> Data {
        let weightColumn = weightUnit == .imperial ? "weight_lbs" : "weight_kg"
        let distanceColumn = weightUnit == .imperial ? "distance_miles" : "distance_km"
        let header = [
            "title", "start_time", "end_time", "description", "exercise_title",
            "superset_id", "exercise_notes", "set_index", "set_type", weightColumn,
            "reps", distanceColumn, "duration_seconds", "rpe"
        ]

        var rows = [header]
        for workout in workouts {
            let title = workout.displayTitle(in: exercises)
            let start = formatDate(workout.safeStart)
            let end = formatDate(workout.safeEnd)
            let description = workout.comment ?? ""
            let workoutExercises = workout.workoutExercises?.array.compactMap { $0 as? WorkoutExercise } ?? []
            var supersetIDs = [UUID: String]()

            for workoutExercise in workoutExercises {
                guard let exercise = workoutExercise.exercise(in: exercises) else { continue }
                let completedSets = workoutExercise.workoutSets?.array
                    .compactMap { $0 as? WorkoutSet }
                    .filter(\.isCompleted) ?? []
                let supersetID: String
                if let uuid = workoutExercise.supersetUuid {
                    if let existing = supersetIDs[uuid] {
                        supersetID = existing
                    } else {
                        let next = String(supersetIDs.count)
                        supersetIDs[uuid] = next
                        supersetID = next
                    }
                } else {
                    supersetID = ""
                }

                for (index, workoutSet) in completedSets.enumerated() {
                    let exportedWeight: Double
                    switch weightUnit {
                    case .metric:
                        exportedWeight = workoutSet.weightValue
                    case .imperial:
                        exportedWeight = Measurement(value: workoutSet.weightValue, unit: UnitMass.kilograms)
                            .converted(to: .pounds).value
                    }

                    let exportedDistance: Double?
                    if let distanceMeters = workoutSet.distanceValue {
                        let distance = Measurement(value: distanceMeters, unit: UnitLength.meters)
                        exportedDistance = weightUnit == .imperial
                            ? distance.converted(to: .miles).value
                            : distance.converted(to: .kilometers).value
                    } else {
                        exportedDistance = nil
                    }

                    rows.append([
                        title,
                        start,
                        end,
                        description,
                        exercise.title,
                        supersetID,
                        workoutExercise.comment ?? "",
                        String(index),
                        hevySetType(for: workoutSet.tagValue),
                        formatNumber(exportedWeight),
                        String(workoutSet.repetitionsValue),
                        exportedDistance.map(formatNumber) ?? "",
                        workoutSet.durationValue.map(formatNumber) ?? "",
                        workoutSet.rpeValue.map(formatNumber) ?? ""
                    ])
                }
            }
        }

        let quotedTextColumns: Set<Int> = [0, 1, 2, 3, 4, 6, 8]
        let csv = rows.enumerated().map { index, row in
            if index == 0 { return row.map(quote).joined(separator: ",") }
            return row.enumerated().map { column, value in
                quotedTextColumns.contains(column) ? quote(value) : value
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        guard let data = csv.data(using: .utf8) else { throw HevyCSVError.unreadableText }
        return data
    }

    private static func record(values: [String: String], sourceRow: Int) throws -> HevyCSVRecord {
        let title = values["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exerciseTitle = values["exercise_title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !exerciseTitle.isEmpty,
              let startTimeString = nonempty(values["start_time"]),
              let startTime = parseDate(startTimeString) else {
            throw HevyCSVError.noWorkoutRows
        }

        let weightKilograms: Double?
        if let kilograms = try parseNumber(values["weight_kg"]) {
            weightKilograms = kilograms
        } else if let pounds = try parseNumber(values["weight_lbs"]) {
            weightKilograms = Measurement(value: pounds, unit: UnitMass.pounds).converted(to: .kilograms).value
        } else {
            weightKilograms = nil
        }

        let distanceMeters: Double?
        if let kilometers = try parseNumber(values["distance_km"]) {
            distanceMeters = Measurement(value: kilometers, unit: UnitLength.kilometers).converted(to: .meters).value
        } else if let miles = try parseNumber(values["distance_miles"]) {
            distanceMeters = Measurement(value: miles, unit: UnitLength.miles).converted(to: .meters).value
        } else {
            distanceMeters = nil
        }

        let repetitions = try parseInteger(values["reps"]) ?? 0
        let setIndex = try parseInteger(values["set_index"])
        let duration = try parseNumber(values["duration_seconds"])
        let rpe = try parseNumber(values["rpe"])
        guard [weightKilograms, distanceMeters].compactMap({ $0 }).allSatisfy(\.isFinite) else {
            throw HevyCSVError.noWorkoutRows
        }

        return HevyCSVRecord(
            sourceRow: sourceRow,
            title: title,
            startTime: startTime,
            endTime: nonempty(values["end_time"]).flatMap(parseDate),
            description: values["description"] ?? "",
            exerciseTitle: exerciseTitle,
            supersetID: nonempty(values["superset_id"]),
            exerciseNotes: values["exercise_notes"] ?? "",
            setIndex: setIndex,
            setType: values["set_type"] ?? "normal",
            weightKilograms: weightKilograms,
            repetitions: max(repetitions, 0),
            distanceMeters: distanceMeters,
            durationSeconds: duration.map { max($0, 0) },
            rpe: rpe
        )
    }

    private static func isMeasurementDocument(_ data: Data) throws -> Bool {
        guard var text = String(data: data, encoding: .utf8) else { throw HevyCSVError.unreadableText }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard let firstRow = try parseRows(text).first else { throw HevyCSVError.noWorkoutRows }
        let header = Set(firstRow.map(normalizeHeader))
        return header.contains("date")
            && !header.contains("start_time")
            && !header.isDisjoint(with: supportedMeasurementColumns)
    }

    private static let supportedMeasurementColumns: Set<String> = {
        let scalarColumns = ["weight_lbs", "weight_kg", "fat_percent"]
        let lengthColumns = [
            "height", "neck", "shoulder", "chest", "left_bicep", "right_bicep",
            "left_forearm", "right_forearm", "abdomen", "waist", "hips",
            "left_thigh", "right_thigh", "left_calf", "right_calf"
        ].flatMap { name in
            ["\(name)_in", "\(name)_cm"]
        }
        return Set(scalarColumns + lengthColumns)
    }()

    private static func validateImportData(_ data: Data) throws {
        if try isMeasurementDocument(data) {
            _ = try parseMeasurementData(data)
        } else {
            _ = try parse(data: data)
        }
    }

    private static func importMeasurementData(
        _ data: Data,
        into store: BodyMetricsStore
    ) throws -> HevyCSVImportResult {
        let document = try parseMeasurementData(data)
        let importedEntries = document.entries

        var knownEntries = [Int64: BodyMeasurementEntry]()
        for entry in store.entries {
            knownEntries[Int64(entry.date.timeIntervalSince1970.rounded())] = entry
        }
        var inserted = 0
        var updated = 0
        var duplicates = 0
        for entry in importedEntries {
            let key = Int64(entry.date.timeIntervalSince1970.rounded())
            if var existing = knownEntries[key] {
                let mergedValues = existing.values.merging(entry.values) { _, imported in imported }
                guard mergedValues != existing.values else {
                    duplicates += 1
                    continue
                }
                existing.values = mergedValues
                store.save(existing, exportToHealth: false)
                knownEntries[key] = existing
                updated += 1
            } else {
                store.save(entry, exportToHealth: false)
                knownEntries[key] = entry
                inserted += 1
            }
        }

        return HevyCSVImportResult(
            importedWorkouts: 0,
            importedSets: 0,
            importedMeasurements: inserted,
            updatedMeasurements: updated,
            createdExercises: 0,
            skippedDuplicateWorkouts: 0,
            skippedDuplicateMeasurements: duplicates,
            skippedRows: document.skippedRows
        )
    }

    private static func parseMeasurementData(_ data: Data) throws -> MeasurementDocument {
        guard var text = String(data: data, encoding: .utf8) else { throw HevyCSVError.unreadableText }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let rows = try parseRows(text)
        guard let rawHeader = rows.first else { throw HevyCSVError.noWorkoutRows }
        let header = rawHeader.map(normalizeHeader)
        guard header.contains("date") else { throw HevyCSVError.missingColumns(["date"]) }

        let lengthMappings: [(BodyMeasurementKind, String, String)] = [
            (.height, "height_in", "height_cm"),
            (.neck, "neck_in", "neck_cm"),
            (.shoulders, "shoulder_in", "shoulder_cm"),
            (.chest, "chest_in", "chest_cm"),
            (.leftBicep, "left_bicep_in", "left_bicep_cm"),
            (.rightBicep, "right_bicep_in", "right_bicep_cm"),
            (.leftForearm, "left_forearm_in", "left_forearm_cm"),
            (.rightForearm, "right_forearm_in", "right_forearm_cm"),
            (.abdomen, "abdomen_in", "abdomen_cm"),
            (.waist, "waist_in", "waist_cm"),
            (.hips, "hips_in", "hips_cm"),
            (.leftThigh, "left_thigh_in", "left_thigh_cm"),
            (.rightThigh, "right_thigh_in", "right_thigh_cm"),
            (.leftCalf, "left_calf_in", "left_calf_cm"),
            (.rightCalf, "right_calf_in", "right_calf_cm")
        ]

        var importedEntries = [BodyMeasurementEntry]()
        var skippedRows = 0
        for fields in rows.dropFirst() {
            guard fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            let values = rowValues(header: header, fields: fields)
            do {
                guard let rawDate = nonempty(values["date"]), let date = parseDate(rawDate) else {
                    throw HevyCSVError.noWorkoutRows
                }
                var measurementValues = [String: Double]()
                if let kilograms = try parseNumber(values["weight_kg"]) {
                    measurementValues[BodyMeasurementKind.bodyWeight.rawValue] = kilograms
                } else if let pounds = try parseNumber(values["weight_lbs"]) {
                    measurementValues[BodyMeasurementKind.bodyWeight.rawValue] = Measurement(value: pounds, unit: UnitMass.pounds)
                        .converted(to: .kilograms).value
                }
                if let bodyFat = try parseNumber(values["fat_percent"]) {
                    measurementValues[BodyMeasurementKind.bodyFat.rawValue] = bodyFat
                }
                for (kind, inchesColumn, centimetersColumn) in lengthMappings {
                    if let centimeters = try parseNumber(values[centimetersColumn]) {
                        measurementValues[kind.rawValue] = centimeters
                    } else if let inches = try parseNumber(values[inchesColumn]) {
                        measurementValues[kind.rawValue] = Measurement(value: inches, unit: UnitLength.inches)
                            .converted(to: .centimeters).value
                    }
                }
                guard !measurementValues.isEmpty,
                      measurementValues.values.allSatisfy(\.isFinite) else {
                    skippedRows += 1
                    continue
                }
                importedEntries.append(BodyMeasurementEntry(date: date, values: measurementValues))
            } catch {
                skippedRows += 1
            }
        }
        guard !importedEntries.isEmpty else { throw HevyCSVError.noWorkoutRows }
        return MeasurementDocument(entries: importedEntries, skippedRows: skippedRows)
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        // Swift's Character view treats CRLF as one grapheme cluster, so a
        // direct switch on "\r"/"\n" misses Windows row endings. Hevy exports
        // can also mix CRLF and LF in the same file. Normalize first while
        // preserving embedded quoted line breaks as regular LF characters.
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var rows = [[String]]()
        var row = [String]()
        var field = ""
        var insideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if insideQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    insideQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r":
                    row.append(field)
                    field = ""
                    if row.contains(where: { !$0.isEmpty }) {
                        rows.append(row)
                    }
                    row = []
                default:
                    field.append(character)
                }
            }
            index += 1
        }

        guard !insideQuotes else { throw HevyCSVError.malformedCSV }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) {
                rows.append(row)
            }
        }
        return rows
    }

    /// Hevy exports have changed shape over time, and third-party producers can
    /// include blank or repeated columns. Keep the first non-empty value for a
    /// column instead of trapping in Dictionary(uniqueKeysWithValues:).
    private static func rowValues(header: [String], fields: [String]) -> [String: String] {
        header.enumerated().reduce(into: [String: String]()) { values, element in
            let (index, column) = element
            guard !column.isEmpty else { return }
            let candidate = index < fields.count ? fields[index] : ""
            if values[column]?.isEmpty != false || !candidate.isEmpty {
                values[column] = candidate
            }
        }
    }

    private static func workoutGroups(from records: [HevyCSVRecord]) -> [WorkoutGroup] {
        var groups = [WorkoutGroup]()
        var indexes = [WorkoutKey: Int]()
        for record in records {
            let key = workoutKey(start: record.startTime, title: record.title)
            if let index = indexes[key] {
                groups[index].records.append(record)
            } else {
                indexes[key] = groups.count
                groups.append(WorkoutGroup(key: key, records: [record]))
            }
        }
        return groups
    }

    private static func splitExerciseRuns(_ records: [HevyCSVRecord]) -> [ExerciseRun] {
        var runs = [ExerciseRun]()
        for record in records {
            if let lastRun = runs.last,
               let previous = lastRun.records.last,
               normalizedName(previous.exerciseTitle) == normalizedName(record.exerciseTitle),
               record.setIndex == nil || previous.setIndex == nil || record.setIndex! > previous.setIndex! {
                runs[runs.count - 1].records.append(record)
            } else {
                runs.append(ExerciseRun(records: [record]))
            }
        }
        return runs
    }

    private static func workoutKey(start: Date, title: String) -> WorkoutKey {
        WorkoutKey(
            startSecond: Int64(start.timeIntervalSince1970.rounded()),
            normalizedTitle: normalizedName(title.isEmpty ? "Workout" : title)
        )
    }

    private static func matchExercise(named title: String, in exercises: [Exercise]) -> Exercise? {
        let normalized = normalizedName(title)
        if let exact = exercises.first(where: { exercise in
            ([exercise.title] + exercise.alias).contains { normalizedName($0) == normalized }
        }) {
            return exact
        }

        let tokens = normalizedTokens(title)
        return exercises.first(where: { exercise in
            ([exercise.title] + exercise.alias).contains { normalizedTokens($0) == tokens }
        })
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        normalizedName(value)
            .split(separator: " ")
            .map(String.init)
            .map { token in
                switch token {
                case "bb": return "barbell"
                case "db", "dumbbells": return "dumbbell"
                case "kgs": return "kg"
                case "lbs": return "lb"
                default: return token
                }
            }
            .sorted()
    }

    private static func inferredExerciseType(from title: String) -> Exercise.ExerciseType {
        let normalized = normalizedName(title)
        if normalized.contains("barbell") || normalized.contains(" bb ") || normalized.hasPrefix("bb ") {
            return .barbell
        }
        if normalized.contains("dumbbell") || normalized.contains(" db ") || normalized.hasPrefix("db ") {
            return .dumbbell
        }
        return .other
    }

    private static func workoutSetTag(for rawValue: String) -> WorkoutSetTag? {
        switch normalizeHeader(rawValue).replacingOccurrences(of: "_", with: "") {
        case "warmup", "warm": return .warmUp
        case "drop", "dropset": return .dropSet
        case "failure", "failureset": return .failure
        default: return nil
        }
    }

    private static func hevySetType(for tag: WorkoutSetTag?) -> String {
        switch tag {
        case .warmUp: return "warmup"
        case .dropSet: return "dropset"
        case .failure: return "failure"
        case nil: return "normal"
        }
    }

    private static func setOrder(_ lhs: HevyCSVRecord, _ rhs: HevyCSVRecord) -> Bool {
        switch (lhs.setIndex, rhs.setIndex) {
        case let (left?, right?):
            return left == right ? lhs.sourceRow < rhs.sourceRow : left < right
        default:
            return lhs.sourceRow < rhs.sourceRow
        }
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func parseNumber(_ value: String?) throws -> Double? {
        guard let value = nonempty(value) else { return nil }
        guard let number = Double(value), number.isFinite else { throw HevyCSVError.noWorkoutRows }
        return number
    }

    private static func parseInteger(_ value: String?) throws -> Int? {
        guard let number = try parseNumber(value) else { return nil }
        // Preserve the CSV importer's truncation of fractional counts without
        // trapping when an external file contains an out-of-range integer.
        guard let integer = Int(exactly: number.rounded(.towardZero)) else {
            throw HevyCSVError.noWorkoutRows
        }
        return integer
    }

    private static func parseDate(_ value: String) -> Date? {
        for formatter in inputDateFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func formatDate(_ date: Date) -> String {
        outputDateFormatter.string(from: date)
    }

    private static func formatNumber(_ value: Double) -> String {
        var result = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result.isEmpty ? "0" : result
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func unescapeNewlines(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
    }
}

struct HevyCSVImportResultSheet: View {
    let outcome: HevyCSVImportOutcome

    var body: some View {
        IronStatusSheet(
            headerTitle: "CSV Import",
            title: title,
            message: detail,
            systemImage: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            tint: isSuccess ? IronTheme.success : IronTheme.danger
        )
    }

    private var isSuccess: Bool {
        if case .success = outcome.result { return true }
        return false
    }

    private var title: String {
        switch outcome.result {
        case .success(let result): return result.title
        case .failure: return "Import Failed"
        }
    }

    private var detail: String {
        switch outcome.result {
        case .success(let result): return result.detail
        case .failure(let error): return error.localizedDescription
        }
    }
}
