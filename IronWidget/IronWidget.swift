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

    private var headline: String {
        guard let days = daysSinceLastWorkout else { return "—" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days"
        }
    }

    private var detail: String {
        guard let workoutInfo = entry.workoutInfo else {
            return "No workouts logged yet."
        }
        let duration = Duration.seconds(workoutInfo.duration)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return "\(duration) · \(workoutInfo.start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Last Workout", systemImage: "figure.strengthtraining.traditional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(headline)
                .font(.ironMetric(.title2))
                .foregroundStyle((daysSinceLastWorkout ?? 0) > 1 ? IronTheme.metricTime : IronTheme.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let info = entry.workoutInfo {
                (Text(Duration.seconds(info.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                    .font(.ironMetric(.caption, weight: .semibold)).foregroundColor(IronTheme.metricTime)
                 + Text(" · " + info.start.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption).foregroundColor(IronTheme.secondaryText))
                    .lineLimit(2)
            } else {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DeepLink.url(for: .startWorkout))
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum WorkoutActivityPalette {
    static let accent = IronTheme.accent
    static let completion = IronTheme.accent
    static let surface = IronTheme.topBar
    static let onSurface = IronTheme.primaryText
    static let secondary = IronTheme.secondaryText
    static let onAccent = IronTheme.onAccent
    static let compactCornerRadius: CGFloat = 12
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityContainer(context: context)
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
                        .font(.ironMetric(.caption, weight: .semibold))
                        .foregroundStyle(IronTheme.metricTime)
                        .multilineTextAlignment(.trailing)
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
        .supplementalActivityFamiliesCompat()
    }
}

private extension ActivityConfiguration {
    /// The Apple Watch Smart Stack renders the `.small` activity family. Older
    /// systems keep the default (`.medium`) presentation only.
    func supplementalActivityFamiliesCompat() -> some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return supplementalActivityFamilies([.small])
        } else {
            return self
        }
    }
}

/// Routes to the Apple Watch Smart Stack layout where the system supports the
/// `.small` activity family, and to the Lock Screen layout everywhere else.
private struct WorkoutLiveActivityContainer: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        if #available(iOS 18.0, watchOS 11.0, *) {
            WorkoutActivityFamilyRouter(context: context)
        } else {
            WorkoutLiveActivityLockScreenView(context: context)
        }
    }
}

@available(iOS 18.0, watchOS 11.0, *)
private struct WorkoutActivityFamilyRouter: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            WorkoutSmartStackView(context: context)
        default:
            WorkoutLiveActivityLockScreenView(context: context)
        }
    }
}

/// Compact Smart Stack layout for Apple Watch: one glanceable line of state,
/// the live value, and rest controls only when they are actionable.
private struct WorkoutSmartStackView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            let set = context.state.visibleSet(at: presentationDate)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: phaseSystemImage(phase))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(phaseTint(phase))

                    Text(set?.exerciseName ?? context.attributes.workoutTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.ironMetric(.caption2, weight: .semibold))
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .foregroundStyle(IronTheme.metricSets)
                }

                if phase == .resting, context.state.isRestPaused {
                    WorkoutPausedRestControls(context: context, compact: true)
                } else if phase == .resting, let end = context.state.restTimerEnd {
                    HStack(spacing: 6) {
                        workoutRestTimerText(until: end)
                            .foregroundStyle(IronTheme.metricTime)
                            .font(.ironMetric(.title3, weight: .semibold))

                        Spacer(minLength: 4)

                        Button(intent: SkipWorkoutRestTimerIntent(
                            workoutID: context.attributes.workoutID
                        )) {
                            Image(systemName: "forward.fill")
                        }
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Skip rest timer")
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(set?.result.isEmpty == false && set?.result != "—" ? set!.result : "Log a set")
                            .font(.ironMetric(.title3, weight: .semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 4)

                        Text(context.attributes.workoutStart, style: .timer)
                            .font(.ironMetric(.caption2, weight: .semibold))
                            .foregroundStyle(IronTheme.metricTime)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)

                        if phase == .currentSet, let set {
                            WorkoutActivityCompleteSetButton(
                                workoutID: context.attributes.workoutID,
                                set: set,
                                size: 30
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .font(.ironMetric(.caption, weight: .semibold))
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .foregroundStyle(IronTheme.metricTime)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                HStack(spacing: 10) {
                    WorkoutActivityExerciseArtwork(
                        set: set,
                        phase: phase,
                        size: 34
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryTitle(phase: phase, set: set))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WorkoutActivityPalette.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .allowsTightening(true)

                        Text(secondaryTitle(phase: phase, set: set))
                            .font(.ironMetric(.caption, weight: .semibold))
                            .foregroundStyle(WorkoutActivityPalette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                    }

                    Spacer(minLength: 4)
                }

                activityProgress(phase: phase, date: presentationDate)

                if phase == .resting, context.state.isRestPaused {
                    WorkoutPausedRestControls(context: context)
                } else if phase == .resting, let end = context.state.restTimerEnd {
                    WorkoutRunningRestControls(
                        workoutID: context.attributes.workoutID,
                        end: end
                    )
                } else {
                    HStack(spacing: 10) {
                        Text(activityResult(set))
                            .font(.ironMetric(.title2, weight: .semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .foregroundStyle(
                                phaseIsCompletion(phase)
                                    ? WorkoutActivityPalette.completion
                                    : WorkoutActivityPalette.onSurface
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                        Spacer(minLength: 8)

                        Text("\(context.state.completedSets)/\(context.state.totalSets) sets")
                            .font(.ironMetric(.caption, weight: .semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .foregroundStyle(IronTheme.metricSets)
                            .lineLimit(1)

                        if phase == .currentSet, let set {
                            WorkoutActivityCompleteSetButton(
                                workoutID: context.attributes.workoutID,
                                set: set,
                                size: 38
                            )
                        } else {
                            Image(systemName: phaseSystemImage(phase))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(
                                    phaseIsCompletion(phase)
                                        ? WorkoutActivityPalette.onAccent
                                        : tint
                                )
                                .frame(width: 38, height: 38)
                                .background(
                                    Circle()
                                        .fill(
                                            phaseIsCompletion(phase)
                                                ? tint
                                                : tint.opacity(0.14)
                                        )
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
                            .fill(IronTheme.metricTime)
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

/// ActivityKit renders a small still from the on-device cache, never a GIF or
/// a remote request. Rest keeps the timer symbol so its controls remain clear.
private struct WorkoutActivityExerciseArtwork: View {
    let set: WorkoutActivityAttributes.SetSnapshot?
    let phase: WorkoutActivityAttributes.Phase
    let size: CGFloat

    var body: some View {
        Group {
            if phase != .resting,
               let fileURL = WorkoutLiveActivityArtwork.fileURL(for: set?.artworkFileName),
               let image = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.17)
                    .frame(width: size, height: size)
                    .background(IronTheme.diagramCanvas, in: Circle())
                    .clipShape(Circle())
            } else {
                Image(systemName: phase == .resting ? "timer" : "figure.strengthtraining.traditional")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(phaseTint(phase))
                    .frame(width: size, height: size)
                    .background(phaseTint(phase).opacity(0.14), in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Keep Skip anchored at the trailing edge while the three rest controls
/// share the remaining space equally on both full-size activity surfaces.
private struct WorkoutRunningRestControls: View {
    let workoutID: String
    let end: Date
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(intent: AdjustWorkoutRestTimerIntent(
                    workoutID: workoutID,
                    seconds: -15
                )) {
                    Text("−15s")
                }
                .buttonStyle(WorkoutActivityControlButtonStyle(fillsWidth: true))
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityLabel("Subtract 15 seconds")

                workoutRestTimerText(until: end)
                    .font(.ironMetric(compact ? .title3 : .title2))
                    .foregroundStyle(IronTheme.metricTime)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Button(intent: AdjustWorkoutRestTimerIntent(
                    workoutID: workoutID,
                    seconds: 15
                )) {
                    Text("+15s")
                }
                .buttonStyle(WorkoutActivityControlButtonStyle(fillsWidth: true))
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityLabel("Add 15 seconds")
            }
            .frame(maxWidth: .infinity)

            Button(intent: SkipWorkoutRestTimerIntent(
                workoutID: workoutID
            )) {
                Text("Skip")
            }
            .buttonStyle(WorkoutActivityControlButtonStyle(isProminent: true))
            .accessibilityLabel("Skip rest timer")
        }
    }
}

private struct WorkoutActivityControlButtonStyle: ButtonStyle {
    var isProminent = false
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ironMetric(.caption, weight: .semibold))
            .foregroundStyle(
                isProminent
                    ? WorkoutActivityPalette.onAccent
                    : WorkoutActivityPalette.onSurface
            )
            .frame(minWidth: 52, maxWidth: fillsWidth ? .infinity : nil, minHeight: 38)
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

private struct WorkoutActivityCompletionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(WorkoutActivityPalette.onAccent)
            .background(
                Circle()
                    .fill(WorkoutActivityPalette.accent)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct WorkoutActivityCompleteSetButton: View {
    let workoutID: String
    let set: WorkoutActivityAttributes.SetSnapshot
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let setID = set.setID {
            Button(intent: CompleteWorkoutSetIntent(
                workoutID: workoutID,
                setID: setID
            )) {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .frame(width: size, height: size)
            }
            .buttonStyle(WorkoutActivityCompletionButtonStyle())
            .accessibilityLabel("Complete set \(set.setNumber)")
        }
    }
}

private struct WorkoutDynamicIslandCenter: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        // The exercise header lives in the full-width bottom region. Leaving
        // center empty prevents the system's centered column from offsetting
        // it relative to the result and controls underneath.
        EmptyView()
    }
}

private struct WorkoutDynamicIslandBottom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            let set = context.state.visibleSet(at: presentationDate)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    WorkoutActivityExerciseArtwork(set: set, phase: phase, size: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(dynamicTitle(phase: phase, set: set))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                phaseIsCompletion(phase)
                                    ? WorkoutActivityPalette.completion
                                    : WorkoutActivityPalette.onSurface
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)

                        Text(dynamicSubtitle(phase: phase, set: set))
                            .font(.ironMetric(.caption2, weight: .semibold))
                            .foregroundStyle(WorkoutActivityPalette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }

                    Spacer(minLength: 4)
                }

                if phase == .resting, context.state.isRestPaused {
                    WorkoutPausedRestControls(context: context)
                } else if phase == .resting,
                   let end = context.state.restTimerEnd,
                   let progress = context.state.restProgress(at: presentationDate) {
                    VStack(spacing: 7) {
                        Capsule(style: .continuous)
                            .fill(WorkoutActivityPalette.secondary.opacity(0.20))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule(style: .continuous)
                                        .fill(IronTheme.metricTime)
                                        .frame(width: proxy.size.width * progress)
                                }
                            }

                        WorkoutRunningRestControls(
                            workoutID: context.attributes.workoutID,
                            end: end,
                            compact: true
                        )
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(dynamicResult(set))
                            .font(.ironMetric(.title3, weight: .semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .foregroundStyle(
                                phaseIsCompletion(phase)
                                    ? WorkoutActivityPalette.completion
                                    : WorkoutActivityPalette.onSurface
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                        Spacer(minLength: 4)
                        Text("\(context.state.completedSets)/\(context.state.totalSets) sets")
                            .font(.ironMetric(.caption2, weight: .semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .foregroundStyle(IronTheme.metricSets)
                            .lineLimit(1)

                        if phase == .currentSet, let set {
                            WorkoutActivityCompleteSetButton(
                                workoutID: context.attributes.workoutID,
                                set: set,
                                size: 34
                            )
                        } else {
                            Image(systemName: phaseIsCompletion(phase) ? "checkmark.circle.fill" : "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(WorkoutActivityPalette.completion)
                        }
                    }
                }
            }
        }
    }

    private func dynamicTitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        if phase == .finished { return "Workout complete" }
        return set?.exerciseName ?? "Workout"
    }

    private func dynamicSubtitle(
        phase: WorkoutActivityAttributes.Phase,
        set: WorkoutActivityAttributes.SetSnapshot?
    ) -> String {
        guard let set else {
            return "\(context.state.completedSets) of \(context.state.totalSets) sets"
        }
        switch phase {
        case .setCompleted:
            return "Set \(set.setNumber) of \(set.setCount) complete"
        case .resting:
            return "Next: set \(set.setNumber) of \(set.setCount) · \(dynamicResult(set))"
        case .currentSet:
            return "Set \(set.setNumber) of \(set.setCount) · \(dynamicResult(set))"
        case .finished:
            return "\(context.state.completedSets) sets logged"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentationDate = workoutPresentationDate(context, timeline.date)
            let phase = context.state.resolvedPhase(at: presentationDate)
            if phase == .resting, context.state.isRestPaused {
                Image(systemName: "pause.fill")
                    .foregroundStyle(IronTheme.metricTime)
                    .accessibilityLabel("Rest timer paused")
            } else if phase == .resting, let end = context.state.restTimerEnd {
                workoutRestTimerText(until: end)
                    .font(.ironMetric(.caption, weight: .bold))
                    .foregroundStyle(IronTheme.metricTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            } else if phaseIsCompletion(phase) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WorkoutActivityPalette.completion)
            } else if let set = context.state.visibleSet(at: presentationDate) {
                Text("\(set.setNumber)/\(set.setCount)")
                    .font(.ironMetric(.caption, weight: .bold))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .foregroundStyle(IronTheme.metricSets)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(WorkoutActivityPalette.completion)
            }
        }
    }
}

private struct WorkoutPausedRestControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Paused")
                    .font(.caption2)
                    .foregroundStyle(WorkoutActivityPalette.secondary)
                Text(remainingText)
                    .font(.ironMetric(.title3, weight: .semibold))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .foregroundStyle(IronTheme.metricTime)
            }
            Spacer(minLength: 4)
            Button(intent: ResumeWorkoutRestTimerIntent(workoutID: context.attributes.workoutID)) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(WorkoutActivityControlButtonStyle(isProminent: true))
            .accessibilityLabel("Resume rest timer")
            if !compact {
                Button(intent: SkipWorkoutRestTimerIntent(workoutID: context.attributes.workoutID)) {
                    Text("Skip")
                }
                .buttonStyle(WorkoutActivityControlButtonStyle())
                .accessibilityLabel("Skip rest timer")
            }
        }
    }

    private var remainingText: String {
        let remaining = context.state.pausedRestRemaining ?? 0
        let seconds = remaining.isFinite ? Int(min(max(remaining.rounded(.up), 0), 86_400)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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
    // The system keeps counting while the intent updates the deadline. Avoid
    // invalidation shimmer and replacement fades on each ±15-second action.
    .contentTransition(.identity)
    .animation(nil, value: end)
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
    phase == .resting ? IronTheme.metricTime : WorkoutActivityPalette.accent
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
