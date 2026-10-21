import SwiftUI
import WidgetKit
import OSLog
import ProxPulseCore

public enum WidgetPalette {
    public static func color(_ accent: AccentChoice) -> Color {
        switch accent {
        case .blue: Color(red: 0.22, green: 0.57, blue: 1)
        case .neon: Color(red: 0.1, green: 0.86, blue: 0.92)
        case .emerald: Color(red: 0.15, green: 0.74, blue: 0.46)
        case .purple: Color(red: 0.65, green: 0.4, blue: 1)
        case .orange: Color(red: 1, green: 0.49, blue: 0.22)
        }
    }
    public static func ringColors(_ accent: AccentChoice, index: Int) -> [Color] {
        if index == 0 { return [color(accent), accent == .orange ? .yellow : .cyan] }
        if index == 1 {
            switch accent {
            case .blue: return [.purple, .pink]
            case .neon: return [.indigo, .cyan]
            case .emerald: return [.teal, .cyan]
            case .purple: return [.indigo, .pink]
            case .orange: return [.pink, .purple]
            }
        }
        switch accent {
        case .blue: return [.orange, .yellow]
        case .neon: return [.yellow, .green]
        case .emerald: return [.orange, .yellow]
        case .purple: return [.orange, .pink]
        case .orange: return [.red, .orange]
        }
    }
}
public struct PulseEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetSnapshot?
    public var isPlaceholder: Bool
    public init(date: Date, snapshot: WidgetSnapshot?, isPlaceholder: Bool = false) { self.date = date; self.snapshot = snapshot; self.isPlaceholder = isPlaceholder }
}
public struct PulseTimelineProvider: TimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> PulseEntry { .init(date: .now, snapshot: WidgetSnapshot(node: MockDataProvider.node, isDemo: true), isPlaceholder: true) }
    public func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .init(date: .now, snapshot: WidgetSnapshotStore.load()))
    }
    public func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()
        let preferences = WidgetSnapshotStore.loadPreferences()
        let matches = snapshot?.profileID == preferences?.profileID && snapshot?.date == preferences?.date && snapshot?.state == preferences?.state && snapshot?.isDemo == preferences?.isDemo
        Logger(subsystem: "dev.proxpulse.widget", category: "sync").info("Timeline loaded node=\(snapshot?.node ?? "none", privacy: .public) demo=\(snapshot?.isDemo ?? false, privacy: .public) state=\(snapshot?.state?.rawValue ?? "unknown", privacy: .public) suiteMatches=\(matches, privacy: .public)")
        completion(Timeline(entries: [PulseEntry(date: now, snapshot: snapshot)], policy: .after(now.addingTimeInterval(30))))
    }
}
public struct PulseWidgetView: View {
    public let entry: PulseEntry
    private let familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var family
    public init(entry: PulseEntry, family: WidgetFamily? = nil) { self.entry = entry; familyOverride = family }
    private var size: WidgetFamily { familyOverride ?? family }
    private var language: String { entry.snapshot?.language ?? "ru" }
    private func text(_ value: String) -> String { L10n.text(value, language: language) }
    public var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: size == .systemSmall ? 6 : size == .systemLarge ? 8 : 10) {
                    HStack(spacing: 6) {
                        Circle().fill(snapshot.state == .error ? .orange : snapshot.online == false ? .gray : .green).frame(width: 6, height: 6)
                        Text(snapshot.node).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if snapshot.isDemo { Text("DEMO").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                    }
                    if snapshot.state == .connecting || snapshot.state == .error {
                        Label(text(snapshot.state == .connecting ? "Подключение к серверу…" : "Ошибка подключения"), systemImage: snapshot.state == .connecting ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                            .font(.system(size: 10)).foregroundStyle(snapshot.state == .error ? .orange : .secondary).lineLimit(2)
                    }
                    if size == .systemSmall {
                        ringStack(snapshot).frame(maxWidth: .infinity)
                        HStack { Text("RAM \(Int(snapshot.memory * 100))%"); Spacer(); Text("Disk \(Int((snapshot.disk ?? 0) * 100))%") }.font(.system(size: 9)).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 16) {
                            ringStack(snapshot)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(text("Топ машин")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                ForEach(topGuests(snapshot)) { guest in
                                    HStack(spacing: 6) {
                                        Circle().fill(guest.running ? .green : .gray).frame(width: 4, height: 4)
                                        Text(guest.name).lineLimit(1)
                                        Spacer(minLength: 2)
                                        Text("\(Int(guest.cpu * 100))%").monospacedDigit().foregroundStyle(.secondary)
                                    }.font(.system(size: 10))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if size == .systemLarge {
                            Divider()
                            Text(text("Состояние хранилищ")).font(.system(size: 11, weight: .semibold))
                            ForEach(Array((snapshot.storage ?? []).prefix(3))) { pool in
                                HStack(spacing: 8) {
                                    Text(pool.name).font(.system(size: 10)).frame(width: 75, alignment: .leading).lineLimit(1)
                                    ProgressView(value: pool.fraction).tint(pool.fraction > 0.9 ? .red : .orange)
                                    Text("\(Int(pool.fraction * 100))%").font(.system(size: 9)).monospacedDigit()
                                }
                            }
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 8) {
                                ForEach(Array((snapshot.guests ?? []).prefix(6))) { guest in
                                    HStack(spacing: 5) { Circle().fill(guest.running ? .green : .gray).frame(width: 4, height: 4); Text(guest.name).lineLimit(1).font(.system(size: 9)) }
                                }
                            }
                        }
                    }
                    if entry.date.timeIntervalSince(snapshot.date) >= 300 && !entry.isPlaceholder {
                        Label(text("Снимок устарел"), systemImage: "clock.badge.exclamationmark").font(.system(size: 9)).foregroundStyle(.orange)
                    } else if size != .systemSmall {
                        HStack { Text(text("\(snapshot.running) работают · \((snapshot.guests ?? []).filter { !$0.running }.count) выключена")); Spacer(); Text(snapshot.date, style: .time) }.font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) { Label("ProxPulse", systemImage: "server.rack"); Text(text("Откройте ProxPulse, чтобы обновить снимок кластера.")).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.ultraThinMaterial, for: .widget)
        .preferredColorScheme(entry.snapshot?.appearance == "dark" ? .dark : entry.snapshot?.appearance == "light" ? .light : nil)
        .widgetURL(URL(string: "proxpulse://dashboard"))
    }
    private func topGuests(_ snapshot: WidgetSnapshot) -> [Guest] {
        Array((snapshot.guests ?? []).sorted {
            let a = $0.cpu + $0.memoryGB / max(1, $0.maxMemoryGB)
            let b = $1.cpu + $1.memoryGB / max(1, $1.maxMemoryGB)
            return a == b ? $0.id < $1.id : a > b
        }.prefix(3))
    }
    private func ringStack(_ snapshot: WidgetSnapshot) -> some View {
        let values = [snapshot.cpu, snapshot.memory, snapshot.disk ?? 0]
        let accent = AccentChoice(rawValue: snapshot.accent ?? "blue") ?? .blue
        return ZStack {
            ForEach(0..<3) { i in
                let colors = WidgetPalette.ringColors(accent, index: i)
                Circle().stroke(colors[0].opacity(0.13), lineWidth: 6).padding(CGFloat(i) * 10 + 3)
                Circle().trim(from: 0, to: min(1, max(0, values[i]))).stroke(AngularGradient(colors: colors, center: .center), style: .init(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).padding(CGFloat(i) * 10 + 3)
            }
            Text("\(Int(snapshot.cpu * 100))%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }.frame(width: size == .systemLarge ? 82 : 88, height: size == .systemLarge ? 82 : 88)
        .accessibilityLabel("CPU \(Int(snapshot.cpu * 100))%, RAM \(Int(snapshot.memory * 100))%, Disk \(Int((snapshot.disk ?? 0) * 100))%")
    }
}

public struct MachineWidgetView: View {
    public let entry: PulseEntry
    public init(entry: PulseEntry) { self.entry = entry }
    private var language: String { entry.snapshot?.language ?? "ru" }
    private func text(_ value: String) -> String { L10n.text(value, language: language) }
    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let snapshot = entry.snapshot,
               let key = snapshot.selectedMachineKey,
               let machine = snapshot.guests?.first(where: { MonitoringRules.guestKey($0) == key }) {
                HStack { Circle().fill(machine.running ? .green : .gray).frame(width: 7, height: 7); Text(machine.name).font(.headline).lineLimit(1); Spacer(); if snapshot.isDemo { Text("DEMO").font(.system(size: 8, weight: .bold)) } }
                HStack { Text("\(machine.kind == .lxc ? "CT" : "VM") \(machine.id)"); Spacer(); Text(machine.running ? "Online" : "Offline") }.font(.caption).foregroundStyle(.secondary)
                HStack { Text("CPU \(Int(machine.cpu*100))% · \(machine.cpuCount.map(String.init) ?? "—") vCPU"); Spacer() }.font(.system(size: 11, weight: .medium))
                Text("RAM \(TelemetryFormat.number(machine.memoryGB, language: language)) / \(TelemetryFormat.number(machine.maxMemoryGB, language: language)) GB").font(.system(size: 11))
                ProgressView(value: min(1, machine.memoryGB / max(0.001, machine.maxMemoryGB))).tint(.purple)
                HStack { Text(machine.ipAddresses?.first ?? "IP —").lineLimit(1); Spacer(); Text(TelemetryFormat.uptime(machine.uptimeSeconds)) }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                if snapshot.state == .error || entry.date.timeIntervalSince(snapshot.date) >= 300 { Text(text("Снимок устарел")).font(.caption2).foregroundStyle(.orange) }
            } else {
                Label(text("Машина"), systemImage: "shippingbox").font(.headline)
                Text(text("Выберите машину в настройках ProxPulse → Виджеты.")).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.ultraThinMaterial, for: .widget)
            .preferredColorScheme(entry.snapshot?.appearance == "dark" ? .dark : entry.snapshot?.appearance == "light" ? .light : nil)
            .widgetURL(URL(string: "proxpulse://dashboard"))
    }
}
