import SwiftUI
import ProxPulseCore

struct PendingGuestAction: Identifiable {
    enum Origin { case dashboard, menuBar, inspector }
    var id = UUID()
    var guest: Guest
    var action: ProxmoxAPIService.GuestAction
    var origin: Origin
    var title: String {
        switch action { case .start: "Запустить"; case .reboot: "Перезагрузить"; case .shutdown: "Завершить работу"; case .stop: "Принудительно остановить" }
    }
}
struct GuestActionSheet: View {
    let pending: PendingGuestAction
    let model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: pending.action == .reboot ? "arrow.clockwise.circle" : "power.circle").font(.system(size: 34)).foregroundStyle(.orange)
            T(pending.title).font(.title2.bold())
            Text(pending.guest.name).font(.headline)
            Text("\(pending.guest.node) · \(pending.guest.kind.rawValue.uppercased()) \(pending.guest.id)").font(.caption).foregroundStyle(.secondary)
            T(pending.action == .stop ? "Принудительная остановка может привести к потере несохранённых данных." : "Операция может прервать работу сервисов. Убедитесь, что выбран правильный гость.").foregroundStyle(.secondary)
            HStack {
                LB("Отмена") { model.pendingAction = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                LB("Подтвердить", role: .destructive) { model.pendingAction = nil; model.perform(pending.guest, action: pending.action); dismiss() }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 420)
    }
}
struct GuestActionsPresentation: ViewModifier {
    @Bindable var model: DashboardModel
    var origin: PendingGuestAction.Origin
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { model.pendingAction?.origin == origin ? model.pendingAction : nil }, set: { if $0 == nil && model.pendingAction?.origin == origin { model.pendingAction = nil } })) { GuestActionSheet(pending: $0, model: model).pulseAppearance() }
    }
}
