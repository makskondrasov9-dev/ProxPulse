import Foundation
import ProxPulseCore

/// A local ICMP probe only. No SSH, server credentials, known_hosts or remote executables.
enum TunnelProbe {
    static func ping(_ tunnel: ExternalTunnel) async -> TunnelMeasurement {
        guard tunnel.isValid else { return .init(peer: nil, pingMS: nil, reachable: false) }
        return await Task.detached(priority: .utility) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: tunnel.address.contains(":") ? "/sbin/ping6" : "/sbin/ping")
            process.arguments = ["-n", "-c", "1", "-W", "1000", tunnel.address]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+3, execute: timer)
                defer { timer.cancel() }
                let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                let pattern = #"time[=<]([0-9.]+)\s*ms"#
                let expression = try NSRegularExpression(pattern: pattern)
                let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
                let ms = match.flatMap { Range($0.range(at: 1), in: text) }.flatMap { Double(text[$0]) }
                return TunnelMeasurement(peer: tunnel.address, pingMS: ms, reachable: process.terminationStatus == 0)
            } catch { return TunnelMeasurement(peer: tunnel.address, pingMS: nil, reachable: false) }
        }.value
    }
}
