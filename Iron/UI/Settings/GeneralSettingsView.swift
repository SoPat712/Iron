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

    /// The rest presets Iron offers everywhere a duration is chosen. Anything
    /// finer than 15s is noise for a rest timer.
    private static let restDurations: [TimeInterval] = stride(from: 30.0, through: 600.0, by: 15.0).map { $0 }

    var body: some View {
        Form {
            Section {
                Toggle("Start Timer After Each Set", isOn: $settingsStore.autoStartRestTimer)
                restPicker("Default", selection: $settingsStore.defaultRestTime)
                restPicker("Dumbbell Exercises", selection: $settingsStore.defaultRestTimeDumbbellBased)
                restPicker("Barbell Exercises", selection: $settingsStore.defaultRestTimeBarbellBased)
                Toggle("Count Past Zero", isOn: Binding(
                    get: { settingsStore.keepRestTimerRunning },
                    set: { newValue in
                        settingsStore.keepRestTimerRunning = newValue
                        RestTimerStore.shared.notifyKeepRestTimerRunningChanged()
                    }
                ))
            } header: {
                Text("Rest Timer")
            } footer: {
                Text("Iron picks the equipment-specific rest length when an exercise matches, and falls back to Default. Counting past zero shows how long you have overrun in red.")
            }

            Section {
                Toggle("Log RPE", isOn: $settingsStore.logRPE)
                Toggle("Carry Over Last Values", isOn: $settingsStore.prefillPreviousValues)
                Toggle("Stopwatch for Timed Sets", isOn: $settingsStore.inlineSetTimer)
            } header: {
                Text("Logging")
            } footer: {
                Text("RPE adds a rated-perceived-exertion column to every set. Carrying over last values fills new sets with the weight and reps from your previous session. Timed sets gain a tap-to-run stopwatch instead of a duration picker.")
            }

            Section {
                Toggle("Plate Calculator", isOn: $settingsStore.showPlateCalculator)
                Toggle("Warm-up Calculator", isOn: $settingsStore.showWarmUpCalculator)
            } header: {
                Text("Calculators")
            } footer: {
                Text("Both appear on barbell exercises: the plate calculator works out what to load per side, and the warm-up calculator builds ramp-up sets below your working weight.")
            }

            Section {
                Toggle("Advance Through Supersets", isOn: $settingsStore.supersetAutoScroll)
                Toggle("Keep Screen Awake", isOn: $settingsStore.keepScreenAwakeDuringWorkout)
            } header: {
                Text("During a Workout")
            } footer: {
                Text("Advancing scrolls to the next exercise in a superset as soon as you complete a set. Keeping the screen awake stops iPhone from locking while a workout is running, which uses more battery.")
            }

        }
        .navigationTitle("Workout Preferences")
    }

    private func restPicker(_ title: String, selection: Binding<TimeInterval>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Self.restDurations, id: \.self) { duration in
                Text(restTimerDurationFormatter.string(from: duration) ?? "\(Int(duration))s")
                    .tag(duration)
            }
        }
    }
}

/// Units affect history, charts, and exports, so they belong beside the other
/// app-wide preferences rather than inside the workout options.
struct UnitsSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Weight", selection: $settingsStore.weightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Weight")
            } footer: {
                Text(settingsStore.weightUnit == .metric
                     ? "Kilograms, with metric barbell plates and 2.5 kg increments."
                     : "Pounds, with imperial barbell plates and 5 lb increments.")
            }

            Section {
                Picker("Max Repetitions", selection: $settingsStore.maxRepetitionsOneRepMax) {
                    ForEach(Array(maxRepetitionsOneRepMaxValues), id: \.self) { value in
                        Text("^[\(value) rep](inflect: true)").tag(value)
                    }
                }
            } header: {
                Text("One Rep Max")
            } footer: {
                Text("Sets above this rep count are ignored when estimating your one rep max. Higher limits are less accurate.")
            }
        }
        .navigationTitle("Units")
    }
}

struct SoundsSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Sound Effects", isOn: $settingsStore.workoutSounds)
                Toggle("Haptics", isOn: $settingsStore.workoutHaptics)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Feedback for sets, controls, and rest timers. Sound effects follow your ringer switch and mix with your music.")
            }

            Section {
                Toggle("Personal Record Alerts", isOn: $settingsStore.personalRecordAlerts)
            } footer: {
                Text("Announce a personal record in the log the moment you complete a set that beats your best for that exercise.")
            }

            Section {
                ForEach(IronSoundPlayer.Sound.allCases) { sound in
                    Button {
                        IronSoundPlayer.shared.play(sound, preview: true)
                    } label: {
                        HStack {
                            Text(sound.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "play.circle.fill")
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Play \(sound.title) sound")
                    .disabled(!settingsStore.workoutSounds)
                }
            } header: {
                Text("Preview")
            } footer: {
                Text("Turn on Sound Effects and your ringer to preview.")
            }
        }
        .navigationTitle("Sounds & Haptics")
    }
}

#if DEBUG
struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GeneralSettingsView()
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
