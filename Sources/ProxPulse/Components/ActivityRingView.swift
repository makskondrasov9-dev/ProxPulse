import SwiftUI
import ProxPulseWidgetUI

struct RingMetric: Identifiable {
    var id: String
    var value: Double
    var colors: [Color]
    static func cpu(_ v: Double) -> Self { .init(id: "CPU", value: v, colors: [PulseTheme.blue, PulseTheme.cyan]) }
    static func ram(_ v: Double) -> Self { .init(id: "RAM", value: v, colors: [PulseTheme.purple, PulseTheme.pink]) }
    static func disk(_ v: Double) -> Self { .init(id: "Disk", value: v, colors: [.orange, PulseTheme.amber]) }
    static func net(_ v: Double) -> Self { .init(id: "Net", value: v, colors: [Color.teal, PulseTheme.green]) }
}
/// Metrics ordered from the outer ring to the inner ring. Values are normalized to 0...1.
struct ActivityRingView: View {
    var metrics: [RingMetric]
    var lineWidth: CGFloat = 9
    var spacing: CGFloat = 5
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseAccent) private var accent
    @State private var revealed = false
    var body: some View {
        ZStack {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                let fraction = metric.value.isFinite ? min(1, max(0, metric.value)) : 0
                let semanticIndex = ["CPU", "RAM", "Disk"].firstIndex(of: metric.id)
                let colors = semanticIndex.map { WidgetPalette.ringColors(accent, index: $0) } ?? metric.colors
                ZStack {
                    Circle().stroke(colors[0].opacity(0.13), lineWidth: lineWidth)
                    Circle().trim(from: 0, to: revealed || !animated ? fraction : 0)
                        .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: colors.last!.opacity(0.28), radius: 5)
                }.padding(CGFloat(index) * (lineWidth + spacing) + lineWidth / 2)
                .localizedAccessibilityLabel("\(metric.id), \(Int(fraction * 100)) процентов")
            }
        }
        .onAppear { withAnimation(reduceMotion || !animated ? nil : .spring(response: 0.45, dampingFraction: 0.75)) { revealed = true } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: accent)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: metrics.map(\.value))
    }
}
