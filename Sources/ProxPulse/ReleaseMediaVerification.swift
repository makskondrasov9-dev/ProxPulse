#if DEBUG
import SwiftUI
import ProxPulseCore

/// Captures the shipping SwiftUI views, using only public demo fixtures.
@MainActor enum ReleaseMediaVerification {
    static func run() async throws {
        let suite = "dev.proxpulse.release-media." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en", forKey: PreferenceKey.language)
        defaults.set("dark", forKey: PreferenceKey.appearance)
        defaults.set("blue", forKey: PreferenceKey.accent)
        defaults.set(true, forKey: "pulse.topologyLineSpeeds")
        var model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        let window = NSWindow(contentRect: .init(x: 50, y: 50, width: 1440, height: 1100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ProxPulse — DEMO"
        window.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        defer { window.orderOut(nil); window.contentView = nil }
        for (mode, name, height) in [(WorkspaceViewMode.grid, "grid", 1300.0), (.rack, "rack", 1120.0), (.topology, "topology", 1080.0)] {
            window.contentView = nil; model.stop()
            model = DashboardModel(loadProfiles: false)
            model.workspaceMode = mode
            model.selectedPage = mode == .topology ? "Обзор" : "Машины"
            if mode == .topology { await model.refreshTopology() }
            let host = NSHostingView(rootView: DashboardView(model: model, animate: true).pulseAppearance().defaultAppStorage(defaults))
            window.setContentSize(.init(width: 1440, height: height)); window.contentView = host
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            if mode == .topology {
                TopologyFrameProbe.shared.begin()
                try await Task.sleep(for: .seconds(12))
                print("ANIMATION: " + TopologyFrameProbe.shared.finish())
            } else { try await Task.sleep(for: .seconds(2)) }
            try save(host, name: name)
        }
        let guest = model.node.guests.first { ($0.swapGB ?? 0) > 0 }!
        model.inspect(guest); model.inspectedGuest = nil
        let inspector = NSHostingView(rootView: GuestInspectorSheet(model: model, original: guest).pulseAppearance().defaultAppStorage(defaults))
        window.contentView = inspector; window.setContentSize(.init(width: 880, height: 840))
        try await Task.sleep(for: .seconds(1))
        try save(inspector, name: "inspector")
        print("PASS: four Retina screenshots of real SwiftUI views; public DEMO fixtures only; topology animation active")
    }
    private static func save(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        precondition(bitmap.pixelsWide >= Int(host.bounds.width) * 2, "Retina capture required")
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        print("MEDIA: \(name).png \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }
}
#endif
