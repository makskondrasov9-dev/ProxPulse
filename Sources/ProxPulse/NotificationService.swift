import Foundation
import UserNotifications
import ProxPulseCore

@MainActor @Observable final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    var status = "Не запрошено"
    var error: String?
    private override init() { super.init() }
    func prepare() async {
        // CLI render/test executables are not installed apps and must not request permissions.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let status = await Self.authorizationStatus()
        if status == UNAuthorizationStatus.notDetermined.rawValue {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch { self.error = error.localizedDescription }
        }
        await refreshStatus()
    }
    func refreshStatus() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let value = await Self.authorizationStatus()
        status = value == UNAuthorizationStatus.authorized.rawValue || value == UNAuthorizationStatus.provisional.rawValue ? "Разрешено" : value == UNAuthorizationStatus.notDetermined.rawValue ? "Не запрошено" : "Не разрешено"
    }
    nonisolated private static func authorizationStatus() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in continuation.resume(returning: settings.authorizationStatus.rawValue) }
        }
    }
    func post(_ event: MonitoringEvent) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let defaults = UserDefaults.standard
        let key = event.kind == .guestStopped ? PreferenceKey.guestAlerts : event.kind == .diskHigh ? PreferenceKey.diskAlerts : PreferenceKey.nodeAlerts
        guard defaults.object(forKey: key) as? Bool ?? true else { return }
        let language = defaults.string(forKey: PreferenceKey.language) ?? "ru"
        let content = UNMutableNotificationContent()
        let title: String
        let body: String
        switch event.kind {
        case .guestStopped:
            title = "Машина \(event.subject) остановилась"
            body = "Нода \(event.node): running → stopped. Проверьте Task History и журналы; причина пока не установлена."
        case .diskHigh:
            title = "Хранилище \(event.subject): \(event.value ?? 0)% занято"
            body = "\(event.node) · " + (language == "en" ? "Check storage capacity and available space." : "Проверьте ёмкость хранилища и свободное место.")
        case .nodeUnavailable:
            title = "Потеря связи с нодой"
            body = "Нода \(event.node) не передаёт данные более 15 секунд."
        }
        content.title = L10n.text(title, language: language)
        content.body = L10n.text(body, language: language)
        if defaults.object(forKey: PreferenceKey.notificationSound) as? Bool ?? true { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil)) { _ in }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { notification.request.content.sound == nil ? [.banner, .list] : [.banner, .sound, .list] }
}
