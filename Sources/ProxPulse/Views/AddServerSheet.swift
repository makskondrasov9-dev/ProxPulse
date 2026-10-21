import SwiftUI
import ProxPulseCore

struct AddServerSheet: View {
    @Environment(\.pulseLanguage) private var language
    @Environment(\.pulseAccent) private var accent
    var model: DashboardModel
    var existing: ServerProfile?
    init(model: DashboardModel, existing: ServerProfile? = nil) {
        self.model = model; self.existing = existing
        if let existing {
            _name = State(initialValue: existing.name); _address = State(initialValue: existing.endpoint.absoluteString)
            _auth = State(initialValue: existing.authMode); _insecure = State(initialValue: existing.allowInsecureSSL)
            let parts = existing.tokenID.split(separator: "!", maxSplits: 1).map(String.init)
            _user = State(initialValue: parts.first ?? "root@pam")
            _tokenName = State(initialValue: parts.count > 1 ? parts[1] : "proxpulse")
            _profileID = State(initialValue: existing.id)
            _vpnEnabled = State(initialValue: existing.externalTunnel != nil)
            _vpnName = State(initialValue: existing.externalTunnel?.name ?? "AmneziaWG")
            _vpnAddress = State(initialValue: existing.externalTunnel?.address ?? "")
            _vpnInterface = State(initialValue: existing.externalTunnel?.interface ?? "awg0")
        }
    }
    private var preservesSecret: Bool { secret.isEmpty && existing?.authMode == auth }
    private func connectionSecret() throws -> String {
        if preservesSecret { return try KeychainManager.token(for: profileID) }
        return secret
    }
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Homelab"
    @State private var address = "https://proxmox.local:8006"
    @State private var auth: AuthenticationMode = .password
    @State private var user = "root@pam"
    @State private var tokenName = "proxpulse"
    @State private var secret = ""
    @State private var insecure = true
    @State private var vpnEnabled = false
    @State private var vpnName = "AmneziaWG"
    @State private var vpnAddress = ""
    @State private var vpnInterface = "awg0"
    private var externalTunnel: ExternalTunnel { .init(name: vpnName, address: vpnAddress.trimmingCharacters(in: .whitespacesAndNewlines), interface: vpnInterface) }
    @State private var testing = false
    @State private var check: ConnectionCheck?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var profileID = UUID()
    private var fingerprint: String { [name, address, auth.rawValue, user, tokenName, secret, String(insecure), String(vpnEnabled), vpnName, vpnAddress, vpnInterface].joined(separator: "\u{1F}") }
    private var validationMessage: String? {
        if vpnEnabled && !externalTunnel.isValid { return "Укажите корректные имя, IP и интерфейс VPN." }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Укажите имя кластера." }
        if (try? ProfileValidation.endpoint(address)) == nil { return "Укажите HTTPS URL или IP сервера, например 192.168.1.228:8006." }
        if ProfileValidation.username(user, mode: auth) == nil { return auth == .password ? "Введите логин, например root или root@pam." : "Введите пользователя с realm, например monitor@pve." }
        if auth == .apiToken {
            if tokenName.isEmpty || !tokenName.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) { return "Укажите Token ID: буквы, цифры, точка, дефис или подчёркивание." }
            if !preservesSecret && UUID(uuidString: secret) == nil { return "Введите Secret API-токена в формате UUID." }
        } else if secret.isEmpty && !preservesSecret { return "Введите пароль Proxmox." }
        return nil
    }
    private var valid: Bool { validationMessage == nil }
    private func profile() throws -> ServerProfile {
        guard valid else { throw ProxmoxError.invalidResponse }
        var value = ServerProfile(id: profileID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: try ProfileValidation.endpoint(address), tokenID: auth == .apiToken ? ProfileValidation.username(user, mode: auth)! + "!" + tokenName : ProfileValidation.username(user, mode: auth)!, allowInsecureSSL: insecure, authentication: auth)
        value.externalTunnel = vpnEnabled ? externalTunnel : nil
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "server.rack").font(.system(size: 24)).foregroundStyle(accent.uiColor).frame(width: 52, height: 52).background(accent.uiColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    T(existing == nil ? "Подключение сервера" : "Редактирование сервера").font(.system(size: 24, weight: .semibold))
                    T("Ваш Proxmox. Напрямую с этого Mac.").foregroundStyle(.secondary).font(.system(size: 12))
                }
            }
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                field("ИМЯ КЛАСТЕРА") { LTextField("Homelab", text: $name) }
                field("URL / IP СЕРВЕРА") { LTextField("https://proxmox.local:8006", text: $address).onChange(of: address) { insecure = ProfileValidation.isLocal(address) } }
                Picker(L10n.text("Авторизация", language: language), selection: $auth) { T("API Token").tag(AuthenticationMode.apiToken); T("Логин и пароль").tag(AuthenticationMode.password) }.pickerStyle(.segmented)
                if auth == .apiToken {
                    HStack(spacing: 14) {
                        field("USER@REALM") { LTextField("monitor@pve", text: $user) }
                        field("TOKEN ID") { LTextField("proxpulse", text: $tokenName) }
                    }
                    field("SECRET UUID") { LSecureField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $secret) }
                } else {
                    field("ЛОГИН") { LTextField("root или root@pam", text: $user) }
                    T("Если realm не указан, используется @pam.").font(.system(size: 10)).foregroundStyle(.secondary)
                    field("ПАРОЛЬ") { LSecureField("Пароль Proxmox", text: $secret) }
                }
                Toggle(isOn: $insecure) {
                    VStack(alignment: .leading, spacing: 4) {
                        T("Разрешить самоподписанный SSL").font(.system(size: 12, weight: .medium))
                        T("Для локального сервера. Проверка сертификата этого подключения будет отключена.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).controlSize(.small)
            }.disabled(testing).padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) }.frame(maxHeight: vpnEnabled ? 340 : 460)
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $vpnEnabled) { T("Внешний туннель (VPN)") }.toggleStyle(.switch)
                if vpnEnabled {
                    HStack {
                        field("Имя VPN") { LTextField("AmneziaWG", text: $vpnName) }
                        field("IP адрес VPS") { LTextField("203.0.113.10", text: $vpnAddress) }
                        field("Интерфейс") { LTextField("awg0", text: $vpnInterface) }.frame(width: 90)
                    }
                    T("Ping с этого Mac. SSH-ключи и Python не нужны.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).disabled(testing)
            if existing != nil { T("Оставьте секрет пустым, чтобы сохранить текущий в Keychain.").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                if testing { ProgressView().controlSize(.small); T("Проверяем доступ и права API…").foregroundStyle(.secondary) }
                else if let check { Image(systemName: "checkmark.circle.fill").foregroundStyle(PulseTheme.green); T("Соединение установлено · \(check.milliseconds) мс · нод: \(check.nodes.count)").foregroundStyle(PulseTheme.green) }
                else if let failure { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange); T(failure).foregroundStyle(.orange).textSelection(.enabled) }
                else { Image(systemName: "lock.shield").foregroundStyle(.secondary); T(validationMessage ?? "Можно подключаться. Секрет сохранится только в Apple Keychain.").foregroundStyle(.secondary) }
            }.font(.system(size: 11)).frame(minHeight: 34)
            HStack {
                LB("Отмена") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                LB("Проверить соединение") { test(connect: false) }.disabled(!valid || testing)
                LB(existing == nil ? "Подключиться" : "Сохранить") { test(connect: true) }
                    .buttonStyle(.borderedProminent).disabled(!valid || testing).keyboardShortcut(.defaultAction)

            }
        }.padding(26).frame(width: 640)
        .onChange(of: fingerprint) { task?.cancel(); testing = false; check = nil; failure = nil }
        .onDisappear { task?.cancel() }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            T(title).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder).controlSize(.large)
        }
    }
    private func test(connect: Bool) {
        task?.cancel(); testing = true; failure = nil
        let alreadyChecked = check != nil
        let input = fingerprint
        task = Task {
            do {
                let connection = try profile()
                if !alreadyChecked {
                    let api = try ProxmoxAPIService(profile: connection, secret: try connectionSecret())
                    let result = try await api.testConnection()
                    guard !Task.isCancelled, input == fingerprint else { return }
                    check = result
                }
                guard !Task.isCancelled, input == fingerprint else { return }
                if connect {
                    if existing != nil { try model.updateProfile(connection, secret: preservesSecret ? nil : secret) }
                    else { try model.addProfile(connection, secret: secret) }
                    dismiss()
                }
                testing = false
            } catch {
                guard !Task.isCancelled, input == fingerprint else { return }
                failure = error.localizedDescription; testing = false
            }
        }
    }
}
