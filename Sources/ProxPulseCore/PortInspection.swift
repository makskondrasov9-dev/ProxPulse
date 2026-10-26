import Foundation
import Network
import Darwin

public struct ListeningPort: Codable, Identifiable, Hashable, Sendable {
    public var transport: String
    public var port: Int
    public var address: String
    public var process: String?
    public var id: String { "\(transport)/\(address)/\(port)" }
    public init(transport: String = "TCP", port: Int, address: String, process: String? = nil) {
        self.transport = transport; self.port = port; self.address = address; self.process = process
    }
    public var loopback: Bool {
        if address == "localhost" || address.hasPrefix("127.") { return true }
        var value = in6_addr()
        guard inet_pton(AF_INET6, address, &value) == 1 else { return false }
        let bytes = withUnsafeBytes(of: value) { Array($0) }
        return bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
    }
    public var service: String? { PortCatalog.services[port] }
    public var risky: Bool { PortCatalog.risky.contains(port) && !loopback }
}
public enum PortCatalog {
    public static let known = [21, 22, 23, 80, 443, 3000, 3001, 3306, 5173, 5432, 6379, 8000, 8080, 8443, 9200, 27017]
    public static let risky: Set<Int> = [21, 23, 3306, 5432, 6379, 27017, 9200]
    public static let services = [21:"FTP", 22:"SSH", 23:"Telnet", 80:"HTTP", 443:"HTTPS", 3306:"MySQL", 5432:"PostgreSQL", 6379:"Redis", 27017:"MongoDB", 9200:"Elasticsearch"]
    /// Only numeric guest addresses. Never scan this Mac's loopback, multicast or unspecified addresses.
    public static func usableAddress(_ raw: String) -> Bool {
        let value = raw.components(separatedBy: "/")[0]
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, value, &v4) == 1 {
            let bytes = value.split(separator: ".").compactMap { Int($0) }
            return bytes.count == 4 && bytes[0] > 0 && bytes[0] != 127 && bytes[0] < 224 && !(bytes[0] == 169 && bytes[1] == 254)
        }
        if inet_pton(AF_INET6, value, &v6) == 1 {
            let bytes = withUnsafeBytes(of: v6) { Array($0) }
            let zeroPrefix = bytes.prefix(15).allSatisfy { $0 == 0 }
            let mapped = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
            return !(zeroPrefix && bytes[15] <= 1) && !mapped && bytes[0] != 0xff && !(bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        return false
    }
}
public struct PortAudit: Codable, Sendable {
    public enum Source: String, Codable, Sendable { case guestAgent, containerExec, tcpScan, demo }
    public enum Coverage: String, Codable, Sendable { case complete, partial, unreachable, unavailable }
    public var date: Date = .now
    public var source: Source
    public var coverage: Coverage
    public var ports: [ListeningPort]
    public var addresses: [String]
    public var attempted: Int = 0
    public var inconclusive: Int = 0
    public var reason: String?
    public var hasRisk: Bool { ports.contains(where: \.risky) }
    public init(source: Source, coverage: Coverage, ports: [ListeningPort] = [], addresses: [String] = [], attempted: Int = 0, inconclusive: Int = 0, reason: String? = nil) {
        self.source = source; self.coverage = coverage; self.ports = ports; self.addresses = addresses; self.attempted = attempted; self.inconclusive = inconclusive; self.reason = reason
    }
    public static func demo(_ guest: Guest) -> PortAudit {
        .init(source: .demo, coverage: .complete, ports: [ListeningPort(port: 22, address: "0.0.0.0", process: "sshd"), ListeningPort(port: guest.id.isMultiple(of: 2) ? 3306 : 443, address: "0.0.0.0", process: guest.id.isMultiple(of: 2) ? "mysqld" : "nginx")])
    }
}
public enum PortInspectionError: Error, LocalizedError, Sendable {
    case unsupported, invalidOutput, executionFailed
    public var errorDescription: String? {
        switch self {
        case .unsupported: "API выполнения команд недоступен."
        case .invalidOutput: "Некорректный ответ списка сокетов."
        case .executionFailed: "Не удалось получить сокеты через Guest Agent."
        }
    }
}
public enum SocketListParser {
    public static func parse(_ text: String) throws -> [ListeningPort] {
        guard text.utf8.count <= 1_048_576 else { throw PortInspectionError.invalidOutput }
        var values: [String: ListeningPort] = [:]
        let processPattern = try NSRegularExpression(pattern: #"\("([^"]+)",pid=(\d+)"#)
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let proto = columns.first else { continue }
            if proto.lowercased() == "netid" { continue }
            guard ["tcp", "tcp6", "udp", "udp6"].contains(proto.lowercased()), columns.count >= 6 else { throw PortInspectionError.invalidOutput }
            let tcp = proto.lowercased().hasPrefix("tcp")
            guard (tcp && columns[1] == "LISTEN") || (!tcp && columns[1] == "UNCONN") else { continue }
            let local = columns[4]
            guard let split = local.lastIndex(of: ":"), let port = Int(local[local.index(after: split)...]), (1...65535).contains(port) else { throw PortInspectionError.invalidOutput }
            let address = String(local[..<split]).trimmingCharacters(in: CharacterSet(charactersIn: "[]")).components(separatedBy: "%")[0]
            let whole = String(line), ns = whole as NSString
            let names = processPattern.matches(in: whole, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) + " (pid " + ns.substring(with: $0.range(at: 2)) + ")" }
            let value = ListeningPort(transport: tcp ? "TCP" : "UDP", port: port, address: address, process: names.isEmpty ? nil : names.joined(separator: ", "))
            values[value.id] = value
        }
        return values.values.sorted { $0.port == $1.port ? $0.id < $1.id : $0.port < $1.port }
    }
}

public enum TCPProbeResult: Sendable { case open, refused, unknown }
/// Single-use connect-only probe. Every completion path closes its socket and timer.
private final class TCPAttempt: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "dev.proxpulse.port-probe", qos: .utility)
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<TCPProbeResult, Never>?
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    func run(address: String, port: UInt16, timeout: Double) async -> TCPProbeResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                guard !finished else { lock.unlock(); continuation.resume(returning: .unknown); return }
                self.continuation = continuation
                let connection = NWConnection(host: .init(address), port: .init(rawValue: port)!, using: .tcp)
                let timer = DispatchSource.makeTimerSource(queue: Self.queue)
                self.connection = connection; self.timer = timer
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready: self?.finish(.open)
                    case .failed(let error), .waiting(let error):
                        if case .posix(.ECONNREFUSED) = error { self?.finish(.refused) }
                        else { self?.finish(.unknown) }
                    case .cancelled: self?.finish(.unknown)
                    default: break
                    }
                }
                timer.setEventHandler { [weak self] in self?.finish(.unknown) }
                timer.schedule(deadline: .now() + max(0.01, min(10, timeout)))
                timer.resume(); connection.start(queue: Self.queue)
                lock.unlock()
            }
        } onCancel: { self.finish(.unknown) }
    }
    private func finish(_ result: TCPProbeResult) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, connection = self.connection, timer = self.timer
        self.continuation = nil; self.connection = nil; self.timer = nil
        lock.unlock()
        connection?.stateUpdateHandler = nil; connection?.cancel(); timer?.cancel()
        continuation?.resume(returning: result)
    }
}
public enum TCPPortScanner {
    public static func probe(address: String, port: UInt16, timeout: Double = 0.7) async -> TCPProbeResult {
        await TCPAttempt().run(address: address, port: port, timeout: timeout)
    }
    public static func scan(addresses: [String], ports: [Int] = PortCatalog.known, timeout: Double = 0.7) async throws -> PortAudit {
        var seen: Set<String> = []
        let targets = Array(addresses.map { $0.components(separatedBy: "/")[0] }.filter { PortCatalog.usableAddress($0) && seen.insert($0).inserted }.prefix(2))
        guard !targets.isEmpty else { return .init(source: .tcpScan, coverage: .unavailable, reason: "IP машины недоступен через API.") }
        let jobs = targets.flatMap { address in Array(Set(ports)).sorted().filter { (1...65535).contains($0) }.map { (address, $0) } }
        var found: [ListeningPort] = [], unknown = 0
        for start in stride(from: 0, to: jobs.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(jobs[start..<min(start+4, jobs.count)])
            let values = await withTaskGroup(of: (String, Int, TCPProbeResult).self) { group in
                for (address, port) in batch { group.addTask { (address, port, await probe(address: address, port: UInt16(port), timeout: timeout)) } }
                var values: [(String, Int, TCPProbeResult)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (address, port, result) in values {
                switch result { case .open: found.append(.init(port: port, address: address)); case .unknown: unknown += 1; case .refused: break }
            }
        }
        try Task.checkCancellation()
        return .init(source: .tcpScan, coverage: !jobs.isEmpty && unknown == jobs.count ? .unreachable : .partial, ports: found.sorted { $0.port == $1.port ? $0.id < $1.id : $0.port < $1.port }, addresses: targets, attempted: jobs.count, inconclusive: unknown)
    }
}
public actor PortInspectionService {
    private let api: ProxmoxAPIService
    public init(api: ProxmoxAPIService) { self.api = api }
    public func inspect(_ guest: Guest, addresses: [String] = []) async throws -> PortAudit {
        guard guest.running else { throw CancellationError() }
        var reason: String?
        do {
            let api = self.api
            let result = try await PollDeadline.run(seconds: 10) { try await api.listeningPorts(guest) }
            return .init(source: guest.kind == .qemu ? .guestAgent : .containerExec, coverage: .complete, ports: result)
        } catch { try Task.checkCancellation(); reason = error.localizedDescription }
        var targets = addresses
        if targets.isEmpty {
            do { targets = try await api.guestAddresses(guest, primaryFirst: true) }
            catch {
                try Task.checkCancellation()
                do { targets = try await api.guestConfiguration(guest).configuredAddresses }
                catch { try Task.checkCancellation(); return .init(source: .tcpScan, coverage: .unavailable, reason: error.localizedDescription) }
            }
        }
        var result = try await TCPPortScanner.scan(addresses: targets)
        result.reason = result.reason ?? reason
        return result
    }
}

public enum PortSecurityLevel: String, Codable, Sendable { case neutral, warning, unknown }
public struct PortSecuritySummary: Sendable {
    public var ports: [Int]
    public var level: PortSecurityLevel
    public var coverage: PortAudit.Coverage
    public var compactList: String { ports.map(String.init).joined(separator: ", ") }
}
extension WidgetSnapshot {
    public mutating func applyPortAudits(_ reports: [String: PortAudit]) {
        detectedPorts = [:]; securityLevel = [:]; portAuditedAt = [:]; portCoverage = [:]
        guard online != false, state != .error, state != .offline, state != .connecting else { return }
        for guest in guests ?? [] where guest.running {
            let key = MonitoringRules.guestKey(guest)
            guard let report = reports[key] else { continue }
            detectedPorts?[key] = Array(Set(report.ports.map(\.port))).sorted()
            securityLevel?[key] = report.hasRisk ? .warning : report.coverage == .unavailable || report.coverage == .unreachable || (report.ports.isEmpty && report.coverage != .complete) ? .unknown : .neutral
            portAuditedAt?[key] = report.date; portCoverage?[key] = report.coverage
        }
    }
    public func portSecurity(for guest: Guest, now: Date = .now) -> PortSecuritySummary? {
        let key = MonitoringRules.guestKey(guest)
        guard guest.running, online != false, state != .error, state != .offline, state != .connecting,
              guests?.contains(where: { MonitoringRules.guestKey($0) == key && $0.running }) == true,
              let ports = detectedPorts?[key], let level = securityLevel?[key] else { return nil }
        let age = now.timeIntervalSince(portAuditedAt?[key] ?? date)
        guard age >= -5 && age < 120 else { return nil }
        return .init(ports: Array(Set(ports.filter { (1...65535).contains($0) })).sorted(), level: level, coverage: portCoverage?[key] ?? .partial)
    }
}
