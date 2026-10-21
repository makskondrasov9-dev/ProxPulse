import AppKit
import SwiftUI
import CryptoKit
import ProxPulseCore

@MainActor @Observable final class UpdateManager {
    var checking = false
    var installing = false
    var release: AppRelease?
    var showRelease = false
    var status: String?
    var error: String?
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
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
            var request = URLRequest(url: ReleaseUpdate.endpoint)
            request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ProxPulse/" + currentVersion, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw ReleaseUpdateError.invalidRelease }
            let latest = try ReleaseUpdate.parse(data)
            guard let installed = ReleaseVersion(currentVersion) else { throw ReleaseUpdateError.invalidRelease }
            release = latest.version > installed ? latest : nil
            if release != nil { showRelease = true } else { status = "Установлена последняя версия" }
        } catch { if !silent { self.error = "Не удалось проверить обновления. Повторите позже." } }
    }
    func install() async {
        guard let release, !installing else { return }
        installing = true; error = nil; status = "Загрузка и проверка обновления…"
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProxPulse-update-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var handedOff = false
            defer { if !handedOff { try? FileManager.default.removeItem(at: directory) } }
            let (checksum, checksumResponse) = try await URLSession.shared.data(from: release.checksum)
            guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200, checksum.count < 4096 else { throw ReleaseUpdateError.invalidChecksum }
            let expected = try ReleaseUpdate.expectedHash(checksum, filename: release.download.lastPathComponent)
            let (temporary, response) = try await URLSession.shared.download(from: release.download)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ReleaseUpdateError.invalidRelease }
            let file = directory.appendingPathComponent(release.download.lastPathComponent)
            try FileManager.default.moveItem(at: temporary, to: file)
            let actual = try await Task.detached(priority: .utility) {
                let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                var hash = SHA256()
                while let bytes = try handle.read(upToCount: 1024*1024), !bytes.isEmpty { hash.update(data: bytes) }
                return hash.finalize().map { String(format: "%02x", $0) }.joined()
            }.value
            guard actual == expected else { throw ReleaseUpdateError.invalidChecksum }
            guard let bundledScript = Bundle.main.url(forResource: "install", withExtension: "sh") else { throw CocoaError(.fileNoSuchFile) }
            // Copy the helper out of the bundle before replacing that bundle.
            let helper = directory.appendingPathComponent("install.sh")
            try FileManager.default.copyItem(at: bundledScript, to: helper)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [helper.path, "--dmg", file.path, "--wait-pid", String(ProcessInfo.processInfo.processIdentifier)]
            let log = directory.appendingPathComponent("install.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
            try process.run(); handedOff = true
            NSApplication.shared.terminate(nil)
        } catch { self.error = "Обновление не установлено. Текущая версия сохранена."; status = nil; installing = false }
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
            if manager.installing { HStack { ProgressView().controlSize(.small); T("Загрузка и проверка обновления…") } }
            if let error = manager.error { T(error).font(.caption).foregroundStyle(.orange) }
            HStack { LB("Позже") { dismiss() }.disabled(manager.installing); Spacer(); LB("Скачать и обновить") { Task { await manager.install() } }.buttonStyle(.borderedProminent).disabled(manager.installing) }
        }.padding(26).frame(width: 620, height: 600).background(.ultraThinMaterial)
            .interactiveDismissDisabled(manager.installing)
    }
}
