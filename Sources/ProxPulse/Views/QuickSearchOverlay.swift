import SwiftUI
import ProxPulseCore

struct QuickSearchOverlay: View {
    @Bindable var model: DashboardModel
    @State private var query = ""
    @FocusState private var focused: Bool
    private var results: [Guest] { model.node.guests.filter { model.matches($0, query: query) }.sorted { $0.id < $1.id } }
    private func perform(_ action: () -> Void) { model.quickSearchPresented = false; action() }
    private func resultRow(_ guest: Guest) -> some View {
        HStack(spacing: 12) {
            Button { perform { model.inspect(guest) } } label: {
                HStack(spacing: 10) {
                    StatusDot(online: guest.running)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(guest.name).font(.system(size: 13, weight: .semibold))
                        Text("\(guest.kind == .lxc ? "CT" : "VM") \(guest.id) · \(model.addresses(for: guest).joined(separator: ", "))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { perform { model.shell(guest) } } label: { Image(systemName: "terminal") }.localizedHelp("Консоль / SSH")
            Button { perform { model.inspect(guest) } } label: { Image(systemName: "info.circle") }.localizedHelp("Инспектор")
            Button { perform { model.request(guest, action: guest.running ? .reboot : .start) } } label: { Image(systemName: guest.running ? "arrow.clockwise" : "play.fill") }.localizedHelp(guest.running ? "Перезагрузить" : "Запустить")
                .disabled(model.busyGuests.contains(guest.id) || (!model.isDemo && (!model.hasSnapshot || model.connectionError != nil)))
        }.buttonStyle(.borderless).padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28).contentShape(Rectangle()).onTapGesture { model.quickSearchPresented = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    LTextField("Поиск машины, IP или действия…", text: $query).textFieldStyle(.plain).font(.title3).focused($focused)
                        .onSubmit { if let guest = results.first { perform { model.inspect(guest) } } }
                    Text("esc").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }.padding(20)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(results, id: \.id) { guest in
                            resultRow(guest)
                        }
                        if results.isEmpty { T("Ничего не найдено").foregroundStyle(.secondary).padding(40) }
                    }.padding(12)
                }.frame(maxHeight: 370)
            }.frame(width: 650).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.13))).shadow(color: .black.opacity(0.3), radius: 35, y: 15).padding(.top, 90)
        }.onAppear { focused = true }.onExitCommand { model.quickSearchPresented = false }
    }
}
