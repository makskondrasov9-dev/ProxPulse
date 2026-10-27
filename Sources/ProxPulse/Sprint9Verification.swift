#if DEBUG
import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI
import WidgetKit

@MainActor enum Sprint9Verification {
    static func run(live: Bool) async throws {
        let model = DashboardModel(loadProfiles: false)
        defer { model.stop() }
        if live {
            guard let profile = try ProfileStore.load().first else { throw ProxmoxError.noNodes }
            model.profiles = [profile]; model.selectedProfile = profile.id
            let deadline = Date().addingTimeInterval(70)
            while Date() < deadline {
                if let error = model.connectionError { throw ProvisionError.invalid(error) }
                if model.hasSnapshot && model.node.guests.contains(where: { $0.id == 105 }) && !model.topologyGuestAddresses.isEmpty && model.portAudits.keys.contains(where: { $0.hasSuffix("/105") }) { break }
                try await Task.sleep(for: .milliseconds(250))
            }
            precondition(model.hasSnapshot)
        }
        let snapshot = model.widgetSnapshot
        let query = MachineEntityQuery(loadSnapshot: { snapshot })
        let targets = live ? [105,101,106].compactMap { id in snapshot.guests?.first { $0.id == id } } : Array((snapshot.guests ?? []).prefix(2)) + Array((snapshot.guests ?? []).filter { !$0.running })
        precondition(targets.count >= 3)
        for guest in targets {
            let key = MonitoringRules.guestKey(guest)
            for identifier in [String(guest.id), "\(guest.node)/\(guest.id)", key, MachineEntity.identifier(profileID: snapshot.profileID, guestKey: key)] {
                // Rehydrate exactly the archived identifier WidgetKit gives the query.
                let resolved = try await query.entities(for: [identifier])
                precondition(resolved.count == 1 && resolved[0].id == identifier && resolved[0].name == guest.name && resolved[0].running == guest.running)
                let entry = MachineTimelineProvider.entry(for: SelectMachineIntent(machine: resolved[0]), snapshot: snapshot)
                precondition(entry.machineKey == key)
                let metrics = MachineIdentity(entry.machineKey!)!.resolve(in: entry.snapshot!)!
                precondition(metrics.memoryGB == guest.memoryGB && metrics.cpu == guest.cpu && metrics.running == guest.running)
                if !guest.running { precondition(snapshot.portSecurity(for: guest) == nil) }
            }
            let entity = MachineEntity(guest: guest, profileID: snapshot.profileID)
            let intent = SelectMachineIntent(machine: entity)
            let entry = MachineTimelineProvider.entry(for: intent, snapshot: snapshot)
            for (name, family, dimensions) in [("small",WidgetFamily.systemSmall,NSSize(width:170,height:170)),("medium",.systemMedium,NSSize(width:360,height:170)),("large",.systemLarge,NSSize(width:360,height:360))] {
                RuntimeUIVerification.capture(MachineWidgetView(entry:.init(date:entry.date,snapshot:entry.snapshot),machineKey:entry.machineKey,family:family).padding(14).environment(\.colorScheme,.dark),size:dimensions,name:"sprint9-\(live ? "live" : "demo")-\(guest.id)-"+name)
            }
            print("WIDGET \(guest.id) \(guest.name): \(guest.running ? "running" : "stopped") CPU=\(guest.cpu) RAM=\(guest.memoryGB)/\(guest.maxMemoryGB) vCPU=\(guest.cpuCount ?? 0) IP=\(guest.ipAddresses?.first ?? "unknown") ports=\(snapshot.portSecurity(for:guest)?.compactList ?? "hidden/unavailable")")
        }
        // One long-lived query must discard prior-profile entities and reflect removals/additions.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-query-"+UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:file) }
        let dynamic = MachineEntityQuery(loadSnapshot: { try? JSONDecoder().decode(WidgetSnapshot.self,from:Data(contentsOf:file)) })
        try JSONEncoder().encode(snapshot).write(to:file)
        let first = try await dynamic.suggestedEntities(); precondition(first.count == snapshot.guests?.count)
        var other = snapshot; other.profileID = UUID(); other.guests = []
        try JSONEncoder().encode(other).write(to:file)
        let empty = try await dynamic.suggestedEntities(); precondition(empty.isEmpty)
        let oldID = MachineEntity(guest:targets[0],profileID:snapshot.profileID).id
        let tombstone = try await dynamic.entities(for:[oldID])
        let missing = MachineTimelineProvider.entry(for:.init(machine:tombstone[0]),snapshot:other)
        precondition(missing.machineKey != nil && MachineIdentity(missing.machineKey!)?.resolve(in:other) == nil)
        print("PASS: per-widget archived IDs resolve immediately to current metrics; running + stopped widgets in all 3 sizes; fresh entity query/profile eviction and missing-state isolation")
    }
}
#endif
