import CryptoKit
import Foundation
import Observation

/// Downloads, checks and removes the local language models. Every file is compared with
/// its checksum before it is used; a model counts as installed only once all files are in
/// place and a marker with its revision is written.
@Observable
@MainActor
final class LocalModelStore {
    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)
    }

    enum Failure: LocalizedError {
        case notEnoughSpace(needed: Int64, free: Int64)
        case checksum(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notEnoughSpace(let needed, let free):
                return "Zu wenig Speicherplatz: Das Modell braucht \(LocalModelStore.gigabytes(needed)), frei sind \(LocalModelStore.gigabytes(free))."
            case .checksum(let file):
                return "\(file) kam besch\u{00E4}digt an. Bitte noch einmal laden."
            case .http(let status):
                return "Der Download wurde abgelehnt (HTTP \(status)). Bitte sp\u{00E4}ter noch einmal versuchen."
            }
        }
    }

    static let shared = LocalModelStore()

    private(set) var states: [String: State] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        for variant in LocalModelVariant.all {
            states[variant.id] = Self.isInstalled(variant) ? .installed : .notInstalled
        }
    }

    func state(of variant: LocalModelVariant) -> State {
        states[variant.id] ?? .notInstalled
    }

    /// What meeting summaries use: the largest installed model this Mac can run.
    var preferredInstalled: LocalModelVariant? {
        LocalModelVariant.all.last { state(of: $0) == .installed && $0.support() == .available }
    }

    func download(_ variant: LocalModelVariant) {
        guard tasks[variant.id] == nil, variant.support() == .available else { return }
        if let free = Self.freeSpace, free < variant.downloadSize + Self.spaceMargin {
            states[variant.id] = .failed(Failure.notEnoughSpace(needed: variant.downloadSize + Self.spaceMargin, free: free).localizedDescription)
            return
        }
        states[variant.id] = .downloading(0)
        tasks[variant.id] = Task { [weak self] in
            do {
                try await Self.install(variant) { fraction in
                    Task { @MainActor in
                        if case .downloading = self?.states[variant.id] { self?.states[variant.id] = .downloading(fraction) }
                    }
                }
                self?.states[variant.id] = .installed
            } catch is CancellationError {
                self?.states[variant.id] = .notInstalled
            } catch let error as URLError where error.code == .cancelled {
                self?.states[variant.id] = .notInstalled
            } catch {
                self?.states[variant.id] = .failed(error.localizedDescription)
            }
            self?.tasks[variant.id] = nil
        }
    }

    /// Stops a running download. Files that arrived complete stay and are not loaded again.
    func cancel(_ variant: LocalModelVariant) {
        tasks[variant.id]?.cancel()
    }

    func remove(_ variant: LocalModelVariant) {
        cancel(variant)
        try? FileManager.default.removeItem(at: Self.folder(for: variant))
        states[variant.id] = .notInstalled
    }

    // MARK: - Files

    /// Room left on the disk after the download, so the Mac does not run full.
    private static let spaceMargin: Int64 = 2_000_000_000

    nonisolated static var directoryURL: URL {
        AppSupportPaths.localModelsDirectoryURL.appendingPathComponent("llm", isDirectory: true)
    }

    nonisolated static func folder(for variant: LocalModelVariant) -> URL {
        directoryURL.appendingPathComponent(variant.id, isDirectory: true)
    }

    nonisolated private static func marker(for variant: LocalModelVariant) -> URL {
        folder(for: variant).appendingPathComponent(".installed")
    }

    nonisolated static func isInstalled(_ variant: LocalModelVariant) -> Bool {
        (try? String(contentsOf: marker(for: variant), encoding: .utf8)) == variant.revision
    }

    nonisolated private static var freeSpace: Int64? {
        let url = AppSupportPaths.appSupportDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    nonisolated private static func install(_ variant: LocalModelVariant, progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = folder(for: variant)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: marker(for: variant))
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var parent = directoryURL
        try? parent.setResourceValues(excluded)

        let total = Double(variant.downloadSize)
        var done: Int64 = 0
        for file in variant.files {
            try Task.checkCancellation()
            let target = folder.appendingPathComponent(file.name)
            if size(of: target) == file.size, (try? sha256(of: target)) == file.sha256 {
                done += file.size
                progress(Double(done) / total)
                continue
            }
            let finished = done
            let downloaded = try await FileDownload.load(variant.url(for: file)) { written in
                progress((Double(finished) + Double(written)) / total)
            }
            guard size(of: downloaded) == file.size, try sha256(of: downloaded) == file.sha256 else {
                try? FileManager.default.removeItem(at: downloaded)
                throw Failure.checksum(file.name)
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: downloaded, to: target)
            done += file.size
            progress(Double(done) / total)
        }
        try variant.revision.write(to: marker(for: variant), atomically: true, encoding: .utf8)
    }

    nonisolated private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// "5,2 GB"
    nonisolated static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }
}

/// One file over URLSession with progress, cancelled together with the Swift task.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let progress: @Sendable (Int64) -> Void
    private var lastReport = Date.distantPast

    private init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    static func load(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = FileDownload(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard Date().timeIntervalSince(lastReport) > 0.25 else { return }
        lastReport = Date()
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
            finish(.failure(LocalModelStore.Failure.http(status)))
            return
        }
        // The file at `location` goes away when this returns, so keep it first.
        let kept = LocalModelStore.directoryURL.appendingPathComponent(".download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
