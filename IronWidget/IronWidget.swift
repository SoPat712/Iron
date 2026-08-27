//
//  IronWidget.swift
//  IronWidget
//
//  Created by Karim Abou Zeid on 12.10.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import WidgetKit
import SwiftUI
import WorkoutDataKit
import CoreData
import ActivityKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), workoutInfo: WorkoutDataStorage.shared.lastWorkoutInfo)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        completion(Entry(date: Date(), workoutInfo: WorkoutDataStorage.shared.lastWorkoutInfo))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let date = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let startOfTomorrow = Calendar.current.startOfDay(for: tomorrow)
        
        completion(Timeline(entries: [Entry(date: date, workoutInfo: WorkoutDataStorage.shared.lastWorkoutInfo)], policy: .after(startOfTomorrow)))
    }
}

private extension WorkoutDataStorage {
    var lastWorkoutInfo: WorkoutInfo? {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [.init(keyPath: \Workout.start, ascending: false)]
        request.propertiesToFetch = ["\(#keyPath(Workout.start))", "\(#keyPath(Workout.end))"]
        request.fetchLimit = 1
        do {
            let workouts = try persistentContainer.viewContext.fetch(request)
            assert(workouts.count <= 1) // the request should only fetch the max
            guard let start = workouts.first?.start, let end = workouts.first?.end else { return nil }
            return WorkoutInfo(start: start, end: end)
        } catch {
            fatalError("Could not execute fetch request for last workout date.")
        }
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let workoutInfo: WorkoutInfo?
}

struct WorkoutInfo {
    let start: Date
    let end: Date
    
    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct LastWorkoutWidgetEntryView : View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.calendar) var calendar
    
    var entry: Provider.Entry
    
    private var daysSinceLastWorkout: Int? {
        guard let workoutInfo = entry.workoutInfo else { return nil }
        return calendar.calendarDays(from: workoutInfo.start, to: entry.date)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            VStack(alignment: .leading) {
                Spacer()
                
                Text("Activity")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Last Workout")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.8))
                        
                        if let days = daysSinceLastWorkout {
                            Text(String(days))
                                .font(.system(.title3, design: .rounded))
                                .foregroundColor(.white)
                                +
                                Text(" ")
                                +
                                Text(days == 1 ? "day" : "days")
                                .font(.system(.body, design: .rounded))
                        } else {
                            Text("-")
                                .font(.system(.title3, design: .rounded))
                        }
                    }
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(8)
                    
                    Spacer()
                }
                .background(ContainerRelativeShape().fill(Color.accentColor))
            }
            .padding()
        }
    }
}

private extension Calendar {
    func calendarDays(from: Date, to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: to).day!
    }
}

struct LastWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lastWorkout.rawValue, provider: Provider()) { entry in
            LastWorkoutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Last Workout")
        .description("The number of days since the last workout.")
        .supportedFamilies([.systemSmall])
    }
}

private enum WorkoutActivityPalette {
    static let accent = Color.accentColor
    static let success = Color.green
    static let surface = Color(.systemBackground)
    static let onSurface = Color.primary
    static let secondary = Color.secondary
    static let onSuccess = Color.white
    static let compactCornerRadius: CGFloat = 12
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(WorkoutActivityPalette.surface)
                .activitySystemActionForegroundColor(WorkoutActivityPalette.onSurface)
                .widgetURL(DeepLink.url(for: .startWorkout))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutDynamicIslandExpandedLeading(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.workoutStart, style: .timer)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WorkoutActivityPalette.secondary)
                }

                DynamicIslandExpandedRegion(.center) {
                    WorkoutDynamicIslandCenter(context: context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutDynamicIslandBottom(context: context)
                }
            } compactLeading: {
                WorkoutDynamicIslandCompactLeading(context: context)
            } compactTrailing: {
                WorkoutDynamicIslandCompactTrailing(context: context)
            } minimal: {
                WorkoutDynamicIslandMinimal(context: context)
            }
            .keylineTint(WorkoutActivityPalette.accent)
            .widgetURL(DeepLink.url(for: .startWorkout))
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            let set = context.state.visibleSet(at: presentationDate)
            let tint = phaseTint(phase)

            // ActivityKit already provides the rounded system surface. Iron contributes
            // hierarchy and color, while avoiding a second card or custom chrome.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 20, height: 20)

                    Text(context.attributes.workoutTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkoutActivityPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)

                    Spacer(minLength: 8)

                    Text(context.attributes.workoutStart, style: .timer)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WorkoutActivityPalette.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                HStack(spacing: 10) {
                    workoutGlyph(phase: phase, tint: tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryTitle(phase: phase, set: set))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WorkoutActivityPalette.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .allowsTightening(true)

                        Text(secondaryTitle(phase: phase, set: set))
                            .font(.caption)
                            .foregroundStyle(WorkoutActivityPalette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                    }

                    Spacer(minLength: 4)
                }

                activityProgress(phase: phase, date: presentationDate)

                if phase == .resting, let end = context.state.restTimerEnd {
                    restControls(until: end)
                } else {
                    HStack(spacing: 10) {
                        Text(activityResult(set))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                phaseIsCompletion(phase)
                                    ? WorkoutActivityPalette.success
                                    : WorkoutActivityPalette.onSurface
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                        Spacer(minLength: 8)

                        Text("\(context.state.completedSets)/\(context.state.totalSets) sets")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(WorkoutActivityPalette.secondary)
                            .lineLimit(1)

                        Image(systemName: phaseSystemImage(phase))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                phaseIsCompletion(phase)
                                    ? WorkoutActivityPalette.onSuccess
                                    : tint
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: WorkoutActivityPalette.compactCornerRadius,
                                    style: .continuous
                                )
                                .fill(
                                    phaseIsCompletion(phase)
                                        ? tint
                                        : tint.opacity(0.14)
                                )
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func workoutGlyph(
        phase: WorkoutActivityAttributes.Phase,
        tint: Color
    ) -> some View {
        Image(systemName: phase == .resting ? "timer" : "figure.strengthtraining.traditional")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(
                    cornerRadius: WorkoutActivityPalette.compactCornerRadius,
                    style: .continuous
                )
                    .fill(tint.opacity(0.14))
            )
    }

    private func primaryTitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        switch phase {
        case .setCompleted: return set?.exerciseName ?? "Set complete"
        case .resting: return set?.exerciseName ?? "Rest"
        case .finished: return "Workout complete"
        case .currentSet: return set?.exerciseName ?? "Workout"
        }
    }

    private func secondaryTitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        guard let set else {
            return "\(context.state.completedSets) of \(context.state.totalSets) sets"
        }
        switch phase {
        case .setCompleted:
            return "Set \(set.setNumber) of \(set.setCount) complete · \(activityResult(set))"
        case .resting:
            return "Next: set \(set.setNumber) of \(set.setCount) · \(activityResult(set))"
        case .currentSet:
            return "Set \(set.setNumber) of \(set.setCount) · \(activityResult(set))"
        case .finished:
            return "\(context.state.completedSets) sets logged"
        }
    }

    @ViewBuilder
    private func activityProgress(
        phase: WorkoutActivityAttributes.Phase,
        date: Date
    ) -> some View {
        if phase == .resting, let progress = context.state.restProgress(at: date) {
            Capsule(style: .continuous)
                .fill(WorkoutActivityPalette.secondary.opacity(0.20))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule(style: .continuous)
                            .fill(WorkoutActivityPalette.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .accessibilityLabel("Rest progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
        } else {
            let progress = context.state.totalSets > 0
                ? Double(context.state.completedSets) / Double(context.state.totalSets)
                : 0
            Capsule(style: .continuous)
                .fill(WorkoutActivityPalette.secondary.opacity(0.20))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule(style: .continuous)
                            .fill(phaseTint(phase))
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
        }
    }

    private func restControls(until end: Date) -> some View {
        HStack(spacing: 8) {
            Button(intent: AdjustWorkoutRestTimerIntent(
                workoutID: context.attributes.workoutID,
                seconds: -15
            )) {
                Text("−15s")
            }
            .buttonStyle(WorkoutActivityControlButtonStyle())
            .accessibilityLabel("Subtract 15 seconds")

            workoutRestTimerText(until: end)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(WorkoutActivityPalette.onSurface)
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .invalidatableContent()

            Button(intent: AdjustWorkoutRestTimerIntent(
                workoutID: context.attributes.workoutID,
                seconds: 15
            )) {
                Text("+15s")
            }
            .buttonStyle(WorkoutActivityControlButtonStyle())
            .accessibilityLabel("Add 15 seconds")

            Button(intent: SkipWorkoutRestTimerIntent(
                workoutID: context.attributes.workoutID
            )) {
                Text("Skip")
            }
            .buttonStyle(WorkoutActivityControlButtonStyle(isProminent: true))
            .accessibilityLabel("Skip rest timer")
        }
    }

    private func phaseSystemImage(_ phase: WorkoutActivityAttributes.Phase) -> String {
        switch phase {
        case .currentSet: return "checkmark"
        case .setCompleted: return "checkmark"
        case .resting: return "forward.fill"
        case .finished: return "checkmark.seal.fill"
        }
    }

    private func activityResult(_ set: WorkoutActivityAttributes.SetSnapshot?) -> String {
        guard let result = set?.result, result != "—" else {
            return "Enter weight & reps"
        }
        return result
    }
}

private struct WorkoutActivityControlButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(
                isProminent
                    ? WorkoutActivityPalette.onSuccess
                    : WorkoutActivityPalette.onSurface
            )
            .frame(minWidth: 52, minHeight: 38)
            .padding(.horizontal, isProminent ? 4 : 0)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isProminent
                            ? WorkoutActivityPalette.accent
                            : WorkoutActivityPalette.secondary.opacity(0.18)
                    )
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct WorkoutDynamicIslandCenter: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            let set = context.state.visibleSet(at: presentationDate)
            VStack(spacing: 2) {
                Text(primaryTitle(phase: phase, set: set))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        phaseIsCompletion(phase)
                            ? WorkoutActivityPalette.success
                            : WorkoutActivityPalette.onSurface
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                Text(secondaryTitle(phase: phase, set: set))
                    .font(.caption2)
                    .foregroundStyle(WorkoutActivityPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
            }
        }
    }

    private func primaryTitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        switch phase {
        case .setCompleted: return set?.exerciseName ?? "Set complete"
        case .resting: return set?.exerciseName ?? "Rest"
        case .finished: return "Workout complete"
        case .currentSet: return set?.exerciseName ?? "Workout"
        }
    }

    private func secondaryTitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        guard let set else {
            return "\(context.state.completedSets) of \(context.state.totalSets) sets"
        }
        switch phase {
        case .setCompleted:
            return "Set \(set.setNumber)/\(set.setCount) complete · \(set.result)"
        case .resting:
            return "Next: set \(set.setNumber)/\(set.setCount) · \(set.result)"
        case .currentSet:
            return "Set \(set.setNumber)/\(set.setCount) · \(set.result)"
        case .finished:
            return "\(context.state.completedSets) sets logged"
        }
    }
}

private struct WorkoutDynamicIslandBottom: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            let set = context.state.visibleSet(at: presentationDate)
            Group {
                if phase == .resting,
                   let end = context.state.restTimerEnd,
                   let progress = context.state.restProgress(at: presentationDate) {
                    VStack(spacing: 7) {
                        Capsule(style: .continuous)
                            .fill(WorkoutActivityPalette.secondary.opacity(0.20))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule(style: .continuous)
                                        .fill(WorkoutActivityPalette.accent)
                                        .frame(width: proxy.size.width * progress)
                                }
                            }

                        HStack(spacing: 7) {
                            Button(intent: AdjustWorkoutRestTimerIntent(
                                workoutID: context.attributes.workoutID,
                                seconds: -15
                            )) {
                                Text("−15s")
                            }
                            .buttonStyle(WorkoutActivityControlButtonStyle())

                            workoutRestTimerText(until: end)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(WorkoutActivityPalette.onSurface)
                                .contentTransition(.numericText(countsDown: true))
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.66)
                                .invalidatableContent()

                            Button(intent: AdjustWorkoutRestTimerIntent(
                                workoutID: context.attributes.workoutID,
                                seconds: 15
                            )) {
                                Text("+15s")
                            }
                            .buttonStyle(WorkoutActivityControlButtonStyle())

                            Button(intent: SkipWorkoutRestTimerIntent(
                                workoutID: context.attributes.workoutID
                            )) {
                                Text("Skip")
                            }
                            .buttonStyle(WorkoutActivityControlButtonStyle(isProminent: true))
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                    Image(systemName: phaseIsCompletion(phase) ? "checkmark.circle.fill" : "dumbbell.fill")
                        .foregroundStyle(
                            phaseIsCompletion(phase)
                                ? WorkoutActivityPalette.success
                                : WorkoutActivityPalette.accent
                        )
                    Text(dynamicResult(set))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            phaseIsCompletion(phase)
                                ? WorkoutActivityPalette.success
                                : WorkoutActivityPalette.onSurface
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                    Spacer(minLength: 4)
                    Text("\(context.state.completedSets)/\(context.state.totalSets) sets")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(WorkoutActivityPalette.secondary)
                        .lineLimit(1)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func dynamicResult(_ set: WorkoutActivityAttributes.SetSnapshot?) -> String {
        guard let result = set?.result, result != "—" else {
            return "Enter weight & reps"
        }
        return result
    }
}

private struct WorkoutDynamicIslandExpandedLeading: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let phase = context.state.resolvedPhase(
                at: workoutPresentationDate(context, timeline.date)
            )
            HStack(spacing: 6) {
                Image(systemName: phaseSystemImage(phase))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(phaseTint(phase))
                Text(phaseTitle(phase))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkoutActivityPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func phaseTitle(_ phase: WorkoutActivityAttributes.Phase) -> String {
        switch phase {
        case .currentSet: return "Iron"
        case .setCompleted: return "Done"
        case .resting: return "Rest"
        case .finished: return "Done"
        }
    }
}

private struct WorkoutDynamicIslandCompactLeading: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let phase = context.state.resolvedPhase(
                at: workoutPresentationDate(context, timeline.date)
            )
            Image(systemName: compactSystemImage(phase))
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    phaseTint(phase)
                )
        }
    }

    private func compactSystemImage(_ phase: WorkoutActivityAttributes.Phase) -> String {
        switch phase {
        case .currentSet: return "dumbbell.fill"
        case .setCompleted: return "checkmark"
        case .resting: return "timer"
        case .finished: return "checkmark.seal.fill"
        }
    }
}

private struct WorkoutDynamicIslandCompactTrailing: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            if phase == .resting, let end = context.state.restTimerEnd {
                workoutRestTimerText(until: end)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(WorkoutActivityPalette.accent)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            } else if phaseIsCompletion(phase) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutActivityPalette.success)
            } else if let set = context.state.visibleSet(at: presentationDate) {
                Text("\(set.setNumber)/\(set.setCount)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(WorkoutActivityPalette.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(WorkoutActivityPalette.success)
            }
        }
    }
}

private struct WorkoutDynamicIslandMinimal: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let phase = context.state.resolvedPhase(
                at: workoutPresentationDate(context, timeline.date)
            )
            Image(systemName: phaseSystemImage(phase))
                .font(.caption.weight(.bold))
                .foregroundStyle(phaseTint(phase))
        }
    }
}

/// `TimelineView` animates system timer text, but Live Activities don't receive widget
/// timeline entries. Referencing `isStale` ensures ActivityKit re-evaluates the phase when
/// the app-provided stale date reaches a confirmation or rest boundary.
private func workoutPresentationDate(
    _ context: ActivityViewContext<WorkoutActivityAttributes>,
    _ timelineDate: Date
) -> Date {
    context.isStale ? Date.now : timelineDate
}

@ViewBuilder
private func workoutRestTimerText(until end: Date) -> some View {
    // Keep the current date inside the interval even when a 10-minute preset is
    // extended from the app or watch. SwiftUI otherwise waits for the lower
    // bound and briefly renders placeholder seconds in the Live Activity.
    let start = end.addingTimeInterval(-24 * 60 * 60)
    Text(
        timerInterval: start...end,
        countsDown: true,
        showsHours: false
    )
}

private func phaseSystemImage(_ phase: WorkoutActivityAttributes.Phase) -> String {
    switch phase {
    case .currentSet: return "dumbbell.fill"
    case .setCompleted: return "checkmark"
    case .resting: return "timer"
    case .finished: return "checkmark.seal.fill"
    }
}

private func phaseTint(_ phase: WorkoutActivityAttributes.Phase) -> Color {
    phaseIsCompletion(phase)
        ? WorkoutActivityPalette.success
        : WorkoutActivityPalette.accent
}

private func phaseIsCompletion(_ phase: WorkoutActivityAttributes.Phase) -> Bool {
    phase == .setCompleted || phase == .finished
}

@main
struct IronWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastWorkoutWidget()
        WorkoutLiveActivityWidget()
    }
}

struct IronWidget_Previews: PreviewProvider {
    static let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
    static let end = Calendar.current.date(byAdding: .minute, value: 72, to: start)!
    
    static var previews: some View {
        Group {
            LastWorkoutWidgetEntryView(entry: Entry(date: Date(), workoutInfo: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            LastWorkoutWidgetEntryView(entry: Entry(date: Date(), workoutInfo: WorkoutInfo(start: start, end: end)))
                .previewContext(WidgetPreviewContext(family: .systemSmall))

            LastWorkoutWidgetEntryView(entry: Entry(date: Date(), workoutInfo: WorkoutInfo(start: start, end: end)))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .dark)
        }
    }
}
