//
//  RestTimerView.swift
//  Iron
//
//  A compact, Cupertino rest timer. The sheet is intentionally designed for
//  the medium detent: the dial, common adjustments, and stop action are all
//  available without pulling a modal over the entire workout.
//

import SwiftUI
import UIKit
import AudioToolbox

struct RestTimerView: View {
    @EnvironmentObject private var restTimerStore: RestTimerStore

    @State private var selectedDuration: TimeInterval = 90

    private let minimumDuration: TimeInterval = 30
    private let maximumDuration: TimeInterval = 600
    private let durationStep: TimeInterval = 15
    private let quickDurations: [TimeInterval] = [60, 90, 120, 180]

    private var isRunning: Bool {
        restTimerStore.restTimerRemainingTime != nil
    }

    var body: some View {
        Group {
            if isRunning {
                runningTimer
            } else {
                timerPicker
            }
        }
        .onAppear {
            if let recent = restTimerStore.recentRestTimes.first {
                selectedDuration = clamped(recent)
            }
        }
        .animation(IronMotion.snappy, value: isRunning)
    }

    /// A compact radial duration selector + presets layout that fits the
    /// medium sheet without requiring the user to expand it. This is a
    /// duration dial, not a clock: the user spins the ring to choose a value.
    private var timerPicker: some View {
        VStack(spacing: 10) {
            RestTimerDurationDial(
                selection: $selectedDuration,
                minimumDuration: minimumDuration,
                maximumDuration: maximumDuration,
                secondsStep: durationStep,
                subtitle: "Spin to set rest"
            )
            .frame(width: 214, height: 214)

            VStack(alignment: .leading, spacing: 5) {
                Text("Presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Presets", selection: $selectedDuration) {
                    ForEach(quickDurations, id: \.self) { duration in
                        Text(timeTitle(duration))
                            .monospacedDigit()
                            .tag(duration)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button {
                startTimer(duration: selectedDuration)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 12)
    }

    private var runningTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = restTimerStore.restTimerRemainingTime ?? 0

            VStack(spacing: 10) {
                RestTimerDurationDial(
                    selection: activeDurationBinding(fallback: remaining),
                    minimumDuration: 0,
                    maximumDuration: maximumDuration,
                    secondsStep: durationStep,
                    subtitle: restTimerStore.isPaused ? "Paused · spin to adjust" : "Spin to adjust remaining"
                )
                .frame(width: 172, height: 172)

                HStack(spacing: 8) {
                    timerActionButton("−15") {
                        adjustRunningTimer(by: -15)
                    }
                    timerActionButton(
                        restTimerStore.isPaused ? "Resume" : "Pause",
                        systemImage: restTimerStore.isPaused ? "play.fill" : "pause.fill",
                        prominent: true
                    ) {
                        restTimerStore.isPaused ? restTimerStore.resume() : restTimerStore.pause()
                        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
                    }
                    timerActionButton("+15") {
                        adjustRunningTimer(by: 15)
                    }
                    timerActionButton("Stop", systemImage: "xmark", destructive: true) {
                        stopTimer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func timerActionButton(
        _ title: String,
        systemImage: String? = nil,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 38)
        }

        Group {
            if prominent {
                button.ironProminentGlassButtonStyle()
            } else {
                button.ironGlassButtonStyle()
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(destructive ? .red : .accentColor)
        .accessibilityLabel(title == "Stop" ? "Stop rest timer" : title)
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), maximumDuration)
    }

    private func timeTitle(_ duration: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: duration) ?? "0:00"
    }

    private func startTimer(duration: TimeInterval) {
        restTimerStore.start(duration: duration)
        restTimerStore.recentRestTimes.removeAll { $0 == duration }
        restTimerStore.recentRestTimes.insert(duration, at: 0)
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }

    private func adjustRunningTimer(by interval: TimeInterval) {
        restTimerStore.adjust(by: interval)
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }

    private func activeDurationBinding(fallback: TimeInterval) -> Binding<TimeInterval> {
        Binding(
            get: {
                let current = restTimerStore.restTimerRemainingTime ?? fallback
                return min(max(current.rounded(.up), 0), maximumDuration)
            },
            set: { duration in
                selectedDuration = duration
                restTimerStore.setRemaining(duration)
                WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
            }
        )
    }

    private func stopTimer() {
        restTimerStore.cancel()
        WorkoutLiveActivityManager.shared.refreshCurrentWorkoutRestTimer()
    }
}

/// A 270-degree rotary duration scrubber. It deliberately looks like a physical
/// control rather than a progress ring or clock face: a neutral rail, tactile
/// notches, and one restrained position marker communicate rotation.
private struct RestTimerDurationDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: TimeInterval

    let minimumDuration: TimeInterval
    let maximumDuration: TimeInterval
    let secondsStep: TimeInterval
    let subtitle: String

    @State private var isDragging = false
    @State private var draftSelection: TimeInterval?
    @State private var lastFeedbackNotch: Int?

    private let startRotation: Double = 135
    private let startDialAngle: CGFloat = 225
    private let endDialAngle: CGFloat = 495

    private var displayedSelection: TimeInterval {
        clamped(draftSelection ?? selection)
    }

    private var progress: CGFloat {
        let range = max(maximumDuration - minimumDuration, 1)
        return CGFloat(min(max((displayedSelection - minimumDuration) / range, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.405
            let markerCount = 31

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 5)

                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        Color.secondary.opacity(0.14),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startRotation))

                ForEach(0..<markerCount, id: \.self) { index in
                    let markerProgress = Double(index) / Double(markerCount - 1)
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(index.isMultiple(of: 5) ? 0.46 : 0.25))
                        .frame(
                            width: index.isMultiple(of: 5) ? 2.5 : 1.5,
                            height: index.isMultiple(of: 5) ? 9 : 6
                        )
                        .offset(y: -radius)
                        .rotationEffect(.degrees(-135 + (markerProgress * 270)))
                }

                Circle()
                    .fill(IronTheme.accent)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white.opacity(0.88), lineWidth: 1.5))
                    .shadow(color: IronTheme.accent.opacity(0.30), radius: 3, y: 1)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(-135 + (Double(progress) * 270)))
                    .scaleEffect(isDragging ? 1.10 : 1)
                    .animation(
                        isDragging || reduceMotion ? nil : IronMotion.snappy,
                        value: progress
                    )
                    .animation(reduceMotion ? nil : IronMotion.snappy, value: isDragging)

                VStack(spacing: 3) {
                    Text(timeTitle(displayedSelection))
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("15-sec steps")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            draftSelection = displayedSelection
                            lastFeedbackNotch = notch(for: displayedSelection)
                        }
                        updateDraft(at: value.location, center: center, radius: radius)
                    }
                    .onEnded { _ in
                        if let draftSelection {
                            selection = draftSelection
                        }
                        isDragging = false
                        draftSelection = nil
                        lastFeedbackNotch = nil
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest duration dial")
            .accessibilityValue(timeTitle(displayedSelection))
            .accessibilityHint("Rotate around the arc to change the rest duration")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selection = clamped(selection + secondsStep)
                case .decrement:
                    selection = clamped(selection - secondsStep)
                @unknown default:
                    break
                }
            }
            .onChange(of: selection) { _, _ in
                guard !isDragging else { return }
                draftSelection = nil
            }
        }
    }

    private func notch(for duration: TimeInterval) -> Int {
        Int((duration / max(secondsStep, 1)).rounded())
    }

    private func updateDraft(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = center.y - location.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= radius * 0.48 else { return }

        var angle = atan2(dx, dy) * 180 / .pi
        if angle < 0 { angle += 360 }
        if angle > 135, angle < 225 {
            angle = angle <= 180 ? endDialAngle : startDialAngle
        } else if angle < startDialAngle {
            angle += 360
        }

        let dialProgress = min(max((angle - startDialAngle) / (endDialAngle - startDialAngle), 0), 1)
        let range = max(maximumDuration - minimumDuration, 1)
        let raw = minimumDuration + (TimeInterval(dialProgress) * range)
        let proposed = clamped((raw / secondsStep).rounded() * secondsStep)
        guard proposed != draftSelection else { return }

        draftSelection = proposed
        let proposedNotch = notch(for: proposed)
        guard proposedNotch != lastFeedbackNotch else { return }
        lastFeedbackNotch = proposedNotch

        if SettingsStore.shared.workoutHaptics {
            let feedback = UISelectionFeedbackGenerator()
            feedback.prepare()
            feedback.selectionChanged()
        }
        if SettingsStore.shared.workoutSounds {
            AudioServicesPlaySystemSound(1104)
        }
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), maximumDuration)
    }

    private func timeTitle(_ duration: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: duration) ?? "0:00"
    }
}

#if DEBUG
struct RestTimerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RestTimerView()
                .navigationTitle("Rest Timer")
                .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(RestTimerStore.shared)
    }
}
#endif
