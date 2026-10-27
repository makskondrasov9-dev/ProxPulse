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
    private enum CodingKeys: String, CodingKey {
        case id, name, node, kind, running, cpu, memoryGB, maxMemoryGB, diskGB, role
        case cpuCount, osType, bridges, swapGB, maxSwapGB, maxDiskGB, diskUsageAvailable
        case uptimeSeconds, receiveBps, transmitBps, telemetryDate, telemetryError, ipAddresses
    }
    private enum LegacyKeys: String, CodingKey { case vmid, status, type, vcpu, ip }
    /// Cache compatibility is intentionally separate from strict Proxmox API decoding.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        guard let identifier = try values.pveInt(.id) ?? legacy.pveInt(.vmid), identifier > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing machine VMID"))
        }
        id = identifier
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "VM / CT \(id)"
        node = try values.decodeIfPresent(String.self, forKey: .node) ?? ""
        kind = try values.decodeIfPresent(GuestKind.self, forKey: .kind) ?? legacy.decodeIfPresent(GuestKind.self, forKey: .type) ?? .lxc
        running = try values.pveBool(.running) ?? (legacy.decodeIfPresent(String.self, forKey: .status) == "running")
        cpu = max(0, (try values.pveDouble(.cpu)) ?? 0)
        memoryGB = max(0, (try values.pveDouble(.memoryGB)) ?? 0)
        maxMemoryGB = max(0, (try values.pveDouble(.maxMemoryGB)) ?? 0)
        diskGB = max(0, (try values.pveDouble(.diskGB)) ?? 0)
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? ""
        cpuCount = try values.pveInt(.cpuCount) ?? legacy.pveInt(.vcpu)
        osType = try values.decodeIfPresent(String.self, forKey: .osType)
        bridges = try values.decodeIfPresent([String].self, forKey: .bridges)
        swapGB = try values.pveDouble(.swapGB)
        maxSwapGB = try values.pveDouble(.maxSwapGB)
        maxDiskGB = try values.pveDouble(.maxDiskGB)
        diskUsageAvailable = try values.pveBool(.diskUsageAvailable)
        uptimeSeconds = try values.pveDouble(.uptimeSeconds)
        receiveBps = try values.pveDouble(.receiveBps)
        transmitBps = try values.pveDouble(.transmitBps)
        telemetryDate = try values.decodeIfPresent(Date.self, forKey: .telemetryDate)
        telemetryError = try values.decodeIfPresent(String.self, forKey: .telemetryError)
        ipAddresses = try values.decodeIfPresent([String].self, forKey: .ipAddresses)
        if ipAddresses == nil, let ip = try legacy.decodeIfPresent(String.self, forKey: .ip), !ip.isEmpty { ipAddresses = [ip] }
    }
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
    private enum CodingKeys: String, CodingKey {
        case profileID, profileName, state, date, writtenAt, node, cpu, memory, running, isDemo
        case disk, online, guests, storage, language, accent, appearance, selectedMachineKey
        case detectedPorts, securityLevel, portAuditedAt, portCoverage
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try values.decodeIfPresent(UUID.self, forKey: .profileID)
        profileName = try values.decodeIfPresent(String.self, forKey: .profileName)
        state = try values.decodeIfPresent(WidgetConnectionState.self, forKey: .state)
        date = try values.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        writtenAt = try values.decodeIfPresent(Date.self, forKey: .writtenAt)
        node = try values.decodeIfPresent(String.self, forKey: .node) ?? ""
        cpu = try values.pveDouble(.cpu) ?? 0; memory = try values.pveDouble(.memory) ?? 0
        isDemo = try values.pveBool(.isDemo) ?? false
        disk = try values.pveDouble(.disk); online = try values.pveBool(.online)
        guests = try values.decodeIfPresent([Guest].self, forKey: .guests)
        for index in (guests ?? []).indices where guests![index].node.isEmpty { guests?[index].node = node }
        running = try values.pveInt(.running) ?? (guests ?? []).filter(\.running).count
        storage = try values.decodeIfPresent([DiskItem].self, forKey: .storage)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        accent = try values.decodeIfPresent(String.self, forKey: .accent)
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance)
        selectedMachineKey = try values.decodeIfPresent(String.self, forKey: .selectedMachineKey)
        detectedPorts = try values.decodeIfPresent([String: [Int]].self, forKey: .detectedPorts)
        securityLevel = try values.decodeIfPresent([String: PortSecurityLevel].self, forKey: .securityLevel)
        portAuditedAt = try values.decodeIfPresent([String: Date].self, forKey: .portAuditedAt)
        portCoverage = try values.decodeIfPresent([String: PortAudit.Coverage].self, forKey: .portCoverage)
    }
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
    @discardableResult public static func writeMirror(_ snapshot: WidgetSnapshot, to url: URL) throws -> Bool {
        try SnapshotPersistence.write(snapshot, to: url)
    }
    public static func readMirror(at url: URL) -> WidgetSnapshot? {
        SnapshotPersistence.read(at: url)
    }
    public static func save(_ snapshot: WidgetSnapshot) throws {
        // The fallback is mandatory and independent of App Group entitlement availability.
        try writeMirror(snapshot, to: fallbackURL)
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let defaults = UserDefaults(suiteName: appGroup),
           (try? writeMirror(snapshot, to: directory.appendingPathComponent("snapshot.json"))) == true {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: snapshotKey)
            // UserDefaults coalesces its own writes; do not force a disk flush per poll.
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

/// Reload transitions immediately, and healthy background metrics at most once every 30 seconds.
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
        guard force || next != identity || now.timeIntervalSince(lastReload) >= 30 else { return false }
        identity = next; lastReload = now
        return true
    }
}
