import SwiftUI
import WidgetKit
import ProxPulseWidgetUI

@main struct ProxPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxPulse.Cluster", provider: PulseTimelineProvider()) { PulseWidgetView(entry: $0) }
            .configurationDisplayName("ProxPulse")
            .description("CPU · RAM · Disk · VM / CT")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
