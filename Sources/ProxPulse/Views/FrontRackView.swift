import SwiftUI
import ProxPulseCore

struct NetworkActivityLED: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var rate: Double?
    var title: String
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || (rate ?? 0) <= 0)) { time in
            let frequency = TrafficAnimation.frequency(bytesPerSecond: rate ?? 0)
            let lit = frequency > 0 && (reduceMotion || sin(time.date.timeIntervalSinceReferenceDate * frequency * 2 * .pi) > -0.15)
            HStack(spacing: 4) { Circle().fill(lit ? color : color.opacity(0.12)).frame(width: 5, height: 5).shadow(color: lit ? color.opacity(0.7) : .clear, radius: 4); Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.gray) }
        }.help(title + " " + TelemetryFormat.rate(rate))
    }
}
struct FrontRackView: View {
    var model: DashboardModel
    var body: some View {
        VStack(spacing: 4) {
            HStack { Image(systemName: "server.rack"); Text("PROXPULSE / VIRTUAL RACK").tracking(2); Spacer(); Text("19″ · \(model.filteredGuests.reduce(0) { $0 + ($1.kind == .lxc ? 1 : 2) })U") }.font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.gray).padding(18)
            ForEach(Array(model.filteredGuests.enumerated()), id: \.element.id) { index, guest in
                let unit = 1 + model.filteredGuests.prefix(index).reduce(0) { $0 + ($1.kind == .lxc ? 1 : 2) }
                RackBladeView(guest: guest, model: model, firstUnit: unit)
            }
            HStack { ForEach(0..<24, id: \.self) { _ in Capsule().fill(.white.opacity(0.055)).frame(height: 3) } }.padding(18)
        }.padding(8).background(Color(red: 0.045, green: 0.05, blue: 0.065), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)))
    }
}
private struct RackBladeView: View {
    var guest: Guest
    var model: DashboardModel
    var firstUnit: Int
    @State private var hovering = false
    private var units: Int { guest.kind == .lxc ? 1 : 2 }
    var body: some View {
        HStack(spacing: 0) {
            rail(numbers: true)
            HStack(spacing: 14) {
                HStack(spacing: 3) { ForEach(0..<7, id: \.self) { _ in Capsule().fill(.black.opacity(0.5)).frame(width: 2, height: 25) } }.padding(.leading, 4)
                StatusDot(online: guest.running)
                VStack(alignment: .leading, spacing: 5) {
                    Text(guest.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("\(guest.kind == .lxc ? "CT" : "VM") \(guest.id) · \(guest.osType ?? "OS —")").font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray).lineLimit(1)
                    if units == 2 { Text(guest.node).font(.system(size: 9)).foregroundStyle(.gray) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                oled("CPU", value: "\(Int(guest.cpu * 100))%", fraction: guest.cpu, color: .cyan)
                oled("RAM", value: "\(Int(guest.memoryGB / max(0.001, guest.maxMemoryGB) * 100))%", fraction: guest.memoryGB / max(0.001, guest.maxMemoryGB), color: .purple)
                VStack(spacing: 9) { NetworkActivityLED(rate: guest.receiveBps, title: "RX", color: .green); NetworkActivityLED(rate: guest.transmitBps, title: "TX", color: .cyan) }
            }.padding(.horizontal, 13).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.085)], startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().stroke(.white.opacity(hovering ? 0.22 : 0.05), lineWidth: 0.7))
            rail(numbers: false)
        }.frame(height: CGFloat(units) * 68)
        .contentShape(Rectangle()).onTapGesture { model.inspect(guest) }
        .contextMenu { GuestContextMenu(guest: guest, model: model) }
        .overlay(alignment: .bottomTrailing) { if hovering { GuestQuickActions(guest: guest, model: model).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.trailing, 45).offset(y: 6) } }
        .overlay(alignment: .topTrailing) { if model.busyGuests.contains(guest.id) { ProgressView().controlSize(.small).padding(8) } }
        .onHover { value in withAnimation(.easeInOut(duration: 0.15)) { hovering = value } }
        .accessibilityElement(children: .combine).accessibilityLabel("\(guest.name), \(guest.id), \(units)U, CPU \(Int(guest.cpu * 100))%")
        .accessibilityAction { model.inspect(guest) }
    }
    private func rail(numbers: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<units, id: \.self) { index in
                VStack(spacing: 5) { Circle().fill(.black).overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1)).frame(width: 6, height: 6); if numbers { Text("\(firstUnit + index)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.gray) }; Circle().fill(.black).frame(width: 4, height: 4) }.frame(maxHeight: .infinity)
            }
        }.frame(width: 32).background(LinearGradient(colors: [Color(white: 0.09), Color(white: 0.16), Color(white: 0.08)], startPoint: .leading, endPoint: .trailing))
    }
    private func oled(_ title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.system(size: 7)); Spacer(); Text(value).font(.system(size: 11, weight: .semibold)) }
            GeometryReader { geometry in Capsule().fill(color.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction))) } }.frame(height: 2)
        }.fontDesign(.monospaced).foregroundStyle(color.opacity(0.9)).padding(8).frame(width: 69).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.12)))
    }
}
