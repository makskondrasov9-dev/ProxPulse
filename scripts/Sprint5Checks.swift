import Foundation
import ProxPulseCore

func verifySprint5() throws {
    var spec = GuestCreationSpec(node: "pve")
    spec.name = "123-container"; spec.vmid = 240; spec.storage = "fast"; spec.template = "local:vztmpl/debian.tar.zst"; spec.bridge = "vmbr0"
    var params = try spec.parameters(password: "fixture-password")
    precondition(params["net0"] == "name=eth0,bridge=vmbr0,firewall=1,ip=dhcp" && params["swap"] == "512" && params["features"] == "nesting=1")
    spec.dhcp = false; spec.address = "192.0.2.20/24"; spec.gateway = "192.0.2.1"; spec.nameserver = "1.1.1.1 8.8.8.8"
    params = try spec.parameters(password: "fixture-password")
    precondition(params["net0"]?.contains("ip=192.0.2.20/24,gw=192.0.2.1") == true)
    for bad in ["192.0.2.20", "192.0.2.20/33", "999.1.1.1/24"] {
        var invalid = spec; invalid.address = bad
        do { _ = try invalid.parameters(password: "fixture-password"); fatalError("Invalid CIDR") } catch ProvisionError.invalid { }
    }
    do { _ = try spec.parameters(password: ""); fatalError("LXC without credentials") } catch ProvisionError.invalid { }
    var vm = GuestCreationSpec(kind: .qemu, node: "pve")
    vm.name = "new-vm"; vm.storage = "fast"; vm.bridge = "vmbr0"; vm.diskBus = "virtio"; vm.sockets = 2; vm.ballooning = true; vm.balloonMB = 512
    params = try vm.parameters(password: "")
    precondition(params["virtio0"] == "fast:16,discard=on" && params["balloon"] == "512" && params["sockets"] == "2" && params["ssh-public-keys"] == nil && params["scsihw"] == nil)
    vm.balloonMB = vm.memoryMB + 1
    do { _ = try vm.parameters(password: ""); fatalError("Invalid balloon") } catch ProvisionError.invalid { }
    var unsafe = spec; unsafe.bridge = "vmbr0,ip=evil"
    do { _ = try unsafe.parameters(password: "fixture-password"); fatalError("Network property injection") } catch ProvisionError.invalid { }
    let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("presets.json")
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    let preset = CreationPreset(name: "Debian", spec: spec)
    try CreationPresetStore.save([preset], to: location)
    let presets = try CreationPresetStore.load(from: location)
    precondition(presets[0].spec.vmid == 0 && presets[0].spec.node.isEmpty && presets[0].spec.address == spec.address)
    let presetJSON = String(data: try Data(contentsOf: location), encoding: .utf8)!
    precondition(!presetJSON.contains("password"))
    let guest = MockDataProvider.guests[5]
    precondition(DestroyGuard.matches("105", guest: guest) && DestroyGuard.matches(guest.name, guest: guest))
    precondition(!DestroyGuard.matches("0105", guest: guest) && !DestroyGuard.matches("105 ", guest: guest) && !DestroyGuard.matches(guest.name.uppercased(), guest: guest))
    let config = try JSONDecoder().decode(GuestConfiguration.self, from: Data(#"{"ostype":"debian","net0":"name=eth0,bridge=vmbr1,ip=dhcp","net1":"name=eth1,bridge=vmbr2"}"#.utf8))
    precondition(config.osType == "debian" && config.bridges == ["vmbr1", "vmbr2"])
    for name in ["wg0", "awg1", "tun0"] { precondition(NodeNetworkInterface(iface: name).isTunnel) }
    precondition(!NodeNetworkInterface(iface: "vmbr0").isTunnel && NodeNetworkInterface(iface: "vmbr0").isBridge)
    precondition(TrafficAnimation.frequency(bytesPerSecond: 0) == 0 && TrafficAnimation.frequency(bytesPerSecond: 100_000) > TrafficAnimation.frequency(bytesPerSecond: 100))
    let multiNIC = try JSONDecoder().decode(GuestConfiguration.self, from: Data(#"{"net10":"virtio,bridge=vmbr10","net0":"virtio,bridge=vmbr9","net1":"virtio,bridge=vmbr1","net2":"virtio,bridge=vmbr9"}"#.utf8))
    precondition(multiNIC.bridges == ["vmbr9", "vmbr1", "vmbr10"])
    var phase = TrafficPhase(speed: 0.4, time: 800_000_000)
    let switchTime = 800_000_003.25
    let before = phase.position(at: switchTime)
    phase.update(speed: 1.1, time: switchTime)
    precondition(abs(phase.position(at: switchTime) - before) < 0.000001)
    for fps in [60.0, 120.0] {
        for frame in 1...120 {
            let a = phase.position(at: switchTime + Double(frame - 1) / fps)
            let b = phase.position(at: switchTime + Double(frame) / fps)
            let distance = (b - a + 1).truncatingRemainder(dividingBy: 1)
            precondition(abs(distance - 1.1 / fps) < 0.000001)
        }
    }
    let runtime = try JSONDecoder().decode(RuntimeNetworkSnapshot.self, from: Data(#"{"interfaces":[{"iface":"awg0","type":"tunnel","active":1}],"measurements":{"awg0":{"peer":"203.0.113.10","pingMS":76,"receiveBps":1234,"transmitBps":567}},"errors":{}}"#.utf8))
    precondition(runtime.interfaces[0].isTunnel && runtime.measurements["awg0"]?.peer == "203.0.113.10")
    print("PASS: runtime VPN discovery payload and continuous particle phases across rate changes, wrap, 60/120 Hz")
    print("PASS: exact LXC/VM parameters, validation, CIDR, balloon, presets without secrets, destroy typing, bridges/tunnels, real-rate animation")
}
