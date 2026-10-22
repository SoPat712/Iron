//
//  SwiftUISupport.swift
//  Iron
//
//  Created by Karim Abou Zeid on 18.09.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit
import MuscleMap

// Palette, metric typography, and motion tokens live in Shared/UI/SwiftUI/IronStyle.swift
// so the app and widget extension use the same visual roles.

private struct IronLiquidGlassPillModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint).interactive(),
                in: Capsule(style: .continuous)
            )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(IronTheme.outline.opacity(0.52), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Shared transparent pill chrome for UI that floats above changing content.
    func ironLiquidGlassPill(
        tint: Color = IronTheme.accent.opacity(0.08)
    ) -> some View {
        modifier(IronLiquidGlassPillModifier(tint: tint))
    }

    /// Glass chrome for hero and summary clusters that sit above scrolling
    /// content. Unlike `IronCard` this is a refracting layer, not an opaque
    /// surface, so it reads as depth instead of another stacked panel.
    func ironLiquidGlassSurface(
        cornerRadius: CGFloat = IronTheme.heroCornerRadius,
        tint: Color = IronTheme.accent.opacity(0.06)
    ) -> some View {
        modifier(IronLiquidGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Secondary action chrome. Every button that floats over scrolling content
    /// should use this so a screen never mixes glass and flat bordered fills.
    @ViewBuilder
    func ironGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// The single primary action on a surface.
    @ViewBuilder
    func ironProminentGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

private struct IronLiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(IronTheme.outline.opacity(0.32), lineWidth: 1))
        }
    }
}

private struct IronSetCompletionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isComplete: Bool
    let feedbackEnabled: Bool
    @State private var lastCompletion: Bool
    @State private var fillProgress: CGFloat
    @State private var fillOpacity: Double

    init(isComplete: Bool, feedbackEnabled: Bool) {
        self.isComplete = isComplete
        self.feedbackEnabled = feedbackEnabled
        _lastCompletion = State(initialValue: isComplete)
        _fillProgress = State(initialValue: isComplete ? 1 : 0)
        _fillOpacity = State(initialValue: isComplete ? 0.12 : 0)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.accent.opacity(fillOpacity))
                    .scaleEffect(x: reduceMotion ? 1 : fillProgress, anchor: .leading)
                    .clipShape(RoundedRectangle(
                        cornerRadius: IronTheme.compactCornerRadius, style: .continuous
                    ))
                    .allowsHitTesting(false)
            }
            .task(id: isComplete) {
                // Existing completed rows appear settled, without replaying feedback.
                guard lastCompletion != isComplete else {
                    fillProgress = isComplete ? 1 : 0
                    fillOpacity = isComplete ? 0.12 : 0
                    return
                }
                lastCompletion = isComplete
                withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
                    fillProgress = isComplete ? 1 : 0
                    fillOpacity = isComplete ? (reduceMotion ? 0.12 : 0.24) : 0
                }
                guard isComplete, !reduceMotion else { return }
                do {
                    try await Task.sleep(for: .milliseconds(420))
                } catch {
                    return
                }
                withAnimation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion)) {
                    fillOpacity = 0.12
                }
            }
            .sensoryFeedback(.success, trigger: isComplete) { _, completed in
                completed && feedbackEnabled
            }
    }
}

private struct IronStaggeredEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(IronMotion.preferred(
                    IronMotion.snappy.delay(Double(max(index, 0)) * 0.04),
                    reduceMotion: reduceMotion
                )) {
                    hasAppeared = true
                }
            }
            // Plays once. Resetting on disappear hides List rows that were
            // prefetched off screen and replays the entrance on every scroll.
    }
}

extension View {
    /// Leading accent sweep, faint settled fill, and completion success haptic.
    /// Apply to the row content inside its existing inset; this adds no geometry.
    /// Callers still own check symbols, field states, and the completion label.
    /// Reduce Motion uses a fade and keeps the haptic.
    func ironSetCompletion(isComplete: Bool, feedbackEnabled: Bool = true) -> some View {
        modifier(IronSetCompletionModifier(isComplete: isComplete, feedbackEnabled: feedbackEnabled))
    }

    /// Fades and rises 8 points on appearance, delayed 40 ms per zero-based index.
    /// Reduce Motion uses an immediate short fade without translation or stagger.
    func ironStaggeredEntrance(index: Int) -> some View {
        modifier(IronStaggeredEntranceModifier(index: index))
    }
}

/// Rest countdown ring: pass the fraction remaining (1 = full, 0 = elapsed).
/// Timer state and ticking stay with the caller. Hide from accessibility when
/// the containing pill already announces the remaining time.
struct IronRestRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    var size: CGFloat = 34
    var accessibilityLabel: String = "Rest remaining"

    private var fraction: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle().stroke(IronTheme.tertiaryFill, lineWidth: 4)
            if reduceMotion {
                progressArc.id(fraction).transition(.opacity)
            } else {
                progressArc
            }
        }
        .padding(2)
        .frame(width: size, height: size)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(IronTheme.metricTime, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .opacity(fraction > 0 ? 1 : 0)
    }
}

struct IronConfirmationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = IronTheme.danger

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(IronTheme.onAccent.opacity(isEnabled ? 1 : 0.62))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(
                        isEnabled
                            ? tint.opacity(configuration.isPressed ? 0.76 : 1)
                            : tint.opacity(0.34)
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

/// Compact Cupertino chrome for workout utilities presented from the bottom.
struct IronUtilitySheet<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onClose: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }

                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .ironScreen()
    }
}

/// A bottom confirmation surface for consequential actions. Destructive roles
/// use the platform red and the secondary action remains visually quiet.
struct IronConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = IronTheme.danger
    var cancelTitle: String = "Cancel"
    var secondaryTitle: String = "Keep current data"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 8)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)

                Spacer(minLength: 0)

                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(tint)
                    .frame(maxWidth: .infinity)

                Button(secondaryTitle, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                }
            }
        }
        .ironScreen()
    }
}

/// A compact bottom-modal result for completed operations and recoverable
/// failures using the same platform hierarchy as other sheets.
struct IronStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let headerTitle: String
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let actionTitle: String

    init(
        headerTitle: String = "Status",
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        actionTitle: String = "Done"
    ) {
        self.headerTitle = headerTitle
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Image(systemName: systemImage)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.top, 8)

                        Text(title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 340)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }

                Button(actionTitle) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .ironScreen()
        .presentationDetents([.height(390), .medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// A consistent Cupertino date row used anywhere a workout or body entry
/// exposes an editable timestamp.
struct IronDateTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let range: ClosedRange<Date>
    let onApply: (Date) -> Void

    @State private var selection: Date

    init(
        title: String,
        subtitle: String,
        initialDate: Date,
        range: ClosedRange<Date>,
        onApply: @escaping (Date) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.range = range
        self.onApply = onApply
        _selection = State(initialValue: min(max(initialDate, range.lowerBound), range.upperBound))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(selection.formatted(date: .complete, time: .omitted))
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(selection.formatted(date: .omitted, time: .shortened))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    DatePicker(
                        title,
                        selection: $selection,
                        in: range,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(height: 190)
                    .clipped()
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .ironScreen()
        .presentationDetents([.height(450), .large])
        .presentationDragIndicator(.visible)
    }
}

/// Fitness-style effort graph: ten rising capsules, each keeping its own color
/// with the effort color role. Inactive bars stay neutral; the selected bar is the
/// one you last scrubbed to.
struct EffortRatingGraph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var rating: Int
    var allowsUnrated: Bool = false

    private let levels = 1...10
    private let graphHeight: CGFloat = 108

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
            }

            GeometryReader { proxy in
                let spacing: CGFloat = 5
                let barWidth = max((proxy.size.width - spacing * 9) / 10, 7)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(levels), id: \.self) { level in
                        bar(for: level, width: barWidth, maxHeight: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            select(at: value.location.x, barWidth: barWidth, spacing: spacing)
                        }
                )
            }
            .frame(height: graphHeight)
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement()
        .accessibilityLabel("Session effort")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let minimum = allowsUnrated ? 0 : 1
            switch direction {
            case .increment: rating = min(rating + 1, 10)
            case .decrement: rating = max(rating - 1, minimum)
            default: break
            }
        }
    }

    private var title: String {
        rating == 0 ? "Not Rated" : EffortTier.tier(for: rating).title
    }

    private var subtitle: String {
        rating == 0 ? "Drag to rate this session" : "\(rating) of 10"
    }

    private var titleColor: Color {
        rating == 0 ? Color.secondary : EffortTier.color(for: rating)
    }

    private var accessibilityValue: String {
        rating == 0 ? "Not rated" : "\(rating) of 10, \(EffortTier.tier(for: rating).title)"
    }

    private func bar(for level: Int, width: CGFloat, maxHeight: CGFloat) -> some View {
        let ratio = 0.18 + 0.82 * (Double(level - 1) / 9)
        let isActive = rating > 0 && level <= rating
        let isSelected = level == rating
        let fill: AnyShapeStyle = isActive
            ? AnyShapeStyle(EffortTier.color(for: level).gradient)
            : AnyShapeStyle(Color(.quaternarySystemFill))

        return Capsule(style: .continuous)
            .fill(fill)
            .frame(width: width, height: maxHeight * ratio)
            .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1, anchor: .bottom)
            .shadow(color: isSelected ? EffortTier.color(for: level).opacity(0.45) : .clear, radius: 6, y: 2)
            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: rating)
    }

    private func select(at x: CGFloat, barWidth: CGFloat, spacing: CGFloat) {
        let step = barWidth + spacing
        guard step > 0 else { return }
        let index = Int((x / step).rounded(.down)) + 1
        let clamped = min(max(index, 1), 10)
        guard clamped != rating else { return }
        rating = clamped
    }
}

enum EffortTier {
    case easy, light, moderate, hard, allOut

    static func tier(for rating: Int) -> EffortTier {
        switch rating {
        case ...2: return .easy
        case 3...4: return .light
        case 5...6: return .moderate
        case 7...8: return .hard
        default: return .allOut
        }
    }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .allOut: return "All Out"
        }
    }

    /// Effort uses one semantic role at every rating.
    static func color(for level: Int) -> Color {
        IronTheme.metricEffort
    }

}

/// A reusable Cupertino bottom modal for timed exercise targets and logged
/// efforts. Duration is adjusted with the same direct radial interaction as
/// Iron's rest timer, so time-based sets never fall back to a keyboard-only
/// text field or a platform picker.
struct IronDurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let systemImage: String
    let secondaryActionTitle: String?
    let onSecondaryAction: (() -> Void)?
    let shouldDismiss: () -> Bool
    let onApply: (TimeInterval) -> Void

    @State private var selection: TimeInterval

    private let minimumDuration: TimeInterval
    private let maximumDuration: TimeInterval
    private let durationStep: TimeInterval
    private let presets: [TimeInterval]

    init(
        title: String = "Set duration",
        subtitle: String = "Choose the target time for this set",
        systemImage: String = "stopwatch.fill",
        initialDuration: TimeInterval,
        minimumDuration: TimeInterval = 5,
        maximumDuration: TimeInterval = 3_600,
        durationStep: TimeInterval = 5,
        presets: [TimeInterval] = [30, 45, 60, 90, 120, 180, 300, 600],
        secondaryActionTitle: String? = nil,
        onSecondaryAction: (() -> Void)? = nil,
        shouldDismiss: @escaping () -> Bool = { true },
        onApply: @escaping (TimeInterval) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.minimumDuration = minimumDuration
        self.maximumDuration = max(maximumDuration, minimumDuration)
        self.durationStep = max(durationStep, 1)
        self.presets = presets.filter { $0 >= minimumDuration && $0 <= maximumDuration }
        self.secondaryActionTitle = secondaryActionTitle
        self.onSecondaryAction = onSecondaryAction
        self.shouldDismiss = shouldDismiss
        self.onApply = onApply
        _selection = State(
            initialValue: min(max(initialDuration, minimumDuration), max(maximumDuration, minimumDuration))
        )
    }

    var body: some View {
        IronUtilitySheet(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            onClose: { dismiss() }
        ) {
            VStack(spacing: 14) {
                IronDurationWheel(
                    selection: $selection,
                    minimumDuration: minimumDuration,
                    maximumDuration: maximumDuration,
                    secondsStep: durationStep
                )

                if !presets.isEmpty {
                    Picker("Presets", selection: $selection) {
                        ForEach(presets, id: \.self) { duration in
                            Text(durationTitle(duration)).tag(duration)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, IronTheme.horizontalPadding)
                }

                VStack(spacing: 10) {
                    Button {
                        onApply(selection)
                        if shouldDismiss() { dismiss() }
                    } label: {
                        Text("Use \(durationTitle(selection))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let secondaryActionTitle, let onSecondaryAction {
                        Button {
                            onSecondaryAction()
                            if shouldDismiss() { dismiss() }
                        } label: {
                            Text(secondaryActionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
            }
            .padding(.bottom, 18)
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: Int(selection))
    }

    private var presentationDetents: Set<PresentationDetent> {
        secondaryActionTitle == nil ? [.height(470), .large] : [.height(540), .large]
    }

    private func durationTitle(_ duration: TimeInterval) -> String {
        IronDurationFormat.title(duration)
    }
}

/// Minute and second wheels, the same control watchOS uses for weight and reps.
/// Replaces Iron's former custom radial dial: a drag-around-a-circle gesture has
/// no platform equivalent, no Digital Crown analogue, and poor VoiceOver support.
struct IronDurationWheel: View {
    @Binding var selection: TimeInterval

    let minimumDuration: TimeInterval
    let maximumDuration: TimeInterval
    let secondsStep: TimeInterval

    private var maximumMinutes: Int {
        max(Int(maximumDuration) / 60, 0)
    }

    private var secondsValues: [Int] {
        let step = max(Int(secondsStep), 1)
        guard step < 60 else { return [0] }
        return Array(stride(from: 0, to: 60, by: step))
    }

    private var minuteSelection: Binding<Int> {
        Binding(
            get: { min(Int(selection) / 60, maximumMinutes) },
            set: { selection = clamped(TimeInterval($0 * 60 + Int(selection) % 60)) }
        )
    }

    private var secondSelection: Binding<Int> {
        Binding(
            get: {
                let current = Int(selection) % 60
                return secondsValues.min(by: { abs($0 - current) < abs($1 - current) }) ?? 0
            },
            set: { selection = clamped(TimeInterval((Int(selection) / 60) * 60 + $0)) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel(
                label: "Minutes",
                unit: "min",
                values: Array(0...maximumMinutes),
                selection: minuteSelection
            )

            wheel(
                label: "Seconds",
                unit: "sec",
                values: secondsValues,
                selection: secondSelection
            )
        }
        .frame(height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duration")
        .accessibilityValue(IronDurationFormat.title(selection))
    }

    private func wheel(
        label: String,
        unit: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        HStack(spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)")
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, minimumDuration), max(maximumDuration, minimumDuration))
    }
}

/// One duration string for the logger, rest timer, and Live Activity so a
/// 90-second rest never renders as "1:30" in one place and "90s" in another.
enum IronDurationFormat {
    static func title(_ duration: TimeInterval) -> String {
        let seconds = Int(max(duration, 0).rounded())
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Native pull-down actions

extension View {
    func ironScreen() -> some View {
        self
            .accentColor(IronTheme.accent)
    }

    @ViewBuilder
    func defaultScrollAnchorCompat_trailing() -> some View {
        if #available(iOS 18.0, *) {
            defaultScrollAnchor(.trailing)
        } else {
            self
        }
    }
}

struct TextCaseNil: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 14.0, *) {
            content.textCase(nil)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func textCaseCompat_nil() -> some View {
        if #available(iOS 14.0, *) {
            textCase(nil)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func listStyleCompat_InsetGroupedListStyle() -> some View {
        if #available(iOS 14.0, *) {
            listStyle(InsetGroupedListStyle())
        } else {
            listStyle(GroupedListStyle())
        }
    }
}

extension View {
    @ViewBuilder
    func redacted_compat() -> some View {
        if #available(iOS 14.0, *) {
            redacted(reason: .placeholder)
        }
    }
}

extension View {
    /// Applies a modifier to a view conditionally.
    ///
    /// - Parameters:
    ///   - condition: The condition to determine if the content should be applied.
    ///   - content: The modifier to apply to the view.
    /// - Returns: The modified view.
    @ViewBuilder func modifier<T: View>(
        if condition: @autoclosure () -> Bool,
        then content: (Self) -> T
    ) -> some View {
        if condition() {
            content(self)
        } else {
            self
        }
    }
    
    /// Applies a modifier to a view conditionally.
    ///
    /// - Parameters:
    ///   - condition: The condition to determine the content to be applied.
    ///   - trueContent: The modifier to apply to the view if the condition passes.
    ///   - falseContent: The modifier to apply to the view if the condition fails.
    /// - Returns: The modified view.
    @ViewBuilder func modifier<TrueContent: View, FalseContent: View>(
        if condition: @autoclosure () -> Bool,
        then trueContent: (Self) -> TrueContent,
        else falseContent: (Self) -> FalseContent
    ) -> some View {
        if condition() {
            trueContent(self)
        } else {
            falseContent(self)
        }
    }
}

/// Normalizes catalog muscle names for the detail and live-workout maps.
func ironMapMuscle(_ rawName: String) -> Muscle? {
    switch rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "abs", "abdominals", "core": return .abs
    case "lower abs", "lowerabs": return .lowerAbs
    case "obliques": return .obliques
    case "serratus", "serratus anterior": return .serratus
    case "biceps", "biceps brachii", "brachialis": return .biceps
    case "triceps", "triceps brachii": return .triceps
    case "forearm", "forearms", "forerm", "wrists", "wrist flexors", "wrist extensors", "grip muscles": return .forearm
    case "hands": return .hands
    case "shoulders", "deltoid", "deltoids", "delts": return .deltoids
    case "rear deltoid", "rear deltoids", "reardeltoid": return .rearDeltoid
    case "rotator cuff", "rotatorcuff": return .rotatorCuff
    case "trapezius", "traps", "levator scapulae": return .trapezius
    case "rhomboids": return .rhomboids
    case "neck", "sternocleidomastoid": return .neck
    case "chest", "pectorals", "pectoralis major": return .chest
    case "upper chest", "upperchest": return .upperChest
    case "lats", "latissimus", "latissimus dorsi", "upper back", "upperback", "back": return .upperBack
    case "lower back", "lowerback", "spine", "erector spinae": return .lowerBack
    case "glutes", "glutaeus maximus", "abductors": return .gluteal
    case "hamstrings", "ischiocrural muscles": return .hamstring
    case "quadriceps", "quads": return .quadriceps
    case "adductors", "groin", "inner thighs": return .adductors
    case "hip flexor", "hip flexors", "hipflexors": return .hipFlexors
    case "calves", "gastrocnemius", "soleus": return .calves
    case "shin", "shins", "tibialis", "tibialis anterior": return .tibialis
    case "ankles", "ankle stabilizers": return .ankles
    case "feet": return .feet
    default: return nil
    }
}
