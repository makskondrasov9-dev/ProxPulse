import Foundation

public enum LiveDataAdapter {
    public static func snapshot(name: String, status: NodeStatus, resources: [ClusterResource], storage: [StorageStatus]) -> NodeSnapshot {
        let gb = 1_000_000_000.0
        let pools = storage.filter { $0.active == 1 && $0.enabled != 0 && ($0.total ?? 0) > 0 }.map {
            DiskItem(id: name + "/" + $0.storage, name: $0.storage, capacityGB: max(0, $0.total ?? 0) / gb, usedGB: max(0, $0.used ?? 0) / gb)
        }.sorted { $0.name < $1.name }
        let disk = DiskItem(id: name + "/storage", name: name, capacityGB: pools.reduce(0) { $0 + $1.capacityGB }, usedGB: pools.reduce(0) { $0 + $1.usedGB }, children: pools)
        let guests = resources.compactMap { resource -> Guest? in
            guard let kind = GuestKind(rawValue: resource.type), let id = resource.vmid, let node = resource.node else { return nil }
            var guest = Guest(id: id, name: resource.name ?? "\(kind.rawValue) \(id)", node: node, kind: kind, running: resource.status == "running", cpu: min(1, max(0, resource.cpu ?? 0)), memoryGB: (resource.mem ?? 0) / gb, maxMemoryGB: (resource.maxmem ?? 0) / gb, diskGB: (resource.disk ?? 0) / gb, role: node)
            guest.maxDiskGB = resource.maxdisk.map { $0 / gb }
            return guest
        }.sorted { $0.id < $1.id }
        let seconds = max(0, Int(status.uptime))
        return NodeSnapshot(id: name, online: true, cpu: min(1, max(0, status.cpu)), memoryGB: status.memory.used / gb, maxMemoryGB: status.memory.total / gb,
                            networkMBps: 0, linkMBps: 0, uptime: "\(seconds / 86400)d \(seconds % 86400 / 3600)h \(seconds % 3600 / 60)m", storage: disk, guests: guests,
                            cpuModel: status.cpuinfo?.model, cpuCount: status.cpuinfo?.cpus,
                            storageNote: "Логические хранилища API. Общий backing pool может учитываться несколько раз; размещение дисков VM/CT не определяется этим endpoint.")
    }
}
