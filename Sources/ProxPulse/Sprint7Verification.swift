#if DEBUG
import SwiftUI
import ProxPulseCore

@MainActor enum Sprint7Verification {
    static func run() async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        var profile = MockDataProvider.profiles[0]
        profile.endpoint = URL(string: "https://pve.example.com/pve/")!
        profile.localEndpoint = URL(string: "https://192.0.2.2:8006")!
        RuntimeUIVerification.capture(AddServerSheet(model: model, existing: profile).pulseAppearance(), size: .init(width: 640, height: 860), name: "sprint7-proxy-profile")
        model.updates.release = try ReleaseUpdate.parse(Data(#"{"tag_name":"v0.2.4","draft":false,"prerelease":false,"body":"Update fixture","assets":[{"name":"ProxPulse-v0.2.4.dmg","browser_download_url":"https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.4/ProxPulse-v0.2.4.dmg"},{"name":"ProxPulse-v0.2.4.dmg.sha256","browser_download_url":"https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v0.2.4/ProxPulse-v0.2.4.dmg.sha256"}]}"#.utf8))
        model.updates.installing = true; model.updates.downloadProgress = .init(received: 4_500_000, total: 9_000_000, bytesPerSecond: 2_500_000)
        RuntimeUIVerification.capture(UpdateSheet(manager: model.updates).pulseAppearance(), size: .init(width: 672, height: 652), name: "sprint7-download-progress")
        model.updates.installing = false
        model.updates.downloadedDMG = URL(fileURLWithPath: "/tmp/fixture.dmg"); model.updates.error = "Helper startup fixture error"
        RuntimeUIVerification.capture(UpdateSheet(manager: model.updates).pulseAppearance(), size: .init(width: 672, height: 652), name: "sprint7-update-fallback")
        weak var released: DashboardModel?
        do {
            let disposable = DashboardModel(loadProfiles: false)
            released = disposable; disposable.stop()
        }
        precondition(released == nil, "Dashboard lifecycle retained stopped model")
        let window = NSWindow(contentRect: .init(x: 40, y: 40, width: 1400, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: DashboardView(model: model, animate: false).pulseAppearance())
        window.contentView = host; NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        await model.refreshTopology(); try await Task.sleep(for: .seconds(2))
        TopologyFrameProbe.shared.begin()
        try await Task.sleep(for: .seconds(12))
        print("TOPOLOGY AUDIT: " + TopologyFrameProbe.shared.finish())
        let guest = model.node.guests[1]
        let inspector = NSHostingView(rootView: GuestInspectorSheet(model: model, original: guest).pulseAppearance())
        window.contentView = inspector; window.setContentSize(.init(width: 880, height: 840)); window.acceptsMouseMovedEvents = true
        try await Task.sleep(for: .seconds(1))
        var delays: [Double] = []
        let clock = ContinuousClock()
        for index in 0..<360 {
            let start = clock.now
            try await Task.sleep(for: .milliseconds(16))
            let elapsed = start.duration(to: clock.now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds)/1e18
            delays.append(max(0,seconds-0.016)*1000)
            let point = inspector.convert(CGPoint(x: 120+Double(index%120)*4, y: 400), to: nil)
            if let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: index, clickCount: 0, pressure: 0) { NSApp.sendEvent(event) }
        }
        let sorted = delays.sorted()
        print(String(format: "INSPECTOR AUDIT: six charts, 360 mouse events, MainActor timer delay p95=%.2f ms; max=%.2f ms", sorted[Int(Double(sorted.count-1)*0.95)], sorted.last ?? 0))
        print("PERF READY pid=\(ProcessInfo.processInfo.processIdentifier)")
        try await Task.sleep(for: .seconds(15))
        print("PASS: profile/progress/fallback native UI, stopped-model deallocation and measured topology/inspector workload")
    }
}
#endif
