import AppIntents
import WidgetKit

/// Which metric the small widget puts front and centre.
enum FocusMetric: String, AppEnum, CaseIterable {
    case heartRate, stress, temperature, activity

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Focus Metric")

    static let caseDisplayRepresentations: [FocusMetric: DisplayRepresentation] = [
        .heartRate:   DisplayRepresentation(title: "Heart Rate", image: .init(systemName: "heart.fill")),
        .stress:      DisplayRepresentation(title: "Stress", image: .init(systemName: "waveform.path.ecg")),
        .temperature: DisplayRepresentation(title: "Skin Temperature", image: .init(systemName: "thermometer.medium")),
        .activity:    DisplayRepresentation(title: "Activity", image: .init(systemName: "figure.run")),
    ]

    var kind: MetricReading.Kind {
        switch self {
        case .heartRate:   .heartRate
        case .stress:      .stress
        case .temperature: .temperature
        case .activity:    .activity
        }
    }
}

struct HumeWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hume Band"
    static let description = IntentDescription("Live heart rate, stress, skin temperature and activity from your Hume Band 2.0.")

    @Parameter(title: "Focus Metric", default: .heartRate)
    var focus: FocusMetric
}

/// The tap target on the widget's refresh control.
///
/// This is the interactive path: it runs in-process, does one fetch, writes
/// the shared cache, and lets `reloadTimelines` redraw. It exists so the user
/// can force a reading on demand without the widget having to poll.
struct RefreshMetricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Hume Band"
    static let description = IntentDescription("Pull the latest reading from your band.")
    /// Keeps the tap inside the widget instead of bouncing the user to the app.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        if let metrics = try? await HumeBandClient.live.currentMetrics() {
            MetricsStore.shared.save(metrics)
        }
        return .result()
    }
}

/// The collapse control on the widget.
///
/// Runs in-process and does not open the app, so the widget folds and unfolds
/// in place. `reloadAllTimelines` is what redraws it — a widget cannot mutate
/// its own view state between renders.
struct ToggleWidgetLayoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Collapse or expand the Hume widget"
    static let description = IntentDescription("Switch between the full readout and a compact row of icons.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetLayoutSettings.toggle()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Steps the widget between its Vitals and Sleep pages.
struct SwitchWidgetPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch the Hume widget page"
    static let description = IntentDescription("Step between live vitals and last night's sleep.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetLayoutSettings.advancePage()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
