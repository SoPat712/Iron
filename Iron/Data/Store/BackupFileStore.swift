//
//  BackupFileStore.swift
//  Iron
//
//  Created by Karim Abou Zeid on 28.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import UIKit
import os.log

class BackupFileStore: ObservableObject {
    static let shared = BackupFileStore()
    private static let maximumDownloadPollAttempts = 15
    
    private init() {}
    
    struct BackupFile: Identifiable {
        let url: URL
        let creationDate: Date
        let fileSize: Int
        let deviceName: String
        
        var id: URL { url }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable(String)
    }
    
    @Published var backups = [BackupFile]()
    @Published private(set) var loadState: LoadState = .idle
    
    func fetchBackups() {
        fetchBackups(downloadPollAttempt: 0)
    }

    private func fetchBackups(downloadPollAttempt: Int) {
        os_log("Fetching backup file list", log: .backup, type: .default)
        DispatchQueue.main.async {
            self.loadState = .loading
        }

        UbiquityContainer.backupsUrl { result in
            let url: URL
            do {
                url = try result.get()
            } catch {
                self.finishLoading(with: .unavailable(Self.availabilityMessage(for: error)), backups: [])
                return
            }
            
            let deviceDirectoryUrls: [URL]
            do {
                deviceDirectoryUrls = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .nameKey]
                )
            } catch {
                self.finishLoading(with: .unavailable(Self.availabilityMessage(for: error)), backups: [])
                return
            }

            var startedDownloads = false
            let backups: [[BackupFile]] = deviceDirectoryUrls.compactMap { deviceDirectoryUrl in
                guard let resourceValues = try? deviceDirectoryUrl.resourceValues(forKeys: [.isDirectoryKey, .nameKey]) else { return nil }
                guard resourceValues.isDirectory ?? false else { return nil }
                guard let deviceName = resourceValues.name else { return nil }
                
                guard let backupUrls = try? FileManager.default.contentsOfDirectory(at: deviceDirectoryUrl, includingPropertiesForKeys: [.typeIdentifierKey, .creationDateKey, .totalFileSizeKey]) else { return nil }
                return backupUrls.compactMap { backupUrl in
                    guard let resourceValues = try? backupUrl.resourceValues(forKeys: [.typeIdentifierKey, .creationDateKey, .totalFileSizeKey]) else { return nil }
                    guard let uti = resourceValues.typeIdentifier else { return nil }
                    if uti == "com.apple.icloud-file-fault" {
                        do {
                            // if there are undownloaded files, download them and call fetchBackups() again after a short delay
                            os_log("Starting download of iCloud file %@", log: .backup, type: .default, backupUrl.path)
                            try FileManager.default.startDownloadingUbiquitousItem(at: backupUrl)
                            startedDownloads = true
                        } catch {
                            os_log("Could not download iCloud file %@:", log: .backup, type: .fault, backupUrl.path, error.localizedDescription)
                        }
                    }
                    guard uti == "com.kabouzeid.ironbackup" else { return nil }
                    guard let creationDate = resourceValues.creationDate else { return nil }
                    guard let totalFileSize = resourceValues.totalFileSize else { return nil }
                    return BackupFile(url: backupUrl, creationDate: creationDate, fileSize: totalFileSize, deviceName: deviceName)
                }
            }

            let sortedBackups = backups
                .flatMap { $0 }
                .sorted { $0.creationDate > $1.creationDate }
            if startedDownloads {
                guard downloadPollAttempt < Self.maximumDownloadPollAttempts else {
                    self.finishLoading(
                        with: .unavailable(
                            "Some iCloud backups are taking longer than expected to download. Check your connection, then try again."
                        ),
                        backups: sortedBackups
                    )
                    return
                }

                self.finishLoading(with: .loading, backups: sortedBackups)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(1)) {
                    self.fetchBackups(downloadPollAttempt: downloadPollAttempt + 1)
                }
            } else {
                self.finishLoading(with: .loaded, backups: sortedBackups)
            }
        }
    }

    private func finishLoading(with state: LoadState, backups: [BackupFile]) {
        DispatchQueue.main.async {
            self.backups = backups
            self.loadState = state
        }
    }

    private static func availabilityMessage(for error: Error) -> String {
        if error is UbiquityContainer.UbiquityContainerError {
            return "iCloud Drive is not available to Iron. Check that you are signed in to iCloud and that iCloud Drive is enabled, then try again."
        }

        os_log(
            "Could not read iCloud backups: %@",
            log: .backup,
            type: .error,
            error.localizedDescription
        )
        return "Iron could not read its iCloud backup folder. Check your connection and iCloud Drive, then try again."
    }
}

// MARK: - Create / Delete Backup
extension BackupFileStore {
    func delete(at index: Int) throws {
        guard index < backups.count else { return }
        try FileManager.default.removeItem(at: backups[index].url)
        backups.remove(at: index)
    }
    
    func create(
        data: @escaping () throws -> Data,
        onSuccess: @escaping (URL) -> Void = { _ in },
        onError: @escaping (Error) -> Void
    ) {
        Self.create(data: data) { result in
            switch result {
            case .success(let url):
                self.fetchBackups()
                onSuccess(url)
            case .failure(let error):
                onError(error)
            }
        }
    }
    
    // data in closure so it is computed on the background thread and only if necessary
    static func create(data: @escaping () throws -> Data, completion: @escaping (Result<URL, Error>) -> Void) {
        UbiquityContainer.backupsUrl { result in
            do {
                let backupsUrl = try result.get()
                let deviceName = UIDevice.current.name
                    .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.illegalCharacters))
                    .joined(separator: "")
                    .components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                var deviceBackupUrl = backupsUrl.appendingPathComponent(deviceName)
                
                if !FileManager.default.fileExists(atPath: deviceBackupUrl.path) {
                    do {
                        os_log("Creating device backup folder", log: .backup, type: .default)
                        try FileManager.default.createDirectory(at: deviceBackupUrl, withIntermediateDirectories: false)
                        os_log("Successfully created device backup folder", log: .backup, type: .info)
                    } catch {
                        os_log("Could not create device backup folder, falling back to creating folder for \"Unknown Device\"", log: .backup, type: .error)
                        deviceBackupUrl = backupsUrl.appendingPathComponent("Unknown Device")
                        if !FileManager.default.fileExists(atPath: deviceBackupUrl.path) {
                            try FileManager.default.createDirectory(at: deviceBackupUrl, withIntermediateDirectories: false)
                        }
                    }
                }
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let fileUrl = deviceBackupUrl.appendingPathComponent(formatter.string(from: Date())).appendingPathExtension("ironbackup")
                
                os_log("Saving backup to %@", log: .backup, type: .default, fileUrl as NSURL)
                try data().write(to: fileUrl, options: .atomic)
                
                completion(.success(fileUrl))
            } catch {
                os_log("Could not create backup: %@", log: .backup, type: .error, error.localizedDescription)
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Misc
extension BackupFileStore {
    var lastBackup: BackupFile? {
        backups.first // assume backups are sorted
    }
}

// MARK: - Formatters
extension BackupFileStore.BackupFile {
    static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true
        return dateFormatter
    }()
    
    static let byteCountFormatter: ByteCountFormatter = {
        ByteCountFormatter()
    }()
}
