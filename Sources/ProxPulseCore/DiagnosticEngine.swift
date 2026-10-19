import Foundation
public struct DiagnosticEvidence: Sendable {
    public var kernelLog: String
    public var diskFraction: Double
    public var descriptorFraction: Double
    public var failedServices: [String: Int]
    public var gatewayReachable: Bool?
    public init(kernelLog: String = "", diskFraction: Double = 0, descriptorFraction: Double = 0, failedServices: [String: Int] = [:], gatewayReachable: Bool? = nil) {
        self.kernelLog = kernelLog; self.diskFraction = diskFraction; self.descriptorFraction = descriptorFraction; self.failedServices = failedServices; self.gatewayReachable = gatewayReachable
    }
}
public struct DiagnosticFinding: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var reason: String
    public var solution: String
    public var command: String
}
public enum DiagnosticEngine {
    public static func analyze(_ evidence: DiagnosticEvidence) -> [DiagnosticFinding] {
        var result: [DiagnosticFinding] = []
        if evidence.kernelLog.localizedCaseInsensitiveContains("out of memory") || evidence.kernelLog.localizedCaseInsensitiveContains("oom-kill") || evidence.kernelLog.localizedCaseInsensitiveContains("killed process") {
            result.append(.init(id: "oom", title: "Процесс завершён OOM-killer", reason: "В журнале ядра обнаружено принудительное завершение процесса из-за нехватки памяти.", solution: "Проверить память", command: "journalctl -k -b | grep -iE 'oom|killed process'"))
        }
        if evidence.diskFraction >= 0.95 {
            result.append(.init(id: "disk", title: "Хранилище почти заполнено", reason: "Занято не менее 95% диска; операции записи могут завершаться ENOSPC.", solution: "Найти крупные каталоги", command: "df -h; du -xhd1 /var/lib/vz"))
        }
        if evidence.descriptorFraction >= 0.90 {
            result.append(.init(id: "fd", title: "Исчерпание файловых дескрипторов", reason: "Использовано не менее 90% системного лимита файловых дескрипторов.", solution: "Проверить лимиты", command: "cat /proc/sys/fs/file-nr; systemctl show --property=DefaultLimitNOFILE"))
        }
        for (service, code) in evidence.failedServices.sorted(by: { $0.key < $1.key }) where code != 0 {
            result.append(.init(id: "service-" + service, title: "Сбой службы \(service)", reason: "systemd сообщает ненулевой код завершения: \(code).", solution: "Открыть журнал службы", command: "systemctl --failed; journalctl -b -p err --no-pager"))
        }
        if evidence.gatewayReachable == false {
            result.append(.init(id: "gateway", title: "Шлюз недоступен", reason: "Проверка доступности настроенного шлюза завершилась неудачей; требуется проверка маршрута и bridge.", solution: "Проверить маршрутизацию", command: "ip route; ip -br link; bridge link"))
        }
        return result
    }
}
