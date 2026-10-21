#if DEBUG
import SwiftUI
import ProxPulseCore

@MainActor enum Sprint5Verification {
    static func run() async throws {
        let demo = DashboardModel(loadProfiles: false)
        demo.selectedPage = "Машины"
        for mode in WorkspaceViewMode.allCases {
            demo.selectedPage = mode == .topology ? "Обзор" : "Машины"
            demo.workspaceMode = mode
            if mode == .topology { await demo.refreshTopology() }
            demo.inspect(demo.node.guests[0])
            precondition(demo.inspectedGuest?.id == 100 && demo.samples(for: demo.node.guests[0]).count == 24)
            demo.inspectedGuest = nil
            RuntimeUIVerification.capture(DashboardView(model: demo, animate: false).environment(\.colorScheme, .dark), size: .init(width: 1440, height: mode == .topology ? 1200 : 1100), name: "sprint5-" + mode.rawValue)
        }
        precondition(demo.networkInterfaces.contains(where: \.isTunnel))
        let ct = GuestWizardModel(dashboard: demo, kind: .lxc)
        await ct.loadCatalog()
        ct.password = "fixture-password"; ct.spec.name = "debian-services"
        precondition(ct.validation == nil && ct.spec.vmid == 106 && ct.spec.unprivileged)
        RuntimeUIVerification.capture(CreateGuestSheet(model: demo, wizard: ct).environment(\.colorScheme, .dark), size: .init(width: 870, height: 740), name: "sprint5-create-lxc")
        ct.password = "fixture-password"; ct.page = 4
        RuntimeUIVerification.capture(CreateGuestSheet(model: demo, wizard: ct).environment(\.colorScheme, .dark), size: .init(width: 870, height: 740), name: "sprint5-create-review")
        let vm = GuestWizardModel(dashboard: demo, kind: .qemu)
        await vm.loadCatalog(); vm.page = 2
        RuntimeUIVerification.capture(CreateGuestSheet(model: demo, wizard: vm).environment(\.colorScheme, .dark), size: .init(width: 870, height: 740), name: "sprint5-create-vm")
        let original = demo.node.guests[5]
        RuntimeUIVerification.capture(DestroyGuardSheet(pending: .init(guest: original, origin: .dashboard), model: demo).environment(\.colorScheme, .dark), size: .init(width: 550, height: 440), name: "sprint5-destroy-guard")
        demo.request(demo.node.guests[0], action: .reboot, origin: .inspector)
        precondition(demo.pendingAction?.origin == .inspector); demo.pendingAction = nil
        ct.password = "fixture-password"
        try await demo.create(ct.spec, password: ct.password) { _ in }
        guard let created = demo.node.guests.first(where: { $0.id == 106 }) else { fatalError("Demo create missing") }
        precondition(!created.running && created.cpuCount == ct.spec.cores && demo.node.guests.count == 7)
        do { try await demo.destroy(created, confirmation: "0106"); fatalError("Destroy typing bypass") } catch ProvisionError.invalid { }
        precondition(demo.node.guests.count == 7)
        try await demo.destroy(created, confirmation: "106")
        precondition(demo.node.guests.count == 6)
        demo.stop()
        print("PASS: grid/rack/topology native renders; shared inspector history; CT/VM wizard/catalog/review; nested actions; typed destroy; demo create/delete without server mutations")
    }
}
#endif
