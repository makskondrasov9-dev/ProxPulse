import XCTest
@testable import ProxPulseCore
final class DiagnosticEngineTests: XCTestCase {
    func testUnknownEvidenceIsNotAnIncident() {
        XCTAssertTrue(DiagnosticEngine.analyze(.init()).isEmpty)
        XCTAssertTrue(DiagnosticEngine.analyze(.init(diskFraction: 0.949, descriptorFraction: 0.899, failedServices: ["ok": 0], gatewayReachable: true)).isEmpty)
    }
    func testAllFiveIncidentTypesAndStableOrder() {
        let findings = DiagnosticEngine.analyze(.init(kernelLog: "kernel: Out of memory: Killed process 42", diskFraction: 0.95, descriptorFraction: 0.9, failedServices: ["z.service": 2, "a.service": 1, "healthy": 0], gatewayReachable: false))
        XCTAssertEqual(findings.map(\.id), ["oom", "disk", "fd", "service-a.service", "service-z.service", "gateway"])
        XCTAssertTrue(findings[3].reason.contains("1"))
    }
    func testCapacityAccountingAndFractions() {
        func check(_ item: DiskItem) {
            XCTAssertLessThanOrEqual(item.usedGB, item.capacityGB)
            if !item.children.isEmpty {
                XCTAssertEqual(item.children.reduce(0) { $0 + $1.capacityGB }, item.capacityGB, accuracy: 0.001)
                XCTAssertEqual(item.children.reduce(0) { $0 + $1.usedGB }, item.usedGB, accuracy: 0.001)
            }
            for child in item.children { check(child) }
        }
        check(MockDataProvider.node.storage)
        XCTAssertEqual(DiskItem(id: "zero", name: "zero", capacityGB: 0, usedGB: 1).fraction, 0)
    }
    func testRejectsUnsafeEndpointsBeforeReadingCredentials() {
        for endpoint in ["http://pve.local:8006", "https://user:pass@pve.local", "https://pve.local/?token=secret"] {
            XCTAssertThrowsError(try ProxmoxAPIService(profile: .init(name: "test", endpoint: URL(string: endpoint)!, tokenID: "test")))
        }
    }
    func testProxyPortsAndPrefixes() throws {
        XCTAssertNil(try ProfileValidation.endpoint("https://pve.example.com/pve/").port)
        XCTAssertEqual(try ProfileValidation.endpoint("https://pve.example.com/pve/").path, "/pve")
        XCTAssertEqual(try ProfileValidation.endpoint("https://pve.example.com:8006").port, 8006)
    }

}
