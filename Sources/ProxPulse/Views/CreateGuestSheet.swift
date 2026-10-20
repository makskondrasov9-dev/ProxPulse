import SwiftUI
import ProxPulseCore

@MainActor @Observable final class GuestWizardModel {
    var spec: GuestCreationSpec
    var password = ""
    var catalog: CreationCatalog?
    var presets: [CreationPreset] = []
    var loading = false
    var submitting = false
    var error: String?
    var upid: String?
    var page = 0
    private let dashboard: DashboardModel
    private let profile: UUID
    init(dashboard: DashboardModel, kind: GuestKind) {
        self.dashboard = dashboard; profile = dashboard.selectedProfile
        spec = GuestCreationSpec(kind: kind, node: dashboard.node.id)
        spec.name = kind == .lxc ? "container" : "virtual-machine"
        do { presets = try CreationPresetStore.load() } catch { self.error = error.localizedDescription }
    }
    var eligibleStorage: [CreationStorage] { (catalog?.storage ?? []).filter { $0.content.contains(spec.kind == .lxc ? "rootdir" : "images") } }
    var media: [CreationMedia] { (catalog?.media ?? []).filter { $0.content == (spec.kind == .lxc ? "vztmpl" : "iso") } }
    var validation: String? {
        do {
            guard let catalog else { return "Загрузите каталог ноды." }
            try catalog.validate(spec); _ = try spec.parameters(password: password)
            guard dashboard.selectedProfile == profile else { return "Профиль сервера изменился. Откройте мастер заново." }
            return nil
        } catch { return error.localizedDescription }
    }
    func loadCatalog() async {
        let node = spec.node; loading = true; error = nil; catalog = nil
        defer { if spec.node == node { loading = false } }
        do {
            let value = try await dashboard.creationCatalog(node: node, kind: spec.kind)
            guard !Task.isCancelled, spec.node == node, dashboard.selectedProfile == profile else { return }
            catalog = value; spec.vmid = value.nextID
            if !eligibleStorage.contains(where: { $0.id == spec.storage }) { spec.storage = eligibleStorage.first?.id ?? "" }
            if !value.bridges.contains(spec.bridge) { spec.bridge = value.bridges.contains("vmbr0") ? "vmbr0" : value.bridges.first ?? "" }
            if spec.kind == .lxc && !media.contains(where: { $0.volid == spec.template }) { spec.template = media.first?.volid ?? "" }
        } catch { if !Task.isCancelled && spec.node == node { self.error = error.localizedDescription } }
    }
    func apply(_ preset: CreationPreset) {
        let vmid = spec.vmid; let node = spec.node
        spec = preset.spec; spec.node = node; spec.vmid = vmid; password = ""
    }
    func savePreset(name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProvisionError.invalid("Введите имя пресета.") }
        var updated = presets
        updated.removeAll { $0.name == name && $0.spec.kind == spec.kind }
        updated.append(.init(name: name, spec: spec))
        try CreationPresetStore.save(updated); presets = updated
    }
    func submit() async -> Bool {
        guard !submitting, validation == nil else { return false }
        submitting = true; error = nil
        defer { submitting = false; password = "" }
        do { try await dashboard.create(spec, password: password) { self.upid = $0 }; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
struct CreateGuestSheet: View {
    var dashboard: DashboardModel
    @State var wizard: GuestWizardModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseAccent) private var accent
    @State private var showPreset = false
    @State private var presetName = ""
    private let pages = ["Основные", "Операционная система", "Ресурсы", "Сеть", "Подтверждение"]
    init(model: DashboardModel, kind: GuestKind) { dashboard = model; _wizard = State(initialValue: GuestWizardModel(dashboard: model, kind: kind)) }
    init(model: DashboardModel, wizard: GuestWizardModel) { dashboard = model; _wizard = State(initialValue: wizard) }
    var body: some View {
        @Bindable var wizard = wizard
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: wizard.spec.kind == .lxc ? "shippingbox" : "desktopcomputer").font(.title).foregroundStyle(accent.uiColor)
                VStack(alignment: .leading, spacing: 5) {
                    T(wizard.spec.kind == .lxc ? "Новый контейнер LXC" : "Новая виртуальная машина").font(.title2.bold())
                    Text(dashboard.profileName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if dashboard.isDemo { Text("DEMO").font(.caption.bold()).foregroundStyle(.orange) }
            }.padding(24)
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button { wizard.page = index } label: {
                            HStack(spacing: 9) {
                                Text(String(index + 1)).font(.caption.bold()).frame(width: 24, height: 24).background(wizard.page == index ? accent.uiColor.opacity(0.2) : .primary.opacity(0.04), in: Circle())
                                T(pages[index]).font(.system(size: 11, weight: .medium))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8).foregroundStyle(wizard.page == index ? accent.uiColor : .secondary)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    T("Пароль используется только для создания и не сохраняется в пресете.").font(.caption2).foregroundStyle(.secondary)
                }.padding(16).frame(width: 200).background(.primary.opacity(0.02))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        presets
                        if wizard.loading { HStack { ProgressView().controlSize(.small); T("Загрузка каталогов Proxmox…") } }
                        Group {
                            switch wizard.page {
                            case 0: general
                            case 1: operatingSystem
                            case 2: resources
                            case 3: network
                            default: review
                            }
                        }.disabled(wizard.loading || wizard.submitting)
                        if let error = wizard.error { T(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                        ForEach(wizard.catalog?.warnings ?? [], id: \.self) { T($0).font(.caption).foregroundStyle(.orange) }
                        if let validation = wizard.validation, !wizard.loading { TL(validation, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                    }.padding(24)
                }.frame(maxWidth: .infinity)
            }
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 10) {
                if wizard.submitting { HStack { ProgressView().controlSize(.small); T("Ожидание завершения задачи Proxmox…") }; if let upid = wizard.upid { Text(upid).font(.caption2.monospaced()).textSelection(.enabled) } }
                HStack {
                    LB("Отмена") { dismiss() }.keyboardShortcut(.cancelAction).disabled(wizard.submitting)
                    Spacer()
                    LB("Назад") { wizard.page = max(0, wizard.page - 1) }.disabled(wizard.page == 0 || wizard.submitting)
                    if wizard.page < 4 { LB("Далее") { wizard.page += 1 }.buttonStyle(.borderedProminent).disabled(wizard.submitting) }
                    else { LB("Создать") { Task { if await wizard.submit() { dismiss() } } }.buttonStyle(.borderedProminent).disabled(wizard.validation != nil || wizard.loading || wizard.submitting) }
                }
                T("Машина создаётся выключенной. После отправки задача продолжает выполняться на сервере.").font(.caption2).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(width: 870, height: 740).background(.ultraThinMaterial)
            .task(id: wizard.spec.node) { await wizard.loadCatalog() }
            .onDisappear { wizard.password = "" }
            .interactiveDismissDisabled(wizard.submitting)
    }
    private var presets: some View {
        HStack {
            Menu {
                ForEach(wizard.presets.filter { $0.spec.kind == wizard.spec.kind }) { preset in Button(preset.name) { wizard.apply(preset) } }
                if wizard.presets.filter({ $0.spec.kind == wizard.spec.kind }).isEmpty { T("Нет сохранённых пресетов") }
            } label: { TL("Пресеты", systemImage: "slider.horizontal.3") }
            Spacer()
            LB("Сохранить как пресет") { showPreset = true }.popover(isPresented: $showPreset) {
                VStack(alignment: .leading, spacing: 12) {
                    T("Имя пресета").font(.headline)
                    LTextField("Имя пресета", text: $presetName).textFieldStyle(.roundedBorder)
                    LB("Сохранить") { do { try wizard.savePreset(name: presetName); showPreset = false } catch { wizard.error = error.localizedDescription } }.disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(20).frame(width: 280)
            }
        }.controlSize(.small).disabled(wizard.submitting)
    }
    private var general: some View {
        @Bindable var wizard = wizard
        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                T("Основные").font(.headline)
                Picker(selection: $wizard.spec.node) { ForEach(dashboard.availableNodes.isEmpty ? [dashboard.node.id] : dashboard.availableNodes, id: \.self) { Text($0).tag($0) } } label: { T("Нода") }
                HStack { number("VMID", value: $wizard.spec.vmid); LB("Свободный ID") { Task { await wizard.loadCatalog() } }.disabled(wizard.loading) }
                field(wizard.spec.kind == .lxc ? "Hostname" : "Name", text: $wizard.spec.name)
                if wizard.spec.kind == .lxc {
                    Toggle("Unprivileged", isOn: $wizard.spec.unprivileged)
                    Toggle("Nesting", isOn: $wizard.spec.nesting)
                    VStack(alignment: .leading) { T("Пароль root"); SecureField("", text: $wizard.password).textFieldStyle(.roundedBorder) }
                    T("Публичные SSH-ключи").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $wizard.spec.sshPublicKeys).font(.system(.caption, design: .monospaced)).frame(height: 85).border(.primary.opacity(0.1))
                }
            }
        }
    }
    private var operatingSystem: some View {
        @Bindable var wizard = wizard
        return GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                T("Операционная система").font(.headline)
                if wizard.spec.kind == .lxc {
                    Picker(selection: $wizard.spec.template) { Text("—").tag(""); ForEach(wizard.media) { Text($0.volid).tag($0.volid) } } label: { T("Шаблон ОС") }
                    T("Показаны только загруженные vztmpl из доступных хранилищ.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker(selection: $wizard.spec.iso) { T("Без ISO").tag(""); ForEach(wizard.media) { Text($0.volid).tag($0.volid) } } label: { Text("ISO") }
                    Picker(selection: $wizard.spec.osType) { Text("Linux").tag("l26"); Text("Windows 10").tag("win10"); Text("Windows 11").tag("win11"); T("Другая ОС").tag("other") } label: { T("Тип ОС") }
                    Toggle("QEMU Guest Agent", isOn: $wizard.spec.agent)
                }
                LB("Обновить каталог") { Task { await wizard.loadCatalog() } }
            }
        }
    }
    private var resources: some View {
        @Bindable var wizard = wizard
        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                T("Ресурсы").font(.headline)
                Picker(selection: $wizard.spec.storage) { Text("—").tag(""); ForEach(wizard.eligibleStorage) { Text($0.id).tag($0.id) } } label: { T("Хранилище диска") }
                number("Диск · GiB", value: $wizard.spec.diskGB)
                number("CPU cores", value: $wizard.spec.cores)
                number("RAM · MiB", value: $wizard.spec.memoryMB)
                if wizard.spec.kind == .lxc { number("SWAP · MiB", value: $wizard.spec.swapMB) }
                else {
                    number("CPU sockets", value: $wizard.spec.sockets)
                    Picker(selection: $wizard.spec.cpuType) { ForEach(["host", "x86-64-v2-AES", "x86-64-v3", "kvm64"], id: \.self) { Text($0).tag($0) } } label: { T("Тип CPU") }
                    Picker(selection: $wizard.spec.diskBus) { Text("SCSI").tag("scsi"); Text("VirtIO").tag("virtio") } label: { T("Шина диска") }
                    Toggle("Discard / TRIM", isOn: $wizard.spec.discard)
                    Toggle("Ballooning", isOn: $wizard.spec.ballooning)
                    if wizard.spec.ballooning { number("Минимальная RAM · MiB", value: $wizard.spec.balloonMB) }
                }
            }
        }
    }
    private var network: some View {
        @Bindable var wizard = wizard
        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                T("Сеть").font(.headline)
                Picker(selection: $wizard.spec.bridge) { Text("—").tag(""); ForEach(wizard.catalog?.bridges ?? [], id: \.self) { Text($0).tag($0) } } label: { T("Сетевой мост") }
                Toggle("Firewall", isOn: $wizard.spec.firewall)
                if wizard.spec.kind == .lxc {
                    Toggle("DHCP", isOn: $wizard.spec.dhcp)
                    if !wizard.spec.dhcp { field("IPv4 / CIDR", text: $wizard.spec.address); field("Gateway", text: $wizard.spec.gateway) }
                    field("DNS · IPv4", text: $wizard.spec.nameserver)
                    field("DNS search domain", text: $wizard.spec.searchdomain)
                } else { Picker(selection: $wizard.spec.networkModel) { ForEach(["virtio", "e1000", "rtl8139", "vmxnet3"], id: \.self) { Text($0).tag($0) } } label: { T("Модель NIC") } }
            }
        }
    }
    private var review: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                T("Параметры Proxmox API").font(.headline)
                Text("POST /nodes/\(wizard.spec.node)/\(wizard.spec.kind.rawValue)").font(.caption.monospaced()).foregroundStyle(.secondary)
                if let parameters = try? wizard.spec.parameters(password: wizard.password) {
                    ForEach(parameters.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top) { Text(key).foregroundStyle(.secondary).frame(width: 120, alignment: .leading); Text(key == "password" ? "••••••••" : parameters[key] ?? "").textSelection(.enabled) }.font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 6) { T(title); TextField("", text: text).textFieldStyle(.roundedBorder) }.font(.system(size: 12)) }
    private func number(_ title: String, value: Binding<Int>) -> some View { HStack { T(title); Spacer(); TextField("", value: value, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 120) }.font(.system(size: 12)) }
}
