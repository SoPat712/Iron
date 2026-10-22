import SwiftUI

/// Scrubs locally; callers persist and synchronize only after a committed choice.
struct RestLengthRuler: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: TimeInterval
    var range: ClosedRange<TimeInterval> = 30...300
    var step: TimeInterval = 15
    let onCommit: (TimeInterval) -> Void

    @State private var scrubbedValue: TimeInterval?
    @State private var stepFeedback = 0
    @State private var rulerWidth: CGFloat = 1
    private let presets: [TimeInterval] = [60, 90, 120, 150, 180]
    private let labels: [TimeInterval] = [30, 60, 120, 180, 240, 300]

    private var displayedValue: TimeInterval { scrubbedValue ?? value }
    private var ticks: [TimeInterval] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: max(step, 1)))
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rest length")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(IronTheme.secondaryText)
                    Spacer(minLength: 8)
                    Text(timeTitle(displayedValue))
                        .font(.ironMetric(.title3))
                        .foregroundStyle(IronTheme.metricTime)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ForEach(ticks, id: \.self) { tick in
                            let height: CGFloat = tick.truncatingRemainder(dividingBy: 60) == 0 ? 26 : 14
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(tick <= displayedValue ? IronTheme.metricTime : IronTheme.tertiaryFill)
                                .frame(width: 2, height: height)
                                .position(x: xPosition(tick, width: proxy.size.width), y: 32 - height / 2)
                        }
                        Capsule()
                            .fill(IronTheme.metricTime)
                            .frame(width: 4, height: 32)
                            .position(x: xPosition(displayedValue, width: proxy.size.width), y: 16)

                        ForEach(labels.filter { range.contains($0) }, id: \.self) { label in
                            Text(timeTitle(label))
                                .font(.ironMetric(.caption2, weight: .semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundStyle(IronTheme.secondaryText)
                                .fixedSize()
                                .position(x: xPosition(label, width: proxy.size.width), y: 46)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onAppear { rulerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in rulerWidth = width }
                }
                .frame(height: 54)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                scrub(at: value.location.x)
                if let scrubbedValue { commit(scrubbedValue) }
            })

            HStack(spacing: 4) {
                ForEach(presets.filter { range.contains($0) }, id: \.self) { preset in
                    Button {
                        scrub(to: preset)
                        commit(preset)
                    } label: {
                        Text(timeTitle(preset))
                            .font(.ironMetric(.footnote, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(displayedValue == preset ? IronTheme.topBar : IronTheme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(displayedValue == preset ? IronTheme.metricTime : IronTheme.tertiaryFill, in: Capsule())
                            .frame(minHeight: IronTheme.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .ironHorizontalScrub(includingTaps: false) { location in
            scrub(at: location.x)
        } onEnded: {
            if let scrubbedValue { commit(scrubbedValue) }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(IronTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: displayedValue)
        .sensoryFeedback(.selection, trigger: stepFeedback)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest length")
        .accessibilityValue(spokenDuration)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: scrub(to: displayedValue + step)
            case .decrement: scrub(to: displayedValue - step)
            default: return
            }
            if let scrubbedValue { commit(scrubbedValue) }
        }
    }

    private func xPosition(_ duration: TimeInterval, width: CGFloat) -> CGFloat {
        let fraction = min(max((duration - range.lowerBound) / max(range.upperBound - range.lowerBound, 1), 0), 1)
        return 14 + fraction * max(width - 28, 0)
    }

    private func scrub(at x: CGFloat) {
        let fraction = min(max((x - 14) / max(rulerWidth - 28, 1), 0), 1)
        scrub(to: range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func scrub(to proposed: TimeInterval) {
        let snapped = range.lowerBound + ((proposed - range.lowerBound) / max(step, 1)).rounded() * max(step, 1)
        let next = min(max(snapped, range.lowerBound), range.upperBound)
        if next != displayedValue {
            stepFeedback += 1
            IronSoundPlayer.shared.play(.tick)
        }
        scrubbedValue = next
    }

    private func commit(_ duration: TimeInterval) {
        value = duration
        onCommit(duration)
        scrubbedValue = nil
    }

    private func timeTitle(_ duration: TimeInterval) -> String {
        restTimerDurationFormatter.string(from: max(0, duration)) ?? "0:00"
    }

    private var spokenDuration: String {
        let seconds = max(0, Int(displayedValue.rounded()))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(remainder) \(remainder == 1 ? "second" : "seconds")"
    }
}
