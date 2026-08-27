//
//  SettingsView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 11.07.19.
//  Rebuilt as Iron's private profile and device hub.
//

import SwiftUI
import MessageUI
import CoreData
import WorkoutDataKit

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject private var bodyMetricsStore = BodyMetricsStore.shared

    @State private var showMeasurements = false
    private struct ActionAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    @State private var actionAlert: ActionAlert?

    private enum FeedbackPresentation: String, Identifiable {
        case composer
        case options

        var id: String { rawValue }
    }
    @State private var feedbackPresentation: FeedbackPresentation?

    var body: some View {
        NavigationStack {
            settingsRoot
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showMeasurements) {
                BodyMeasurementsView(store: bodyMetricsStore)
                    .environmentObject(settingsStore)
                    .ironScreen()
            }
            .sheet(item: $actionAlert) { alert in
                IronStatusSheet(
                    headerTitle: "Iron",
                    title: alert.title,
                    message: alert.message,
                    systemImage: "info.circle.fill",
                    tint: IronTheme.accent
                )
            }
            .sheet(item: $feedbackPresentation) { presentation in
                switch presentation {
                case .composer:
                    FeedbackMailComposer(
                        recipients: ["iron@ka.codes"],
                        subject: "Iron feedback"
                    ) { error in
                        feedbackPresentation = nil
                        guard let error else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            actionAlert = ActionAlert(
                                title: "Could Not Send Feedback",
                                message: error.localizedDescription
                            )
                        }
                    }

                case .options:
                    FeedbackOptionsSheet(emailAddress: "iron@ka.codes")
                }
            }
        }
    }

    private var settingsRoot: some View {
        List {
            Section {
                NavigationLink(destination:
                    BodyMeasurementsDashboardView(store: bodyMetricsStore)
                        .environmentObject(settingsStore)
                ) {
                    settingsRow(
                        "Body measurements",
                        detail: bodyMetricsStore.entries.isEmpty ? "Not set up" : latestDateText,
                        icon: "figure.arms.open"
                    )
                }
                settingsLink(
                    "Appearance",
                    detail: settingsStore.appearance.title,
                    icon: "circle.lefthalf.filled",
                    destination: AppearanceSettingsView()
                )
            }

            Section {
                settingsLink("Workout preferences", icon: "slider.horizontal.3", destination: GeneralSettingsView())
                if HealthSettingsView.isSupported {
                    settingsLink("Apple Health", icon: "heart.fill", tint: IronTheme.danger, destination: HealthSettingsView())
                }
                if WatchSettingsView.isSupported {
                    settingsLink("Apple Watch", icon: "applewatch", destination: WatchSettingsView())
                }
            } header: {
                Text("Training")
            }

            Section("Your Data") {
                settingsLink("Backup & export", icon: "externaldrive.fill", destination: BackupAndExportView())
            }

            Section("Support") {
                Button(action: sendFeedback) {
                    settingsRow("Send feedback", icon: "paperplane.fill")
                }
                .buttonStyle(.plain)

                Button(action: openReview) {
                    settingsRow("Rate Iron", icon: "star.fill", tint: IronTheme.warning)
                }
                .buttonStyle(.plain)

                settingsLink(
                    "Licenses & attributions",
                    icon: "doc.text.magnifyingglass",
                    destination: LicensesAttributionsView()
                )
                settingsLink("About Iron", icon: "info.circle.fill", destination: AboutView())
            }

            #if DEBUG
            Section("Development") {
                settingsLink("Developer settings", icon: "hammer.fill", destination: DeveloperSettings())
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(IronTheme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironScreen()
    }

    private var profileCard: some View {
        VStack(spacing: 12) {
            IronCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(IronTheme.accentSoft)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(IronTheme.accent)
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your profile")
                                .font(.headline)
                                .foregroundColor(IronTheme.primaryText)
                            Text(bodyMetricsStore.entries.isEmpty ? "Start tracking body measurements" : "Last updated \(latestDateText)")
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(16)

                    IronHairline(opacity: 0.42)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 0) {
                            profileMetricRow(kind: .bodyWeight, icon: "scalemass.fill")
                            IronHairline(opacity: 0.36).padding(.leading, 46)
                            profileMetricRow(kind: .bodyFat, icon: "percent")
                            IronHairline(opacity: 0.36).padding(.leading, 46)
                            profileMetricRow(kind: .height, icon: "ruler.fill")
                        }
                    } else {
                        HStack(spacing: 0) {
                            profileMetricColumn(kind: .bodyWeight, icon: "scalemass.fill")
                            profileMetricDivider
                            profileMetricColumn(kind: .bodyFat, icon: "percent")
                            profileMetricDivider
                            profileMetricColumn(kind: .height, icon: "ruler.fill")
                        }
                    }
                }
            }

            Button(action: { showMeasurements = true }) {
                Label("Log body measurements", systemImage: "plus.circle.fill")
            }
            .buttonStyle(IronPrimaryButtonStyle())
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private var profileDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Personal data", detail: "PRIVATE")

            VStack(spacing: 0) {
                NavigationLink(destination:
                    BodyMeasurementsDashboardView(store: bodyMetricsStore)
                        .environmentObject(settingsStore)
                ) {
                    profileDestinationRow(
                        title: "Measures",
                        subtitle: "Weight, photos, and circumferences",
                        icon: "figure.arms.open"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func profileDestinationRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                        .fill(IronTheme.accentSoft)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(IronTheme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func profileMetricPresentation(kind: BodyMeasurementKind) -> (value: String, detail: String) {
        let canonical = bodyMetricsStore.latestValue(for: kind)
        if let canonical = canonical {
            let value = kind.displayValue(from: canonical, weightUnit: settingsStore.weightUnit)
            return (
                String(format: value >= 100 ? "%.0f" : "%.1f", value),
                kind.unitLabel(weightUnit: settingsStore.weightUnit)
            )
        }
        return ("—", "Not logged")
    }

    private func profileMetricColumn(kind: BodyMeasurementKind, icon: String) -> some View {
        let presentation = profileMetricPresentation(kind: kind)
        let tint = kind == .bodyFat ? IronTheme.warning : IronTheme.accent

        return VStack(alignment: .leading, spacing: 4) {
            Label(kind.title, systemImage: icon)
                .font(.caption)
                .foregroundColor(tint)
                .lineLimit(1)
            Text(presentation.value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(presentation.detail)
                .font(.caption2)
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
    }

    private func profileMetricRow(kind: BodyMeasurementKind, icon: String) -> some View {
        let presentation = profileMetricPresentation(kind: kind)
        let tint = kind == .bodyFat ? IronTheme.warning : IronTheme.accent

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 30)
            Text(kind.title)
                .font(.body)
                .foregroundColor(IronTheme.primaryText)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(presentation.value)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }

    private var profileMetricDivider: some View {
        Rectangle()
            .fill(IronTheme.outline.opacity(0.5))
            .frame(width: 1, height: 52)
    }

    private var latestDateText: String {
        guard let date = bodyMetricsStore.latest?.date else { return "today" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        detail: String? = nil,
        icon: String,
        tint: Color = IronTheme.accent,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            settingsRow(title, detail: detail, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(
        _ title: String,
        detail: String? = nil,
        icon: String,
        tint: Color = IronTheme.accent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }

    private var privacySummaryCard: some View {
        IronCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(IronTheme.success)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(IronTheme.success.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Private by design")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("No social feed, followers, or public profile. Your training data stays on your devices and in backups you create.")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func openReview() {
        guard let url = URL(string: "https://itunes.apple.com/app/id1479893244?action=write-review") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                actionAlert = ActionAlert(
                    title: "Could Not Open the App Store",
                    message: "You can rate Iron from its App Store page when the store is available."
                )
            }
        }
    }

    private func sendFeedback() {
        feedbackPresentation = MFMailComposeViewController.canSendMail() ? .composer : .options
    }
}

private struct FeedbackMailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let onFinish: (Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Error?) -> Void

        init(onFinish: @escaping (Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(error)
        }
    }
}

private struct FeedbackOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let emailAddress: String
    @State private var copied = false
    @State private var mailLaunchFailed = false

    var body: some View {
        IronUtilitySheet(
            title: "Send feedback",
            subtitle: "Choose an email app or copy the address",
            systemImage: "paperplane.fill",
            onClose: { dismiss() }
        ) {
            VStack(spacing: 12) {
                Text("Apple Mail isn't configured on this device. Open another email app or copy our support address.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Button {
                    openMailApp()
                } label: {
                    Label("Open Default Mail App", systemImage: "envelope.fill")
                }
                .buttonStyle(IronPrimaryButtonStyle())

                if mailLaunchFailed {
                    Label(
                        "No email app could open this message. Copy the address below instead.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundColor(IronTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                Button {
                    UIPasteboard.general.string = emailAddress
                    copied = true
                } label: {
                    Label(copied ? "Address Copied" : "Copy \(emailAddress)", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(IronSecondaryButtonStyle())
            }
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(IronTheme.modalSurface)
        .sensoryFeedback(.success, trigger: copied)
    }

    private func openMailApp() {
        guard let mailURL else {
            mailLaunchFailed = true
            return
        }

        UIApplication.shared.open(mailURL, options: [:]) { opened in
            DispatchQueue.main.async {
                if opened {
                    dismiss()
                } else {
                    mailLaunchFailed = true
                }
            }
        }
    }

    private var mailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [URLQueryItem(name: "subject", value: "Iron feedback")]
        return components.url
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        List {
            Section {
                appearanceOverviewRow
            }

            Section {
                ForEach(IronAppearance.allCases) { appearance in
                    appearanceRow(appearance)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your iPhone’s Display & Brightness setting. Light and Dark keep Iron in that appearance until you change it here.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(IronTheme.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironDestinationScreen(title: "Appearance")
        .ironScreen()
        .animation(.easeInOut(duration: 0.2), value: settingsStore.appearance)
    }

    private var appearanceOverviewRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(IronTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose how Iron looks")
                        .font(.headline)
                        .foregroundColor(IronTheme.primaryText)
                    Text("Adaptive Apple system colors and controls that feel at home on iPhone and Apple Watch.")
                        .font(.subheadline)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            IronHairline(opacity: 0.42)

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIVE PREVIEW")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(IronTheme.secondaryText)
                    Text(settingsStore.appearance.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

                previewMetric(value: "225", label: "LB")
                previewMetric(value: "8", label: "REPS")

                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundColor(IronTheme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.accent)
                    )
            }
        }
        .padding(.vertical, 6)
    }

    private func previewMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundColor(IronTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
    }

    private func appearanceRow(_ appearance: IronAppearance) -> some View {
        let isSelected = settingsStore.appearance == appearance

        return Button {
            settingsStore.appearance = appearance
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: appearance.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSelected ? .white : IronTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? IronTheme.accent : IronTheme.raisedSurface)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(appearance.title)
                        .font(.body)
                        .foregroundColor(IronTheme.primaryText)
                    Text(appearance.subtitle)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(isSelected ? IronTheme.accent : IronTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LicensesAttributionsView: View {
    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    introCard

                    IronSectionTitle(title: "Exercise content", detail: "SOURCES & TERMS")
                        .padding(.horizontal, IronTheme.horizontalPadding)

                    attributionCard(
                        icon: "figure.strengthtraining.traditional",
                        title: "Exercise catalogue",
                        badge: "MIT",
                        message: "Exercise names, metadata, and English instructions are generated from Hasan Emir Yıldırım’s exercises dataset supplied through the openGym reference material.",
                        links: [
                            AttributionLink(title: "Dataset source", url: URL(string: "https://github.com/hasaneyldrm/exercises-dataset")!)
                        ]
                    )

                    attributionCard(
                        icon: "photo.on.rectangle.angled",
                        title: "Exercise images & animations",
                        badge: "CACHED",
                        message: "Iron downloads ExerciseDB’s Gym Visual GIFs once, stores them on this device, and does not delete them. Later launches fill any missing files over Wi-Fi so the library works offline. The upstream notice requests the following attribution: \(Exercise.mediaAttribution). The media is not covered by the catalogue’s MIT license.",
                        links: [
                            AttributionLink(title: "Gym Visual", url: URL(string: "https://gymvisual.com/")!),
                            AttributionLink(title: "ExerciseDB", url: URL(string: "https://exercisedb.dev/")!)
                        ]
                    )

                    attributionCard(
                        icon: "figure.arms.open",
                        title: "Muscle maps",
                        badge: "MIT",
                        message: "Front and back muscle highlighting uses MuscleMap 1.6.4 by Melih Colpan.",
                        links: [
                            AttributionLink(title: "MuscleMap source", url: URL(string: "https://github.com/melihcolpan/MuscleMap")!)
                        ]
                    )

                    Text("Full third-party license text is included with Iron’s source distribution in THIRD_PARTY_NOTICES.md.")
                        .font(.caption)
                        .foregroundColor(IronTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, IronTheme.horizontalPadding)
                }
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .ironDestinationScreen(title: "Licenses & Attributions")
        .ironScreen()
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 48, height: 48)
                .background(Circle().fill(IronTheme.accentSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text("Built with credited sources")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Attribution lives here instead of being repeated over every exercise image.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func attributionCard(
        icon: String,
        title: String,
        badge: String,
        message: String,
        links: [AttributionLink]
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                            .fill(IronTheme.accentSoft)
                    )

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)

                Spacer(minLength: 8)

                Text(badge)
                    .font(.caption2.weight(.bold))
                    .tracking(0.55)
                    .foregroundColor(IronTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(IronTheme.accentSoft))
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                if index > 0 {
                    IronHairline(opacity: 0.38)
                }
                Link(destination: link.url) {
                    HStack {
                        Text(link.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(IronTheme.accent)
                    .frame(minHeight: IronTheme.controlHeight)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private struct AttributionLink {
        let title: String
        let url: URL
    }
}

struct WorkoutCalendarView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @FetchRequest(fetchRequest: WorkoutCalendarView.fetchRequest) private var workouts: FetchedResults<Workout>

    @State private var visibleMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var showingMonthYearPicker = false

    private static var fetchRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return request
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var weekdays: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let firstIndex = max(min(calendar.firstWeekday - 1, symbols.count - 1), 0)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthWorkouts: [Workout] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: visibleMonth) else { return [] }
        return workouts.filter { workout in
            guard let start = workout.start else { return false }
            return interval.contains(start) && (workout.hasCompletedSets ?? false)
        }
    }

    private var completedWorkouts: [Workout] {
        workouts.filter { ($0.hasCompletedSets ?? false) && $0.start != nil }
    }

    private var selectableYears: ClosedRange<Int> {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let workoutYears = completedWorkouts.compactMap { workout in
            workout.start.map { calendar.component(.year, from: $0) }
        }
        let lowerBound = min(workoutYears.min() ?? currentYear, currentYear - 5) - 2
        let upperBound = max(workoutYears.max() ?? currentYear, currentYear + 2) + 2
        return lowerBound...upperBound
    }

    private var trainingStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = Date()

        for weekOffset in 0..<520 {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: cursor) else { break }
            let trained = completedWorkouts.contains { workout in
                guard let date = workout.start else { return false }
                return interval.contains(date)
            }

            if trained {
                streak += 1
            } else if weekOffset > 0 || !interval.contains(Date()) {
                break
            }

            guard let previousWeek = calendar.date(
                byAdding: .weekOfYear,
                value: -1,
                to: interval.start
            ) else { break }
            cursor = previousWeek
        }

        return streak
    }

    private var restDayCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let lastWorkoutDate = completedWorkouts
            .compactMap(\.start)
            .map({ calendar.startOfDay(for: $0) })
            .filter({ $0 <= today })
            .max() else { return 0 }

        return max(calendar.dateComponents([.day], from: lastWorkoutDate, to: today).day ?? 0, 0)
    }

    private var calendarCells: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: first)
        }
    }

    var body: some View {
        ZStack {
            IronScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        monthButton(direction: -1, icon: "chevron.left")
                        Spacer()
                        Button(action: { showingMonthYearPicker = true }) {
                            HStack(spacing: 9) {
                                VStack(spacing: 2) {
                                    Text(monthTitle)
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(IronTheme.primaryText)
                                    Text("\(monthWorkouts.count) workout\(monthWorkouts.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                            .frame(minHeight: IronTheme.controlHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose month and year, currently \(monthTitle)")
                        Spacer()
                        monthButton(direction: 1, icon: "chevron.right")
                    }

                    calendarSummary

                    VStack(spacing: 10) {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                                Text(weekday.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(IronTheme.tertiaryText)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 7) {
                            ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, date in
                                calendarDay(date)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(Divider(), alignment: .top)
                    .overlay(Divider(), alignment: .bottom)

                    IronSectionTitle(title: "This month", detail: "\(monthWorkouts.count) SESSIONS")
                    if monthWorkouts.isEmpty {
                        IronCard {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(IronTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(IronTheme.accentSoft))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("No completed workouts")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(IronTheme.primaryText)
                                    Text("Finished sessions in \(monthTitle) will appear here.")
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(monthWorkouts) { workout in
                                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                    CalendarWorkoutCard(workout: workout, showsDate: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(IronTheme.horizontalPadding)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .ironDestinationScreen(title: "Calendar")
        .sheet(isPresented: $showingMonthYearPicker) {
            CalendarMonthYearPickerSheet(
                initialMonth: visibleMonth,
                yearRange: selectableYears
            ) { month in
                withAnimation(.easeInOut(duration: 0.22)) {
                    visibleMonth = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
                }
            }
            .presentationDetents([.height(430), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(IronTheme.modalSurface)
        }
    }

    private var calendarSummary: some View {
        HStack(spacing: 12) {
            Label("\(trainingStreak)-week streak", systemImage: "flame.fill")
                .foregroundColor(IronTheme.warning)
            Spacer(minLength: 8)
            Label(
                "\(restDayCount) \(restDayCount == 1 ? "rest day" : "rest days")",
                systemImage: "moon.fill"
            )
            .foregroundColor(IronTheme.accent)
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, 12)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    private func monthButton(direction: Int, icon: String) -> some View {
        Button(action: {
            guard let month = Calendar.current.date(byAdding: .month, value: direction, to: visibleMonth) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { visibleMonth = month }
        }) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Previous month" : "Next month")
    }

    @ViewBuilder private func calendarDay(_ date: Date?) -> some View {
        if let date {
            let dayWorkouts = completedWorkouts(on: date)
            if dayWorkouts.isEmpty {
                calendarDayContent(date, workoutCount: 0)
            } else {
                NavigationLink(destination: calendarDestination(date: date, workouts: dayWorkouts)) {
                    calendarDayContent(date, workoutCount: dayWorkouts.count)
                }
                .buttonStyle(.plain)
                .accessibilityHint(dayWorkouts.count == 1 ? "Opens this workout" : "Opens workouts from this day")
            }
        } else {
            Color.clear.frame(minHeight: 44)
        }
    }

    private func completedWorkouts(on date: Date) -> [Workout] {
        workouts.filter { workout in
            guard let start = workout.start, workout.hasCompletedSets ?? false else { return false }
            return Calendar.current.isDate(start, inSameDayAs: date)
        }
    }

    @ViewBuilder
    private func calendarDestination(date: Date, workouts: [Workout]) -> some View {
        if workouts.count == 1, let workout = workouts.first {
            WorkoutDetailView(workout: workout)
        } else {
            WorkoutCalendarDayView(date: date, workouts: workouts)
        }
    }

    private func calendarDayContent(_ date: Date, workoutCount: Int) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return ZStack {
            if workoutCount > 0 {
                Circle()
                    .fill(IronTheme.accent)
            } else if isToday {
                Circle()
                    .stroke(IronTheme.danger, lineWidth: 1.5)
            }

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(workoutCount > 0 || isToday ? .semibold : .regular).monospacedDigit())

            if workoutCount > 1 {
                Text("\(workoutCount)")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundColor(IronTheme.onAccent)
                    .offset(y: 13)
            }
        }
        .foregroundColor(
            workoutCount > 0
                ? IronTheme.onAccent
                : (isToday ? IronTheme.danger : IronTheme.primaryText)
        )
        .frame(width: 38, height: 38)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(date.formatted(date: .long, time: .omitted)), \(workoutCount) workout\(workoutCount == 1 ? "" : "s")"
        )
    }
}

private struct CalendarMonthYearPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    @State private var month: Int
    @State private var year: Int

    let yearRange: ClosedRange<Int>
    let onApply: (Date) -> Void

    init(
        initialMonth: Date,
        yearRange: ClosedRange<Int>,
        onApply: @escaping (Date) -> Void
    ) {
        let components = Calendar.current.dateComponents([.month, .year], from: initialMonth)
        _month = State(initialValue: components.month ?? 1)
        _year = State(initialValue: components.year ?? Calendar.current.component(.year, from: Date()))
        self.yearRange = yearRange
        self.onApply = onApply
    }

    private var monthSymbols: [String] {
        calendar.monthSymbols
    }

    var body: some View {
        IronUtilitySheet(
            title: "Choose month",
            subtitle: "Spin month and year vertically, then open that training period.",
            systemImage: "calendar",
            onClose: { dismiss() }
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    wheelColumn(title: "Month") {
                        Picker("Month", selection: $month) {
                            ForEach(Array(monthSymbols.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(index + 1)
                            }
                        }
                    }

                    Rectangle()
                        .fill(IronTheme.outline.opacity(0.46))
                        .frame(width: 1, height: 146)

                    wheelColumn(title: "Year") {
                        Picker("Year", selection: $year) {
                            ForEach(Array(yearRange), id: \.self) { value in
                                Text(String(value)).tag(value)
                            }
                        }
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .background(
                    RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                        .fill(IronTheme.surface)
                )
                .padding(.horizontal, IronTheme.horizontalPadding)

                HStack(spacing: 10) {
                    Button("Today") {
                        let components = calendar.dateComponents([.month, .year], from: Date())
                        month = components.month ?? month
                        year = components.year ?? year
                    }
                    .buttonStyle(IronSecondaryButtonStyle())

                    Button("Show Month") {
                        var components = DateComponents()
                        components.calendar = calendar
                        components.year = year
                        components.month = month
                        components.day = 1
                        guard let selectedDate = calendar.date(from: components) else { return }
                        onApply(selectedDate)
                        dismiss()
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
            }
        }
        .ironScreen()
    }

    private func wheelColumn<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundColor(IronTheme.secondaryText)
                .padding(.top, 10)

            content()
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                .clipped()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkoutCalendarDayView: View {
    let date: Date
    let workouts: [Workout]

    var body: some View {
        ZStack {
            IronScreenBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    daySummaryCard

                    ForEach(workouts) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            CalendarWorkoutCard(workout: workout, showsDate: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .ironDestinationScreen(title: date.formatted(date: .abbreviated, time: .omitted))
    }

    private var daySummaryCard: some View {
        let setCount = workouts.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) }
        let duration = workouts.reduce(0) { $0 + ($1.duration ?? 0) }

        return IronCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(IronTheme.accentSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(workouts.count) training \(workouts.count == 1 ? "session" : "sessions")")
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("\(setCount) completed sets · \(Workout.durationFormatter.string(from: duration) ?? "0m")")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer()
            }
        }
    }
}

private struct CalendarWorkoutCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore

    @ObservedObject var workout: Workout
    let showsDate: Bool

    private var durationText: String {
        guard let duration = workout.duration else { return "—" }
        return Workout.durationFormatter.string(from: duration) ?? "—"
    }

    private var volumeText: String {
        WeightUnit.format(
            weight: workout.totalCompletedWeight ?? 0,
            from: .metric,
            to: settingsStore.weightUnit
        )
    }

    private var timestampText: String {
        guard let start = workout.start else { return "Unknown date" }
        if showsDate {
            return start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundColor(IronTheme.onAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(IronTheme.success))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.displayTitle(in: exerciseStore.exercises))
                        .font(.headline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(1)
                    Text(timestampText)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(IronTheme.tertiaryText)
            }

            HStack(spacing: 8) {
                metricChip(icon: "clock", value: durationText)
                metricChip(icon: "checkmark.circle", value: "\(workout.numberOfCompletedSets ?? 0) sets")
                metricChip(icon: "scalemass", value: volumeText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    private func metricChip(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(IronTheme.accent)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundColor(IronTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
