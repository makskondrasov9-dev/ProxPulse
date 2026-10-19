import Foundation

public enum CheckState: String, Sendable { case checked, warning, unavailable }
public struct IncidentCheck: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var state: CheckState
    public var detail: String
}
public struct IncidentReport: Sendable {
    public var date = Date()
    public var isDemo = false
    public var checks: [IncidentCheck] = []
    public var findings: [DiagnosticFinding] = []
    public var stoppedGuests: [Guest] = []
    public init() {}
    public static func live(storage: DiskItem, guests: [Guest]) -> IncidentReport {
        var report = IncidentReport()
        report.stoppedGuests = guests.filter { !$0.running }
        let full = storage.children.filter { $0.fraction >= 0.95 }
        report.findings = full.map { pool in
            DiagnosticFinding(id: "disk-" + pool.id, title: "Хранилище \(pool.name) заполнено на \(Int(pool.fraction * 100))%", reason: "API storage: \(Int(pool.usedGB)) / \(Int(pool.capacityGB)) GB. Запись может завершаться ENOSPC.", solution: "Проверить хранилище", command: "pvesm status; df -h")
        }
        report.checks = [
            .init(id: "oom", title: "OOM-killer", state: .unavailable, detail: "Журнал ещё не получен."),
            .init(id: "disks", title: "Заполнение дисков", state: storage.children.isEmpty ? .unavailable : full.isEmpty ? .checked : .warning, detail: storage.children.isEmpty ? "API не вернул активных хранилищ." : "Проверено хранилищ: \(storage.children.count). Порог инцидента: 95%."),
            .init(id: "services", title: "Службы systemd", state: .unavailable, detail: "Список служб ещё не получен."),
            .init(id: "network", title: "Сетевой шлюз", state: .unavailable, detail: "Доступность API не доказывает доступность шлюза из ноды. Для проверки нужен ping из ноды; API status не предоставляет этот результат."),
            .init(id: "descriptors", title: "Файловые дескрипторы", state: .unavailable, detail: "Для /proc/sys/fs/file-nr требуется диагностика внутри ОС; доступные API не возвращают этот счётчик.")
        ]
        return report
    }
    public mutating func unavailable(_ id: String, reason: String) {
        guard let i = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[i].state = .unavailable; checks[i].detail = reason
    }
    public mutating func addKernelLog(_ text: String) {
        let evidence = DiagnosticEngine.analyze(.init(kernelLog: text)).filter { $0.id == "oom" }
        if var finding = evidence.first {
            let line = text.split(separator: "\n").first { $0.localizedCaseInsensitiveContains("out of memory") || $0.localizedCaseInsensitiveContains("oom-kill") || $0.localizedCaseInsensitiveContains("killed process") }
            finding.reason = "Журнал ноды: " + String((line ?? "").prefix(600))
            findings.append(finding)
        }
        if let i = checks.firstIndex(where: { $0.id == "oom" }) {
            checks[i].state = evidence.isEmpty ? .checked : .warning
            checks[i].detail = "Проверено до 500 строк syslog. \(evidence.isEmpty ? "В полученном фрагменте OOM не обнаружен; это не исключает более ранний инцидент." : "Найдена запись OOM; принадлежность конкретной VM/CT не установлена.")"
        }
    }
    public mutating func addServices(_ services: [ServiceStatus]) {
        let failed = services.filter { $0.state == "failed" || $0.state == "error" }
        for service in failed {
            findings.append(.init(id: "service-" + service.service, title: "Сбой службы \(service.service)", reason: "API services сообщает state=\(service.state ?? "unknown"). Exit code API не предоставлен.", solution: "Проверить журнал", command: "systemctl --failed; journalctl -b -p err --no-pager"))
        }
        if let i = checks.firstIndex(where: { $0.id == "services" }) {
            checks[i].state = services.isEmpty ? .unavailable : failed.isEmpty ? .checked : .warning
            checks[i].detail = "Получено служб: \(services.count), failed/error: \(failed.count). Неактивная служба сама по себе не считается аварией."
        }
    }
    public static var demo: IncidentReport {
        var report = live(storage: MockDataProvider.node.storage, guests: MockDataProvider.guests)
        report.isDemo = true
        report.findings = DiagnosticEngine.analyze(.init(diskFraction: 0.96, failedServices: ["pve-backup.service": 1]))
        report.checks = [
            .init(id: "oom", title: "OOM-killer", state: .checked, detail: "DEMO: записей OOM нет."),
            .init(id: "disks", title: "Заполнение дисков", state: .warning, detail: "DEMO: отдельный тестовый сценарий диска 96%."),
            .init(id: "services", title: "Службы systemd", state: .warning, detail: "DEMO: pve-backup.service, exit code 1."),
            .init(id: "network", title: "Сетевой шлюз", state: .checked, detail: "DEMO: шлюз доступен."),
            .init(id: "descriptors", title: "Файловые дескрипторы", state: .checked, detail: "DEMO: лимит не достигнут.")
        ]
        return report
    }
}
