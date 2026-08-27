//
//  HealthSettingsView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 31.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import WorkoutDataKit

struct HealthSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var exerciseStore: ExerciseStore
    @Environment(\.managedObjectContext) var managedObjectContext

    @State private var updating = false
    @State private var authorizing = false
    @State private var accessState = HealthManager.AccessState.notDetermined
    @State private var activeModal: HealthModal?

    private struct HealthModal: Identifiable {
        enum Kind {
            case access(Result<Void, Error>)
            case workoutSync(Result<HealthManager.WorkoutUpdates, Error>)
            case healthAppUnavailable
        }

        let id = UUID()
        let kind: Kind
    }

    private enum HealthAccessSetupError: LocalizedError {
        case needsReview

        var errorDescription: String? {
            "Some Health categories remain off. Review Iron's access in Apple Health to enable the categories you want to use."
        }
    }

    @ViewBuilder
    private func workoutSyncResultSheet(_ updateResult: Result<HealthManager.WorkoutUpdates, Error>) -> some View {
        switch updateResult {
        case .success(let updates):
            IronStatusSheet(
                headerTitle: "Apple Health",
                title: "Workout sync complete",
                message: "\(updates.created) created · \(updates.modified) updated · \(updates.deleted) removed",
                systemImage: "heart.circle.fill",
                tint: IronTheme.success
            )
        case .failure(let error):
            IronStatusSheet(
                headerTitle: "Apple Health",
                title: "Could not update workouts",
                message: error.localizedDescription,
                systemImage: "heart.slash.fill",
                tint: IronTheme.danger
            )
        }
    }

    @ViewBuilder
    private func accessResultSheet(_ result: Result<Void, Error>) -> some View {
        switch result {
        case .success:
            IronStatusSheet(
                headerTitle: "Apple Health",
                title: "Health access requested",
                message: "Iron can now sync strength workouts and exchange supported body measurements. You can adjust individual categories in the Health app.",
                systemImage: "heart.circle.fill",
                tint: IronTheme.success
            )
        case .failure(let error):
            IronStatusSheet(
                headerTitle: "Apple Health",
                title: error is HealthAccessSetupError ? "Health access needs review" : "Could not connect",
                message: error.localizedDescription,
                systemImage: "heart.slash.fill",
                tint: error is HealthAccessSetupError ? IronTheme.warning : IronTheme.danger
            )
        }
    }

    var body: some View {
        List {
            Section("Connection") {
                accessStatusRow

                LabeledContent("Write access", value: accessState.permissionStatus)
                LabeledContent("Data types", value: "Workouts + body")
                LabeledContent("Managed in", value: "Apple Health")

                if accessState == .notDetermined {
                    Button(action: requestAccess) {
                        HStack(spacing: 9) {
                            if authorizing {
                                ProgressView()
                            } else {
                                Image(systemName: "heart.text.square.fill")
                            }
                            Text(authorizing ? "Requesting access…" : accessState.actionTitle)
                        }
                    }
                    .disabled(authorizing)
                }

                if accessState == .needsReview || accessState == .ready {
                    Button(action: openHealthApp) {
                        Label("Review access in Health", systemImage: "arrow.up.forward.app")
                    }
                }
            }

            Section("Workout History") {
                workoutSyncSummaryRow

                Button(action: updateWorkouts) {
                    HStack(spacing: 9) {
                        if updating {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(updating ? "Syncing workout history…" : "Sync workout history")
                    }
                }
                .disabled(updating || accessState != .ready)
            }

            Section("Data Exchanged") {
                healthDataRow(
                    icon: "figure.strengthtraining.traditional",
                    title: "Strength workouts",
                    detail: "Start time, duration, and workout title are written to Apple Health."
                )
                healthDataRow(
                    icon: "scalemass.fill",
                    title: "Body measurements",
                    detail: "Iron can read and write weight, height, body fat, and waist circumference."
                )
                healthDataRow(
                    icon: "applewatch.radiowaves.left.and.right",
                    title: "Watch workout metrics",
                    detail: "Heart rate and active energy stay in Apple Health when a Watch workout is active."
                )
            }

            Section {
                privacyRow
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(IronTheme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironDestinationScreen(title: "Apple Health")
        .ironScreen()
        .onAppear(perform: refreshAccessState)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshAccessState()
        }
        .sheet(item: $activeModal) { modal in
            switch modal.kind {
            case .access(let result):
                accessResultSheet(result)
            case .workoutSync(let result):
                workoutSyncResultSheet(result)
            case .healthAppUnavailable:
                IronStatusSheet(
                    headerTitle: "Apple Health",
                    title: "Could not open Health",
                    message: "Open the Health app manually, tap your profile, then review Apps and Services → Iron.",
                    systemImage: "arrow.up.forward.app.fill",
                    tint: IronTheme.warning
                )
            }
        }
    }

    private var accessStatusRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(accessState.title)
                        .font(.headline)
                        .foregroundColor(IronTheme.primaryText)
                    Text(accessState.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(accessState.tint)
                }
                Text(accessState.detail)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: accessState.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(accessState.tint)
                .frame(width: 28)
        }
        .padding(.vertical, 4)
    }

    private var workoutSyncSummaryRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Repair or backfill workout history")
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text("Reconcile completed Iron sessions with Apple Health. Existing matches are updated instead of duplicated.")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.body.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private func healthDataRow(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private var privacyRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("You stay in control")
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text("Apple Health permissions can be changed at any time. Iron never shares your health data socially or with other Iron users.")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "hand.raised.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private func openHealthApp() {
        guard let healthURL = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(healthURL, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                activeModal = HealthModal(kind: .healthAppUnavailable)
            }
        }
    }

    private func refreshAccessState() {
        accessState = HealthManager.shared.accessState
    }

    private func requestAccess() {
        guard !authorizing else { return }
        authorizing = true
        HealthManager.shared.requestWorkoutAndBodyMeasurementPermission { result in
            DispatchQueue.main.async {
                authorizing = false
                refreshAccessState()
                let verifiedResult: Result<Void, Error>
                switch result {
                case .failure:
                    verifiedResult = result
                case .success where accessState == .ready:
                    verifiedResult = .success(())
                case .success:
                    verifiedResult = .failure(HealthAccessSetupError.needsReview)
                }
                activeModal = HealthModal(kind: .access(verifiedResult))
            }
        }
    }

    private func updateWorkouts() {
        updating = true
        HealthManager.shared.updateHealthWorkouts(managedObjectContext: managedObjectContext, exerciseStore: exerciseStore) { result in
            DispatchQueue.main.async {
                refreshAccessState()
                activeModal = HealthModal(kind: .workoutSync(result))
                updating = false
            }
        }
    }
}

private extension HealthManager.AccessState {
    var title: String {
        switch self {
        case .unavailable: return "Apple Health unavailable"
        case .notDetermined: return "Connect Apple Health"
        case .needsReview: return "Review Health access"
        case .ready: return "Apple Health connected"
        }
    }

    var detail: String {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device. Iron will continue storing everything locally."
        case .notDetermined:
            return "Choose the workout and body-measurement categories Iron may exchange. Nothing leaves your device without permission."
        case .needsReview:
            return "One or more write categories are unavailable. Review access to keep workouts and supported measurements aligned."
        case .ready:
            return "Workout and supported body-measurement write access is ready. Setup also requested read access; Apple keeps read decisions private, and every category remains under your control in Health."
        }
    }

    var permissionStatus: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not set"
        case .needsReview: return "Review"
        case .ready: return "Write ready"
        }
    }

    var badge: String {
        switch self {
        case .unavailable: return "UNAVAILABLE"
        case .notDetermined: return "NOT CONNECTED"
        case .needsReview: return "REVIEW"
        case .ready: return "CONNECTED"
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable: return "heart.slash.fill"
        case .notDetermined: return "heart.text.square.fill"
        case .needsReview: return "exclamationmark.triangle.fill"
        case .ready: return "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unavailable: return IronTheme.secondaryText
        case .notDetermined: return IronTheme.danger
        case .needsReview: return IronTheme.warning
        case .ready: return IronTheme.success
        }
    }

    var actionTitle: String {
        switch self {
        case .unavailable: return "Apple Health unavailable"
        case .notDetermined: return "Connect Apple Health"
        case .needsReview: return "Request access again"
        case .ready: return "Review requested categories"
        }
    }
}

import HealthKit
extension HealthSettingsView {
    static var isSupported: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}

struct HealthSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HealthSettingsView()
    }
}
