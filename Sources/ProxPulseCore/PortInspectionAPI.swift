import Foundation

extension ProxmoxAPIService {
    private struct DirectoryEntry: Decodable, Sendable { var subdir: String }
    private struct ExecStarted: Decodable, Sendable { var pid: Int }
    private struct ExecResult: Decodable, Sendable {
        var exited: Bool
        var exitcode: Int?
        var output: String?
        var truncated: Bool
        enum CodingKeys: String, CodingKey { case exited, exitcode; case output = "out-data"; case truncated = "out-truncated" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exited = try c.pveBool(.exited) ?? false; exitcode = try c.pveInt(.exitcode)
            output = try c.decodeIfPresent(String.self, forKey: .output); truncated = try c.pveBool(.truncated) ?? false
        }
    }
    private struct ContainerOutput: Decodable, Sendable { var stdout: String }
    public func listeningPorts(_ guest: Guest) async throws -> [ListeningPort] {
        guard guest.running else { throw CancellationError() }
        let base = ["nodes", guest.node, guest.kind.rawValue, String(guest.id)]
        // Standard LXC API has no exec endpoint. Only use one if the server advertises it.
        if guest.kind == .lxc {
            let supported: Bool
            if let cached = lxcPortExecCapabilities[guest.node] { supported = cached }
            else {
                let entries = try await request(base, as: [DirectoryEntry].self)
                supported = entries.contains { $0.subdir == "exec" }; lxcPortExecCapabilities[guest.node] = supported
            }
            guard supported else { throw PortInspectionError.unsupported }
            let output = try await request(base + ["exec"], method: "POST", form: ["command":"ss -H -lntup"], as: ContainerOutput.self)
            return try SocketListParser.parse(output.stdout)
        }
        // No shell or user-controlled command arguments; the command only lists listening sockets.
        let command = Data(#"{"command":["ss","-H","-lntup"]}"#.utf8)
        let started = try await request(base + ["agent", "exec"], method: "POST", json: command, as: ExecStarted.self)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            let result = try await request(base + ["agent", "exec-status"], query: [.init(name: "pid", value: String(started.pid))], as: ExecResult.self)
            if result.exited {
                guard result.exitcode == 0, !result.truncated else { throw PortInspectionError.executionFailed }
                return try SocketListParser.parse(result.output ?? "")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw URLError(.timedOut)
    }
}
