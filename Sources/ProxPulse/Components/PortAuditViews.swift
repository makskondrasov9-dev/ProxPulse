import SwiftUI
import ProxPulseCore

struct PortAuditBadge: View {
    let guest: Guest
    let report: PortAudit?
    var loading = false
    var available = true
    @Environment(\.pulseLanguage) private var language
    private var title: String {
        guard let report else { return L10n.text("Порты: проверка…", language: language) }
        if report.coverage == .unreachable { return L10n.text("Порты: нет доступа с Mac", language: language) }
        if report.coverage == .unavailable { return L10n.text("Порты: данные недоступны", language: language) }
        if report.ports.isEmpty { return L10n.text(report.coverage == .complete ? "Нет слушающих портов" : "Известные TCP-порты не отвечают", language: language) }
        let unique = Array(Set(report.ports.map(\.port))).sorted()
        let risky = Set(report.ports.filter(\.risky).map(\.port))
        let selected = Array((unique.filter { risky.contains($0) } + unique.filter { !risky.contains($0) }).prefix(4)).sorted()
        let labels = selected.map { port in risky.contains(port) ? "\(port) (\(PortCatalog.services[port] ?? ""))" : String(port) }
        return L10n.text("Порты", language: language) + ": " + labels.joined(separator: ", ") + (unique.count > selected.count ? " +\(unique.count-selected.count)" : "")
    }
    var body: some View {
        if guest.running && available {
            HStack(spacing: 6) {
                if loading && report == nil { ProgressView().controlSize(.mini) }
                else { Image(systemName: report?.hasRisk == true ? "exclamationmark.triangle.fill" : "network") }
                Text(title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.font(.system(size: 10, weight: .medium))
                .foregroundStyle(report?.hasRisk == true ? Color.orange : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background((report?.hasRisk == true ? Color.orange : Color.primary).opacity(report?.hasRisk == true ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(report?.hasRisk == true ? .orange.opacity(0.2) : .clear))
                .help(PortAuditText.help(report, language: language))
                .accessibilityIdentifier("ports.\(guest.id)")
        }
    }
}

enum PortAuditText {
    static func help(_ report: PortAudit?, language: String) -> String {
        guard let report else { return L10n.text("Проверка API и доступности известных TCP-портов с этого Mac.", language: language) }
        var lines = [L10n.text(report.source == .tcpScan ? "TCP-проверка с Mac: частичный список. UDP и процессы не определяются." : report.source == .demo ? "Демонстрационные данные." : "Слушающие TCP/UDP-сокеты внутри машины через API.", language: language)]
        if report.hasRisk { lines.append(L10n.text("Доступный порт БД или небезопасного сервиса. Проверьте firewall, аутентификацию и привязку интерфейса. Это не доказательство доступа из Интернета.", language: language)) }
        if report.coverage == .unreachable { lines.append(L10n.text("Нет ответа с этого Mac: возможны VPN, маршрутизация или firewall. Отсутствие открытых портов не подтверждено.", language: language)) }
        if report.inconclusive > 0 { lines.append(L10n.text("Неопределённых проверок: \(report.inconclusive) из \(report.attempted). Возможна фильтрация firewall.", language: language)) }
        if report.source == .tcpScan { lines.append(L10n.text("Проверяемые порты", language: language) + ": " + PortCatalog.known.map(String.init).joined(separator: ", ")) }
        if let reason = report.reason { lines.append(L10n.text(reason, language: language)) }
        return lines.joined(separator: "\n\n")
    }
}
struct PortAuditPanel: View {
    let guest: Guest
    let model: DashboardModel
    @Environment(\.pulseLanguage) private var language
    private var report: PortAudit? { model.portAudit(for: guest) }
    private var loading: Bool { model.inspectingPorts.contains(MonitoringRules.guestKey(guest)) }
    var body: some View {
        if guest.running && model.node.online && (model.isDemo || model.connectionError == nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TL("Сетевые порты и сервисы", systemImage: "network.badge.shield.half.filled").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    else if !model.isDemo {
                        LB("Обновить") { model.portAudits.removeValue(forKey: MonitoringRules.guestKey(guest)); model.schedulePortInspection() }.controlSize(.small)
                    }
                }
                PortAuditBadge(guest: guest, report: report, loading: loading)
                if let report {
                    Text(PortAuditText.help(report, language: language)).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                    if !report.addresses.isEmpty { Text(report.addresses.joined(separator: " · ")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !report.ports.isEmpty {
                        HStack {
                            T("Порт / протокол").frame(width: 110, alignment: .leading)
                            T("Адрес привязки").frame(width: 190, alignment: .leading)
                            T("Сервис / процесс")
                        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(report.ports) { port in
                            HStack(alignment: .top) {
                                Text(String(port.port) + " / " + port.transport).frame(width: 110, alignment: .leading).foregroundStyle(port.risky ? .orange : .primary)
                                Text(port.address).frame(width: 190, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    if let service = port.service { Text(service + (port.process == nil ? " · " + L10n.text("по номеру порта", language: language) : "")) }
                                    Text(port.process ?? L10n.text("Процесс недоступен", language: language)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Divider().opacity(0.35)
                        }
                    }
                    Text(report.date, format: .dateTime.hour().minute().second()).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.09)))
        }
    }
}
