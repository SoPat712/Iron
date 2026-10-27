import SwiftUI
import HealthKit
import WidgetKit

enum WatchRoute: Hashable {
    case workout
    case exercise(UUID)
    case set(UUID, UUID)
    case exerciseSettings(UUID)
    case superset(UUID)
    case arrange
    case rest
    case details
    case finish
}

final class WatchNavigation: ObservableObject {
    @Published var path: [WatchRoute] = []
    func openWorkout() { path = [.workout] }
}

struct ContentView: View {
    @ObservedObject private var store = WorkoutSessionManagerStore.shared
    @ObservedObject private var phone = PhoneConnectionManager.shared
    @StateObject private var navigation = WatchNavigation()
    @Environment(\.scenePhase) private var scenePhase
    @State private var restoredNavigation = false

    var body: some View {
        NavigationStack(path: $navigation.path) {
            WatchHomeView()
                .navigationDestination(for: WatchRoute.self) { route in
                    Group {
                    switch route {
                    case .workout: WorkoutSessionView(workoutSessionManager: store.workoutSessionManager)
                    case .exercise(let id): ActiveExerciseView(exerciseID: id)
                    case .set(let exercise, let set): ActiveSetEditor(exerciseID: exercise, setID: set)
                    case .exerciseSettings(let id): ActiveExerciseSettings(exerciseID: id)
                    case .superset(let id): ActiveSupersetEditor(anchorID: id)
                    case .arrange: ArrangeWatchExercisesView()
                    case .rest: WatchRestView()
                    case .details: OptionsView()
                    case .finish: OptionsView(startInFinish: true)
                    }
                    }.watchVitalsInset()
                }
        }
        .environmentObject(store)
        .environmentObject(navigation)
        .onAppear {
            guard !restoredNavigation else { return }
            restoredNavigation = true
            if store.workoutSnapshot != nil { navigation.openWorkout() }
            refreshActiveRoot()
        }
        .onOpenURL { _ in openWorkout() }
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in openWorkout() }
        .onReceive(NotificationCenter.default.publisher(for: .lightOpenWorkout)) { _ in openWorkout() }
        .onChange(of: store.workoutSnapshot?.workoutID) {
            if store.workoutSnapshot != nil { navigation.openWorkout() }
            else { navigation.path = [] }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { refreshActiveRoot() } }
        .alert("Workout Not Saved", isPresented: Binding(
            get: { store.persistenceFailure != nil },
            set: { if !$0 { store.clearPersistenceFailure() } }
        )) {
            Button("OK", role: .cancel) { store.clearPersistenceFailure() }
        } message: { Text(store.persistenceFailure?.message ?? "Please try again.") }
    }

    private func openWorkout() {
        if store.workoutSnapshot != nil { navigation.openWorkout() }
        else { navigation.path = [] }
        refreshActiveRoot()
    }

    private func refreshActiveRoot() {
        store.ensureAutomaticRecording()
        phone.requestLibrary()
        phone.requestCurrentSnapshotIfReady()
    }
}

private struct WatchHomeView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @EnvironmentObject private var navigation: WatchNavigation
    @State private var creating = false
    @State private var showingCurrent = false

    var body: some View {
        let library = store.library
        let saved = library.savedWorkouts.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        List {
            Section {
                Button {
                    if store.workoutSnapshot != nil { showingCurrent = true }
                    else { store.startBlankWorkout() }
                } label: { Text("New Workout").font(.headline).frame(maxWidth: .infinity) }
                .watchGlassButton(prominent: true)
                .listRowBackground(EmptyView())
                if let current = store.workoutSnapshot {
                    NavigationLink(value: WatchRoute.workout) {
                        Label("Resume \(current.title ?? "Workout")", systemImage: "play.fill")
                            .font(.headline).foregroundStyle(IronTheme.accent)
                    }
                }
            }
            Section("Saved Workouts") {
                ForEach(Array(saved.prefix(2))) { workout in
                    NavigationLink { SavedWorkoutDetailView(workoutID: workout.id) } label: {
                        WatchWorkoutSummaryRow(title: workout.title, exercises: workout.exercises)
                    }
                }
                if saved.isEmpty {
                    Button("Create Saved Workout", systemImage: "plus") { creating = true }
                } else {
                    NavigationLink { SavedWorkoutsView() } label: { Text("All Saved Workouts") }
                }
            }
            Section("History") {
                ForEach(Array(library.history.prefix(2)), id: \.workoutID) { workout in
                    NavigationLink { WatchHistoryDetail(workout: workout) } label: {
                        WatchWorkoutSummaryRow(title: workout.title ?? "Workout", exercises: workout.exercises,
                                               date: workout.startDate, duration: workout.recordedDuration)
                    }
                }
                NavigationLink { WatchHistoryView() } label: { Text("All History") }
            }
            Section {
                NavigationLink { WatchSyncView() } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { WatchUnitsView() } label: { Label("Units", systemImage: "scalemass") }
            }
            if let error = store.recordingError {
                Section("Health Recording") {
                    Text(error).font(.caption).foregroundStyle(IronTheme.warning)
                    Button("Dismiss") { store.clearRecordingError() }
                }
            }
        }
        .navigationTitle("Light")
        .watchVitalsInset()
        .alert("Workout in Progress", isPresented: $showingCurrent) {
            Button("Resume Workout") { navigation.openWorkout() }
            Button("Finish Workout") { navigation.path = [.workout, .finish] }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Finish or discard your current workout before starting another.") }
        .sheet(isPresented: $creating) {
            NavigationStack {
                SavedWorkoutEditor(workout: WatchSavedWorkout(id: UUID(), title: "Workout", exercises: [],
                    weightUnit: store.preferredWeightUnit, comment: nil, updatedAt: Date()))
            }
        }
    }
}

struct SavedWorkoutsView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @State private var creating = false

    var body: some View {
        List {
            Button("New Workout", systemImage: "plus") { creating = true }
            if store.library.savedWorkouts.isEmpty {
                ContentUnavailableView("No Saved Workouts", systemImage: "bookmark",
                                       description: Text("Create one here or sync from iPhone."))
            } else {
                ForEach(store.library.savedWorkouts.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }) { workout in
                    NavigationLink {
                        SavedWorkoutDetailView(workoutID: workout.id)
                    } label: {
                        WatchWorkoutSummaryRow(title: workout.title, exercises: workout.exercises)
                    }
                }
            }
        }
        .navigationTitle("Saved")
        .watchVitalsInset()
        .sheet(isPresented: $creating) {
            NavigationStack {
                SavedWorkoutEditor(workout: WatchSavedWorkout(
                    id: UUID(), title: "Workout", exercises: [],
                    weightUnit: store.preferredWeightUnit, comment: nil, updatedAt: Date()))
            }.environmentObject(store)
        }
    }
}

private struct SavedWorkoutDetailView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    let workoutID: UUID
    @State private var editing = false
    @State private var confirmingDelete = false

    private var workout: WatchSavedWorkout? { store.library.savedWorkouts.first { $0.id == workoutID } }

    var body: some View {
        List {
            if let workout {
                Section { WatchWorkoutSummaryRow(title: workout.title, exercises: workout.exercises) }
                Section {
                    Button("Start Workout", systemImage: "play.fill") { store.startWorkout(from: workout) }
                        .disabled(store.workoutSnapshot != nil)
                        .buttonStyle(.borderedProminent)
                }
                if let comment = workout.comment, !comment.isEmpty { Section("Notes") { Text(comment) } }
                Section("Exercises") {
                    ForEach(workout.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                        NavigationLink {
                            RecordedExerciseView(exercise: exercise, unit: workout.weightUnit, isTemplate: true)
                        } label: { RecordedExerciseRow(exercise: exercise) }
                    }
                }
                Section {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle("")
        .watchVitalsInset()
        .sheet(isPresented: $editing) {
            if let workout { NavigationStack { SavedWorkoutEditor(workout: workout) }.environmentObject(store) }
        }
        .confirmationDialog("Delete Saved Workout?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                store.deleteSavedWorkout(id: workoutID) { deleted in if deleted { dismiss() } }
            }
        } message: { Text("Workout history is kept.") }
    }
}

private struct SavedWorkoutEditor: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WatchSavedWorkout
    @State private var choosingExercise = false
    @State private var editingSupersets = false
    @State private var arranging = false
    @State private var supersetAnchorID: UUID?

    init(workout: WatchSavedWorkout) {
        var value = workout
        let unit = WorkoutSessionManagerStore.shared.preferredWeightUnit
        let projection = WatchWorkoutSnapshot(workoutID: workout.id, exercises: workout.exercises,
                                              weightUnit: workout.weightUnit)
        value.exercises = WatchWorkoutEditing.converting(projection, to: unit).exercises
        value.weightUnit = unit
        _draft = State(initialValue: value)
    }

    var body: some View {
        List {
            Section("Workout") {
                TextField("Name", text: $draft.title)
                TextField("Notes", text: optionalText($draft.comment), axis: .vertical)
            }
            Section("Exercises") {
                ForEach(draft.exercises) { item in
                    NavigationLink {
                        SavedExerciseEditor(exercise: exerciseBinding(item), catalog: store.library.exercises, unit: draft.weightUnit, onSuperset: {
                            supersetAnchorID = item.id; editingSupersets = true
                        }) {
                            draft.exercises.removeAll { $0.id == item.id }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline).lineLimit(2)
                            Text("\(item.sets.count) sets" +
                                 (item.supersetID == nil ? "" : " · Linked"))
                                .font(.ironMetric(.caption, weight: .semibold)).foregroundStyle(IronTheme.secondaryText)
                        }
                    }
                }
                Button("Add Exercise", systemImage: "plus") { choosingExercise = true }
                if draft.exercises.count > 1 {
                    Button("Arrange Exercises") { arranging = true }
                }
            }
        }
        .navigationTitle("")
        .watchVitalsInset()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    normalizeDraft(); draft.updatedAt = Date()
                    store.saveWorkout(draft) { saved in if saved { dismiss() } }
                }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $choosingExercise) {
            NavigationStack {
                WatchCatalogPicker(catalog: store.library.exercises) { pick in
                    draft.exercises.append(WatchWorkoutExercise(
                        order: draft.exercises.count + 1, name: pick.name,
                        sets: [WatchWorkoutSet(order: 1, minTargetReps: 8, maxTargetReps: 8)], muscleGroup: pick.muscle,
                        exerciseUuid: pick.id, imageURL: pick.imageURL))
                    choosingExercise = false
                }
            }
        }
        .sheet(isPresented: $editingSupersets) {
            NavigationStack { SupersetDraftEditor(exercises: $draft.exercises, anchorID: supersetAnchorID) }
        }
        .sheet(isPresented: $arranging) { NavigationStack { SavedArrangeExercises(exercises: $draft.exercises) } }
    }

    private func optionalText(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    private func exerciseBinding(_ item: WatchWorkoutExercise) -> Binding<WatchWorkoutExercise> {
        Binding(get: { draft.exercises.first { $0.id == item.id } ?? item }, set: { replacement in
            guard let index = draft.exercises.firstIndex(where: { $0.id == item.id }) else { return }
            draft.exercises[index] = replacement
        })
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard draft.exercises.indices.contains(destination) else { return }
        draft.exercises.swapAt(index, destination); normalizeDraft()
    }
    private func normalizeDraft() {
        var projection = WatchWorkoutSnapshot(workoutID: draft.id, exercises: draft.exercises)
        WatchWorkoutEditing.normalize(&projection)
        draft.exercises = projection.exercises
    }
}

private struct SavedExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercise: WatchWorkoutExercise
    let catalog: [WatchExercisePick]
    let unit: WatchWorkoutWeightUnit
    let onSuperset: () -> Void
    let onDelete: () -> Void
    @State private var replacing = false
    @State private var confirmingDelete = false
    @State private var editingRest = false

    var body: some View {
        List {
            Section("Exercise") {
                TextField("Notes", text: Binding(get: { exercise.comment ?? "" }, set: {
                    exercise.comment = $0.isEmpty ? nil : $0
                }), axis: .vertical)
                Button("Replace Exercise", systemImage: "arrow.triangle.2.circlepath") { replacing = true }
                Button("Rest Length", systemImage: "timer") { editingRest = true }
                Button(exercise.supersetID == nil ? "Create Superset" : "Edit Superset", systemImage: "link", action: onSuperset)
            }
            Section("Sets") {
                ForEach(exercise.sets) { item in
                    NavigationLink("Set \(item.order)") {
                        SavedSetEditor(set: Binding(get: { exercise.sets.first { $0.id == item.id } ?? item },
                            set: { replacement in
                                guard let index = exercise.sets.firstIndex(where: { $0.id == item.id }) else { return }
                                exercise.sets[index] = replacement
                            }), unit: unit)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            guard exercise.sets.count > 1 else { return }
                            exercise.sets.removeAll { $0.id == item.id }
                            for setIndex in exercise.sets.indices { exercise.sets[setIndex].order = setIndex + 1 }
                        }
                    }
                }
                Button("Add Set", systemImage: "plus") {
                    let source = exercise.sets.last
                    exercise.sets.append(WatchWorkoutSet(
                        order: exercise.sets.count + 1, weight: source?.weight,
                        reps: source?.minTargetReps != nil || source?.maxTargetReps != nil ? nil : source?.reps, completed: false, tag: source?.tag,
                        duration: source?.duration, distance: source?.distance, comment: source?.comment,
                        minTargetReps: source?.minTargetReps, maxTargetReps: source?.maxTargetReps))
                }
            }
            Section { Button("Remove Exercise", systemImage: "trash", role: .destructive) { confirmingDelete = true } }
        }
        .navigationTitle(exercise.name)
        .watchVitalsInset()
        .sheet(isPresented: $replacing) {
            NavigationStack {
                WatchCatalogPicker(catalog: catalog) { pick in
                    exercise.name = pick.name; exercise.exerciseUuid = pick.id
                    exercise.muscleGroup = pick.muscle; exercise.imageURL = pick.imageURL
                    exercise.imageData = nil
                    replacing = false
                }
            }
        }
        .sheet(isPresented: $editingRest) {
            WatchNumericEditor(title: "Rest Length", unit: "seconds", range: 0...900, step: 15,
                               initialValue: exercise.restTimerDuration ?? 0, allowsEmpty: true) {
                exercise.restTimerDuration = $0
            }
        }
        .confirmationDialog("Remove Exercise?", isPresented: $confirmingDelete) {
            Button("Remove", role: .destructive) {
                dismiss()
                DispatchQueue.main.async { onDelete() }
            }
        }
    }
}

private struct SavedSetEditor: View {
    @Binding var set: WatchWorkoutSet
    let unit: WatchWorkoutWeightUnit
    @State private var edit: SetDraftField?
    var body: some View {
        List {
            Section("Targets") {
                valueButton("Weight", set.weight.map(WatchNumber.format) ?? "—", field: .weight)
                valueButton("Minimum Reps", set.minTargetReps.map(String.init) ?? "—", field: .minimum)
                valueButton("Maximum Reps", set.maxTargetReps.map(String.init) ?? "—", field: .maximum)
                valueButton("Duration", set.duration.map(WatchNumber.clock) ?? "—", field: .duration)
            }
            Section("Details") {
                Picker("Set Type", selection: Binding(get: { set.tag ?? "working" }, set: {
                    set.tag = $0 == "working" ? nil : $0
                })) {
                    Text("Working").tag("working"); Text("Warm-up").tag("warmUp")
                    Text("Drop").tag("dropSet"); Text("Failure").tag("failure")
                }
                TextField("Notes", text: Binding(get: { set.comment ?? "" }, set: {
                    set.comment = $0.isEmpty ? nil : $0
                }), axis: .vertical)
            }
        }
        .navigationTitle("Set \(set.order)")
        .watchVitalsInset()
        .sheet(item: $edit) { field in
            WatchNumericEditor(title: field.title, unit: field == .weight ? unit.symbol : field.unit, range: field.range,
                               step: field.step, initialValue: field.value(in: set), allowsEmpty: true) {
                field.apply($0, to: &set)
            }
        }
    }

    private func valueButton(_ title: String, _ value: String, field: SetDraftField) -> some View {
        Button { edit = field } label: {
            HStack { Text(title); Spacer(); Text(value).font(.ironMetric(.body, weight: .semibold)).foregroundStyle(IronTheme.secondaryText) }
        }
    }
}

private enum SetDraftField: String, Identifiable {
    case weight, minimum, maximum, duration, distance
    var id: String { rawValue }
    var title: String {
        switch self { case .minimum: return "Minimum Reps"; case .maximum: return "Maximum Reps"
        default: return rawValue.capitalized }
    }
    var unit: String {
        switch self { case .duration: return "seconds"; case .distance: return "meters"
        case .weight: return "weight"; case .minimum, .maximum: return "reps" }
    }
    var range: ClosedRange<Double> { self == .duration ? 0...3_600 : (self == .distance ? 0...100_000 : 0...1_000) }
    var step: Double { self == .weight ? 0.5 : (self == .duration ? 5 : 1) }
    func value(in set: WatchWorkoutSet) -> Double {
        switch self { case .weight: return set.weight ?? 0; case .minimum: return Double(set.minTargetReps ?? 0)
        case .maximum: return Double(set.maxTargetReps ?? 0); case .duration: return set.duration ?? 0
        case .distance: return set.distance ?? 0 }
    }
    func apply(_ value: Double?, to set: inout WatchWorkoutSet) {
        switch self { case .weight: set.weight = value; case .minimum: set.minTargetReps = value.map { Int($0.rounded()) }; set.reps = nil
        case .maximum: set.maxTargetReps = value.map { Int($0.rounded()) }; set.reps = nil; case .duration: set.duration = value
        case .distance: set.distance = value }
    }
}

private struct SupersetDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [WatchWorkoutExercise]
    let anchorID: UUID?
    @State private var selected = Set<UUID>()
    var body: some View {
        List {
            ForEach(exercises) { exercise in
                Button {
                    if !selected.insert(exercise.id).inserted { selected.remove(exercise.id) }
                } label: {
                    HStack(spacing: 8) {
                        WatchExerciseThumbnail(imageURL: exercise.imageURL, imageData: exercise.imageData, size: 28)
                        Text(exercise.name).font(.headline).foregroundStyle(IronTheme.primaryText).lineLimit(3)
                        Spacer(minLength: 2)
                        Image(systemName: selected.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(exercise.id) ? IronTheme.accent : IronTheme.secondaryText)
                    }
                }
            }
            Button("Link Selected", systemImage: "link") {
                var projection = WatchWorkoutSnapshot(workoutID: UUID(), startDate: Date(), exercises: exercises)
                WatchWorkoutEditing.replaceSuperset(exerciseIDs: selected, anchorID: anchorID, in: &projection)
                exercises = projection.exercises
                dismiss()
            }.disabled(selected.count < 2)
            Button("Unlink Selected", systemImage: "link.badge.minus") {
                for index in exercises.indices where selected.contains(exercises[index].id) { exercises[index].supersetID = nil }
                dismiss()
            }.disabled(selected.isEmpty)
        }.navigationTitle("Superset").watchVitalsInset()
        .onAppear {
            guard selected.isEmpty, let anchor = exercises.first(where: { $0.id == anchorID }) else { return }
            selected = Set(exercises.filter { $0.id == anchor.id || (anchor.supersetID != nil && $0.supersetID == anchor.supersetID) }.map(\.id))
        }
    }
}

private struct SavedArrangeExercises: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [WatchWorkoutExercise]
    var body: some View {
        List {
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name).font(.headline)
                    HStack {
                        Button { move(exercise.id, offset: -1) } label: { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                            .disabled(exercise.id == exercises.first?.id).accessibilityLabel("Move " + exercise.name + " up")
                        Button { move(exercise.id, offset: 1) } label: { Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44) }
                            .disabled(exercise.id == exercises.last?.id).accessibilityLabel("Move " + exercise.name + " down")
                    }.buttonStyle(.borderless)
                }
            }
            Button("Done") { dismiss() }
        }.navigationTitle("Arrange").watchVitalsInset()
    }
    private func move(_ id: UUID, offset: Int) {
        guard let index = exercises.firstIndex(where: { $0.id == id }), exercises.indices.contains(index + offset) else { return }
        exercises.swapAt(index, index + offset)
    }
}

struct WatchCatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: [WatchExercisePick]
    let onPick: (WatchExercisePick) -> Void
    @State private var query = ""
    private var grouped: [String: [WatchExercisePick]] {
        let filtered = query.isEmpty ? catalog : catalog.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.muscle?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return Dictionary(grouping: filtered, by: { $0.muscle ?? "Other" })
            .mapValues { $0.sorted { $0.name < $1.name } }
    }
    var body: some View {
        let groups = grouped
        List {
            ForEach(groups.keys.sorted(), id: \.self) { group in
                Section(group) {
                    ForEach(groups[group] ?? []) { pick in
                        Button { onPick(pick); dismiss() } label: {
                            HStack(spacing: 8) {
                                WatchExerciseThumbnail(imageURL: pick.imageURL, imageData: nil, size: 32)
                                Text(pick.name).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Exercises").watchVitalsInset().searchable(text: $query, prompt: "Search")
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    var body: some View {
        List {
            if store.library.history.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("Completed workouts appear here."))
            } else {
                ForEach(store.library.history, id: \.workoutID) { workout in
                    NavigationLink {
                        WatchHistoryDetail(workout: workout)
                    } label: {
                        WatchWorkoutSummaryRow(title: workout.title ?? "Workout", exercises: workout.exercises,
                                               date: workout.startDate, duration: workout.recordedDuration)
                    }
                }
            }
        }.navigationTitle("History").watchVitalsInset()
    }
}

private struct WatchHistoryDetail: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    let workout: WatchWorkoutSnapshot
    @State private var saved = false
    var body: some View {
        List {
            Section {
                WatchWorkoutSummaryRow(title: workout.title ?? "Workout", exercises: workout.exercises,
                                       date: workout.startDate, duration: workout.recordedDuration)
            }
            Section {
                Button("Repeat Workout", systemImage: "arrow.clockwise") { store.repeatWorkout(workout) }
                    .disabled(store.workoutSnapshot != nil).watchGlassButton(prominent: true).listRowBackground(EmptyView())
                Button(saved ? "Workout Saved" : "Save as Workout", systemImage: saved ? "checkmark" : "bookmark") {
                    store.saveAsWorkout(workout) { success in saved = success }
                }.disabled(saved)
            }
            if let comment = workout.comment, !comment.isEmpty { Section("Notes") { Text(comment) } }
            Section("Exercises") {
                ForEach(workout.exercises) { exercise in
                    NavigationLink { RecordedExerciseView(exercise: exercise, unit: workout.weightUnit ?? .kilogram) } label: {
                        RecordedExerciseRow(exercise: exercise)
                    }
                }
            }
        }.navigationTitle("").watchVitalsInset()
    }
}

private struct RecordedExerciseRow: View {
    let exercise: WatchWorkoutExercise
    var body: some View {
        HStack(spacing: 8) {
            WatchExerciseThumbnail(imageURL: exercise.imageURL, imageData: exercise.imageData, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.headline).lineLimit(3)
                Text("\(exercise.sets.count) sets").font(.ironMetric(.caption2, weight: .semibold)).foregroundStyle(IronTheme.metricSets)
                if let muscle = exercise.muscleGroup { Text(muscle.localizedCapitalized).font(.caption2).foregroundStyle(IronTheme.secondaryText) }
            }
        }.frame(minHeight: 64).accessibilityElement(children: .combine)
    }
}

private struct RecordedExerciseView: View {
    let exercise: WatchWorkoutExercise
    let unit: WatchWorkoutWeightUnit
    var isTemplate = false
    var body: some View {
        List {
            Section { Text(exercise.name).font(.headline) }.listRowBackground(EmptyView())
            if let comment = exercise.comment, !comment.isEmpty { Section("Notes") { Text(comment) } }
            Section(isTemplate ? "Targets" : "Sets") {
                ForEach(exercise.sets) { set in
                    NavigationLink {
                        List {
                            LabeledContent("Result") { Text(result(set)).font(.ironMetric(.body, weight: .semibold)) }
                            if let rpe = set.rpe { LabeledContent("RPE") { Text(WatchNumber.format(rpe)).font(.ironMetric(.body)).foregroundStyle(IronTheme.metricEffort) } }
                            if let note = set.comment, !note.isEmpty { Section("Notes") { Text(note) } }
                            LabeledContent("Type", value: set.kindTitle)
                        }.navigationTitle("Set \(set.order)").watchVitalsInset()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Set \(set.order)").font(.headline)
                            Text(result(set)).font(.ironMetric(.caption, weight: .semibold))
                        }.frame(minHeight: 44)
                    }
                }
            }
        }.navigationTitle("").watchVitalsInset()
    }
    private func result(_ set: WatchWorkoutSet) -> String {
        var display = set
        if isTemplate { display.reps = set.maxTargetReps ?? set.minTargetReps ?? set.reps }
        return display.displayText(weightUnit: unit)
    }
}

struct WatchSyncView: View {
    @ObservedObject private var phone = PhoneConnectionManager.shared
    var body: some View {
        List {
            Section {
                LabeledContent("iPhone", value: phone.isReachable ? "Connected" : "Offline")
                Button("Sync Library", systemImage: "arrow.triangle.2.circlepath") { phone.requestLibrary() }
                Button("Sync Current Workout", systemImage: "arrow.clockwise") { phone.requestCurrentSnapshot() }
            } footer: { Text("Edits are saved on this watch and delivered when iPhone reconnects.") }
        }.navigationTitle("Sync").watchVitalsInset()
    }
}

struct WatchUnitsView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    var body: some View {
        List {
            Picker("Units", selection: Binding(get: { store.preferredWeightUnit }, set: { store.setPreferredWeightUnit($0) })) {
                Text("Kilograms").tag(WatchWorkoutWeightUnit.kilogram)
                Text("Pounds").tag(WatchWorkoutWeightUnit.pound)
            }
        }.navigationTitle("Units").watchVitalsInset()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }
#endif
