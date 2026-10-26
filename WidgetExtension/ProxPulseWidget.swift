import SwiftUI
import WidgetKit
import AppIntents
import ProxPulseWidgetUI

struct ClusterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxPulse.Cluster", provider: PulseTimelineProvider()) { PulseWidgetView(entry: $0) }
            .configurationDisplayName("ProxPulse")
            .description("CPU · RAM · Disk · VM / CT")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
struct MachineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProxPulse.Machine", intent: SelectMachineIntent.self, provider: MachineTimelineProvider()) { entry in
            MachineWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot), machineKey: entry.machineKey)
        }
            .configurationDisplayName("ProxPulse · Container / VM")
            .description("Status · vCPU · RAM · IP · Uptime. Right-click → Edit Widget to choose a machine for each widget.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
@main struct ProxPulseWidget: WidgetBundle {
    var body: some Widget { ClusterWidget(); MachineWidget() }
}

struct WidgetIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [ProxPulseIntentsPackage.self] }
}
