import OSLog
import AppIntents
import WidgetKit
import ProxPulseCore

public struct MachineEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Машина / Machine" }
    public static var defaultQuery: MachineEntityQuery { MachineEntityQuery() }
    public let id: String
    public let name: String
    public let node: String
    public let vmid: Int
    public let running: Bool
    public let guestKey: String
    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name) · \(vmid)", subtitle: running ? "🟢 Работает / Running" : "⚪️ Остановлен / Stopped")
    }
    public init(guest: Guest, profileID: UUID?, identifier: String? = nil) {
        guestKey = MonitoringRules.guestKey(guest)
        id = identifier ?? Self.identifier(profileID: profileID, guestKey: guestKey)
        name = guest.name; node = guest.node; vmid = guest.id; running = guest.running
    }
    private init(id: String, key: String, node: String, vmid: Int) {
        self.id = id; guestKey = key; self.node = node; self.vmid = vmid; name = "VM / CT \(vmid)"; running = false
    }
    /// Preserve an archived selection after deletion, while excluding it from suggestions.
    public static func missing(identifier: String) -> MachineEntity? {
        guard let identity = MachineIdentity(identifier) else { return nil }
        let key = identity.node.map { $0 + "/" + (identity.kind?.rawValue ?? "unknown") + "/" + String(identity.vmid) } ?? identifier
        return .init(id: identifier, key: key, node: identity.node ?? "", vmid: identity.vmid)
    }
    public static func identifier(profileID: UUID?, guestKey: String) -> String { "\(profileID?.uuidString ?? "legacy")|\(guestKey)" }
}
public struct MachineEntityQuery: EntityStringQuery {
    private let loadSnapshot: @Sendable () -> WidgetSnapshot?
    public init() { loadSnapshot = { WidgetSnapshotStore.load() } }
    public init(loadSnapshot: @escaping @Sendable () -> WidgetSnapshot?) { self.loadSnapshot = loadSnapshot }
    public static func machines(in snapshot: WidgetSnapshot?) -> [MachineEntity] {
        guard let snapshot else { return [] }
        return (snapshot.guests ?? []).sorted { $0.id < $1.id }.map { MachineEntity(guest: $0, profileID: snapshot.profileID) }
    }
    public func entities(for identifiers: [String]) async throws -> [MachineEntity] {
        // No process-global entity cache: every query uses exactly the current active profile.
        let snapshot = loadSnapshot()
        return identifiers.compactMap { id in
            if let snapshot, let guest = MachineIdentity(id)?.resolve(in: snapshot) {
                return MachineEntity(guest: guest, profileID: snapshot.profileID, identifier: id)
            }
            return MachineEntity.missing(identifier: id)
        }
    }
    public func suggestedEntities() async throws -> [MachineEntity] { Self.machines(in: loadSnapshot()) }
    public func entities(matching string: String) async throws -> [MachineEntity] {
        Self.machines(in: loadSnapshot()).filter { $0.name.localizedCaseInsensitiveContains(string) || String($0.vmid).contains(string) || $0.node.localizedCaseInsensitiveContains(string) }
    }
}
public struct SelectMachineIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Машина / Machine" }
    public static var description: IntentDescription { "Выберите отдельную машину для этого виджета / Choose a machine for this widget." }
    @Parameter(title: "Машина / Machine") public var machine: MachineEntity?
    public init() {}
    public init(machine: MachineEntity) { self.machine = machine }
}
public struct MachineEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetSnapshot?
    public let machineKey: String?
    public init(date: Date, snapshot: WidgetSnapshot?, machineKey: String?) { self.date = date; self.snapshot = snapshot; self.machineKey = machineKey }
}
public struct MachineTimelineProvider: AppIntentTimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> MachineEntry {
        var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
        snapshot.applyPortAudits(Dictionary(uniqueKeysWithValues: MockDataProvider.node.guests.filter(\.running).map { (MonitoringRules.guestKey($0), PortAudit.demo($0)) }))
        return .init(date: .now, snapshot: snapshot, machineKey: snapshot.guests?.first.map(MonitoringRules.guestKey))
    }
    public static func entry(for configuration: SelectMachineIntent, snapshot: WidgetSnapshot?) -> MachineEntry {
        let selected = configuration.machine
        guard let selected else { return .init(date: .now, snapshot: snapshot, machineKey: nil) }
        let guest = snapshot.flatMap { MachineIdentity(selected.id)?.resolve(in: $0) }
        // A stored selection that is missing/foreign must say “not found”, not “choose a machine”.
        return .init(date: .now, snapshot: snapshot, machineKey: guest.map(MonitoringRules.guestKey) ?? selected.id)
    }
    public func snapshot(for configuration: SelectMachineIntent, in context: Context) async -> MachineEntry {
        context.isPreview && configuration.machine == nil ? placeholder(in: context) : Self.entry(for: configuration, snapshot: WidgetSnapshotStore.load())
    }
    public func timeline(for configuration: SelectMachineIntent, in context: Context) async -> Timeline<MachineEntry> {
        let entry = Self.entry(for: configuration, snapshot: WidgetSnapshotStore.load())
        let guest = entry.snapshot?.guests?.first { MonitoringRules.guestKey($0) == entry.machineKey }
        let security = guest.flatMap { entry.snapshot?.portSecurity(for: $0, now: entry.date) }
        Logger(subsystem: "dev.proxpulse.widget", category: "ports").info("Machine timeline vmid=\(guest?.id ?? -1, privacy: .public) ports=\(security?.ports.count ?? 0, privacy: .public) warning=\(security?.level == .warning, privacy: .public)")
        return .init(entries: [entry], policy: .after(Date().addingTimeInterval(30)))
    }
}

// Expose intents in this library to Xcode's metadata extraction build phase.
public struct ProxPulseIntentsPackage: AppIntentsPackage { public init() {} }
