import Foundation
import CryptoKit

public struct DownloadProgress: Sendable {
    public var received: Int64
    public var total: Int64?
    public var bytesPerSecond: Double
    public var fraction: Double? { total.flatMap { $0 > 0 ? min(1, Double(received)/Double($0)) : nil } }
    public init(received: Int64 = 0, total: Int64? = nil, bytesPerSecond: Double = 0) { self.received = received; self.total = total; self.bytesPerSecond = bytesPerSecond }
}
/// A single-use, cancellable transfer. Delegate work and file moves run on its serial worker queue.
public final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var result: Result<URL, any Error>?
    private let destination: URL
    private let progress: @Sendable (DownloadProgress) -> Void
    private let started = Date()
    private var lastReport = Date.distantPast
    public init(destination: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) { self.destination = destination; self.progress = progress }
    public func download(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 180
        configuration.urlCache = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: url)
                let stop = lock.withLock { self.continuation = continuation; self.task = task; return cancelled }
                if stop { task.cancel() } // Completion still resumes the continuation exactly once.
                task.resume()
            }
        } onCancel: { self.cancel() }
    }
    public func cancel() { lock.withLock { cancelled = true; task?.cancel() } }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 2_000_000_000 { downloadTask.cancel(); return }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.15 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        progress(.init(received: totalBytesWritten, total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil, bytesPerSecond: Double(totalBytesWritten)/max(0.001, now.timeIntervalSince(started))))
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let value = Result<URL, any Error> {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw ReleaseUpdateError.http((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0) }
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        }
        lock.withLock { result = value }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let state = lock.withLock { let state = (continuation, result); continuation = nil; self.task = nil; return state }
        if let error { state.0?.resume(throwing: error) }
        else { state.0?.resume(with: state.1 ?? .failure(ReleaseUpdateError.invalidRelease)) }
    }
}
public struct VerifiedUpdate: Sendable {
    public let directory: URL
    public let dmg: URL
    public init(directory: URL, dmg: URL) { self.directory = directory; self.dmg = dmg }
}
public enum UpdatePackage {
    public static func fetch(_ release: AppRelease, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> VerifiedUpdate {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProxPulseUpdate-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 10
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: release.checksum)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4096 else { throw ReleaseUpdateError.invalidChecksum }
            let expected = try ReleaseUpdate.expectedHash(data, filename: release.download.lastPathComponent)
            let file = directory.appendingPathComponent("ProxPulseUpdate.dmg")
            _ = try await UpdateDownloader(destination: file, progress: progress).download(release.download)
            try Task.checkCancellation()
        assert(!Thread.isMainThread, "Blocking parsing/cache/file work must stay off MainActor")
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1024*1024), !bytes.isEmpty { try Task.checkCancellation(); hash.update(data: bytes) }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else { throw ReleaseUpdateError.invalidChecksum }
            return .init(directory: directory, dmg: file)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
