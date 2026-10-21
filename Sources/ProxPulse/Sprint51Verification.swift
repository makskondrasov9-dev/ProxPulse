#if DEBUG
import SwiftUI
import ProxPulseCore

@MainActor final class TopologyInteractionProbe {
    static let shared = TopologyInteractionProbe()
    var viewport = CGSize.zero
    var origin = CGPoint.zero
    var bounds = CGRect.zero
    var scale: CGFloat = 1
    var pan = CGSize.zero
    var centers: [String: CGPoint] = [:]
    var rectangles: [String: CGRect] = [:]
    var badgeCount = 0
    var positions: [String: CanvasPosition] = [:]
    var scope = ""
    var reset: () -> Void = {}
    var recenter: () -> Void = {}
    var zoomTo: (CGFloat, CGPoint?) -> Void = { _, _ in }
    var filter: (String) -> Void = { _ in }
    func record(viewport: CGSize, origin: CGPoint, bounds: CGRect, scale: CGFloat, pan: CGSize, cameraCenter: CGPoint, nodes: [(String, CGPoint, CGSize)], badgeCount: Int, positions: [String: CanvasPosition], scope: String, reset: @escaping () -> Void, recenter: @escaping () -> Void) {
        self.viewport = viewport; self.origin = origin; self.bounds = bounds; self.scale = scale; self.pan = CGSize(width: pan.width + (bounds.midX-cameraCenter.x)*scale, height: pan.height + (bounds.midY-cameraCenter.y)*scale)
        centers = Dictionary(uniqueKeysWithValues: nodes.map { id, point, _ in
            (id, CGPoint(x: origin.x + viewport.width/2 + pan.width + (point.x-cameraCenter.x)*scale, y: origin.y + viewport.height/2 + pan.height + (point.y-cameraCenter.y)*scale))
        })
        rectangles = Dictionary(uniqueKeysWithValues: nodes.map { id, _, size in
            let point = centers[id]!
            return (id, CGRect(x: point.x-size.width*scale/2, y: point.y-size.height*scale/2, width: size.width*scale, height: size.height*scale))
        })
        self.badgeCount = badgeCount
        self.positions = positions; self.scope = scope; self.reset = reset; self.recenter = recenter
    }
}

@MainActor enum InspectorHoverProbe { static var selected = false }

@MainActor enum Sprint51Verification {
    static func run(hardBounds: Bool = false) async throws {
        let suite = "dev.proxpulse.sprint51." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "pulse.topologyLineSpeeds")
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        model.selectedPage = "Машины"; model.workspaceMode = .topology
        await model.refreshTopology()
        let host = NSHostingView(rootView: TopologyCanvasView(model: model).environment(\.topologyViewportHeight, 900).pulseAppearance().defaultAppStorage(defaults).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: .init(x: 60, y: 60, width: 1440, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "ProxPulse — Sprint 5.1 interaction check"; window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .seconds(2))
        let probe = TopologyInteractionProbe.shared
        for delta in [CGSize(width: 10000, height: 10000), CGSize(width: -20000, height: -18000)] {
            let previousPan = probe.pan
            let start = CGPoint(x: probe.origin.x + 20, y: probe.origin.y + probe.viewport.height - 20)
            await drag(window: window, host: host, start: start, end: CGPoint(x: start.x+delta.width, y: start.y+delta.height))
            try await Task.sleep(for: .milliseconds(400))
            precondition(abs(previousPan.width - probe.pan.width) > 1, "Background drag was not delivered")
            let visible = TopologyCamera.screenBounds(bounds: probe.bounds, viewport: probe.viewport, scale: probe.scale, pan: probe.pan)
            precondition(visible.minX >= 23.99 && visible.minY >= 23.99 && visible.maxX <= probe.viewport.width-23.99 && visible.maxY <= probe.viewport.height-23.99, "Pan escaped padded viewport")
        }
        probe.recenter(); try await Task.sleep(for: .milliseconds(300))
        for prefix in ["host/", "bridge/", "tunnel/", "guest/"] {
            guard let (id, point) = probe.centers.sorted(by: { $0.key < $1.key }).first(where: { $0.key.hasPrefix(prefix) }) else { fatalError("Missing node type") }
            await drag(window: window, host: host, start: point, end: CGPoint(x: point.x+30, y: point.y-24))
            try await Task.sleep(for: .milliseconds(450))
            precondition(probe.positions[id] != nil, "Native drag did not move \(id)")
            precondition(model.inspectedGuest == nil, "Drag incorrectly opened inspector")
        }
        let archive = TopologyLayoutArchive(data: defaults.data(forKey: "pulse.topologyLayout.centered.v2") ?? Data())
        precondition(archive.positions(in: probe.scope).count >= 4, "Node positions were not persisted")
        let restored = NSHostingView(rootView: TopologyCanvasView(model: model).environment(\.topologyViewportHeight, 900).pulseAppearance().defaultAppStorage(defaults).environment(\.colorScheme, .dark))
        window.contentView = restored
        try await Task.sleep(for: .milliseconds(800))
        precondition(probe.positions.count >= 4, "Recreated canvas did not reload persisted positions")
        save(restored, "sprint51-layout-restored")
        probe.reset(); try await Task.sleep(for: .milliseconds(350))
        precondition(probe.positions.isEmpty)
        precondition(TopologyLayoutArchive(data: defaults.data(forKey: "pulse.topologyLayout.centered.v2") ?? Data()).positions(in: probe.scope).isEmpty)
        save(restored, "sprint51-auto-layout")
        if hardBounds {
            for prefix in ["host/", "bridge/", "tunnel/", "guest/"] {
                for delta in [CGSize(width: -20000, height: -20000), CGSize(width: 20000, height: -20000), CGSize(width: -20000, height: 20000), CGSize(width: 20000, height: 20000)] {
                    probe.reset(); try await Task.sleep(for: .milliseconds(150))
                    let (id, point) = probe.centers.sorted { $0.key < $1.key }.first { $0.key.hasPrefix(prefix) }!
                    await drag(window: window, host: restored, start: point, end: CGPoint(x: point.x+delta.width, y: point.y+delta.height))
                    try await Task.sleep(for: .milliseconds(150))
                    precondition(probe.positions[id] != nil, "Corner drag was not delivered to intended node")
                    let visible = CGRect(x: probe.origin.x+23.99, y: probe.origin.y+23.99, width: probe.viewport.width-47.98, height: probe.viewport.height-47.98)
                    precondition(probe.rectangles.values.allSatisfy { visible.contains($0) }, "A full card escaped the viewport")
                    let rect = probe.rectangles[id]!
                    let x = delta.width < 0 ? rect.minX-probe.origin.x : probe.origin.x+probe.viewport.width-rect.maxX
                    let y = delta.height < 0 ? rect.minY-probe.origin.y : probe.origin.y+probe.viewport.height-rect.maxY
                    precondition(abs(x-24) < 0.1 && abs(y-24) < 0.1, "Card did not stop precisely at 24pt wall")
                    precondition(model.inspectedGuest == nil)
                }
            }
            save(restored, "sprint52-hard-wall")
            probe.reset(); try await Task.sleep(for: .milliseconds(200))
            precondition(probe.badgeCount > 0)
            for index in model.node.guests.indices {
                model.node.guests[index].receiveBps = 0; model.node.guests[index].transmitBps = 0
            }
            model.tunnelMeasurements = [:]
            try await Task.sleep(for: .milliseconds(150))
            precondition(probe.badgeCount == 0, "Idle speed badges are still visible")
            save(restored, "sprint52-idle-lines")
            let index = model.node.guests.firstIndex { $0.running }!
            model.node.guests[index].receiveBps = 286; model.node.guests[index].transmitBps = 91
            try await Task.sleep(for: .milliseconds(150))
            precondition(probe.badgeCount == 2, "Active guest and its bridge must show exactly two midpoint badges")
            save(restored, "sprint52-active-badges")
            print("PASS: native drags of all 4 node kinds into all 4 corners stop full cards exactly 24pt from edges; pan clamped; idle badges hidden; active guest/bridge badges restored; persistence/reset preserved")
            return
        }
        if let point = probe.centers.first(where: { $0.key.hasPrefix("guest/") })?.value {
            await drag(window: window, host: restored, start: point, end: point)
            try await Task.sleep(for: .milliseconds(300))
            precondition(model.inspectedGuest != nil, "Card click no longer opens inspector")
            model.inspectedGuest = nil
        }
        let guest = model.node.guests.first { ($0.swapGB ?? 0) > 0 }!
        model.inspect(guest); model.inspectedGuest = nil
        RuntimeUIVerification.capture(GuestInspectorSheet(model: model, original: guest).pulseAppearance().defaultAppStorage(defaults).environment(\.colorScheme, .dark), size: .init(width: 880, height: 840), name: "sprint51-inspector-dark")
        RuntimeUIVerification.capture(GuestInspectorSheet(model: model, original: guest).pulseAppearance().defaultAppStorage(defaults).environment(\.colorScheme, .light), size: .init(width: 880, height: 840), name: "sprint51-inspector-light")
        let chart = NSHostingView(rootView: InspectorHistoryChart(title: "CPU", unit: "%", color: .cyan, samples: model.samples(for: guest), fixedMaximum: 100) { $0.cpu * 100 }.padding(20).environment(\.colorScheme, .dark))
        window.contentView = chart; window.setContentSize(.init(width: 500, height: 250)); window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        let location = chart.convert(CGPoint(x: 260, y: 140), to: nil)
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        NSApp.sendEvent(event)
        let previousCursor = CGEvent(source: nil)!.location
        defer { CGWarpMouseCursorPosition(previousCursor) }
        let screenPoint = window.convertPoint(toScreen: location)
        let cursor = CGPoint(x: screenPoint.x, y: NSScreen.screens[0].frame.height - screenPoint.y)
        CGWarpMouseCursorPosition(cursor)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cursor, mouseButton: .left)?.postToPid(getpid())
        try await Task.sleep(for: .milliseconds(150))
        for _ in 0..<20 {
            guard let queued = NSApp.nextEvent(matching: [.mouseMoved, .mouseEntered, .mouseExited], until: Date(), inMode: .default, dequeue: true) else { break }
            NSApp.sendEvent(queued)
        }
        try await Task.sleep(for: .milliseconds(300))
        precondition(InspectorHoverProbe.selected, "Native chart hover did not select a sample")
        save(chart, "sprint51-chart-hover")
        print("PASS: native background drag at ±20000pt remains within padding; host/bridge/VPS/guest mouse drags persist; drag does not open inspector; restored layout/reset and dark/light inspector rendered")
    }
    private static func save(_ host: NSView, _ name: String) {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Preview")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    }
    private static func drag(window: NSWindow, host: NSView, start: CGPoint, end: CGPoint) async {
        let now = ProcessInfo.processInfo.systemUptime
        let items: [(NSEvent.EventType, CGPoint)] = [(.leftMouseDown,start),(.leftMouseDragged,CGPoint(x: start.x+(end.x-start.x)*0.3,y: start.y+(end.y-start.y)*0.3)),(.leftMouseDragged,end),(.leftMouseUp,end)]
        for (index, item) in items.enumerated().reversed() {
            let point = host.convert(item.1, to: nil)
            let event = NSEvent.mouseEvent(with: item.0, location: point, modifierFlags: [], timestamp: now+Double(index)*0.08, windowNumber: window.windowNumber, context: nil, eventNumber: index, clickCount: 1, pressure: item.0 == .leftMouseUp ? 0 : 1)!
            NSApp.postEvent(event, atStart: true)
        }
        for _ in 0..<12 {
            guard let event = NSApp.nextEvent(matching: [.leftMouseDown,.leftMouseDragged,.leftMouseUp], until: Date(), inMode: .default, dequeue: true) else { break }
            NSApp.sendEvent(event)
        }
    }
}
#endif
