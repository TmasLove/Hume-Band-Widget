import Foundation

/// The green / yellow / red banding shared by every metric.
///
/// Colour alone never carries the meaning: each zone also has a `label` and a
/// distinct `symbol`, so the widget stays readable for colour-blind users and
/// in the greyscale accessibility rendering mode.
enum MetricZone: String, Sendable, CaseIterable {
    case optimal
    case elevated
    case high

    var label: String {
        switch self {
        case .optimal:  "Optimal"
        case .elevated: "Elevated"
        case .high:     "High"
        }
    }

    var symbol: String {
        switch self {
        case .optimal:  "checkmark.circle.fill"
        case .elevated: "exclamationmark.circle.fill"
        case .high:     "exclamationmark.triangle.fill"
        }
    }

}

/// One metric, already reduced to everything a view needs to draw it.
///
/// The provider builds these once per timeline entry so the view body stays
/// pure layout — no arithmetic, no date maths, no formatting during render.
struct MetricReading: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case heartRate, stress, temperature, activity
    }

    var kind: Kind
    var title: String
    var shortTitle: String
    var symbol: String
    var value: String
    var unit: String
    /// 0...1, how full the bar is drawn.
    var fraction: Double
    var zone: MetricZone

    var id: String { kind.rawValue }

    var accessibilityDescription: String {
        "\(title): \(value) \(unit). \(zone.label)."
    }
}

extension HumeMetrics {
    /// Heart rate banded against the user's own resting rate rather than a
    /// fixed population number, so the zones mean something per-person.
    var heartRateReading: MetricReading {
        let reserve = Double(heartRate - restingHeartRate)
        let zone: MetricZone = switch reserve {
        case ..<25:  .optimal
        case ..<55:  .elevated
        default:     .high
        }
        return MetricReading(
            kind: .heartRate,
            title: "Heart Rate",
            shortTitle: "HR",
            symbol: "heart.fill",
            value: "\(heartRate)",
            unit: "BPM",
            fraction: normalise(Double(heartRate), from: Double(restingHeartRate), to: Double(restingHeartRate) + 110),
            zone: zone
        )
    }

    var stressReading: MetricReading {
        let zone: MetricZone = switch stress {
        case ..<40:  .optimal
        case ..<70:  .elevated
        default:     .high
        }
        return MetricReading(
            kind: .stress,
            title: "Stress",
            shortTitle: "Stress",
            symbol: "waveform.path.ecg",
            value: "\(stress)",
            unit: "/100",
            fraction: normalise(Double(stress), from: 0, to: 100),
            zone: zone
        )
    }

    /// Skin temperature is only meaningful as a deviation from the wearer's
    /// own baseline, and it matters in both directions, so the zone uses the
    /// absolute deviation.
    var temperatureReading: MetricReading {
        let delta = skinTemperature - temperatureBaseline
        let zone: MetricZone = switch abs(delta) {
        case ..<0.4: .optimal
        case ..<1.0: .elevated
        default:     .high
        }
        return MetricReading(
            kind: .temperature,
            title: "Skin Temp",
            shortTitle: "Temp",
            symbol: "thermometer.medium",
            value: delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())),
            unit: "°C",
            fraction: normalise(abs(delta), from: 0, to: 1.6),
            zone: zone
        )
    }

    /// Activity is the one metric where "high" is not a warning, so it is
    /// always drawn in the optimal tint and relies on the bar for magnitude.
    var activityReading: MetricReading {
        MetricReading(
            kind: .activity,
            title: "Activity",
            shortTitle: "Move",
            symbol: "figure.run",
            value: "\(activity)",
            unit: "/100",
            fraction: normalise(Double(activity), from: 0, to: 100),
            zone: .optimal
        )
    }

    var allReadings: [MetricReading] {
        [heartRateReading, stressReading, temperatureReading, activityReading]
    }

    private func normalise(_ value: Double, from lower: Double, to upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}
