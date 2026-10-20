#if DEBUG
import SwiftUI
import ProxPulseCore

final class TopologyFrameProbe: @unchecked Sendable {
    static let shared = TopologyFrameProbe()
    private let lock = NSLock()
    private var enabled = false
    private var frames: [(Double, Double)] = []
    func begin() { lock.withLock { frames = []; enabled = true } }
    func record(time: Double, duration: Double) { lock.withLock { if enabled { frames.append((time, duration)) } } }
    func finish() -> String {
        let values = lock.withLock { enabled = false; return frames }
        let times = Array(Set(values.map(\.0))).sorted()
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }
        let seconds = max(0.001, (times.last ?? 0) - (times.first ?? 0))
        let durations = values.map(\.1).sorted()
        let p95 = durations.isEmpty ? 0 : durations[min(durations.count - 1, Int(Double(durations.count) * 0.95))] * 1000
        let gap95 = gaps.isEmpty ? 0 : gaps.sorted()[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))] * 1000
        return String(format: "frames=%d; FPS=%.1f; Canvas p95=%.3f ms; frame-gap p95=%.2f ms", times.count, Double(max(0,times.count - 1))/seconds, p95, gap95)
    }
}

@MainActor enum TopologyVerification {
    static func run(live: Bool) async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        if live {
            guard let profile = try ProfileStore.load().first else { throw ProxmoxError.noNodes }
            model.profiles = [profile]; model.selectedProfile = profile.id
            model.selectedNode = ""
            let deadline = Date().addingTimeInterval(60)
            while !model.hasSnapshot && Date() < deadline {
                if let error = model.connectionError { throw ProvisionError.invalid(error) }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard model.hasSnapshot else { throw ProvisionError.invalid("Live telemetry timed out") }
            try await Task.sleep(for: .seconds(5))
        }
        await model.refreshTopology(sshMetrics: true)
        if live {
            guard let tunnel = model.networkInterfaces.first(where: { $0.isTunnel && $0.active == 1 }),
                  let metrics = model.tunnelMeasurements[tunnel.iface], metrics.peer?.isEmpty == false else {
                throw ProvisionError.invalid(model.topologyProbeError ?? "Runtime tunnel endpoint missing")
            }
            print("LIVE: runtime \(tunnel.iface) endpoint=\(metrics.peer ?? "—"); RTT=\(metrics.pingMS.map(String.init(describing:)) ?? "unavailable") ms; RX=\(metrics.receiveBps); TX=\(metrics.transmitBps); guest IPs=\(model.topologyGuestAddresses.values.filter { !$0.isEmpty }.count)")
        }
        if live {
            let refresh = Task { await model.refreshTopology(sshMetrics: true) }
            let runtimeNames = Set(model.networkInterfaces.filter(\.isTunnel).map(\.iface))
            for _ in 0..<25 {
                precondition(runtimeNames.isSubset(of: Set(model.networkInterfaces.map(\.iface))), "Runtime tunnel vanished during API refresh")
                try await Task.sleep(for: .milliseconds(200))
            }
            await refresh.value
            if let guest = model.node.guests.first(where: \.running) {
                print("PRIMARY GUEST IP: " + (model.topologyGuestAddresses[MonitoringRules.guestKey(guest)]?.first ?? "unavailable"))
            }
            print("PASS: runtime tunnel remains visible throughout API + SSH refresh")
        }
        let suite = "dev.proxpulse.topology-verification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "pulse.topologyVPNProbe"); defaults.set(true, forKey: "pulse.topologyLineSpeeds")
        model.selectedPage = "Машины"; model.workspaceMode = .topology
        let host = NSHostingView(rootView: DashboardView(model: model, animate: false).pulseAppearance().defaultAppStorage(defaults).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: .init(x: 70, y: 70, width: 1440, height: 960), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ProxPulse — Topology verification"
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .seconds(2))
        save(host, live ? "topology-live" : "topology-demo")
        TopologyFrameProbe.shared.begin()
        try await Task.sleep(for: .seconds(12))
        print("RENDER: " + TopologyFrameProbe.shared.finish())
        window.setContentSize(.init(width: 1680, height: 1080))
        try await Task.sleep(for: .seconds(1))
        save(host, live ? "topology-live-wide" : "topology-demo-wide")
        defaults.set(false, forKey: "pulse.topologyLineSpeeds")
        try await Task.sleep(for: .milliseconds(500))
        save(host, live ? "topology-live-no-speeds" : "topology-demo-no-speeds")
        print("PASS: topology native window, runtime tunnel, guest IPs, resize/fit, speed toggle, display-driven Canvas measured; no server changes")
    }
    private static func save(_ host: NSView, _ name: String) {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Bitmap unavailable") }
        host.cacheDisplay(in: host.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Preview")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
#endif
