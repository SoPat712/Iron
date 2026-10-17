//
//  OptionsView.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 11.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI

struct OptionsView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @State private var pendingAction: PendingAction?
    @State private var sessionEffort = 7

    private enum PendingAction {
        case finish
        case discard
    }

    var body: some View {
        List {
            if let pendingAction {
                Section {
                    if pendingAction == .finish {
                        Picker("Effort", selection: $sessionEffort) {
                            ForEach(1...10, id: \.self) { value in
                                Text("\(value) · \(effortLabel(for: value))").tag(value)
                            }
                        }
                    }

                    Button(
                        pendingAction == .discard ? "Yes, Discard" : "Save Workout",
                        systemImage: pendingAction == .discard ? "trash" : "checkmark",
                        role: pendingAction == .discard ? .destructive : nil
                    ) {
                        perform(pendingAction)
                    }

                    Button("Keep Workout") { self.pendingAction = nil }
                } header: {
                    Text(pendingAction == .discard ? "Discard This Workout?" : "Finish This Workout?")
                } footer: {
                    Text(pendingAction == .discard
                         ? "This removes the local session and cannot be undone on the watch."
                         : "Rate the whole session, then save it even if the iPhone is offline.")
                }
            } else {
                Section {
                    Button("Finish Workout", systemImage: "checkmark.circle.fill") {
                        pendingAction = .finish
                    }
                    .accessibilityHint("Opens a confirmation before saving the workout.")
                } footer: {
                    Text("Save the session and sync your final state.")
                }

                Section {
                    Button("Discard Workout", systemImage: "trash.fill", role: .destructive) {
                        pendingAction = .discard
                    }
                    .accessibilityHint("Opens a confirmation before removing the workout.")
                } footer: {
                    Text("Remove this session without saving a result.")
                }
            }
        }
        .navigationTitle("End Workout")
        .onAppear(perform: loadSavedSessionEffort)
    }

    private func effortLabel(for value: Int) -> String {
        switch value {
        case 1...2: return "Easy"
        case 3...4: return "Light"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        default: return "Max"
        }
    }

    private func loadSavedSessionEffort() {
        guard let effort = workoutSessionManagerStore.workoutSnapshot?.sessionEffort else { return }
        sessionEffort = min(max(Int(effort.rounded()), 1), 10)
    }

    private func perform(_ action: PendingAction) {
        pendingAction = nil
        guard let snapshot = workoutSessionManagerStore.workoutSnapshot else { return }

        switch action {
        case .finish:
            let manager = workoutSessionManagerStore.workoutSessionManager
            let start = manager?.startDate ?? snapshot.startDate
            let uuid = manager?.uuid ?? snapshot.workoutID
            let end = manager?.endDate ?? snapshot.endDate ?? Date()
            workoutSessionManagerStore.endWorkoutSession(
                start: start,
                end: end,
                title: snapshot.title,
                uuid: uuid,
                sessionEffort: Double(sessionEffort))
        case .discard:
            let uuid = workoutSessionManagerStore.workoutSessionManager?.uuid ?? snapshot.workoutID
            workoutSessionManagerStore.discardWorkoutSession(uuid: uuid)
        }
    }
}
