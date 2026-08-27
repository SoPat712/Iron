//
//  GeneralSettingsView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 31.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var activePicker: PreferencePicker?

    private enum PreferencePicker: String, Identifiable {
        case weightUnit
        case defaultRest
        case dumbbellRest
        case barbellRest
        case maxRepetitions

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .weightUnit: return "scalemass.fill"
            case .defaultRest: return "timer"
            case .dumbbellRest: return "dumbbell.fill"
            case .barbellRest: return "figure.strengthtraining.traditional"
            case .maxRepetitions: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        List {
            Section("Units") {
                preferenceRow(
                    title: "Weight Unit",
                    value: settingsStore.weightUnit.title,
                    picker: .weightUnit
                )
            }

            Section("Rest timer defaults") {
                preferenceRow(
                    title: "Default Rest Time",
                    value: restTimeTitle(settingsStore.defaultRestTime),
                    picker: .defaultRest
                )
                preferenceRow(
                    title: "Dumbbell Exercises",
                    value: restTimeTitle(settingsStore.defaultRestTimeDumbbellBased),
                    picker: .dumbbellRest
                )
                preferenceRow(
                    title: "Barbell Exercises",
                    value: restTimeTitle(settingsStore.defaultRestTimeBarbellBased),
                    picker: .barbellRest
                )
            }

            Section {
                timerBehaviorRow
            } header: {
                Text("Timer behavior")
            } footer: {
                Text("Keep the rest timer running even after it has elapsed. The time exceeded is displayed in red.")
            }

            Section {
                preferenceRow(
                    title: "Max Repetitions",
                    value: "\(settingsStore.maxRepetitionsOneRepMax)",
                    picker: .maxRepetitions
                )
            } header: {
                Text("One rep max")
            } footer: {
                Text("Maximum number of repetitions that a set can have for it to be considered in the one rep max (1RM) calculation. Keep in mind that higher values are less accurate.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(IronTheme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironDestinationScreen(title: "Workout Preferences")
        .ironScreen()
        .sheet(item: $activePicker) { picker in
            preferenceSheet(picker)
        }
    }

    private func preferenceRow(
        title: String,
        value: String,
        picker: PreferencePicker
    ) -> some View {
        Button {
            activePicker = picker
        } label: {
            LabeledContent {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label(title, systemImage: picker.systemImage)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Opens a bottom sheet to change this preference")
    }

    @ViewBuilder
    private func preferenceSheet(_ picker: PreferencePicker) -> some View {
        switch picker {
        case .weightUnit:
            PreferenceOptionsSheet(
                title: "Weight unit",
                subtitle: "Choose how Iron displays every load",
                systemImage: "scalemass.fill",
                selection: $settingsStore.weightUnit,
                values: WeightUnit.allCases,
                valueTitle: { $0.title },
                valueDetail: { unit in
                    unit == .metric ? "Kilograms and metric barbell plates" : "Pounds and imperial barbell plates"
                }
            )
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)

        case .defaultRest:
            RestDurationPreferenceSheet(
                title: "Default rest time",
                subtitle: "Used when an exercise has no specific default",
                selection: $settingsStore.defaultRestTime
            )

        case .dumbbellRest:
            RestDurationPreferenceSheet(
                title: "Dumbbell rest time",
                subtitle: "Automatic rest after dumbbell sets",
                selection: $settingsStore.defaultRestTimeDumbbellBased
            )

        case .barbellRest:
            RestDurationPreferenceSheet(
                title: "Barbell rest time",
                subtitle: "Automatic rest after barbell sets",
                selection: $settingsStore.defaultRestTimeBarbellBased
            )

        case .maxRepetitions:
            PreferenceOptionsSheet(
                title: "1RM repetition limit",
                subtitle: "Only sets at or below this count estimate 1RM",
                systemImage: "chart.line.uptrend.xyaxis",
                selection: $settingsStore.maxRepetitionsOneRepMax,
                values: Array(maxRepetitionsOneRepMaxValues),
                valueTitle: { "\($0) reps" },
                valueDetail: { value in
                    value <= 5 ? "More conservative strength estimate" : "Includes higher-repetition sets"
                }
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    private var timerBehaviorRow: some View {
        Toggle(isOn: Binding(
            get: { settingsStore.keepRestTimerRunning },
            set: { newValue in
                settingsStore.keepRestTimerRunning = newValue
                RestTimerStore.shared.notifyKeepRestTimerRunningChanged()
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep rest timer running")
                        .font(.body)
                    Text("Show overtime after the timer ends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(IronTheme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keep rest timer running")
        .accessibilityValue(settingsStore.keepRestTimerRunning ? "On" : "Off")
    }

    private func restTimeTitle(_ time: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: time) ?? "\(Int(time))s"
    }
}

private struct PreferenceOptionsSheet<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var selection: Value
    let values: [Value]
    let valueTitle: (Value) -> String
    let valueDetail: (Value) -> String

    var body: some View {
        IronUtilitySheet(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            onClose: { dismiss() }
        ) {
            List(values, id: \.self) { value in
                Button {
                    selection = value
                    dismiss()
                } label: {
                    optionLabel(value)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .presentationBackground(IronTheme.modalSurface)
    }

    private func optionLabel(_ value: Value) -> some View {
        let isSelected = selection == value

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(valueTitle(value))
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text(valueDetail(value))
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.accent)
            }
        }
        .frame(minHeight: 48)
    }
}

private struct RestDurationPreferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    @Binding var selection: TimeInterval
    @State private var workingDuration: TimeInterval

    private let minimumDuration: TimeInterval = 30
    private let maximumDuration: TimeInterval = 600
    private let durationStep: TimeInterval = 5
    private let quickDurations: [TimeInterval] = [60, 90, 120, 180, 300]

    init(title: String, subtitle: String, selection: Binding<TimeInterval>) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self._workingDuration = State(
            initialValue: min(max(selection.wrappedValue, 30), 600)
        )
    }

    var body: some View {
        IronUtilitySheet(
            title: title,
            subtitle: subtitle,
            systemImage: "timer",
            onClose: { dismiss() }
        ) {
            VStack(spacing: 14) {
                ZStack {
                    radialDial

                    HStack {
                        stepButton(
                            systemImage: "minus",
                            label: "Subtract five seconds",
                            isEnabled: workingDuration > minimumDuration
                        ) {
                            workingDuration = clamped(workingDuration - durationStep)
                        }

                        Spacer()

                        stepButton(
                            systemImage: "plus",
                            label: "Add five seconds",
                            isEnabled: workingDuration < maximumDuration
                        ) {
                            workingDuration = clamped(workingDuration + durationStep)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                HStack(spacing: 6) {
                    ForEach(quickDurations, id: \.self) { duration in
                        Button {
                            workingDuration = duration
                        } label: {
                            Text(timeTitle(duration))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundColor(
                                    workingDuration == duration ? IronTheme.accent : IronTheme.primaryText
                                )
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(workingDuration == duration ? IronTheme.accentSoft : IronTheme.surface)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            workingDuration == duration ? IronTheme.accent.opacity(0.46) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(workingDuration == duration ? .isSelected : [])
                    }
                }

                Button {
                    selection = workingDuration
                    dismiss()
                } label: {
                    Label("Use \(timeTitle(workingDuration))", systemImage: "checkmark")
                }
                .buttonStyle(IronPrimaryButtonStyle())
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 22)
        }
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(IronTheme.modalSurface)
        .sensoryFeedback(.selection, trigger: Int(workingDuration))
    }

    private var radialDial: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = (side - 28) / 2
            let normalizedProgress = progress
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
                    .stroke(IronTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
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
                    Text(timeTitle(workingDuration))
                        .font(.system(size: 42, weight: .bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                    Text("DRAG TO SET")
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
                        workingDuration = dialDuration(at: value.location, in: geometry.size)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest duration")
            .accessibilityValue(timeTitle(workingDuration))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    workingDuration = clamped(workingDuration + durationStep)
                case .decrement:
                    workingDuration = clamped(workingDuration - durationStep)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 220)
    }

    private var progress: CGFloat {
        min(
            max(CGFloat((workingDuration - minimumDuration) / (maximumDuration - minimumDuration)), 0),
            1
        )
    }

    private func stepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isEnabled ? IronTheme.accent : IronTheme.tertiaryText)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(isEnabled ? IronTheme.accentSoft : IronTheme.raisedSurface)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func dialDuration(at location: CGPoint, in size: CGSize) -> TimeInterval {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var angle = atan2(location.y - center.y, location.x - center.x) + (.pi / 2)
        if angle < 0 { angle += 2 * .pi }
        let rawDuration = minimumDuration + (angle / (2 * .pi)) * (maximumDuration - minimumDuration)
        return clamped((rawDuration / durationStep).rounded() * durationStep)
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), maximumDuration)
    }

    private func timeTitle(_ duration: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: duration) ?? "0:00"
    }
}

#if DEBUG
struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
