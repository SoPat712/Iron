//
//  RestoreBackupView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 28.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct RestoreBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var exerciseStore: ExerciseStore

    @ObservedObject var backupStore: BackupFileStore

    private struct BackupModal: Identifiable {
        enum Kind {
            case restoreConfirmation(URL)
            case deleteConfirmation(URL)
            case restoreResult(RestoreActionSheet.RestoreResult)
            case deleteError(Error)
        }

        let id = UUID()
        let kind: Kind
    }

    @State private var activeModal: BackupModal?
    @State private var modalAfterDismiss: BackupModal?
    @State private var isEditing = false
    @State private var isRestoring = false

    var body: some View {
        ZStack {
            IronScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        IronSectionTitle(title: "Backups", detail: backupStatusTitle)
                        restoreScopeCard
                    }
                    .padding(.horizontal, IronTheme.horizontalPadding)

                    backupContent
                }
                .padding(.top, 14)
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                editButton
            }
        }
        .onAppear(perform: backupStore.fetchBackups)
        .allowsHitTesting(!isRestoring)
        .overlay {
            if isRestoring {
                restoreProgressOverlay
                    .transition(.opacity)
            }
        }
        .sheet(item: $activeModal, onDismiss: presentQueuedModal) { modal in
            switch modal.kind {
            case .restoreConfirmation(let url):
                IronConfirmationSheet(
                    title: RestoreActionSheet.confirmationTitle,
                    message: RestoreActionSheet.confirmationMessage,
                    confirmTitle: "Restore Backup",
                    systemImage: "arrow.counterclockwise.icloud.fill",
                    secondaryTitle: "Keep Current Data",
                    onCancel: { activeModal = nil },
                    onConfirm: { restoreBackup(at: url) }
                )
                .presentationDetents([.height(410), .medium])
                .presentationDragIndicator(.visible)

            case .deleteConfirmation(let url):
                IronConfirmationSheet(
                    title: "Delete this backup?",
                    message: "This removes only the selected iCloud backup. Other backups and your current Iron data are not changed.",
                    confirmTitle: "Delete Backup",
                    systemImage: "trash.fill",
                    secondaryTitle: "Keep Backup",
                    onCancel: { activeModal = nil },
                    onConfirm: { deleteBackup(at: url) }
                )
                .presentationDetents([.height(410), .medium])
                .presentationDragIndicator(.visible)

            case .restoreResult(let result):
                let details = RestoreActionSheet.restoreResultDetails(result)
                IronStatusSheet(
                    headerTitle: "Restore",
                    title: details.title,
                    message: details.message,
                    systemImage: details.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: details.isSuccess ? IronTheme.success : IronTheme.danger
                )

            case .deleteError(let error):
                IronStatusSheet(
                    headerTitle: "Backups",
                    title: "Could not delete backup",
                    message: error.localizedDescription,
                    systemImage: "trash.slash.fill",
                    tint: IronTheme.danger
                )
            }
        }
        .ironScreen()
    }

    private var restoreProgressOverlay: some View {
        ZStack {
            IronTheme.background.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 13) {
                ProgressView()
                    .controlSize(.large)
                    .tint(IronTheme.accent)
                Text("Restoring your data")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Keep Iron open while workouts and measurements are replaced.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 290)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .fill(IronTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                    .stroke(IronTheme.outline.opacity(0.45), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Restoring your Iron data")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var editButton: some View {
        Group {
            if backupStore.loadState == .loaded, !backupStore.backups.isEmpty {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation {
                        isEditing.toggle()
                    }
                }
            }
        }
    }

    private var backupStatusTitle: String {
        switch backupStore.loadState {
        case .idle, .loading:
            return "CHECKING"
        case .unavailable:
            return "UNAVAILABLE"
        case .loaded:
            return backupStore.backups.isEmpty ? "EMPTY" : "\(backupStore.backups.count) SAVED"
        }
    }

    @ViewBuilder
    private var backupContent: some View {
        switch backupStore.loadState {
        case .idle, .loading:
            loadingState
        case .unavailable(let message):
            unavailableState(message: message)
        case .loaded:
            if backupStore.backups.isEmpty {
                emptyState
            } else {
                backupsCard
            }
        }
    }

    private var backupsCard: some View {
        IronCard(padding: 0) {
            LazyVStack(spacing: 0) {
                ForEach(backupStore.backups.indices, id: \.self) { index in
                    let backup = backupStore.backups[index]
                    backupRow(backup)

                    if index != backupStore.backups.indices.last {
                        IronHairline(opacity: 0.35)
                            .padding(.leading, 58)
                    }
                }
            }
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private var emptyState: some View {
        IronCard {
            VStack(spacing: 13) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(IronTheme.accentSoft))
                Text("No iCloud backups yet")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Create your first private backup, then return here whenever you need to restore it.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: { dismiss() }) {
                    Label("Back to Backup & Export", systemImage: "arrow.left")
                }
                .buttonStyle(IronSecondaryButtonStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private var loadingState: some View {
        IronCard {
            VStack(spacing: 13) {
                ProgressView()
                    .tint(IronTheme.accent)
                    .frame(width: 58, height: 58)
                Text("Checking iCloud Drive")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Looking for private Iron backups saved by your devices…")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private func unavailableState(message: String) -> some View {
        IronCard {
            VStack(spacing: 13) {
                Image(systemName: "icloud.slash.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(IronTheme.warning)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(IronTheme.warning.opacity(0.14)))
                Text("iCloud Drive unavailable")
                    .font(.headline.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: backupStore.fetchBackups) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(IronSecondaryButtonStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
    }

    private var restoreScopeCard: some View {
        IronCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(IronTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(IronTheme.accentSoft)
                    .clipShape(
                        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your current session stays safe")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(IronTheme.primaryText)
                    Text("A restore replaces completed workouts, saved workouts, custom exercises, and body measurements. Settings and any workout in progress stay unchanged.")
                        .font(.caption)
                        .foregroundColor(IronTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func backupRow(_ backup: BackupFileStore.BackupFile) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                activeModal = BackupModal(kind: .restoreConfirmation(backup.url))
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(IronTheme.accent)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BackupFileStore.BackupFile.dateFormatter.string(from: backup.creationDate))
                            .font(.body.weight(.medium))
                            .foregroundColor(IronTheme.primaryText)
                            .lineLimit(1)
                        Text("\(backup.deviceName) • \(BackupFileStore.BackupFile.byteCountFormatter.string(fromByteCount: Int64(backup.fileSize)))")
                            .font(.caption)
                            .foregroundColor(IronTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(IronTheme.tertiaryText)
                    }
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                Button(action: {
                    activeModal = BackupModal(kind: .deleteConfirmation(backup.url))
                }) {
                    Image(systemName: "trash.fill")
                }
                .buttonStyle(IronIconButtonStyle())
                .foregroundColor(IronTheme.danger)
                .accessibilityLabel(Text("Delete backup"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func restoreBackup(at url: URL) {
        guard !isRestoring else { return }
        isRestoring = true
        activeModal = nil

        // Let the confirmation sheet finish dismissing and render the progress
        // surface before the Core Data replacement starts on its required queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            RestoreActionSheet.restore(
                context: managedObjectContext,
                exerciseStore: exerciseStore,
                data: { try Data(contentsOf: url) }
            ) { result in
                isRestoring = false
                activeModal = BackupModal(kind: .restoreResult(result))
            }
        }
    }

    private func deleteBackup(at url: URL) {
        guard let index = backupStore.backups.firstIndex(where: { $0.url == url }) else {
            activeModal = nil
            return
        }
        do {
            try backupStore.delete(at: index)
        } catch {
            modalAfterDismiss = BackupModal(kind: .deleteError(error))
        }
        activeModal = nil
        if backupStore.backups.isEmpty {
            isEditing = false
        }
    }

    private func presentQueuedModal() {
        guard let nextModal = modalAfterDismiss else { return }
        modalAfterDismiss = nil
        DispatchQueue.main.async {
            activeModal = nextModal
        }
    }
}

import CoreData
enum RestoreActionSheet {
    typealias RestoreResult = Result<Void, Error>

    static let confirmationTitle = "Restore this backup?"
    static let confirmationMessage = "Completed workouts, saved workouts, custom exercises, and saved body measurements will be replaced with the backup. Settings and any workout in progress stay unchanged. This cannot be undone."

    static func restore(
        context: NSManagedObjectContext,
        exerciseStore: ExerciseStore,
        data: @escaping () throws -> Data,
        completion: @escaping (RestoreResult) -> Void
    ) {
        do {
            try IronBackup.restoreBackupData(
                data: data(),
                managedObjectContext: context,
                exerciseStore: exerciseStore
            )
            BodyMetricsStore.shared.reload()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    static func restoreResultDetails(_ restoreResult: RestoreResult) -> (title: String, message: String, isSuccess: Bool) {
        switch restoreResult {
        case .success():
            return (
                "Restore complete",
                "Your completed workouts, saved workouts, custom exercises, and body measurements are ready.",
                true
            )
        case .failure(let error):
            let errorMessage: String
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case let .dataCorrupted(context):
                    errorMessage = "Data corrupted. \(context.debugDescription)"
                case let .keyNotFound(_, context):
                    errorMessage = "Key not found. \(context.debugDescription)"
                case let .typeMismatch(_, context):
                    errorMessage = "Type mismatch. \(context.debugDescription)"
                case let .valueNotFound(_, context):
                    errorMessage = "Value not found. \(context.debugDescription)"
                @unknown default:
                    errorMessage = "Decoding error. \(error.localizedDescription)"
                }
            } else {
                errorMessage = error.localizedDescription
            }
            return ("Restore failed", errorMessage, false)
        }
    }
}
