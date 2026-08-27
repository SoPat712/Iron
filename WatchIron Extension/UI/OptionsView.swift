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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WORKOUT OPTIONS")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(WatchUITheme.actionBlue)
                    Text("Finish cleanly or remove this session from the watch.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(WatchUITheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let pendingAction = pendingAction {
                    confirmationCard(for: pendingAction)
                } else {
                    finishCard
                    discardCard
                }
            }
            .scenePadding()
        }
        .background(WatchUITheme.background)
        .onAppear(perform: loadSavedSessionEffort)
    }

    private var finishCard: some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 8) {
                actionHeading(title: "Finish Workout",
                              detail: "Save the session and sync your final state.",
                              symbol: "checkmark.circle.fill",
                              tint: WatchUITheme.success)

                Button(action: { pendingAction = .finish }) {
                    Label("Finish Workout", systemImage: "checkmark")
                }
                .buttonStyle(WatchActionButtonStyle(tint: WatchUITheme.actionBlue))
                .accessibilityHint("Opens a confirmation before saving the workout.")
            }
        }
    }

    private var discardCard: some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 8) {
                actionHeading(title: "Discard Workout",
                              detail: "Remove this session without saving a result.",
                              symbol: "trash.fill",
                              tint: WatchUITheme.danger)

                Button(action: { pendingAction = .discard }) {
                    Label("Discard Workout", systemImage: "xmark")
                }
                .buttonStyle(WatchActionButtonStyle(tint: WatchUITheme.danger))
                .accessibilityHint("Opens a confirmation before removing the workout.")
            }
        }
    }

    private func confirmationCard(for action: PendingAction) -> some View {
        let isDiscard = action == .discard
        return WatchCard {
            VStack(alignment: .leading, spacing: 9) {
                actionHeading(title: isDiscard ? "Discard this workout?" : "Finish this workout?",
                              detail: isDiscard
                                ? "This removes the local session and cannot be undone on the watch."
                                : "Rate the whole session, then save it even if the phone is offline.",
                              symbol: isDiscard ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                              tint: isDiscard ? WatchUITheme.danger : WatchUITheme.success)

                if !isDiscard {
                    effortSelector
                }

                Button(action: { perform(action) }) {
                    Label(isDiscard ? "Yes, Discard" : "Save Workout",
                          systemImage: isDiscard ? "trash.fill" : "checkmark")
                }
                .buttonStyle(WatchActionButtonStyle(tint: isDiscard ? WatchUITheme.danger : WatchUITheme.actionBlue))

                Button(action: { pendingAction = nil }) {
                    Text("Keep Workout")
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

    private var effortSelector: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("SESSION EFFORT")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(WatchUITheme.secondaryText)
                Spacer()
                Text("\(sessionEffort)/10 · \(effortLabel)")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundColor(WatchUITheme.actionBlue)
            }

            Picker("Session effort", selection: $sessionEffort) {
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) · \(effortLabel(for: value))")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(height: 82)
            .accessibilityLabel("Session effort")
            .accessibilityValue("\(sessionEffort) out of 10, \(effortLabel)")
        }
        .padding(8)
        .background(WatchUITheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var effortLabel: String {
        effortLabel(for: sessionEffort)
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

    private func actionHeading(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(detail)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(WatchUITheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
