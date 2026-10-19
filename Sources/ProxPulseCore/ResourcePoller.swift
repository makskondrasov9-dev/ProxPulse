import Foundation

/// Single cancellable source for dashboard/menu. Widgets consume snapshots, never this loop.
public enum ResourcePoller {
    public static func stream(service: ProxmoxAPIService, interval: Duration = .seconds(5)) -> AsyncThrowingStream<[ClusterResource], Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let resources = try await service.resources()
                        try Task.checkCancellation()
                        continuation.yield(resources)
                        try await Task.sleep(for: max(.seconds(1), interval))
                    }
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
