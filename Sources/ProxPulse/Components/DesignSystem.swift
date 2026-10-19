import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI

extension AccentChoice { var uiColor: Color { WidgetPalette.color(self) }; func ringColors(_ index: Int) -> [Color] { WidgetPalette.ringColors(self, index: index) } }

enum PulseTheme {
    static let blue = Color(red: 0.22, green: 0.57, blue: 1)
    static let cyan = Color(red: 0.27, green: 0.88, blue: 1)
    static let purple = Color(red: 0.65, green: 0.40, blue: 1)
    static let pink = Color(red: 1, green: 0.39, blue: 0.75)
    static let green = Color(red: 0.25, green: 0.88, blue: 0.65)
    static let amber = Color(red: 1, green: 0.72, blue: 0.27)
}
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
    }
}
struct StatusDot: View {
    var online: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    var body: some View {
        Circle().fill(online ? PulseTheme.green : .secondary).frame(width: 6, height: 6)
            .shadow(color: online ? PulseTheme.green.opacity(breathing ? 0.65 : 0.2) : .clear, radius: breathing ? 6 : 2)
            .opacity(online && breathing ? 0.65 : 1)
            .onAppear { if online && !reduceMotion { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathing = true } } }
            .localizedAccessibilityLabel(online ? "Online" : "Offline")
    }
}
struct SectionTitle: View {
    var title: String
    var detail: String
    var body: some View { HStack(alignment: .firstTextBaseline) {
        T(title).font(.system(size: 17, weight: .semibold)); Spacer()
        T(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    } }
}
