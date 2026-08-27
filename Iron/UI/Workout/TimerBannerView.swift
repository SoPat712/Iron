//
//  TimerBannerView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 14.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct TimerBannerView: View {
    @EnvironmentObject var restTimerStore: RestTimerStore
    
    @ObservedObject var workout: Workout

    @ObservedObject private var refresher = Refresher()
    
    @State private var activeSheet: SheetType?

    private enum SheetType: Identifiable {
        case restTimer
        case editTime
        
        var id: Self { self }
    }

    private let workoutTimerDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    private var editTimeSheet: some View {
        IronUtilitySheet(
            title: "Workout duration",
            subtitle: "Adjust the session clock",
            systemImage: "stopwatch",
            onClose: { activeSheet = nil }
        ) {
            EditCurrentWorkoutTimeView(workout: workout) {
                activeSheet = nil
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(IronTheme.modalSurface)
    }
    
    private var restTimerSheet: some View {
        IronUtilitySheet(
            title: "Rest timer",
            subtitle: "Dial in your recovery",
            systemImage: "timer",
            onClose: { activeSheet = nil }
        ) {
            RestTimerView()
                .environmentObject(restTimerStore)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(IronTheme.modalSurface)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                self.activeSheet = .editTime
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "stopwatch")
                        .foregroundColor(IronTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                        Text(workoutTimerDurationFormatter.string(from: workout.safeDuration) ?? "00:00")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundColor(IronTheme.primaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Capsule().fill(IronTheme.surface))
            }
            .buttonStyle(.plain)

            Button(action: {
                self.activeSheet = .restTimer
            }) {
                let remainingTime = restTimerStore.restTimerRemainingTime
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundColor((remainingTime ?? 0) < 0 ? IronTheme.danger : IronTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                        if let remainingTime = remainingTime {
                            Text(restTimerDurationFormatter.string(from: abs(remainingTime.rounded(.up))) ?? "00:00")
                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                .foregroundColor(remainingTime < 0 ? IronTheme.danger : IronTheme.primaryText)
                        } else {
                            Text("Start timer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(IronTheme.primaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Capsule().fill(IronTheme.surface))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 10)
        .background(IronTheme.background.overlay(IronHairline(), alignment: .bottom))
        .sheet(item: $activeSheet) { sheet in
            if sheet == .editTime {
                self.editTimeSheet
            } else if sheet == .restTimer {
                self.restTimerSheet
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in self.refresher.refresh() }
    }
}

#if DEBUG
struct TimerBannerView_Previews: PreviewProvider {
    static var previews: some View {
        if RestTimerStore.shared.restTimerRemainingTime == nil {
            RestTimerStore.shared.restTimerStart = Date()
            RestTimerStore.shared.restTimerDuration = 10
        }
        return TimerBannerView(workout: MockWorkoutData.metricRandom.currentWorkout)
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
