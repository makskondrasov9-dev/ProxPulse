import Foundation
import ProxPulseCore

func verifySprint9() throws {
    func expect(_ condition: Bool) { precondition(condition) }
    var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
    snapshot.profileID = UUID()
    let guest = snapshot.guests![0], key = MonitoringRules.guestKey(guest)
    for identifier in [String(guest.id), "\(guest.node)/\(guest.id)", key, "\(guest.kind.rawValue)/\(guest.id)", "legacy|" + key, snapshot.profileID!.uuidString.lowercased() + "|" + key, " 00\(guest.id) "] {
        precondition(MachineIdentity(identifier)?.resolve(in: snapshot)?.id == guest.id, "Legacy ID failed: \(identifier)")
    }
    precondition(MachineIdentity(UUID().uuidString + "|" + key)?.resolve(in: snapshot) == nil)
    precondition(MachineIdentity("other-node/\(guest.id)")?.resolve(in: snapshot) == nil)
    precondition(MachineIdentity("malformed") == nil)
    var duplicate = guest; duplicate.node = "other-node"; snapshot.guests?.append(duplicate)
    precondition(MachineIdentity(String(guest.id))?.resolve(in: snapshot) == nil, "Ambiguous VMID resolved to wrong node")
    snapshot.guests?.removeLast()
    for json in [#"{"id":105,"name":"foreign","node":"other-node","kind":"lxc","running":true,"cpu":0.42,"memoryGB":0.9,"maxMemoryGB":4}"#,
                 #"{"vmid":"106","name":"stopped","status":"stopped","type":"qemu","ip":null,"vcpu":null,"swapGB":null,"maxDiskGB":null,"ipAddresses":null}"#] {
        let decoded = try JSONDecoder().decode(Guest.self, from: Data(json.utf8))
        precondition(decoded.swapGB == nil && decoded.cpuCount == nil && decoded.ipAddresses == nil && decoded.diskGB == 0)
        if decoded.id == 105 { precondition(decoded.running && decoded.cpu == 0.42 && decoded.memoryGB == 0.9) }
        else { precondition(!decoded.running && decoded.kind == .qemu && decoded.maxMemoryGB == 0) }
        _ = try JSONDecoder().decode(Guest.self, from: JSONEncoder().encode(decoded))
    }
    let sparse = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(#"{"node":"foreign-node","guests":[{"vmid":"105","name":"foreign","status":"running","memoryGB":0.9,"maxMemoryGB":4}],"detectedPorts":null,"securityLevel":null}"#.utf8))
    precondition(sparse.guests?.first?.node == "foreign-node" && MachineIdentity("foreign-node/105")?.resolve(in:sparse)?.memoryGB == 0.9)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProxPulse-Sprint9-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("live_snapshot.json")
    let base = Date(); snapshot.date = base; snapshot.writtenAt = base
    snapshot.guests?[0].telemetryDate = base; snapshot.portAuditedAt = [key:base]
    expect(try WidgetSnapshotStore.writeMirror(snapshot, to: url))
    let original = try Data(contentsOf: url)
    let inode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber
    for tick in 1...60 {
        let time = base.addingTimeInterval(Double(tick)*4)
        snapshot.date = time; snapshot.writtenAt = time
        snapshot.guests?[0].telemetryDate = time; snapshot.portAuditedAt = [key:time]
        expect(try !WidgetSnapshotStore.writeMirror(snapshot, to: url))
    }
    expect(try Data(contentsOf: url) == original)
    expect(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as! NSNumber == inode)
    let fresh = WidgetSnapshotStore.readMirror(at: url)!
    precondition(fresh.date.timeIntervalSince(base) >= 210 && fresh.portAuditedAt![key]!.timeIntervalSince(base) >= 210, "Unchanged metrics falsely became stale")
    // A changed profile or metric must write immediately; an old observation must never leak back.
    snapshot.profileID = UUID(); snapshot.guests?[0].cpu = 0.87
    expect(try WidgetSnapshotStore.writeMirror(snapshot, to: url))
    let changed = WidgetSnapshotStore.readMirror(at: url)!
    precondition(changed.profileID == snapshot.profileID && changed.guests?[0].cpu == 0.87)
    print("PASS: normalized legacy/canonical IDs, profile and node isolation, ambiguous VMIDs; sparse/null machine JSON; 60 unchanged polls -> zero payload rewrites, bounded observation metadata, fresh timestamps, immediate changed/profile writes")
}
