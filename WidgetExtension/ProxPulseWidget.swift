import SwiftUI
import WidgetKit
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
        StaticConfiguration(kind: "ProxPulse.Machine", provider: PulseTimelineProvider()) { MachineWidgetView(entry: $0) }
            .configurationDisplayName("ProxPulse · Container / VM")
            .description("Status · vCPU · RAM · IP · Uptime. Select a machine in ProxPulse Settings.")
            .supportedFamilies([.systemMedium])
    }
}
@main struct ProxPulseWidget: WidgetBundle {
    var body: some Widget { ClusterWidget(); MachineWidget() }
}
