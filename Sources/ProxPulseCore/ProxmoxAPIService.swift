import Foundation
import Security

public enum ProxmoxError: Error, LocalizedError {
    case invalidEndpoint, missingToken, http(Int), keychain(OSStatus), invalidResponse, noNodes, twoFactorRequired, taskFailed(String), taskTimeout
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Требуется HTTPS URL сервера без query и fragment."
        case .missingToken: "Учётные данные отсутствуют в Keychain."
        case .http(401): "Авторизация отклонена (HTTP 401). Проверьте логин, realm и пароль или API Token."
        case .http(403): "Недостаточно прав API (HTTP 403). Проверьте разрешения пользователя и API Token."
        case .http(let code): "Proxmox API: HTTP \(code)."
        case .keychain(let status): "Ошибка Keychain: \(status)."
        case .invalidResponse: "Некорректный ответ Proxmox."
        case .taskFailed(let status): "Задача Proxmox завершилась с ошибкой: \(status)"
        case .taskTimeout: "Задача ещё выполняется или её результат недоступен. Проверьте Task History Proxmox."
        case .noNodes: "API не вернул доступных нод. Проверьте права пользователя (Sys.Audit / VM.Audit / Datastore.Audit)."
        case .twoFactorRequired: "Требуется двухфакторная авторизация. Используйте API Token для этого аккаунта."
        }
    }
}
public enum KeychainManager {
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.proxpulse.api-token", kSecAttrAccount as String: id.uuidString]
    }
    public static func save(_ token: String, for id: UUID) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id); item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ProxmoxError.keychain(added) }
        } else if status != errSecSuccess { throw ProxmoxError.keychain(status) }
    }
    public static func token(for id: UUID) throws -> String {
        var item = query(id); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound { throw ProxmoxError.missingToken }; throw ProxmoxError.keychain(status)
        }
        return token
    }
    public static func delete(for id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProxmoxError.keychain(status) }
    }
}
private final class ServerTrustDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let host: String
    let allowInsecure: Bool
    init(host: String, allowInsecure: Bool) { self.host = host; self.allowInsecure = allowInsecure }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInsecure, challenge.protectionSpace.host == host,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
    // Never forward API credentials to a redirect destination.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct ClusterResource: Decodable, Sendable {
    public var id: String
    public var type: String
    public var node: String?
    public var name: String?
    public var status: String?
    public var vmid: Int?
    public var cpu: Double?
    public var mem: Double?
    public var maxmem: Double?
    public var disk: Double?
    public var maxdisk: Double?
}
public struct NodeStatus: Decodable, Sendable {
    public struct Memory: Decodable, Sendable { public var used: Double; public var total: Double }
    public struct CPUInfo: Decodable, Sendable { public var model: String?; public var cpus: Int? }
    public var cpu: Double
    public var memory: Memory
    public var uptime: Double
    public var cpuinfo: CPUInfo?
}
public struct StorageStatus: Decodable, Sendable {
    public var storage: String
    public var total: Double?
    public var used: Double?
    public var active: Int?
    public var enabled: Int?
    public var type: String?
}
public struct ServiceStatus: Decodable, Sendable {
    public var service: String
    public var state: String?
}
public struct LogLine: Decodable, Sendable { public var t: String? }
public struct ConnectionCheck: Sendable {
    public var nodes: [String]
    public var milliseconds: Int
}
public struct LiveSnapshot: Sendable {
    public var node: NodeSnapshot
    public var nodes: [String]
}
public actor ProxmoxAPIService {
    private let profile: ServerProfile
    private let session: URLSession
    private let suppliedSecret: String?
    private var networkSampler = GuestNetworkSampler()
    private var ticket: String?
    private var csrf: String?
    private var ticketDate: Date?
    public init(profile: ServerProfile, secret: String? = nil, configuration: URLSessionConfiguration = .ephemeral) throws {
        guard let c = URLComponents(url: profile.endpoint, resolvingAgainstBaseURL: false), c.scheme == "https", let host = c.host, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else { throw ProxmoxError.invalidEndpoint }
        self.profile = profile; suppliedSecret = secret
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: ServerTrustDelegate(host: host, allowInsecure: profile.allowInsecureSSL), delegateQueue: nil)
    }
    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct TicketResponse: Decodable {
        var ticket: String?
        var CSRFPreventionToken: String?
        var NeedTFA: Int?
    }
    private func secret() throws -> String { try suppliedSecret ?? KeychainManager.token(for: profile.id) }
    private func url(_ path: [String], query: [URLQueryItem] = []) -> URL {
        var url = profile.endpoint.appendingPathComponent("api2").appendingPathComponent("json")
        for part in path { url.appendPathComponent(part) }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        return c.url!
    }
    private func decode<T: Decodable & Sendable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProxmoxError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ProxmoxError.http(http.statusCode) }
        return try JSONDecoder().decode(Envelope<T>.self, from: data).data
    }
    private func authenticate() async throws {
        guard profile.authMode == .password else { return }
        if ticket != nil, let ticketDate, Date().timeIntervalSince(ticketDate) < 6000 { return }
        var request = URLRequest(url: url(["access", "ticket"]))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = ["username": profile.tokenID, "password": try secret()].sorted { $0.key < $1.key }.map {
            $0.key + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let result = try await decode(request, as: TicketResponse.self)
        guard let value = result.ticket, !value.hasPrefix("PVE:tfa!"), result.NeedTFA != 1 else { throw ProxmoxError.twoFactorRequired }
        guard let prevention = result.CSRFPreventionToken else { throw ProxmoxError.invalidResponse }
        ticket = value; csrf = prevention; ticketDate = Date()
    }
    private func request<T: Decodable & Sendable>(_ path: [String], method: String = "GET", query: [URLQueryItem] = [], as: T.Type, retry: Bool = true) async throws -> T {
        try await authenticate()
        var request = URLRequest(url: url(path, query: query)); request.httpMethod = method
        if profile.authMode == .apiToken {
            request.setValue("PVEAPIToken=\(profile.tokenID)=\(try secret())", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("PVEAuthCookie=\(ticket ?? "")", forHTTPHeaderField: "Cookie")
            if method != "GET" { request.setValue(csrf, forHTTPHeaderField: "CSRFPreventionToken") }
        }
        do { return try await decode(request, as: T.self) }
        catch ProxmoxError.http(401) where profile.authMode == .password && retry {
            ticket = nil; ticketDate = nil
            return try await self.request(path, method: method, query: query, as: T.self, retry: false)
        }
    }
    public func resources() async throws -> [ClusterResource] { try await request(["cluster", "resources"], as: [ClusterResource].self) }
    private struct NodeInfo: Decodable, Sendable { var node: String; var status: String? }
    public func nodes() async throws -> [String] {
        let nodes = try await request(["nodes"], as: [NodeInfo].self)
        return nodes.sorted { a, b in a.status == b.status ? a.node < b.node : a.status == "online" }.map(\.node)
    }
    public func testConnection() async throws -> ConnectionCheck {
        let start = Date()
        let available = try await nodes()
        guard let first = available.first else { throw ProxmoxError.noNodes }
        _ = try await request(["nodes", first, "status"], as: NodeStatus.self)
        _ = try await resources()
        _ = try await request(["nodes", first, "storage"], as: [StorageStatus].self)
        return ConnectionCheck(nodes: available, milliseconds: Int(Date().timeIntervalSince(start) * 1000))
    }
    public func snapshot(node preferred: String? = nil) async throws -> LiveSnapshot {
        let available = try await nodes()
        guard let name = preferred.flatMap({ available.contains($0) ? $0 : nil }) ?? available.first else { throw ProxmoxError.noNodes }
        let status = try await request(["nodes", name, "status"], as: NodeStatus.self)
        let resources = try await resources()
        let storage = try await request(["nodes", name, "storage"], as: [StorageStatus].self)
        var node = LiveDataAdapter.snapshot(name: name, status: status, resources: resources, storage: storage)
        let guests = node.guests
        // Bounded fan-out keeps large clusters from saturating pveproxy. A denied guest must not blank the dashboard.
        for start in stride(from: 0, to: guests.count, by: 4) {
            let batch = Array(guests[start..<min(start + 4, guests.count)])
            let results = await withTaskGroup(of: (Guest, GuestStatus?, String?, Date).self) { group in
                for guest in batch {
                    group.addTask {
                        do { return (guest, try await self.guestStatus(guest), nil, Date()) }
                        catch { return (guest, nil, error.localizedDescription, Date()) }
                    }
                }
                var result: [(Guest, GuestStatus?, String?, Date)] = []
                for await item in group { result.append(item) }
                return result
            }
            try Task.checkCancellation()
            for (guest, status, error, date) in results {
                guard let index = node.guests.firstIndex(where: { MonitoringRules.guestKey($0) == MonitoringRules.guestKey(guest) }) else { continue }
                if let status { node.guests[index] = networkSampler.apply(status, to: guest, date: date) }
                else { networkSampler.invalidate(guest); node.guests[index].telemetryError = error }
            }
        }
        networkSampler.retain(node.guests)
        return LiveSnapshot(node: node, nodes: available)
    }
    public func guestStatus(_ guest: Guest) async throws -> GuestStatus {
        try await request(["nodes", guest.node, guest.kind.rawValue, String(guest.id), "status", "current"], as: GuestStatus.self)
    }
    private struct GuestInterface: Decodable, Sendable {
        struct Address: Decodable, Sendable {
            var address: String
            enum CodingKeys: String, CodingKey { case address = "ip-address" }
        }
        var name: String?
        var inet: String?
        var inet6: String?
        var addresses: [Address]?
        enum CodingKeys: String, CodingKey { case name, inet, inet6; case addresses = "ip-addresses" }
    }
    private struct AgentInterfaces: Decodable, Sendable { var result: [GuestInterface] }
    public func guestAddresses(_ guest: Guest) async throws -> [String] {
        guard guest.running else { return [] }
        let base = ["nodes", guest.node, guest.kind.rawValue, String(guest.id)]
        let interfaces: [GuestInterface]
        if guest.kind == .lxc { interfaces = try await request(base + ["interfaces"], as: [GuestInterface].self) }
        else { interfaces = try await request(base + ["agent", "network-get-interfaces"], as: AgentInterfaces.self).result }
        return Array(Set(interfaces.filter { $0.name != "lo" }.flatMap { item in
            [item.inet, item.inet6].compactMap { $0 } + (item.addresses ?? []).map(\.address)
        }.map { $0.components(separatedBy: "/")[0] }.filter { !$0.hasPrefix("127.") && $0 != "::1" && !$0.hasPrefix("fe80:") && !$0.isEmpty })).sorted()
    }
    public func diagnostics(node: String, storage: DiskItem, guests: [Guest]) async -> IncidentReport {
        var report = IncidentReport.live(storage: storage, guests: guests)
        do {
            let lines = try await request(["nodes", node, "syslog"], query: [.init(name: "limit", value: "500")], as: [LogLine].self)
            report.addKernelLog(lines.compactMap(\.t).joined(separator: "\n"))
        } catch { report.unavailable("oom", reason: error.localizedDescription) }
        do {
            let services = try await request(["nodes", node, "services"], as: [ServiceStatus].self)
            report.addServices(services)
        } catch { report.unavailable("services", reason: error.localizedDescription) }
        return report
    }
    private struct NetworkInterface: Decodable, Sendable { var address: String?; var gateway: String?; var active: Int?; var iface: String? }
    public func sshHost(node: String) async throws -> String? {
        let interfaces = try await request(["nodes", node, "network"], as: [NetworkInterface].self)
        let usable = interfaces.filter { $0.iface != "lo" && $0.active != 0 && !($0.address ?? "").isEmpty }
        let selected = usable.first { !($0.gateway ?? "").isEmpty } ?? usable.first
        return selected?.address?.components(separatedBy: "/").first
    }
    public enum GuestAction: String, CaseIterable, Sendable { case start, reboot, shutdown, stop }
    public struct TaskStatus: Decodable, Sendable { public var status: String; public var exitstatus: String? }
    public func taskStatus(node: String, upid: String) async throws -> TaskStatus {
        try await request(["nodes", node, "tasks", upid, "status"], as: TaskStatus.self)
    }
    public func waitForTask(node: String, upid: String, timeout: TimeInterval = 120) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let status = try await taskStatus(node: node, upid: upid)
            if status.status == "stopped" {
                guard status.exitstatus == "OK" else { throw ProxmoxError.taskFailed(status.exitstatus ?? "unknown") }
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw ProxmoxError.taskTimeout
    }
    public func control(_ guest: Guest, action: GuestAction) async throws -> String {
        try await request(["nodes", guest.node, guest.kind.rawValue, String(guest.id), "status", action.rawValue], method: "POST", as: String.self)
    }
}
