import SwiftUI
import ProxPulseCore

enum WorkspaceViewMode: String, CaseIterable { case grid, rack, topology
    var title: String { switch self { case .grid: "Сетка"; case .rack: "Стойка"; case .topology: "Карта" } }
    var icon: String { switch self { case .grid: "square.grid.2x2"; case .rack: "server.rack"; case .topology: "point.3.connected.trianglepath.dotted" } }
}
struct PendingDestroy: Identifiable {
    var id = UUID()
    var guest: Guest
    var origin: PendingGuestAction.Origin
}
struct GuestContextMenu: View {
    let guest: Guest
    var model: DashboardModel
    var origin: PendingGuestAction.Origin = .dashboard
    private var unavailable: Bool { model.busyGuests.contains(guest.id) || (!model.isDemo && model.connectionError != nil) }
    var body: some View {
        LB("Подробнее") { model.inspect(guest) }
        Divider()
        LB("Запустить") { model.request(guest, action: .start, origin: origin) }.disabled(guest.running || unavailable)
        LB("Перезагрузить") { model.request(guest, action: .reboot, origin: origin) }.disabled(!guest.running || unavailable)
        LB("Завершить работу") { model.request(guest, action: .shutdown, origin: origin) }.disabled(!guest.running || unavailable)
        LB("Принудительно остановить", role: .destructive) { model.request(guest, action: .stop, origin: origin) }.disabled(!guest.running || unavailable)
        Divider()
        LB("Консоль / SSH") { model.shell(guest) }
        LB("Веб-консоль") { model.webConsole(guest) }
        LB("Диагностика") { model.diagnosticGuest = guest }
        Divider()
        LB("Удалить", role: .destructive) { model.pendingDestroy = PendingDestroy(guest: guest, origin: origin) }.disabled(unavailable)
    }
}
struct GuestQuickActions: View {
    let guest: Guest
    var model: DashboardModel
    var body: some View {
        HStack(spacing: 8) {
            Button { model.request(guest, action: guest.running ? .stop : .start) } label: { Image(systemName: guest.running ? "stop.fill" : "play.fill") }.localizedHelp(guest.running ? "Принудительно остановить" : "Запустить")
            Button { model.shell(guest) } label: { Image(systemName: "terminal") }.localizedHelp("Консоль / SSH")
        }.buttonStyle(.borderless).controlSize(.small)
            .disabled(model.busyGuests.contains(guest.id) || (!model.isDemo && model.connectionError != nil))
    }
}
struct DestroyGuardSheet: View {
    @Environment(\.dismiss) private var dismiss
    var pending: PendingDestroy
    var model: DashboardModel
    @State private var confirmation = ""
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private var current: Guest { model.node.guests.first { $0.id == pending.guest.id && $0.node == pending.guest.node } ?? pending.guest }
    private var valid: Bool { DestroyGuard.matches(confirmation, guest: current) && !current.running && !submitting }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill").font(.title).foregroundStyle(.red).frame(width: 56, height: 56).background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) { T("Удаление машины").font(.title2.bold()); Text("\(current.kind.rawValue.uppercased()) \(current.id) · \(current.name)").foregroundStyle(.secondary) }
            }
            T("Будут удалены конфигурация и диски машины. Proxmox выполнит purge=1. Действие необратимо.").foregroundStyle(.secondary)
            if current.running { TL("Сначала остановите машину.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            T("Введите точный VMID или имя машины.").font(.headline)
            TextField("\(current.id) / \(current.name)", text: $confirmation).textFieldStyle(.roundedBorder).controlSize(.large).focused($focused).disabled(submitting)
            if let error { T(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if submitting { HStack { ProgressView().controlSize(.small); T("Ожидание завершения задачи Proxmox…") } }
            HStack {
                LB("Отмена") { dismiss() }.keyboardShortcut(.cancelAction).disabled(submitting)
                Spacer()
                LB("Уничтожить", role: .destructive) {
                    submitting = true; error = nil
                    Task {
                        do { try await model.destroy(current, confirmation: confirmation); dismiss() }
                        catch { self.error = error.localizedDescription; submitting = false }
                    }
                }.buttonStyle(.borderedProminent).tint(.red).disabled(!valid)
            }
        }.padding(28).frame(width: 550).interactiveDismissDisabled(submitting).onAppear { focused = true }
    }
}
struct DestroyPresentation: ViewModifier {
    @Bindable var model: DashboardModel
    var origin: PendingGuestAction.Origin
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { model.pendingDestroy?.origin == origin ? model.pendingDestroy : nil }, set: { if $0 == nil && model.pendingDestroy?.origin == origin { model.pendingDestroy = nil } })) { DestroyGuardSheet(pending: $0, model: model).pulseAppearance() }
    }
}
