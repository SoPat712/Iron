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

/// Shared semantic roles for the watch UI. The system canvas remains visible
/// and tonal grouping derives from the current watchOS appearance.
enum WatchUITheme {
    static let background = Color.clear
    static let card = Color.primary.opacity(0.10)
    static let elevatedCard = Color.primary.opacity(0.16)
    static let mutedCard = Color.primary.opacity(0.07)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.66)
    static let actionBlue = Color.accentColor
    static let success = Color.green
    static let danger = Color.red
    static let onAction = Color.white
    static let cornerRadius: CGFloat = 12
    static let compactCornerRadius: CGFloat = 10
}

/// A compact filled button that remains legible on a small watch display.
struct WatchActionButtonStyle: ButtonStyle {
    let tint: Color
    var foregroundColor: Color = WatchUITheme.onAction

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: WatchUITheme.compactCornerRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// A reusable tonal card for the compact, set-first watch layout.
struct WatchCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchUITheme.card)
            .clipShape(RoundedRectangle(cornerRadius: WatchUITheme.cornerRadius, style: .continuous))
    }
}

struct ContentView: View {
    var body: some View {
        _ContentView()
            .environmentObject(WorkoutSessionManagerStore.shared)
    }
}

private struct _ContentView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @ObservedObject private var phoneConnectionManager = PhoneConnectionManager.shared

    @ViewBuilder
    var body: some View {
        Group {
            if let manager = workoutSessionManagerStore.workoutSessionManager,
               workoutSessionManagerStore.workoutSnapshot != nil {
                workoutTabs {
                    WorkoutSessionView(workoutSessionManager: manager)
                }
            } else if workoutSessionManagerStore.workoutSnapshot != nil {
                workoutTabs {
                    OfflineWorkoutView()
                }
            } else {
                IdleWorkoutView(errorMessage: errorMessage,
                                pendingEventCount: WatchWorkoutStore.shared.pendingEvents().count,
                                phoneIsReachable: phoneConnectionManager.isReachable,
                                connectionIsActivated: phoneConnectionManager.isActivated)
            }
        }
        .background(WatchUITheme.background)
        .foregroundColor(WatchUITheme.primaryText)
        .accentColor(WatchUITheme.actionBlue)
    }

    private func workoutTabs<Workout: View>(@ViewBuilder workout: () -> Workout) -> some View {
        NavigationView {
            workout()
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
            return "Not authorized for Apple Health. You can authorize Iron in the settings app."
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
        if pendingEventCount > 0 {
            return pendingEventCount == 1 ? "1 CHANGE QUEUED" : "\(pendingEventCount) CHANGES QUEUED"
        }
        if phoneIsReachable { return "PHONE CONNECTED" }
        if connectionIsActivated { return "READY OFFLINE" }
        return "CONNECTING"
    }

    private var statusColor: Color {
        if hasHealthError { return WatchUITheme.danger }
        if pendingEventCount > 0 { return WatchUITheme.actionBlue }
        if phoneIsReachable { return WatchUITheme.success }
        return WatchUITheme.secondaryText
    }

    private var guidanceText: String {
        if let errorMessage = errorMessage { return errorMessage }
        if pendingEventCount > 0 {
            return "Saved on this watch. Iron will deliver every queued change when your iPhone reconnects."
        }
        return "Start a workout on your iPhone. Your watch will show every exercise, then one set at a time."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WatchCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: hasHealthError ? "exclamationmark.triangle.fill" : "applewatch")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundColor(hasHealthError ? WatchUITheme.danger : WatchUITheme.actionBlue)
                                .frame(width: 38, height: 38)
                                .background((hasHealthError ? WatchUITheme.danger : WatchUITheme.actionBlue).opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(statusColor)
                                        .frame(width: 6, height: 6)
                                    Text(hasHealthError ? "HEALTH ACCESS" : statusText)
                                        .font(.system(.caption2, design: .rounded).weight(.bold))
                                        .foregroundColor(statusColor)
                                }

                                Text("Iron on Apple Watch")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .lineLimit(1)
                            }
                        }

                        Text(guidanceText)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(WatchUITheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                WatchCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("EXERCISE LIST")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundColor(WatchUITheme.actionBlue)

                        Text("Open a movement to log the current set, swipe sets with the arrows, then scroll for add, replace, and delete.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(WatchUITheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scenePadding()
        }
        .background(WatchUITheme.background)
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
