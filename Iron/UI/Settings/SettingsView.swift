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
            .sheet(item: $actionAlert) { alert in
                IronStatusSheet(
                    headerTitle: "Iron",
                    title: alert.title,
                    message: alert.message,
                    systemImage: "info.circle.fill",
                    tint: .accentColor
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
                settingsLink(
                    "Appearance",
                    detail: settingsStore.appearance.title,
                    icon: "circle.lefthalf.filled",
                    destination: AppearanceSettingsView()
                )
            }

            Section {
                settingsLink(
                    "Units",
                    detail: settingsStore.weightUnit.title,
                    icon: "scalemass.fill",
                    destination: UnitsSettingsView()
                )
                settingsLink("Workout preferences", icon: "slider.horizontal.3", destination: GeneralSettingsView())
                settingsLink("Sounds & haptics", icon: "speaker.wave.2.fill", tint: .pink, destination: SoundsSettingsView())
                if HealthSettingsView.isSupported {
                    settingsLink("Apple Health", icon: "heart.fill", tint: .red, destination: HealthSettingsView())
                }
                if WatchSettingsView.isSupported {
                    settingsLink("Apple Watch", icon: "applewatch", destination: WatchSettingsView())
                }
            } header: {
                Text("Training")
            }

            Section("Your Data") {
                settingsLink("Import & export", icon: "arrow.up.arrow.down", destination: BackupAndExportView())
            }

            Section("Support") {
                Button(action: sendFeedback) {
                    settingsRow("Send feedback", icon: "paperplane.fill")
                }
                .buttonStyle(.plain)

                Button(action: openReview) {
                    settingsRow("Rate Iron", icon: "star.fill", tint: .orange)
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .ironScreen()
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        detail: String? = nil,
        icon: String,
        tint: Color = .accentColor,
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
        tint: Color = .accentColor
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
        NavigationStack {
            List {
                Section {
                    Button("Open Default Mail App", systemImage: "envelope.fill", action: openMailApp)

                    Button(
                        copied ? "Address Copied" : "Copy \(emailAddress)",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    ) {
                        UIPasteboard.general.string = emailAddress
                        copied = true
                    }
                } header: {
                    Text("Send Feedback")
                } footer: {
                    if mailLaunchFailed {
                        Label(
                            "No email app could open this message. Copy the address instead.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Text("Apple Mail isn’t configured on this device. Open another email app or copy our support address.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        List {
            Section {
                ForEach(IronAppearance.allCases) { appearance in
                    Button {
                        settingsStore.appearance = appearance
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
                            Label(appearance.title, systemImage: appearance.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settingsStore.appearance == appearance {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text(settingsStore.appearance.subtitle)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: settingsStore.appearance)
    }
}

struct LicensesAttributionsView: View {
    private struct AttributionLink {
        let title: String
        let url: URL
    }

    var body: some View {
        List {
            Section {
                attributionSectionContent(
                    message: "Exercise names, metadata, and English instructions are generated from Hasan Emir Yıldırım’s exercises dataset supplied through the openGym reference material.",
                    license: "MIT",
                    links: [
                        AttributionLink(title: "Dataset source", url: URL(string: "https://github.com/hasaneyldrm/exercises-dataset")!)
                    ]
                )
            } header: {
                Text("Exercise Catalogue")
            }

            Section {
                attributionSectionContent(
                    message: "Iron downloads ExerciseDB’s Gym Visual GIFs once, stores them on this device, and does not delete them. Later launches fill any missing files over Wi-Fi so the library works offline. The upstream notice requests the following attribution: \(Exercise.mediaAttribution). The media is not covered by the catalogue’s MIT license.",
                    license: "Cached media",
                    links: [
                        AttributionLink(title: "Gym Visual", url: URL(string: "https://gymvisual.com/")!),
                        AttributionLink(title: "ExerciseDB", url: URL(string: "https://exercisedb.dev/")!)
                    ]
                )
            } header: {
                Text("Exercise Images & Animations")
            }

            Section {
                attributionSectionContent(
                    message: "Front and back muscle highlighting uses MuscleMap 1.6.4 by Melih Colpan.",
                    license: "MIT",
                    links: [
                        AttributionLink(title: "MuscleMap source", url: URL(string: "https://github.com/melihcolpan/MuscleMap")!)
                    ]
                )
            } header: {
                Text("Muscle Maps")
            } footer: {
                Text("Full third-party license text ships with Iron’s source distribution in THIRD_PARTY_NOTICES.md.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Licenses & Attributions")
    }

    @ViewBuilder
    private func attributionSectionContent(
        message: String,
        license: String,
        links: [AttributionLink]
    ) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)

        LabeledContent("License", value: license)

        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
            Link(destination: link.url) {
                LabeledContent(link.title) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

struct WorkoutCalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @FetchRequest(fetchRequest: WorkoutCalendarView.fetchRequest) private var workouts: FetchedResults<Workout>

    @State private var visibleMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

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
        List {
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
                            .labelStyle(.iconOnly)

                        Spacer()

                        Text(monthTitle)
                            .font(.headline)

                        Spacer()

                        Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                            Text(weekday.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, date in
                            calendarDay(date)
                        }
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("^[\(monthWorkouts.count) workout](inflect: true) in \(monthTitle).")
            }

            Section("Momentum") {
                LabeledContent("Streak", value: "^[\(trainingStreak) week](inflect: true)")
                LabeledContent("Rest Days", value: "^[\(restDayCount) day](inflect: true)")
            }

            Section("This Month") {
                if monthWorkouts.isEmpty {
                    Text("Finished sessions in \(monthTitle) will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monthWorkouts) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            CalendarWorkoutRow(workout: workout, showsDate: true)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) {
                        visibleMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
                    }
                }
            }
        }
    }

    private func shiftMonth(_ direction: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: direction, to: visibleMonth) else { return }
        withAnimation(IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)) { visibleMonth = month }
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
            Color.clear.frame(minHeight: 40)
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
                Circle().fill(Color.accentColor)
            } else if isToday {
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.monospacedDigit())
                .fontWeight(workoutCount > 0 || isToday ? .semibold : .regular)
                .foregroundStyle(workoutCount > 0 ? Color.white : (isToday ? Color.accentColor : Color.primary))
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(date.formatted(date: .long, time: .omitted)), \(workoutCount) workout\(workoutCount == 1 ? "" : "s")"
        )
    }
}

private struct WorkoutCalendarDayView: View {
    let date: Date
    let workouts: [Workout]

    var body: some View {
        List {
            Section {
                LabeledContent("Sessions", value: "\(workouts.count)")
                LabeledContent("Completed Sets", value: "\(workouts.reduce(0) { $0 + ($1.numberOfCompletedSets ?? 0) })")
                LabeledContent(
                    "Time",
                    value: Workout.durationFormatter.string(from: workouts.reduce(0) { $0 + ($1.duration ?? 0) }) ?? "0m"
                )
            }

            Section("Workouts") {
                ForEach(workouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        CalendarWorkoutRow(workout: workout, showsDate: false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
    }
}

private struct CalendarWorkoutRow: View {
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
        VStack(alignment: .leading, spacing: 3) {
            Text(workout.displayTitle(in: exerciseStore.exercises))
                .lineLimit(1)
            Text(timestampText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(durationText) · \(workout.numberOfCompletedSets ?? 0) sets · \(volumeText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
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
