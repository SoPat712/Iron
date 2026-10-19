//
//  BackupAndExportView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import WorkoutDataKit
import os.log
import UniformTypeIdentifiers

struct BackupAndExportView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore

    @ObservedObject var backupStore = BackupFileStore.shared

    @State private var operationError: DataOperationError?
    private struct DataOperationError: Identifiable {
        let id = UUID()
        let title: String
        let error: Error
    }

    @State private var activityItems: [Any]?
    @State private var isShowingCSVImporter = false
    @State private var hevyImportOutcome: HevyCSVImportOutcome?
    @State private var isCreatingCloudBackup = false
    @State private var cloudBackupSucceeded = false

    private var cloudBackupFooterText: String {
        var strings = [String]()
        if settingsStore.autoBackup {
            strings.append("Iron attempts an automatic backup when iOS closes the app.")
        }
        strings.append("Backups are stored in Iron's app folder in your iCloud Drive. Only the last backup of each day is kept, and the files are also available from the Files app.")
        if let creationDate = backupStore.lastBackup?.creationDate {
            strings.append("Last backup: " + BackupFileStore.BackupFile.dateFormatter.string(from: creationDate))
        }

        return strings.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                nativeSummaryRow(
                    title: "Bring everything into Iron",
                    detail: "Imports one or both Hevy CSV files automatically.",
                    systemImage: "square.and.arrow.down"
                )

                Button(action: { isShowingCSVImporter = true }) {
                    Label("Choose CSV from Files", systemImage: "folder")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Choose workout_data.csv, measurement_data.csv, or both. Iron detects each file automatically.")
            }

            Section {
                nativeSummaryRow(
                    title: "Take your data with you",
                    detail: "Share Hevy-compatible CSV files or a complete Iron backup.",
                    systemImage: "square.and.arrow.up"
                )

                Button(action: exportHevyWorkoutCSV) {
                    Label("Workouts (Hevy CSV)", systemImage: "tablecells")
                }
                Button(action: exportHevyMeasurementCSV) {
                    Label("Measurements (Hevy CSV)", systemImage: "ruler")
                }

                Menu {
                    Button(action: exportWorkoutDataJSON) {
                        Label("JSON", systemImage: "curlybraces")
                    }
                    Button(action: exportWorkoutDataText) {
                        Label("Plain Text", systemImage: "doc.plaintext")
                    }
                } label: {
                    Label("Other export formats", systemImage: "ellipsis.circle")
                }

                Button(action: createAndShareBackup) {
                    Label("Share Full Backup", systemImage: "archivebox")
                }
            } header: {
                Text("Export")
            }

            Section {
                nativeCloudBackupContent
            } header: {
                Text("iCloud Backup")
            } footer: {
                Text(cloudBackupFooterText)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 36)
        }
        .onAppear(perform: backupStore.fetchBackups)
        .navigationTitle("Backup & Export")
        .navigationBarTitleDisplayMode(.inline)
        .ironScreen()
        .alert(item: $operationError) { operationError in
            Alert(
                title: Text(operationError.title),
                message: Text(operationError.error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Backup created", isPresented: $cloudBackupSucceeded) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your latest Iron data is now stored in iCloud Drive and is available from Restore Backup or the Files app.")
        }
        .ironActivitySheet(activityItems: $activityItems)
        .fileImporter(
            isPresented: $isShowingCSVImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true,
            onCompletion: importCSV
        )
        .sheet(item: $hevyImportOutcome) { outcome in
            HevyCSVImportResultSheet(outcome: outcome)
        }
    }

    private func nativeSummaryRow(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var nativeCloudBackupContent: some View {
        switch backupStore.loadState {
        case .idle, .loading:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checking iCloud Drive")
                    Text("Looking for Iron backups saved by your devices…")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                }
            } icon: {
                ProgressView()
            }

        case .unavailable(let message):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Drive unavailable")
                    Text(message)
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "icloud.slash")
                    .foregroundColor(IronTheme.warning)
            }

            Button(action: backupStore.fetchBackups) {
                Label("Try iCloud Again", systemImage: "arrow.clockwise")
            }

        case .loaded:
            if backupStore.lastBackup != nil {
                NavigationLink(destination: RestoreBackupView(backupStore: backupStore)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore from iCloud")
                            Text(restoreAvailabilityText)
                                .font(.caption)
                                .foregroundColor(IronTheme.secondaryText)
                        }
                    } icon: {
                        Image(systemName: "arrow.counterclockwise.icloud")
                            .foregroundColor(IronTheme.accent)
                    }
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore from iCloud")
                        Text("No saved backups yet")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                } icon: {
                    Image(systemName: "icloud.slash")
                        .foregroundColor(IronTheme.tertiaryText)
                }
                .foregroundColor(IronTheme.secondaryText)
            }

            Toggle(isOn: $settingsStore.autoBackup) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic backups")
                        Text("Attempt a backup when Iron closes")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(settingsStore.autoBackup ? IronTheme.accent : IronTheme.secondaryText)
                }
            }
            .tint(IronTheme.accent)

            Button(action: createCloudBackup) {
                HStack(spacing: 8) {
                    if isCreatingCloudBackup {
                        ProgressView()
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                    Text(isCreatingCloudBackup ? "Creating Backup…" : "Back Up Now")
                }
            }
            .disabled(isCreatingCloudBackup)
        }
    }

    private var restoreAvailabilityText: String {
        guard let creationDate = backupStore.lastBackup?.creationDate else {
            return "No saved backups yet"
        }
        return "Latest: \(BackupFileStore.BackupFile.dateFormatter.string(from: creationDate))"
    }

    private func createAndShareBackup() {
        do {
            os_log("Creating backup data", log: .backup, type: .default)
            let data = try IronBackup.createBackupData(managedObjectContext: managedObjectContext, exerciseStore: exerciseStore)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let url = try tempFile(data: data, name: "\(formatter.string(from: Date())).ironbackup")

            shareFile(url: url)
        } catch {
            os_log("Could not create backup: %@", log: .backup, type: .default, error.localizedDescription)
            operationError = DataOperationError(title: "Could Not Create Backup", error: error)
        }
    }

    private func importCSV(_ selection: Result<[URL], Error>) {
        if case .failure(let error) = selection,
           (error as NSError).code == NSUserCancelledError {
            return
        }

        do {
            let urls = try selection.get()
            guard !urls.isEmpty else { return }
            let dataDocuments = try urls.map { url -> Data in
                let isSecurityScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
                }
                return try Data(contentsOf: url)
            }

            Task {
                hevyImportOutcome = await HevyImportController.shared.run(
                    dataDocuments,
                    into: managedObjectContext,
                    exerciseStore: exerciseStore
                )
            }
        } catch {
            hevyImportOutcome = HevyCSVImportOutcome(result: .failure(error))
        }
    }

    private func exportHevyWorkoutCSV() {
        do {
            let workouts = try fetchWorkouts()
            let data = try HevyCSV.exportData(
                workouts: workouts,
                exercises: exerciseStore.exercises,
                weightUnit: settingsStore.weightUnit
            )
            shareFile(url: try tempFile(data: data, name: "workout_data.csv"))
        } catch {
            operationError = DataOperationError(title: "Could Not Export Workout Data", error: error)
        }
    }

    private func exportHevyMeasurementCSV() {
        do {
            let data = try HevyCSV.exportMeasurementData(
                entries: BodyMetricsStore.shared.entries,
                weightUnit: settingsStore.weightUnit
            )
            shareFile(url: try tempFile(data: data, name: "measurement_data.csv"))
        } catch {
            operationError = DataOperationError(title: "Could Not Export Measurements", error: error)
        }
    }

    private func exportWorkoutDataJSON() {
        do {
            let workouts = try fetchWorkouts()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            if let exercisesKey = CodingUserInfoKey.exercisesKey {
                encoder.userInfo[exercisesKey] = ExerciseStore.shared.exercises
            }
            let data = try encoder.encode(workouts)
            shareFile(url: try tempFile(data: data, name: "workout_data.json"))
        } catch {
            operationError = DataOperationError(title: "Could Not Export Workout Data", error: error)
        }
    }

    private func exportWorkoutDataText() {
        do {
            let workouts = try fetchWorkouts()
            let text = workouts
                .compactMap { $0.logText(in: exerciseStore.exercises, weightUnit: settingsStore.weightUnit) }
                .joined(separator: "\n\n\n\n\n")
            let data = Data(text.utf8)
            shareFile(url: try tempFile(data: data, name: "workout_data.txt"))
        } catch {
            operationError = DataOperationError(title: "Could Not Export Workout Data", error: error)
        }
    }

    private func createCloudBackup() {
        guard !isCreatingCloudBackup else { return }
        isCreatingCloudBackup = true
        backupStore.create(data: {
            try self.managedObjectContext.performAndWait { context in
                os_log("Creating backup data", log: .backup, type: .default)
                return try IronBackup.createBackupData(managedObjectContext: context, exerciseStore: self.exerciseStore)
            }
        }, onSuccess: { _ in
            DispatchQueue.main.async {
                self.isCreatingCloudBackup = false
                self.cloudBackupSucceeded = true
            }
        }, onError: { error in
            DispatchQueue.main.async {
                self.isCreatingCloudBackup = false
                self.operationError = DataOperationError(title: "Could Not Create iCloud Backup", error: error)
            }
        })
    }

    private func fetchWorkouts() throws -> [Workout] {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "\(#keyPath(Workout.isCurrentWorkout)) != %@", NSNumber(booleanLiteral: true))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.start, ascending: false)]
        return try managedObjectContext.fetch(request)
    }

    private func tempFile(data: Data, name: String) throws -> URL {
        let path = FileManager.default.temporaryDirectory
        let url = path.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func shareFile(url: URL) {
        activityItems = [url]
    }
}

#if DEBUG
struct BackupAndExportView_Previews: PreviewProvider {
    static var previews: some View {
        BackupAndExportView()
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
