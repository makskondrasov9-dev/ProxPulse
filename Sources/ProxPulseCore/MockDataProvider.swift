import Foundation
public enum MockDataProvider {
    public static let profiles = [
        ServerProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Homelab", endpoint: URL(string: "https://pve.home.arpa:8006")!, tokenID: "monitor@pve!proxpulse"),
        ServerProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Studio", endpoint: URL(string: "https://pve.studio.arpa:8006")!, tokenID: "monitor@pve!proxpulse")
    ]
    public static let guests: [Guest] = [
        Guest(id: 100, name: "home-assistant", node: "pve-01", kind: .qemu, running: true, cpu: 0.12, memoryGB: 3.2, maxMemoryGB: 8, diskGB: 96, role: "Smart home"),
        Guest(id: 101, name: "docker-engine", node: "pve-01", kind: .lxc, running: true, cpu: 0.38, memoryGB: 6.4, maxMemoryGB: 16, diskGB: 320, role: "Application services"),
        Guest(id: 102, name: "ubuntu-server", node: "pve-01", kind: .qemu, running: true, cpu: 0.08, memoryGB: 2.1, maxMemoryGB: 8, diskGB: 180, role: "Development"),
        Guest(id: 103, name: "jellyfin", node: "pve-01", kind: .lxc, running: true, cpu: 0.24, memoryGB: 4.8, maxMemoryGB: 8, diskGB: 1120, role: "Media server"),
        Guest(id: 104, name: "adguard-home", node: "pve-01", kind: .lxc, running: true, cpu: 0.02, memoryGB: 0.4, maxMemoryGB: 2, diskGB: 12, role: "Network & DNS"),
        Guest(id: 105, name: "windows-lab", node: "pve-01", kind: .qemu, running: false, cpu: 0, memoryGB: 0, maxMemoryGB: 16, diskGB: 128, role: "Testing environment")
    ].enumerated().map { index, source in
        var guest = source
        guest.cpuCount = [4, 8, 4, 4, 2, 8][index]
        guest.swapGB = index == 1 ? 0.24 : 0; guest.maxSwapGB = 0.512
        guest.maxDiskGB = [160, 400, 192, 1400, 48, 200][index]; guest.diskUsageAvailable = true
        guest.uptimeSeconds = guest.running ? Double(90000 + index * 4000) : 0
        guest.receiveBps = guest.running ? Double(12000 + index * 2400) : nil
        guest.transmitBps = guest.running ? Double(4000 + index * 800) : nil
        return guest
    }
    public static let node = NodeSnapshot(id: "pve-01", online: true, cpu: 0.34, memoryGB: 38.4, maxMemoryGB: 64, networkMBps: 24.8, linkMBps: 125, uptime: "24d 16h", storage:
        DiskItem(id: "root", name: "pve-01", capacityGB: 4000, usedGB: 2456, children: [
            DiskItem(id: "ssd", name: "SSD-FAST", capacityGB: 1000, usedGB: 648, children: [
                DiskItem(id: "100", name: "VM 100 · home-assistant", capacityGB: 160, usedGB: 96),
                DiskItem(id: "101", name: "CT 101 · docker-engine", capacityGB: 400, usedGB: 320),
                DiskItem(id: "105", name: "VM 105 · windows-lab", capacityGB: 200, usedGB: 128),
                DiskItem(id: "ssd-system", name: "System & snapshots", capacityGB: 240, usedGB: 104)]),
            DiskItem(id: "hdd", name: "HDD-2T", capacityGB: 2000, usedGB: 1440, children: [
                DiskItem(id: "103", name: "CT 103 · jellyfin", capacityGB: 1400, usedGB: 1120),
                DiskItem(id: "backups", name: "Backups", capacityGB: 600, usedGB: 320)]),
            DiskItem(id: "nvme", name: "NVMe", capacityGB: 1000, usedGB: 368, children: [
                DiskItem(id: "102", name: "VM 102 · ubuntu-server", capacityGB: 192, usedGB: 180),
                DiskItem(id: "104", name: "CT 104 · adguard-home", capacityGB: 48, usedGB: 12),
                DiskItem(id: "images", name: "Images & templates", capacityGB: 760, usedGB: 176)])]), guests: guests)
    public static var studio: NodeSnapshot {
        var n = node; n.id = "studio-01"; n.cpu = 0.18; n.memoryGB = 22.6; n.storage.name = n.id
        n.guests = n.guests.map { var g = $0; g.node = n.id; return g }; return n
    }
}
