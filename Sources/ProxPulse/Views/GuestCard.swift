import SwiftUI
import ProxPulseCore
struct GuestCard: View {
    @Environment(\.pulseLanguage) private var language
    @Environment(\.pulseAccent) private var accent
    var guest: Guest
    var model: DashboardModel
    @State private var hovering = false
    @State private var showActions = false
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: guest.kind == .lxc ? "shippingbox" : "desktopcomputer")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(guest.running ? accent.uiColor : .secondary)
                        .frame(width: 37, height: 37).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        T(guest.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        T("\(guest.kind == .lxc ? "CT" : "VM") \(guest.id) · \(guest.role)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    StatusDot(online: guest.running)
                }
                GuestResourcesView(guest: guest)
                if guest.telemetryError != nil { TL("Телеметрия недоступна", systemImage: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(.orange) }

            }
        }
        .overlay(alignment: .topTrailing) { if model.busyGuests.contains(guest.id) { ProgressView().controlSize(.small).padding(15) } }
        .animation(.easeInOut(duration: 0.25), value: guest.running)
        .overlay(alignment: .bottom) {
            if hovering || showActions {
                HStack(spacing: 5) {
                    if !guest.running {
                        action("play.fill", "Запустить") { model.request(guest, action: .start) }
                    } else {
                        action("arrow.clockwise", "Перезагрузить") { model.request(guest, action: .reboot) }
                        action("power", "Завершить работу") { model.request(guest, action: .shutdown) }
                        action("stop.fill", "Принудительно остановить") { model.request(guest, action: .stop) }
                    }
                    action("terminal", "Консоль / SSH") { model.shell(guest) }
                }.padding(6).background(.ultraThinMaterial, in: Capsule()).offset(y: 11).transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { model.inspect(guest) }
        .accessibilityAction(named: Text(L10n.text("Подробнее", language: language))) { model.inspect(guest) }
        .onHover { value in withAnimation(.easeOut(duration: 0.15)) { hovering = value } }
        .contextMenu { GuestContextMenu(guest: guest, model: model) }
        .accessibilityAction(named: Text(L10n.text("Показать действия", language: language))) { showActions.toggle() }
    }
    private func action(_ icon: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { TL(title, systemImage: icon).labelStyle(.iconOnly).font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 5) }
            .buttonStyle(.plain).localizedHelp(title)
            .disabled(model.busyGuests.contains(guest.id) || (!model.isDemo && model.connectionError != nil))
    }
}
