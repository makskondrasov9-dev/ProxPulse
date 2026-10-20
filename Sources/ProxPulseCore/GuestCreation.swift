import Foundation
import Darwin

public enum ProvisionError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public struct GuestCreationSpec: Codable, Sendable, Equatable {
    public var kind: GuestKind = .lxc
    public var node = ""
    public var vmid = 100
    public var name = ""
    public var unprivileged = true
    public var nesting = true
    public var sshPublicKeys = ""
    public var template = ""
    public var storage = ""
    public var diskGB = 16
    public var cores = 2
    public var memoryMB = 2048
    public var swapMB = 512
    public var bridge = ""
    public var dhcp = true
    public var address = ""
    public var gateway = ""
    public var firewall = true
    public var nameserver = ""
    public var searchdomain = ""
    public var iso = ""
    public var agent = true
    public var diskBus = "scsi"
    public var discard = true
    public var sockets = 1
    public var cpuType = "host"
    public var networkModel = "virtio"
    public var osType = "l26"
    public var ballooning = false
    public var balloonMB = 512
    public init(kind: GuestKind = .lxc, node: String = "") { self.kind = kind; self.node = node }
    public static func ipv4(_ address: String) -> Bool {
        var parsed = in_addr()
        return address.withCString { inet_pton(AF_INET, $0, &parsed) == 1 }
    }
    public func parameters(password: String) throws -> [String: String] {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw ProvisionError.invalid(message) } }
        func simple(_ value: String) -> Bool { !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }
        try require(simple(node), "Выберите ноду.")
        try require((100...999_999_999).contains(vmid), "VMID должен быть от 100 до 999999999.")
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        try require(!name.isEmpty && name.count <= 253 && labels.allSatisfy { label in !label.isEmpty && label.count <= 63 }, "Укажите корректное DNS-имя машины.")
        try require(labels.allSatisfy { label in label.first?.isLetter == true || label.first?.isNumber == true } && labels.allSatisfy { label in (label.last?.isLetter == true || label.last?.isNumber == true) && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }, "Укажите корректное DNS-имя машины.")
        try require(simple(storage) && simple(bridge), "Выберите хранилище и сетевой мост.")
        try require((1...8192).contains(cores) && (1...16).contains(sockets), "Проверьте число CPU cores / sockets.")
        try require((16...4_194_304).contains(memoryMB) && (0...4_194_304).contains(swapMB), "Проверьте RAM и SWAP (MiB).")
        try require((1...1_000_000).contains(diskGB), "Проверьте размер диска (GiB).")
        var parameters = ["vmid": String(vmid), "cores": String(cores), "memory": String(memoryMB)]
        if kind == .lxc {
            try require(!template.isEmpty && template.contains(":vztmpl/") && !template.contains(where: { $0.isNewline }), "Выберите доступный шаблон LXC.")
            try require(password.isEmpty || password.count >= 5, "Пароль LXC должен содержать не менее 5 символов.")
            let keys = sshPublicKeys.trimmingCharacters(in: .whitespacesAndNewlines)
            try require(!password.isEmpty || !keys.isEmpty, "Введите пароль LXC или публичный SSH-ключ.")
            if !keys.isEmpty {
                let supported = ["ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com"]
                try require(keys.split(separator: "\n").allSatisfy { line in let fields = line.split(whereSeparator: \.isWhitespace); return fields.count >= 2 && supported.contains(String(fields[0])) && Data(base64Encoded: String(fields[1])) != nil }, "Нужен публичный SSH-ключ OpenSSH, по одному на строку.")
            }
            parameters.merge(["hostname": name, "ostemplate": template, "rootfs": "\(storage):\(diskGB)", "unprivileged": unprivileged ? "1" : "0", "features": "nesting=\(nesting ? 1 : 0)", "swap": String(swapMB), "start": "0"]) { _, new in new }
            if !password.isEmpty { parameters["password"] = password }
            if !keys.isEmpty { parameters["ssh-public-keys"] = keys }
            var net = "name=eth0,bridge=\(bridge),firewall=\(firewall ? 1 : 0)"
            if dhcp { net += ",ip=dhcp" }
            else {
                let parts = address.split(separator: "/", omittingEmptySubsequences: false)
                try require(parts.count == 2 && Self.ipv4(String(parts[0])) && Int(parts[1]).map { (0...32).contains($0) } == true, "Статический IPv4 должен включать CIDR, например 192.168.1.20/24.")
                try require(gateway.isEmpty || Self.ipv4(gateway), "Укажите корректный IPv4 шлюза.")
                net += ",ip=\(address)"; if !gateway.isEmpty { net += ",gw=\(gateway)" }
            }
            parameters["net0"] = net
            if !nameserver.isEmpty {
                try require(nameserver.split(whereSeparator: \.isWhitespace).allSatisfy { Self.ipv4(String($0)) }, "DNS: IPv4-адреса через пробел.")
                parameters["nameserver"] = nameserver
            }
            if !searchdomain.isEmpty { try require(searchdomain.split(whereSeparator: \.isWhitespace).allSatisfy { simple(String($0)) }, "Проверьте DNS search domain."); parameters["searchdomain"] = searchdomain }
        } else {
            try require(["scsi", "virtio"].contains(diskBus) && ["virtio", "e1000", "rtl8139", "vmxnet3"].contains(networkModel), "Выберите поддерживаемую модель диска / NIC.")
            try require(simple(cpuType) && ["l26", "win10", "win11", "other"].contains(osType), "Проверьте тип CPU и гостевой ОС.")
            try require(!ballooning || (16...memoryMB).contains(balloonMB), "Минимальная balloon memory должна быть в пределах RAM.")
            try require(iso.isEmpty || iso.contains(":iso/") && !iso.contains(",") && !iso.contains(where: { $0.isNewline }), "Выберите доступный ISO.")
            parameters.merge(["name": name, "sockets": String(sockets), "cpu": cpuType, "ostype": osType, "agent": "enabled=\(agent ? 1 : 0)", "balloon": String(ballooning ? balloonMB : 0), diskBus + "0": "\(storage):\(diskGB),discard=\(discard ? "on" : "ignore")", "net0": "\(networkModel),bridge=\(bridge),firewall=\(firewall ? 1 : 0)", "ide2": iso.isEmpty ? "none,media=cdrom" : iso + ",media=cdrom"]) { _, new in new }
            parameters["boot"] = "order=" + (iso.isEmpty ? "" : "ide2;") + diskBus + "0;net0"
            if diskBus == "scsi" { parameters["scsihw"] = "virtio-scsi-single" }
        }
        return parameters
    }
}
public struct CreationStorage: Identifiable, Sendable {
    public var id: String
    public var content: Set<String>
    public var available: Double?
    public init(id: String, content: Set<String>, available: Double? = nil) { self.id = id; self.content = content; self.available = available }
}
public struct CreationMedia: Decodable, Identifiable, Sendable {
    public var volid: String
    public var content: String?
    public var size: Double?
    public var id: String { volid }
    public init(volid: String, content: String? = nil) { self.volid = volid; self.content = content }
}
public struct CreationCatalog: Sendable {
    public var nextID: Int
    public var storage: [CreationStorage]
    public var media: [CreationMedia]
    public var bridges: [String]
    public var warnings: [String]
    public static var demo: CreationCatalog { .init(nextID: 106, storage: [.init(id: "SSD-FAST", content: ["rootdir", "images"]), .init(id: "local", content: ["vztmpl", "iso"])], media: [.init(volid: "local:vztmpl/debian-12-standard.tar.zst", content: "vztmpl"), .init(volid: "local:iso/debian-12.iso", content: "iso")], bridges: ["vmbr0", "vmbr1"], warnings: []) }
    public func validate(_ spec: GuestCreationSpec) throws {
        guard let pool = storage.first(where: { $0.id == spec.storage }), pool.content.contains(spec.kind == .lxc ? "rootdir" : "images"), bridges.contains(spec.bridge) else { throw ProvisionError.invalid("Хранилище или мост недоступны на выбранной ноде.") }
        if spec.kind == .lxc && !media.contains(where: { $0.volid == spec.template && $0.content == "vztmpl" }) { throw ProvisionError.invalid("Шаблон отсутствует в каталоге ноды.") }
        if spec.kind == .qemu && !spec.iso.isEmpty && !media.contains(where: { $0.volid == spec.iso && $0.content == "iso" }) { throw ProvisionError.invalid("ISO отсутствует в каталоге ноды.") }
        if let available = pool.available, Double(spec.diskGB) * 1_073_741_824 > available { throw ProvisionError.invalid("Недостаточно свободного места для выбранного диска.") }
    }
}
public struct CreationPreset: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var spec: GuestCreationSpec
    public init(name: String, spec: GuestCreationSpec) { self.name = name; self.spec = spec; self.spec.vmid = 0; self.spec.node = "" }
}
public enum CreationPresetStore {
    public static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ProxPulse/creation-presets.json") }
    public static func load(from location: URL = CreationPresetStore.url) throws -> [CreationPreset] {
        guard FileManager.default.fileExists(atPath: location.path) else { return [] }
        return try JSONDecoder().decode([CreationPreset].self, from: Data(contentsOf: location))
    }
    public static func save(_ presets: [CreationPreset], to location: URL = CreationPresetStore.url) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(presets).write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
    }
}
public enum DestroyGuard {
    public static func matches(_ text: String, guest: Guest) -> Bool { text == String(guest.id) || (!guest.name.isEmpty && text == guest.name) }
}
