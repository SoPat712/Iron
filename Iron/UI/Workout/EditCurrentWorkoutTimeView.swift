//
//  EditCurrentWorkoutTimeView.swift
//  Iron
//
//  A draft-based Cupertino editor for the active workout clock.
//

import SwiftUI
import WorkoutDataKit

struct EditCurrentWorkoutTimeView: View {
    @ObservedObject private var workout: Workout

    private let onApply: () -> Void

    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var tracksAutomatically: Bool
    @State private var dateEditorTarget: DateEditorTarget?

    private enum DateEditorTarget: String, Identifiable {
        case started
        case ended

        var id: String { rawValue }
    }

    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    init(workout: Workout, onApply: @escaping () -> Void = {}) {
        self.workout = workout
        self.onApply = onApply

        let start = workout.safeStart
        let end = max(workout.safeEnd, start)
        _draftStart = State(initialValue: start)
        _draftEnd = State(initialValue: end)
        _tracksAutomatically = State(initialValue: workout.end == nil)
    }

    private var effectiveEnd: Date {
        tracksAutomatically ? Date() : max(draftEnd, draftStart)
    }

    private var draftDuration: TimeInterval {
        max(effectiveEnd.timeIntervalSince(draftStart), 0)
    }

    private var latestStartDate: Date {
        min(effectiveEnd, Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    durationSummary
                    trackingModeCard
                    dateEditor(
                        title: "Workout started",
                        detail: "Sets and elapsed time are measured from here",
                        systemImage: "play.fill",
                        selection: $draftStart,
                        target: .started
                    )

                    if !tracksAutomatically {
                        dateEditor(
                            title: "Workout ended",
                            detail: "Use a fixed end for a paused or corrected session",
                            systemImage: "stop.fill",
                            selection: $draftEnd,
                            target: .ended
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    resetAction
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }

            IronHairline(opacity: 0.48)

            Button(action: applyDraft) {
                Label("Apply workout time", systemImage: "checkmark")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(IronTheme.modalSurface)
        }
        .background(IronTheme.modalSurface)
        .animation(.easeInOut(duration: 0.2), value: tracksAutomatically)
        .onChange(of: draftStart) { _, newStart in
            if !tracksAutomatically, draftEnd < newStart {
                draftEnd = newStart
            }
        }
        .onChange(of: tracksAutomatically) { _, automatic in
            if !automatic {
                draftEnd = max(Date(), draftStart)
            }
        }
        .sensoryFeedback(.selection, trigger: tracksAutomatically)
        .sheet(item: $dateEditorTarget) { target in
            IronDateTimePickerSheet(
                title: target == .started ? "Workout started" : "Workout ended",
                subtitle: target == .started
                    ? "Choose when this session began."
                    : "Choose a fixed finish time for this session.",
                initialDate: target == .started ? draftStart : draftEnd,
                range: target == .started
                    ? Date.distantPast...latestStartDate
                    : draftStart...Date()
            ) { newDate in
                if target == .started {
                    draftStart = newDate
                } else {
                    draftEnd = newDate
                }
            }
        }
    }

    private var durationSummary: some View {
        IronCard(padding: 15) {
            HStack(spacing: 14) {
                Image(systemName: tracksAutomatically ? "stopwatch" : "clock.badge.checkmark")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text(durationTitle)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                        .contentTransition(.numericText())
                    Text(tracksAutomatically ? "Live workout duration" : "Fixed workout duration")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Text(tracksAutomatically ? "LIVE" : "FIXED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(tracksAutomatically ? IronTheme.success : IronTheme.warning)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill((tracksAutomatically ? IronTheme.success : IronTheme.warning).opacity(0.13))
                    )
            }
        }
    }

    private var trackingModeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            IronSectionTitle(title: "Clock behavior", detail: tracksAutomatically ? "AUTOMATIC" : "MANUAL")

            IronCard(padding: 14) {
                Toggle(isOn: $tracksAutomatically) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(tracksAutomatically ? IronTheme.accent : IronTheme.secondaryText)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                    .fill(tracksAutomatically ? IronTheme.accentSoft : IronTheme.raisedSurface)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Track time automatically")
                                .font(.body.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text(tracksAutomatically ? "The clock keeps running with your workout" : "Choose a fixed end time below")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(IronTheme.accent)
            }
        }
    }

    private func dateEditor(
        title: String,
        detail: String,
        systemImage: String,
        selection: Binding<Date>,
        target: DateEditorTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            IronDateTimeButton(
                title: title,
                systemImage: systemImage,
                date: selection.wrappedValue,
                compactValue: true,
                action: { dateEditorTarget = target }
            )

            Text(detail)
                .font(.caption)
                .foregroundColor(IronTheme.secondaryText)
                .padding(.leading, 45)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .stroke(IronTheme.outline.opacity(0.36), lineWidth: 1)
        )
    }

    private var resetAction: some View {
        Button {
            let now = Date()
            draftStart = now
            if !tracksAutomatically {
                draftEnd = now
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(IronTheme.warning)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(IronTheme.warning.opacity(0.13)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset start to now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("The draft changes only after you apply it")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer()
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.raisedSurface)
            )
        }
        .buttonStyle(.plain)
    }

    private var durationTitle: String {
        durationFormatter.string(from: draftDuration) ?? "00:00"
    }

    private func applyDraft() {
        workout.start = draftStart
        workout.end = tracksAutomatically ? nil : max(draftEnd, draftStart)
        onApply()
    }
}

#if DEBUG
struct EditCurrentWorkoutTimeView_Previews: PreviewProvider {
    static var previews: some View {
        EditCurrentWorkoutTimeView(workout: MockWorkoutData.metricRandom.currentWorkout)
            .preferredColorScheme(.dark)
    }
}
#endif
