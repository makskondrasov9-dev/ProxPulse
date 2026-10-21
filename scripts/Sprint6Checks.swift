import Foundation
import ProxPulseCore

func verifySprint6() throws {
    precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("v0.2.9")!)
    for text in ["0.2", "v0.2.1-beta", "0.02.1", "-1.0.0", "1.2.3.4"] { precondition(ReleaseVersion(text) == nil) }
    let base = "https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.2/"
    let release: [String: Any] = ["tag_name":"v0.2.2", "draft":false, "prerelease":false, "body":"## What's new\nFixture", "assets":[["name":"ProxPulse-v0.2.2.dmg", "browser_download_url":base+"ProxPulse-v0.2.2.dmg"],["name":"ProxPulse-v0.2.2.dmg.sha256", "browser_download_url":base+"ProxPulse-v0.2.2.dmg.sha256"]]]
    let parsed = try ReleaseUpdate.parse(JSONSerialization.data(withJSONObject: release))
    precondition(parsed.version > ReleaseVersion("0.2.1")! && parsed.notes.contains("Fixture"))
    for key in ["draft", "prerelease"] {
        var bad = release; bad[key] = true
        do { _ = try ReleaseUpdate.parse(JSONSerialization.data(withJSONObject: bad)); fatalError("Unstable release accepted") } catch { }
    }
    var bad = release; bad["assets"] = [["name":"ProxPulse-v0.2.2.dmg", "browser_download_url":"https://example.com/update.dmg"]]
    do { _ = try ReleaseUpdate.parse(JSONSerialization.data(withJSONObject: bad)); fatalError("Untrusted asset accepted") } catch { }
    let hash = String(repeating: "a", count: 64)
    let actual = try ReleaseUpdate.expectedHash(Data((hash + "  ProxPulse-v0.2.2.dmg\n").utf8), filename: "ProxPulse-v0.2.2.dmg")
    precondition(actual == hash)
    do { _ = try ReleaseUpdate.expectedHash(Data((hash + "  other.dmg").utf8), filename: "ProxPulse-v0.2.2.dmg"); fatalError("Wrong checksum filename") } catch { }
    let old = Data(#"{"id":"00000000-0000-0000-0000-000000000002","name":"legacy","endpoint":"https://pve.local:8006","tokenID":"root@pam","allowInsecureSSL":false}"#.utf8)
    var profile = try JSONDecoder().decode(ServerProfile.self, from: old)
    precondition(profile.externalTunnel == nil)
    profile.externalTunnel = .init(name: "AmneziaWG", address: "203.0.113.10", interface: "awg0")
    precondition(profile.externalTunnel!.isValid)
    let decodedProfile = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile))
    precondition(decodedProfile.externalTunnel == profile.externalTunnel)
    precondition(!ExternalTunnel(name: "VPN", address: "1.2.3.4; reboot", interface: "awg0").isValid)
    precondition(!ExternalTunnel(name: "VPN", address: "203.0.113.10", interface: "wg0;rm").isValid)
    precondition(ExternalTunnel(name: "VPN", address: "2001:db8::1", interface: "wg0").isValid)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProxPulse-fallback-test-" + UUID().uuidString).appendingPathComponent("live_snapshot.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
    snapshot.selectedMachineKey = MonitoringRules.guestKey(MockDataProvider.guests[0])
    snapshot.guests?[0].ipAddresses = ["192.0.2.10"]
    try WidgetSnapshotStore.writeMirror(snapshot, to: url)
    let decoded = WidgetSnapshotStore.readMirror(at: url)!
    precondition(decoded.selectedMachineKey == snapshot.selectedMachineKey && decoded.guests?[0].ipAddresses == ["192.0.2.10"])
    try Data("broken".utf8).write(to: url, options: .atomic)
    precondition(WidgetSnapshotStore.readMirror(at: url) == nil)
    let first = UUID(), second = UUID()
    var choices = WidgetMachineSelection.setting("node/lxc/105", profile: first, data: nil)
    choices = WidgetMachineSelection.setting("node/qemu/105", profile: second, data: choices)
    precondition(WidgetMachineSelection.machine(profile: first, data: choices) == "node/lxc/105")
    precondition(WidgetMachineSelection.machine(profile: second, data: choices) == "node/qemu/105")
    print("PASS: stable release/version/asset/checksum validation; legacy VPN profiles and IP validation; atomic fallback and selected machine telemetry round-trip")
}
