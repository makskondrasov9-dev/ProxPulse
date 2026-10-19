import AppKit
import ProxPulseCore

@MainActor enum TerminalLauncher {
    static func open(host: String, user: String, guest: Guest? = nil) async throws {
        let command = try SSHCommand.make(host: host, user: user, guest: guest)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ProxPulse/Consoles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(UUID().uuidString + ".command")
        try command.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw CocoaError(.fileNoSuchFile) }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
