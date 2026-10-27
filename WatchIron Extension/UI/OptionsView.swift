import SwiftUI
import HealthKit

struct OptionsView: View {
    @EnvironmentObject private var store: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    private let opensFinish: Bool
    @State private var pendingAction: PendingAction?
    @State private var effort = 7.0
    @State private var savedAsWorkout = false
    @State private var editingEffort = false

    private enum PendingAction: String, Identifiable {
        case finish, discard
        var id: String { rawValue }
    }

    init(startInFinish: Bool = false) {
        opensFinish = startInFinish
        _pendingAction = State(initialValue: startInFinish ? .finish : nil)
    }

    var body: some View {
        List {
            if let snapshot = store.workoutSnapshot {
                if let pendingAction {
                    confirmation(action: pendingAction, snapshot: snapshot)
                } else {
                    sessionControls(snapshot: snapshot)
                    status(snapshot: snapshot)
                    libraryActions
                    endActions
                }
            }
        }
        .navigationTitle(pendingAction == .finish ? "Finish" : "Details")
        .sheet(isPresented: $editingEffort) {
            WatchNumericEditor(title: "Effort", unit: "out of 10", range: 1...10, step: 1,
                               initialValue: effort, allowsEmpty: false) { value in
                if let value { effort = value }
            }
        }
        .onAppear {
            if let saved = store.workoutSnapshot?.sessionEffort { effort = min(max(saved, 1), 10) }
        }
    }

    @ViewBuilder
    private func sessionControls(snapshot: WatchWorkoutSnapshot) -> some View {
        Section {
            if let manager = store.workoutSessionManager, manager.state == .running || manager.state == .paused {
                Button(manager.state == .paused ? "Resume Workout" : "Pause Workout",
                       systemImage: manager.state == .paused ? "play.fill" : "pause.fill") {
                    store.toggleWorkoutPause()
                }
            } else if store.recordingError != nil {
                Button(store.isStartingRecording ? "Starting…" : "Retry Recording",
                       systemImage: "heart.circle") {
                    store.startRecording()
                }
                .disabled(store.isStartingRecording || store.isRecoveringRecording)
            } else {
                Label(store.isRecoveringRecording ? "Recovering Recording…" : "Starting Recording…", systemImage: "heart.fill")
                    .foregroundStyle(IronTheme.secondaryText)
            }
            TextField("Workout Name", text: Binding(get: { store.workoutSnapshot?.title ?? "" }, set: { name in
                store.updateCurrent { $0.title = name.isEmpty ? nil : name }
            }))
            TextField("Workout Notes", text: Binding(get: { store.workoutSnapshot?.comment ?? "" }, set: { note in
                store.updateCurrent { $0.comment = note.isEmpty ? nil : note }
            }), axis: .vertical)
        } header: {
            Text("Session")
        } footer: {
            Text(store.workoutSessionManager == nil
                 ? "Your Watch starts recording automatically. If access is denied or recording fails, your workout edits stay saved."
                 : "Your Watch records heart rate and active energy, even without iPhone.")
        }
    }

    @ViewBuilder
    private func status(snapshot: WatchWorkoutSnapshot) -> some View {
        Section("Status") {
            LabeledContent("Recording", value: recordingText)
            LabeledContent("Edit Sync", value: syncText)
            if let error = store.recordingError {
                Text(error).foregroundStyle(IronTheme.danger)
                Button("Retry Recording", systemImage: "arrow.clockwise") { store.startRecording() }
            }
        }
    }

    private var libraryActions: some View {
        Section("Library") {
            Button(savedAsWorkout ? "Workout Saved" : "Save as Workout", systemImage: savedAsWorkout ? "checkmark" : "bookmark") {
                store.saveCurrentAsWorkout { success in savedAsWorkout = success }
            }.disabled(savedAsWorkout)
            NavigationLink("Sync") { WatchSyncView() }
            NavigationLink("Units") { WatchUnitsView() }
        }
    }

    private var endActions: some View {
        Group {
            Section {
                Button("Finish Workout", systemImage: "checkmark.circle.fill") { pendingAction = .finish }
                    .tint(IronTheme.accent)
            }
            Section {
                Button("Discard Workout", systemImage: "trash.fill", role: .destructive) { pendingAction = .discard }
            }
        }
    }

    @ViewBuilder
    private func confirmation(action: PendingAction, snapshot: WatchWorkoutSnapshot) -> some View {
        if action == .discard {
            Section("Discard This Workout?") {
                Text("This removes the workout and its unsaved Watch recording.")
                Button("Discard", role: .destructive) { store.discardWorkout() }
                Button("Keep Workout") { pendingAction = nil }
            }
        } else {
            Section("Workout Recap") {
                recap(snapshot)
            }
            Section("How Hard Was It?") {
                Button { editingEffort = true } label: { EffortPicker(value: $effort) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens a Digital Crown effort editor")
            }
            Section {
                Button("Save Workout", systemImage: "checkmark") {
                    store.finishWorkout(effort: effort)
                }
                .buttonStyle(.borderedProminent)
                .disabled(snapshot.isFinishedRecord || !snapshot.exercises.flatMap(\.sets).contains(where: \.completed))
                Button("Keep Training") { if opensFinish { dismiss() } else { pendingAction = nil } }
            } footer: {
                Text(store.workoutSessionManager == nil
                     ? "The workout saves in Light. Health contains only the sensor window that was actually recorded."
                     : "Light finishes the Watch recording and syncs the final workout.")
            }
        }
    }

    private func recap(_ snapshot: WatchWorkoutSnapshot) -> some View {
        let sets = snapshot.exercises.flatMap(\.sets).filter(\.completed)
        let volume = sets.reduce(0) { $0 + (($1.weight ?? 0) * Double($1.reps ?? 0)) }
        let durationEnd = snapshot.isFinishedRecord ? (snapshot.endDate ?? Date()) : Date()
        let duration = max(0, durationEnd.timeIntervalSince(snapshot.startDate))
        return Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                recapMetric(WatchNumber.clock(duration), "Duration", IronTheme.metricTime)
                recapMetric("\(sets.count)", "Sets", IronTheme.metricSets)
            }
            GridRow {
                recapMetric(volume > 0 ? WatchNumber.format(volume) : "—",
                            snapshot.weightUnit?.symbol ?? "volume", IronTheme.metricVolume)
                if let manager = store.workoutSessionManager {
                    LiveRecapEnergy(manager: manager)
                } else {
                    recapMetric(WatchNumber.whole(snapshot.activeEnergyKilocalories),
                                "Active kcal", IronTheme.metricEnergy)
                }
            }
        }
    }

    private func recapMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.ironMetric(.title3)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(IronTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingText: String {
        if store.isRecoveringRecording { return "Recovering" }
        if store.isStartingRecording { return "Starting" }
        guard let manager = store.workoutSessionManager else { return "Not recording" }
        switch manager.state {
        case .running: return "On Watch"
        case .paused: return "Paused"
        case .stopped: return "Saving"
        case .ended: return "Finished"
        default: return "Preparing"
        }
    }

    private var syncText: String {
        let count = WatchWorkoutStore.shared.pendingEvents().count
        return count == 0 ? "Saved" : "\(count) queued"
    }
}
private struct LiveRecapEnergy: View {
    @ObservedObject var manager: WorkoutSessionManager
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WatchNumber.whole(manager.burnedCalories)).font(.ironMetric(.title3)).foregroundStyle(IronTheme.metricEnergy)
            Text("Active kcal").font(.caption2).foregroundStyle(IronTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Estimated active energy \(WatchNumber.whole(manager.burnedCalories)) kilocalories")
    }
}

private struct EffortPicker: View {
    @Binding var value: Double
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...10, id: \.self) { level in
                    Capsule()
                        .fill(Double(level) <= value ? IronTheme.metricEffort : IronTheme.tertiaryFill)
                        .frame(height: CGFloat(6 + level * 3))
                }
            }
            Text(WatchNumber.format(value)).font(.ironMetric(.title2)).foregroundStyle(IronTheme.metricEffort)
            Text(effortLabel).font(.caption).foregroundStyle(IronTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session effort")
        .accessibilityValue("\(WatchNumber.format(value)) out of 10, \(effortLabel)")
    }
    private var effortLabel: String {
        switch value { case ..<3: return "Easy"; case ..<5: return "Light"
        case ..<7: return "Moderate"; case ..<9: return "Hard"; default: return "Max" }
    }
}
