import SwiftUI
import ProxPulseCore

private struct TopologyNodeSizeKey: SwiftUI.PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct TopologyViewportHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 620 }
extension EnvironmentValues {
    var topologyViewportHeight: CGFloat {
        get { self[TopologyViewportHeightKey.self] }
        set { self[TopologyViewportHeightKey.self] = newValue }
    }
}

private struct TopologyLink: Identifiable, Equatable {
    var id: String
    var start: CGPoint
    var end: CGPoint
    var receive: Double?
    var transmit: Double?
    var tunnel = false
    var active = true
    // Guest links end at the guest; bridge/tunnel counters belong to the source node.
    var receiveTowardEnd = true
    func point(_ t: Double) -> CGPoint {
        TopologyTrafficBadge.curvePoint(start: start, end: end, t: CGFloat(t))
    }

    var path: Path {
        Path { p in
            p.move(to: start)
            p.addCurve(to: end, control1: CGPoint(x: (start.x + end.x)/2, y: start.y), control2: CGPoint(x: (start.x + end.x)/2, y: end.y))
        }
    }
}

/// Only this layer redraws per display frame. Cards, labels and layout are outside TimelineView.
private struct TopologyFlowCanvas: View {
    let links: [TopologyLink]
    var drawingOrigin: CGPoint = .zero
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phases: [String: TrafficPhase] = [:]
    var body: some View {
        // Read State in the view body so the first phase update invalidates Canvas.
        let currentPhases = phases
        return TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas(rendersAsynchronously: true) { graphics, _ in
                graphics.translateBy(x: -drawingOrigin.x, y: -drawingOrigin.y)
                let now = context.date.timeIntervalSinceReferenceDate
                #if DEBUG
                let renderStart = Date().timeIntervalSinceReferenceDate
                defer { TopologyFrameProbe.shared.record(time: now, duration: Date().timeIntervalSinceReferenceDate - renderStart) }
                #endif
                for link in links {
                    let hue: Color = link.tunnel ? .purple : color
                    let opacity = !link.active ? 0.12 : link.tunnel && !reduceMotion ? 0.44 + 0.12 * sin(now * 2) : 0.35
                    graphics.stroke(link.path, with: .color(hue.opacity(opacity)), style: StrokeStyle(lineWidth: 1.4, dash: link.tunnel ? [5, 5] : []))
                    guard !reduceMotion, link.active else { continue }
                    for (direction, rate, reverse) in [("rx", link.receive, false), ("tx", link.transmit, true)] {
                        guard let rate, rate > 0, let phase = currentPhases[link.id + direction] else { continue }
                        for index in 0..<4 {
                            var t = phase.position(at: now, particleOffset: Double(index) / 4)
                            if reverse == link.receiveTowardEnd { t = 1 - t }
                            let point = link.point(t)
                            let particle = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
                            graphics.fill(Path(ellipseIn: particle.insetBy(dx: -3, dy: -3)), with: .color((reverse ? Color.purple : Color.cyan).opacity(0.09)))
                            graphics.fill(Path(ellipseIn: particle), with: .color(reverse ? .purple : .cyan))
                        }
                    }
                }
            }
        }.onAppear { updatePhases() }.onChange(of: links) { _, _ in updatePhases() }
    }
    private func updatePhases() {
        let time = Date().timeIntervalSinceReferenceDate
        var next: [String: TrafficPhase] = [:]
        for link in links {
            for (direction, rate) in [("rx", link.receive), ("tx", link.transmit)] {
                let key = link.id + direction, speed = TrafficAnimation.frequency(bytesPerSecond: rate ?? 0) * 0.075
                var phase = phases[key] ?? TrafficPhase(speed: speed, time: time)
                phase.update(speed: speed, time: time); next[key] = phase
            }
        }
        phases = next
    }
}

struct TopologyCanvasView: View {
    var model: DashboardModel
    @Environment(\.pulseAccent) private var accent
    @Environment(\.pulseLanguage) private var language
    @Environment(\.topologyViewportHeight) private var viewportHeight
    @AppStorage("pulse.topologyLineSpeeds") private var showSpeeds = true
    @State private var statusFilter = "Все"
    @State private var zoom: CGFloat = 1
    @AppStorage("pulse.topologyLayout.centered.v2") private var layoutData = Data()
    @AppStorage("pulse.topologyLayout.v1") private var legacyLayoutData = Data()
    @State private var positions: [String: CanvasPosition] = [:]
    @State private var nodeSizes: [String: CGSize] = [:]
    @State private var nodeDrag: (id: String, origin: CGPoint)?
    @State private var viewportSize: CGSize = .zero
    @State private var cameraCenter: CGPoint = .zero
    @State private var pan: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    private var allGuests: [Guest] { model.node.guests.filter { $0.node == model.node.id } }
    private var guests: [Guest] { allGuests.filter { statusFilter == "Все" || ($0.running ? statusFilter == "Работают" : statusFilter == "Выключены") } }
    private var visibleIndices: [Int] { ordered.indices.filter { index in guests.contains { $0.id == ordered[index].id } } }
    private var tunnels: [NodeNetworkInterface] { model.networkInterfaces.filter(\.isTunnel) }
    private var bridges: [String] {
        Array(Set(model.networkInterfaces.filter(\.isBridge).map(\.iface) + allGuests.flatMap { $0.bridges?.isEmpty == false ? $0.bridges! : ["?"] })).sorted()
    }
    private var ordered: [Guest] { bridges.flatMap { bridge in allGuests.filter { ($0.bridges?.first ?? "?") == bridge } } }
    private var columns: Int { allGuests.count > 4 ? 2 : 1 }
    private var rows: Int { max(1, (allGuests.count + columns - 1) / columns) }
    private var height: CGFloat { max(640, max(CGFloat(rows) * 152 + 200, CGFloat(bridges.count) * 110 + 210)) }
    private var width: CGFloat { max(columns == 1 ? 1060 : 1410, 360 + CGFloat(tunnels.count) * 310) }
    private var sceneSize: CGSize { CGSize(width: width, height: height) }
    private var layoutID: String { model.selectedProfile.uuidString + model.node.id + ordered.map { String($0.id) }.joined(separator: ",") + bridges.joined() + tunnels.map(\.iface).joined() }
    private var scope: String { model.selectedProfile.uuidString + "/" + model.node.id }
    private var hostID: String { "host/" + model.node.id }
    private func guestID(_ guest: Guest) -> String { "guest/" + guest.kind.rawValue + "/" + String(guest.id) }
    private func bridgeID(_ bridge: String) -> String { "bridge/" + bridge }
    private func tunnelID(_ tunnel: String) -> String { "tunnel/" + tunnel }
    private func position(_ id: String, fallback: CGPoint) -> CGPoint { positions[id].map { CGPoint(x: $0.x + width/2, y: $0.y + height/2) } ?? fallback }
    private var hostPoint: CGPoint { position(hostID, fallback: CGPoint(x: 135, y: (height - 160) / 2)) }
    private func guestPoint(_ index: Int) -> CGPoint { position(guestID(ordered[index]), fallback: CGPoint(x: 855 + CGFloat(index / rows) * 345, y: 100 + CGFloat(index % rows) * 152)) }
    private func bridgePoint(_ bridge: String) -> CGPoint {
        let index = CGFloat(bridges.firstIndex(of: bridge) ?? 0)
        let count = CGFloat(max(1, bridges.count))
        let y: CGFloat = 65 + (index + 0.5) * ((height - 240) / count)
        return position(bridgeID(bridge), fallback: CGPoint(x: 480, y: y))
    }
    private func tunnelPoint(_ index: Int) -> CGPoint { position(tunnelID(tunnels[index].iface), fallback: CGPoint(x: 440 + CGFloat(index) * 310, y: height - 65)) }
    private func measurement(_ iface: String) -> TunnelMeasurement? {
        guard let value = model.tunnelMeasurements[iface], Date().timeIntervalSince(value.measuredAt) <= 45 else { return nil }
        return value
    }
    private func sum(_ members: [Guest], receive: Bool) -> Double? {
        let rates = members.compactMap { receive ? $0.receiveBps : $0.transmitBps }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
    private var links: [TopologyLink] {
        var result = bridges.map { bridge in
            let members = guests.filter { ($0.bridges?.first ?? "?") == bridge }, metrics = measurement(bridge)
            let point = bridgePoint(bridge)
            return TopologyLink(id: "bridge/" + bridge, start: CGPoint(x: hostPoint.x + 82, y: hostPoint.y), end: CGPoint(x: point.x - 55, y: point.y), receive: metrics?.receiveBps ?? sum(members, receive: true), transmit: metrics?.transmitBps ?? sum(members, receive: false), receiveTowardEnd: false)
        }
        for index in visibleIndices {
            let guest = ordered[index], point = guestPoint(index)
            for (nic, bridge) in (guest.bridges?.isEmpty == false ? guest.bridges! : ["?"]).enumerated() {
                let start = bridgePoint(bridge)
                result.append(.init(id: "guest/\(guest.id)/\(bridge)", start: CGPoint(x: start.x + 55, y: start.y), end: CGPoint(x: point.x - 147, y: point.y), receive: nic == 0 ? guest.receiveBps : nil, transmit: nic == 0 ? guest.transmitBps : nil, active: guest.running))
            }
        }
        for (index, tunnel) in tunnels.enumerated() {
            let metrics = measurement(tunnel.iface), point = tunnelPoint(index)
            result.append(.init(id: "tunnel/" + tunnel.iface, start: CGPoint(x: hostPoint.x + 50, y: hostPoint.y + 80), end: CGPoint(x: point.x, y: point.y - 52), receive: metrics?.ratesAvailable == false ? nil : metrics?.receiveBps, transmit: metrics?.ratesAvailable == false ? nil : metrics?.transmitBps, tunnel: true, active: tunnel.active != 0, receiveTowardEnd: false))
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls
            GeometryReader { viewport in
                scene(viewport: viewport.size, origin: viewport.frame(in: .global).origin)
                    .environment(\.colorScheme, .dark)
                    .onAppear { loadLayout(); viewportSize = viewport.size; recenter(viewport.size) }
                    .onChange(of: scope) { _, _ in loadLayout(); recenter(viewport.size) }
                    .onChange(of: viewport.size) { _, size in withAnimation(.spring(response: 0.45, dampingFraction: 1)) { viewportSize = size; recenter(size) } }
                    .onChange(of: statusFilter) { _, _ in pan = clamped(pan, viewport: viewport.size) }
                    .onChange(of: layoutID) { _, _ in withAnimation(.spring(response: 0.45, dampingFraction: 1)) { recenter(viewport.size) } }
                    .onPreferenceChange(TopologyNodeSizeKey.self) { sizes in
                        Task { @MainActor in
                            if nodeSizes != sizes { nodeSizes = sizes; pan = clamped(pan, viewport: viewportSize) }
                        }
                    }
                    .onChange(of: layoutData) { _, _ in if nodeDrag == nil { loadLayout() } }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 8) {
                        Button { withAnimation(.spring(response: 0.45, dampingFraction: 1)) { resetLayout(); recenter(viewport.size) } } label: { TL("Сбросить расстановку", systemImage: "arrow.triangle.branch").font(.caption) }
                        Button { setZoom(effectiveScale * 1.2) } label: { Image(systemName: "plus") }.localizedHelp("Приблизить")
                        Button { setZoom(effectiveScale / 1.2) } label: { Image(systemName: "minus") }.localizedHelp("Отдалить")
                        Button("100%") { setZoom(1) }.localizedHelp("Масштаб 100%")
                        Button { withAnimation(.spring(response: 0.45, dampingFraction: 1)) { recenter(viewport.size) } } label: { TL("По размеру", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption) }
                        Button { withAnimation(.spring(response: 0.45, dampingFraction: 1)) { recenter(viewport.size) } } label: { TL("В центр", systemImage: "scope").font(.caption) }
                        }.buttonStyle(.plain).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(12)
                    }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            T("Мосты: сумма трафика машин. VPN: ping с этого Mac. Скорость туннеля недоступна без счётчиков.").font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(height: max(280, viewportHeight))
        .task(id: model.selectedProfile.uuidString + "/" + model.node.id) {
            while !Task.isCancelled {
                await model.refreshTopology()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }
    private var controls: some View {
        HStack(spacing: 18) {
            Picker(L10n.text("Статус", language: language), selection: $statusFilter) {
                T("Все").tag("Все"); T("Работают").tag("Работают"); T("Выключены").tag("Выключены")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
            Toggle(isOn: $showSpeeds) { T("Скорость на линиях").font(.caption) }.toggleStyle(.switch).controlSize(.small)
            if model.loadingTopology { ProgressView().controlSize(.small) }
            Spacer()
            Button { Task { await model.refreshTopology() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
        }
    }
    private struct NodeFrame {
        var id: String; var center: CGPoint; var size: CGSize
        var rect: CGRect { CGRect(x: center.x-size.width/2, y: center.y-size.height/2, width: size.width, height: size.height) }
    }
    private var nodeFrames: [NodeFrame] {
        var result = [NodeFrame(id: hostID, center: hostPoint, size: nodeSizes[hostID] ?? CGSize(width: 166, height: 190))]
        result += bridges.map { NodeFrame(id: bridgeID($0), center: bridgePoint($0), size: nodeSizes[bridgeID($0)] ?? CGSize(width: 110, height: 70)) }
        result += visibleIndices.map { NodeFrame(id: guestID(ordered[$0]), center: guestPoint($0), size: nodeSizes[guestID(ordered[$0])] ?? CGSize(width: 294, height: 112)) }
        result += tunnels.indices.map { NodeFrame(id: tunnelID(tunnels[$0].iface), center: tunnelPoint($0), size: nodeSizes[tunnelID(tunnels[$0].iface)] ?? CGSize(width: 270, height: 112)) }
        return result
    }
    private var contentBounds: CGRect { TopologyCamera.bounds(nodeFrames.map(\.rect)) }
    private var effectiveScale: CGFloat {
        min(3, max(0.05, zoom * magnification))
    }
    private func clamped(_ proposed: CGSize, viewport: CGSize) -> CGSize {
        let bounds = contentBounds
        let dx = (bounds.midX - cameraCenter.x) * effectiveScale
        let dy = (bounds.midY - cameraCenter.y) * effectiveScale
        let centered = CGSize(width: proposed.width + dx, height: proposed.height + dy)
        let limited = TopologyCamera.navigationClamp(centered, bounds: bounds, viewport: viewport, scale: effectiveScale)
        return CGSize(width: limited.width - dx, height: limited.height - dy)
    }
    private func recenter(_ size: CGSize) {
        let bounds = contentBounds
        cameraCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        zoom = TopologyCamera.fit(bounds: bounds, viewport: size); pan = .zero
    }
    private func setZoom(_ requested: CGFloat, anchor: CGPoint? = nil, animated: Bool = true) {
        let next = min(3, max(0.05, requested))
        let point = anchor ?? CGPoint(x: viewportSize.width/2, y: viewportSize.height/2)
        let oldPan = clamped(pan, viewport: viewportSize)
        let anchored = TopologyCamera.anchoredPan(anchor: point, viewport: viewportSize, pan: oldPan, oldScale: effectiveScale, newScale: next)
        let update = { zoom = next; pan = clamped(anchored, viewport: viewportSize) }
        if animated { withAnimation(.spring(response: 0.3, dampingFraction: 0.9), update) } else { update() }
    }
    private func loadLayout() {
        let archive = TopologyLayoutArchive(data: layoutData)
        if archive.scopes[scope] != nil { positions = archive.positions(in: scope) }
        else {
            positions = TopologyLayoutArchive(data: legacyLayoutData).positions(in: scope).mapValues { CanvasPosition(x: $0.x - width/2, y: $0.y - height/2) }
            if !positions.isEmpty { saveLayout() }
        }
    }
    private func saveLayout() {
        var archive = TopologyLayoutArchive(data: layoutData); archive.save(positions, in: scope); layoutData = archive.data
    }
    private func resetLayout() {
        positions = [:]; nodeDrag = nil
        var archive = TopologyLayoutArchive(data: layoutData); archive.save([:], in: scope); layoutData = archive.data
    }
    private func nodeGesture(_ id: String, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("topologyViewport")).onChanged { value in
            if nodeDrag?.id != id { nodeDrag = (id, center) }
            guard let origin = nodeDrag?.origin else { return }
            let proposed = CGPoint(x: origin.x + value.translation.width/effectiveScale, y: origin.y + value.translation.height/effectiveScale)
            let size = nodeFrames.first { $0.id == id }?.size ?? .zero
            let offset = clamped(pan, viewport: viewportSize)
            let limited = TopologyCamera.nodePosition(proposed, size: size, viewport: viewportSize, center: cameraCenter, pan: offset, scale: effectiveScale)
            positions[id] = CanvasPosition(x: limited.x - width/2, y: limited.y - height/2)
        }.onEnded { _ in saveLayout(); nodeDrag = nil; pan = clamped(pan, viewport: viewportSize) }
    }
    private func movable<Content: View>(_ content: Content, id: String, center: CGPoint) -> some View {
        content.background(GeometryReader { proxy in Color.clear.preference(key: TopologyNodeSizeKey.self, value: [id: proxy.size]) })
            .contentShape(Rectangle())
            .highPriorityGesture(nodeGesture(id, center: center))
            .accessibilityIdentifier("topology-node-" + id)
            .position(center)
    }
    private func scene(viewport: CGSize, origin: CGPoint) -> some View {
        let graphLinks = links
        #if DEBUG
        let _ = { TopologyInteractionProbe.shared.zoomTo = { setZoom($0, anchor: $1, animated: false) }; TopologyInteractionProbe.shared.filter = { statusFilter = $0 } }()
        #endif
        let offset = clamped(CGSize(width: pan.width + dragging.width, height: pan.height + dragging.height), viewport: viewport)
        #if DEBUG
        let _ = TopologyInteractionProbe.shared.record(viewport: viewport, origin: origin, bounds: contentBounds, scale: effectiveScale, pan: offset, cameraCenter: cameraCenter, nodes: nodeFrames.map { ($0.id, $0.center, $0.size) }, badgeCount: showSpeeds ? speedLabels(graphLinks).count : 0, positions: positions, scope: scope, reset: { resetLayout(); recenter(viewport) }, recenter: { recenter(viewport) })
        #endif
        return ZStack {
            Color(red: 0.035, green: 0.05, blue: 0.075)
            Canvas { context, size in
                let step: CGFloat = 26
                let dx = (pan.width + dragging.width).truncatingRemainder(dividingBy: step)
                let dy = (pan.height + dragging.height).truncatingRemainder(dividingBy: step)
                for x in stride(from: dx, to: size.width, by: step) {
                    for y in stride(from: dy, to: size.height, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.09)))
                    }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture().updating($dragging) { value, state, _ in state = value.translation }.onEnded { value in
                    pan = clamped(CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height), viewport: viewport)
                })
            diagram(links: graphLinks).frame(width: width, height: height)
                .offset(x: width/2 - cameraCenter.x, y: height/2 - cameraCenter.y)
                .scaleEffect(effectiveScale)
                .position(x: viewport.width / 2 + offset.width, y: viewport.height / 2 + offset.height)
        }.frame(width: viewport.width, height: viewport.height).clipped().contentShape(Rectangle()).coordinateSpace(name: "topologyViewport")
            .overlay { CanvasScrollZoom { delta, location in setZoom(effectiveScale * exp(delta), anchor: location, animated: false) }.allowsHitTesting(false) }
            .animation(.easeInOut(duration: 0.22), value: statusFilter)
            .simultaneousGesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { zoom = min(3, max(0.05, zoom * $0)); pan = clamped(pan, viewport: viewport) })
    }
    private func diagram(links: [TopologyLink]) -> some View {
        ZStack(alignment: .topLeading) {
            let drawingBounds = contentBounds.insetBy(dx: -100, dy: -100)
            TopologyFlowCanvas(links: links, drawingOrigin: drawingBounds.origin, color: accent.uiColor).id(statusFilter).transition(.opacity)
                .frame(width: drawingBounds.width, height: drawingBounds.height)
                .position(x: drawingBounds.midX, y: drawingBounds.midY).allowsHitTesting(false)
            if showSpeeds {
                ForEach(speedLabels(links)) { label in
                    trafficPill(label.link).position(label.position).allowsHitTesting(false)
                }
            }
            movable(host, id: hostID, center: hostPoint)
            ForEach(bridges, id: \.self) { bridge in movable(bridgeNode(bridge), id: bridgeID(bridge), center: bridgePoint(bridge)) }
            ForEach(visibleIndices, id: \.self) { index in movable(guestNode(ordered[index]), id: guestID(ordered[index]), center: guestPoint(index)).transition(.opacity) }
            ForEach(Array(tunnels.enumerated()), id: \.element.iface) { index, tunnel in movable(tunnelNode(tunnel), id: tunnelID(tunnel.iface), center: tunnelPoint(index)) }
        }
    }
    private struct SpeedLabel: Identifiable {
        let link: TopologyLink
        let position: CGPoint
        var id: String { link.id }
    }
    private func speedLabels(_ links: [TopologyLink]) -> [SpeedLabel] {
        links.filter { TopologyTrafficBadge.isVisible(receive: $0.receive, transmit: $0.transmit) }
            .map { SpeedLabel(link: $0, position: $0.point(0.5)) }
    }
    private func trafficPill(_ link: TopologyLink) -> some View {
        HStack(spacing: 6) {
            Text("↓ " + TelemetryFormat.rate(link.receive, language: language)).foregroundStyle(.cyan)
            Text("↑ " + TelemetryFormat.rate(link.transmit, language: language)).foregroundStyle(.purple)
        }.font(.system(size: 8, weight: .medium, design: .monospaced)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 3).fixedSize()
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08))).help(link.id)
    }
    private func bridgeNode(_ bridge: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted").foregroundStyle(accent.uiColor)
            Text(bridge).font(.system(.caption, design: .monospaced).bold())
        }.padding(13).frame(width: 110).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.uiColor.opacity(0.3)))
    }
    private var host: some View {
        VStack(spacing: 12) {
            ZStack {
                ActivityRingView(metrics: [.cpu(model.node.cpu), .ram(model.node.memoryGB / max(1, model.node.maxMemoryGB)), .disk(model.node.storage.fraction)], lineWidth: 5, spacing: 4).frame(width: 85, height: 85)
                Image(systemName: "server.rack").font(.title3).foregroundStyle(.white)
            }
            HStack { StatusDot(online: model.node.online && model.connectionError == nil); Text(model.node.id).font(.system(.caption, design: .monospaced).bold()).foregroundStyle(.white) }
            Text(model.isDemo ? "PROXMOX · DEMO" : "PROXMOX · LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
        }.padding(18).frame(width: 166).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private func guestNode(_ guest: Guest) -> some View {
        let key = MonitoringRules.guestKey(guest)
        let addresses = model.topologyGuestAddresses[key] ?? []
        return Button { model.inspect(guest) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: guest.kind == .lxc ? "shippingbox" : "desktopcomputer").foregroundStyle(accent.uiColor)
                    Text(guest.name).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: 0)
                    if model.busyGuests.contains(guest.id) { ProgressView().controlSize(.mini) } else { StatusDot(online: guest.running) }
                }.font(.system(size: 12))
                HStack { Text("\(guest.kind == .lxc ? "CT" : "VM") \(guest.id)").foregroundStyle(.secondary); Text(addresses.first ?? "IP —").foregroundStyle(accent.uiColor).lineLimit(1) }.font(.system(size: 10, design: .monospaced))
                HStack { Text("CPU \(Int(guest.cpu * 100))% · \(guest.cpuCount.map(String.init) ?? "—") vCPU"); Spacer(); Text("RAM \(guest.memoryGB.formatted(.number.precision(.fractionLength(1)))) / \(guest.maxMemoryGB.formatted(.number.precision(.fractionLength(1)))) GB") }.font(.system(size: 9)).foregroundStyle(.secondary)
                Text("↓ \(TelemetryFormat.rate(guest.receiveBps))  ↑ \(TelemetryFormat.rate(guest.transmitBps))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(12).frame(width: 294).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.09)))
        }.buttonStyle(.plain).contextMenu { GuestContextMenu(guest: guest, model: model) }
            .help(model.topologyAddressErrors[key] ?? addresses.joined(separator: "\n"))
    }
    private func tunnelNode(_ tunnel: NodeNetworkInterface) -> some View {
        let measured = measurement(tunnel.iface)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "network.badge.shield.half.filled").foregroundStyle(.purple)
                Text(model.profiles.first(where: { $0.id == model.selectedProfile })?.externalTunnel?.name ?? (tunnel.iface.hasPrefix("awg") ? "AmneziaWG / VPS" : "VPN / VPS")).fontWeight(.semibold)
                Spacer(); StatusDot(online: measured?.reachable ?? (tunnel.active != 0))
            }.font(.system(size: 12))
            HStack { Text(tunnel.iface); Spacer(); Text(measured?.pingMS.map { String(format: "%.1f ms", $0) } ?? "— ms") }.font(.system(size: 10, design: .monospaced))
            Text(measured?.peer ?? "Endpoint —").font(.system(size: 11, design: .monospaced)).foregroundStyle(.purple)
            Text("↓ \(TelemetryFormat.rate(measured?.ratesAvailable == false ? nil : measured?.receiveBps))  ↑ \(TelemetryFormat.rate(measured?.ratesAvailable == false ? nil : measured?.transmitBps))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(14).frame(width: 270).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.purple.opacity(0.3)))
    }
}
