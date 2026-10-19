#if DEBUG
import SwiftUI
import WidgetKit
import ProxPulseCore
import ProxPulseWidgetUI

@MainActor private final class AppearanceObservation {
    var language = ""
    var accent = AccentChoice.blue
    var scheme = ColorScheme.light
}
private struct AppearanceProbe: View {
    let observation: AppearanceObservation
    @Environment(\.pulseLanguage) private var language
    @Environment(\.pulseAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onAppear { update() }
            .onChange(of: language) { update() }
            .onChange(of: accent) { update() }
            .onChange(of: scheme) { update() }
    }
    private func update() { observation.language = language; observation.accent = accent; observation.scheme = scheme }
}
@MainActor enum RuntimeUIVerification {
    static func run() {
        let domain = "dev.proxpulse.ui-verification." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: domain) else { fatalError("No test preferences") }
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("ru", forKey: PreferenceKey.language)
        defaults.set("dark", forKey: PreferenceKey.appearance)
        defaults.set("blue", forKey: PreferenceKey.accent)
        let observation = AppearanceObservation()
        let demo = DashboardModel(loadProfiles: false)
        demo.search = "home"
        let content = DashboardView(model: demo, animate: false)
            .overlay { AppearanceProbe(observation: observation) }
            .pulseAppearance().defaultAppStorage(defaults)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1440, height: 1000), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ProxPulse · Runtime UI verification"
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        settle(host)
        precondition(observation.language == "ru" && observation.scheme == .dark)
        let ru = save(host, "runtime-ru-dark")
        defaults.set("en", forKey: PreferenceKey.language)
        defaults.set("light", forKey: PreferenceKey.appearance)
        defaults.set("emerald", forKey: PreferenceKey.accent)
        settle(host)
        precondition(observation.language == "en" && observation.scheme == .light && observation.accent == .emerald)
        precondition(L10n.text("Обзор", language: observation.language) == "Overview")
        let en = save(host, "runtime-en-light")
        precondition(ru != en && demo.search == "home", "Appearance change must not reset view model state")
        defaults.set("dark", forKey: PreferenceKey.appearance)
        defaults.set("purple", forKey: PreferenceKey.accent)
        settle(host)
        precondition(observation.scheme == .dark && observation.accent == .purple)
        save(host, "runtime-en-dark-purple")
        defaults.set("ru", forKey: PreferenceKey.language)
        settle(host)
        precondition(observation.language == "ru" && observation.scheme == .dark)
        save(host, "runtime-ru-dark-purple")
        window.orderOut(nil); window.contentView = nil
        demo.selectedPage = "Настройки"
        capture(DashboardView(model: demo, animate: false).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 1440, height: 1100), name: "sprint4-settings-ru")
        defaults.set("en", forKey: PreferenceKey.language)
        settle(host)
        capture(DashboardView(model: demo, animate: false).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 1440, height: 1100), name: "sprint4-settings-en")
        precondition(demo.selectedPage == "Настройки" && demo.search == "home")
        if let guest = demo.node.guests.first(where: { ($0.swapGB ?? 0) > 0 }) {
            demo.inspect(guest)
            capture(GuestInspectorSheet(model: demo, original: guest).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 760, height: 780), name: "sprint4-inspector-en")
            demo.inspectedGuest = nil
        }
        capture(AddServerSheet(model: demo, existing: MockDataProvider.profiles[0]).pulseAppearance().defaultAppStorage(defaults), size: .init(width: 640, height: 735), name: "sprint4-edit-profile-en")
        let snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
        let families: [(String, WidgetFamily, NSSize)] = [("small", .systemSmall, .init(width: 170, height: 170)), ("medium", .systemMedium, .init(width: 360, height: 170)), ("large", .systemLarge, .init(width: 360, height: 390))]
        for (name, family, size) in families {
            capture(PulseWidgetView(entry: .init(date: .now, snapshot: snapshot), family: family).padding(16).environment(\.colorScheme, .dark), size: size, name: "widget-" + name)
        }
        print("PASS: same running NSHostingView RU→EN→RU, dark/light, blue/emerald/purple, preserved model state; settings and all widget sizes rendered")
    }
    private static func settle(_ host: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @discardableResult private static func save(_ host: NSView, _ name: String) -> Data {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Preview")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try data.write(to: directory.appendingPathComponent(name + ".png")) } catch { fatalError("Could not save render") }
        return data
    }
    static func capture<Content: View>(_ content: Content, size: NSSize, name: String) {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(Color(red: 0.055, green: 0.065, blue: 0.085)))
        let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = host; window.display(); settle(host); save(host, name)
        window.contentView = nil
    }
}

#endif
