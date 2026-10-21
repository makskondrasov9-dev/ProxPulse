import SwiftUI
import ProxPulseCore

struct SettingsView: View {
    var model: DashboardModel
    var embedded: Bool
    @AppStorage(PreferenceKey.language) private var language = "ru"
    @AppStorage(PreferenceKey.appearance) private var appearance = "system"
    @AppStorage(PreferenceKey.accent) private var accent = "blue"
    @AppStorage(PreferenceKey.pollInterval) private var interval = 4
    @AppStorage(PreferenceKey.diskThreshold) private var diskThreshold = 90
    @AppStorage(PreferenceKey.guestAlerts) private var guestAlerts = true
    @AppStorage(PreferenceKey.diskAlerts) private var diskAlerts = true
    @AppStorage(PreferenceKey.nodeAlerts) private var nodeAlerts = true
    @AppStorage(PreferenceKey.notificationSound) private var sound = true
    @AppStorage(PreferenceKey.sshUser) private var sshUser = "root"
    private let notifications = NotificationService.shared
    init(model: DashboardModel, embedded: Bool = false) { self.model = model; self.embedded = embedded }
    private var content: some View {
        Group {
            if embedded { sections }
            else { ScrollView { sections.padding(24) }.frame(width: 760, height: 790) }
        }
        .sheet(isPresented: Binding(get: { !embedded && model.showAddServer }, set: { if !$0 { model.showAddServer = false } })) { AddServerSheet(model: model) }
        .sheet(item: Binding(get: { embedded ? nil : model.editingProfile }, set: { if !embedded { model.editingProfile = $0 } })) { profile in AddServerSheet(model: model, existing: profile) }
        .task { await notifications.refreshStatus() }
    }
    var body: some View {
        content
        .onChange(of: interval) { model.preferencesChanged(restart: true) }
        .onChange(of: language) { model.preferencesChanged() }
        .onChange(of: accent) { model.preferencesChanged() }
        .onChange(of: appearance) { model.preferencesChanged() }
        .onChange(of: guestAlerts) { model.notificationPreferencesChanged() }
        .onChange(of: diskAlerts) { model.notificationPreferencesChanged() }
        .onChange(of: nodeAlerts) { model.notificationPreferencesChanged() }
    }
    private var sections: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Обновления", icon: "arrow.down.circle", subtitle: "Новые версии ProxPulse с GitHub") { UpdateSectionView(manager: model.updates) }
            section("Подключение к Proxmox", icon: "server.rack", subtitle: "Профили и безопасный доступ") {
                if model.profiles.isEmpty { T("Нет сохранённых серверов").foregroundStyle(.secondary) }
                ForEach(model.profiles) { profile in
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).fontWeight(.semibold)
                            Text(profile.endpoint.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if profile.id == model.selectedProfile { T("Выбран").font(.caption).foregroundStyle(.green) }
                        LB("Редактировать") { model.editingProfile = profile }
                    }
                    Divider().opacity(0.4)
                }
                HStack { LB("Подключить сервер") { model.showAddServer = true }.buttonStyle(.borderedProminent); Spacer(); Label("Apple Keychain", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary) }
            }
            section("Внешний вид", icon: "paintpalette", subtitle: "Все параметры применяются сразу, без перезапуска.") {
                setting("Язык интерфейса") {
                    Picker("", selection: $language) { Text("🇷🇺 Русский").tag("ru"); Text("🇬🇧 English").tag("en") }.labelsHidden().pickerStyle(.segmented).frame(width: 280)
                }
                setting("Тема") {
                    Picker("", selection: $appearance) { T("Системная").tag("system"); T("Тёмная").tag("dark"); T("Светлая").tag("light") }.labelsHidden().pickerStyle(.segmented).frame(width: 280)
                }
                Divider().opacity(0.4)
                T("Акцентный цвет").font(.system(size: 12, weight: .medium))
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases, id: \.self) { choice in
                        Button { accent = choice.rawValue } label: {
                            VStack(spacing: 8) {
                                Circle().fill(choice.uiColor.gradient).frame(width: 32, height: 32)
                                    .overlay { if accent == choice.rawValue { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) } }
                                Text(accentName(choice)).font(.system(size: 10))
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityLabel(accentName(choice)).accessibilityAddTraits(accent == choice.rawValue ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            }
            section("Мониторинг", icon: "waveform.path.ecg", subtitle: "Данные обновляются, пока ProxPulse запущен.") {
                setting("Интервал опроса") {
                    Picker("", selection: $interval) { T("2 сек · быстрый").tag(2); T("4 сек · стандарт").tag(4); T("10 сек · экономия энергии").tag(10) }.labelsHidden().frame(width: 235)
                }
                setting("Порог предупреждения по диску") {
                    Picker("", selection: $diskThreshold) { Text("80%").tag(80); Text("90%").tag(90); Text("95%").tag(95) }.labelsHidden().pickerStyle(.segmented).frame(width: 235)
                }
                setting("SSH-пользователь") { TextField("root", text: $sshUser).textFieldStyle(.roundedBorder).frame(width: 160) }
            }
            section("Уведомления", icon: "bell.badge", subtitle: "Локальные уведомления работают, пока приложение запущено.") {
                Toggle(isOn: $guestAlerts) { T("Падение машины") }
                Toggle(isOn: $diskAlerts) { T("Переполнение хранилища") }
                Toggle(isOn: $nodeAlerts) { T("Потеря связи с нодой >15 сек") }
                Toggle(isOn: $sound) { T("Звук уведомлений") }
                Divider().opacity(0.4)
                HStack { T("Разрешение macOS"); Spacer(); T(notifications.status).foregroundStyle(.secondary) }
                HStack {
                    LB("Разрешить уведомления") { Task { await notifications.prepare() } }
                    LB("Открыть настройки macOS") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                }
                if let error = notifications.error { T(error).font(.caption).foregroundStyle(.orange) }
            }
            section("Виджеты", icon: "rectangle.3.group", subtitle: "Кластер на вашем рабочем столе") {
                T("Нажмите правой кнопкой на рабочем столе → Изменить виджеты → найдите ProxPulse. Выберите малый, средний или большой виджет.").foregroundStyle(.secondary)
                T("Виджеты читают общий кеш. Время обновления определяет macOS; приложение должно быть запущено для получения свежих данных.").font(.caption).foregroundStyle(.secondary)
                T("Для каждого виджета машины: правый клик → Изменить виджет → Машина. Выбор независим для каждого экземпляра.").font(.caption).foregroundStyle(.secondary)
                if let error = model.widgetError { T(error).font(.caption).foregroundStyle(.orange) }
            }
        }.toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { T(title); Spacer(); content() }
    }
    private func section<Content: View>(_ title: String, icon: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 11) {
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(AccentChoice(rawValue: accent)?.uiColor ?? .blue).frame(width: 34, height: 34).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) { T(title).font(.system(size: 16, weight: .semibold)); T(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Divider().opacity(0.4)
                content()
            }
        }
    }
    private func accentName(_ choice: AccentChoice) -> String {
        switch choice { case .blue: "Electric Blue"; case .neon: "Cyber Neon"; case .emerald: "Emerald Green"; case .purple: "Royal Purple"; case .orange: "Sunset Orange" }
    }
}
