import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable { case ru, en }
public enum AppearanceChoice: String, CaseIterable, Codable, Sendable { case system, dark, light }
public enum AccentChoice: String, CaseIterable, Codable, Sendable { case blue, neon, emerald, purple, orange }
public enum PreferenceKey {
    public static let language = "pulse.language"
    public static let appearance = "pulse.appearance"
    public static let accent = "pulse.accent"
    public static let pollInterval = "pulse.pollInterval"
    public static let guestAlerts = "pulse.alert.guests"
    public static let diskAlerts = "pulse.alert.disks"
    public static let nodeAlerts = "pulse.alert.nodes"
    public static let diskThreshold = "pulse.diskThreshold"
    public static let notificationSound = "pulse.alert.sound"
    public static let sshUser = "pulse.sshUser"
}
public struct MonitoringEvent: Identifiable, Sendable {
    public enum Kind: String, Sendable { case guestStopped, diskHigh, nodeUnavailable }
    public var id: String
    public var kind: Kind
    public var subject: String
    public var node: String
    public var value: Int?
}
/// Pure transition detector: no permission requests, scheduling, networking, or UserDefaults.
public struct MonitoringRules: Sendable {
    private var running: [String: Bool] = [:]
    private var highDisks: Set<String> = []
    private var expectedStops: [String: Date] = [:]
    private var failureSince: Date?
    private var offlineSent = false
    public init() {}
    public static func guestKey(_ guest: Guest) -> String { "\(guest.node)/\(guest.kind.rawValue)/\(guest.id)" }
    public mutating func actionCompleted(_ guest: Guest, running newState: Bool) { running[Self.guestKey(guest)] = newState; expectedStops.removeValue(forKey: Self.guestKey(guest)) }
    public mutating func expectStop(_ guest: Guest, now: Date) { expectedStops[Self.guestKey(guest)] = now.addingTimeInterval(180) }
    public mutating func observe(_ snapshot: NodeSnapshot, now: Date = .now, diskThreshold: Double = 0.9) -> [MonitoringEvent] {
        failureSince = nil; offlineSent = false
        expectedStops = expectedStops.filter { $0.value > now }
        var events: [MonitoringEvent] = []
        let currentKeys = Set(snapshot.guests.map(Self.guestKey))
        running = running.filter { currentKeys.contains($0.key) }
        for guest in snapshot.guests {
            let key = Self.guestKey(guest)
            if running[key] == true && !guest.running && expectedStops[key] == nil {
                events.append(.init(id: "guest-" + key, kind: .guestStopped, subject: guest.name, node: guest.node))
            }
            if running[key] == true && !guest.running { expectedStops.removeValue(forKey: key) }
            running[key] = guest.running
        }
        for pool in snapshot.storage.children {
            if pool.fraction > diskThreshold && !highDisks.contains(pool.id) {
                highDisks.insert(pool.id)
                events.append(.init(id: "disk-" + pool.id, kind: .diskHigh, subject: pool.name, node: snapshot.id, value: Int(pool.fraction * 100)))
            } else if pool.fraction <= diskThreshold - 0.02 { highDisks.remove(pool.id) }
        }
        return events
    }
    public mutating func failed(now: Date = .now) { if failureSince == nil { failureSince = now } }
    public mutating func clearFailure() { failureSince = nil; offlineSent = false }
    public mutating func checkUnavailable(node: String, now: Date = .now) -> MonitoringEvent? {
        guard let failureSince, now.timeIntervalSince(failureSince) > 15, !offlineSent else { return nil }
        offlineSent = true
        return .init(id: "offline-" + node, kind: .nodeUnavailable, subject: node, node: node)
    }
}
public enum SSHCommand {
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func make(host: String, user: String, guest: Guest? = nil) throws -> String {
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains(where: { $0.isWhitespace || $0.isNewline }),
              !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-".contains($0)) }) else { throw ProxmoxError.invalidEndpoint }
        var command = "exec /usr/bin/ssh -t -l " + quote(user) + " -- " + quote(host)
        if let guest {
            guard guest.id > 0 else { throw ProxmoxError.invalidResponse }
            command += " " + quote(guest.kind == .lxc ? "pct enter \(guest.id)" : "qm terminal \(guest.id)")
        }
        return "#!/bin/zsh\n" + command + "\n"
    }
}
