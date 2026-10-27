//
//  SessionContentView.swift
//  SwiftUI Playground
//
//  Created by Karim Abou Zeid on 19.06.19.
//  Copyright © 2019 Karim Abou Zeid. All rights reserved.
//

import SwiftUI
import CoreData
import WorkoutDataKit

let NAVIGATION_BAR_SPACING: CGFloat = 16

struct ContentView : View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sceneState: SceneState
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @ObservedObject private var importController = HevyImportController.shared
    @FetchRequest(fetchRequest: Workout.currentWorkoutFetchRequest) private var currentWorkouts

    #if DEBUG
    @FetchRequest(fetchRequest: ContentView.inspectionWorkoutExerciseFetchRequest)
    private var inspectionWorkoutExercises: FetchedResults<WorkoutExercise>

    @FetchRequest(fetchRequest: ContentView.inspectionCompletedWorkoutFetchRequest)
    private var inspectionCompletedWorkouts: FetchedResults<Workout>
    #endif

    @State private var restoreResult: IdentifiableHolder<Result<Void, Error>>?
    @State private var restoreBackupData: IdentifiableHolder<Data>?
    @State private var hevyImportOutcome: HevyCSVImportOutcome?
    @State private var showingDiscardWorkoutConfirmation = false
    @Namespace private var activeWorkoutNamespace

    private let activeWorkoutDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    var body: some View {
        rootView
            .overlay {
                if let phase = importController.phase {
                    HevyImportProgressOverlay(phase: phase)
                        .transition(.opacity)
                }
            }
            .animation(IronMotion.preferred(IronMotion.fade, reduceMotion: reduceMotion), value: importController.phase)
            .ironScreen()
            .preferredColorScheme(settingsStore.appearance.colorScheme)
            .onChange(of: currentWorkouts.first?.objectID) { _, newWorkoutID in
                guard newWorkoutID != nil else { return }
                if let workout = currentWorkouts.first {
                    WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
                }
                withAnimation(activeWorkoutTransition) {
                    sceneState.selectedTab = .workout
                    sceneState.isCurrentWorkoutExpanded = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                TrainingHistoryStore.shared.refresh()
                guard let workout = currentWorkouts.first else { return }
                WorkoutLiveActivityManager.shared.startOrUpdate(for: workout)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.RestoreFromBackup)) { output in
                guard let backupData = output.userInfo?[restoreFromBackupDataUserInfoKey] as? Data else { return }
                self.restoreBackupData = IdentifiableHolder(value: backupData)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.ImportHevyCSV)) { output in
                if let error = output.userInfo?[importHevyCSVErrorUserInfoKey] as? Error {
                    hevyImportOutcome = HevyCSVImportOutcome(result: .failure(error))
                    return
                }
                let incoming = output.userInfo?[importHevyCSVDataUserInfoKey]
                let csvDocuments: [Data]
                if let documents = incoming as? [Data] {
                    csvDocuments = documents
                } else if let document = incoming as? Data {
                    csvDocuments = [document]
                } else {
                    return
                }
                Task {
                    hevyImportOutcome = await HevyImportController.shared.run(
                        csvDocuments,
                        into: WorkoutDataStorage.shared.persistentContainer.viewContext,
                        exerciseStore: ExerciseStore.shared
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { restoreBackupData != nil && !usesNativeLoggerPresentation },
                    set: { if !$0 { restoreBackupData = nil } }
                )
            ) {
                restoreBackupConfirmation
            }
            .sheet(item: rootPresentationBinding($restoreResult)) { restoreResultHolder in
                restoreResultSheet(restoreResultHolder.value)
            }
            .sheet(item: rootPresentationBinding($hevyImportOutcome)) { outcome in
                HevyCSVImportResultSheet(outcome: outcome)
            }
            .alert(
                "Discard the active workout?",
                isPresented: $showingDiscardWorkoutConfirmation
            ) {
                Button("Discard Workout", role: .destructive, action: discardCurrentWorkout)
                Button("Cancel", role: .cancel) {
                    showingDiscardWorkoutConfirmation = false
                }
            } message: {
                Text("The active workout, its notes, and every logged set will be permanently deleted.")
            }
    }

    private var restoreBackupConfirmation: some View {
        IronConfirmationSheet(
            title: RestoreActionSheet.confirmationTitle,
            message: RestoreActionSheet.confirmationMessage,
            confirmTitle: "Restore Backup",
            systemImage: "arrow.counterclockwise.icloud.fill",
            secondaryTitle: "Keep Current Data",
            onCancel: { restoreBackupData = nil },
            onConfirm: restoreIncomingBackup
        )
        .presentationDetents([.height(410), .medium])
        .presentationDragIndicator(.visible)
    }

    private var usesNativeLoggerPresentation: Bool {
        if #available(iOS 18.0, *) {
            return !reduceMotion && sceneState.isCurrentWorkoutExpanded && currentWorkouts.first != nil
        }
        return false
    }

    private func rootPresentationBinding<Value>(_ state: Binding<Value?>) -> Binding<Value?> {
        Binding(get: { usesNativeLoggerPresentation ? nil : state.wrappedValue }, set: { state.wrappedValue = $0 })
    }

    private func restoreIncomingBackup() {
        guard let data = restoreBackupData?.value else { return }
        restoreBackupData = nil
        RestoreActionSheet.restore(
            context: WorkoutDataStorage.shared.persistentContainer.viewContext,
            exerciseStore: ExerciseStore.shared,
            data: { data }
        ) { result in
            restoreResult = IdentifiableHolder(value: result)
        }
    }

    private func restoreResultSheet(_ result: RestoreActionSheet.RestoreResult) -> some View {
        let details = RestoreActionSheet.restoreResultDetails(result)
        return IronStatusSheet(
            headerTitle: "Restore",
            title: details.title,
            message: details.message,
            systemImage: details.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            tint: details.isSuccess ? IronTheme.success : IronTheme.danger
        )
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ironInspectHome") {
            FeedView()
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectHistory") {
            HistoryView()
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectSettings") {
            SettingsView()
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectEmptyWorkoutTab") {
            StartWorkoutView()
                .environment(\.managedObjectContext, Self.inspectionEmptyContext)
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectImportedData") {
            NavigationStack {
                BackupAndExportView()
                    .environment(\.managedObjectContext, Self.inspectionImportedContext)
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectWorkoutTab") {
            StartWorkoutView()
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectExerciseLibrary") {
            NavigationStack {
                ExerciseMuscleGroupsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectExerciseDetail"),
                  let inspectionExercise = inspectionWorkoutExercise?.exercise(in: exerciseStore.exercises)
                    ?? exerciseStore.exercises.first {
            NavigationStack {
                ExerciseDetailView(exercise: inspectionExercise)
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectEmptyExercise"),
                  let inspectionExercise = inspectionEmptyExercise {
            NavigationStack {
                ExerciseDetailView(exercise: inspectionExercise)
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectHealthSettings") {
            NavigationStack {
                HealthSettingsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectBackupSettings") {
            NavigationStack {
                BackupAndExportView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectWorkoutPreferences") {
            NavigationStack {
                GeneralSettingsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectUnits") {
            NavigationStack {
                UnitsSettingsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectSounds") {
            NavigationStack {
                SoundsSettingsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectPlateCalculator") {
            NavigationStack {
                PlateCalculatorView(
                    unit: SettingsStore.shared.weightUnit,
                    initialTarget: SettingsStore.shared.weightUnit == .metric ? 102.5 : 225
                ) { _ in }
                .navigationTitle("Plate Calculator")
                .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectAbout") {
            NavigationStack {
                AboutView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectLicenses") {
            NavigationStack {
                LicensesAttributionsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectWatchSettings") {
            NavigationStack {
                WatchSettingsView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectCreateExercise") {
            CreateCustomExerciseSheet()
                .productionEnvironment()
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectCustomExercises") {
            NavigationStack {
                CustomExercisesView()
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectCompletedWorkout"),
                  let completedWorkout = inspectionCompletedWorkout {
            NavigationStack {
                WorkoutDetailView(workout: completedWorkout)
                    .productionEnvironment()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-ironInspectWorkoutExercise"),
           let workoutExercise = inspectionWorkoutExercise {
            NavigationStack {
                WorkoutExerciseDetailView(workoutExercise: workoutExercise)
                    .productionEnvironment()
            }
        } else {
            standardRootView
        }
        #else
        standardRootView
        #endif
    }

    @ViewBuilder
    private var standardRootView: some View {
        if #available(iOS 18.0, *), !reduceMotion {
            workoutRootSurface(useNativeWorkoutPresentation: true)
                .fullScreenCover(
                    isPresented: nativeWorkoutPresentationBinding
                ) {
                    if let workout = currentWorkouts.first {
                        nativeCurrentWorkoutPresentation(workout)
                    }
                }
        } else {
            workoutRootSurface(useNativeWorkoutPresentation: false)
        }
    }

    @ViewBuilder
    private func workoutRootSurface(useNativeWorkoutPresentation: Bool) -> some View {
        ZStack {
            tabSurface

            if let workout = currentWorkouts.first {
                if useNativeWorkoutPresentation {
                    // Keep the source mounted behind the native cover so the
                    // reverse zoom has a live origin after an interactive dismiss.
                    if #available(iOS 18.0, *) {
                        if #unavailable(iOS 26.1) {
                            nativeCollapsedWorkoutSource(workout)
                                .zIndex(9)
                        }
                    }
                } else {
                    if sceneState.isCurrentWorkoutExpanded {
                        legacyCurrentWorkoutOverlay(workout)
                    } else if #unavailable(iOS 26.1) {
                        collapsedActiveWorkoutPill(workout)
                            .matchedGeometryEffect(
                                id: "active-workout-surface",
                                in: activeWorkoutNamespace,
                                properties: reduceMotion ? [] : .frame,
                                anchor: .bottom
                            )
                            .transition(.opacity)
                            .zIndex(9)
                    }
                }
            }
        }
        .animation(activeWorkoutTransition, value: sceneState.isCurrentWorkoutExpanded)
        .animation(activeWorkoutTransition, value: currentWorkouts.first?.objectID)
    }

    private func legacyCurrentWorkoutOverlay(_ workout: Workout) -> some View {
        currentWorkoutLogger(workout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IronTheme.background.ignoresSafeArea())
            .matchedGeometryEffect(
                id: "active-workout-surface",
                in: activeWorkoutNamespace,
                properties: reduceMotion ? [] : .frame,
                anchor: .bottom
            )
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .zIndex(10)
    }

    @available(iOS 18.0, *)
    private func nativeCollapsedWorkoutSource(_ workout: Workout) -> some View {
        activeWorkoutPillChrome(workout)
            .matchedTransitionSource(
                id: "active-workout-zoom",
                in: activeWorkoutNamespace
            )
            .padding(.horizontal, IronTheme.activeWorkoutPillHorizontalPadding)
            .padding(.bottom, IronTheme.activeWorkoutPillBottomOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func currentWorkoutLogger(_ workout: Workout) -> some View {
        CurrentWorkoutView(workout: workout, onMinimize: minimizeCurrentWorkout)
            .productionEnvironment()
    }

    @available(iOS 18.0, *)
    private func nativeCurrentWorkoutPresentation(_ workout: Workout) -> some View {
        currentWorkoutLogger(workout)
            // Global import/restore UI must be presented above the native cover,
            // just as it was above the former in-place logger overlay.
            .overlay {
                if let phase = importController.phase {
                    HevyImportProgressOverlay(phase: phase)
                }
            }
            .sheet(isPresented: Binding(
                get: { restoreBackupData != nil },
                set: { if !$0 { restoreBackupData = nil } }
            )) {
                restoreBackupConfirmation
            }
            .sheet(item: $restoreResult) { result in
                restoreResultSheet(result.value)
            }
            .sheet(item: $hevyImportOutcome) { outcome in
                HevyCSVImportResultSheet(outcome: outcome)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IronTheme.background.ignoresSafeArea())
            .navigationTransition(
                .zoom(sourceID: "active-workout-zoom", in: activeWorkoutNamespace)
            )
    }

    @available(iOS 18.0, *)
    private var nativeWorkoutPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                sceneState.isCurrentWorkoutExpanded && currentWorkouts.first != nil
            },
            set: { isPresented in
                if isPresented {
                    guard currentWorkouts.first != nil else { return }
                    sceneState.isCurrentWorkoutExpanded = true
                } else {
                    sceneState.isCurrentWorkoutExpanded = false
                }
            }
        )
    }

    @ViewBuilder
    private var tabSurface: some View {
        if #available(iOS 26.1, *) {
            tabView
                .tabBarMinimizeBehavior(hasActiveWorkout ? .onScrollDown : .never)
                .tabViewBottomAccessory(
                    isEnabled: hasActiveWorkout && (!sceneState.isCurrentWorkoutExpanded || !reduceMotion)
                ) {
                    if let workout = currentWorkouts.first {
                        activeWorkoutAccessory(workout)
                    }
                }
        } else {
            tabView
        }
    }

    @available(iOS 26.1, *)
    private func activeWorkoutAccessory(_ workout: Workout) -> some View {
        AdaptiveWorkoutTabAccessory {
            collapsedActiveWorkoutAccessory(workout)
                .padding(.horizontal, 4)
        } inline: {
            inlineActiveWorkoutAccessory(workout)
        }
        .matchedTransitionSource(
            id: "active-workout-zoom",
            in: activeWorkoutNamespace
        )
    }

    private var hasActiveWorkout: Bool {
        currentWorkouts.first != nil
    }

    private var activeWorkoutTransition: Animation {
        IronMotion.preferred(IronMotion.collapse, reduceMotion: reduceMotion)
    }

    private func collapsedActiveWorkoutPill(_ workout: Workout) -> some View {
        activeWorkoutPillChrome(workout)
            .padding(.horizontal, IronTheme.activeWorkoutPillHorizontalPadding)
            .padding(.bottom, IronTheme.activeWorkoutPillBottomOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func activeWorkoutPillChrome(_ workout: Workout) -> some View {
        collapsedActiveWorkoutAccessory(workout)
            .ironLiquidGlassPill(tint: .clear)
            .shadow(color: IronTheme.mediaBackdrop.opacity(0.14), radius: 18, x: 0, y: 8)
    }

    private func collapsedActiveWorkoutAccessory(_ workout: Workout) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            HStack(spacing: 5) {
                Button(action: expandCurrentWorkout) {
                    HStack(spacing: 9) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(IronTheme.onAccent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(IronTheme.accent))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(workout.displayTitle(in: exerciseStore.exercises))
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(IronTheme.primaryText)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(IronTheme.accent)
                                    .frame(width: 5, height: 5)
                                    .accessibilityHidden(true)
                                Text(activeWorkoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                                    .foregroundStyle(IronTheme.metricTime)
                                    .contentTransition(reduceMotion ? .opacity : .numericText())
                                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: Int(workout.safeDuration))
                                Text("•").foregroundColor(IronTheme.tertiaryText)
                                (Text(activeWorkoutVolumeTitle(workout))
                                 + Text(" " + settingsStore.weightUnit.unit.symbol)
                                    .font(.caption2).foregroundColor(IronTheme.secondaryText))
                                    .foregroundStyle(IronTheme.metricVolume)
                                    .contentTransition(reduceMotion ? .opacity : .numericText())
                                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: workout.totalCompletedWeight)
                                Text("•").foregroundColor(IronTheme.tertiaryText)
                                Text("\(workout.numberOfCompletedSets ?? 0) sets")
                                    .foregroundStyle(IronTheme.metricSets)
                                    .contentTransition(reduceMotion ? .opacity : .numericText())
                                    .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: workout.numberOfCompletedSets)
                            }
                            .font(.ironMetric(.caption2, weight: .semibold))
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume \(workout.displayTitle(in: exerciseStore.exercises))")

                compactWorkoutActionButton(
                    systemImage: "chevron.up",
                    tint: IronTheme.accent,
                    fill: IronTheme.accent.opacity(0.14),
                    accessibilityLabel: "Expand active workout",
                    action: expandCurrentWorkout
                )

                compactWorkoutActionButton(
                    systemImage: "trash.fill",
                    tint: IronTheme.danger,
                    fill: IronTheme.danger.opacity(0.13),
                    accessibilityLabel: "Discard active workout"
                ) {
                    showingDiscardWorkoutConfirmation = true
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
        }
    }

    private func inlineActiveWorkoutAccessory(_ workout: Workout) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            Button(action: expandCurrentWorkout) {
                HStack(spacing: 7) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(IronTheme.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(IronTheme.accent))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(workout.displayTitle(in: exerciseStore.exercises))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(1)

                        Text(activeWorkoutDurationFormatter.string(from: workout.safeDuration) ?? "0:00")
                            .font(.ironMetric(.caption2, weight: .semibold))
                            .foregroundColor(IronTheme.metricTime)
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: Int(workout.safeDuration))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 5)
            .accessibilityLabel("Resume \(workout.displayTitle(in: exerciseStore.exercises))")
        }
    }

    private func compactWorkoutActionButton(
        systemImage: String,
        tint: Color,
        fill: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tint)
                }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func minimizeCurrentWorkout() {
        withAnimation(activeWorkoutTransition) {
            sceneState.selectedTab = .workout
            sceneState.isCurrentWorkoutExpanded = false
        }
    }

    private func expandCurrentWorkout() {
        withAnimation(activeWorkoutTransition) {
            sceneState.selectedTab = .workout
            sceneState.isCurrentWorkoutExpanded = true
        }
    }

    private func activeWorkoutVolumeTitle(_ workout: Workout) -> String {
        let value = WeightUnit.convert(weight: workout.totalCompletedWeight ?? 0, from: .metric, to: settingsStore.weightUnit)
        return settingsStore.weightUnit.displayNumberFormatter.string(from: value as NSNumber) ?? "0"
    }

    private func discardCurrentWorkout() {
        showingDiscardWorkoutConfirmation = false
        guard let workout = currentWorkouts.first else { return }
        workout.cancelOrCrash()
        sceneState.isCurrentWorkoutExpanded = false

        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.warning)
    }

    #if DEBUG
    private static var inspectionWorkoutExerciseFetchRequest: NSFetchRequest<WorkoutExercise> {
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(
            format: "\(#keyPath(WorkoutExercise.workout.isCurrentWorkout)) != %@",
            NSNumber(booleanLiteral: true)
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \WorkoutExercise.workout?.start, ascending: false)
        ]
        return request
    }

    private static var inspectionCompletedWorkoutFetchRequest: NSFetchRequest<Workout> {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(
            format: "\(#keyPath(Workout.isCurrentWorkout)) != %@",
            NSNumber(booleanLiteral: true)
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Workout.start, ascending: false)
        ]
        return request
    }

    private var inspectionCompletedWorkout: Workout? {
        inspectionCompletedWorkouts.first(where: { $0.hasCompletedSets ?? false })
    }

    private var inspectionWorkoutExercise: WorkoutExercise? {
        inspectionWorkoutExercises.first(where: { ($0.numberOfCompletedSets ?? 0) > 1 })
            ?? inspectionWorkoutExercises.first
    }

    private var inspectionEmptyExercise: Exercise? {
        let workoutExerciseIDs = Set(
            inspectionWorkoutExercises.compactMap { $0.exercise(in: exerciseStore.exercises)?.uuid }
        )
        return exerciseStore.exercises.first { !workoutExerciseIDs.contains($0.uuid) }
    }

    private static let inspectionEmptyContext = makeInspectionContext(imported: false)
    private static let inspectionImportedContext = makeInspectionContext(imported: true)

    /// Screen fixtures are disposable: QA never removes or replaces the user's store.
    private static func makeInspectionContext(imported: Bool) -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "IronInspection", managedObjectModel: WorkoutDataStorage.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in precondition(error == nil) }
        let context = container.viewContext
        if imported {
            for (index, time) in [1_570_000_000.0, 1_650_000_000.0, 1_792_800_000.0].enumerated() {
                let workout = Workout.create(context: context)
                workout.title = "Imported Workout \(index + 1)"
                workout.importSource = "hevy"
                workout.start = Date(timeIntervalSince1970: time)
                workout.end = workout.start?.addingTimeInterval(3_600)
            }
            let native = Workout.create(context: context)
            native.title = "Logged in Light"
            native.start = Date(timeIntervalSince1970: 1_792_850_000)
            native.end = native.start?.addingTimeInterval(3_600)
            context.saveOrCrash()
        }
        return context
    }
    #endif

    @ViewBuilder
    private var tabView: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $sceneState.selectedTab) {
                Tab("Home", systemImage: "house.fill", value: SceneState.Tab.home) {
                    FeedView()
                }
                Tab("History", systemImage: "clock.arrow.circlepath", value: SceneState.Tab.history) {
                    HistoryView()
                }
                Tab("Workout", systemImage: "dumbbell.fill", value: SceneState.Tab.workout) {
                    WorkoutTab {
                        withAnimation(activeWorkoutTransition) {
                            sceneState.selectedTab = .workout
                            sceneState.isCurrentWorkoutExpanded = true
                        }
                    }
                }
                Tab("Exercises", systemImage: "figure.strengthtraining.traditional", value: SceneState.Tab.exercises) {
                    NavigationStack {
                        ExerciseMuscleGroupsView()
                    }
                }
                Tab("Settings", systemImage: "gearshape.fill", value: SceneState.Tab.settings) {
                    SettingsView()
                }
                .tabPlacement(hasActiveWorkout ? .pinned : .automatic)
            }
            .productionEnvironment()
        } else {
            TabView(selection: $sceneState.selectedTab) {
                FeedView()
                    .tag(SceneState.Tab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                HistoryView()
                    .tag(SceneState.Tab.history)
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                WorkoutTab {
                    withAnimation(activeWorkoutTransition) {
                        sceneState.selectedTab = .workout
                        sceneState.isCurrentWorkoutExpanded = true
                    }
                }
                    .tag(SceneState.Tab.workout)
                    .tabItem {
                        Label("Workout", systemImage: "dumbbell.fill")
                    }

                NavigationStack {
                    ExerciseMuscleGroupsView()
                }
                    .tag(SceneState.Tab.exercises)
                    .tabItem {
                        Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                    }

                SettingsView()
                    .tag(SceneState.Tab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .productionEnvironment()
        }
    }
}

@available(iOS 26.1, *)
private struct AdaptiveWorkoutTabAccessory<Expanded: View, Inline: View>: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @ViewBuilder let expanded: () -> Expanded
    @ViewBuilder let inline: () -> Inline

    var body: some View {
        if placement == .inline {
            inline()
        } else {
            expanded()
        }
    }
}

private extension View {
    func productionEnvironment() -> some View {
        self
            .environmentObject(SettingsStore.shared)
            .environmentObject(RestTimerStore.shared)
            .environmentObject(ExerciseStore.shared)
            .environmentObject(PinnedChartsStore.shared)
            .environment(\.managedObjectContext, WorkoutDataStorage.shared.persistentContainer.viewContext)
    }
}

#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
