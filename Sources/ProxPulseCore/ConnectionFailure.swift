import Foundation

public struct ConnectionFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public static func map(_ error: any Error) -> any Error {
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return Self(message: "Домен не существует или опечатка в адресе.")
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return Self(message: "Сервер недоступен. Проверьте доступность порта 443/8006 или включите VPN.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return Self(message: "Ошибка SSL. Возможно, самоподписанный сертификат. Включите тумблер «Разрешить самоподписанный SSL».")
        default: return error
        }
    }
}
public enum PollDeadline {
    /// Structured cancellation propagates to all URLSession requests belonging to this cycle.
    public static func run<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: .seconds(seconds)); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            return value
        }
    }
}
public actor SnapshotWriter {
    private var sequence = 0
    public init() {}
    public func save(_ snapshot: WidgetSnapshot, sequence: Int) throws {
        try Task.checkCancellation()
        guard sequence > self.sequence else { return }
        self.sequence = sequence
        assert(!Thread.isMainThread, "Blocking parsing/cache/file work must stay off MainActor")
        try WidgetSnapshotStore.save(snapshot)
    }
}
