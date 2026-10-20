import Foundation

public struct NodeNetworkInterface: Decodable, Identifiable, Sendable {
    public var iface: String
    public var type: String?
    public var active: Int?
    public var address: String?
    public var gateway: String?
    public var id: String { iface }
    public var isBridge: Bool { type == "bridge" || type == "OVSBridge" || iface.hasPrefix("vmbr") }
    public var isTunnel: Bool { ["awg", "wg", "tun"].contains { iface.hasPrefix($0) } }
    public init(iface: String, type: String? = nil, active: Int? = nil, address: String? = nil, gateway: String? = nil) { self.iface = iface; self.type = type; self.active = active; self.address = address; self.gateway = gateway }
}
public struct GuestConfiguration: Decodable, Sendable {
    public var osType: String?
    public var bridges: [String]
    private struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        osType = try? values.decode(String.self, forKey: Key(stringValue: "ostype")!)
        let keys = values.allKeys.filter { $0.stringValue.hasPrefix("net") && Int($0.stringValue.dropFirst(3)) != nil }
            .sorted { Int($0.stringValue.dropFirst(3))! < Int($1.stringValue.dropFirst(3))! }
        var seen: Set<String> = []
        bridges = keys.compactMap { key -> String? in
            guard let network = try? values.decode(String.self, forKey: key),
                  let bridge = network.split(separator: ",").first(where: { $0.hasPrefix("bridge=") }).map({ String($0.dropFirst(7)) }),
                  seen.insert(bridge).inserted else { return nil }
            return bridge
        }
    }
}
public struct TunnelMeasurement: Decodable, Sendable {
    public var peer: String?
    public var pingMS: Double?
    public var receiveBps: Double
    public var transmitBps: Double
    public var measuredAt: Date = .now
    enum CodingKeys: String, CodingKey { case peer, pingMS, receiveBps, transmitBps }
}
public enum TrafficAnimation {
    public static func frequency(bytesPerSecond: Double) -> Double { bytesPerSecond > 0 ? min(8, 0.7 + log10(max(1, bytesPerSecond)) * 0.7) : 0 }
}

/// Read-only runtime interfaces and byte-counter deltas, including systemd-created VPNs.
public struct RuntimeNetworkSnapshot: Decodable, Sendable {
    public var interfaces: [NodeNetworkInterface]
    public var measurements: [String: TunnelMeasurement]
    public var errors: [String: String]
}

/// Keeps a particle's phase continuous when a new traffic sample changes its speed.
public struct TrafficPhase: Sendable {
    public private(set) var speed: Double
    public private(set) var offset: Double
    public init(speed: Double, time: Double) { self.speed = speed; offset = -time * speed }
    public func position(at time: Double, particleOffset: Double = 0) -> Double {
        let value = (time * speed + offset + particleOffset).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }
    public mutating func update(speed: Double, time: Double) {
        let phase = position(at: time)
        self.speed = speed; offset = phase - time * speed
    }
}
