#if DEBUG
import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI

@MainActor enum Sprint6Verification {
    static func run() async throws {
        let suite = "dev.proxpulse.sprint6." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ru", forKey: PreferenceKey.language); defaults.set("dark", forKey: PreferenceKey.appearance)
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        model.selectedPage = "Настройки"
        RuntimeUIVerification.capture(SettingsView(model: model, embedded: true).pulseAppearance().defaultAppStorage(defaults).padding(24), size: .init(width: 1000, height: 1650), name: "sprint6-settings-ru")
        var profile = MockDataProvider.profiles[0]
        profile.externalTunnel = .init(name: "AmneziaWG", address: "203.0.113.10", interface: "awg0")
        RuntimeUIVerification.capture(AddServerSheet(model: model, existing: profile).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 640, height: 850), name: "sprint6-vpn-profile")
        var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
        snapshot.selectedMachineKey = MonitoringRules.guestKey(MockDataProvider.guests[1]); snapshot.guests?[1].ipAddresses = ["192.0.2.10"]
        RuntimeUIVerification.capture(MachineWidgetView(entry: .init(date: .now, snapshot: snapshot), machineKey: snapshot.selectedMachineKey).padding(16).environment(\.colorScheme, .dark), size: .init(width: 360, height: 170), name: "sprint6-machine-widget")
        if ProcessInfo.processInfo.environment["PROXPULSE_VERIFY_GITHUB"] == "1" {
            await model.updates.check()
            precondition(model.updates.error == nil, "GitHub update check failed")
            print("PASS: real GitHub latest API parsed and compared with current version")
        }
        let base = "https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.2/ProxPulse-v0.2.2.dmg"
        let json: [String: Any] = ["tag_name":"v0.2.2","draft":false,"prerelease":false,"body":"## ProxPulse 0.2.2\n- Fixture release notes\n- More improvements","assets":[["name":"ProxPulse-v0.2.2.dmg","browser_download_url":base],["name":"ProxPulse-v0.2.2.dmg.sha256","browser_download_url":base+".sha256"]]]
        model.updates.release = try ReleaseUpdate.parse(JSONSerialization.data(withJSONObject: json))
        RuntimeUIVerification.capture(UpdateSheet(manager: model.updates).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 672, height: 652), name: "sprint6-update-sheet")
        defaults.set("en", forKey: PreferenceKey.language)
        RuntimeUIVerification.capture(SettingsView(model: model, embedded: true).pulseAppearance().defaultAppStorage(defaults).padding(24), size: .init(width: 1000, height: 1650), name: "sprint6-settings-en")
        let loopback = await TunnelProbe.ping(.init(name: "Loopback", address: "127.0.0.1", interface: "awg0"))
        precondition(loopback.reachable == true && loopback.pingMS != nil && loopback.ratesAvailable == false)
        let ipv6 = await TunnelProbe.ping(.init(name: "IPv6 loopback", address: "::1", interface: "wg0"))
        precondition(ipv6.reachable == true && ipv6.pingMS != nil && ipv6.ratesAvailable == false)
        print("PASS: IPv4 and IPv6 system ping argument handling and deadlines")
        print("PASS: update modal, VPN profile, RU/EN settings, selected-machine widget native renders; local ping works without SSH and does not fabricate rates")
    }
}
#endif
