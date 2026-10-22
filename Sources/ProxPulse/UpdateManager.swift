import AppKit
import SwiftUI
import CryptoKit
import ProxPulseCore

@MainActor private final class UpdateProgressRelay {
    weak var manager: UpdateManager?
    init(_ manager: UpdateManager) { self.manager = manager }
    func update(_ progress: DownloadProgress) { manager?.downloadProgress = progress }
}
@MainActor @Observable final class UpdateManager {
    var downloadProgress = DownloadProgress()
    var downloadedDMG: URL?
    private var transfer: Task<VerifiedUpdate, any Error>?
    var checking = false
    var installing = false
    var preparingReplacement = false
    var release: AppRelease?
    var showRelease = false
    var status: String?
    var error: String?
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.3"
    private var checkedAtLaunch = false
    func atLaunch() async {
        guard !checkedAtLaunch else { return }; checkedAtLaunch = true
        guard UserDefaults.standard.object(forKey: PreferenceKey.checkUpdates) == nil || UserDefaults.standard.bool(forKey: PreferenceKey.checkUpdates) else { return }
        await check(silent: true)
    }
    func check(silent: Bool = false) async {
        guard !checking, !installing else { return }
        checking = true; error = nil; status = nil
        defer { checking = false }
        do {
            let version = currentVersion
            let latest = try await Task.detached(priority: .utility) {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25
                let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
                var request = URLRequest(url: ReleaseUpdate.endpoint)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("ProxPulse/" + version, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw ReleaseUpdateError.invalidRelease }
                return try ReleaseUpdate.parse(data)
            }.value
            guard let installed = ReleaseVersion(currentVersion) else { throw ReleaseUpdateError.invalidRelease }
            release = latest.version > installed ? latest : nil
            if release != nil { showRelease = true } else { status = "Установлена последняя версия" }
        } catch { if !silent { self.error = "Не удалось проверить обновления. Повторите позже." } }
    }
    func cancelDownload() { transfer?.cancel() }
    func openDownloadedDMG() { if let downloadedDMG { NSWorkspace.shared.open(downloadedDMG) } }
    func install() async {
        guard let release, !installing else { return }
        installing = true; error = nil; status = "Загрузка и проверка обновления…"; downloadProgress = .init()
        defer { installing = false; preparingReplacement = false; transfer = nil }
        do {
            let relay = UpdateProgressRelay(self)
            let task = Task.detached(priority: .utility) {
                try await UpdatePackage.fetch(release) { progress in
                    Task { @MainActor in relay.update(progress) }
                }
            }
            transfer = task
            let package = try await task.value
            downloadedDMG = package.dmg; preparingReplacement = true
            status = "Подготовка замены приложения…"
            guard let installer = Bundle.main.url(forResource: "install", withExtension: "sh") else { throw CocoaError(.fileNoSuchFile) }
            let pid = ProcessInfo.processInfo.processIdentifier
            try await Task.detached(priority: .utility) {
                let helper = try UpdateHandoff.prepare(package: package, installer: installer, parentPID: pid)
                try await UpdateHandoff.launch(helper)
            }.value
            // Quit only after the child acknowledges startup. It then waits for this exact PID,
            // stages and verifies the app, replaces it with rollback, and relaunches it.
            NSApplication.shared.terminate(nil)
        } catch is CancellationError {
            status = "Загрузка отменена"
        } catch let error as URLError where error.code == .cancelled {
            status = "Загрузка отменена"
        } catch {
            self.error = "Обновление не установлено. Текущая версия сохранена. " + error.localizedDescription
            status = nil
        }
    }

}

struct UpdateSectionView: View {
    @Bindable var manager: UpdateManager
    @AppStorage(PreferenceKey.checkUpdates) private var automatic = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("ProxPulse " + manager.currentVersion).foregroundStyle(.secondary); Spacer(); if manager.checking { ProgressView().controlSize(.small) }; LB("Проверить обновления") { Task { await manager.check() } }.disabled(manager.checking || manager.installing) }
            Toggle(isOn: $automatic) { T("Проверять обновления при запуске") }
            if let status = manager.status { T(status).foregroundStyle(.secondary) }
            if let error = manager.error { T(error).foregroundStyle(.orange) }
            if manager.release != nil { LB("Что нового") { manager.showRelease = true } }
        }
    }
}
struct UpdateSheet: View {
    @Bindable var manager: UpdateManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseAccent) private var accent
    private func markdown(_ line: String) -> AttributedString {
        var value = line
        if value.hasPrefix("#") { value = "**" + value.drop(while: { $0 == "#" || $0 == " " }) + "**" }
        if value.hasPrefix("- ") || value.hasPrefix("* ") { value = "• " + value.dropFirst(2) }
        return (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "arrow.down.circle.fill").font(.largeTitle).foregroundStyle(accent.uiColor); VStack(alignment: .leading) { T("Доступно обновление").font(.title2.bold()); Text("ProxPulse " + (manager.release?.tag ?? "")) }; Spacer() }
            T("Что нового").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array((manager.release?.notes ?? "").components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                        Text(markdown(line)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            T("Приложение закроется и запустится после установки.").font(.caption).foregroundStyle(.secondary)
            if manager.installing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: manager.downloadProgress.fraction)
                    HStack {
                        Text(String(format: "%.1f / %@ MB · %@ · %.1f MB/s", Double(manager.downloadProgress.received)/1_000_000, manager.downloadProgress.total.map { String(format: "%.1f", Double($0)/1_000_000) } ?? "—", manager.downloadProgress.fraction.map { String(format: "%.0f%%", $0*100) } ?? "—", manager.downloadProgress.bytesPerSecond/1_000_000)).font(.caption.monospacedDigit())
                        Spacer()
                        LB("Отменить загрузку") { manager.cancelDownload() }.disabled(manager.preparingReplacement)
                    }
                    T(manager.status ?? "Загрузка и проверка обновления…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if manager.error != nil && manager.downloadedDMG != nil { LB("Открыть скачанный DMG") { manager.openDownloadedDMG() } }
            if let error = manager.error { T(error).font(.caption).foregroundStyle(.orange) }
            HStack { LB("Позже") { dismiss() }.disabled(manager.installing); Spacer(); LB("Скачать и обновить") { Task { await manager.install() } }.buttonStyle(.borderedProminent).disabled(manager.installing) }
        }.padding(26).frame(width: 620, height: 600).background(.ultraThinMaterial)
            .interactiveDismissDisabled(manager.installing)
    }
}
