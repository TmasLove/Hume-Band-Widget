import WidgetKit
import SwiftUI

struct HumeEntry: TimelineEntry {
    var date: Date
    var metrics: HumeMetrics
    var configuration: HumeWidgetConfiguration
    /// Read from the App Group when the timeline is built, so every entry in
    /// one timeline agrees even if the user changes it mid-flight.
    var palette: ZonePalette = .classic
    /// Collapsed draws an icon-only strip inside the same frame.
    var isCollapsed: Bool = false
    /// Which page the widget is on — the closest a widget gets to a tab.
    var page: WidgetPage = .vitals
    /// True when we are showing a projection rather than a reading the band
    /// actually produced at this instant.
    var isProjected: Bool = false
}

struct HumeTimelineProvider: AppIntentTimelineProvider {
    private let service: any HumeBandService = HumeBandClient.live
    private let store = MetricsStore.shared

    func placeholder(in context: Context) -> HumeEntry {
        HumeEntry(date: .now, metrics: .placeholder, configuration: HumeWidgetConfiguration(), palette: ZoneSettings.current(), isCollapsed: WidgetLayoutSettings.current(), page: WidgetLayoutSettings.currentPage())
    }

    /// The gallery and the transient states need to be instant, so this never
    /// touches the network — cached value or placeholder only.
    func snapshot(for configuration: HumeWidgetConfiguration, in context: Context) async -> HumeEntry {
        HumeEntry(date: .now, metrics: store.load() ?? .placeholder, configuration: configuration, palette: ZoneSettings.current(), isCollapsed: WidgetLayoutSettings.current(), page: WidgetLayoutSettings.currentPage())
    }

    func timeline(for configuration: HumeWidgetConfiguration, in context: Context) async -> Timeline<HumeEntry> {
        let now = Date.now

        // One network call per timeline. If it fails we fall back to the last
        // good reading rather than showing an error card — a slightly old
        // heart rate is more useful than a broken widget.
        var latest: HumeMetrics
        if let fresh = try? await service.currentMetrics() {
            latest = fresh
            store.save(fresh, reloadWidgets: false) // already inside a reload
        } else {
            latest = store.load() ?? .placeholder
        }

        let projected = service.projection(
            from: latest,
            count: RefreshPolicy.entryCount,
            interval: RefreshPolicy.displayInterval
        )

        let palette = ZoneSettings.current()
        let collapsed = WidgetLayoutSettings.current()
        let page = WidgetLayoutSettings.currentPage()
        let entries = projected.enumerated().map { index, metrics in
            HumeEntry(
                date: now.addingTimeInterval(Double(index) * RefreshPolicy.displayInterval),
                metrics: metrics,
                configuration: configuration,
                palette: palette,
                isCollapsed: collapsed,
                page: page,
                isProjected: index > 0
            )
        }

        // `.after` rather than `.atEnd` so the next real fetch is pinned to the
        // moment the projection runs out, not left to the system's discretion.
        let next = now.addingTimeInterval(RefreshPolicy.horizon)
        return Timeline(entries: entries, policy: .after(next))
    }

    func recommendations() -> [AppIntentRecommendation<HumeWidgetConfiguration>] {
        FocusMetric.allCases.map { metric in
            let configuration = HumeWidgetConfiguration()
            configuration.focus = metric
            return AppIntentRecommendation(
                intent: configuration,
                description: FocusMetric.caseDisplayRepresentations[metric]?.title ?? "Hume Band"
            )
        }
    }
}
