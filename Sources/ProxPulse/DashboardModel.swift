import SwiftUI
import WidgetKit
import ProxPulseCore

struct MetricSample: Identifiable {
    let id = UUID()
    var cpu: Double
    var ram: Double
    var disk: Double
}
@MainActor @Observable final class DashboardModel {
    static let demoID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var profiles: [ServerProfile] = []
    var selectedProfile = DashboardModel.demoID { didSet { if oldValue != selectedProfile { if persistSelection { UserDefaults.standard.set(selectedProfile.uuidString, forKey: "pulse.lastProfile") }; switchProfile() } } }
    var selectedNode = "" { didSet { if oldValue != selectedNode && !isDemo && !changingProfile { restartPolling(clear: true) } } }
    var availableNodes: [String] = []
    var node = MockDataProvider.node
    var selectedPage = "Обзор"
    var search = ""
    var guestFilter = "Все"
    var notice: String?
    var inspectedGuest: Guest?
    var editingProfile: ServerProfile?
    var guestHistory: [String: [GuestSample]] = [:]
    var guestAddresses: [String] = []
    var addressError: String?
    var loadingAddresses = false
    private var addressTask: Task<Void, Never>?
    var diagnosticGuest: Guest?
    var solution: DiagnosticFinding?
    var pendingAction: PendingGuestAction?
    var showAddServer = false
    var incidentPresented = false
    var incidentReport = IncidentReport.demo
    var isDiagnosing = false
    var widgetError: String?
    var connectionError: String?
    var isLoading = false
    var hasSnapshot = true
    var lastUpdated = Date()
    var history: [MetricSample] = []
    var busyGuests: Set<Int> = []
    private var pollTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var operationTasks: [Int: Task<Void, Never>] = [:]
    private var rules = MonitoringRules()
    private var started = false
    private var persistSelection = false
    private var diagnosticTask: Task<Void, Never>?
    private var service: ProxmoxAPIService?
    private var revision = 0
    private var changingProfile = false
    private var widgetReloadPolicy = WidgetReloadPolicy()
    @ObservationIgnored var widgetTestSink: ((WidgetSnapshot, Bool) -> Void)?
    var isDemo: Bool { selectedProfile == Self.demoID }
    var profileName: String { isDemo ? "DEMO (Mock-данные)" : profiles.first(where: { $0.id == selectedProfile })?.name ?? "Сервер" }
    var sourceLabel: String { isDemo ? "DEMO" : connectionError != nil ? "ОШИБКА" : hasSnapshot ? "LIVE" : "ПОДКЛЮЧЕНИЕ" }
    var connectionSummary: String {
        if isDemo { return "DEMO · Локальный снимок" }
        if let connectionError { return (hasSnapshot ? "Данные устарели · " : "Нет данных · ") + connectionError }
        return hasSnapshot ? "LIVE · Интервал \(pollInterval) сек" : "Подключение к серверу…"
    }
    var pollInterval: Int { let value = UserDefaults.standard.integer(forKey: PreferenceKey.pollInterval); return [2, 4, 10].contains(value) ? value : 4 }
    var diskThreshold: Double {
        let value = UserDefaults.standard.integer(forKey: PreferenceKey.diskThreshold)
        return Double([80, 90, 95].contains(value) ? value : 90) / 100
    }
    var findings: [DiagnosticFinding] { incidentReport.findings }
    init(loadProfiles: Bool = true) {
        persistSelection = loadProfiles
        for guest in MockDataProvider.guests {
            guestHistory[MonitoringRules.guestKey(guest)] = (0..<24).map { index in
                var sample = GuestSample(guest: guest, date: Date().addingTimeInterval(Double(index - 24) * 4))
                sample.cpu = guest.cpu * (0.8 + 0.2 * sin(Double(index)))
                return sample
            }
        }
        if loadProfiles {
            do { profiles = try ProfileStore.load() }
            catch { notice = "Не удалось прочитать профили: \(error.localizedDescription)" }
        }
    }
    func start() {
        guard !started else { return }; started = true
        guard persistSelection else { return }
        let stored = UserDefaults.standard.string(forKey: "pulse.lastProfile").flatMap(UUID.init(uuidString:))
        if let stored, stored == Self.demoID { return }
        if let profile = profiles.first(where: { $0.id == stored }) ?? profiles.first { selectedProfile = profile.id }
    }
    func preferencesChanged(restart: Bool = false) { publishSnapshot(force: true); if restart { sleepTask?.cancel() } }
    func notificationPreferencesChanged() {
        guard !isDemo else { return }
        let defaults = UserDefaults.standard
        if [PreferenceKey.guestAlerts, PreferenceKey.diskAlerts, PreferenceKey.nodeAlerts].contains(where: { defaults.object(forKey: $0) as? Bool ?? true }) { Task { await NotificationService.shared.prepare() } }
    }
    var filteredGuests: [Guest] {
        node.guests.filter { guest in
            (search.isEmpty || guest.name.localizedCaseInsensitiveContains(search) || String(guest.id).contains(search)) &&
            (guestFilter == "Все" || (guestFilter == "Работают" && guest.running) || (guestFilter == "Выключены" && !guest.running))
        }
    }
    func addProfile(_ profile: ServerProfile, secret: String) throws {
        try KeychainManager.save(secret, for: profile.id)
        do { try ProfileStore.save(profiles + [profile]) }
        catch { try? KeychainManager.delete(for: profile.id); throw error }
        profiles.append(profile)
        selectedProfile = profile.id
    }
    func updateProfile(_ profile: ServerProfile, secret: String?) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profiles; updated[index] = profile
        try ProfileStore.save(updated)
        do { if let secret { try KeychainManager.save(secret, for: profile.id) } }
        catch { try? ProfileStore.save(profiles); throw error }
        profiles = updated
        if selectedProfile == profile.id { switchProfile() }
        else { selectedProfile = profile.id }
    }
    func inspect(_ guest: Guest) {
        inspectedGuest = guest; guestAddresses = []; addressError = nil
        addressTask?.cancel()
        if isDemo { guestAddresses = ["192.168.1.\(guest.id)"]; loadingAddresses = false; return }
        guard let service else { return }
        loadingAddresses = true
        let current = revision
        addressTask = Task { [weak self] in
            do {
                let addresses = try await service.guestAddresses(guest)
                guard let self, !Task.isCancelled, current == self.revision else { return }
                self.guestAddresses = addresses; self.loadingAddresses = false
            } catch {
                guard let self, !Task.isCancelled, current == self.revision else { return }
                self.addressError = error.localizedDescription; self.loadingAddresses = false
            }
        }
    }
    func samples(for guest: Guest) -> [GuestSample] { guestHistory[MonitoringRules.guestKey(guest)] ?? [] }
    func switchProfile() {
        incidentPresented = false; inspectedGuest = nil
        changingProfile = true
        availableNodes = []; selectedNode = ""
        changingProfile = false
        search = ""; guestFilter = "Все"; diagnosticGuest = nil; pendingAction = nil; busyGuests = []
        restartPolling(clear: true)
    }
    private func restartPolling(clear: Bool) {
        pollTask?.cancel(); sleepTask?.cancel(); offlineTask?.cancel(); diagnosticTask?.cancel(); addressTask?.cancel()
        operationTasks.values.forEach { $0.cancel() }; operationTasks = [:]; busyGuests = []
        rules = MonitoringRules(); revision += 1
        isDiagnosing = false; service = nil; connectionError = nil
        if clear { guestHistory = [:]; inspectedGuest = nil; history = []; hasSnapshot = false; node = .empty(name: selectedNode.isEmpty ? profileName : selectedNode); incidentReport = IncidentReport() }
        if isDemo {
            node = MockDataProvider.node; incidentReport = .demo; hasSnapshot = true; isLoading = false; lastUpdated = Date()
            publishSnapshot(force: true); return
        }
        guard let profile = profiles.first(where: { $0.id == selectedProfile }) else { return }
        let current = revision
        let preferred = selectedNode.isEmpty ? nil : selectedNode
        isLoading = true
        publishSnapshot(force: true)
        notificationPreferencesChanged()
        offlineTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, current == self.revision else { return }
                if let event = self.rules.checkUnavailable(node: self.hasSnapshot ? self.node.id : profile.endpoint.host ?? profile.name) { self.node.online = false; self.publishSnapshot(force: true); NotificationService.shared.post(event) }
            }
        }
        pollTask = Task { [weak self] in
            do {
                let api = try ProxmoxAPIService(profile: profile)
                guard let self, current == self.revision else { return }
                self.service = api
                while !Task.isCancelled {
                    do {
                        let snapshot = try await api.snapshot(node: preferred)
                        try Task.checkCancellation()
                        guard current == self.revision else { return }
                        self.availableNodes = snapshot.nodes
                        for event in self.rules.observe(snapshot.node, diskThreshold: self.diskThreshold) { NotificationService.shared.post(event) }
                        let keys = Set(snapshot.node.guests.map(MonitoringRules.guestKey))
                        self.guestHistory = self.guestHistory.filter { keys.contains($0.key) }
                        for guest in snapshot.node.guests where guest.telemetryDate != nil {
                            let key = MonitoringRules.guestKey(guest)
                            self.guestHistory[key, default: []].append(GuestSample(guest: guest, date: guest.telemetryDate!))
                            self.guestHistory[key] = Array(self.guestHistory[key, default: []].suffix(120))
                        }
                        self.node = snapshot.node
                        self.hasSnapshot = true; self.isLoading = false; self.connectionError = nil
                        self.lastUpdated = Date()
                        self.history.append(.init(cpu: snapshot.node.cpu, ram: snapshot.node.memoryGB / max(1, snapshot.node.maxMemoryGB), disk: snapshot.node.storage.fraction))
                        self.history = Array(self.history.suffix(30))
                        if !self.incidentPresented { self.incidentReport = .live(storage: snapshot.node.storage, guests: snapshot.node.guests) }
                        self.publishSnapshot()
                    } catch is CancellationError { return }
                    catch {
                        guard current == self.revision && !Task.isCancelled else { return }
                        self.connectionError = error.localizedDescription; self.isLoading = false
                        if case ProxmoxError.http(401) = error { self.rules.clearFailure() }
                        else if case ProxmoxError.http(403) = error { self.rules.clearFailure() }
                        else { self.rules.failed() }
                        self.publishSnapshot()
                    }
                    let sleep = Task<Void, Never> { do { try await Task.sleep(for: .seconds(self.pollInterval)) } catch {} }
                    self.sleepTask = sleep
                    await sleep.value
                }
            } catch is CancellationError { }
            catch { if let self, current == self.revision { self.connectionError = error.localizedDescription; self.isLoading = false; self.publishSnapshot() } }
        }
    }
    var widgetSnapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot(node: node, isDemo: isDemo)
        snapshot.profileID = selectedProfile; snapshot.profileName = profileName
        snapshot.state = isDemo ? .demo : connectionError != nil ? .error : !hasSnapshot ? .connecting : node.online ? .live : .offline
        snapshot.date = hasSnapshot ? lastUpdated : Date()
        return snapshot
    }
    func publishSnapshot(force: Bool = false) {
        let snapshot = widgetSnapshot
        if let widgetTestSink {
            widgetTestSink(snapshot, widgetReloadPolicy.shouldReload(snapshot, force: force))
            return
        }
        guard persistSelection, Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            try WidgetSnapshotStore.save(snapshot)
            widgetError = nil
            if widgetReloadPolicy.shouldReload(snapshot, force: force) { WidgetCenter.shared.reloadAllTimelines() }
        } catch { widgetError = "Не удалось сохранить снимок виджета: \(error.localizedDescription)" }
    }
    func refresh() {
        if isDemo { lastUpdated = Date() } else { sleepTask?.cancel() }
    }
    func showIncidents() {
        incidentPresented = true
        if isDemo { incidentReport = .demo; return }
        guard let service, hasSnapshot else { incidentReport = IncidentReport(); return }
        diagnosticTask?.cancel()
        isDiagnosing = true
        let current = revision; let snapshot = node
        diagnosticTask = Task { [weak self] in
            let report = await service.diagnostics(node: snapshot.id, storage: snapshot.storage, guests: snapshot.guests)
            guard !Task.isCancelled, let self, self.revision == current else { return }
            self.incidentReport = report; self.isDiagnosing = false
        }
    }
    func request(_ guest: Guest, action: ProxmoxAPIService.GuestAction, origin: PendingGuestAction.Origin = .dashboard) {
        guard !busyGuests.contains(guest.id) else { return }
        if action == .start { perform(guest, action: action) }
        else { pendingAction = PendingGuestAction(guest: guest, action: action, origin: origin) }
    }
    func control(_ guest: Guest, running: Bool) { perform(guest, action: running ? .start : .stop) }
    func perform(_ guest: Guest, action: ProxmoxAPIService.GuestAction) {
        guard !busyGuests.contains(guest.id) else { return }
        if isDemo {
            guard let index = node.guests.firstIndex(where: { $0.id == guest.id }) else { return }
            node.guests[index].running = action == .start || action == .reboot
            node.guests[index].cpu = node.guests[index].running ? 0.03 : 0
            node.guests[index].memoryGB = node.guests[index].running ? 0.5 : 0
            publishSnapshot(force: true); return
        }
        guard let service, connectionError == nil else { return }
        busyGuests.insert(guest.id)
        if action != .start { rules.expectStop(guest, now: .now) }
        let current = revision
        operationTasks[guest.id] = Task { [weak self] in
            do {
                let upid = try await service.control(guest, action: action)
                try await service.waitForTask(node: guest.node, upid: upid)
                try Task.checkCancellation()
                guard let self, current == self.revision else { return }
                self.rules.actionCompleted(guest, running: action == .start || action == .reboot)
                self.busyGuests.remove(guest.id); self.operationTasks.removeValue(forKey: guest.id)
                self.refresh()
            } catch is CancellationError { }
            catch {
                guard let self, current == self.revision else { return }
                self.busyGuests.remove(guest.id); self.operationTasks.removeValue(forKey: guest.id)
                self.notice = error.localizedDescription
            }
        }
    }
    func shell(_ guest: Guest? = nil) {
        guard !isDemo, let profile = profiles.first(where: { $0.id == selectedProfile }) else { notice = "Недоступно в демо. Подключите живой сервер."; return }
        let targetNode = guest?.node ?? node.id
        let fallbackHost = availableNodes.count <= 1 ? profile.endpoint.host ?? targetNode : targetNode
        let api = service
        let user = UserDefaults.standard.string(forKey: PreferenceKey.sshUser) ?? "root"
        Task {
            do {
                let host = (try? await api?.sshHost(node: targetNode)) ?? fallbackHost
                try await TerminalLauncher.open(host: host, user: user, guest: guest)
            }
            catch { notice = "Не удалось открыть Terminal: \(error.localizedDescription)" }
        }
    }
    func webConsole(_ guest: Guest) {
        guard !isDemo, let profile = profiles.first(where: { $0.id == selectedProfile }) else { notice = "Shell доступен после подключения живого сервера."; return }
        var c = URLComponents(url: profile.endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "console", value: guest.kind == .lxc ? "lxc" : "kvm"), .init(name: "vmid", value: String(guest.id)), .init(name: "node", value: guest.node), .init(name: "novnc", value: "1")]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
    func chartValues(_ metric: Int) -> [Double] {
        if isDemo {
            return (0..<24).map { (index: Int) -> Double in
                let wave = sin(Double(index + metric * 3) * 0.7) * 0.12
                let ripple = cos(Double(index * 2 + metric) * 0.53) * 0.1
                return 0.3 + wave + ripple
            }
        }
        return history.map { metric == 0 ? $0.cpu : metric == 1 ? $0.ram : $0.disk }
    }
    func stop() { pollTask?.cancel(); sleepTask?.cancel(); offlineTask?.cancel(); diagnosticTask?.cancel(); operationTasks.values.forEach { $0.cancel() }; revision += 1 }
}
