import Foundation

/// Normalize archived AppIntent IDs without letting a VMID from a different profile match.
public struct MachineIdentity: Sendable {
    public let profile: UUID?
    public let node: String?
    public let kind: GuestKind?
    public let vmid: Int
    public init?(_ identifier: String) {
        let parts = identifier.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        if parts.count == 2 {
            if parts[0] == "legacy" { profile = nil }
            else if let uuid = UUID(uuidString: String(parts[0])) { profile = uuid }
            else { return nil }
        } else { profile = nil }
        let path = parts.last!.split(separator: "/").map(String.init)
        guard (1...3).contains(path.count), let id = Int(path.last!), id > 0 else { return nil }
        vmid = id
        switch path.count {
        case 3:
            guard let type = GuestKind(rawValue: path[1]) else { return nil }
            node = path[0]; kind = type
        case 2:
            if let type = GuestKind(rawValue: path[0]) { kind = type; node = nil }
            else { node = path[0]; kind = nil }
        default: node = nil; kind = nil
        }
    }
    public func resolve(in snapshot: WidgetSnapshot) -> Guest? {
        guard profile == nil || profile == snapshot.profileID else { return nil }
        let matches = (snapshot.guests ?? []).filter {
            $0.id == vmid && (node == nil || node == $0.node) && (kind == nil || kind == $0.kind)
        }
        // Never guess between duplicate VMIDs across nodes/types.
        return matches.count == 1 ? matches[0] : nil
    }
}
