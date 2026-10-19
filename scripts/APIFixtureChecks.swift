import Foundation
import ProxPulseCore

private final class FixtureState: @unchecked Sendable {
    let lock = NSLock()
    var mode: AuthenticationMode = .apiToken
    var loginCount = 0
    var unauthorizedOnce = false
    var requests = 0
    var taskChecks = 0
    var denyGuest = false
    var taskExit = "OK"
    func reset(_ mode: AuthenticationMode) { lock.withLock { self.mode = mode; loginCount = 0; unauthorizedOnce = false; requests = 0; taskChecks = 0; taskExit = "OK"; denyGuest = false } }
    func response(_ request: URLRequest) -> (Int, String) {
        lock.withLock {
            requests += 1
            let path = request.url!.path
            if path.hasSuffix("/access/ticket") {
                precondition(mode == .password && request.httpMethod == "POST")
                var data = request.httpBody ?? Data()
                if data.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        data.append(contentsOf: buffer.prefix(count))
                    }
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                precondition(body.contains("password=p%26a%2B%3Dss") && body.contains("username=root%40pam"))
                loginCount += 1
                return (200, #"{"data":{"ticket":"PVE:fixture","CSRFPreventionToken":"fixture-csrf"}}"#)
            }
            if mode == .apiToken { precondition(request.value(forHTTPHeaderField: "Authorization") == "PVEAPIToken=monitor@pve!test=fixture-secret") }
            else {
                precondition(request.value(forHTTPHeaderField: "Cookie") == "PVEAuthCookie=PVE:fixture")
                if path.hasSuffix("/cluster/resources") && !unauthorizedOnce { unauthorizedOnce = true; return (401, "{}") }
                if request.httpMethod == "POST" { precondition(request.value(forHTTPHeaderField: "CSRFPreventionToken") == "fixture-csrf") }
            }
            if path.hasSuffix("/qemu/200/status/current") {
                if denyGuest { return (403, "{}") }
                return (200, #"{"data":{"status":"running","cpus":4,"cpu":0.21,"mem":2000000000,"maxmem":8000000000,"disk":0,"maxdisk":40000000000,"netin":120000,"netout":40000,"uptime":900}}"#)
            }
            if path.hasSuffix("/lxc/201/status/current") {
                return (200, #"{"data":{"status":"stopped","cpus":2,"mem":0,"maxmem":4000000000,"swap":0,"maxswap":512000000,"disk":2700000000,"maxdisk":40000000000,"uptime":0}}"#)
            }
            if path.hasSuffix("/agent/network-get-interfaces") {
                return (200, #"{"data":{"result":[{"name":"lo","ip-addresses":[{"ip-address":"127.0.0.1"}]},{"name":"eth0","ip-addresses":[{"ip-address":"192.168.1.20"},{"ip-address":"192.168.1.20/24"},{"ip-address":"fe80::1234"}]}]}}"#)
            }
            if path.contains("/tasks/") && path.hasSuffix("/status") {
                taskChecks += 1
                return taskChecks == 1 ? (200, #"{"data":{"status":"running"}}"#) : (200, "{\"data\":{\"status\":\"stopped\",\"exitstatus\":\"" + taskExit + "\"}}")
            }
            if request.httpMethod == "POST", ["start", "reboot", "shutdown", "stop"].contains(path.components(separatedBy: "/").last ?? "") { return (200, #"{"data":"UPID:fixture:test"}"#) }
            switch path {
            case "/api2/json/nodes": return (200, #"{"data":[{"node":"pve-live","status":"online"}]}"#)
            case "/api2/json/nodes/pve-live/status": return (200, #"{"data":{"cpu":0.42,"memory":{"used":32000000000,"total":64000000000},"uptime":90061,"cpuinfo":{"model":"Fixture CPU","cpus":24}}}"#)
            case "/api2/json/cluster/resources": return (200, #"{"data":[{"id":"qemu/200","type":"qemu","vmid":200,"node":"pve-live","name":"live-vm","status":"running","cpu":0.21,"mem":2000000000,"maxmem":8000000000},{"id":"lxc/201","type":"lxc","vmid":201,"node":"pve-live","name":"stopped-ct","status":"stopped"},{"id":"node/pve-live","type":"node","node":"pve-live"}]}"#)
            case "/api2/json/nodes/pve-live/storage": return (200, #"{"data":[{"storage":"fast","active":1,"enabled":1,"total":1000000000000,"used":960000000000},{"storage":"off","active":0,"total":1000000000000,"used":100000000000}]}"#)
            case "/api2/json/nodes/pve-live/syslog": return (200, #"{"data":[{"t":"kernel: Out of memory: Killed process 42 (worker)"}]}"#)
            case "/api2/json/nodes/pve-live/network": return (200, #"{"data":[{"iface":"lo","active":1,"address":"127.0.0.1"},{"iface":"vmbr0","active":1,"address":"192.168.1.228/24","gateway":"192.168.1.1"}]}"#)
            case "/api2/json/nodes/pve-live/services": return (200, #"{"data":[{"service":"pvedaemon","state":"running"},{"service":"pveproxy","state":"failed"},{"service":"optional","state":"stopped"}]}"#)
            case "/api2/json/nodes/pve-live/qemu/200/status/start": return (200, #"{"data":"UPID:fixture:test"}"#)
            default: return (404, "{}")
            }
        }
    }
}
private final class APIFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = FixtureState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, json) = Self.state.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
func verifyAPIFixtures() async throws {
    precondition(ProfileValidation.username("root", mode: .password) == "root@pam")
    precondition(ProfileValidation.username(" root@pve ", mode: .password) == "root@pve")
    precondition(ProfileValidation.username("root", mode: .apiToken) == nil)
    precondition(ProfileValidation.username("@pam", mode: .password) == nil)
    precondition(ProfileValidation.username("", mode: .password) == nil)
    precondition(ProfileValidation.username("root@pam@pve", mode: .password) == nil)
    let endpoint = try ProfileValidation.endpoint("192.168.1.228")
    precondition(endpoint.absoluteString == "https://192.168.1.228:8006")
    precondition(ProfileValidation.isLocal("172.16.1.2") && !ProfileValidation.isLocal("172.32.1.2"))
    for mode in AuthenticationMode.allCases {
        APIFixtureProtocol.state.reset(mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIFixtureProtocol.self]
        let profile = ServerProfile(name: "Fixture", endpoint: URL(string: "https://fixture.invalid:8006")!, tokenID: mode == .apiToken ? "monitor@pve!test" : "root@pam", authentication: mode)
        let api = try ProxmoxAPIService(profile: profile, secret: mode == .apiToken ? "fixture-secret" : "p&a+=ss", configuration: configuration)
        let check = try await api.testConnection()
        precondition(check.nodes == ["pve-live"])
        let snapshot = try await api.snapshot()
        precondition(snapshot.node.cpu == 0.42 && snapshot.node.memoryGB == 32 && snapshot.node.cpuCount == 24)
        precondition(snapshot.node.guests.count == 2 && snapshot.node.guests[0].node == "pve-live")
        precondition(snapshot.node.storage.children.count == 1 && snapshot.node.storage.usedGB == 960)
        precondition(snapshot.node.guests[0].cpuCount == 4 && snapshot.node.guests[0].maxDiskGB == 40)
        precondition(snapshot.node.guests[0].swapGB == nil && snapshot.node.guests[0].diskUsageAvailable == false)
        precondition(snapshot.node.guests[1].swapGB == 0 && snapshot.node.guests[1].maxSwapGB == 0.512)
        precondition(snapshot.node.guests[1].diskUsageAvailable == true && snapshot.node.guests[1].diskGB == 2.7)
        let addresses = try await api.guestAddresses(snapshot.node.guests[0])
        precondition(addresses == ["192.168.1.20"])
        APIFixtureProtocol.state.lock.withLock { APIFixtureProtocol.state.denyGuest = true }
        let partial = try await api.snapshot()
        precondition(partial.node.online && partial.node.guests[0].telemetryError != nil && partial.node.guests[1].telemetryError == nil)
        APIFixtureProtocol.state.lock.withLock { APIFixtureProtocol.state.denyGuest = false }
        let report = await api.diagnostics(node: snapshot.node.id, storage: snapshot.node.storage, guests: snapshot.node.guests)
        precondition(report.findings.count == 3 && report.stoppedGuests.count == 1)
        precondition(report.checks.first { $0.id == "network" }?.state == .unavailable)
        let upid = try await api.control(snapshot.node.guests[0], action: .start)
        precondition(upid == "UPID:fixture:test")
        if mode == .password { precondition(APIFixtureProtocol.state.lock.withLock { APIFixtureProtocol.state.loginCount } == 2) }
        let sshHost = try await api.sshHost(node: "pve-live")
        precondition(sshHost == "192.168.1.228")
        for action in ProxmoxAPIService.GuestAction.allCases {
            _ = try await api.control(snapshot.node.guests[0], action: action)
            _ = try await api.control(snapshot.node.guests[1], action: action)
        }
        try await api.waitForTask(node: "pve-live", upid: upid)
        APIFixtureProtocol.state.lock.withLock { APIFixtureProtocol.state.taskExit = "ERROR: fixture" }
        do { try await api.waitForTask(node: "pve-live", upid: upid); fatalError("Failed task accepted") }
        catch ProxmoxError.taskFailed { }
        let metadata = String(data: try JSONEncoder().encode(profile), encoding: .utf8)!
        precondition(!metadata.contains("fixture-secret") && !metadata.contains("p&a"))
    }
    print("PASS: API Token and password/CSRF, form encoding, 401 ticket renewal, live mapping, per-pool incidents, controls (URLProtocol fixture, no real server mutations)")
}
