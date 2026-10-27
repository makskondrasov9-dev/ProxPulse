import Foundation
import ProxPulseCore

@main struct CoreChecks {
    static func main() async throws {
        precondition(DiagnosticEngine.analyze(.init()).isEmpty, "Unknown evidence must not imply health or failure")
        precondition(DiagnosticEngine.analyze(.init(diskFraction: 0.949, descriptorFraction: 0.899, failedServices: ["ok": 0], gatewayReachable: true)).isEmpty)
        let findings = DiagnosticEngine.analyze(.init(kernelLog: "kernel: Out of memory: Killed process 42", diskFraction: 0.95, descriptorFraction: 0.9, failedServices: ["z.service": 2, "a.service": 1, "healthy": 0], gatewayReachable: false))
        precondition(findings.map(\.id) == ["oom", "disk", "fd", "service-a.service", "service-z.service", "gateway"])
        func check(_ item: DiskItem) {
            precondition(item.usedGB <= item.capacityGB)
            if !item.children.isEmpty {
                precondition(abs(item.children.reduce(0) { $0 + $1.capacityGB } - item.capacityGB) < 0.001)
                precondition(abs(item.children.reduce(0) { $0 + $1.usedGB } - item.usedGB) < 0.001)
            }
            for child in item.children { check(child) }
        }
        check(MockDataProvider.node.storage)
        precondition(DiskItem(id: "zero", name: "zero", capacityGB: 0, usedGB: 1).fraction == 0)
        for endpoint in ["http://pve.local:8006", "https://user:pass@pve.local", "https://pve.local/?token=secret"] {
            do { _ = try ProxmoxAPIService(profile: .init(name: "test", endpoint: URL(string: endpoint)!, tokenID: "test")); fatalError("Unsafe URL accepted") }
            catch ProxmoxError.invalidEndpoint { }
        }
        let snapshot = WidgetSnapshot(node: MockDataProvider.node)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(decoded.running == 5 && decoded.node == "pve-01" && decoded.cpu == 0.34)
        try verifySprint5()
        verifySprint51()
        try verifySprint6()
        try verifySprint9()
        try await verifySprint7()
        try await verifySprint8()
        try await verifyProgressiveTelemetry()
        try verifySprint4()
        try verifySprint3()
        try await verifyAPIFixtures()
        print("PASS: unknown evidence, thresholds, all incident types/order, capacity accounting, unsafe endpoints, widget snapshot round-trip")
    }
}
