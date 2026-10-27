import Combine
import CoreData
import Foundation
import WorkoutDataKit

/// Immutable dashboard values. Managed objects stay on their context's queue;
/// screens only resolve an object ID when opening a workout.
struct TrainingExerciseSnapshot {
    let id: NSManagedObjectID
    let uuid: UUID?
    let setCount: Int
    let repetitions: Int
    let volume: Double
}

struct TrainingSessionSnapshot: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let title: String?
    let duration: TimeInterval
    let setCount: Int
    let repetitions: Int
    let volume: Double
    let effort: Double?
    let exercises: [TrainingExerciseSnapshot]
}

struct TrainingExerciseTotals {
    var sessions: Int = 0
    var sets: Int = 0
    var lastTrained: Date = .distantPast
}

struct TrainingHistorySnapshot {
    var sessions: [TrainingSessionSnapshot] = []
    var byDay: [Date: [TrainingSessionSnapshot]] = [:]
    var trainedWeeks: Set<Date> = []
    var exerciseTotals: [UUID: TrainingExerciseTotals] = [:]
    var recordSetIDs: Set<NSManagedObjectID> = []

    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        var count = 0
        for offset in 0..<520 {
            if trainedWeeks.contains(week) { count += 1 }
            else if offset > 0 { break }
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    static func build(from workouts: [Workout], calendar: Calendar = .current) -> Self {
        var result = Self()
        for workout in workouts where !workout.isCurrentWorkout {
            let exercises = (workout.workoutExercises?.array as? [WorkoutExercise] ?? []).compactMap { exercise -> TrainingExerciseSnapshot? in
                let sets = (exercise.workoutSets?.array as? [WorkoutSet] ?? []).filter(\.isCompleted)
                guard !sets.isEmpty else { return nil }
                let volume = sets.reduce(0.0) { sum, set in
                    let value = set.weightValue * Double(set.repetitionsValue)
                    return sum + (value.isFinite ? value : 0)
                }
                return TrainingExerciseSnapshot(id: exercise.objectID, uuid: exercise.exerciseUuid,
                    setCount: sets.count, repetitions: sets.reduce(0) { $0 + Int($1.repetitionsValue) }, volume: volume)
            }
            guard !exercises.isEmpty else { continue }
            let date = workout.start ?? .distantPast
            let session = TrainingSessionSnapshot(id: workout.objectID, date: date, title: workout.title,
                duration: max(0, workout.duration ?? 0), setCount: exercises.reduce(0) { $0 + $1.setCount },
                repetitions: exercises.reduce(0) { $0 + $1.repetitions }, volume: exercises.reduce(0) { $0 + $1.volume },
                effort: workout.sessionEffortValue, exercises: exercises)
            result.sessions.append(session)
            if let week = calendar.dateInterval(of: .weekOfYear, for: date) { result.trainedWeeks.insert(week.start) }
            result.byDay[calendar.startOfDay(for: date), default: []].append(session)
            // Count a workout once even if the same exercise appears twice.
            for (uuid, entries) in Dictionary(grouping: exercises.compactMap { entry in entry.uuid.map { ($0, entry) } }, by: { $0.0 }) {
                var total = result.exerciseTotals[uuid, default: TrainingExerciseTotals()]
                total.sessions += 1
                total.sets += entries.reduce(0) { $0 + $1.1.setCount }
                total.lastTrained = max(total.lastTrained, date)
                result.exerciseTotals[uuid] = total
            }
        }
        result.sessions.sort { $0.date > $1.date }
        result.recordSetIDs = TrainingRecordIndex.recordSetIDs(in: workouts.filter { !$0.isCurrentWorkout })
        return result
    }
}

/// One debounced background history read shared by Home, History and day recaps.
/// No history traversal, Core Data faulting or catalog search runs from a view body.
@MainActor final class TrainingHistoryStore: ObservableObject {
    static let shared = TrainingHistoryStore()
    @Published private(set) var snapshot = TrainingHistorySnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var context: NSManagedObjectContext?
    private var observers: Set<AnyCancellable> = []
    private var refreshPending = false

    func observe(in source: NSManagedObjectContext) {
        guard let coordinator = source.persistentStoreCoordinator,
              context?.persistentStoreCoordinator !== coordinator else { return }
        let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        reader.persistentStoreCoordinator = coordinator
        reader.undoManager = nil
        context = reader
        observers.removeAll()
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { notification in
                guard (notification.object as? NSManagedObjectContext)?.persistentStoreCoordinator === coordinator else { return false }
                let entities: Set<String> = ["Workout", "WorkoutExercise", "WorkoutSet"]
                return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
                    (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains { entities.contains($0.entity.name ?? "") } ?? false
                }
            }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &observers)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &observers)
        refresh()
    }

    func refresh() {
        guard let context else { return }
        guard !isLoading else { refreshPending = true; return }
        isLoading = true
        Task {
            do {
                let value = try await context.perform {
                    defer { context.reset() }
                    let request = Workout.fetchRequest()
                    request.predicate = NSPredicate(format: "isCurrentWorkout != YES")
                    request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
                    request.relationshipKeyPathsForPrefetching = ["workoutExercises", "workoutExercises.workoutSets"]
                    return TrainingHistorySnapshot.build(from: try context.fetch(request))
                }
                snapshot = value
                error = nil
            } catch { self.error = error.localizedDescription }
            isLoading = false
            if refreshPending { refreshPending = false; refresh() }
        }
    }
}

/// A small Pareto frontier of weight/repetition pairs, matching the model's
/// "no earlier set with both weight and reps >= this set" record rule.
private struct TrainingRecordFrontier {
    private var pairs: [(weight: Double, reps: Int16)] = []

    func dominates(weight: Double, reps: Int16) -> Bool {
        pairs.contains { $0.weight >= weight && $0.reps >= reps }
    }

    mutating func insert(weight: Double, reps: Int16) {
        guard !dominates(weight: weight, reps: reps) else { return }
        pairs.removeAll { weight >= $0.weight && reps >= $0.reps }
        pairs.append((weight, reps))
    }
}

private enum TrainingRecordIndex {
    static func recordSetIDs(in workouts: [Workout]) -> Set<NSManagedObjectID> {
        var records: Set<NSManagedObjectID> = []
        var trained: Set<UUID> = []
        var previous: [UUID: TrainingRecordFrontier] = [:]
        let dated = Dictionary(grouping: workouts.filter { $0.start != nil }, by: { $0.start! })

        // Workouts sharing a start are peers, never each other's prior history.
        for date in dated.keys.sorted() {
            let batch = dated[date] ?? []
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    var earlier = TrainingRecordFrontier()
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] {
                        if set.isCompleted, set.weight != nil, set.repetitions != nil,
                           set.repetitionsValue > 0, trained.contains(uuid),
                           !(previous[uuid]?.dominates(weight: set.weightValue, reps: set.repetitionsValue) ?? false),
                           !earlier.dominates(weight: set.weightValue, reps: set.repetitionsValue) {
                            records.insert(set.objectID)
                        }
                        // The model also considers earlier uncompleted sets in
                        // the same exercise when suppressing duplicate records.
                        earlier.insert(weight: set.weightValue, reps: set.repetitionsValue)
                    }
                }
            }
            for workout in batch {
                for exercise in workout.workoutExercises?.array as? [WorkoutExercise] ?? [] {
                    guard let uuid = exercise.exerciseUuid else { continue }
                    for set in exercise.workoutSets?.array as? [WorkoutSet] ?? [] where set.isCompleted {
                        trained.insert(uuid)
                        if let weight = set.weight, let reps = set.repetitions {
                            previous[uuid, default: TrainingRecordFrontier()].insert(
                                weight: weight.doubleValue, reps: reps.int16Value
                            )
                        }
                    }
                }
            }
        }
        return records
    }
}
