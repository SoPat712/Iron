//
//  MainContentView.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 02.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WatchKit
import HealthKit

/// Shared semantic roles for the watch UI. watchOS paints the canvas, so Iron
/// only names tints and lets `List`/`Section` provide grouping and insets.
enum WatchUITheme {
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let actionBlue = Color.accentColor
    static let success = Color.green
    static let danger = Color.red
}

struct ContentView: View {
    @ObservedObject private var workoutSessionManagerStore = WorkoutSessionManagerStore.shared

    var body: some View {
        _ContentView()
            .environmentObject(workoutSessionManagerStore)
            .alert("Workout Not Saved", isPresented: Binding(
                get: { workoutSessionManagerStore.persistenceFailure != nil },
                set: { if !$0 { workoutSessionManagerStore.clearPersistenceFailure() } }
            )) {
                Button("OK", role: .cancel) {
                    workoutSessionManagerStore.clearPersistenceFailure()
                }
            } message: {
                Text(workoutSessionManagerStore.persistenceFailure?.message ?? "Please try again.")
            }
    }
}

private struct _ContentView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @ObservedObject private var phoneConnectionManager = PhoneConnectionManager.shared

    @ViewBuilder
    var body: some View {
        if let manager = workoutSessionManagerStore.workoutSessionManager,
           workoutSessionManagerStore.workoutSnapshot != nil {
            NavigationStack {
                WorkoutSessionView(workoutSessionManager: manager)
            }
        } else if workoutSessionManagerStore.workoutSnapshot != nil {
            NavigationStack {
                OfflineWorkoutView()
            }
        } else {
            NavigationStack {
                IdleWorkoutView(
                    errorMessage: errorMessage,
                    pendingEventCount: WatchWorkoutStore.shared.pendingEvents().count,
                    phoneIsReachable: phoneConnectionManager.isReachable,
                    connectionIsActivated: phoneConnectionManager.isActivated
                )
            }
        }
    }

    private var errorMessage: String? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "HealthKit is not available on this device."
        }

        switch WorkoutSessionManager.healthStore.authorizationStatus(for: .workoutType()) {
        case .notDetermined:
            return nil
        case .sharingAuthorized:
            return nil
        case .sharingDenied:
            return "Not authorized for Apple Health. You can authorize Iron in the Settings app."
        @unknown default:
            return nil
        }
    }
}

private struct IdleWorkoutView: View {
    let errorMessage: String?
    let pendingEventCount: Int
    let phoneIsReachable: Bool
    let connectionIsActivated: Bool

    private var hasHealthError: Bool {
        errorMessage != nil
    }

    private var statusText: String {
        if hasHealthError { return "Health Access" }
        if pendingEventCount > 0 {
            return pendingEventCount == 1 ? "1 change queued" : "\(pendingEventCount) changes queued"
        }
        if phoneIsReachable { return "iPhone connected" }
        if connectionIsActivated { return "Ready offline" }
        return "Connecting…"
    }

    private var statusColor: Color {
        if hasHealthError { return WatchUITheme.danger }
        if pendingEventCount > 0 { return WatchUITheme.actionBlue }
        if phoneIsReachable { return WatchUITheme.success }
        return WatchUITheme.secondaryText
    }

    private var guidanceText: String {
        if let errorMessage { return errorMessage }
        if pendingEventCount > 0 {
            return "Saved on this watch. Iron delivers every queued change when your iPhone reconnects."
        }
        return "Start a workout on your iPhone. Your watch shows every exercise, then one set at a time."
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text(statusText)
                } icon: {
                    Image(systemName: hasHealthError ? "exclamationmark.triangle.fill" : "applewatch")
                }
                .foregroundStyle(statusColor)
            } footer: {
                Text(guidanceText)
            }

            Section {
                Text("Open a movement to log the current set, step sets with the arrows, then scroll for add, replace, and delete.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Exercise List")
            }
        }
        .navigationTitle("Iron")
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WorkoutSessionManagerStore.shared)
    }
}
#endif
