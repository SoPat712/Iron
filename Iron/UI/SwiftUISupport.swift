//
//  SwiftUISupport.swift
//  Iron
//
//  Created by Karim Abou Zeid on 18.09.20.
//  Copyright © 2020 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Cupertino visual system

/// One explicit palette record. Screens consume the semantic aliases in
/// `IronTheme`; palette values only live here so light, dark, and modal
/// surfaces cannot drift into one-off system colors.
struct IronPaletteColors {
    let accent: UIColor
    let accentPressed: UIColor
    let accentContainer: UIColor
    let success: UIColor
    let successContainer: UIColor
    let successControl: UIColor
    let onSuccessContainer: UIColor
    let warning: UIColor
    let danger: UIColor
    let canvas: UIColor
    let modalSurface: UIColor
    let surface: UIColor
    let raisedSurface: UIColor
    let field: UIColor
    let topBar: UIColor
    let outline: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    let onAccent: UIColor
}

/// Iron uses Apple's adaptive semantic colors instead of maintaining separate
/// hard-coded light and dark palettes. Keeping the roles centralized prevents
/// local screens from guessing at contrast or appearance-specific values.
enum IronPalette {
    static let semantic = IronPaletteColors(
        accent: .systemBlue,
        accentPressed: UIColor.systemBlue.withAlphaComponent(0.72),
        accentContainer: UIColor.systemBlue.withAlphaComponent(0.12),
        success: .systemGreen,
        successContainer: UIColor.systemGreen.withAlphaComponent(0.14),
        successControl: UIColor.systemGreen.withAlphaComponent(0.22),
        // Completed controls keep a subtle green fill, but their content uses
        // the adaptive label color so light appearance never produces pale
        // green text on a pale green surface.
        onSuccessContainer: .label,
        warning: .systemOrange,
        danger: .systemRed,
        canvas: .systemGroupedBackground,
        modalSurface: .systemGroupedBackground,
        surface: .secondarySystemGroupedBackground,
        raisedSurface: .tertiarySystemGroupedBackground,
        field: .secondarySystemFill,
        topBar: .systemBackground,
        outline: .separator,
        primaryText: .label,
        secondaryText: .secondaryLabel,
        tertiaryText: .tertiaryLabel,
        onAccent: .white
    )

    static func uiColor(_ role: KeyPath<IronPaletteColors, UIColor>) -> UIColor {
        semantic[keyPath: role]
    }

    static func color(_ role: KeyPath<IronPaletteColors, UIColor>) -> Color {
        Color(uiColor(role))
    }
}

/// Iron follows Apple's platform conventions: semantic colors, SF typography,
/// grouped content surfaces, standard control geometry, and restrained tint.
enum IronTheme {
    static let accent = IronPalette.color(\.accent)
    static let accentPressed = IronPalette.color(\.accentPressed)
    static let accentSoft = IronPalette.color(\.accentContainer)
    static let success = IronPalette.color(\.success)
    static let successContainer = IronPalette.color(\.successContainer)
    static let successControl = IronPalette.color(\.successControl)
    static let onSuccessContainer = IronPalette.color(\.onSuccessContainer)
    static let warning = IronPalette.color(\.warning)
    static let danger = IronPalette.color(\.danger)
    static let background = IronPalette.color(\.canvas)
    static let modalSurface = IronPalette.color(\.modalSurface)
    static let surface = IronPalette.color(\.surface)
    static let raisedSurface = IronPalette.color(\.raisedSurface)
    static let field = IronPalette.color(\.field)
    static let topBar = IronPalette.color(\.topBar)
    static let outline = IronPalette.color(\.outline)
    static let primaryText = IronPalette.color(\.primaryText)
    static let secondaryText = IronPalette.color(\.secondaryText)
    static let tertiaryText = IronPalette.color(\.tertiaryText)
    static let onAccent = IronPalette.color(\.onAccent)

    // Exercise diagrams and user media intentionally keep a fixed canvas so
    // third-party artwork and photo controls retain predictable contrast in
    // both appearances. Keep those fixed colors semantic and centralized.
    static let diagramCanvas = Color(UIColor.white)
    static let mediaBackdrop = Color(UIColor.black)
    static let onMedia = Color(UIColor.white)
    static let mediaControlSurface = Color(UIColor.white.withAlphaComponent(0.16))
    static let mediaBadgeSurface = Color(UIColor.black.withAlphaComponent(0.56))

    static let cornerRadius: CGFloat = 12
    static let compactCornerRadius: CGFloat = 10
    static let controlHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = controlHeight
    static let pillCornerRadius: CGFloat = controlHeight / 2
    static let horizontalPadding: CGFloat = 16
    /// The native five-item tab bar occupies almost the full phone width. The
    /// active workout pill is intentionally four points narrower on each side
    /// and sits close enough to read as a companion surface.
    static let activeWorkoutPillHorizontalPadding: CGFloat = 20
    static let activeWorkoutPillBottomOffset: CGFloat = 66
    /// Bottom breathing room for destination content while the global active-
    /// workout glass pill floats above the tab bar. Full-screen editors also
    /// use this value because the pill intentionally remains available there.
    static let floatingWorkoutBottomClearance: CGFloat = 152
}

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
}

struct IronScreenBackground: View {
    var body: some View {
        IronTheme.background.edgesIgnoringSafeArea(.all)
    }
}

/// Sheets use the platform's adaptive grouped background from edge to edge.
struct IronModalBackground: View {
    var body: some View {
        IronTheme.modalSurface.edgesIgnoringSafeArea(.all)
    }
}

/// An axis-independent separator for overlays. SwiftUI's `Divider` inherits the
/// surrounding stack axis and can unexpectedly become vertical when overlaid on
/// an `HStack`; this always renders as a horizontal one-pixel hairline.
struct IronHairline: View {
    var opacity: Double = 0.55

    var body: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(opacity))
            .frame(height: 1)
    }
}

struct IronCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
            )
    }
}

/// Continuous rows are the default for high-density browsing. Selection uses
/// the system tint without giving every idle row its own floating container.
private struct IronTonalListRowModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.accentSoft)
                )
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.vertical, 4)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    IronHairline(opacity: 0.42)
                        .padding(.leading, IronTheme.horizontalPadding + 71)
                }
        }
    }
}

extension View {
    func ironTonalListRow(isSelected: Bool = false) -> some View {
        modifier(IronTonalListRowModifier(isSelected: isSelected))
    }
}

/// A compact, reusable effort picker for completed and in-progress workouts.
/// The selected score is centered whenever the control appears or changes, so
/// an existing 7/10 rating never opens with its value hidden off-screen.
struct IronEffortCarousel: View {
    @Binding var selection: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemWidth: CGFloat = 52
    private let itemHeight: CGFloat = 48
    private let itemSpacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: itemSpacing) {
                            edgeSpacer(for: geometry.size.width)

                            ForEach(1...10, id: \.self) { value in
                                effortButton(value)
                                    .id(value)
                            }

                            edgeSpacer(for: geometry.size.width)
                        }
                        .padding(.vertical, 3)
                    }
                    .onAppear {
                        centerSelection(using: proxy, animated: false)
                    }
                    .onChange(of: selection) { _, _ in
                        centerSelection(using: proxy, animated: true)
                    }
                }
            }
            .frame(height: itemHeight + 6)

            HStack {
                Label("Easy", systemImage: "leaf.fill")
                Spacer()
                Label("Maximum", systemImage: "flame.fill")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(IronTheme.tertiaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session effort")
    }

    private func edgeSpacer(for availableWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: max((availableWidth - itemWidth) / 2, 0), height: 1)
            .accessibilityHidden(true)
    }

    private func effortButton(_ value: Int) -> some View {
        let isSelected = selection == Double(value)

        return Button {
            selection = Double(value)
        } label: {
            Text("\(value)")
                .font(.system(size: isSelected ? 18 : 16, weight: .bold).monospacedDigit())
                .foregroundColor(isSelected ? IronTheme.accent : IronTheme.primaryText)
                .frame(width: itemWidth, height: itemHeight)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(isSelected ? IronTheme.accentSoft : IronTheme.field)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.18),
                    value: isSelected
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effort \(value) out of 10")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func centerSelection(using proxy: ScrollViewProxy, animated: Bool) {
        guard let value = selection.map({ Int($0.rounded()) }), (1...10).contains(value) else { return }

        DispatchQueue.main.async {
            if animated && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            } else {
                proxy.scrollTo(value, anchor: .center)
            }
        }
    }
}

struct IronSectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                titleText
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                if let detail {
                    detailText(detail)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                titleText
                if let detail {
                    detailText(detail)
                }
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundColor(IronTheme.primaryText)
            .lineLimit(2)
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            .font(.caption.weight(.medium))
            .foregroundColor(IronTheme.secondaryText)
            .lineLimit(2)
    }
}

/// Compatibility navigation bar for destinations that also supply custom
/// trailing content. Simpler destinations use the native navigation bar via
/// `ironDestinationScreen(title:)` below.
struct IronDestinationHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    private let trailingWidth: CGFloat
    private let trailing: Trailing

    init(
        title: String,
        trailingWidth: CGFloat = IronTheme.iconButtonSize,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailingWidth = trailingWidth
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, max(72, trailingWidth + 28))
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                trailing
                    .frame(width: trailingWidth, height: IronTheme.iconButtonSize)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(IronTheme.background)
        .overlay(IronHairline(opacity: 0.30), alignment: .bottom)
    }
}

extension IronDestinationHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title, trailingWidth: IronTheme.iconButtonSize) { EmptyView() }
    }
}

private struct IronDestinationScreenModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .background(IronTheme.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(IronTheme.topBar, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            VStack(spacing: 0) {
                IronDestinationHeader(title: title)
                content
            }
            .background(IronTheme.background)
            .navigationBarHidden(true)
        }
    }
}

extension View {
    /// Applies Iron's controlled pushed-screen bar while leaving the wrapped
    /// screen responsible only for its scrollable content.
    func ironDestinationScreen(title: String) -> some View {
        modifier(IronDestinationScreenModifier(title: title))
    }
}

struct IronMetricTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = IronTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(IronTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
    }
}

struct IronChip: View {
    let title: String
    var icon: String? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(isSelected ? IronTheme.accent : IronTheme.primaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: IronTheme.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(isSelected ? IronTheme.accentSoft : IronTheme.field)
        )
    }
}

struct IronPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(IronTheme.onAccent.opacity(isEnabled ? 1 : 0.68))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(
                        isEnabled
                            ? (configuration.isPressed ? IronTheme.accentPressed : IronTheme.accent)
                            : IronTheme.accent.opacity(0.34)
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

struct IronSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(IronTheme.primaryText.opacity(isEnabled ? 1 : 0.48))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(
                        IronTheme.field.opacity(
                            isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.50
                        )
                    )
            )
    }
}

/// Compact utility actions use the same grouped-control geometry as native
/// sheet controls.
struct IronUtilityPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = IronTheme.primaryText
    var fill: Color = IronTheme.raisedSurface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(tint.opacity(isEnabled ? 1 : 0.46))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(
                        fill.opacity(
                            isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.5
                        )
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

struct IronIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(
                (prominent ? IronTheme.onAccent : IronTheme.primaryText)
                    .opacity(isEnabled ? 1 : 0.46)
            )
            .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
            .background(
                Circle()
                    .fill(
                        prominent
                            ? (isEnabled
                                ? (configuration.isPressed ? IronTheme.accentPressed : IronTheme.accent)
                                : IronTheme.accent.opacity(0.34))
                            : IronTheme.raisedSurface.opacity(
                                isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.50
                            )
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.72 : 1)
    }
}

struct IronCompactPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundColor(
                (prominent ? IronTheme.onAccent : IronTheme.accent)
                    .opacity(isEnabled ? 1 : 0.48)
            )
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        prominent
                            ? (isEnabled
                                ? (configuration.isPressed ? IronTheme.accentPressed : IronTheme.accent)
                                : IronTheme.accent.opacity(0.34))
                            : Color.clear
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.72 : 1)
    }
}

/// Compact controls shown above the system keyboard retain Apple's 44-point
/// minimum target and system-fill treatment.
struct IronKeyboardAccessoryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = IronTheme.primaryText
    var minWidth: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(tint.opacity(isEnabled ? 1 : 0.46))
            .lineLimit(1)
            .fixedSize(horizontal: minWidth > 44, vertical: false)
            .frame(minWidth: minWidth, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        IronTheme.raisedSurface.opacity(
                            isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.5
                        )
                    )
            )
            .opacity(configuration.isPressed && isEnabled ? 0.72 : 1)
    }
}

struct IronChoicePillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(
                (isSelected ? IronTheme.primaryText : IronTheme.secondaryText)
                    .opacity(isEnabled ? 1 : 0.48)
            )
            .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? IronTheme.surface.opacity(configuration.isPressed ? 0.72 : 1)
                            : IronTheme.field.opacity(configuration.isPressed ? 0.68 : 1)
                    )
            )
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
            ZStack {
                IronModalBackground()

                VStack(spacing: 0) {
                    if !subtitle.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.accent)

                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    content
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close \(title)")
                }
            }
        }
        .ironScreen()
        .presentationBackground(IronTheme.modalSurface)
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
            ZStack {
                IronModalBackground()

                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(tint)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(tint.opacity(0.14)))

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340)

                    Spacer(minLength: 0)

                    Button(confirmTitle, role: .destructive, action: onConfirm)
                        .buttonStyle(IronConfirmationButtonStyle(tint: tint))

                    Button(secondaryTitle, action: onCancel)
                        .buttonStyle(IronSecondaryButtonStyle())
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                }
            }
        }
        .ironScreen()
        .presentationBackground(IronTheme.modalSurface)
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
            ZStack {
                IronModalBackground()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            Image(systemName: systemImage)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(tint)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(tint.opacity(0.14)))

                            Text(title)
                                .font(.title3.weight(.bold))
                                .foregroundColor(IronTheme.primaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(IronTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 340)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 14)
                        .padding(.bottom, 12)
                    }

                    IronHairline(opacity: 0.42)

                    Button(actionTitle) { dismiss() }
                        .buttonStyle(IronPrimaryButtonStyle())
                        .padding(.horizontal, IronTheme.horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                }
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
        .presentationBackground(IronTheme.modalSurface)
    }
}

/// A consistent Cupertino date row used anywhere a workout or body entry
/// exposes an editable timestamp.
struct IronDateTimeButton: View {
    let title: String
    let systemImage: String
    let date: Date
    var compactValue = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(IronTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous))

                if compactValue {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundColor(IronTheme.primaryText)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                } else {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    HStack(spacing: 6) {
                        dateValue(date.formatted(date: .abbreviated, time: .omitted))
                        dateValue(date.formatted(date: .omitted, time: .shortened))
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.tertiaryText)
                }
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(date.formatted(date: .long, time: .shortened))")
        .accessibilityHint("Opens the date and time editor")
    }

    private func dateValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundColor(IronTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.field)
            )
    }
}

/// Bottom-modal wrapper around the platform wheel control.
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
            ZStack {
                IronModalBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(spacing: 4) {
                            Text(selection.formatted(date: .complete, time: .omitted))
                                .font(.headline.weight(.bold))
                                .foregroundColor(IronTheme.primaryText)
                                .multilineTextAlignment(.center)
                            Text(selection.formatted(date: .omitted, time: .shortened))
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundColor(IronTheme.accent)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
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
                        .tint(IronTheme.accent)
                        .frame(height: 190)
                        .clipped()
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
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
        .presentationBackground(IronTheme.modalSurface)
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
            VStack(spacing: 12) {
                ZStack {
                    radialDial

                    HStack {
                        stepButton(systemImage: "minus", label: "Decrease duration") {
                            selection = clamped(selection - durationStep)
                        }
                        Spacer()
                        stepButton(systemImage: "plus", label: "Increase duration") {
                            selection = clamped(selection + durationStep)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { duration in
                            Button(action: { selection = duration }) {
                                IronChip(
                                    title: durationTitle(duration),
                                    isSelected: selection == duration
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)
                }

                VStack(spacing: 8) {
                    Button {
                        onApply(selection)
                        if shouldDismiss() { dismiss() }
                    } label: {
                        Label("Use \(durationTitle(selection))", systemImage: "checkmark")
                    }
                    .buttonStyle(IronPrimaryButtonStyle())

                    if let secondaryActionTitle, let onSecondaryAction {
                        Button {
                            onSecondaryAction()
                            if shouldDismiss() { dismiss() }
                        } label: {
                            Label(secondaryActionTitle, systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(IronSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
            }
            .padding(.bottom, 18)
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .presentationBackground(IronTheme.modalSurface)
        .sensoryFeedback(.selection, trigger: Int(selection))
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
                    Text(durationTitle(selection))
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
                        selection = dialDuration(at: value.location, in: geometry.size)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(durationTitle(selection))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selection = clamped(selection + durationStep)
                case .decrement:
                    selection = clamped(selection - durationStep)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 220)
    }

    private var progress: CGFloat {
        min(
            max(CGFloat((selection - minimumDuration) / (maximumDuration - minimumDuration)), 0),
            1
        )
    }

    private var presentationDetents: Set<PresentationDetent> {
        secondaryActionTitle == nil ? [.height(520), .large] : [.height(586), .large]
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
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

    private func durationTitle(_ duration: TimeInterval) -> String {
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

struct IronPopupAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isSelected = false
    var role: ButtonRole? = nil
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.role = role
        self.action = action
    }
}

struct IronPopupMenu<Label: View>: View {
    let title: String?
    let actions: [IronPopupAction]
    let arrowEdge: Edge
    private let label: Label

    init(
        title: String? = nil,
        actions: [IronPopupAction],
        arrowEdge: Edge = .top,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title
        self.actions = actions
        self.arrowEdge = arrowEdge
        self.label = label()
    }

    var body: some View {
        Menu {
            if let title {
                Section(title) {
                    actionButtons
                }
            } else {
                actionButtons
            }
        } label: {
            label
        }
        .menuStyle(.button)
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(actions) { item in
            Button(role: item.role, action: item.action) {
                SwiftUI.Label(
                    item.title,
                    systemImage: item.isSelected ? "checkmark" : item.systemImage
                )
            }
        }
    }
}

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
