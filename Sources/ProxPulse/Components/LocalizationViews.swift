import SwiftUI
import ProxPulseCore
import ProxPulseWidgetUI

private struct LanguageKey: EnvironmentKey { static let defaultValue = "ru" }
private struct AccentKey: EnvironmentKey { static let defaultValue = AccentChoice.blue }
extension EnvironmentValues {
    var pulseLanguage: String { get { self[LanguageKey.self] } set { self[LanguageKey.self] = newValue } }
    var pulseAccent: AccentChoice { get { self[AccentKey.self] } set { self[AccentKey.self] = newValue } }
}
struct T: View {
    let value: String
    @Environment(\.pulseLanguage) private var language
    init(_ value: String) { self.value = value }
    var body: some View { Text(L10n.text(value, language: language)) }
}
struct LB: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) { self.title = title; self.role = role; self.action = action }
    var body: some View { Button(role: role, action: action) { T(title) } }
}
struct TL: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { Label { T(title) } icon: { Image(systemName: systemImage) } }
}
struct LTextField: View {
    let title: String
    @Binding var text: String
    @Environment(\.pulseLanguage) private var language
    init(_ title: String, text: Binding<String>) { self.title = title; self._text = text }
    var body: some View { TextField(L10n.text(title, language: language), text: $text) }
}
struct LSecureField: View {
    let title: String
    @Binding var text: String
    @Environment(\.pulseLanguage) private var language
    init(_ title: String, text: Binding<String>) { self.title = title; self._text = text }
    var body: some View { SecureField(L10n.text(title, language: language), text: $text) }
}
struct LocalizedHelp: ViewModifier {
    let value: String
    @Environment(\.pulseLanguage) private var language
    func body(content: Content) -> some View { content.help(L10n.text(value, language: language)) }
}
struct LocalizedAccessibility: ViewModifier {
    let value: String
    @Environment(\.pulseLanguage) private var language
    func body(content: Content) -> some View { content.accessibilityLabel(L10n.text(value, language: language)) }
}
extension View {
    func localizedHelp(_ value: String) -> some View { modifier(LocalizedHelp(value: value)) }
    func localizedAccessibilityLabel(_ value: String) -> some View { modifier(LocalizedAccessibility(value: value)) }
    func pulseAppearance() -> some View { modifier(PulseAppearance()) }
}
struct PulseAppearance: ViewModifier {
    @Environment(\.colorScheme) private var inheritedScheme
    @AppStorage(PreferenceKey.language) private var language = "ru"
    @AppStorage(PreferenceKey.appearance) private var appearance = "system"
    @AppStorage(PreferenceKey.accent) private var accent = "blue"
    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appearance == "dark" ? .dark : appearance == "light" ? .light : inheritedScheme)
            .environment(\.pulseLanguage, language)
            .environment(\.pulseAccent, AccentChoice(rawValue: accent) ?? .blue)
            .environment(\.locale, Locale(identifier: language == "ru" ? "ru_RU" : "en_US"))
            .tint(WidgetPalette.color(AccentChoice(rawValue: accent) ?? .blue))
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
