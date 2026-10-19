import SwiftUI
import Charts
import ProxPulseCore

struct DashboardView: View {
    @Environment(\.pulseLanguage) private var language
    @Environment(\.pulseAccent) private var accent
    @Bindable var model: DashboardModel
    var animate = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if model.isLoading { HStack { ProgressView().controlSize(.small); T("Подключение к \(model.profileName)…").foregroundStyle(.secondary) } }
                        if let error = model.connectionError { TL((model.hasSnapshot ? "Данные устарели. " : "Нет данных. ") + error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                        if model.selectedPage == "Настройки" { SettingsView(model: model, embedded: true) }
                        else if model.selectedPage == "Машины" { guests }
                        else if model.selectedPage == "Диагностика" { diagnostics }
                        else if model.selectedPage == "Хранилище" { storagePage }
                        else {
                            overview
                            HStack(alignment: .top, spacing: 20) {
                                guests.frame(maxWidth: .infinity)
                                radar.frame(width: 336)
                            }
                            insight
                        }
                    }.padding(28)
                }
                HStack(spacing: 6) {
                    StatusDot(online: model.node.online && model.connectionError == nil)
                    T(model.connectionSummary).font(.system(size: 10, weight: .medium))
                    Spacer()
                    T(model.isDemo ? "Proxmox · DEMO" : "Proxmox VE · API v2").font(.system(size: 10))
                }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 11)
                .background(.primary.opacity(0.02))
            }
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if scheme == .dark { Color(red: 0.035, green: 0.048, blue: 0.07) }
                RadialGradient(colors: [accent.uiColor.opacity(scheme == .dark ? 0.10 : 0.06), .clear], center: .topTrailing, startRadius: 5, endRadius: 650)
            }
        }
        .frame(minWidth: 1180, minHeight: 830)
        .alert("ProxPulse", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { LB("Понятно") { model.notice = nil } } message: { T(model.notice ?? "") }
        .modifier(GuestActionsPresentation(model: model, origin: .dashboard))
        .sheet(item: $model.inspectedGuest) { guest in GuestInspectorSheet(model: model, original: guest) }
        .sheet(item: $model.editingProfile) { profile in AddServerSheet(model: model, existing: profile) }
        .sheet(item: $model.diagnosticGuest) { guest in guestDiagnostics(guest) }
        .sheet(isPresented: $model.showAddServer) { AddServerSheet(model: model) }
        .sheet(isPresented: $model.incidentPresented) { IncidentSheet(model: model) }
        .sheet(item: $model.solution) { finding in solution(finding) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(accent.uiColor.opacity(0.14)).frame(width: 39, height: 39)
                    ActivityRingView(metrics: [.cpu(0.78), .ram(0.56)], lineWidth: 3, spacing: 3, animated: animate).frame(width: 25, height: 25)
                }
                T("ProxPulse").font(.system(size: 19, weight: .semibold, design: .rounded))
            }.padding(.top, 29)
            VStack(alignment: .leading, spacing: 8) {
                T("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.tertiary)
                Picker(L10n.text("Сервер", language: language), selection: $model.selectedProfile) { T("DEMO (Mock-данные)").tag(DashboardModel.demoID); ForEach(model.profiles) { T($0.name).tag($0.id) } }
                    .labelsHidden().pickerStyle(.menu).controlSize(.large)
                Button { model.showAddServer = true } label: { TL("Подключить сервер", systemImage: "plus.circle").font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(accent.uiColor)
            }
            VStack(spacing: 5) {
                nav("Обзор", icon: "square.grid.2x2")
                nav("Машины", icon: "square.stack.3d.up")
                nav("Хранилище", icon: "internaldrive")
                nav("Диагностика", icon: "waveform.path.ecg", badge: model.findings.isEmpty ? nil : String(model.findings.count))
                nav("Настройки", icon: "gearshape")
            }
            VStack(alignment: .leading, spacing: 15) {
                HStack { T("НОДЫ").tracking(1.6); Spacer(); T("1") }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Button { model.selectedPage = "Обзор" } label: {
                    HStack(spacing: 9) { Image(systemName: "server.rack").foregroundStyle(.secondary); T(model.node.id).font(.system(size: 12, weight: .medium)); Spacer(); StatusDot(online: model.node.online && model.connectionError == nil) }
                }.buttonStyle(.plain)
                if !model.isDemo && !model.availableNodes.isEmpty {
                    Picker(L10n.text("Нода", language: language), selection: $model.selectedNode) {
                        T("Автоматически").tag("")
                        ForEach(model.availableNodes, id: \.self) { T($0).tag($0) }
                    }.labelsHidden()
                }
            }.padding(.top, 5)
            Spacer()
            LB("SSH ноды") { model.shell() }.buttonStyle(.plain).disabled(model.isDemo || !model.hasSnapshot)
            VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: "sparkles").foregroundStyle(accent.uiColor); T("Место для вашего кластера").font(.system(size: 11, weight: .medium)) }
                T("Все системы.\nОдин спокойный взгляд.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            HStack { Image(systemName: "circle.dotted"); T("ProxPulse"); Spacer(); T(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 19).padding(.bottom, 20)
        .background(.ultraThinMaterial)
    }
    private func nav(_ title: String, icon: String, badge: String? = nil) -> some View {
        Button { model.selectedPage = title } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                T(title).lineLimit(1).font(.system(size: 12, weight: model.selectedPage == title ? .semibold : .regular))
                Spacer()
                if let badge { T(badge).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2).background(.primary.opacity(0.08), in: Capsule()) }
            }.foregroundStyle(model.selectedPage == title ? (scheme == .dark ? accent.uiColor : accent.uiColor) : .secondary)
                .padding(.horizontal, 11).padding(.vertical, 11)
                .background(model.selectedPage == title ? accent.uiColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) { T(model.selectedPage == "Обзор" ? "Ваш кластер, в балансе." : model.selectedPage).font(.system(size: 25, weight: .semibold)); T(model.sourceLabel).font(.system(size: 8, weight: .bold)).tracking(1).padding(.horizontal, 7).padding(.vertical, 4).background(.primary.opacity(0.07), in: Capsule()).foregroundStyle(.secondary) }
                HStack(spacing: 6) { T(model.profileName); T("/").foregroundStyle(.tertiary); T(model.node.id); T("·"); T(model.hasSnapshot ? "Обновлено в \(model.lastUpdated.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(Locale(identifier: "en_GB"))))" : "Ожидание данных") }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)).frame(width: 31, height: 31) }.buttonStyle(.plain).background(.primary.opacity(0.04), in: Circle()).localizedHelp("Обновить снимок")
        }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 5)
    }
    private var overview: some View {
        GlassCard {
            HStack(spacing: 26) {
                ZStack {
                    ActivityRingView(metrics: [.cpu(model.node.cpu), .ram(model.node.memoryGB / max(1, model.node.maxMemoryGB)), .disk(model.node.storage.fraction), .net(model.node.networkMBps / max(1, model.node.linkMBps))], lineWidth: 8, spacing: 5, animated: animate)
                    Image(systemName: "server.rack").font(.system(size: 17)).foregroundStyle(.secondary)
                }.frame(width: 144, height: 144)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) { StatusDot(online: model.node.online); T(model.node.id).font(.system(size: 16, weight: .semibold)) }
                    T(model.isDemo ? "AMD Ryzen 9 5900X" : model.node.cpuModel ?? "CPU —").font(.system(size: 10)).foregroundStyle(.secondary)
                    T(model.isDemo ? "12 cores · 24 threads" : model.node.cpuCount.map { "\($0) логических CPU" } ?? "Нет данных CPU").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TL(model.node.uptime, systemImage: "clock").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 7)
                }.frame(width: 146, alignment: .leading)
                Rectangle().fill(.primary.opacity(0.07)).frame(width: 1, height: 112)
                HStack(spacing: 25) {
                    metric("CPU", value: model.hasSnapshot ? "\(Int(model.node.cpu * 100))" : "—", unit: "%", detail: "нагрузка процессора", color: accent.uiColor, seed: 0)
                    metric("ПАМЯТЬ", value: model.hasSnapshot ? model.node.memoryGB.formatted(.number.precision(.fractionLength(1))) : "—", unit: "GB", detail: "из \(model.node.maxMemoryGB.formatted(.number.precision(.fractionLength(1)))) GB", color: accent.ringColors(1).last!, seed: 1)
                    metric("ДИСК", value: model.node.storage.capacityGB > 0 ? "\(Int(model.node.storage.fraction * 100))" : "—", unit: "%", detail: "\(Int(model.node.storage.usedGB)) / \(Int(model.node.storage.capacityGB)) GB", color: accent.ringColors(2).last!, seed: 2)
                    metric("СЕТЬ", value: model.isDemo ? "24.8" : "—", unit: "MB/s", detail: model.isDemo ? "из 125 MB/s · demo" : "Нет данных скорости", color: PulseTheme.green, seed: 3)
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private func metric(_ name: String, value: String, unit: String, detail: String, color: Color, seed: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 4, height: 4); T(name).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary) }
            HStack(alignment: .firstTextBaseline, spacing: 3) { T(value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit(); T(unit).font(.system(size: 10)).foregroundStyle(.secondary) }.fixedSize()
            T(detail).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            let values = seed == 3 && !model.isDemo ? [] : model.chartValues(seed)
            Chart(Array(values.indices), id: \.self) { index in
                let v = values[index]
                AreaMark(x: .value("t", index), y: .value("load", v)).foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                LineMark(x: .value("t", index), y: .value("load", v)).foregroundStyle(color.opacity(0.8)).lineStyle(.init(lineWidth: 1.3)).interpolationMethod(.catmullRom)
            }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: 0...1).frame(height: 27).localizedAccessibilityLabel("\(model.isDemo ? "Демонстрационный" : "Живой") график \(name)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var guests: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "Виртуальные машины", detail: "\(model.node.guests.filter(\.running).count) работают · \(model.node.guests.filter { !$0.running }.count) выключена")
            HStack {
                Picker(L10n.text("Статус", language: language), selection: $model.guestFilter) { T("Все").tag("Все"); T("Работают").tag("Работают"); T("Выключены").tag("Выключены") }.pickerStyle(.segmented).labelsHidden().frame(width: 247)
                Spacer(minLength: 5)
                HStack(spacing: 4) { Image(systemName: "magnifyingglass").foregroundStyle(.tertiary); LTextField("Поиск", text: $model.search).textFieldStyle(.plain) }.font(.system(size: 10)).padding(7).frame(width: 105).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }
            if model.filteredGuests.isEmpty { ContentUnavailableView.search(text: model.search).frame(height: 260) }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 15) {
                ForEach(model.filteredGuests) { guest in GuestCard(guest: guest, model: model) }
            }
        }
    }
    private var radar: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "Дисковый радар", detail: "\(model.node.storage.children.count) хранилищ")
            GlassCard {
                VStack(alignment: .leading, spacing: 15) {
                    SunburstDiskView(root: model.node.storage)
                    Divider().opacity(0.5)
                    HStack { TL("Свободно", systemImage: "circle.dotted").foregroundStyle(.secondary); Spacer(); T("\(Int(max(0, model.node.storage.capacityGB - model.node.storage.usedGB))) GB").fontWeight(.medium) }.font(.system(size: 11))
                    T(model.isDemo ? "Нажмите на сектор, чтобы раскрыть пул или машину." : model.node.storageNote ?? "Хранилища ноды").font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(3)
                }
            }
        }
    }
    private var insight: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 18)).foregroundStyle(PulseTheme.amber).frame(width: 36, height: 36).background(PulseTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) { T("Что случилось?").font(.system(size: 12, weight: .semibold)); T(model.isDemo ? "2 демонстрационных сценария · диски и службы" : "Проверить OOM, диски, службы и доступные свидетельства сбоев").font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer()
            Button { model.showIncidents() } label: { HStack { T("Разобраться"); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(PulseTheme.amber)
        }.padding(15).background(PulseTheme.amber.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(PulseTheme.amber.opacity(0.1), lineWidth: 0.75))
    }
    private var storagePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(title: "Карта хранилища", detail: "Ёмкость секторов · занятое место цветом")
            GlassCard { SunburstDiskView(root: model.node.storage).frame(maxWidth: .infinity).padding(15) }.frame(maxWidth: 650)
            ForEach(model.node.storage.children) { pool in
                GlassCard { HStack { TL(pool.name, systemImage: "internaldrive"); Spacer(); T("\(Int(pool.usedGB)) / \(Int(pool.capacityGB)) GB").foregroundStyle(.secondary); ProgressView(value: pool.fraction).frame(width: 150) } }
            }
        }
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 16) {
            T("Детерминированные проверки").font(.system(size: 20, weight: .semibold))
            T(model.isDemo ? "Демонстрационные инциденты. Проверки не используют ИИ." : "Проверки используют доступные API и явно показывают недостающие данные.").foregroundStyle(.secondary)
            LB("Запустить проверки · Что случилось?") { model.showIncidents() }.buttonStyle(.borderedProminent)
            ForEach(model.findings) { finding in
                GlassCard { HStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(PulseTheme.amber)
                    VStack(alignment: .leading, spacing: 8) { T(finding.title).font(.headline); T(finding.reason).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer()
                    LB(finding.solution) { model.solution = finding }.buttonStyle(.bordered)
                } }
            }
        }
    }
    private func guestDiagnostics(_ guest: Guest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            T("Диагностика · \(guest.name)").font(.title2.bold())
            TL(guest.running ? "Гостевая система работает" : "Гостевая система выключена", systemImage: guest.running ? "checkmark.circle" : "moon")
            T("\(model.isDemo ? "Мок-снимок" : "API-снимок"): CPU \(Int(guest.cpu * 100))%, RAM \(guest.memoryGB.formatted()) GB. Для установления причины сбоя нужны журналы и проверки гостевой ОС; статус сам по себе не доказывает наличие OOM или сетевой ошибки.").foregroundStyle(.secondary)
            LB("Готово") { model.diagnosticGuest = nil }.keyboardShortcut(.defaultAction)
        }.padding(30).frame(width: 500)
    }
    private func solution(_ finding: DiagnosticFinding) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            T(finding.title).font(.title2.bold())
            T(finding.reason).foregroundStyle(.secondary)
            T(finding.command).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            T("Выполните проверку в Shell ноды. Команда показывает данные и не меняет конфигурацию.").font(.caption).foregroundStyle(.secondary)
            HStack { LB("Скопировать команду") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(finding.command, forType: .string) }; Spacer(); LB("Готово") { model.solution = nil }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 560)
    }
}
#if PROXPULSE_XCODE
#Preview("Dashboard · Dark") { DashboardView(model: DashboardModel(), animate: false).frame(width: 1280, height: 900).preferredColorScheme(.dark) }
#Preview("Dashboard · Light") { DashboardView(model: DashboardModel(), animate: false).frame(width: 1280, height: 900).preferredColorScheme(.light) }
#endif
