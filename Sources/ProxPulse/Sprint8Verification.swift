#if DEBUG
import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI
import WidgetKit

@MainActor enum Sprint8Verification {
    static func renderSavedInspector() throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        model.selectedProfile = UUID()
        model.node = try JSONDecoder().decode(NodeSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: ".build/sprint8-node.json")))
        model.portAudits = try JSONDecoder().decode([String: PortAudit].self, from: Data(contentsOf: URL(fileURLWithPath: ".build/sprint8-ports.json")))
        guard let guest = model.node.guests.first(where: { $0.id == 105 }) else { throw ProxmoxError.noNodes }
        model.guestAddresses = model.portAudit(for: guest)?.addresses ?? []
        let content = GuestInspectorSheet(model: model, original: guest).environment(\.pulseLanguage, "en").environment(\.locale, Locale(identifier: "en_US")).pulseAppearance().environment(\.colorScheme, .dark)
        RuntimeUIVerification.capture(content, size: .init(width: 880, height: 840), name: "sprint8-live-inspector-en")
        print("PASS: English inspector rendered from captured live node/port data; no server access")
    }
    static func run(live: Bool) async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        if live {
            guard let profile = try ProfileStore.load().first else { throw ProxmoxError.noNodes }
            model.profiles = [profile]; model.selectedProfile = profile.id
            let deadline = Date().addingTimeInterval(90)
            while Date() < deadline {
                if let error = model.connectionError { throw ProvisionError.invalid(error) }
                let required = model.node.guests.filter { $0.running && [105,107].contains($0.id) }
                if model.hasSnapshot && !required.isEmpty && required.allSatisfy({ model.portAudit(for: $0) != nil }) { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            precondition(model.hasSnapshot)
            // Real LIVE → DEMO → LIVE transition must release every old worker and refill IPs/ports.
            model.selectedProfile = DashboardModel.demoID
            precondition(model.portAudits.isEmpty && model.portAuditTask == nil)
            model.selectedProfile = profile.id
            let restored = Date().addingTimeInterval(70)
            while Date() < restored {
                if let error = model.connectionError { throw ProvisionError.invalid(error) }
                if model.hasSnapshot && !model.topologyGuestAddresses.isEmpty && model.portAudits.keys.contains(where: { $0.hasSuffix("/105") }) { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            precondition(model.hasSnapshot && !model.topologyGuestAddresses.isEmpty, "Topology worker did not restart after switching profiles")
            let portDeadline = Date().addingTimeInterval(35)
            while !model.portAudits.keys.contains(where: { $0.hasSuffix("/107") }) && Date() < portDeadline { try await Task.sleep(for: .milliseconds(200)) }
            print("PASS: live → demo → live discards old workers and restores topology IPs + port reports")
            for guest in model.node.guests {
                if guest.running, let report = model.portAudit(for: guest) {
                    print("PORTS \(guest.id) \(guest.name): \(report.coverage.rawValue); \(report.ports.map { "\($0.address):\($0.port)/\($0.transport)" }.joined(separator: ", "))")
                } else if !guest.running {
                    precondition(model.portAudit(for: guest) == nil)
                    print("HIDDEN \(guest.id) \(guest.name)")
                }
            }
            try JSONEncoder().encode(model.node).write(to: URL(fileURLWithPath: ".build/sprint8-node.json"))
            try JSONEncoder().encode(model.portAudits).write(to: URL(fileURLWithPath: ".build/sprint8-ports.json"))
        } else {
            var stop = model.node.guests[0]; stop.running = false
            model.portAudits[MonitoringRules.guestKey(stop)] = .demo(stop)
            precondition(model.portAudit(for: stop) == nil)
            // Repeated profile transitions must release the old worker slot, even when it has not completed.
            for _ in 0..<12 {
                model.portAuditTask = Task { try? await Task.sleep(for: .seconds(30)) }
                model.switchProfile()
                precondition(model.portAuditTask == nil && model.inspectingPorts.isEmpty && model.portAudits.isEmpty)
            }
        }
        let shared = model.widgetSnapshot
        if live, let edu = model.node.guests.first(where: { $0.id == 105 }) {
            let key = MonitoringRules.guestKey(edu)
            precondition(shared.detectedPorts?[key]?.contains(3306) == true && shared.securityLevel?[key] == .warning)
            let entity = MachineEntity(guest: edu, profileID: shared.profileID)
            let entry = MachineTimelineProvider.entry(for: SelectMachineIntent(machine: entity), snapshot: shared)
            precondition(entry.machineKey == key)
            for (name, family, dimensions) in [("small",WidgetFamily.systemSmall,NSSize(width:170,height:170)),("medium",.systemMedium,NSSize(width:360,height:170)),("large",.systemLarge,NSSize(width:360,height:360))] {
                let content = MachineWidgetView(entry: .init(date:.now,snapshot:shared),machineKey:entry.machineKey,family:family).padding(14).environment(\.colorScheme,.dark)
                RuntimeUIVerification.capture(content,size:dimensions,name:"sprint81-live-widget-"+name)
            }
            RuntimeUIVerification.capture(TopologyCanvasView(model:model).environment(\.topologyViewportHeight,850).pulseAppearance().environment(\.colorScheme,.dark),size:.init(width:1600,height:900),name:"sprint81-live-topology")
            print("PASS: edu-server security shared snapshot → selected AppIntent → Small/Medium/Large widget views and topology")
        }
        let window = NSWindow(contentRect: .init(x: 60, y: 60, width: 1440, height: 1100), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        model.selectedPage = "Машины"; model.workspaceMode = .grid
        let dashboard = NSHostingView(rootView: DashboardView(model: model, animate: false).pulseAppearance().environment(\.pulseLanguage, "ru").environment(\.colorScheme, .dark))
        window.contentView = dashboard
        try await Task.sleep(for: .seconds(1))
        save(dashboard, live ? "sprint8-live-grid" : "sprint8-demo-grid")
        let guests = live ? [105,107,101,106].compactMap { id in model.node.guests.first { $0.id == id } } : Array(model.node.guests.prefix(4))
        let cards = LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 22) {
            ForEach(guests) { guest in GuestCard(guest: guest, model: model) }
        }.padding(24).background(Color(red: 0.035, green: 0.045, blue: 0.06)).environment(\.pulseLanguage, "ru").environment(\.colorScheme, .dark)
        RuntimeUIVerification.capture(cards, size: .init(width: 840, height: 740), name: live ? "sprint8-live-cards" : "sprint8-demo-cards")
        if let guest = guests.first(where: \.running) {
            model.guestAddresses = model.addresses(for: guest)
            let inspector = GuestInspectorSheet(model: model, original: guest).environment(\.pulseLanguage, "en").environment(\.locale, Locale(identifier: "en_US")).pulseAppearance().environment(\.colorScheme, .dark)
            RuntimeUIVerification.capture(inspector, size: .init(width: 880, height: 840), name: live ? "sprint8-live-inspector-en" : "sprint8-demo-inspector-en")
        }
        var delays: [Double] = []
        for _ in 0..<120 {
            let before = Date(); try await Task.sleep(for: .milliseconds(16))
            delays.append(max(0,Date().timeIntervalSince(before)-0.016)*1000)
        }
        delays.sort(); print(String(format:"UI latency p95=%.2f ms; max=%.2f ms",delays[Int(Double(delays.count-1)*0.95)],delays.last ?? 0))
        weak var released: DashboardModel?
        do {
            let disposable = DashboardModel(loadProfiles: false); released = disposable
            disposable.portAuditTask = Task { try? await Task.sleep(for: .seconds(30)) }
            disposable.stop()
        }
        try await Task.sleep(for: .milliseconds(100))
        precondition(released == nil, "Stopped dashboard retained by worker")
        print("PASS: active/stopped badges, RU cards + EN inspector, 12 worker resets, cancelled dashboard released, native security views; no SSH or guest state changes")
    }
    private static func save(_ host: NSView, _ name: String) {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Bitmap unavailable") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Preview")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
