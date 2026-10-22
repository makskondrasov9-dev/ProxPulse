import Foundation
import ProxPulseCore

private final class RequestTracker: @unchecked Sendable {
    let lock = NSLock()
    var active = 0, maximum = 0, cancellations = 0
    func start() { lock.withLock { active += 1; maximum = max(maximum, active) } }
    func stop() { lock.withLock { active -= 1; cancellations += 1 } }
    func result() -> (Int,Int,Int) { lock.withLock { (active,maximum,cancellations) } }
}
private final class SlowProtocol: URLProtocol, @unchecked Sendable {
    static let tracker = RequestTracker()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.tracker.start() }
    override func stopLoading() { Self.tracker.stop() }
}
private final class ProxyProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(!Thread.isMainThread)
        precondition(request.url!.path == "/pve/api2/json/nodes")
        precondition(request.url!.port == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[{"node":"proxy-node","status":"online"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
func verifySprint7() async throws {
    for (input, output) in [
        ("https://pve.example.com", "https://pve.example.com"),
        ("pve.example.com/pve/", "https://pve.example.com/pve"),
        ("https://pve.example.com:8006/pve/", "https://pve.example.com:8006/pve"),
        ("https://[::1]:8006/pve/", "https://[::1]:8006/pve")
    ] { let url = try ProfileValidation.endpoint(input); precondition(url.absoluteString == output) }
    for invalid in ["http://pve.example.com", "https://u:p@pve.example.com/pve", "https://pve.example.com/pve?token=secret", "https://pve.example.com:0", "https://pve.example.com/a/../secret"] {
        do { _ = try ProfileValidation.endpoint(invalid); fatalError("Unsafe URL allowed") } catch ProxmoxError.invalidEndpoint {}
    }
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProxyProtocol.self]
    let api = try ProxmoxAPIService(profile: .init(name: "Proxy", endpoint: URL(string: "https://pve.example.com/pve/")!, tokenID: "root@pam!test"), secret: "fixture", configuration: config)
    let nodes = try await api.nodes(); precondition(nodes == ["proxy-node"])
    for code in [URLError.Code.cannotFindHost, .timedOut, .cannotConnectToHost, .serverCertificateUntrusted] {
        precondition(ConnectionFailure.map(URLError(code)).localizedDescription != URLError(code).localizedDescription)
    }
    var profile = MockDataProvider.profiles[0]; profile.localEndpoint = URL(string: "https://192.0.2.2:8006")!
    let restored = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile)); precondition(restored.localEndpoint == profile.localEndpoint)
    let slow = URLSessionConfiguration.ephemeral; slow.protocolClasses = [SlowProtocol.self]
    let slowAPI = try ProxmoxAPIService(profile: profile, secret: "fixture", configuration: slow)
    let started = Date()
    for _ in 0..<12 {
        do { _ = try await PollDeadline.run(seconds: 0.025) { try await slowAPI.nodes() }; fatalError("Deadline ignored") }
        catch let error as URLError { precondition(error.code == .timedOut) }
    }
    try await Task.sleep(for: .milliseconds(50))
    let (active, maximum, cancelled) = SlowProtocol.tracker.result()
    precondition(active == 0 && maximum == 1 && cancelled == 12 && Date().timeIntervalSince(started) < 2)
    print("PASS: proxy URL prefix/443/explicit-port/IPv6; actionable errors; LAN profile round-trip; 12 stalled polls cancelled, max in-flight=1, active=0")
}

private final class DetailMetrics: @unchecked Sendable {
    let lock = NSLock(); var active: Set<ObjectIdentifier> = []; var requested: Set<String> = []
    func start(_ object: AnyObject, path: String) { lock.withLock { _ = active.insert(ObjectIdentifier(object)); _ = requested.insert(path) } }
    func stop(_ object: AnyObject) { lock.withLock { _ = active.remove(ObjectIdentifier(object)) } }
}
private final class DetailProtocol: URLProtocol, @unchecked Sendable {
    static let metrics = DetailMetrics()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        if path.hasSuffix("/status/current") { Self.metrics.start(self,path:path); return }
        let payload: String
        if path.hasSuffix("/nodes") { payload = #"{"data":[{"node":"slow","status":"online"}]}"# }
        else if path.hasSuffix("/status") { payload = #"{"data":{"cpu":0.2,"memory":{"used":1000000000,"total":8000000000},"uptime":1000}}"# }
        else if path.hasSuffix("/resources") { payload = "{\"data\":[" + (100..<112).map { "{\"id\":\"lxc/\($0)\",\"type\":\"lxc\",\"node\":\"slow\",\"vmid\":\($0),\"name\":\"ct-\($0)\",\"status\":\"running\",\"cpu\":0.1,\"mem\":1000000000,\"maxmem\":2000000000}" }.joined(separator:",") + "]}" }
        else { payload = #"{"data":[]}"# }
        client?.urlProtocol(self,didReceive: HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(payload.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.metrics.stop(self) }
}
func verifyProgressiveTelemetry() async throws {
    let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[DetailProtocol.self]
    let api = try ProxmoxAPIService(profile:.init(name:"Slow guests",endpoint:URL(string:"https://fixture.invalid")!,tokenID:"fixture@pve!token"),secret:"fixture",configuration:configuration)
    for _ in 0..<2 {
        let result = try await api.snapshot(detailDeadline: Date().addingTimeInterval(0.5))
        precondition(result.node.guests.count == 12 && result.node.cpu == 0.2)
    }
    try await Task.sleep(for: .milliseconds(200))
    let metrics = DetailProtocol.metrics.lock.withLock { (DetailProtocol.metrics.active.count, DetailProtocol.metrics.requested.count) }
    precondition(metrics.0 == 0 && metrics.1 == 8, "active=\(metrics.0), requested=\(metrics.1)")
    print("PASS: hanging guest details preserve node + 12 machine cards; round-robin requests advance 8 distinct guests; no outstanding detail requests")
}
