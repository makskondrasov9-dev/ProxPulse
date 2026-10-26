import SwiftUI
import ProxPulseCore
struct MenuBarPopover: View {
    @Environment(\.pulseLanguage) private var language
    @Bindable var model: DashboardModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { T("ProxPulse").font(.system(size: 16, weight: .semibold, design: .rounded)); Spacer(); T(model.sourceLabel).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            Picker(L10n.text("Профиль", language: language), selection: $model.selectedProfile) { T("DEMO (Mock-данные)").tag(DashboardModel.demoID); ForEach(model.profiles) { T($0.name).tag($0.id) } }
            HStack(spacing: 20) {
                ActivityRingView(metrics: [.cpu(model.node.cpu), .ram(model.node.memoryGB / max(1, model.node.maxMemoryGB))], lineWidth: 7, spacing: 5).frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { StatusDot(online: model.node.online); T(model.node.id).fontWeight(.semibold) }
                    T("CPU \(Int(model.node.cpu * 100))% · RAM \(Int(model.node.memoryGB / max(1, model.node.maxMemoryGB) * 100))%").font(.caption).foregroundStyle(.secondary)
                    T("Uptime \(model.node.uptime)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Divider()
            ForEach(model.node.guests) { guest in
                HStack { StatusDot(online: guest.running); Text(guest.name).font(.system(size: 12)); Spacer(); T("\(guest.id)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Button { model.request(guest, action: guest.running ? .shutdown : .start, origin: .menuBar) } label: { Image(systemName: guest.running ? "stop.circle" : "play.circle") }.buttonStyle(.plain).localizedHelp(guest.running ? "Остановить в демо" : "Запустить в демо")
                }
            }
            Divider()
            HStack { LB("Открыть дашборд") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }; Spacer(); Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).localizedHelp("Выйти") }
            Button { model.selectedPage = "Настройки"; openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) } label: { TL("Настройки…", systemImage: "gearshape") }
            T(model.connectionSummary).font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(width: 340)
        .modifier(GuestActionsPresentation(model: model, origin: .menuBar))
    }
}
