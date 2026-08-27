//
//  WorkoutSessionView.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 09.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import Combine

struct WorkoutSessionView: View {
    @ObservedObject var workoutSessionManager: WorkoutSessionManager

    var body: some View {
        WorkoutProjectionView(workoutSessionManager: workoutSessionManager)
    }
}

/// Used when the HealthKit session has been recovered/ended but the durable
/// workout projection is still available for editing or retrying.
struct OfflineWorkoutView: View {
    var body: some View {
        WorkoutProjectionView(workoutSessionManager: nil)
    }
}

private struct WorkoutProjectionView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @ObservedObject private var phoneConnectionManager = PhoneConnectionManager.shared
    let workoutSessionManager: WorkoutSessionManager?

    @State private var selectedSetID: UUID?
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var rpeText = ""
    @State private var inputError: String?
    @State private var pendingDraftCommit: DispatchWorkItem?

    private var snapshot: WatchWorkoutSnapshot? {
        workoutSessionManagerStore.workoutSnapshot
    }

    private var selectedSet: (exercise: WatchWorkoutExercise, set: WatchWorkoutSet)? {
        findSelectedSet(id: selectedSetID)
    }

    private var completedSetCount: Int {
        snapshot?.exercises.reduce(0) { count, exercise in
            count + exercise.sets.filter { $0.completed }.count
        } ?? 0
    }

    private var totalSetCount: Int {
        snapshot?.exercises.reduce(0) { count, exercise in
            count + exercise.sets.count
        } ?? 0
    }

    private var orderedSets: [(exercise: WatchWorkoutExercise, set: WatchWorkoutSet)] {
        snapshot?.exercises.flatMap { exercise in
            exercise.sets.map { (exercise: exercise, set: $0) }
        } ?? []
    }

    private var selectedSetPosition: Int? {
        guard let selectedSetID = selectedSetID else { return nil }
        return orderedSets.firstIndex(where: { $0.set.id == selectedSetID })
    }

    private var pendingEventCount: Int {
        WatchWorkoutStore.shared.pendingEvents().count
    }

    private var syncStatus: (text: String, color: Color) {
        if pendingEventCount > 0 {
            let text = pendingEventCount == 1 ? "1 CHANGE QUEUED" : "\(pendingEventCount) CHANGES QUEUED"
            return (text, WatchUITheme.actionBlue)
        }
        if phoneConnectionManager.isReachable {
            return ("PHONE CONNECTED", WatchUITheme.success)
        }
        return ("OFFLINE • SAVED", WatchUITheme.actionBlue)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                if let snapshot = snapshot {
                    workoutHeader(snapshot: snapshot)

                    if let selectedSet = selectedSet {
                        SetEditorView(exercise: selectedSet.exercise,
                                      set: selectedSet.set,
                                      weightUnit: snapshot.weightUnit ?? .kilogram,
                                      position: selectedSetPosition.map { $0 + 1 } ?? 1,
                                      totalSetCount: orderedSets.count,
                                      weightText: $weightText,
                                      repsText: $repsText,
                                      rpeText: $rpeText,
                                      errorMessage: inputError,
                                      canSelectPrevious: (selectedSetPosition ?? 0) > 0,
                                      canSelectNext: (selectedSetPosition ?? orderedSets.count) < orderedSets.count - 1,
                                      selectPrevious: { selectAdjacentSet(offset: -1) },
                                      selectNext: { selectAdjacentSet(offset: 1) },
                                      toggleCompleted: toggleSelectedSet)
                            .id("focused-set-editor")
                    } else {
                        WatchCard {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundColor(WatchUITheme.actionBlue)
                                Text("Select a set to edit it.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(WatchUITheme.secondaryText)
                            }
                        }
                    }

                    restTimerSection(snapshot: snapshot)
                    workoutMetrics
                    exerciseList(snapshot: snapshot)
                } else {
                    WatchCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NO WORKOUT LOADED")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundColor(WatchUITheme.secondaryText)
                            Text("Start a workout on your iPhone to send a set list to the watch.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(WatchUITheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                }
                .scenePadding()
            }
            .onChange(of: selectedSetID) { newID in
                inputError = nil
                loadSelectedSet(for: newID)
                guard newID != nil else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo("focused-set-editor", anchor: .top)
                    }
                }
            }
        }
        .background(WatchUITheme.background)
        .onAppear {
            initializeSelectedSet()
        }
        .onChange(of: weightText) { _ in scheduleDraftCommit() }
        .onChange(of: repsText) { _ in scheduleDraftCommit() }
        .onChange(of: rpeText) { _ in scheduleDraftCommit() }
        .onChange(of: snapshot?.selectedSetID) { newID in
            guard let newID = newID, selectedSetID != newID else { return }
            selectedSetID = newID
            loadSelectedSet(for: newID)
        }
        .onChange(of: orderedSets.map { $0.set.id }) { _ in
            reconcileSelectedSet()
        }
        .onDisappear {
            pendingDraftCommit?.cancel()
            _ = commitDraftIfPresent()
        }
    }

    private func workoutHeader(snapshot: WatchWorkoutSnapshot) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.title ?? "Workout")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    ElapsedTimeView(start: workoutSessionManager?.startDate ?? snapshot.startDate,
                                    end: workoutSessionManager?.endDate ?? snapshot.endDate ?? context.date)
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundColor(WatchUITheme.primaryText)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(syncStatus.color)
                        .frame(width: 6, height: 6)
                    Text(syncStatus.text)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(syncStatus.color)

                    Spacer(minLength: 4)

                    Text("\(completedSetCount)/\(totalSetCount) SETS")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(WatchUITheme.secondaryText)
                }

                ProgressView(value: Double(completedSetCount),
                             total: Double(max(totalSetCount, 1)))
                    .progressViewStyle(.linear)
                    .accentColor(WatchUITheme.actionBlue)
                    .accessibilityLabel("Workout progress")
                    .accessibilityValue("\(completedSetCount) of \(totalSetCount) sets complete")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchUITheme.mutedCard)
            .clipShape(RoundedRectangle(cornerRadius: WatchUITheme.compactCornerRadius, style: .continuous))
        }
    }

    private var workoutMetrics: some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 7) {
                Text("LIVE METRICS")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(WatchUITheme.secondaryText)

                HStack(spacing: 6) {
                    MetricTile(value: workoutSessionManager?.burnedCalories,
                               label: "KCAL",
                               symbol: "flame.fill",
                               tint: .orange)

                    if let manager = workoutSessionManager {
                        WatchCardMetric {
                            HeartRateView(mostRecentHeartRate: manager.mostRecentHeartRate,
                                          mostRecentHeartRateDate: manager.mostRecentHeartRateDate)
                        }
                    } else {
                        MetricTile(value: nil,
                                   label: "BPM",
                                   symbol: "heart.fill",
                                   tint: WatchUITheme.tertiaryText)
                    }
                }
            }
        }
    }

    private func exerciseList(snapshot: WatchWorkoutSnapshot) -> some View {
        let weightUnit = snapshot.weightUnit ?? .kilogram

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EXERCISES")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(WatchUITheme.secondaryText)
                Spacer()
                Text("\(snapshot.exercises.count)")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(WatchUITheme.actionBlue)
            }

            if snapshot.exercises.isEmpty {
                WatchCard {
                    Text("No exercises were sent with this workout.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(WatchUITheme.secondaryText)
                }
            } else {
                WatchCard {
                    VStack(spacing: 10) {
                        ForEach(Array(snapshot.exercises.enumerated()), id: \.element.id) { index, exercise in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(exercise.name)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .lineLimit(2)
                                Spacer(minLength: 4)
                                let completed = exercise.sets.filter { $0.completed }.count
                                Text("\(completed)/\(exercise.sets.count)")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundColor(WatchUITheme.secondaryText)
                            }

                            ForEach(exercise.sets) { set in
                                let isSelected = selectedSetID == set.id
                                Button(action: {
                                    selectSet(set.id)
                                }) {
                                    HStack(spacing: 7) {
                                        Text("\(set.order)")
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundColor(isSelected ? WatchUITheme.onAction : WatchUITheme.secondaryText)
                                            .frame(width: 20, height: 20)
                                            .background(isSelected ? WatchUITheme.actionBlue : WatchUITheme.mutedCard)
                                            .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(set.completed ? "Complete" : "Ready")
                                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                                .foregroundColor(set.completed ? WatchUITheme.success : WatchUITheme.secondaryText)
                                            Text(set.displayText(weightUnit: weightUnit))
                                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                                .foregroundColor(WatchUITheme.primaryText)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 3)

                                        Image(systemName: set.completed ? "checkmark.circle.fill" : "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(set.completed ? WatchUITheme.success : WatchUITheme.tertiaryText)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isSelected ? WatchUITheme.actionBlue.opacity(0.22) : Color.clear)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: WatchUITheme.compactCornerRadius,
                                            style: .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Set \(set.order), \(exercise.name)")
                                .accessibilityValue(
                                    set.completed
                                        ? "Completed, \(set.displayText(weightUnit: weightUnit))"
                                        : set.displayText(weightUnit: weightUnit)
                                )
                            }
                        }

                            if index < snapshot.exercises.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func restTimerSection(snapshot: WatchWorkoutSnapshot) -> some View {
        let end = workoutSessionManager?.restTimerEnd ?? snapshot.restTimerEnd
        let keepRunning = workoutSessionManager?.keepRestTimerRunning ?? snapshot.keepRestTimerRunning

        return TimelineView(.periodic(from: Date(), by: 1)) { context in
            WatchCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .foregroundColor(WatchUITheme.actionBlue)
                            Text("REST TIMER")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundColor(WatchUITheme.secondaryText)
                        }

                        Spacer()

                        RestTimerView(date: context.date,
                                      end: end,
                                      keepRunning: keepRunning)
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    }

                    HStack(spacing: 5) {
                        ForEach([60.0, 90.0, 120.0], id: \.self) { duration in
                            Button(action: {
                                guard commitDraftIfPresent() else { return }
                                workoutSessionManagerStore.startRestTimer(
                                    workoutID: snapshot.workoutID,
                                    duration: duration)
                            }) {
                                Text(restPresetLabel(duration))
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(WatchUITheme.actionBlue.opacity(0.18))
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: WatchUITheme.compactCornerRadius,
                                            style: .continuous
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start a \(Int(duration)) second rest timer")
                        }
                    }

                    if let end, keepRunning || end > context.date {
                        Button(action: {
                            workoutSessionManagerStore.stopRestTimer(workoutID: snapshot.workoutID)
                        }) {
                            Label("Stop Timer", systemImage: "stop.fill")
                        }
                        .buttonStyle(
                            WatchActionButtonStyle(
                                tint: WatchUITheme.elevatedCard,
                                foregroundColor: WatchUITheme.primaryText
                            )
                        )
                    }
                }
            }
        }
    }

    private func restPresetLabel(_ duration: TimeInterval) -> String {
        switch Int(duration) {
        case 60: return "1:00"
        case 90: return "1:30"
        case 120: return "2:00"
        default: return "\(Int(duration))s"
        }
    }

    private func initializeSelectedSet() {
        reconcileSelectedSet()
    }

    private func reconcileSelectedSet() {
        let availableIDs = orderedSets.map { $0.set.id }
        if let selectedSetID, availableIDs.contains(selectedSetID) {
            return
        }

        let nextID = snapshot?.selectedSetID.flatMap { availableIDs.contains($0) ? $0 : nil }
            ?? availableIDs.first
        selectedSetID = nextID

        if let nextID {
            loadSelectedSet(for: nextID)
        } else {
            weightText = ""
            repsText = ""
            rpeText = ""
            inputError = nil
        }
    }

    private func findSelectedSet(id: UUID?) -> (exercise: WatchWorkoutExercise, set: WatchWorkoutSet)? {
        guard let id = id, let snapshot = snapshot else { return nil }
        for exercise in snapshot.exercises {
            if let set = exercise.sets.first(where: { $0.id == id }) {
                return (exercise, set)
            }
        }
        return nil
    }

    private func loadSelectedSet(for id: UUID? = nil) {
        guard let selectedSet = findSelectedSet(id: id ?? selectedSetID) else { return }
        weightText = selectedSet.set.weight.flatMap { weight in
            weight > 0 ? String(format: "%g", weight) : nil
        } ?? ""
        repsText = selectedSet.set.reps.map(String.init) ?? ""
        rpeText = selectedSet.set.rpe.map { String(format: "%.1f", $0) } ?? ""
    }

    private func scheduleDraftCommit() {
        pendingDraftCommit?.cancel()
        let workItem = DispatchWorkItem {
            _ = commitDraftIfPresent()
        }
        pendingDraftCommit = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @discardableResult
    private func commitDraftIfPresent() -> Bool {
        guard selectedSet != nil else { return true }
        return commitSelectedSet()
    }

    @discardableResult
    private func commitSelectedSet() -> Bool {
        guard let snapshot = snapshot,
              let selectedSetID = selectedSetID,
              let selectedSet = selectedSet,
              let values = validatedInput() else { return false }
        workoutSessionManagerStore.updateSet(
            workoutID: snapshot.workoutID,
            exerciseID: selectedSet.exercise.id,
            setID: selectedSetID,
            weight: values.weight,
            reps: values.reps,
            rpe: values.rpe)
        inputError = nil
        return true
    }

    private func toggleSelectedSet() {
        guard let snapshot = snapshot,
              let selectedSetID = selectedSetID,
              let selectedSet = selectedSet,
              commitSelectedSet() else { return }

        workoutSessionManagerStore.toggleSet(workoutID: snapshot.workoutID,
                                             exerciseID: selectedSet.exercise.id,
                                             setID: selectedSetID)

        inputError = nil
        if !selectedSet.set.completed {
            workoutSessionManagerStore.startRestTimer(
                workoutID: snapshot.workoutID,
                duration: selectedSet.exercise.restTimerDuration ?? 60
            )
            if let nextID = nextIncompleteSetID(after: selectedSetID) {
                self.selectedSetID = nextID
                loadSelectedSet(for: nextID)
            }
        }
    }

    private func selectAdjacentSet(offset: Int) {
        guard let currentPosition = selectedSetPosition else { return }
        let targetPosition = currentPosition + offset
        guard orderedSets.indices.contains(targetPosition) else { return }
        selectSet(orderedSets[targetPosition].set.id)
    }

    private func selectSet(_ setID: UUID) {
        guard setID != selectedSetID else { return }
        if selectedSetID != nil, !commitSelectedSet() {
            return
        }
        selectedSetID = setID
        loadSelectedSet(for: setID)
    }

    private func validatedInput() -> (weight: Double?, reps: Int?, rpe: Double?)? {
        let normalizedWeight = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let normalizedReps = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRPE = rpeText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        let weight = normalizedWeight.isEmpty ? nil : Double(normalizedWeight)
        let reps = normalizedReps.isEmpty ? nil : Int(normalizedReps)
        let rpe = normalizedRPE.isEmpty ? nil : Double(normalizedRPE)

        guard normalizedWeight.isEmpty || weight != nil else {
            inputError = "Enter a valid weight. Your saved value was not changed."
            return nil
        }
        guard normalizedReps.isEmpty || reps != nil else {
            inputError = "Enter whole reps. Your saved value was not changed."
            return nil
        }
        guard normalizedRPE.isEmpty || rpe != nil else {
            inputError = "Enter an RPE from 5 to 10 in half steps. Your saved value was not changed."
            return nil
        }
        guard weight.map({ $0 >= 0 }) ?? true else {
            inputError = "Weight cannot be negative."
            return nil
        }
        guard reps.map({ $0 >= 0 }) ?? true else {
            inputError = "Reps cannot be negative."
            return nil
        }
        guard rpe.map({ value in
            (5...10).contains(value) && abs((value * 2).rounded() - (value * 2)) < 0.000_001
        }) ?? true else {
            inputError = "RPE must be 5 to 10 in 0.5 steps."
            return nil
        }
        return (weight, reps, rpe)
    }

    private func nextIncompleteSetID(after setID: UUID) -> UUID? {
        guard let snapshot = snapshot else { return nil }
        let sets = snapshot.exercises.flatMap { $0.sets }
        guard let index = sets.firstIndex(where: { $0.id == setID }), sets.count > 1 else { return nil }
        let following = sets.dropFirst(index + 1) + sets.prefix(index)
        return following.first(where: { !$0.completed })?.id
    }
}

private struct WatchCardMetric<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(WatchUITheme.mutedCard)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct MetricTile: View {
    let value: Double?
    let label: String
    let symbol: String
    let tint: Color

    private var displayValue: String {
        value.map { String(format: "%.0f", $0) } ?? "--"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(displayValue)
                    .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundColor(WatchUITheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(WatchUITheme.mutedCard)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayValue) \(label)")
    }
}

private struct SetEditorView: View {
    let exercise: WatchWorkoutExercise
    let set: WatchWorkoutSet
    let weightUnit: WatchWorkoutWeightUnit
    let position: Int
    let totalSetCount: Int
    @Binding var weightText: String
    @Binding var repsText: String
    @Binding var rpeText: String
    let errorMessage: String?
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let toggleCompleted: () -> Void

    var body: some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FOCUSED SET")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundColor(WatchUITheme.actionBlue)
                        Text(exercise.name)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(set.completed ? WatchUITheme.success : WatchUITheme.secondaryText)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 6) {
                    WatchInputField(title: "WEIGHT", unit: weightUnit.symbol, value: $weightText)
                    WatchInputField(title: "REPS", unit: "", value: $repsText)
                    WatchInputField(title: "RPE", unit: "", value: $rpeText)
                }

                if let errorMessage = errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(WatchUITheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: toggleCompleted) {
                    Label(set.completed ? "Undo completion" : "Complete set",
                          systemImage: set.completed ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(WatchActionButtonStyle(tint: set.completed ? WatchUITheme.actionBlue : WatchUITheme.success))
                .accessibilityHint("Weight, repetitions, and effort save automatically.")

                HStack(spacing: 6) {
                    Text("SET \(position) OF \(totalSetCount)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(WatchUITheme.secondaryText)

                    Spacer(minLength: 4)

                    setNavigationButton(symbol: "chevron.left",
                                        label: "Previous set",
                                        enabled: canSelectPrevious,
                                        action: selectPrevious)
                    setNavigationButton(symbol: "chevron.right",
                                        label: "Next set",
                                        enabled: canSelectNext,
                                        action: selectNext)
                }

                if let previousText = set.previousDisplayText(weightUnit: weightUnit) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.left.circle.fill")
                            .foregroundColor(WatchUITheme.secondaryText)
                        Text("PREVIOUS")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundColor(WatchUITheme.secondaryText)
                        Spacer(minLength: 3)
                        Text(previousText)
                            .font(.system(.caption, design: .rounded).monospacedDigit())
                            .foregroundColor(WatchUITheme.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(WatchUITheme.mutedCard)
                    .clipShape(RoundedRectangle(cornerRadius: WatchUITheme.compactCornerRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Previous set")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func setNavigationButton(symbol: String,
                                     label: String,
                                     enabled: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? WatchUITheme.primaryText : WatchUITheme.tertiaryText)
                .frame(width: 44, height: 44)
                .background(WatchUITheme.mutedCard)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct WatchInputField: View {
    let title: String
    let unit: String
    @Binding var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundColor(WatchUITheme.secondaryText)

            HStack(spacing: 2) {
                TextField(title, text: $value)
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 34)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(WatchUITheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(WatchUITheme.mutedCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) input")
        .accessibilityValue(value.isEmpty ? "Empty" : value)
    }
}

private struct ElapsedTimeView: View {
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    let start: Date?
    let end: Date?

    var body: some View {
        Text(start.map { Self.durationFormatter.string(from: $0, to: end ?? Date()) ?? "--:--:--" } ?? "--:--:--")
    }
}

private struct RestTimerView: View {
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    let date: Date
    let end: Date?
    let keepRunning: Bool

    private var remainingTime: TimeInterval? {
        guard let end = end else { return nil }
        let remainingTime = end.timeIntervalSince(date)
        guard remainingTime >= 0 || keepRunning else { return nil }
        return remainingTime
    }

    // i.e. 8.1 and 8.9 should be displayed as 9.
    private var roundedRemainingTime: TimeInterval? {
        remainingTime?.rounded(.up)
    }

    var body: some View {
        let remainingTime = roundedRemainingTime
        let isOvertime = (remainingTime ?? 0) < 0
        let formatted = remainingTime.map {
            Self.durationFormatter.string(from: abs($0)) ?? "--:--"
        } ?? "READY"

        Text(isOvertime ? "+\(formatted)" : formatted)
            .foregroundColor(isOvertime ? WatchUITheme.danger : WatchUITheme.primaryText)
            .accessibilityLabel(
                isOvertime
                    ? "Over rest time by \(formatted)"
                    : (remainingTime == nil ? "Rest timer ready" : "Rest time remaining \(formatted)")
            )
    }
}

private struct HeartRateView: View {
    private static let maxHeartRateAge: Double = 10

    let mostRecentHeartRate: Double?
    let mostRecentHeartRateDate: Date?

    var body: some View {
        TimelineView(.periodic(from: mostRecentHeartRateDate ?? Date(), by: Self.maxHeartRateAge)) { context in
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .foregroundColor(measurementWasRecent(date: context.date) ? WatchUITheme.danger : WatchUITheme.tertiaryText)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mostRecentHeartRate.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                    Text("BPM")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(WatchUITheme.secondaryText)
                }
                PulsatingHeartView(bpm: measurementWasRecent(date: context.date) ? mostRecentHeartRate : nil)
                    .foregroundColor(measurementWasRecent(date: context.date) ? WatchUITheme.danger : WatchUITheme.tertiaryText)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func measurementWasRecent(date: Date) -> Bool {
        guard let mostRecentHeartRateDate = mostRecentHeartRateDate else {
            return false
        }
        return date.timeIntervalSince(mostRecentHeartRateDate) < Self.maxHeartRateAge
    }
}

private struct PulsatingHeartView: View {
    let bpm: Double?

    var body: some View {
        TimelineView(.animation) { context in
            Image(systemName: bpm != nil ? "heart.fill" : "heart")
                .scaleEffect(context.cadence == .live && bpm != nil ? scale(offset: context.date.timeIntervalSince1970) : 1)
        }
    }

    private func scale(offset: Double) -> Double {
        max(sin(2 * .pi * offset * (bpm ?? 0) / 60) * 0.15, 0) + 1
    }
}
