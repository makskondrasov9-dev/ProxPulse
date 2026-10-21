import Foundation

public enum TelemetryFormat {
    public static func number(_ value: Double, language: String) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: language == "en" ? "en_US" : "ru_RU")))
    }
    public static func rate(_ value: Double?, language: String = "en") -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 { return number(value / 1_000_000, language: language) + " MB/s" }
        if value >= 1000 { return number(value / 1000, language: language) + " KB/s" }
        return String(format: "%.0f B/s", value)
    }
    public static func swap(_ value: Double?, language: String = "en") -> String {
        guard let value else { return "—" }
        return value < 1 ? String(format: "%.0f MB", value * 1000) : number(value, language: language) + " GB"
    }
    public static func uptime(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let s = max(0, Int(seconds)); return "\(s / 86400)d \(s % 86400 / 3600)h \(s % 3600 / 60)m"
    }
}
