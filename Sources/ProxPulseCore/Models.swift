import Foundation
import Darwin

public enum AuthenticationMode: String, Codable, CaseIterable, Sendable { case apiToken, password }

public struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var endpoint: URL
    public var tokenID: String
    public var allowInsecureSSL: Bool
    public var externalTunnel: ExternalTunnel? = nil
    public var localEndpoint: URL? = nil
    public var authentication: AuthenticationMode?
    public var authMode: AuthenticationMode { authentication ?? .apiToken }
    public init(id: UUID = UUID(), name: String, endpoint: URL, tokenID: String, allowInsecureSSL: Bool = false, authentication: AuthenticationMode = .apiToken) {
        self.id = id; self.name = name; self.endpoint = endpoint; self.tokenID = tokenID; self.allowInsecureSSL = allowInsecureSSL; self.authentication = authentication
    }
}
public enum GuestKind: String, Codable, Sendable { case lxc, qemu }
public struct Guest: Identifiable, Codable, Sendable {
    public var id: Int
    public var name: String
    public var node: String
    public var kind: GuestKind
    public var running: Bool
    public var cpu: Double
    public var memoryGB: Double
    public var maxMemoryGB: Double
    public var diskGB: Double
    public var role: String
    public var cpuCount: Int? = nil
    public var osType: String? = nil
    public var bridges: [String]? = nil
    public var swapGB: Double? = nil
    public var maxSwapGB: Double? = nil
    public var maxDiskGB: Double? = nil
    public var diskUsageAvailable: Bool? = nil
    public var uptimeSeconds: Double? = nil
    public var receiveBps: Double? = nil
    public var transmitBps: Double? = nil
    public var telemetryDate: Date? = nil
    public var telemetryError: String? = nil
    public var ipAddresses: [String]? = nil
    public init(id: Int, name: String, node: String, kind: GuestKind, running: Bool, cpu: Double, memoryGB: Double, maxMemoryGB: Double, diskGB: Double, role: String) {
        self.id = id; self.name = name; self.node = node; self.kind = kind; self.running = running; self.cpu = cpu; self.memoryGB = memoryGB; self.maxMemoryGB = maxMemoryGB; self.diskGB = diskGB; self.role = role
    }
}
public struct DiskItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var capacityGB: Double
    public var usedGB: Double
    public var children: [DiskItem]
    public var fraction: Double { capacityGB > 0 ? min(1, max(0, usedGB / capacityGB)) : 0 }
    public init(id: String, name: String, capacityGB: Double, usedGB: Double, children: [DiskItem] = []) {
        self.id = id; self.name = name; self.capacityGB = capacityGB; self.usedGB = usedGB; self.children = children
    }
}
public struct NodeSnapshot: Identifiable, Codable, Sendable {
    public var id: String
    public var online: Bool
    public var cpu: Double
    public var memoryGB: Double
    public var maxMemoryGB: Double
    public var networkMBps: Double
    public var linkMBps: Double
    public var uptime: String
    public var storage: DiskItem
    public var guests: [Guest]
    public var cpuModel: String? = nil
    public var cpuCount: Int? = nil
    public var storageNote: String? = nil
    public static func empty(name: String = "Подключение…") -> NodeSnapshot {
        NodeSnapshot(id: name, online: false, cpu: 0, memoryGB: 0, maxMemoryGB: 0, networkMBps: 0, linkMBps: 0, uptime: "—", storage: DiskItem(id: "empty", name: name, capacityGB: 0, usedGB: 0), guests: [])
    }
}
public enum WidgetConnectionState: String, Codable, Sendable { case demo, connecting, live, error, offline }
public struct WidgetSnapshot: Codable, Sendable {
    public var profileID: UUID? = nil
    public var profileName: String? = nil
    public var state: WidgetConnectionState? = nil
    public var date: Date
    public var writtenAt: Date? = .now
    public var node: String
    public var cpu: Double
    public var memory: Double
    public var running: Int
    public var isDemo: Bool
    public var disk: Double?
    public var online: Bool?
    public var guests: [Guest]?
    public var storage: [DiskItem]?
    public var language: String?
    public var accent: String?
    public var appearance: String?
    public var selectedMachineKey: String? = nil
    // Guest keys include node/type/vmid; the snapshot itself is scoped to one active profile.
    public var detectedPorts: [String: [Int]]? = nil
    public var securityLevel: [String: PortSecurityLevel]? = nil
    public var portAuditedAt: [String: Date]? = nil
    public var portCoverage: [String: PortAudit.Coverage]? = nil
    public init(node: NodeSnapshot, isDemo: Bool = false) {
        state = isDemo ? .demo : node.online ? .live : .offline
        date = Date(); self.node = node.id; cpu = node.cpu; self.isDemo = isDemo
        disk = node.storage.fraction; online = node.online; guests = node.guests; storage = node.storage.children
        language = UserDefaults.standard.string(forKey: PreferenceKey.language) ?? "ru"
        accent = UserDefaults.standard.string(forKey: PreferenceKey.accent) ?? "blue"
        appearance = UserDefaults.standard.string(forKey: PreferenceKey.appearance) ?? "system"
        memory = node.memoryGB / max(1, node.maxMemoryGB); running = node.guests.filter(\.running).count
    }
}
public enum WidgetSnapshotStore {
    public static let appGroup = "group.proxpulsedata"
    public static let snapshotKey = "widget.snapshot.v2"
    public static var fallbackURL: URL {
        // NSHomeDirectory is redirected inside App Sandbox; use the login user's actual home.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/ProxPulse/live_snapshot.json")
    }
    public static func writeMirror(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func readMirror(at url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url), data.count <= 8_000_000 else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    public static func save(_ snapshot: WidgetSnapshot) throws {
        // The fallback is mandatory and independent of App Group entitlement availability.
        try writeMirror(snapshot, to: fallbackURL)
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let defaults = UserDefaults(suiteName: appGroup),
           (try? writeMirror(snapshot, to: directory.appendingPathComponent("snapshot.json"))) != nil {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: snapshotKey)
            defaults.synchronize()
        }
    }
    public static func load() -> WidgetSnapshot? {
        let grouped = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .flatMap { readMirror(at: $0.appendingPathComponent("snapshot.json")) } ?? loadPreferences()
        let fallback = readMirror(at: fallbackURL)
        // An accessible but stale group must not mask a newer file from another installation.
        if let fallback, grouped == nil || (fallback.writtenAt ?? fallback.date) > (grouped!.writtenAt ?? grouped!.date) { return fallback }
        return grouped
    }
    public static func loadPreferences() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Reload transitions immediately, and healthy background metrics at most once every 20 seconds.
public struct WidgetReloadPolicy {
    private struct Identity: Equatable {
        var profile: UUID?
        var node: String
        var demo: Bool
        var state: WidgetConnectionState?
    }
    private var identity: Identity?
    private var lastReload = Date.distantPast
    public init() {}
    public mutating func shouldReload(_ snapshot: WidgetSnapshot, force: Bool = false, now: Date = .now) -> Bool {
        let next = Identity(profile: snapshot.profileID, node: snapshot.node, demo: snapshot.isDemo, state: snapshot.state)
        guard force || next != identity || now.timeIntervalSince(lastReload) >= 20 else { return false }
        identity = next; lastReload = now
        return true
    }
}
