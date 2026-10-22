import Foundation

public struct UpdateHelper: Sendable {
    public let script: URL
    public let ready: URL
    public let log: URL
}
public enum UpdateHandoff {
    /// Generate the helper outside the bundle. The existing installer provides staged replacement,
    /// admin escalation when required, signature checks, rollback and WidgetKit registration.
    public static func prepare(package: VerifiedUpdate, installer: URL, parentPID: Int32) throws -> UpdateHelper {
        let helper = package.directory.appendingPathComponent("proxpulse_replace.sh")
        let ready = package.directory.appendingPathComponent("helper.ready")
        let log = package.directory.appendingPathComponent("replace.log")
        let copied = package.directory.appendingPathComponent("installer.sh")
        try FileManager.default.copyItem(at: installer, to: copied)
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let source = """
        #!/bin/bash
        set -euo pipefail
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export LC_ALL=C
        umask 077
        exec >\(quoted(log.path)) 2>&1
        echo ready >\(quoted(ready.path))
        if /bin/bash \(quoted(copied.path)) --dmg \(quoted(package.dmg.path)) --wait-pid \(parentPID); then
          rm -f \(quoted(package.dmg.path)) \(quoted(copied.path)) \(quoted(ready.path)) \(quoted(helper.path))
          echo SUCCESS
        else
          echo FAILED
          /usr/bin/open \(quoted(package.dmg.path)) || true
          exit 1
        fi
        """
        try source.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        return .init(script: helper, ready: ready, log: log)
    }
    public static func launch(_ helper: UpdateHelper) async throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = [helper.script.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 {
            try Task.checkCancellation()
            if !process.isRunning { throw CocoaError(.executableRuntimeMismatch) }
            if FileManager.default.fileExists(atPath: helper.ready.path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        process.terminate()
        throw URLError(.timedOut)
    }
}
