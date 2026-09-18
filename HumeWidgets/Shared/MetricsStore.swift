import Foundation
import WidgetKit

/// The single cache the app writes and the widget reads.
///
/// The widget extension is memory-constrained and is killed aggressively, so
/// it never holds state between renders — it reads this file, draws, and
/// exits. The app is the only writer.
struct MetricsStore: Sendable {
    static let shared = MetricsStore()

    private let filename = "latest-metrics.json"

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HumeConfig.appGroup)
    }

    private var fileURL: URL? {
        containerURL?.appending(path: filename)
    }

    func load() -> HumeMetrics? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? HumeJSON.decoder.decode(HumeMetrics.self, from: data)
    }

    /// Writes the reading and asks WidgetKit to re-render.
    ///
    /// `reloadTimelines` is the only refresh path that does not spend the
    /// widget's own background budget, so every genuinely-new band reading
    /// should come through here rather than through a shorter timeline.
    func save(_ metrics: HumeMetrics, reloadWidgets: Bool = true) {
        guard let fileURL else { return }
        guard let data = try? HumeJSON.encoder.encode(metrics) else { return }
        // Atomic so a widget render mid-write never sees a truncated file.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        if reloadWidgets {
            WidgetCenter.shared.reloadTimelines(ofKind: HumeConfig.widgetKind)
        }
    }
}
