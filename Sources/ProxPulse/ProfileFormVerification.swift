#if DEBUG
import SwiftUI
import ProxPulseCore

struct ProfileFormFrames: SwiftUI.PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
@MainActor final class ProfileFormProbe {
    static let shared = ProfileFormProbe()
    var frames: [String: CGRect] = [:]
    var configure: ((String, AuthenticationMode, String) -> Void)?
    var enabled = false
    var preservesSecret = false
    var failure: String?
}
struct ProfileFormDebugModifier: ViewModifier {
    var enabled: Bool
    var preservesSecret: Bool
    var failure: String?
    var configure: (String, AuthenticationMode, String) -> Void
    func body(content: Content) -> some View {
        content.coordinateSpace(name: "profile-form")
            .onPreferenceChange(ProfileFormFrames.self) { frames in Task { @MainActor in ProfileFormProbe.shared.frames = frames } }
            .onAppear { ProfileFormProbe.shared.configure = configure; update() }
            .onChange(of: enabled) { update() }
            .onChange(of: preservesSecret) { update() }
            .onChange(of: failure) { update() }
    }
    private func update() {
        let probe = ProfileFormProbe.shared
        probe.enabled = enabled; probe.preservesSecret = preservesSecret; probe.failure = failure
    }
}
@MainActor enum ProfileFormVerification {
    static func run() async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop(); ProfileFormProbe.shared.configure = nil }
        let fixture = ServerProfile(name: "Token fixture", endpoint: URL(string: "https://localhost:" + (try String(contentsOfFile: ".build/profile-form-tls/port", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!, tokenID: "fixture@pve!proxpulse", allowInsecureSSL: true)
        try await Task.detached { try KeychainManager.save("saved-token-not-a-uuid", for: fixture.id) }.value
        defer { try? KeychainManager.delete(for: fixture.id) }
        let window = NSWindow(contentRect: .init(x: 60, y: 60, width: 640, height: 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        let probe = ProfileFormProbe.shared
        for editing in [false, true] {
            let host = NSHostingView(rootView: AddServerSheet(model: model, existing: editing ? fixture : nil).environment(\.pulseLanguage, "ru"))
            window.contentView = host
            try await Task.sleep(for: .milliseconds(600))
            window.setContentSize(host.fittingSize)
            probe.configure?(fixture.endpoint.absoluteString, .apiToken, editing ? "" : "  new-token-not-a-uuid \n")
            try await Task.sleep(for: .milliseconds(400))
            precondition(probe.enabled, "Token form incorrectly disabled")
            precondition(probe.preservesSecret == editing)
            capture(host, name: editing ? "token-edit-valid" : "token-add-valid")
            for key in ["test", "save"] {
                try await click(key, host: host, window: window)
                precondition(probe.failure?.contains("401") == true, "Button did not execute API test or display 401")
                precondition(probe.enabled, "Buttons remained disabled after server rejected token")
            }
            if editing {
                probe.configure?(fixture.endpoint.absoluteString, .apiToken, "   \n")
                try await Task.sleep(for: .milliseconds(250))
                precondition(probe.enabled && probe.preservesSecret)
                probe.configure?(fixture.endpoint.absoluteString, .apiToken, " replacement-token ")
                try await Task.sleep(for: .milliseconds(250))
                precondition(probe.enabled && !probe.preservesSecret)
                try await click("test", host: host, window: window)
            } else {
                probe.configure?(fixture.endpoint.absoluteString, .apiToken, " \n ")
                try await Task.sleep(for: .milliseconds(250))
                precondition(!probe.enabled, "New profile accepted an empty secret")
            }
        }
        let unchanged = try await Task.detached { try KeychainManager.token(for: fixture.id) == "saved-token-not-a-uuid" }.value
        precondition(unchanged, "Blank edit replaced the stored credential")
        let lines = try String(contentsOfFile: ".build/profile-form-tls/requests.jsonl", encoding: .utf8).split(separator: "\n")
        let records = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: String] }
        precondition(records.filter { $0["kind"] == "new" }.count == 2)
        precondition(records.filter { $0["kind"] == "saved" }.count == 2)
        precondition(records.filter { $0["kind"] == "replacement" }.count == 1)
        print("PASS: native Test + Save clicks on NEW and EDIT token forms reach HTTPS API; arbitrary non-UUID secrets trimmed; blank edit reuses Keychain; whitespace preserves saved credential; typed replacement sent; HTTP 401 visible and buttons reenabled; empty NEW secret rejected; stored Keychain fixture unchanged")
    }
    private static func capture(_ host: NSView, name: String) {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Bitmap missing") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Preview/" + name + ".png")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    private static func click(_ key: String, host: NSView, window: NSWindow) async throws {
        let probe = ProfileFormProbe.shared
        guard let rect = probe.frames[key] else { fatalError("Button frame missing") }
        let local = CGPoint(x: rect.midX, y: host.isFlipped ? rect.midY : host.bounds.height - rect.midY)
        let point = host.convert(local, to: nil)
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated().reversed() {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + Double(index)*0.08, windowNumber: window.windowNumber, context: nil, eventNumber: index, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            NSApp.postEvent(event, atStart: true)
        }
        for _ in 0..<4 {
            guard let event = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date(), inMode: .default, dequeue: true) else { break }
            NSApp.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(100))
        let deadline = Date().addingTimeInterval(5)
        while probe.failure == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }
}
#endif
