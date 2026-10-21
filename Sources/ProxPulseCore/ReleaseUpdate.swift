import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let parts: [UInt64]
    public init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && ($0.count == 1 || $0.first != "0") }) else { return nil }
        let numbers = pieces.compactMap { UInt64($0) }; guard numbers.count == 3 else { return nil }
        parts = numbers
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
public struct AppRelease: Sendable, Identifiable {
    public let tag: String
    public let version: ReleaseVersion
    public let notes: String
    public let download: URL
    public let checksum: URL
    public var id: String { tag }
}
public enum ReleaseUpdateError: Error { case invalidRelease, invalidChecksum, http(Int) }
public enum ReleaseUpdate {
    public static let repository = "makskondrasov9-dev/ProxPulse"
    public static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static func parse(_ data: Data) throws -> AppRelease {
        struct Response: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let body: String?; let draft: Bool; let prerelease: Bool; let assets: [Asset]
        }
        let value = try JSONDecoder().decode(Response.self, from: data)
        guard !value.draft, !value.prerelease, let version = ReleaseVersion(value.tag_name),
              let dmg = value.assets.first(where: { $0.name == "ProxPulse-\(value.tag_name).dmg" }),
              let sha = value.assets.first(where: { $0.name == dmg.name + ".sha256" }) else { throw ReleaseUpdateError.invalidRelease }
        for asset in [dmg, sha] {
            let url = asset.browser_download_url
            guard url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path == "/\(repository)/releases/download/\(value.tag_name)/\(asset.name)" else { throw ReleaseUpdateError.invalidRelease }
        }
        return .init(tag: value.tag_name, version: version, notes: String((value.body ?? "").prefix(50000)), download: dmg.browser_download_url, checksum: sha.browser_download_url)
    }
    public static func expectedHash(_ data: Data, filename: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw ReleaseUpdateError.invalidChecksum }
        let rows = text.split(whereSeparator: \.isNewline)
        guard rows.count == 1 else { throw ReleaseUpdateError.invalidChecksum }
        let parts = rows[0].split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy({ $0.isASCII && $0.isHexDigit }), String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*")) == filename else { throw ReleaseUpdateError.invalidChecksum }
        return parts[0].lowercased()
    }
}
