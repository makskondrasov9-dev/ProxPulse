#if DEBUG
import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI

@MainActor enum Sprint61Verification {
    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("snapshot.json")
        let query = MachineEntityQuery(loadSnapshot: { try? JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: file)) })
        var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true); snapshot.profileID = UUID()
        func write() throws { try JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
        try write()
        let initial = try await query.suggestedEntities()
        precondition(initial.count == 6 && initial.filter(\.running).count == 5)
        let selected = initial[0]
        snapshot.guests?.removeFirst(); try write()
        let removed = try await query.entities(for: [selected.id])
        precondition(removed.first?.id == selected.id)
        let entry = MachineTimelineProvider.entry(for: SelectMachineIntent(machine: removed[0]), snapshot: snapshot)
        precondition(entry.machineKey == selected.guestKey && !snapshot.guests!.contains { MonitoringRules.guestKey($0) == entry.machineKey })
        RuntimeUIVerification.capture(MachineWidgetView(entry: .init(date: .now, snapshot: snapshot), machineKey: entry.machineKey).padding(16), size: .init(width: 360, height: 180), name: "sprint61-missing-machine")
        snapshot.guests = MockDataProvider.guests; try write()
        let restored = try await query.suggestedEntities(); precondition(restored.count == 6)
        let search = try await query.entities(matching: "100"); precondition(search.first?.vmid == 100)
        var created = MockDataProvider.guests[0]; created.id = 777; created.name = "new-container"
        snapshot.guests?.append(created); try write()
        let added = try await query.suggestedEntities(); precondition(added.count == 7 && added.last?.vmid == 777)
        // A cursor anchor remains fixed in screen space as magnification changes.
        for scale in [0.25, 0.5, 1.0, 2.0] {
            let viewport = CGSize(width: 1400, height: 800), point = CGPoint(x: 900, y: 350), pan = CGSize(width: 10, height: -20)
            let next = TopologyCamera.anchoredPan(anchor: point, viewport: viewport, pan: pan, oldScale: scale, newScale: scale*1.2)
            let world = CGPoint(x: (point.x-viewport.width/2-pan.width)/scale, y: (point.y-viewport.height/2-pan.height)/scale)
            let after = TopologyCamera.screenPoint(world, viewport: viewport, center: .zero, pan: next, scale: scale*1.2)
            precondition(hypot(after.x-point.x, after.y-point.y) < 0.0001)
        }
        let defaults = UserDefaults(suiteName: "dev.proxpulse.sprint61." + UUID().uuidString)!
        let model = DashboardModel(loadProfiles: false); defer { model.stop() }
        await model.refreshTopology()
        let host = NSHostingView(rootView: TopologyCanvasView(model: model).environment(\.topologyViewportHeight, 760).pulseAppearance().defaultAppStorage(defaults))
        let window = NSWindow(contentRect: .init(x: 60, y: 60, width: 1400, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .seconds(1))
        let probe = TopologyInteractionProbe.shared
        probe.zoomTo(1, nil); try await Task.sleep(for: .milliseconds(250)); precondition(abs(probe.scale-1) < 0.001)
        probe.zoomTo(1.2, nil); try await Task.sleep(for: .milliseconds(250)); precondition(probe.scale > 1)
        probe.filter("Выключены"); try await Task.sleep(for: .milliseconds(350))
        precondition(probe.centers.keys.filter { $0.hasPrefix("guest/") }.count == 1)
        probe.filter("Работают"); try await Task.sleep(for: .milliseconds(350))
        precondition(probe.centers.keys.filter { $0.hasPrefix("guest/") }.count == 5)
        probe.filter("Все"); probe.recenter(); try await Task.sleep(for: .milliseconds(350))
        precondition(probe.centers.keys.filter { $0.hasPrefix("guest/") }.count == 6)
        model.selectedPage = "Обзор"
        RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance(), size: .init(width: 1440, height: 1000), name: "sprint61-overview")
        print("PASS: query rereads file on every call, deletion tombstone/missing widget, added/restored machines, status rows; cursor-anchored zoom math; real canvas 100%/120% and all/running/stopped filters; full-height overview")
    }
}
#endif
