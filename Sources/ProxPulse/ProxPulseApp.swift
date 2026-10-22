import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI
import WidgetKit

@main struct ProxPulseApp: App {
    @NSApplicationDelegateAdaptor(PulseAppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @State private var model = DashboardModel()
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--verify-profile-form") {
            Task { @MainActor in
                do { try await ProfileFormVerification.run(); exit(0) }
                catch { print("PROFILE FORM: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint7") {
            Task { @MainActor in
                do { try await Sprint7Verification.run(); exit(0) }
                catch { print("SPRINT 7: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint61") {
            Task { @MainActor in
                do { try await Sprint61Verification.run(); exit(0) }
                catch { print("SPRINT 6.1: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint622") {
            Task { @MainActor in
                do { try await Sprint622Verification.run(); exit(0) }
                catch { print("SPRINT 6.2.2: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint6") {
            Task { @MainActor in
                do { try await Sprint6Verification.run(); exit(0) }
                catch { print("SPRINT 6: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--release-media") {
            Task { @MainActor in
                do { try await ReleaseMediaVerification.run(); exit(0) }
                catch { print("RELEASE MEDIA: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint51") || CommandLine.arguments.contains("--verify-sprint52") {
            Task { @MainActor in
                do { try await Sprint51Verification.run(hardBounds: CommandLine.arguments.contains("--verify-sprint52")); exit(0) }
                catch { print("SPRINT 5.1 CHECK: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-topology-live") || CommandLine.arguments.contains("--verify-topology-demo") {
            Task { @MainActor in
                do { try await TopologyVerification.run(live: CommandLine.arguments.contains("--verify-topology-live")); exit(0) }
                catch { print("TOPOLOGY CHECK: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-sprint5") {
            Task { @MainActor in
                do { try await Sprint5Verification.run(); exit(0) }
                catch { print("FAIL Sprint 5: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-widget-share") {
            do {
                guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroup) else { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let probe = directory.appendingPathComponent("probe-" + UUID().uuidString + ".json")
                defer { try? FileManager.default.removeItem(at: probe) }
                let data = try JSONEncoder().encode(WidgetSnapshot(node: MockDataProvider.node, isDemo: true))
                try data.write(to: probe, options: .atomic)
                let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: probe))
                precondition(decoded.guests?.count == 6)
                print("PASS: App Group container is writable and widget payload round-trips")
                exit(0)
            } catch { print("App Group unavailable: \(error.localizedDescription)"); exit(1) }
        }
        if CommandLine.arguments.contains("--verify-ui") { RuntimeUIVerification.run(); exit(0) }
        if CommandLine.arguments.contains("--verify-widget-cache") {
            guard let snapshot = WidgetSnapshotStore.load(), let preferences = WidgetSnapshotStore.loadPreferences(),
                  snapshot.date == preferences.date, snapshot.profileID == preferences.profileID,
                  snapshot.isDemo == preferences.isDemo, snapshot.state == preferences.state else {
                print("FAIL: shared defaults and atomic snapshot disagree"); exit(1)
            }
            print("PASS: independent reader group=\(WidgetSnapshotStore.appGroup) node=\(snapshot.node) demo=\(snapshot.isDemo) state=\(snapshot.state?.rawValue ?? "legacy")")
            exit(0)
        }
        if CommandLine.arguments.contains("--verify-widget-switch") {
            Task { @MainActor in
                let model = DashboardModel()
                do {
                    guard let profile = model.profiles.first else { throw ProxmoxError.noNodes }
                    model.selectedProfile = profile.id
                    let connecting = WidgetSnapshotStore.load()
                    precondition(connecting?.isDemo == false && connecting?.state == .connecting && connecting?.profileID == profile.id)
                    @MainActor func waitForLive() async throws {
                        for _ in 0..<150 {
                            try await Task.sleep(for: .milliseconds(200))
                            if model.hasSnapshot && model.node.online && model.connectionError == nil { return }
                            if let error = model.connectionError { throw NSError(domain: "WidgetSync", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                        }
                        throw ProxmoxError.taskTimeout
                    }
                    try await waitForLive()
                    let first = WidgetSnapshotStore.load()
                    precondition(first?.isDemo == false && first?.state == .live && first?.node == model.node.id)
                    print("PASS: initial LIVE=\(model.node.id)")
                    model.selectedProfile = DashboardModel.demoID
                    precondition(WidgetSnapshotStore.load()?.isDemo == true && WidgetSnapshotStore.loadPreferences()?.state == .demo)
                    print("PASS: DEMO selected, shared snapshot updated synchronously")
                    try await Task.sleep(for: .seconds(3))
                    model.selectedProfile = profile.id
                    let pending = WidgetSnapshotStore.load()
                    precondition(pending?.isDemo == false && pending?.state == .connecting && pending?.guests?.isEmpty == true)
                    precondition(WidgetSnapshotStore.loadPreferences()?.isDemo == false)
                    print("PASS: LIVE selected, DEMO cleared before any API response")
                    try await waitForLive()
                    let live = WidgetSnapshotStore.load()
                    precondition(live?.state == .live && live?.isDemo == false && live?.node == model.node.id)
                    precondition(WidgetSnapshotStore.loadPreferences()?.profileID == profile.id)
                    print("PASS: first LIVE reply published immediately, node=\(model.node.id), guests=\(model.node.guests.count)")
                    let date = live!.date
                    try await Task.sleep(for: .seconds(24))
                    let next = WidgetSnapshotStore.load()
                    precondition(next!.date > date && next?.state == .live && next?.isDemo == false)
                    print("PASS: live polling continues publishing; date advanced=\(next!.date.timeIntervalSince(date)) seconds")
                    model.stop(); exit(0)
                } catch { model.stop(); print("FAIL widget switch: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-demo") {
            let demo = DashboardModel(loadProfiles: false)
            precondition(demo.filteredGuests.count == 6)
            demo.guestFilter = "Выключены"
            precondition(demo.filteredGuests.map(\.id) == [105])
            demo.guestFilter = "Все"; demo.search = "101"
            precondition(demo.filteredGuests.map(\.name) == ["docker-engine"])
            demo.search = ""; demo.control(demo.node.guests[5], running: true)
            precondition(demo.node.guests.filter(\.running).count == 6)
            demo.control(demo.node.guests[0], running: false)
            precondition(!demo.node.guests[0].running)
            demo.profiles = [MockDataProvider.profiles[1]]
            demo.selectedProfile = demo.profiles[0].id
            precondition(!demo.hasSnapshot && demo.node.guests.isEmpty && demo.node.storage.children.isEmpty)
            demo.selectedProfile = DashboardModel.demoID
            precondition(demo.hasSnapshot && demo.node.id == "pve-01" && demo.node.guests.count == 6)
            demo.request(demo.node.guests[0], action: .reboot)
            precondition(demo.pendingAction?.action == .reboot)
            demo.pendingAction = nil
            demo.perform(demo.node.guests[0], action: .shutdown)
            precondition(!demo.node.guests[0].running)
            demo.perform(demo.node.guests[0], action: .start)
            precondition(demo.node.guests[0].running)
            var publications: [(WidgetSnapshot, Bool)] = []
            demo.widgetTestSink = { publications.append(($0, $1)) }
            demo.selectedProfile = demo.profiles[0].id
            precondition(publications.last?.0.state == .connecting && publications.last?.0.isDemo == false && publications.last?.1 == true)
            demo.selectedProfile = DashboardModel.demoID
            precondition(publications.last?.0.state == .demo && publications.last?.1 == true)
            demo.selectedProfile = demo.profiles[0].id
            precondition(publications.last?.0.state == .connecting && publications.last?.0.guests?.isEmpty == true)
            demo.node = MockDataProvider.studio; demo.hasSnapshot = true; demo.lastUpdated = Date()
            demo.publishSnapshot()
            precondition(publications.last?.0.state == .live && publications.last?.1 == true)
            demo.publishSnapshot()
            precondition(publications.last?.1 == false)
            demo.stop()
            print("PASS: synchronous widget DEMO → connecting → LIVE publications; first response forces refresh; following poll is throttled")
            print("PASS: demo filters, search, start/stop, profile switch")
            exit(0)
        }
        if CommandLine.arguments.contains("--render-preview") {
            // Render the real SwiftUI hierarchy, with stable ring values and no network.
            let destination = ProcessInfo.processInfo.environment["PROXPULSE_PREVIEW_DIR"] ?? FileManager.default.currentDirectoryPath + "/Preview"
            try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            for (name, scheme) in [("dashboard-dark", ColorScheme.dark), ("dashboard-light", ColorScheme.light)] {
                let view = DashboardView(model: DashboardModel(), animate: false).frame(width: 1440, height: 1000).environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "ru_RU"))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1000), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                window.display()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("\(name).png")) }
                }
                window.contentView = nil

            }
            for (name, content, size) in [
                ("add-server", AnyView(AddServerSheet(model: DashboardModel(loadProfiles: false))), NSSize(width: 640, height: 670)),
                ("incident-sheet", AnyView(IncidentSheet(model: DashboardModel(loadProfiles: false))), NSSize(width: 736, height: 806))
            ] {
                let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark).background(Color(red: 0.055, green: 0.065, blue: 0.085)))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host; window.display(); host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("\(name).png")) }
                }
                window.contentView = nil
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--verify-telemetry") {
            Task { @MainActor in
                do {
                    guard let profile = try ProfileStore.load().first else { throw ProxmoxError.noNodes }
                    let api = try ProxmoxAPIService(profile: profile)
                    let first = try await api.snapshot()
                    try await Task.sleep(for: .seconds(4))
                    let result = try await api.snapshot()
                    let model = DashboardModel(loadProfiles: false)
                    model.profiles = [profile]; model.selectedProfile = profile.id; model.stop()
                    model.node = result.node; model.hasSnapshot = true; model.isLoading = false
                    for guest in result.node.guests {
                        let key = MonitoringRules.guestKey(guest)
                        model.guestHistory[key] = first.node.guests.filter { MonitoringRules.guestKey($0) == key }.map { GuestSample(guest: $0, date: $0.telemetryDate ?? Date()) }
                        model.guestHistory[key, default: []].append(GuestSample(guest: guest, date: guest.telemetryDate ?? Date()))
                        print("GUEST \(guest.id) \(guest.kind.rawValue): vCPU=\(guest.cpuCount.map(String.init) ?? "unavailable"); RAM=\(guest.memoryGB)/\(guest.maxMemoryGB) GB; SWAP=\(guest.swapGB.map(String.init(describing:)) ?? "unavailable")/\(guest.maxSwapGB.map(String.init(describing:)) ?? "unavailable") GB; disk=\(guest.diskUsageAvailable == true ? String(guest.diskGB) : "unavailable")/\(guest.maxDiskGB.map(String.init(describing:)) ?? "unavailable") GB; RX=\(guest.receiveBps.map(String.init(describing:)) ?? "first sample") B/s; telemetry=\(guest.telemetryError ?? "OK")")
                    }
                    RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance(), size: .init(width: 1440, height: 1100), name: "sprint4-live-dashboard")
                    model.selectedPage = "Настройки"
                    RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance(), size: .init(width: 1440, height: 1100), name: "sprint4-live-settings")
                    if let guest = result.node.guests.first(where: { ($0.swapGB ?? 0) > 0 }) ?? result.node.guests.first {
                        do { model.guestAddresses = try await api.guestAddresses(guest) } catch { model.addressError = error.localizedDescription }
                        RuntimeUIVerification.capture(GuestInspectorSheet(model: model, original: guest).pulseAppearance(), size: .init(width: 880, height: 840), name: "sprint4-live-inspector")
                    }
                    guard result.node.guests.allSatisfy({ $0.telemetryDate != nil }) else { throw ProxmoxError.invalidResponse }
                    print("PASS: active server per-guest telemetry, two network counter samples, live dashboard/settings/inspector rendered")
                    exit(0)
                } catch { print("TELEMETRY CHECK: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        if CommandLine.arguments.contains("--verify-live") {
            Task {
                do {
                    guard let profile = try ProfileStore.load().first else { print("Нет сохранённых профилей. Добавьте сервер в приложении."); exit(2) }
                    let api = try ProxmoxAPIService(profile: profile)
                    let snapshot = try await api.snapshot()
                    let report = await api.diagnostics(node: snapshot.node.id, storage: snapshot.node.storage, guests: snapshot.node.guests)
                    print("LIVE PASS: node=\(snapshot.node.id); CPU=\(Int(snapshot.node.cpu * 100))%; RAM=\(snapshot.node.memoryGB.formatted()) GB; guests=\(snapshot.node.guests.count); storage=\(snapshot.node.storage.children.count); diagnostic checks=\(report.checks.count)")
                    exit(0)
                } catch { print("LIVE CHECK: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        #endif
    }
    var body: some Scene {
        Window("ProxPulse", id: "dashboard") {
            DashboardView(model: model).pulseAppearance().task { delegate.model = model; await model.start(); model.publishSnapshot(); await model.updates.atLaunch(); if CommandLine.arguments.contains("--add-server") { model.showAddServer = true } }
            .onOpenURL { url in if url.scheme == "proxpulse" { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) } }
        }.defaultSize(width: 1280, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Настройки…", language: UserDefaults.standard.string(forKey: PreferenceKey.language) ?? "ru")) {
                    model.selectedPage = "Настройки"; openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true)
                }.keyboardShortcut(",", modifiers: .command)
            }
        }
        Settings { SettingsView(model: model).pulseAppearance() }
        MenuBarExtra {
            MenuBarPopover(model: model).pulseAppearance()
        } label: {
            Image(systemName: model.node.online ? "circle.inset.filled" : "circle.dotted")
                .accessibilityLabel("ProxPulse · \(model.node.id) · \(model.node.online ? "Online" : "Offline")")
        }.menuBarExtraStyle(.window)
    }
}

@MainActor final class PulseAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: DashboardModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model?.stop(); return .terminateNow }
}
