//
//  ExerciseMediaStore.swift
//  Iron
//
//  Persistent on-device cache for ExerciseDB / Gym Visual GIFs.
//  Files are written once and never evicted so the library works offline
//  after the first successful download.
//

import Foundation
import os.log
import WorkoutDataKit

final class ExerciseMediaStore {
    static let shared = ExerciseMediaStore()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.joshpatra.Iron.exercise-media", qos: .utility)
    private let log = OSLog(subsystem: "com.joshpatra.Iron", category: "exercise-media")

    /// On-demand fetches (opening an exercise) may use cellular.
    private let interactiveSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Catalog prefetch waits for an inexpensive path (Wi-Fi) and never deletes files.
    private let prefetchSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private var prefetchTask: Task<Void, Never>?

    private init() {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private var directoryURL: URL {
        fileManager.appGroupContainerApplicationSupportURL
            .appendingPathComponent("ExerciseMedia", isDirectory: true)
    }

    func fileURL(for remoteURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheFileName(for: remoteURL), isDirectory: false)
    }

    func cachedData(for remoteURL: URL) -> Data? {
        let url = fileURL(for: remoteURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Returns persisted bytes, downloading and storing them when missing.
    func data(for remoteURL: URL) async -> Data? {
        if let cached = cachedData(for: remoteURL) {
            return cached
        }
        return await download(remoteURL, session: interactiveSession)
    }

    /// Fills any missing catalogue GIFs in the background. Safe to call on every launch.
    func prefetchCatalogue(from exercises: [Exercise]) {
        prefetchTask?.cancel()
        let urls = uniqueMediaURLs(in: exercises)
        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for url in urls {
                if Task.isCancelled { return }
                if self.cachedData(for: url) != nil { continue }
                _ = await self.download(url, session: self.prefetchSession)
            }
        }
    }

    private func uniqueMediaURLs(in exercises: [Exercise]) -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        urls.reserveCapacity(exercises.count)
        for exercise in exercises {
            guard let url = exercise.imageURL ?? exercise.animationURL else { continue }
            if seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func download(_ remoteURL: URL, session: URLSession) async -> Data? {
        if let cached = cachedData(for: remoteURL) {
            return cached
        }

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
            os_log("Exercise media download failed for %{public}@: %{public}@", log: log, type: .info, remoteURL.absoluteString, error.localizedDescription)
            return cachedData(for: remoteURL)
        }
    }

    private func persist(_ data: Data, for remoteURL: URL) {
        let destination = fileURL(for: remoteURL)
        if fileManager.fileExists(atPath: destination.path) { return }

        ioQueue.sync {
            if fileManager.fileExists(atPath: destination.path) { return }
            let temporary = destination.appendingPathExtension("tmp")
            do {
                try data.write(to: temporary, options: .atomic)
                if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: temporary)
                    return
                }
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.removeItem(at: temporary)
                os_log("Could not persist exercise media: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
    }

    private func cacheFileName(for remoteURL: URL) -> String {
        let last = remoteURL.lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let filtered = last.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(filtered)
        if name.isEmpty || name == "." || name == ".." {
            return String(remoteURL.absoluteString.hashValue) + ".gif"
        }
        return name
    }
}
