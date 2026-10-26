import Foundation
import Network
import ProxPulseCore

private final class PortsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(!Thread.isMainThread && request.timeoutInterval == 10)
        var value: Any = [:]
        let path = request.url!.path, host = request.url!.host!
        var status = 200
        if path.hasSuffix("/nodes") { value = [["node":"node", "status":"online"]] }
        else if path.hasSuffix("/node/status") { value = ["cpu":"0.1", "memory":["used":"1024", "total":"4096"], "uptime":"100"] }
        else if path.hasSuffix("/cluster/resources") { value = [["id":"lxc/105", "vmid":105, "type":"lxc", "name":"fixture", "node":"node", "status":"running", "mem":1024, "maxmem":4096]] }
        else if path.hasSuffix("/storage") { value = [] }
        else if path.hasSuffix("/agent/exec") {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream, data.isEmpty {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            precondition(json["command"] as? [String] == ["ss", "-H", "-lntup"])
            precondition(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            value = ["pid": 123]
        } else if path.hasSuffix("/exec-status") {
            value = ["exited":1, "exitcode":"0", "out-data":"tcp LISTEN 0 128 0.0.0.0:3306 0.0.0.0:* users:((\"mysqld\",pid=123,fd=8))\nudp UNCONN 0 0 [::]:53 [::]:*", "out-truncated":false]
            if host == "empty.fixture" { value = ["exited":true, "exitcode":0] }
        } else if path.hasSuffix("/interfaces") {
            value = [["name":"eth0", "inet":"192.0.2.50/24"], ["name":"docker0", "inet":"172.17.0.1/16"], ["name":"lo", "inet":"127.0.0.1/8"]]
        } else if path.hasSuffix("/status/current") {
            value = ["status":"running", "cpu":"0.25", "cpus":"4", "mem": host == "malformed.fixture" ? ["bad":1] as Any : "1024", "maxmem":"4096", "swap":"256", "netin":"100", "netout":"200", "uptime":"123"]
        } else if path.hasSuffix("/config") {
            if host == "lag.fixture" { return }
            value = ["cores":"4", "swap":"512", "net0":"name=eth0,bridge=vmbr0,ip=192.0.2.50/24", "ostype":"debian"]
        } else if path.hasSuffix("/lxc/105") { value = [["subdir":"interfaces"],["subdir":"config"]] }
        else { status = 403 }
        let data = try! JSONSerialization.data(withJSONObject: ["data":value])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func verifySprint8() async throws {
    let output = "tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=12,fd=8))\ntcp LISTEN 0 128 127.0.0.1:3306 0.0.0.0:*\ntcp LISTEN 0 128 [::]:5432 [::]:*\nudp UNCONN 0 0 0.0.0.0:53 0.0.0.0:*"
    let parsed = try SocketListParser.parse(output)
    precondition(parsed.count == 4 && parsed.first?.process == "sshd (pid 12)")
    precondition(!parsed.first(where: { $0.port == 3306 })!.risky && parsed.first(where: { $0.port == 5432 })!.risky)
    precondition(parsed.contains { $0.transport == "UDP" && $0.port == 53 })
    do { _ = try SocketListParser.parse("bad protocol payload"); fatalError("Invalid output accepted") } catch PortInspectionError.invalidOutput {}
    for invalid in ["localhost", "0.0.0.0", "127.1.2.3", "::1", "0:0:0:0:0:0:0:1", "0:0:0:0:0:ffff:7f00:1", "::ffff:127.0.0.1", "fe80::1", "ff02::1", "239.1.2.3"] { precondition(!PortCatalog.usableAddress(invalid)) }
    for valid in ["192.0.2.50", "10.0.0.5", "2001:db8::50"] { precondition(PortCatalog.usableAddress(valid)) }
    var guest = Guest(id: 105, name: "fixture", node: "node", kind: .lxc, running: true, cpu: 0, memoryGB: 0, maxMemoryGB: 1, diskGB: 0, role: "test")
    func api(_ host: String = "ports.fixture") throws -> ProxmoxAPIService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PortsProtocol.self]
        return try .init(profile: .init(name: "Fixture", endpoint: URL(string: "https://"+host)!, tokenID: "fixture@pve!test"), secret: "fixture", configuration: config)
    }
    let service = try api()
    defer { service.invalidate() }
    let status = try await service.guestStatus(guest)
    precondition(status.cpu == 0.25 && status.cpus == 4 && status.mem == 1024)
    let config = try await service.guestConfiguration(guest)
    precondition(config.cpuCount == 4 && config.swapMB == 512 && config.configuredAddresses == ["192.0.2.50"])
    let addresses = try await service.guestAddresses(guest, primaryFirst: true)
    precondition(addresses == ["192.0.2.50"], "Docker networks must not be scanned as guest primary addresses")
    do { _ = try await service.listeningPorts(guest); fatalError("Invented LXC exec endpoint") } catch PortInspectionError.unsupported {}
    guest.kind = .qemu
    let sockets = try await service.listeningPorts(guest)
    precondition(sockets.count == 2 && sockets.contains { $0.port == 3306 && $0.risky && $0.process == "mysqld (pid 123)" })
    let emptyAPI = try api("empty.fixture")
    let empty = try await emptyAPI.listeningPorts(guest); precondition(empty.isEmpty); emptyAPI.invalidate()
    guest.running = false
    do { _ = try await PortInspectionService(api: service).inspect(guest); fatalError("Stopped machine inspected") } catch is CancellationError {}
    let malformed = try api("malformed.fixture")
    defer { malformed.invalidate() }
    do { _ = try await malformed.guestStatus(guest); fatalError("Bad metric silently decoded") } catch ProxmoxError.decoding(let field) { precondition(field.contains("mem")) }
    let lag = try api("lag.fixture")
    let partial = try await lag.snapshot(detailDeadline: Date().addingTimeInterval(0.4))
    precondition(partial.node.guests.first?.cpuCount == 4 && partial.node.guests.first?.swapGB == 256 / 1e9, "Slow config discarded valid resource telemetry")
    precondition(partial.node.guests.first?.telemetryError != nil)
    lag.invalidate()
    let noTargets = try await TCPPortScanner.scan(addresses: ["127.0.0.1", "::1"])
    precondition(noTargets.coverage == .unavailable && noTargets.attempted == 0)
    let start = Date()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<16 {
            group.addTask {
                let probe = Task { await TCPPortScanner.probe(address: "192.0.2.1", port: 5432, timeout: 10) }
                try? await Task.sleep(for: .milliseconds(20)); probe.cancel(); _ = await probe.value
            }
        }
    }
    precondition(Date().timeIntervalSince(start) < 2, "TCP cancellation failed")
    // A real local listener verifies connect-only probes without remote traffic.
    let listener = try NWListener(using: .tcp, on: .any)
    let queue = DispatchQueue(label: "dev.proxpulse.port-test")
    listener.newConnectionHandler = { connection in
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1) { connection.cancel() }
    }
    listener.start(queue: queue)
    defer { listener.cancel() }
    for _ in 0..<40 { if let value = listener.port, value.rawValue > 0 { break }; try await Task.sleep(for: .milliseconds(25)) }
    guard let port = listener.port else { fatalError("Listener unavailable") }
    try await Task.sleep(for: .milliseconds(100))
    let open = await TCPPortScanner.probe(address: "127.0.0.1", port: port.rawValue, timeout: 2)
    precondition(open == .open)
    listener.cancel(); try await Task.sleep(for: .milliseconds(100))
    let refused = await TCPPortScanner.probe(address: "127.0.0.1", port: port.rawValue)
    precondition(refused == .refused)
    for key in ["Обновить", "Часть телеметрии недоступна", "Конфигурация машины ещё не получена.", "Неопределённых проверок: 13 из 16. Возможна фильтрация firewall.", "Порты: проверка…", "Сетевые порты и сервисы", "Порты: нет доступа с Mac", "Некорректный формат API-поля: data.mem."] { precondition(L10n.text(key, language: "en") != key) }
    var snapshot = WidgetSnapshot(node: MockDataProvider.node, isDemo: true)
    snapshot.profileID = UUID()
    let running = snapshot.guests!.first(where: \.running)!, key = MonitoringRules.guestKey(running)
    let warning = PortAudit(source: .tcpScan, coverage: .partial, ports: [.init(port:22,address:"192.0.2.50"),.init(port:3306,address:"192.0.2.50")])
    snapshot.applyPortAudits([key:warning])
    precondition(snapshot.detectedPorts?[key] == [22,3306] && snapshot.securityLevel?[key] == .warning)
    let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(roundTrip.portSecurity(for: running)?.level == .warning)
    var stopped = running; stopped.running = false
    precondition(snapshot.portSecurity(for: stopped) == nil)
    var stale = snapshot; stale.portAuditedAt?[key] = Date().addingTimeInterval(-121)
    precondition(stale.portSecurity(for: running) == nil)
    var disconnected = snapshot; disconnected.state = .connecting
    precondition(disconnected.portSecurity(for: running) == nil)
    disconnected.applyPortAudits([key:warning]); precondition(disconnected.detectedPorts?.isEmpty == true)
    var freshProfile = WidgetSnapshot(node: MockDataProvider.node, isDemo: false); freshProfile.profileID = UUID()
    precondition(freshProfile.portSecurity(for: running) == nil)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String:Any]
    for key in ["detectedPorts","securityLevel","portAuditedAt","portCoverage"] { legacy.removeValue(forKey:key) }
    let legacySnapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject:legacy))
    precondition(legacySnapshot.portSecurity(for: running) == nil)
    print("PASS: widget per-machine security payload, old-cache decoding, profile isolation, stopped/offline/stale suppression")
    print("PASS: socket parsing TCP/UDP/PID, loopback risk exclusion, numeric-string metrics, explicit malformed-field error, primary-IP Docker exclusion, API QEMU exec JSON+status, no invented LXC exec, stopped-machine guard, real TCP open/refused, 16 cancelled probes, RU/EN security strings")
}
