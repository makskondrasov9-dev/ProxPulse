import SwiftUI
import Charts
import ProxPulseCore

struct GuestInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseAccent) private var accent
    @Environment(\.pulseLanguage) private var language
    var model: DashboardModel
    var original: Guest
    private var guest: Guest { model.node.guests.first { MonitoringRules.guestKey($0) == MonitoringRules.guestKey(original) } ?? original }
    private var samples: [GuestSample] { model.samples(for: guest) }
    private var busy: Bool { model.busyGuests.contains(guest.id) }
    private var unavailable: Bool { busy || (!model.isDemo && model.connectionError != nil) }
    private func number(_ value: Double) -> String { TelemetryFormat.number(value, language: language) }
    private var totalRate: Double? {
        guard let rx = guest.receiveBps, let tx = guest.transmitBps else { return nil }
        return rx + tx
    }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kpis
                    actions
                    specifications
                    if let error = guest.telemetryError { T(error).font(.caption).foregroundStyle(.orange) }
                    if guest.kind == .qemu { T("QEMU: SWAP и занятое место внутри ОС могут быть недоступны в status/current. Для IP нужен QEMU Guest Agent.").font(.caption2).foregroundStyle(.secondary) }
                    HStack {
                        T("История ресурсов").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        T(model.isDemo ? "DEMO · пример данных" : "До 120 замеров за текущую сессию").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 2)
                    if samples.count < 2 { T("Графики появятся после двух успешных замеров.").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                        InspectorHistoryChart(title: "CPU", unit: "%", color: accent.uiColor, samples: samples, fixedMaximum: 100) { $0.cpu * 100 }
                        InspectorHistoryChart(title: "RAM", unit: "GB", color: PulseTheme.purple, samples: samples) { $0.memoryGB }
                        InspectorHistoryChart(title: "SWAP", unit: "MB", color: PulseTheme.amber, samples: samples) { $0.swapGB.map { $0 * 1000 } }
                        InspectorHistoryChart(title: "Диск", unit: "GB", color: PulseTheme.amber, samples: samples) { $0.diskGB }
                        InspectorHistoryChart(title: "Входящий трафик", unit: "KB/s", color: .cyan, samples: samples) { $0.receiveBps.map { $0 / 1000 } }
                        InspectorHistoryChart(title: "Исходящий трафик", unit: "KB/s", color: PulseTheme.purple, samples: samples) { $0.transmitBps.map { $0 / 1000 } }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }.frame(width: 880, height: 840)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(alignment: .topTrailing) { RadialGradient(colors: [accent.uiColor.opacity(0.11), .clear], center: .topTrailing, startRadius: 0, endRadius: 520) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.12)))
            .modifier(GuestActionsPresentation(model: model, origin: .inspector))
            .modifier(DestroyPresentation(model: model, origin: .inspector))
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: guest.kind == .lxc ? "shippingbox" : "desktopcomputer")
                .font(.system(size: 25, weight: .light)).foregroundStyle(accent.uiColor)
                .frame(width: 56, height: 56).background(accent.uiColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.uiColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 7) {
                Text(guest.name).font(.system(size: 23, weight: .semibold, design: .rounded)).textSelection(.enabled)
                HStack(spacing: 7) {
                    Text("\(guest.kind == .lxc ? "LXC" : "QEMU") · \(guest.id)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text("· \(guest.node)").font(.system(size: 11)).foregroundStyle(.secondary)
                    StatusDot(online: guest.running)
                    T(guest.running ? "Работает" : "Выключена").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 27, height: 27).background(.primary.opacity(0.05), in: Circle()) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).localizedHelp("Готово")
        }
    }
    private var kpis: some View {
        HStack(spacing: 12) {
            InspectorKPITile(title: "CPU", icon: "cpu", value: "\(Int(guest.cpu * 100))", unit: "%", detail: "\(guest.cpuCount.map(String.init) ?? "—") vCPU", color: accent.uiColor, fraction: guest.cpu)
            InspectorKPITile(title: "RAM", icon: "memorychip", value: number(guest.memoryGB), unit: "GB", detail: "/ \(number(guest.maxMemoryGB)) GB", color: PulseTheme.purple, fraction: guest.memoryGB / max(0.001, guest.maxMemoryGB))
            InspectorKPITile(title: "SWAP", icon: "arrow.left.arrow.right", value: TelemetryFormat.swap(guest.swapGB, language: language), unit: "", detail: "/ " + TelemetryFormat.swap(guest.maxSwapGB, language: language), color: PulseTheme.amber, fraction: (guest.swapGB ?? 0) / max(0.001, guest.maxSwapGB ?? 0), warning: (guest.swapGB ?? 0) > 0)
            InspectorKPITile(title: "Сеть", icon: "network", value: TelemetryFormat.rate(totalRate, language: language), unit: "", detail: "↓ \(TelemetryFormat.rate(guest.receiveBps, language: language)) · ↑ \(TelemetryFormat.rate(guest.transmitBps, language: language))", color: .cyan, fraction: nil)
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            tool(guest.running ? "Завершить работу" : "Запустить", icon: guest.running ? "power" : "play.fill") { model.request(guest, action: guest.running ? .shutdown : .start, origin: .inspector) }
            tool("Перезагрузить", icon: "arrow.clockwise") { model.request(guest, action: .reboot, origin: .inspector) }.disabled(!guest.running)
            Menu {
                LB("Принудительно остановить", role: .destructive) { model.request(guest, action: .stop, origin: .inspector) }.disabled(!guest.running)
                LB("Веб-консоль") { model.webConsole(guest) }
            } label: { Image(systemName: "ellipsis").frame(width: 23, height: 22) }.menuStyle(.borderlessButton).fixedSize()
            Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 22).padding(.horizontal, 3)
            tool("Консоль / SSH", icon: "terminal") { model.shell(guest) }
            Spacer(minLength: 8)
            Button(role: .destructive) { model.pendingDestroy = .init(guest: guest, origin: .inspector) } label: { TL("Удалить", systemImage: "trash").font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7) }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85)).background(.red.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.22)))
        }.padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.09))).disabled(unavailable)
    }
    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { TL(title, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 7) }
            .buttonStyle(.plain).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private var specifications: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                TL(TelemetryFormat.uptime(guest.uptimeSeconds), systemImage: "clock")
                TL(guest.osType ?? "OS —", systemImage: "desktopcomputer")
                TL((guest.diskUsageAvailable == true ? number(guest.diskGB) : "—") + " / " + (guest.maxDiskGB.map(number) ?? "—") + " GB", systemImage: "internaldrive")
            }.font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
            Rectangle().fill(.primary.opacity(0.07)).frame(width: 1, height: 62)
            VStack(alignment: .leading, spacing: 7) {
                T("IP-адреса").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if model.loadingAddresses { ProgressView().controlSize(.small) }
                else if model.guestAddresses.isEmpty { T("IP недоступен").foregroundStyle(.tertiary) }
                else { Text(model.guestAddresses.joined(separator: "  ·  ")).font(.system(size: 11, weight: .medium, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if let error = model.addressError { T(error).font(.caption2).foregroundStyle(.orange).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct InspectorKPITile: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let detail: String
    let color: Color
    var fraction: Double?
    var warning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon).foregroundStyle(color); T(title).foregroundStyle(.secondary); Spacer(); if warning { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(color) } }.font(.system(size: 10, weight: .medium))
            HStack(alignment: .firstTextBaseline, spacing: 3) { Text(value).font(.system(size: 25, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6); Text(unit).font(.system(size: 10)).foregroundStyle(.secondary) }.monospacedDigit()
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.08)).overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing)).frame(width: proxy.size.width * min(1, max(0, fraction ?? 0)))
                }
            }.frame(height: 3).opacity(fraction == nil ? 0 : 1)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .background(warning ? color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(warning ? color.opacity(0.35) : .white.opacity(0.1)))
    }
}

struct InspectorHistoryChart: View {
    let title: String
    let unit: String
    let color: Color
    let samples: [GuestSample]
    var fixedMaximum: Double?
    let value: (GuestSample) -> Double?
    @Environment(\.pulseLanguage) private var language
    @State private var hovered: Date?
    private var selected: GuestSample? {
        guard let hovered else { return nil }
        return samples.filter { value($0) != nil }.min { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); T(title).font(.system(size: 11, weight: .semibold)) }
                Spacer()
                if let sample = selected, let metric = value(sample) { Text(TelemetryFormat.number(metric, language: language) + " " + unit).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(color) }
                else { Text(unit).font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
            chart.frame(height: 110)
        }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.09)))
    }
    private var chart: some View {
        Chart(samples) { sample in
            if let number = value(sample) {
                AreaMark(x: .value("Time", sample.date), yStart: .value("Zero", 0), yEnd: .value(unit, number))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.015)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.date), y: .value(unit, number))
                    .foregroundStyle(color).lineStyle(.init(lineWidth: 1.8)).interpolationMethod(.catmullRom)
            }
            if let selected, selected.id == sample.id, let metric = value(selected) {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(color.opacity(0.4)).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Selected", selected.date), y: .value(unit, metric)).foregroundStyle(color).symbolSize(27)
            }
        }.chartYScale(domain: 0...(fixedMaximum ?? max(0.001, samples.compactMap(value).max() ?? 1) * 1.15))
            .chartXScale(range: .plotDimension(padding: 7))
            .chartXAxis {
                AxisMarks(values: samples.count > 1 ? [samples.first!.date, samples.last!.date] : []) { _ in
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().locale(Locale(identifier: "en_GB")))
                        .foregroundStyle(.secondary.opacity(0.55)).font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.4)).foregroundStyle(.primary.opacity(0.04))
                    AxisValueLabel().font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let frame = geometry[plot]
                            guard frame.contains(location) else { hovered = nil; return }
                            hovered = proxy.value(atX: location.x - frame.minX, as: Date.self)
                            #if DEBUG
                            InspectorHoverProbe.selected = hovered != nil
                            #endif
                        case .ended: hovered = nil
                        }
                    }
                }
            }
            .accessibilityLabel(Text(L10n.text(title, language: language)))
    }
}
