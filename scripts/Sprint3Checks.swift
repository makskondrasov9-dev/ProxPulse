import Foundation
import ProxPulseCore

func verifySprint3() throws {
    let now = Date(timeIntervalSince1970: 1000)
    var rules = MonitoringRules()
    var node = MockDataProvider.node
    precondition(rules.observe(node, now: now).isEmpty)
    node.guests[0].running = false
    let stopped = rules.observe(node, now: now)
    precondition(stopped.count == 1 && stopped[0].kind == .guestStopped)
    precondition(rules.observe(node, now: now).isEmpty)
    rules.expectStop(node.guests[1], now: now)
    node.guests[1].running = false
    precondition(rules.observe(node, now: now).isEmpty)
    node.guests[1].running = true
    rules.actionCompleted(node.guests[1], running: true)
    node.guests[1].running = false
    precondition(rules.observe(node, now: now).count == 1)
    let capacity = node.storage.children[0].capacityGB
    node.storage.children[0].usedGB = capacity * 0.90
    precondition(rules.observe(node, now: now).isEmpty)
    node.storage.children[0].usedGB = capacity * 0.91
    precondition(rules.observe(node, now: now).first?.kind == .diskHigh)
    precondition(rules.observe(node, now: now).isEmpty)
    node.storage.children[0].usedGB = capacity * 0.89
    _ = rules.observe(node, now: now)
    node.storage.children[0].usedGB = capacity * 0.91
    precondition(rules.observe(node, now: now).isEmpty)
    node.storage.children[0].usedGB = capacity * 0.88
    _ = rules.observe(node, now: now)
    node.storage.children[0].usedGB = capacity * 0.91
    precondition(rules.observe(node, now: now).count == 1)
    rules.failed(now: now)
    precondition(rules.checkUnavailable(node: node.id, now: now.addingTimeInterval(15)) == nil)
    precondition(rules.checkUnavailable(node: node.id, now: now.addingTimeInterval(16))?.kind == .nodeUnavailable)
    precondition(rules.checkUnavailable(node: node.id, now: now.addingTimeInterval(30)) == nil)
    _ = rules.observe(node, now: now.addingTimeInterval(31))
    rules.failed(now: now.addingTimeInterval(32))
    precondition(rules.checkUnavailable(node: node.id, now: now.addingTimeInterval(48)) != nil)
    let command = try SSHCommand.make(host: "192.168.1.228", user: "root", guest: node.guests[0])
    precondition(command.contains("/usr/bin/ssh -t -l 'root' -- '192.168.1.228' 'qm terminal 100'"))
    let ct = try SSHCommand.make(host: "pve.local", user: "admin", guest: node.guests[1])
    precondition(ct.contains("'pct enter 101'"))
    do { _ = try SSHCommand.make(host: "-oProxyCommand=bad", user: "root"); fatalError("Option injection") } catch ProxmoxError.invalidEndpoint {}
    precondition(SSHCommand.quote("a'b") == "'a'\\''b'")
    precondition(L10n.text("из 64 GB RAM", language: "en") == "of 64 GB RAM")
    precondition(L10n.text("Машина docker остановилась", language: "en") == "Guest docker stopped")
    precondition(L10n.text("LIVE · Интервал 10 сек", language: "en") == "LIVE · Interval 10 sec")
    precondition(L10n.text("Обзор", language: "ru") == "Обзор")
    let old = Data(#"{"date":0,"node":"legacy","cpu":0.5,"memory":0.3,"running":2,"isDemo":false}"#.utf8)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: old)
    precondition(decoded.disk == nil && decoded.guests == nil && decoded.node == "legacy")
    let snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
    let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(roundTrip.guests?.count == 6 && roundTrip.storage?.count == 3 && roundTrip.disk == MockDataProvider.node.storage.fraction)
    var policy = WidgetReloadPolicy()
    var mode = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
    mode.profileID = UUID()
    precondition(policy.shouldReload(mode, now: now))
    precondition(!policy.shouldReload(mode, now: now.addingTimeInterval(4)))
    mode.isDemo = false; mode.state = .connecting; mode.guests = []; mode.node = "pve-live"
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(5)))
    mode.state = .live
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(6)), "First LIVE response must invalidate the connecting/DEMO timeline")
    precondition(!policy.shouldReload(mode, now: now.addingTimeInterval(25)))
    precondition(!policy.shouldReload(mode, now: now.addingTimeInterval(26)))
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(36)))
    mode.profileID = UUID()
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(37)), "Servers with identical node names must still reload")
    precondition(policy.shouldReload(mode, force: true, now: now.addingTimeInterval(38)))
    mode.state = .error
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(39)))
    mode.state = .live
    precondition(policy.shouldReload(mode, now: now.addingTimeInterval(40)))
    print("PASS: immediate DEMO/LIVE/profile/error transitions and 30-second background widget refresh")
    print("PASS: notification transitions/deduplication/hysteresis/offline threshold/recovery/intentional stop; SSH quoting; RU/EN interpolation; widget migration and full payload")
}
