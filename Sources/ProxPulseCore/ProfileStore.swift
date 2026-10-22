import Foundation

/// Only non-secret connection metadata lives here. Passwords and token secrets live in Keychain.
public enum ProfileStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxPulse", isDirectory: true).appendingPathComponent("profiles.json")
    }
    public static func load() throws -> [ServerProfile] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ServerProfile].self, from: Data(contentsOf: url))
    }
    public static func save(_ profiles: [ServerProfile]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: url, options: .atomic)
    }
}
public enum ProfileValidation {
    public static func username(_ text: String, mode: AuthenticationMode) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "!" || $0 == "=" }) else { return nil }
        if mode == .password && !value.contains("@") { value += "@pam" }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return value
    }

    public static func endpoint(_ text: String) throws -> URL {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "https://" + raw }
        guard var c = URLComponents(string: raw), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              !c.path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }), c.port.map({ (1...65535).contains($0) }) ?? true else { throw ProxmoxError.invalidEndpoint }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        guard let url = c.url else { throw ProxmoxError.invalidEndpoint }
        return url
    }
    public static func isLocal(_ text: String) -> Bool {
        guard let url = try? endpoint(text), let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") || host.hasSuffix(".home.arpa") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            return octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1]))
        }
        return host.hasPrefix("fd") && host.contains(":") || host.hasPrefix("fc") && host.contains(":")
    }
}
