import SwiftUI
import ProxPulseCore

struct GuestResourcesView: View {
    @Environment(\.pulseLanguage) private var language
    @Environment(\.pulseAccent) private var accent
    var guest: Guest
    private var separator: String { language == "en" ? " of " : " из " }
    private func number(_ value: Double) -> String { TelemetryFormat.number(value, language: language) }
    var body: some View {
        VStack(spacing: 9) {
            row("CPU", icon: "cpu", value: "\(Int(guest.cpu * 100))% • \(guest.cpuCount.map(String.init) ?? "—") vCPU")
            row("RAM", icon: "memorychip", value: number(guest.memoryGB) + separator + number(guest.maxMemoryGB) + " GB (\(Int(guest.memoryGB / max(0.001, guest.maxMemoryGB) * 100))%)")
            GeometryReader { proxy in
                Capsule().fill(.primary.opacity(0.06)).overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: accent.ringColors(1), startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(1, guest.memoryGB / max(0.001, guest.maxMemoryGB)))
                }
            }.frame(height: 3).padding(.bottom, 2)
            row("SWAP", icon: "arrow.left.arrow.right", value: TelemetryFormat.swap(guest.swapGB, language: language) + separator + TelemetryFormat.swap(guest.maxSwapGB, language: language), warning: (guest.swapGB ?? 0) > 0)
            row("Диск", icon: "internaldrive", value: (guest.diskUsageAvailable == true ? number(guest.diskGB) : "—") + separator + (guest.maxDiskGB.map(number) ?? "—") + " GB")
            row("Сеть", icon: "network", value: "↓ \(TelemetryFormat.rate(guest.receiveBps, language: language))  ↑ \(TelemetryFormat.rate(guest.transmitBps, language: language))")
        }.monospacedDigit()
    }
    private func row(_ title: String, icon: String, value: String, warning: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).frame(width: 12).foregroundStyle(warning ? PulseTheme.amber : .secondary)
            T(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(warning ? PulseTheme.amber : .primary).lineLimit(1).minimumScaleFactor(0.8)
        }.font(.system(size: 10, weight: .medium))
        .padding(.vertical, warning ? 5 : 0).padding(.horizontal, warning ? 5 : 0)
        .background(warning ? PulseTheme.amber.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
