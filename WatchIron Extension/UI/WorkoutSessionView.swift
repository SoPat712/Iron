import SwiftUI
import WatchKit
import HealthKit
import ImageIO
import CryptoKit

struct WorkoutSessionView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let workoutSessionManager: WorkoutSessionManager?

    var body: some View {
        Group {
            if let snapshot = store.workoutSnapshot {
                if snapshot.isFinishedRecord { FinishedRecordView(snapshot: snapshot) }
                else {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            List {
                                if snapshot.hasRest {
                                    NavigationLink(value: WatchRoute.rest) { WatchRestStatusRow(snapshot: snapshot) }
                                        .listRowBackground(IronTheme.metricTimeContainer)
                                }
                                if snapshot.exercises.isEmpty {
                                    Text("Add an exercise to begin logging.")
                                        .font(.caption).foregroundStyle(IronTheme.secondaryText)
                                }
                                ForEach(snapshot.exercises) { exercise in
                                    NavigationLink(value: WatchRoute.exercise(exercise.id)) {
                                        ExerciseOverviewRow(exercise: exercise)
                                    }
                                    .id(exercise.id)
                                    .listRowBackground(exercise.id == snapshot.focusExerciseID
                                        ? IronTheme.accentSoft : nil)
                                }
                                Section {
                                    NavigationLink { WatchAddExerciseView() } label: { Label("Add Exercise", systemImage: "plus") }
                                    if snapshot.exercises.count > 1 {
                                        NavigationLink(value: WatchRoute.arrange) { Text("Arrange Exercises") }
                                    }
                                    NavigationLink(value: WatchRoute.details) { Text("Workout Details") }
                                    NavigationLink(value: WatchRoute.finish) { Text("Finish Workout").foregroundStyle(IronTheme.accent) }
                                        .disabled(!snapshot.exercises.flatMap(\.sets).contains(where: \.completed))
                                }
                                if let error = store.recordingError {
                                    Section("Health Recording") {
                                        Text(error).font(.caption).foregroundStyle(IronTheme.warning)
                                        Button("Retry Recording") { store.startRecording() }
                                            .disabled(store.isStartingRecording || store.isRecoveringRecording)
                                    }
                                }
                            }
                            .onChange(of: snapshot.selectedSetID) {
                                guard let exercise = snapshot.focusExerciseID else { return }
                                withAnimation(IronMotion.preferred(.timingCurve(0.12, 0.9, 0.2, 1, duration: 0.46), reduceMotion: reduceMotion)) {
                                    proxy.scrollTo(exercise, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Workout", systemImage: "dumbbell")
            }
        }
        .navigationTitle(store.workoutSnapshot?.title ?? "Workout")
    }
}

private struct WatchAddExerciseView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    var body: some View { WatchCatalogPicker(catalog: store.library.exercises) { store.addExercise($0) } }
}

private struct FinishedRecordView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    let snapshot: WatchWorkoutSnapshot
    var body: some View {
        List {
            Label(store.workoutSessionManager == nil ? "Workout Saved" : "Saving Recording…",
                  systemImage: store.workoutSessionManager == nil ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .foregroundStyle(IronTheme.accent)
            WatchWorkoutSummaryRow(title: snapshot.title ?? "Workout", exercises: snapshot.exercises,
                                   duration: snapshot.recordedDuration)
            if let error = store.recordingError { Text(error).font(.caption).foregroundStyle(IronTheme.warning) }
        }.navigationTitle("")
    }
}

private extension WatchWorkoutSnapshot {
    var focusExerciseID: UUID? {
        let id = selectedSet.flatMap { $0.set.completed ? nil : $0.set.id } ?? WatchWorkoutEditing.nextSet(in: self)
        return exercises.first { $0.sets.contains { $0.id == id } }?.id
    }
    var hasRest: Bool {
        guard WatchWorkoutEditing.nextSet(in: self) != nil else { return false }
        if let pausedRestRemaining { return pausedRestRemaining > 0 }
        guard let restTimerEnd else { return false }
        return keepRestTimerRunning || restTimerEnd > Date()
    }
}

private struct WatchRestStatusRow: View {
    let snapshot: WatchWorkoutSnapshot
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(snapshot.pausedRestRemaining == nil ? "Rest" : "Rest Paused").font(.caption)
                Spacer(minLength: 2)
                Text(WatchNumber.clock(snapshot.pausedRestRemaining ?? max(0, snapshot.restTimerEnd?.timeIntervalSince(context.date) ?? 0)))
                    .font(.ironMetric(.headline, weight: .semibold))
            }.foregroundStyle(IronTheme.metricTime)
        }
    }
}

struct OfflineWorkoutView: View {
    var body: some View { WorkoutSessionView(workoutSessionManager: nil) }
}

private enum FocusEditor: String, Identifiable {
    case weight, reps, duration, distance, rpe
    var id: String { rawValue }

    func specification(set: WatchWorkoutSet, unit: WatchWorkoutWeightUnit)
    -> (title: String, unit: String, range: ClosedRange<Double>, step: Double, value: Double) {
        switch self {
        case .weight: return ("Weight", unit.symbol, 0...2_000, 0.5, set.weight ?? 0)
        case .reps: return ("Reps", "reps", 0...1_000, 1, Double(set.reps ?? 0))
        case .duration: return ("Duration", "seconds", 0...3_600, 5, set.duration ?? 0)
        case .distance:
            let display = WatchNumber.distance(meters: set.distance ?? 0, unit: unit)
            let value = (set.distance ?? 0) / (unit == .pound ? 1_609.344 : 1_000)
            return ("Distance", display.1, 0...1_000, 0.1, value)
        case .rpe: return ("RPE", "effort", 1...10, 0.5, set.rpe ?? 7)
        }
    }

    func apply(_ value: Double?, unit: WatchWorkoutWeightUnit, to set: inout WatchWorkoutSet) {
        switch self {
        case .weight: set.weight = value
        case .reps: set.reps = value.map { Int($0.rounded()) }
        case .duration: set.duration = value
        case .distance: set.distance = value.map { WatchNumber.meters(displayValue: $0, unit: unit) }
        case .rpe: set.rpe = value
        }
    }
}

struct WatchRestView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @EnvironmentObject private var navigation: WatchNavigation
    private var snapshot: WatchWorkoutSnapshot? { store.workoutSnapshot }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var next: (WatchWorkoutExercise, WatchWorkoutSet)? {
        guard let snapshot, let id = WatchWorkoutEditing.nextSet(in: snapshot) else { return nil }
        for exercise in snapshot.exercises {
            if let set = exercise.sets.first(where: { $0.id == id }) { return (exercise, set) }
        }
        return nil
    }

    var body: some View {
        if let snapshot {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            ScrollView {
            VStack(spacing: 10) {
                Text("Next: \(next?.0.name ?? "Workout")")
                    .font(.headline).lineLimit(2).multilineTextAlignment(.center)
                Text(WatchNumber.clock(remaining(at: context.date)))
                    .font(.ironMetric(.largeTitle))
                    .foregroundStyle(IronTheme.metricTime)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                Text(snapshot.pausedRestRemaining != nil ? "Rest paused" :
                     (remaining(at: context.date) <= 0 ? "Ready · rest complete" : "Rest"))
                    .font(.caption).foregroundStyle(IronTheme.secondaryText)

                HStack(spacing: 8) {
                    Button("−15") { store.adjustRest(by: -15) }
                        .accessibilityLabel("Subtract 15 seconds")
                        .frame(minWidth: 44, minHeight: 44)
                    Button { store.toggleRestPause() } label: {
                        Image(systemName: snapshot.pausedRestRemaining == nil ? "pause.fill" : "play.fill")
                    }.accessibilityLabel(snapshot.pausedRestRemaining == nil ? "Pause rest" : "Resume rest")
                    Button("+15") { store.adjustRest(by: 15) }
                        .accessibilityLabel("Add 15 seconds")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .watchGlassButton()

                if let next {
                    Text(next.1.displayText(weightUnit: snapshot.weightUnit ?? store.preferredWeightUnit))
                        .font(.ironMetric(.headline, weight: .semibold))
                    if next.0.supersetID != nil {
                        Text("Superset next")
                            .font(.caption2).foregroundStyle(IronTheme.secondaryText)
                    }
                }
                Button("Start Next Set") { store.skipRest(); navigation.openWorkout() }
                    .watchGlassButton(prominent: true)
                    .frame(minHeight: IronTheme.controlHeight)
            }
            .padding(.horizontal, 8)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion),
                       value: snapshot.pausedRestRemaining)
            }
        }
        } else { ContentUnavailableView("Rest Complete", systemImage: "timer") }
    }

    private func remaining(at date: Date) -> TimeInterval {
        snapshot?.pausedRestRemaining ?? max(0, snapshot?.restTimerEnd?.timeIntervalSince(date) ?? 0)
    }
}

struct WatchVitalsRow: View {
    let manager: WorkoutSessionManager?
    let snapshot: WatchWorkoutSnapshot
    @ViewBuilder var body: some View {
        if let manager, manager.uuid == snapshot.workoutID { LiveWatchVitals(manager: manager) }
        else { WatchVitalsLine(heartRate: "—", energy: WatchNumber.whole(snapshot.activeEnergyKilocalories)) }
    }
}

private struct WatchVitalsLine: View {
    let heartRate: String
    let energy: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 6) { metrics }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { metrics }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(heartRate).font(.ironMetric(.headline)).foregroundStyle(IronTheme.metricHeartRate)
                            Text("bpm").font(.caption2).foregroundStyle(IronTheme.secondaryText)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(energy).font(.ironMetric(.headline)).foregroundStyle(IronTheme.metricEnergy)
                            Text("kcal").font(.caption2).foregroundStyle(IronTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate \(heartRate) beats per minute. Estimated active energy \(energy) kilocalories.")
    }
    @ViewBuilder private var metrics: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(IronTheme.metricHeartRate)
            WatchMetricValue(value: heartRate, unit: "bpm", color: IronTheme.metricHeartRate)
        }.fixedSize()
        if dynamicTypeSize < .xxLarge { Spacer(minLength: 4) }
        WatchMetricValue(value: energy, unit: "kcal", color: IronTheme.metricEnergy).fixedSize()
    }
}

private struct LiveWatchVitals: View {
    @ObservedObject var manager: WorkoutSessionManager
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { context in
            WatchVitalsLine(heartRate: currentHeartRate(at: Date()),
                            energy: WatchNumber.whole(manager.burnedCalories))
        }
    }
    private func currentHeartRate(at date: Date) -> String {
        guard let value = manager.mostRecentHeartRate, value.isFinite, value > 0,
              let sampleDate = manager.mostRecentHeartRateDate,
              (-5...30).contains(date.timeIntervalSince(sampleDate)) else { return "—" }
        return WatchNumber.whole(value)
    }
}

private struct RecordingAndSyncStatus: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @ObservedObject private var phone = PhoneConnectionManager.shared
    let manager: WorkoutSessionManager?
    private var pending: Int { WatchWorkoutStore.shared.pendingEvents().count }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(recordingText, systemImage: manager == nil ? "heart.slash" : "heart.fill")
            Label(syncText, systemImage: phone.isReachable ? "iphone" : "applewatch")
        }
        .font(.caption2)
        .foregroundStyle(IronTheme.secondaryText)
    }
    private var recordingText: String {
        if store.isRecoveringRecording { return "Recovering Health recording" }
        if store.isStartingRecording { return "Starting Health recording" }
        guard let manager else { return "Edits saved · not recording" }
        switch manager.state {
        case .running: return "Recording on Watch"
        case .paused: return "Recording paused"
        case .stopped: return "Saving Health recording"
        case .ended: return "Health recording finished"
        default: return "Preparing Health recording"
        }
    }
    private var syncText: String {
        pending > 0 ? "\(pending) edit\(pending == 1 ? "" : "s") queued" :
            (phone.isReachable ? "Edits synced" : "Edits saved on Watch")
    }
}

private struct SetProgressCells: View {
    let exercise: WatchWorkoutExercise
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(exercise.sets.prefix(12))) { set in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(set.completed ? IronTheme.accent : IronTheme.tertiaryFill)
                    .frame(width: 5, height: 8)
            }
        }
        .accessibilityLabel("\(exercise.sets.filter(\.completed).count) of \(exercise.sets.count) sets complete")
    }
}

private struct ExerciseOverviewRow: View {
    let exercise: WatchWorkoutExercise
    var body: some View {
        HStack(spacing: 8) {
            WatchExerciseThumbnail(imageURL: exercise.imageURL, imageData: exercise.imageData, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.headline).lineLimit(3).foregroundStyle(IronTheme.primaryText)
                Text("\(exercise.sets.filter(\.completed).count)/\(exercise.sets.count) sets")
                    .font(.ironMetric(.caption2, weight: .semibold)).foregroundStyle(IronTheme.metricSets)
                let description = [exercise.muscleGroup?.localizedCapitalized, exercise.supersetID == nil ? nil : "Superset"]
                    .compactMap { $0 }.joined(separator: " · ")
                if !description.isEmpty { Text(description).font(.caption2).foregroundStyle(IronTheme.secondaryText).lineLimit(2) }
                SetProgressCells(exercise: exercise).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct ActiveExerciseView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    let exerciseID: UUID
    private var exercise: WatchWorkoutExercise? { store.workoutSnapshot?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        List {
            if let exercise {
                VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                        if let muscle = exercise.muscleGroup { Text(muscle.localizedCapitalized).font(.caption).foregroundStyle(IronTheme.secondaryText) }
                        if let group = exercise.supersetID {
                            let partners = store.workoutSnapshot?.exercises.filter { $0.supersetID == group && $0.id != exerciseID }.map(\.name) ?? []
                            Label(partners.joined(separator: " · "), systemImage: "link")
                                .font(.caption2).foregroundStyle(IronTheme.secondaryText)
                        }
                }.listRowBackground(EmptyView())
                    ForEach(exercise.sets) { set in
                        NavigationLink(value: WatchRoute.set(exerciseID, set.id)) {
                            HStack(spacing: 8) {
                                Text("\(set.order)").font(.ironMetric(.headline)).foregroundStyle(set.completed ? IronTheme.accent : IronTheme.secondaryText)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.displayText(weightUnit: store.workoutSnapshot?.weightUnit ?? store.preferredWeightUnit))
                                        .font(.ironMetric(.body, weight: .semibold)).foregroundStyle(IronTheme.primaryText)
                                    Text(set.completed ? "Completed" : set.kindTitle).font(.caption2).foregroundStyle(IronTheme.secondaryText)
                                }
                                Spacer(minLength: 2)
                                if set.completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(IronTheme.accent) }
                            }.frame(minHeight: 44)
                        }.listRowBackground(set.completed ? IronTheme.accentSoft : nil)
                    }
                    Button("Add Set", systemImage: "plus") {
                        store.updateCurrent { projection in
                            guard let index = projection.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                            let source = projection.exercises[index].sets.last
                            projection.exercises[index].sets.append(WatchWorkoutSet(
                                order: projection.exercises[index].sets.count + 1, weight: source?.weight,
                                reps: source?.reps ?? 8, completed: false, tag: source?.tag,
                                duration: source?.duration, distance: source?.distance,
                                comment: source?.comment, minTargetReps: source?.minTargetReps, maxTargetReps: source?.maxTargetReps))
                        }
                    }
                Section {
                    NavigationLink(value: WatchRoute.superset(exerciseID)) { Text(exercise.supersetID == nil ? "Create Superset" : "Edit Superset") }
                    NavigationLink(value: WatchRoute.exerciseSettings(exerciseID)) { Text("Exercise Settings") }
                }
            } else { ContentUnavailableView("Exercise Removed", systemImage: "dumbbell") }
        }.navigationTitle("")
    }
}

struct ActiveExerciseSettings: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @EnvironmentObject private var navigation: WatchNavigation
    let exerciseID: UUID
    @State private var replacing = false
    @State private var confirmingDelete = false
    @State private var editingRest = false
    private var exercise: WatchWorkoutExercise? { store.workoutSnapshot?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        List {
            if let exercise {
                Section {
                    Button("Rest Length · \(WatchNumber.clock(exercise.restTimerDuration ?? 0))", systemImage: "timer") { editingRest = true }
                    TextField("Notes", text: Binding(get: { self.exercise?.comment ?? "" }, set: { note in
                        store.updateCurrent { projection in
                            guard let index = projection.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                            projection.exercises[index].comment = note.isEmpty ? nil : note
                        }
                    }), axis: .vertical)
                    Button("Replace Exercise", systemImage: "arrow.triangle.2.circlepath") { replacing = true }
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } footer: { Text(exercise.name).font(.caption2) }
            }
        }
        .navigationTitle("Exercise")
        .sheet(isPresented: $replacing) {
            NavigationStack {
                WatchCatalogPicker(catalog: store.library.exercises) { pick in
                    store.updateCurrent { projection in
                        guard let index = projection.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                        projection.exercises[index].name = pick.name
                        projection.exercises[index].exerciseUuid = pick.id
                        projection.exercises[index].muscleGroup = pick.muscle
                        projection.exercises[index].imageURL = pick.imageURL
                        projection.exercises[index].imageData = nil
                    }
                }
            }
        }
        .sheet(isPresented: $editingRest) {
            WatchNumericEditor(title: "Rest Length", unit: "seconds", range: 0...900, step: 15,
                               initialValue: exercise?.restTimerDuration ?? 0, allowsEmpty: true) { value in
                store.updateCurrent { projection in
                    guard let index = projection.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                    projection.exercises[index].restTimerDuration = value
                }
            }
        }
        .confirmationDialog("Remove Exercise?", isPresented: $confirmingDelete) {
            Button("Remove", role: .destructive) {
                store.updateCurrent { $0.exercises.removeAll { $0.id == exerciseID } }
                navigation.openWorkout()
            }
        }
    }
}

struct ActiveSupersetEditor: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    let anchorID: UUID
    @State private var selected = Set<UUID>()
    private var exercises: [WatchWorkoutExercise] { store.workoutSnapshot?.exercises ?? [] }
    var body: some View {
        List {
            ForEach(exercises) { exercise in
                Button {
                    guard exercise.id != anchorID else { return }
                    if !selected.insert(exercise.id).inserted { selected.remove(exercise.id) }
                } label: {
                    HStack(spacing: 8) {
                        WatchExerciseThumbnail(imageURL: exercise.imageURL, imageData: exercise.imageData, size: 28)
                        Text(exercise.name).font(.headline).foregroundStyle(IronTheme.primaryText).lineLimit(3)
                        Spacer(minLength: 2)
                        Image(systemName: selected.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(exercise.id) ? IronTheme.accent : IronTheme.secondaryText)
                    }
                }.accessibilityValue(selected.contains(exercise.id) ? "Selected" : "Not selected")
            }
            Button("Save Superset") {
                store.updateCurrent {
                    WatchWorkoutEditing.replaceSuperset(exerciseIDs: selected, anchorID: anchorID, in: &$0)
                }
                dismiss()
            }.disabled(selected.count < 2)
            if exercises.first(where: { $0.id == anchorID })?.supersetID != nil {
                Button("Remove Link") {
                    store.updateCurrent { snapshot in
                        guard let index = snapshot.exercises.firstIndex(where: { $0.id == anchorID }) else { return }
                        snapshot.exercises[index].supersetID = nil
                    }
                    dismiss()
                }
            }
        }
        .navigationTitle("Superset")
        .onAppear {
            guard selected.isEmpty, let anchor = exercises.first(where: { $0.id == anchorID }) else { return }
            selected = Set(exercises.filter { $0.id == anchorID || (anchor.supersetID != nil && $0.supersetID == anchor.supersetID) }.map(\.id))
        }
    }
}

struct ArrangeWatchExercisesView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    @State private var order: [UUID] = []
    var body: some View {
        List {
            let exercises = store.workoutSnapshot?.exercises ?? []
            ForEach(order, id: \.self) { id in
                if let exercise = exercises.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.name).font(.headline)
                        HStack(spacing: 8) {
                            Button { move(id, by: -1) } label: { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("Move \(exercise.name) up").disabled(id == order.first)
                            Button { move(id, by: 1) } label: { Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("Move \(exercise.name) down").disabled(id == order.last)
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Button("Done") {
                let ids = order
                store.updateCurrent { WatchWorkoutEditing.reorder(exerciseIDs: ids, in: &$0) }
                dismiss()
            }
        }.navigationTitle("Arrange")
        .onAppear { if order.isEmpty { order = store.workoutSnapshot?.exercises.map(\.id) ?? [] } }
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }
}

struct ActiveSetEditor: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @EnvironmentObject private var navigation: WatchNavigation
    @Environment(\.dismiss) private var dismiss
    let exerciseID: UUID
    let setID: UUID
    var showsMeasurements = false
    var showsSettings = false
    @State private var field: FocusEditor?
    @State private var confirmingDelete = false
    private var exercise: WatchWorkoutExercise? { store.workoutSnapshot?.exercises.first { $0.id == exerciseID } }
    private var set: WatchWorkoutSet? { exercise?.sets.first { $0.id == setID } }
    private var unit: WatchWorkoutWeightUnit { store.workoutSnapshot?.weightUnit ?? store.preferredWeightUnit }

    var body: some View {
        List {
            if let set {
                if showsMeasurements {
                    Section {
                        value("Weight", value: set.weight.map(WatchNumber.format) ?? "—", field: .weight)
                        value("Reps", value: set.reps.map(String.init) ?? "—", field: .reps)
                        value("Duration", value: set.duration.map(WatchNumber.clock) ?? "—", field: .duration)
                        let distance = set.distance.map { WatchNumber.distance(meters: $0, unit: unit) }
                        value("Distance", value: distance.map { "\($0.0) \($0.1)" } ?? "—", field: .distance)
                    }
                } else if showsSettings {
                Section("Details") {
                    value("RPE", value: set.rpe.map(WatchNumber.format) ?? "—", field: .rpe)
                    Picker("Set Type", selection: Binding(get: { set.tag ?? "working" }, set: { tag in
                        mutate { $0.tag = tag == "working" ? nil : tag }
                    })) {
                        Text("Working").tag("working"); Text("Warm-up").tag("warmUp")
                        Text("Drop").tag("dropSet"); Text("Failure").tag("failure")
                    }
                    TextField("Notes", text: Binding(get: { self.set?.comment ?? "" }, set: { note in
                        mutate { $0.comment = note.isEmpty ? nil : note }
                    }), axis: .vertical)
                    NavigationLink {
                        ActiveSetEditor(exerciseID: exerciseID, setID: setID, showsMeasurements: true)
                            .watchVitalsInset()
                    } label: { Text("More Measurements") }
                    if let weight = set.weight {
                        NavigationLink { WatchPlateCalculatorView(targetWeight: weight, unit: unit) } label: { Text("Plate Calculator") }
                    }
                    if set.completed {
                        Button("Mark Incomplete", systemImage: "arrow.uturn.backward") {
                            store.completeSet(exerciseID: exerciseID, setID: setID)
                        }
                    }
                    Button("Delete Set", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
                } else {
                Section {
                    if set.duration != nil || set.distance != nil {
                        value("Duration", value: set.duration.map(WatchNumber.clock) ?? "—", field: .duration)
                        let distance = set.distance.map { WatchNumber.distance(meters: $0, unit: unit) }
                        value("Distance", value: distance.map { "\($0.0) \($0.1)" } ?? "—", field: .distance)
                    } else {
                        value("Weight", value: (set.weight.map(WatchNumber.format) ?? "—") + " " + unit.symbol, field: .weight)
                        value("Reps", value: set.reps.map(String.init) ?? "—", field: .reps)
                    }
                }
                Section {
                    Button(set.completed ? "Done" : "Log Set", systemImage: "checkmark") {
                        if set.completed { dismiss() }
                        else {
                            store.completeSet(exerciseID: exerciseID, setID: setID)
                            navigation.openWorkout()
                        }
                    }.watchGlassButton(prominent: true).listRowBackground(EmptyView())
                }
                Section {
                    NavigationLink {
                        ActiveSetEditor(exerciseID: exerciseID, setID: setID, showsSettings: true)
                            .watchVitalsInset()
                    } label: { Text("Settings") }
                }
                }
            } else { ContentUnavailableView("Set Removed", systemImage: "checklist") }
        }
        .navigationTitle(showsMeasurements ? "Measurements" : showsSettings ? "Settings" : (set.map { "Set \($0.order)" } ?? "Set"))
        .sheet(item: $field) { field in
            if let set {
                let spec = field.specification(set: set, unit: unit)
                WatchNumericEditor(title: spec.title, unit: spec.unit, range: spec.range,
                                   step: spec.step, initialValue: spec.value, allowsEmpty: true) { newValue in
                    mutate { field.apply(newValue, unit: unit, to: &$0) }
                }
            }
        }
        .confirmationDialog("Delete Set?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                store.updateCurrent { projection in
                    guard let index = projection.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                    projection.exercises[index].sets.removeAll { $0.id == setID }
                }
                dismiss()
            }
        }
    }
    private func value(_ title: String, value: String, field: FocusEditor) -> some View {
        Button { self.field = field } label: {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(minLength: 4); Text(value).font(.ironMetric(.body, weight: .semibold)) }
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption); Text(value).font(.ironMetric(.title3)) }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.foregroundStyle(IronTheme.primaryText)
    }
    private func mutate(_ body: @escaping (inout WatchWorkoutSet) -> Void) {
        store.updateCurrent { projection in
            guard let exercise = projection.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let index = projection.exercises[exercise].sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&projection.exercises[exercise].sets[index])
        }
    }
}

private struct WatchTextDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var text: String
    let onCommit: () -> Void
    var body: some View {
        Form {
            TextField(title, text: $text, axis: .vertical)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Done") { onCommit(); dismiss() }.buttonStyle(.borderedProminent)
            }
        }.navigationTitle(title)
    }
}

extension WatchWorkoutSet {
    var kindTitle: String {
        switch tag { case "warmUp": return "Warm-up"; case "dropSet": return "Drop"
        case "failure": return "Failure"; default: return "Working" }
    }
}

struct WatchExerciseThumbnail: View {
    let imageURL: String?
    let imageData: Data?
    var size: CGFloat = 36
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(IronTheme.tertiaryFill)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(IronTheme.secondaryText).opacity(image == nil ? 1 : 0)
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(size * 0.14) }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: imageURL) { await load() }
        .onChange(of: imageData) { image = imageData.flatMap(UIImage.init(data:)) }
        .accessibilityHidden(true)
    }

    private func load() async {
        image = imageData.flatMap(UIImage.init(data:))
        guard let imageURL, let url = URL(string: imageURL) else { return }
        let target = size * WKInterfaceDevice.current().screenScale
        let loaded = await WatchExerciseStillStore.shared.image(for: url, targetPixelSize: target)
        guard !Task.isCancelled else { return }
        if let loaded { image = loaded }
    }

}

private actor WatchExerciseStillStore {
    static let shared = WatchExerciseStillStore()
    private let memory = NSCache<NSString, UIImage>()
    private init() { memory.countLimit = 80; memory.totalCostLimit = 8 * 1_024 * 1_024 }
    private let fileManager = FileManager.default
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()
    private var directoryURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseMedia", isDirectory: true)
    }
    func image(for remoteURL: URL, targetPixelSize: CGFloat) async -> UIImage? {
        let key = "\(remoteURL.absoluteString)|\(Int(targetPixelSize.rounded(.up)))" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        let data: Data?
        if let disk = try? Data(contentsOf: fileURL(for: remoteURL)) {
            data = disk
        } else {
            data = await download(remoteURL)
        }
        guard let data, let image = stillFrame(from: data, targetPixelSize: targetPixelSize) else { return nil }
        memory.setObject(image, forKey: key, cost: Int(targetPixelSize * targetPixelSize * 4)); return image
    }
    private func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url); request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), !data.isEmpty else { return nil }
        let destination = fileURL(for: url); try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: destination, options: .atomic); return data
    }
    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent(hash)
    }
    private func stillFrame(from data: Data, targetPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(targetPixelSize)),
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: frame)
    }
}

private enum WatchPlateMath {
    static func format(_ value: Double) -> String { WatchNumber.format(value) }
}
private extension WatchWorkoutWeightUnit {
    var barbellWeight: Double { self == .kilogram ? 20 : 45 }
    var plates: [Double] { self == .kilogram ? [25,20,15,10,5,2.5,1.25,0.5] : [45,35,25,10,5,2.5,1.25] }
}
private struct WatchPlateCalculatorView: View {
    private struct PlateLoad: Identifiable {
        let weight: Double
        let count: Int
        var id: Double { weight }
    }
    let targetWeight: Double
    let unit: WatchWorkoutWeightUnit
    private var platesPerSide: [PlateLoad] {
        var remaining = max((targetWeight - unit.barbellWeight) / 2, 0)
        return unit.plates.compactMap { plate in
            let count = Int(floor((remaining + 0.0001) / plate)); guard count > 0 else { return nil }
            remaining -= Double(count) * plate; return PlateLoad(weight: plate, count: count)
        }
    }
    var body: some View {
        List {
            Section { LabeledContent("Target", value: "\(WatchPlateMath.format(targetWeight)) \(unit.symbol)")
                LabeledContent("Bar", value: "\(WatchPlateMath.format(unit.barbellWeight)) \(unit.symbol)") }
            Section("Each Side") {
                if platesPerSide.isEmpty { Text(targetWeight < unit.barbellWeight ? "Target is lighter than the bar." : "Empty bar.").foregroundStyle(IronTheme.secondaryText) }
                ForEach(platesPerSide) { plate in
                    LabeledContent("\(WatchPlateMath.format(plate.weight)) \(unit.symbol)", value: "\(plate.count)×")
                }
            }
        }.navigationTitle("Plates").watchVitalsInset()
    }
}
