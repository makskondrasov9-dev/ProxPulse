import Foundation
import ProxPulseCore

func verifySprint4() throws {
    func status(_ json: String) throws -> GuestStatus { try JSONDecoder().decode(GuestStatus.self, from: Data(json.utf8)) }
    let source = MockDataProvider.guests[1]
    let baseline = try status(#"{"status":"running","cpus":4,"cpu":0.22,"mem":900000000,"maxmem":4000000000,"swap":125000000,"maxswap":512000000,"disk":2700000000,"maxdisk":40000000000,"netin":12000,"netout":4000,"uptime":600}"#)
    var sampler = GuestNetworkSampler()
    let time = Date(timeIntervalSince1970: 1000)
    let first = sampler.apply(baseline, to: source, date: time)
    precondition(first.receiveBps == nil && first.transmitBps == nil)
    precondition(first.cpuCount == 4 && first.memoryGB == 0.9 && first.maxMemoryGB == 4)
    precondition(first.swapGB == 0.125 && first.maxSwapGB == 0.512 && first.diskGB == 2.7 && first.maxDiskGB == 40)
    var next = baseline; next.netin = 60000; next.netout = 20000; next.uptime = 604
    let second = sampler.apply(next, to: source, date: time.addingTimeInterval(4))
    precondition(second.receiveBps == 12000 && second.transmitBps == 4000)
    next.netin = 0; next.netout = 0; next.uptime = 1
    let rebooted = sampler.apply(next, to: source, date: time.addingTimeInterval(8))
    precondition(rebooted.receiveBps == nil && rebooted.transmitBps == nil)
    sampler.invalidate(source)
    precondition(sampler.apply(baseline, to: source, date: time.addingTimeInterval(12)).receiveBps == nil)
    var vm = source; vm.kind = .qemu
    let unknown = sampler.apply(try status(#"{"status":"running","disk":0,"maxdisk":40000000000}"#), to: vm)
    precondition(unknown.swapGB == nil && unknown.maxSwapGB == nil && unknown.diskUsageAvailable == false)
    let stopped = sampler.apply(try status(#"{"status":"stopped","disk":0,"maxdisk":40000000000}"#), to: source)
    precondition(stopped.diskUsageAvailable == false && stopped.maxDiskGB == 40)
    let zeroSwap = sampler.apply(try status(#"{"status":"running","swap":0,"maxswap":0}"#), to: source)
    precondition(zeroSwap.swapGB == 0 && zeroSwap.maxSwapGB == 0)
    // Old WidgetKit caches must remain decodable when telemetry fields are absent.
    let old = #"{"id":1,"name":"old","node":"pve","kind":"lxc","running":true,"cpu":0,"memoryGB":1,"maxMemoryGB":2,"diskGB":3,"role":"legacy"}"#
    let decoded = try JSONDecoder().decode(Guest.self, from: Data(old.utf8))
    precondition(decoded.cpuCount == nil && decoded.swapGB == nil)
    var rules = MonitoringRules()
    var node = MockDataProvider.node
    node.storage.children = [.init(id: "threshold", name: "test", capacityGB: 100, usedGB: 85)]
    precondition(rules.observe(node, diskThreshold: 0.9).isEmpty)
    precondition(rules.observe(node, diskThreshold: 0.8).contains { $0.kind == .diskHigh })
    precondition(rules.observe(node, diskThreshold: 0.8).isEmpty)
    print("PASS: guest telemetry, first/reset counter samples, byte rates, missing QEMU metrics, legacy cache, configurable disk threshold")
}
