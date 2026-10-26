import SwiftUI
import ProxPulseCore

extension DashboardModel {
    func portAudit(for guest: Guest) -> PortAudit? {
        guard guest.running else { return nil }
        return isDemo ? .demo(guest) : portAudits[MonitoringRules.guestKey(guest)]
    }
    func schedulePortInspection() {
        let running = node.guests.filter(\.running)
        let keys = Set(running.map(MonitoringRules.guestKey))
        portAudits = portAudits.filter { keys.contains($0.key) }
        if !inspectingPorts.isSubset(of: keys) {
            portAuditTask?.cancel(); portAuditTask = nil; inspectingPorts = []
        }
        inspectingPorts.formIntersection(keys)
        guard !isDemo, node.online, connectionError == nil, portAuditTask == nil, let service else { return }
        let pending = Array(running.filter { guest in
            guard let report = portAudits[MonitoringRules.guestKey(guest)] else { return true }
            return Date().timeIntervalSince(report.date) >= 30
        }.sorted { (portAudits[MonitoringRules.guestKey($0)]?.date ?? .distantPast) < (portAudits[MonitoringRules.guestKey($1)]?.date ?? .distantPast) }.prefix(4))
        guard !pending.isEmpty else { return }
        let engine = PortInspectionService(api: service), current = revision
        let inputs = pending.map { ($0, addresses(for: $0)) }
        inspectingPorts.formUnion(pending.map(MonitoringRules.guestKey))
        portAuditTask = Task { [weak self] in
            for start in stride(from: 0, to: inputs.count, by: 2) {
                guard !Task.isCancelled else { return }
                let batch = Array(inputs[start..<min(start+2, inputs.count)])
                let results = await withTaskGroup(of: (String, PortAudit?).self) { group in
                    for (guest, addresses) in batch {
                        group.addTask {
                            do { return (MonitoringRules.guestKey(guest), try await engine.inspect(guest, addresses: addresses)) }
                            catch is CancellationError { return (MonitoringRules.guestKey(guest), nil) }
                            catch { return (MonitoringRules.guestKey(guest), .init(source: .tcpScan, coverage: .unavailable, reason: error.localizedDescription)) }
                        }
                    }
                    var values: [(String, PortAudit?)] = []
                    for await result in group { values.append(result) }
                    return values
                }
                guard !Task.isCancelled, let self, self.revision == current else { return }
                let live = Set(self.node.guests.filter(\.running).map(MonitoringRules.guestKey))
                var securityChanged = false
                for (key, report) in results {
                    self.inspectingPorts.remove(key)
                    if live.contains(key), let report {
                        let old = self.portAudits[key]
                        securityChanged = securityChanged || old == nil || Set(old?.ports.map(\.port) ?? []) != Set(report.ports.map(\.port)) || old?.hasRisk != report.hasRisk || old?.coverage != report.coverage
                        self.portAudits[key] = report
                    }
                }
                self.publishSnapshot(force: securityChanged)
            }
            if let self, self.revision == current { self.portAuditTask = nil }
        }
    }
}
