#if DEBUG
import SwiftUI
import AppIntents
import ProxPulseCore
import ProxPulseWidgetUI

@MainActor enum Sprint622Verification {
    static func run() async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        await model.refreshTopology()
        let guests = model.node.guests
        for sort in GuestSort.allCases {
            model.guestSort = sort
            let ordered = model.filteredGuests
            for (a,b) in zip(ordered, ordered.dropFirst()) {
                switch sort {
                case .ram: precondition(a.memoryGB >= b.memoryGB)
                case .cpu: precondition(a.cpu >= b.cpu)
                case .vmid: precondition(a.id <= b.id)
                case .name: precondition(a.name.localizedStandardCompare(b.name) != .orderedDescending)
                }
            }
        }
        let guest = guests[1]
        model.topologyGuestAddresses[MonitoringRules.guestKey(guest)] = ["192.0.2.235"]
        for query in ["192.0.2.235", String(guest.id), guest.name] {
            precondition(model.node.guests.filter { model.matches($0, query: query) }.contains { $0.id == guest.id })
        }
        model.guestFilter = "Выключены"; precondition(model.filteredGuests.allSatisfy { !$0.running })
        model.guestFilter = "Работают"; precondition(model.filteredGuests.allSatisfy(\.running))
        model.guestFilter = "Все"; model.search = "no-match"
        precondition(model.filteredGuests.isEmpty && model.matches(guest, query: "192.0.2.235"))
        model.search = ""
        var snapshot = WidgetSnapshot(node: model.node, isDemo: true)
        snapshot.profileID = DashboardModel.demoID
        // Legacy global selection must have no effect on individual widget configurations.
        snapshot.selectedMachineKey = MonitoringRules.guestKey(guests.last!)
        let entities = MachineEntityQuery.machines(in: snapshot)
        precondition(entities.count == guests.count)
        var keys = Set<String>()
        for entity in entities.prefix(3) {
            let intent = SelectMachineIntent(machine: entity)
            let entry = MachineTimelineProvider.entry(for: intent, snapshot: snapshot)
            precondition(entry.machineKey == entity.guestKey)
            keys.insert(entry.machineKey!)
            RuntimeUIVerification.capture(MachineWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot), machineKey: entry.machineKey).padding(16).environment(\.colorScheme, .dark), size: .init(width: 360, height: 180), name: "sprint622-widget-\(entity.vmid)")
        }
        precondition(keys.count == 3)
        let selected = SelectMachineIntent(machine: entities[0])
        var otherProfile = snapshot; otherProfile.profileID = UUID()
        precondition(MachineTimelineProvider.entry(for: selected, snapshot: otherProfile).machineKey == selected.machine?.id)
        precondition(MachineTimelineProvider.entry(for: SelectMachineIntent(), snapshot: snapshot).machineKey == nil)
        var updated = snapshot; updated.guests?[0].memoryGB = 2.1
        precondition(MachineTimelineProvider.entry(for: selected, snapshot: updated).snapshot?.guests?[0].memoryGB == 2.1)
        model.selectedPage = "Обзор"
        RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance().environment(\.colorScheme, .dark), size: .init(width: 1500, height: 1400), name: "sprint622-overview")
        model.selectedPage = "Машины"; model.workspaceMode = .grid
        RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance().environment(\.colorScheme, .dark), size: .init(width: 1500, height: 1050), name: "sprint622-fleet")
        model.quickSearchPresented = true
        RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance().environment(\.colorScheme, .dark), size: .init(width: 1500, height: 1050), name: "sprint622-search")
        model.quickSearchPresented = false; model.workspaceMode = .rack
        RuntimeUIVerification.capture(DashboardView(model: model, animate: false).pulseAppearance().environment(\.colorScheme, .dark), size: .init(width: 1500, height: 1050), name: "sprint622-rack")
        print("PASS: independent widget selections, profile isolation, no legacy global fallback, fresh metrics, fleet sorting/status filters, IP/name/VMID search, overview/fleet/search/rack native renders")
    }
}
#endif
