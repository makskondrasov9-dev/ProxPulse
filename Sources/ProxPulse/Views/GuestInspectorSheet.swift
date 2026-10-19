import SwiftUI
import Charts
import ProxPulseCore

struct GuestInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseAccent) private var accent
    var model: DashboardModel
    var original: Guest
    private var guest: Guest { model.node.guests.first { MonitoringRules.guestKey($0) == MonitoringRules.guestKey(original) } ?? original }
    private var samples: [GuestSample] { model.samples(for: guest) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: guest.kind == .lxc ? "shippingbox" : "desktopcomputer").font(.title).foregroundStyle(accent.uiColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(guest.name).font(.title2.bold())
                    Text("\(guest.kind.rawValue.uppercased()) · ID \(guest.id) · \(guest.node)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); StatusDot(online: guest.running)
                LB("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        HStack(alignment: .top, spacing: 32) {
                            GuestResourcesView(guest: guest).frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 12) {
                                TL(TelemetryFormat.uptime(guest.uptimeSeconds), systemImage: "clock")
                                T("IP-адреса").font(.caption).foregroundStyle(.secondary)
                                if model.loadingAddresses { ProgressView().controlSize(.small) }
                                else if !model.guestAddresses.isEmpty { Text(model.guestAddresses.joined(separator: "\n")).textSelection(.enabled) }
                                else { T("IP недоступен").foregroundStyle(.secondary) }
                                if let error = model.addressError { T(error).font(.caption2).foregroundStyle(.orange).textSelection(.enabled) }
                                LB("Консоль / SSH") { model.shell(guest) }
                            }.font(.system(size: 12)).frame(width: 210, alignment: .leading)
                        }
                    }
                    if let error = guest.telemetryError { T(error).font(.caption).foregroundStyle(.orange) }
                    if guest.kind == .qemu { T("QEMU: SWAP и занятое место внутри ОС могут быть недоступны в status/current. Для IP нужен QEMU Guest Agent.").font(.caption).foregroundStyle(.secondary) }
                    HStack { T("История ресурсов").font(.headline); Spacer(); T(model.isDemo ? "DEMO · пример данных" : "До 120 замеров за текущую сессию").font(.caption).foregroundStyle(.secondary) }
                    if samples.count < 2 { T("Графики появятся после двух успешных замеров.").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                        graph("CPU", unit: "%", color: accent.uiColor) { $0.cpu * 100 }
                        graph("RAM", unit: "GB", color: PulseTheme.purple) { $0.memoryGB }
                        graph("SWAP", unit: "MB", color: PulseTheme.amber) { $0.swapGB.map { $0 * 1000 } }
                        graph("Диск", unit: "GB", color: PulseTheme.amber) { $0.diskGB }
                        graph("Входящий трафик", unit: "KB/s", color: PulseTheme.green) { $0.receiveBps.map { $0 / 1000 } }
                        graph("Исходящий трафик", unit: "KB/s", color: PulseTheme.cyan) { $0.transmitBps.map { $0 / 1000 } }
                    }
                }.padding(24)
            }
        }.frame(width: 760, height: 780).background(.ultraThinMaterial)
    }
    private func graph(_ title: String, unit: String, color: Color, value: @escaping (GuestSample) -> Double?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { T(title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(unit).font(.caption).foregroundStyle(.secondary) }
                Chart(samples) { sample in
                    if let number = value(sample) {
                        LineMark(x: .value("Time", sample.date), y: .value(unit, number)).foregroundStyle(color).interpolationMethod(.linear)
                    }
                }.chartYScale(domain: 0...(title == "CPU" ? 100 : max(0.001, samples.compactMap(value).max() ?? 1) * 1.15))
                    .chartXScale(range: .plotDimension(padding: 27))
                    .chartXAxis {
                        AxisMarks(values: samples.count > 1 ? [samples.first!.date, samples.last!.date] : []) { _ in
                            AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().locale(Locale(identifier: "en_GB")))
                        }
                    }
                    .frame(height: 105)
            }
        }
    }
}
