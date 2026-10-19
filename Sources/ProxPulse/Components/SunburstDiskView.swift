import SwiftUI
import ProxPulseCore

struct AnnularSector: Shape {
    var start: Double
    var end: Double
    var inner: Double
    var outer: Double
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(start, end), .init(inner, outer)) }
        set { start = newValue.first.first; end = newValue.first.second; inner = newValue.second.first; outer = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: r * outer, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        path.addArc(center: center, radius: r * inner, startAngle: .degrees(end - 90), endAngle: .degrees(start - 90), clockwise: true)
        path.closeSubpath(); return path
    }
}
private struct DiskSector: Identifiable {
    var item: DiskItem
    var start: Double
    var end: Double
    var level: Int
    var palette: Int
    var id: String { item.id }
}
struct SunburstDiskView: View {
    @Environment(\.pulseAccent) private var accent
    var root: DiskItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [String] = []
    @State private var hovered: String?
    private var trail: [DiskItem] {
        var items = [root]
        for id in path { if let item = items.last?.children.first(where: { $0.id == id }) { items.append(item) } }
        return items
    }
    private var focus: DiskItem { trail.last ?? root }
    private var sectors: [DiskSector] {
        var result: [DiskSector] = []
        func append(_ parent: DiskItem, start: Double, end: Double, level: Int, palette: Int?) {
            guard parent.capacityGB > 0, level < 2 else { return }
            var cursor = start
            for (index, child) in parent.children.enumerated() {
                let span = (end - start) * min(1, max(0, child.capacityGB / parent.capacityGB))
                guard span > 0 else { continue }
                let last = min(end, cursor + span)
                let p = palette ?? index
                result.append(.init(item: child, start: cursor, end: last, level: level, palette: p))
                append(child, start: cursor, end: last, level: level + 1, palette: p)
                cursor = last
            }
        }
        append(focus, start: 0, end: 360, level: 0, palette: nil)
        if focus.children.isEmpty { result.append(.init(item: focus, start: 0, end: 360, level: 0, palette: 0)) }
        return result
    }
    private func color(_ sector: DiskSector) -> Color {
        let fraction = sector.item.fraction
        let base = [accent.uiColor, PulseTheme.purple, PulseTheme.green][sector.palette % 3]
        // Continuous interpolation at the 80% and 90% boundaries.
        if fraction > 0.9 { return .orange.mix(with: .red, by: min(1, (fraction - 0.9) / 0.06)) }
        if fraction > 0.8 { return base.mix(with: .orange, by: (fraction - 0.8) / 0.1) }
        return base
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary) }
                    LB(item.name) { navigate(Array(path.prefix(index))) }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                }
            }.lineLimit(1)
            ZStack {
                Circle().stroke(.primary.opacity(0.04), lineWidth: 1).padding(1)
                ForEach(sectors) { sector in
                    let inner = sector.level == 0 ? 0.47 : 0.76
                    let outer = sector.level == 0 ? 0.71 : 0.94
                    let gap = min(1.4, (sector.end - sector.start) / 8)
                    let shape = AnnularSector(start: sector.start + gap, end: sector.end - gap, inner: inner, outer: outer)
                    ZStack {
                        shape.fill(color(sector).opacity(0.12))
                        AnnularSector(start: sector.start + gap, end: sector.start + gap + max(0, sector.end - sector.start - gap * 2) * sector.item.fraction, inner: inner, outer: outer)
                            .fill(LinearGradient(colors: [color(sector).opacity(0.62), color(sector)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        shape.strokeBorderCompat(color(sector).opacity(hovered == sector.id ? 0.9 : 0.18))
                    }
                    .shadow(color: color(sector).opacity(hovered == sector.id ? 0.32 : 0), radius: 12)
                    .contentShape(shape)
                    .onHover { hovered = $0 ? sector.id : nil }
                    .onTapGesture { if sector.item.id != focus.id { navigate(path + [sector.item.id], selected: sector.item) } }
                    .accessibilityElement(children: .ignore)
                    .localizedAccessibilityLabel("\(sector.item.name), \(Int(sector.item.usedGB)) из \(Int(sector.item.capacityGB)) GB")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { navigate(path + [sector.item.id], selected: sector.item) }
                }
                VStack(spacing: 5) {
                    Image(systemName: "internaldrive").font(.system(size: 18)).foregroundStyle(.secondary).padding(.bottom, 2)
                    T(focus.usedGB.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 31, weight: .semibold, design: .rounded)).monospacedDigit()
                    T("из \(Int(focus.capacityGB)) GB").font(.system(size: 11)).foregroundStyle(.secondary)
                    T("\(Int(focus.fraction * 100))% занято").font(.system(size: 10, weight: .medium)).foregroundStyle(accent.uiColor).padding(.top, 4)
                }.allowsHitTesting(false)
                if let hovered, let sector = sectors.first(where: { $0.id == hovered }) {
                    VStack(alignment: .leading, spacing: 4) {
                        T(sector.item.name).font(.system(size: 11, weight: .semibold))
                        T("\(Int(sector.item.usedGB)) / \(Int(sector.item.capacityGB)) GB · \(Int(sector.item.fraction * 100))%")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).allowsHitTesting(false)
                }
            }.aspectRatio(1, contentMode: .fit).frame(maxHeight: 330)
            HStack(spacing: 16) {
                ForEach(Array(root.children.enumerated()), id: \.element.id) { index, pool in
                    Button { navigate([pool.id]) } label: {
                        HStack(spacing: 5) { Circle().fill([accent.uiColor, PulseTheme.purple, PulseTheme.green][index % 3]).frame(width: 5, height: 5); T(pool.name).font(.system(size: 10, weight: .medium)) }
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }
        .onChange(of: root.id) { path = []; hovered = nil }
    }
    private func navigate(_ next: [String], selected: DiskItem? = nil) {
        var resolved = next
        // Outer-ring guests need their parent pool in the breadcrumb path.
        if let selected, !focus.children.contains(where: { $0.id == selected.id }), let parent = focus.children.first(where: { $0.children.contains(where: { $0.id == selected.id }) }) {
            resolved = path + [parent.id, selected.id]
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) { path = resolved; hovered = nil }
    }
}
private extension Shape {
    func strokeBorderCompat(_ color: Color) -> some View { stroke(color, lineWidth: 0.75) }
}
// macOS 14-compatible sRGB blend (Color.mix is only available on later macOS).
private extension Color {
    func mix(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .blue
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .orange
        let t = min(1, max(0, amount))
        return Color(red: a.redComponent * (1-t) + b.redComponent * t, green: a.greenComponent * (1-t) + b.greenComponent * t, blue: a.blueComponent * (1-t) + b.blueComponent * t)
    }
}
