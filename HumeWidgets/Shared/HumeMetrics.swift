import Foundation

/// A single point-in-time reading from a Hume Band 2.0.
///
/// `Codable` so it can be cached in the shared App Group container, and
/// `Sendable` so it can cross the actor boundary between the band transport,
/// the widget timeline provider, and the UI without copying warnings.
struct HumeMetrics: Codable, Sendable, Equatable, Hashable {
    /// Beats per minute.
    var heartRate: Int
    /// Normalised stress score, 0...100.
    var stress: Int
    /// Skin temperature in celsius.
    var skinTemperature: Double
    /// Activity intensity, 0...100 (derived from accelerometer + HR reserve).
    var activity: Int
    /// The user's resting heart rate, used to place `heartRate` in a zone.
    var restingHeartRate: Int
    /// The user's skin-temperature baseline, used to place `skinTemperature` in a zone.
    var temperatureBaseline: Double
    /// When the band produced this reading.
    var capturedAt: Date

    /// Last night's sleep. Optional so a cache written before this field
    /// existed still decodes instead of throwing the whole reading away.
    var sleep: SleepSummary?

    /// True when this came off the band via the iPhone relay rather than
    /// being synthesised. Defaulted so older caches still decode.
    var isLive: Bool = false

    /// Stress has no Apple Health type, so even a live reading carries a
    /// simulated value for it. Worth saying out loud on screen rather than
    /// letting one fake number hide among real ones.
    var stressIsSimulated: Bool = true

    /// Age of the reading. Used to dim the widget when data has gone stale.
    func age(asOf now: Date = .now) -> TimeInterval {
        max(0, now.timeIntervalSince(capturedAt))
    }

    /// Readings older than this are shown as stale rather than presented as live.
    static let stalenessThreshold: TimeInterval = 15 * 60

    func isStale(asOf now: Date = .now) -> Bool {
        age(asOf: now) > Self.stalenessThreshold
    }

    /// Shown in the widget before the band has ever reported, and in Xcode previews.
    static let placeholder = HumeMetrics(
        heartRate: 68,
        stress: 34,
        skinTemperature: 33.4,
        activity: 22,
        restingHeartRate: 58,
        temperatureBaseline: 33.2,
        capturedAt: .now,
        sleep: .placeholder
    )
}


/// One continuous stretch of a single stage during the night.
struct StageInterval: Codable, Sendable, Equatable, Hashable, Identifiable {
    var stage: SleepSummary.Stage
    var start: Date
    var duration: TimeInterval

    var id: Date { start }
    var end: Date { start.addingTimeInterval(duration) }
}

/// Last night, in Hume's own vocabulary.
///
/// The metric names and definitions follow Hume Health's published Sleep
/// Architecture Metrics rather than Apple's Health app, which differs in ways
/// that matter: Hume says **Light**, not "Core"; it leads with stage
/// *percentages*; and it defines resting heart rate and HRV as measured
/// during deep sleep specifically.
///
/// One subtlety carried over exactly: Deep, REM and Light are percentages of
/// **total sleep**, while Awake is a percentage of the whole **sleep period**.
/// They have different denominators, so they do not sum to 100.
///
/// `intervals` is the single source of truth. Every total, percentage and
/// clock time is derived from it, so the hypnogram and the summary figures
/// cannot drift apart.
struct SleepSummary: Codable, Sendable, Equatable, Hashable {
    enum Stage: String, Codable, Sendable, CaseIterable, Identifiable {
        case awake, rem, light, deep
        var id: String { rawValue }

        var title: String {
            switch self {
            case .awake: "Awake"
            case .rem:   "REM"
            case .light: "Light"
            case .deep:  "Deep"
            }
        }

        var detail: String {
            switch self {
            case .awake: "Fragmentation"
            case .rem:   "Cognitive recovery"
            case .light: "Transitional"
            case .deep:  "Physical recovery"
            }
        }

        /// Lane order in the hypnogram, shallowest at the top — the
        /// convention every sleep chart uses.
        var lane: Int {
            switch self {
            case .awake: 0
            case .rem:   1
            case .light: 2
            case .deep:  3
            }
        }
    }

    var intervals: [StageInterval]
    var restingHeartRate: Int
    var hrv: Int
    var qualityScore: Int
    var sleepDebt: TimeInterval

    var bedtime: Date { intervals.first?.start ?? .now }
    var wakeTime: Date { intervals.last?.end ?? .now }

    /// Seconds spent in each stage, summed from the timeline.
    var durations: [Stage: TimeInterval] {
        intervals.reduce(into: [:]) { $0[$1.stage, default: 0] += $1.duration }
    }

    /// Hume's "Total Sleep Duration" — all stages except awake.
    var asleep: TimeInterval {
        intervals.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    /// The whole sleep period, awake time included.
    var inBed: TimeInterval { intervals.reduce(0) { $0 + $1.duration } }

    /// Deep / REM / Light are shares of total sleep; Awake is a share of the
    /// whole period. Hume defines them with those different denominators.
    func percentage(_ stage: Stage) -> Int {
        let value = durations[stage] ?? 0
        let base = stage == .awake ? inBed : asleep
        guard base > 0 else { return 0 }
        return Int((value / base * 100).rounded())
    }

    var efficiency: Int {
        guard inBed > 0 else { return 0 }
        return Int((asleep / inBed * 100).rounded())
    }

    /// Banded on the quality score, which is the composite Hume leads with.
    var zone: MetricZone {
        switch qualityScore {
        case 80...:   .optimal
        case 60..<80: .elevated
        default:      .high
        }
    }

    var formattedDuration: String { Self.format(asleep) }

    /// Rounds to the nearest whole minute *before* splitting into hours and
    /// minutes. Truncating the remainder instead makes independently
    /// formatted figures stop adding up — 6h 9.6m asleep and 50.4m of debt
    /// print as "6h 9m" and "50m", which is 6h 59m against a 7-hour target.
    static func format(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static let placeholder = MockHumeBandService.synthesiseSleep(for: .now, restingHeartRate: 58)
}
