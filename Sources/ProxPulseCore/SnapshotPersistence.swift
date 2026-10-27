import Foundation
import CryptoKit

/// Keep unchanged metrics on disk intact. A small, rate-limited observation receipt preserves
/// freshness without re-encoding/replacing the complete machine catalog on every poll.
enum SnapshotPersistence {
    private struct Observation: Codable {
        var digest: String
        var date: Date
        var writtenAt: Date
        var telemetry: [String: Date]
        var portAuditedAt: [String: Date]?
    }
    private static func receiptURL(_ url: URL) -> URL { url.appendingPathExtension("observation") }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    private static func digest(_ data: Data) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        object.removeValue(forKey: "date"); object.removeValue(forKey: "writtenAt")
        object.removeValue(forKey: "portAuditedAt")
        if var guests = object["guests"] as? [[String: Any]] {
            for index in guests.indices { guests[index].removeValue(forKey: "telemetryDate") }
            object["guests"] = guests
        }
        return SHA256.hash(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            .map { String(format: "%02x", $0) }.joined()
    }
    private static func data(at url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000 else { return nil }
        return try? Data(contentsOf: url)
    }
    private static func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func write(_ snapshot: WidgetSnapshot, to url: URL) throws -> Bool {
        let encoded = try encoder().encode(snapshot), hash = try digest(encoded)
        let old = data(at: url)
        if let old, (try? digest(old)) == hash {
            let receipt = receiptURL(url)
            let previous = data(at: receipt).flatMap { try? JSONDecoder().decode(Observation.self, from: $0) }
            // Metadata only: at most once per 30s, never rewrite live_snapshot.json for a timestamp.
            if previous?.digest != hash || (snapshot.writtenAt ?? snapshot.date) >= previous!.writtenAt.addingTimeInterval(30) {
                let telemetry = Dictionary((snapshot.guests ?? []).compactMap { guest in
                    guest.telemetryDate.map { (MonitoringRules.guestKey(guest), $0) }
                }, uniquingKeysWith: { _, latest in latest })
                let observation = Observation(digest: hash, date: snapshot.date, writtenAt: snapshot.writtenAt ?? snapshot.date, telemetry: telemetry, portAuditedAt: snapshot.portAuditedAt)
                try atomicWrite(encoder().encode(observation), to: receipt)
            }
            return false
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atomicWrite(encoded, to: url)
        return true
    }
    static func read(at url: URL) -> WidgetSnapshot? {
        guard let data = data(at: url), var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        if let receipt = self.data(at: receiptURL(url)),
           let observation = try? JSONDecoder().decode(Observation.self, from: receipt),
           observation.writtenAt > (snapshot.writtenAt ?? snapshot.date),
           observation.digest == (try? digest(data)) {
            snapshot.date = observation.date; snapshot.writtenAt = observation.writtenAt
            snapshot.portAuditedAt = observation.portAuditedAt
            for index in (snapshot.guests ?? []).indices {
                let key = MonitoringRules.guestKey(snapshot.guests![index])
                snapshot.guests?[index].telemetryDate = observation.telemetry[key]
            }
        }
        return snapshot
    }
}
