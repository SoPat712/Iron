//
//  RestTimerView.swift
//  Iron
//
//  A compact radial rest timer designed for Iron's bottom utility sheet.
//

import SwiftUI

struct RestTimerView: View {
    @EnvironmentObject private var restTimerStore: RestTimerStore

    @ObservedObject private var refresher = Refresher()
    @State private var selectedDuration: TimeInterval = 90

    private let minimumDuration: TimeInterval = 30
    private let maximumDuration: TimeInterval = 600
    private let durationStep: TimeInterval = 15

    private var roundedRemainingTime: TimeInterval? {
        restTimerStore.restTimerRemainingTime?.rounded(.up)
    }

    private var isOvertime: Bool {
        (roundedRemainingTime ?? 0) < 0
    }

    private var remainingProgress: CGFloat {
        guard let duration = restTimerStore.restTimerDuration,
              let remaining = roundedRemainingTime,
              duration > 0 else { return 0 }
        return CGFloat(min(max(remaining / duration, 0), 1))
    }

    private var quickDurations: [TimeInterval] {
        [60, 90, 120, 180]
    }

    var body: some View {
        Group {
            if roundedRemainingTime != nil {
                runningTimer
            } else {
                timerPicker
            }
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(IronTheme.modalSurface)
        .onAppear {
            guard let recent = restTimerStore.recentRestTimes.first else { return }
            selectedDuration = clamped(recent)
        }
        .sensoryFeedback(.selection, trigger: Int(selectedDuration))
    }

    private var timerPicker: some View {
        VStack(spacing: 14) {
            ZStack {
                radialDial(
                    duration: selectedDuration,
                    progress: pickerProgress,
                    subtitle: "DRAG TO SET",
                    isInteractive: true
                )

                HStack {
                    durationStepButton(systemImage: "minus", label: "Subtract 15 seconds") {
                        selectedDuration = clamped(selectedDuration - durationStep)
                    }
                    .disabled(selectedDuration <= minimumDuration)

                    Spacer()

                    durationStepButton(systemImage: "plus", label: "Add 15 seconds") {
                        selectedDuration = clamped(selectedDuration + durationStep)
                    }
                    .disabled(selectedDuration >= maximumDuration)
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 8) {
                ForEach(quickDurations, id: \.self) { duration in
                    Button(action: { selectedDuration = clamped(duration) }) {
                        Text(timeTitle(duration))
                            .monospacedDigit()
                    }
                    .buttonStyle(IronChoicePillButtonStyle(isSelected: selectedDuration == duration))
                }
            }

            Button(action: { startTimer(duration: selectedDuration) }) {
                Label("Start rest", systemImage: "play.fill")
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
    }

    private var runningTimer: some View {
        VStack(spacing: 16) {
            Label(
                isOvertime ? "Rest over time" : "Rest in progress",
                systemImage: isOvertime ? "exclamationmark.clock.fill" : "bolt.fill"
            )
                .font(.caption.weight(.bold))
                .foregroundColor(isOvertime ? IronTheme.danger : IronTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOvertime ? IronTheme.danger.opacity(0.12) : IronTheme.accentSoft)
                )

            radialDial(
                duration: abs(roundedRemainingTime ?? 0),
                progress: remainingProgress,
                subtitle: isOvertime ? "OVER BY" : "REMAINING",
                titlePrefix: isOvertime ? "+" : "",
                isInteractive: false
            )
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                refresher.refresh()
            }

            HStack(spacing: 10) {
                timerControl(title: "−15 sec", systemImage: "minus") {
                    adjustRunningTimer(by: -15)
                }
                timerControl(title: "+15 sec", systemImage: "plus") {
                    adjustRunningTimer(by: 15)
                }
                timerControl(title: "Skip", systemImage: "forward.end.fill", isDestructive: true) {
                    stopTimer()
                }
            }
        }
    }

    private var pickerProgress: CGFloat {
        CGFloat((selectedDuration - minimumDuration) / (maximumDuration - minimumDuration))
    }

    private func radialDial(
        duration: TimeInterval,
        progress: CGFloat,
        subtitle: String,
        titlePrefix: String = "",
        isInteractive: Bool
    ) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = (side - 28) / 2
            let normalizedProgress = min(max(progress, 0), 1)
            let angle = Angle.degrees(Double(normalizedProgress) * 360)

            ZStack {
                Circle()
                    .fill(IronTheme.surface)

                ForEach(0..<40, id: \.self) { tick in
                    Capsule(style: .continuous)
                        .fill(tick.isMultiple(of: 5) ? IronTheme.secondaryText : IronTheme.outline)
                        .frame(width: 2, height: tick.isMultiple(of: 5) ? 9 : 5)
                        .offset(y: -(side / 2 - 16))
                        .rotationEffect(.degrees(Double(tick) * 9))
                }

                Circle()
                    .stroke(IronTheme.raisedSurface, lineWidth: 12)
                    .padding(14)

                Circle()
                    .trim(from: 0, to: normalizedProgress)
                    .stroke(
                        IronTheme.accent,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(14)
                    .animation(.snappy(duration: 0.18), value: normalizedProgress)

                Circle()
                    .fill(IronTheme.accent)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(IronTheme.onAccent.opacity(0.85), lineWidth: 3))
                    .shadow(color: IronTheme.accent.opacity(0.32), radius: 8)
                    .position(
                        x: side / 2 + CGFloat(sin(angle.radians)) * radius,
                        y: side / 2 - CGFloat(cos(angle.radians)) * radius
                    )

                VStack(spacing: 3) {
                    Text("\(titlePrefix)\(timeTitle(duration))")
                        .font(.system(size: 46, weight: .bold).monospacedDigit())
                        .foregroundColor(
                            (roundedRemainingTime ?? 0) < 0 ? IronTheme.danger : IronTheme.primaryText
                        )
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(IronTheme.secondaryText)
                }
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isInteractive else { return }
                        selectedDuration = dialDuration(at: value.location, in: geometry.size)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest duration")
            .accessibilityValue("\(titlePrefix)\(timeTitle(duration))")
            .accessibilityHint(
                isInteractive
                    ? "Use the increase and decrease actions, or the adjacent buttons."
                    : (isOvertime ? "Amount past the rest target." : "Current remaining rest time.")
            )
            .accessibilityAction(named: "Increase 15 seconds") {
                guard isInteractive else { return }
                selectedDuration = clamped(selectedDuration + durationStep)
            }
            .accessibilityAction(named: "Decrease 15 seconds") {
                guard isInteractive else { return }
                selectedDuration = clamped(selectedDuration - durationStep)
            }
        }
        .frame(height: 222)
    }

    private func durationStepButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                .background(Circle().fill(IronTheme.accentSoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func timerControl(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(
            IronUtilityPillButtonStyle(
                tint: isDestructive ? IronTheme.danger : IronTheme.primaryText,
                fill: isDestructive ? IronTheme.danger.opacity(0.12) : IronTheme.raisedSurface
            )
        )
    }

    private func dialDuration(at location: CGPoint, in size: CGSize) -> TimeInterval {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var angle = atan2(location.y - center.y, location.x - center.x) + (.pi / 2)
        if angle < 0 { angle += 2 * .pi }
        let progress = angle / (2 * .pi)
        let rawDuration = minimumDuration + progress * (maximumDuration - minimumDuration)
        return clamped((rawDuration / durationStep).rounded() * durationStep)
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), maximumDuration)
    }

    private func timeTitle(_ duration: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: duration) ?? "0:00"
    }

    private func startTimer(duration: TimeInterval) {
        restTimerStore.restTimerStart = Date()
        restTimerStore.restTimerDuration = duration
        restTimerStore.recentRestTimes.removeAll { $0 == duration }
        restTimerStore.recentRestTimes.insert(duration, at: 0)
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }

    private func adjustRunningTimer(by interval: TimeInterval) {
        restTimerStore.adjust(by: interval)
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }

    private func stopTimer() {
        restTimerStore.restTimerStart = nil
        restTimerStore.restTimerDuration = nil
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }
}

#if DEBUG
struct RestTimerView_Previews: PreviewProvider {
    static var previews: some View {
        RestTimerView()
            .environmentObject(RestTimerStore.shared)
    }
}
#endif
