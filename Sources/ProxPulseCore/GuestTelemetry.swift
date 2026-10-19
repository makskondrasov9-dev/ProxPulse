import Foundation

public struct GuestStatus: Decodable, Sendable {
    public var status: String?
    public var cpus: Int?
    public var cpu: Double?
    public var mem: Double?
    public var maxmem: Double?
    public var swap: Double?
    public var maxswap: Double?
    public var disk: Double?
    public var maxdisk: Double?
    public var netin: Double?
    public var netout: Double?
    public var uptime: Double?
}

public struct GuestSample: Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var cpu: Double
    public var memoryGB: Double
    public var swapGB: Double?
    public var diskGB: Double?
    public var receiveBps: Double?
    public var transmitBps: Double?
    public init(guest: Guest, date: Date = .now) {
        self.date = date; cpu = guest.cpu; memoryGB = guest.memoryGB
        swapGB = guest.swapGB; diskGB = guest.diskUsageAvailable == true ? guest.diskGB : nil
        receiveBps = guest.receiveBps; transmitBps = guest.transmitBps
    }
}

/// Counters belong to a profile/node/type/vmid session. Never divide the first sample by uptime.
public struct GuestNetworkSampler: Sendable {
    private struct Counter: Sendable { var date: Date; var incoming: Double; var outgoing: Double; var uptime: Double }
    private var counters: [String: Counter] = [:]
    public init() {}
    public mutating func apply(_ status: GuestStatus, to source: Guest, date: Date = .now) -> Guest {
        var guest = source
        let gb = 1_000_000_000.0
        guest.running = status.status.map { $0 == "running" } ?? source.running
        guest.cpu = min(1, max(0, status.cpu ?? source.cpu))
        guest.cpuCount = status.cpus
        guest.memoryGB = max(0, status.mem ?? source.memoryGB * gb) / gb
        guest.maxMemoryGB = max(0, status.maxmem ?? source.maxMemoryGB * gb) / gb
        guest.swapGB = status.swap.map { max(0, $0) / gb }
        guest.maxSwapGB = status.maxswap.map { max(0, $0) / gb }
        guest.diskGB = max(0, status.disk ?? source.diskGB * gb) / gb
        guest.maxDiskGB = status.maxdisk.map { max(0, $0) / gb } ?? source.maxDiskGB
        // QEMU commonly returns disk=0 without filesystem accounting. Do not present it as an empty guest disk.
        guest.diskUsageAvailable = status.disk != nil && ((source.kind == .lxc && guest.running) || (status.disk ?? 0) > 0)
        guest.uptimeSeconds = status.uptime
        guest.telemetryDate = date; guest.telemetryError = nil
        guest.receiveBps = nil; guest.transmitBps = nil
        let key = MonitoringRules.guestKey(guest)
        if guest.running, let incoming = status.netin, let outgoing = status.netout, let uptime = status.uptime {
            if let previous = counters[key], date > previous.date, uptime >= previous.uptime,
               incoming >= previous.incoming, outgoing >= previous.outgoing {
                let elapsed = date.timeIntervalSince(previous.date)
                guest.receiveBps = (incoming - previous.incoming) / elapsed
                guest.transmitBps = (outgoing - previous.outgoing) / elapsed
            }
            counters[key] = Counter(date: date, incoming: incoming, outgoing: outgoing, uptime: uptime)
        } else { counters.removeValue(forKey: key) }
        return guest
    }
    public mutating func retain(_ guests: [Guest]) {
        let keys = Set(guests.map(MonitoringRules.guestKey)); counters = counters.filter { keys.contains($0.key) }
    }
    public mutating func invalidate(_ guest: Guest) { counters.removeValue(forKey: MonitoringRules.guestKey(guest)) }
}
