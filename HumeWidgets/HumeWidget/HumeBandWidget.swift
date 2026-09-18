import SwiftUI
import WidgetKit

struct HumeBandWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: HumeEntry

    var body: some View {
        content
            .environment(\.zonePalette, entry.palette)
            // Tapping anywhere that is not the refresh button opens the
            // in-app dashboard, deep-linked to whichever metric is focused.
            // Land on whatever the widget was showing. From the sleep page
            // that means the sleep tab with the timeline already opened —
            // tapping a chart that is too small to read should give you the
            // big one, not the dashboard's front page.
            .widgetURL(URL(string: entry.page == .sleep
                           ? "\(HumeConfig.urlScheme)://dashboard?tab=sleep&graph=expanded"
                           : "\(HumeConfig.urlScheme)://dashboard?metric=\(entry.configuration.focus.rawValue)"))
            // Stale data is dimmed rather than hidden: the user still sees
            // their last reading, but it no longer reads as live.
            .opacity(entry.metrics.isStale(asOf: entry.date) ? 0.55 : 1)
            .animation(.snappy(duration: 0.28), value: entry.metrics)
    }

    @ViewBuilder
    private var content: some View {
        // Collapsed is one layout for every family: the point of folding is
        // that the widget stops competing for attention, so it should look
        // the same however large the tile happens to be.
        if entry.isCollapsed {
            CollapsedHumeView(entry: entry)
        } else if entry.page == .sleep {
            SleepHumeView(entry: entry)
        } else {
            switch family {
            case .systemSmall:            SmallHumeView(entry: entry)
            case .systemMedium:           MediumHumeView(entry: entry)
            case .systemLarge,
                 .systemExtraLarge:       LargeHumeView(entry: entry)
            default:                      SmallHumeView(entry: entry)
            }
        }
    }
}

struct HumeBandWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: HumeConfig.widgetKind,
            intent: HumeWidgetConfiguration.self,
            provider: HumeTimelineProvider()
        ) { entry in
            HumeBandWidgetEntryView(entry: entry)
                .containerBackground(Palette.card, for: .widget)
        }
        .configurationDisplayName("Hume Band")
        .description("Live heart rate, stress, skin temperature and activity.")
        // macOS has no lock screen, so the accessory families do not exist
        // here; extra-large is Mac/iPad only and worth supporting.
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
        ])
    }
}

@main
struct HumeWidgetBundle: WidgetBundle {
    var body: some Widget {
        HumeBandWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    HumeBandWidget()
} timeline: {
    HumeEntry(date: .now, metrics: .placeholder, configuration: HumeWidgetConfiguration(), palette: .classic, isCollapsed: false, page: .vitals)
}

#Preview("Medium", as: .systemMedium) {
    HumeBandWidget()
} timeline: {
    HumeEntry(date: .now, metrics: .placeholder, configuration: HumeWidgetConfiguration(), palette: .classic, isCollapsed: false, page: .vitals)
}

#Preview("Large", as: .systemLarge) {
    HumeBandWidget()
} timeline: {
    HumeEntry(date: .now, metrics: .placeholder, configuration: HumeWidgetConfiguration(), palette: .classic, isCollapsed: false, page: .vitals)
}
