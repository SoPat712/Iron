//
//  WorkoutSessionView.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 09.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WatchKit
import ImageIO

struct WorkoutSessionView: View {
    @ObservedObject var workoutSessionManager: WorkoutSessionManager

    var body: some View {
        WorkoutProjectionView(workoutSessionManager: workoutSessionManager)
    }
}

/// Used when the HealthKit session has been recovered/ended but the durable
/// workout projection is still available for editing or retrying.
struct OfflineWorkoutView: View {
    var body: some View {
        WorkoutProjectionView(workoutSessionManager: nil)
    }
}

private struct WorkoutProjectionView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @ObservedObject private var phoneConnectionManager = PhoneConnectionManager.shared
    let workoutSessionManager: WorkoutSessionManager?

    private var snapshot: WatchWorkoutSnapshot? {
        workoutSessionManagerStore.workoutSnapshot
    }

    private var completedSetCount: Int {
        snapshot?.exercises.reduce(0) { $0 + $1.sets.filter(\.completed).count } ?? 0
    }

    private var totalSetCount: Int {
        snapshot?.exercises.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    private var completedVolume: Double {
        snapshot?.exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { partial, set in
                guard set.completed, let weight = set.weight, let reps = set.reps else { return partial }
                return partial + (weight * Double(reps))
            }
        } ?? 0
    }

    private var pendingEventCount: Int {
        WatchWorkoutStore.shared.pendingEvents().count
    }

    private var syncStatus: (text: String, color: Color) {
        if pendingEventCount > 0 {
            let text = pendingEventCount == 1 ? "1 queued" : "\(pendingEventCount) queued"
            return (text, Color.accentColor)
        }
        if phoneConnectionManager.isReachable {
            return ("Phone linked", Color.green)
        }
        return ("Saved on watch", Color.accentColor)
    }

    @ViewBuilder
    var body: some View {
        if let snapshot {
            exerciseOverview(snapshot: snapshot)
        } else {
            ContentUnavailableView {
                Label("No Workout Loaded", systemImage: "applewatch.slash")
            } description: {
                Text("Start a workout on your iPhone to send the exercise list to this watch.")
            }
        }
    }

    private func exerciseOverview(snapshot: WatchWorkoutSnapshot) -> some View {
        List {
            Section {
                overviewHeader(snapshot: snapshot)
            }

            Section("Exercises") {
                if snapshot.exercises.isEmpty {
                    Text("No exercises were sent with this workout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.exercises) { exercise in
                        NavigationLink(
                            destination: SetLoggingView(
                                workoutSessionManager: workoutSessionManager,
                                exerciseID: exercise.id
                            )
                        ) {
                            ExerciseOverviewRow(
                                exercise: exercise,
                                weightUnit: snapshot.weightUnit ?? .kilogram
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(snapshot.title ?? "Workout")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: OptionsView()) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Workout options")
            }
        }
    }

    private func overviewHeader(snapshot: WatchWorkoutSnapshot) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                ElapsedTimeView(start: workoutSessionManager?.startDate ?? snapshot.startDate,
                                end: workoutSessionManager?.endDate ?? snapshot.endDate ?? context.date)
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())

                HStack(spacing: 5) {
                    Circle()
                        .fill(syncStatus.color)
                        .frame(width: 6, height: 6)
                    Text(syncStatus.text)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(syncStatus.color)
                    Spacer(minLength: 4)
                    Text("\(completedSetCount)/\(totalSetCount) sets")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.secondary)
                }

                HStack(spacing: 6) {
                    OverviewMetric(
                        value: volumeText(snapshot: snapshot),
                        label: snapshot.weightUnit?.symbol.uppercased() ?? "VOL"
                    )
                    OverviewMetric(
                        value: workoutSessionManager?.burnedCalories.map { String(format: "%.0f", $0) } ?? "--",
                        label: "KCAL"
                    )
                    if let manager = workoutSessionManager {
                        HeartRateView(mostRecentHeartRate: manager.mostRecentHeartRate,
                                      mostRecentHeartRateDate: manager.mostRecentHeartRateDate)
                    } else {
                        OverviewMetric(value: "--", label: "BPM")
                    }
                }

                RestBanner(
                    date: context.date,
                    end: workoutSessionManager?.restTimerEnd ?? snapshot.restTimerEnd,
                    keepRunning: workoutSessionManager?.keepRestTimerRunning ?? snapshot.keepRestTimerRunning
                )

                ProgressView(value: Double(completedSetCount), total: Double(max(totalSetCount, 1)))
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Workout progress")
                    .accessibilityValue("\(completedSetCount) of \(totalSetCount) sets complete")
            }
            .padding(.vertical, 2)
        }
    }

    private func volumeText(snapshot: WatchWorkoutSnapshot) -> String {
        guard completedVolume > 0 else { return "--" }
        if completedVolume.rounded() == completedVolume {
            return String(format: "%.0f", completedVolume)
        }
        return String(format: "%.0f", completedVolume)
    }
}

private struct ExerciseOverviewRow: View {
    let exercise: WatchWorkoutExercise
    let weightUnit: WatchWorkoutWeightUnit

    private var completedCount: Int {
        exercise.sets.filter(\.completed).count
    }

    var body: some View {
        HStack(spacing: 10) {
            WatchExerciseThumbnail(imageURL: exercise.imageURL, imageData: exercise.imageData, muscle: exercise.muscleGroup)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("\(completedCount)/\(exercise.sets.count) sets")
                        .foregroundStyle(.tint)
                    if let latest = exercise.sets.last(where: { $0.completed })?
                        .displayText(weightUnit: weightUnit) {
                        Text(latest)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exercise.name)
        .accessibilityValue("\(completedCount) of \(exercise.sets.count) sets complete")
    }
}

private struct SetLoggingView: View {
    @EnvironmentObject var workoutSessionManagerStore: WorkoutSessionManagerStore
    @Environment(\.dismiss) private var dismiss
    let workoutSessionManager: WorkoutSessionManager?
    let exerciseID: UUID

    @State private var selectedSetID: UUID?
    @State private var weightTenths = 0
    @State private var repsValue = 5
    @State private var rpeTenths = -1
    @State private var showingPlateCalculator = false
    @State private var pendingDelete: PendingDelete?

    private enum PendingDelete: Identifiable {
        case set
        case exercise

        var id: String {
            switch self {
            case .set: return "set"
            case .exercise: return "exercise"
            }
        }
    }

    private var snapshot: WatchWorkoutSnapshot? {
        workoutSessionManagerStore.workoutSnapshot
    }

    private var exercise: WatchWorkoutExercise? {
        snapshot?.exercises.first { $0.id == exerciseID }
    }

    private var selectedSet: WatchWorkoutSet? {
        guard let selectedSetID else { return nil }
        return exercise?.sets.first { $0.id == selectedSetID }
    }

    private var selectedIndex: Int? {
        guard let selectedSetID else { return nil }
        return exercise?.sets.firstIndex { $0.id == selectedSetID }
    }

    private var weightUnit: WatchWorkoutWeightUnit {
        snapshot?.weightUnit ?? .kilogram
    }

    var body: some View {
        Group {
            if let snapshot, let exercise, let selectedSet, let selectedIndex {
                setPage(snapshot: snapshot, exercise: exercise, set: selectedSet, index: selectedIndex)
            } else {
                ContentUnavailableView {
                    Label("Exercise Removed", systemImage: "xmark.circle")
                } description: {
                    Text("This exercise is no longer in the workout.")
                }
            }
        }
        .navigationTitle(exercise?.name ?? "Set")
        .onAppear(perform: reconcileSelection)
        .onChange(of: snapshot?.exercises.map(\.id)) {
            if exercise == nil {
                dismiss()
            } else {
                reconcileSelection()
            }
        }
        .onChange(of: exercise?.sets.map(\.id)) {
            reconcileSelection()
        }
        .onChange(of: selectedSetID) {
            loadSelectedSet()
        }
        .onChange(of: weightTenths) { commitCurrentSet() }
        .onChange(of: repsValue) { commitCurrentSet() }
        .onChange(of: rpeTenths) { commitCurrentSet() }
        .alert(item: $pendingDelete) { item in
            switch item {
            case .set:
                return Alert(
                    title: Text("Delete this set?"),
                    message: Text("The remaining sets stay in place."),
                    primaryButton: .destructive(Text("Delete Set"), action: deleteCurrentSet),
                    secondaryButton: .cancel()
                )
            case .exercise:
                return Alert(
                    title: Text("Remove this exercise?"),
                    message: Text("Its sets leave the workout."),
                    primaryButton: .destructive(Text("Delete Exercise"), action: deleteCurrentExercise),
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func setPage(snapshot: WatchWorkoutSnapshot,
                         exercise: WatchWorkoutExercise,
                         set: WatchWorkoutSet,
                         index: Int) -> some View {
        List {
            Section {
                Picker(weightUnit.symbol.uppercased(), selection: $weightTenths) {
                    ForEach(weightTenthChoices(current: set.weight), id: \.self) { tenths in
                        Text(WatchPlateMath.format(Double(tenths) / 10, integerOnly: false))
                            .tag(tenths)
                    }
                }

                Picker("Reps", selection: $repsValue) {
                    ForEach(repChoices(current: set.reps), id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }

                Picker("RPE", selection: $rpeTenths) {
                    Text("Off").tag(-1)
                    ForEach(Array(stride(from: 50, through: 100, by: 5)), id: \.self) { tenths in
                        Text(Self.rpeLabel(tenths)).tag(tenths)
                    }
                }
            } header: {
                Text("\(set.kindTitle) · Set \(index + 1) of \(exercise.sets.count)")
            } footer: {
                if let previous = set.previousDisplayText(weightUnit: weightUnit) {
                    Text("Previous \(previous)")
                        .monospacedDigit()
                }
            }

            Section {
                setPager(exercise: exercise, index: index, set: set)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Button("Plate Calculator", systemImage: "rectangle.split.2x1") {
                    showingPlateCalculator = true
                }
                .disabled(weightTenths <= 0)
            }

            Section("This Set") {
                Button("Add Set", systemImage: "plus", action: addSet)

                NavigationLink {
                    SetKindPickerView(
                        currentTag: set.tag,
                        onSelect: { tag in
                            workoutSessionManagerStore.updateSetTag(
                                workoutID: snapshot.workoutID,
                                exerciseID: exercise.id,
                                setID: set.id,
                                tag: tag
                            )
                        }
                    )
                } label: {
                    LabeledContent("Set Type", value: set.kindTitle)
                }

                Button("Delete Set", systemImage: "trash", role: .destructive) {
                    pendingDelete = .set
                }
                .disabled(exercise.sets.count < 2)
            }

            Section("Exercise") {
                NavigationLink {
                    WatchExercisePickerView(
                        title: "Add Exercise",
                        library: snapshot.library ?? [],
                        onPick: { pick in
                            workoutSessionManagerStore.addExercise(
                                workoutID: snapshot.workoutID,
                                afterExerciseID: exercise.id,
                                catalogExerciseUuid: pick.id,
                                name: pick.name,
                                muscleGroup: pick.muscle,
                                imageURL: pick.imageURL
                            )
                        }
                    )
                } label: {
                    Label("Add Below", systemImage: "plus.circle")
                }

                NavigationLink {
                    WatchExercisePickerView(
                        title: "Replace Exercise",
                        library: snapshot.library ?? [],
                        onPick: { pick in
                            workoutSessionManagerStore.replaceExercise(
                                workoutID: snapshot.workoutID,
                                exerciseID: exercise.id,
                                catalogExerciseUuid: pick.id,
                                name: pick.name,
                                muscleGroup: pick.muscle,
                                imageURL: pick.imageURL
                            )
                        }
                    )
                } label: {
                    Label("Replace Exercise", systemImage: "arrow.triangle.2.circlepath")
                }

                Button("Delete Exercise", systemImage: "trash", role: .destructive) {
                    pendingDelete = .exercise
                }
                .disabled(snapshot.exercises.count < 2)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                RestBanner(
                    date: context.date,
                    end: workoutSessionManager?.restTimerEnd ?? snapshot.restTimerEnd,
                    keepRunning: workoutSessionManager?.keepRestTimerRunning ?? snapshot.keepRestTimerRunning,
                    heartRate: workoutSessionManager?.mostRecentHeartRate
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .padding(.bottom, 2)
            }
        }
        .sheet(isPresented: $showingPlateCalculator) {
            WatchPlateCalculatorView(
                targetWeight: Double(weightTenths) / 10,
                unit: weightUnit
            )
        }
    }

    private func setPager(exercise: WatchWorkoutExercise, index: Int, set: WatchWorkoutSet) -> some View {
        HStack(spacing: 6) {
            Button("Previous Set", systemImage: "chevron.left") {
                selectSet(at: index - 1, in: exercise)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(index == 0)

            Button(action: toggleCurrentSet) {
                Image(systemName: set.completed ? "arrow.uturn.backward" : "checkmark")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(set.completed ? Color.accentColor : Color.green)
            .accessibilityLabel(set.completed ? "Undo completion" : "Complete set")

            Button("Next Set", systemImage: "chevron.right") {
                selectSet(at: index + 1, in: exercise)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(index >= exercise.sets.count - 1)
        }
    }

    private static func rpeLabel(_ tenths: Int) -> String {
        let value = Double(tenths) / 10
        return String(format: tenths % 10 == 0 ? "%.0f" : "%.1f", value)
    }

    private func weightTenthChoices(current: Double?) -> [Int] {
        let stepTenths = weightUnit == .pound ? 50 : 25
        let upperTenths = weightUnit == .pound ? 5_000 : 2_500
        var values = Array(stride(from: 0, through: upperTenths, by: stepTenths))
        let extras = [weightTenths, Int(((current ?? 0) * 10).rounded())]
        for extra in extras where extra > 0 && !values.contains(extra) {
            values.append(extra)
        }
        return values.sorted()
    }

    private func repChoices(current: Int?) -> [Int] {
        var values = Array(0...40)
        if let current, current > 40 {
            values.append(current)
        }
        return values
    }

    private func reconcileSelection() {
        let sets = exercise?.sets ?? []
        if let selectedSetID, sets.contains(where: { $0.id == selectedSetID }) {
            loadSelectedSet()
            return
        }
        let next = snapshot?.selectedSetID.flatMap { id in sets.contains(where: { $0.id == id }) ? id : nil }
            ?? sets.first(where: { !$0.completed })?.id
            ?? sets.first?.id
        selectedSetID = next
        loadSelectedSet()
    }

    private func loadSelectedSet() {
        guard let set = selectedSet else { return }
        let nextWeight = Int(((set.weight ?? 0) * 10).rounded())
        let nextReps = set.reps ?? 0
        let nextRPE = set.rpe.map { Int(($0 * 10).rounded()) } ?? -1
        if weightTenths != nextWeight {
            weightTenths = nextWeight
        }
        if repsValue != nextReps {
            repsValue = nextReps
        }
        if rpeTenths != nextRPE {
            rpeTenths = nextRPE
        }
    }

    private func commitCurrentSet() {
        guard let snapshot, let exercise, let currentSetID = selectedSetID, let selectedSet else { return }
        let weight = weightTenths > 0 ? Double(weightTenths) / 10 : nil
        let reps = repsValue
        let rpe = rpeTenths < 0 ? nil : Double(rpeTenths) / 10
        guard selectedSet.weight != weight || selectedSet.reps != reps || selectedSet.rpe != rpe else { return }
        workoutSessionManagerStore.updateSet(
            workoutID: snapshot.workoutID,
            exerciseID: exercise.id,
            setID: currentSetID,
            weight: weight,
            reps: reps,
            rpe: rpe
        )
    }

    private func selectSet(at index: Int, in exercise: WatchWorkoutExercise) {
        guard exercise.sets.indices.contains(index) else { return }
        commitCurrentSet()
        selectedSetID = exercise.sets[index].id
        loadSelectedSet()
    }

    private func toggleCurrentSet() {
        guard let snapshot, let exercise, let currentSetID = selectedSetID, let selectedSet else { return }
        commitCurrentSet()
        workoutSessionManagerStore.toggleSet(
            workoutID: snapshot.workoutID,
            exerciseID: exercise.id,
            setID: currentSetID
        )
        if !selectedSet.completed {
            workoutSessionManagerStore.startRestTimer(
                workoutID: snapshot.workoutID,
                duration: exercise.restTimerDuration ?? 60
            )
            if let next = exercise.sets.drop(while: { $0.id != currentSetID }).dropFirst().first(where: { !$0.completed })
                ?? exercise.sets.first(where: { !$0.completed && $0.id != currentSetID }) {
                selectedSetID = next.id
                loadSelectedSet()
            }
        }
    }

    private func addSet() {
        guard let snapshot, let exercise else { return }
        commitCurrentSet()
        workoutSessionManagerStore.addSet(workoutID: snapshot.workoutID, exerciseID: exercise.id)
    }

    private func deleteCurrentSet() {
        guard let snapshot, let exercise, let currentSetID = selectedSetID else { return }
        workoutSessionManagerStore.deleteSet(
            workoutID: snapshot.workoutID,
            exerciseID: exercise.id,
            setID: currentSetID
        )
    }

    private func deleteCurrentExercise() {
        guard let snapshot else { return }
        workoutSessionManagerStore.deleteExercise(workoutID: snapshot.workoutID, exerciseID: exerciseID)
        dismiss()
    }
}

private struct SetKindPickerView: View {
    let currentTag: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let kinds: [(title: String, tag: String?, color: Color)] = [
        ("Working", nil, Color.primary),
        ("Warm-up", "warmUp", .orange),
        ("Drop", "dropSet", .purple),
        ("Failure", "failure", Color.red)
    ]

    var body: some View {
        List {
            ForEach(kinds, id: \.title) { kind in
                Button(action: {
                    onSelect(kind.tag)
                    dismiss()
                }) {
                    HStack {
                        Text(kind.title)
                            .foregroundColor(kind.color)
                        Spacer()
                        if currentTag == kind.tag {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Set Options")
    }
}

private struct WatchExercisePickerView: View {
    let title: String
    let library: [WatchExercisePick]
    let onPick: (WatchExercisePick) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if library.isEmpty {
                Text("The exercise library arrives from iPhone when this workout syncs.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(Color.secondary)
            } else {
                ForEach(library) { pick in
                    Button(action: {
                        onPick(pick)
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            WatchExerciseThumbnail(imageURL: pick.imageURL, imageData: nil, muscle: pick.muscle, size: 28)
                            Text(pick.name)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(Color.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct WatchExerciseThumbnail: View {
    let imageURL: String?
    let imageData: Data?
    let muscle: String?
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            WatchMuscleGlyph(muscle: muscle, size: size, showsBackground: false)
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.66, height: size * 0.66)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .onAppear { load() }
        .onChange(of: imageURL) {
            load(reset: true)
        }
        .onChange(of: imageData) {
            load(reset: true)
        }
        .accessibilityHidden(true)
    }

    private func load(reset: Bool = false) {
        if reset { image = nil }
        if image == nil, let imageData, let embedded = UIImage(data: imageData) {
            image = embedded
        }
        guard let imageURL, let url = URL(string: imageURL) else { return }
        let target = size * WKInterfaceDevice.current().screenScale
        Task {
            let loaded = await WatchExerciseStillStore.shared.image(for: url, targetPixelSize: target)
            await MainActor.run {
                if let loaded {
                    image = loaded
                }
            }
        }
    }
}

private final class WatchExerciseStillStore {
    static let shared = WatchExerciseStillStore()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private var directoryURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExerciseMedia", isDirectory: true)
    }

    func image(for remoteURL: URL, targetPixelSize: CGFloat) async -> UIImage? {
        let key = "\(remoteURL.absoluteString)|\(Int(targetPixelSize.rounded(.up)))" as NSString
        if let cached = memory.object(forKey: key) {
            return cached
        }
        let data: Data?
        if let disk = try? Data(contentsOf: fileURL(for: remoteURL)) {
            data = disk
        } else {
            data = await download(remoteURL)
        }
        guard let data, let decoded = stillFrame(from: data, targetPixelSize: targetPixelSize) else {
            return nil
        }
        memory.setObject(decoded, forKey: key)
        return decoded
    }

    private func download(_ remoteURL: URL) async -> Data? {
        var request = URLRequest(url: remoteURL)
        request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            persist(data, for: remoteURL)
            return data
        } catch {
            return nil
        }
    }

    private func persist(_ data: Data, for remoteURL: URL) {
        let destination = fileURL(for: remoteURL)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: destination, options: .atomic)
    }

    private func fileURL(for remoteURL: URL) -> URL {
        directoryURL.appendingPathComponent(remoteURL.lastPathComponent, isDirectory: false)
    }

    private func stillFrame(from data: Data, targetPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return UIImage(data: data)
        }
        _ = targetPixelSize
        return UIImage(cgImage: frame)
    }
}

private struct WatchMuscleGlyph: View {
    let muscle: String?
    var size: CGFloat = 36
    var showsBackground: Bool = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(showsBackground ? tint.opacity(0.18) : Color.clear)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch muscle {
        case "back": return "arrow.up.and.down.circle.fill"
        case "chest": return "shield.fill"
        case "legs": return "figure.walk"
        case "arms": return "bolt.fill"
        case "shoulders": return "triangle.fill"
        case "abdominals": return "circle.grid.cross.fill"
        case "cardio": return "heart.fill"
        default: return "circle.grid.cross.fill"
        }
    }

    private var tint: Color {
        switch muscle {
        case "abdominals": return .yellow
        case "arms": return .purple
        case "shoulders": return .orange
        case "back": return .blue
        case "legs": return .green
        case "chest": return .red
        case "cardio": return .pink
        default: return Color.accentColor
        }
    }
}

private struct OverviewMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundColor(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct RestBanner: View {
    let date: Date
    let end: Date?
    let keepRunning: Bool
    var heartRate: Double? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .foregroundStyle(.tint)
            RestTimerView(date: date, end: end, keepRunning: keepRunning)
                .font(.caption.weight(.semibold).monospacedDigit())

            if let heartRate {
                Spacer(minLength: 4)
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(String(format: "%.0f", heartRate))
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension WatchWorkoutSet {
    var kindTitle: String {
        switch tag {
        case "warmUp": return "Warm-up"
        case "dropSet": return "Drop"
        case "failure": return "Failure"
        default: return "Working"
        }
    }

    var kindColor: Color {
        switch tag {
        case "warmUp": return .orange
        case "dropSet": return .purple
        case "failure": return Color.red
        default: return Color.secondary
        }
    }
}

private enum WatchPlateMath {
    static func currentWeight(from text: String) -> Double {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    static func format(_ value: Double, integerOnly: Bool) -> String {
        if integerOnly {
            return String(Int(value.rounded()))
        }
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}

private extension WatchWorkoutWeightUnit {
    var barbellWeight: Double {
        self == .kilogram ? 20 : 45
    }

    var plates: [Double] {
        self == .kilogram
            ? [25, 20, 15, 10, 5, 2.5, 1.25, 0.5]
            : [45, 35, 25, 10, 5, 2.5, 1.25]
    }
}

private struct WatchPlateCalculatorView: View {
    let targetWeight: Double
    let unit: WatchWorkoutWeightUnit

    private var platesPerSide: [(weight: Double, count: Int)] {
        var remaining = max((targetWeight - unit.barbellWeight) / 2, 0)
        return unit.plates.compactMap { plate in
            let count = Int(floor((remaining + 0.0001) / plate))
            guard count > 0 else { return nil }
            remaining -= Double(count) * plate
            return (plate, count)
        }
    }

    private var loadedWeight: Double {
        unit.barbellWeight + (2 * platesPerSide.reduce(0) { $0 + ($1.weight * Double($1.count)) })
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Target", value: "\(WatchPlateMath.format(targetWeight, integerOnly: false)) \(unit.symbol)")
                LabeledContent("Bar", value: "\(WatchPlateMath.format(unit.barbellWeight, integerOnly: true)) \(unit.symbol)")
            }

            Section {
                if targetWeight < unit.barbellWeight {
                    Text("Target is lighter than the bar.")
                        .foregroundStyle(.red)
                } else if platesPerSide.isEmpty {
                    Text("Empty bar.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(platesPerSide, id: \.weight) { plate in
                        LabeledContent(
                            "\(WatchPlateMath.format(plate.weight, integerOnly: false)) \(unit.symbol)",
                            value: "\(plate.count)×"
                        )
                        .monospacedDigit()
                    }
                }
            } header: {
                Text("Each Side")
            } footer: {
                Text("Loads \(WatchPlateMath.format(loadedWeight, integerOnly: false)) \(unit.symbol).")
            }
        }
        .navigationTitle("Plates")
    }
}

private struct ElapsedTimeView: View {
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    let start: Date?
    let end: Date?

    var body: some View {
        Text(start.map { Self.durationFormatter.string(from: $0, to: end ?? Date()) ?? "--:--:--" } ?? "--:--:--")
    }
}

private struct RestTimerView: View {
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    let date: Date
    let end: Date?
    let keepRunning: Bool

    private var remainingTime: TimeInterval? {
        guard let end = end else { return nil }
        let remainingTime = end.timeIntervalSince(date)
        guard remainingTime >= 0 || keepRunning else { return nil }
        return remainingTime
    }

    private var roundedRemainingTime: TimeInterval? {
        remainingTime?.rounded(.up)
    }

    var body: some View {
        let remainingTime = roundedRemainingTime
        let isOvertime = (remainingTime ?? 0) < 0
        let formatted = remainingTime.map {
            Self.durationFormatter.string(from: abs($0)) ?? "--:--"
        } ?? "Ready"

        Text(isOvertime ? "+\(formatted)" : formatted)
            .foregroundColor(isOvertime ? Color.red : Color.primary)
            .accessibilityLabel(
                isOvertime
                    ? "Over rest time by \(formatted)"
                    : (remainingTime == nil ? "Rest timer ready" : "Rest time remaining \(formatted)")
            )
    }
}

private struct HeartRateView: View {
    private static let maxHeartRateAge: Double = 10

    let mostRecentHeartRate: Double?
    let mostRecentHeartRateDate: Date?

    var body: some View {
        TimelineView(.periodic(from: mostRecentHeartRateDate ?? Date(), by: Self.maxHeartRateAge)) { context in
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .foregroundColor(measurementWasRecent(date: context.date) ? Color.red : Color.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mostRecentHeartRate.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                    Text("BPM")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func measurementWasRecent(date: Date) -> Bool {
        guard let mostRecentHeartRateDate = mostRecentHeartRateDate else {
            return false
        }
        return date.timeIntervalSince(mostRecentHeartRateDate) < Self.maxHeartRateAge
    }
}
