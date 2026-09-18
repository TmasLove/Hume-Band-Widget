import Foundation

/// Everything the app and the widget need from a Hume Band 2.0.
///
/// Both the mock and the eventual real implementation sit behind this, so
/// swapping in real credentials is a one-line change in `HumeBandClient.live`.
protocol HumeBandService: Sendable {
    /// The most recent reading the band has produced.
    func currentMetrics() async throws -> HumeMetrics

    /// A short forward projection used to fill a widget timeline.
    ///
    /// WidgetKit renders pre-computed entries without waking the extension, so
    /// projecting the next few minutes at `interval` spacing is what lets the
    /// widget visibly move every 10 seconds on a handful of refreshes a day.
    func projection(from metrics: HumeMetrics, count: Int, interval: TimeInterval) -> [HumeMetrics]
}

enum HumeBandError: LocalizedError {
    case notConfigured
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No Hume Band API key configured."
        case .transport(let detail):
            detail
        }
    }
}

// MARK: - Mock transport

/// Simulates the band until real API keys exist.
///
/// It is deterministic on `capturedAt`, which matters for two reasons: the
/// widget and the app agree on what "now" looks like without sharing state,
/// and snapshot tests are reproducible.
struct MockHumeBandService: HumeBandService {
    /// Stand-in for the real endpoint. Nothing calls it yet; it documents the
    /// shape the live client will use so the swap is mechanical.
    static let mockEndpoint = URL(string: "https://mock.hume.local/v2/band/metrics")!

    var restingHeartRate: Int = 58
    var temperatureBaseline: Double = 33.2

    func currentMetrics() async throws -> HumeMetrics {
        synthesise(at: .now)
    }

    func projection(from metrics: HumeMetrics, count: Int, interval: TimeInterval) -> [HumeMetrics] {
        (0..<max(1, count)).map { step in
            synthesise(at: metrics.capturedAt.addingTimeInterval(Double(step) * interval))
        }
    }

    /// Layered slow and fast sine waves give something that reads like a real
    /// biosignal — a circadian-ish drift plus breath-rate ripple — instead of
    /// random noise, which would make the bars jitter meaninglessly.
    private func synthesise(at date: Date) -> HumeMetrics {
        let t = date.timeIntervalSince1970
        let slow = sin(t / 900)          // ~15 min drift
        let fast = sin(t / 37)           // ~37 s ripple
        let drift = sin(t / 5400)        // ~90 min cycle

        // Exertion episodes. Without these the baseline waves alone span only
        // 47–97 BPM against a resting rate of 58 — a reserve of 39, where the
        // `.high` band starts at 55. Measured over 48 hours at the widget's
        // own cadence, the red heart-rate and skin-temperature states were
        // simply unreachable, so a state the UI is built to show could never
        // appear. A narrow power of a sine gives a few sharp peaks a day,
        // which is what a workout looks like to a wrist sensor.
        let surge = pow(max(0, sin(t / 3000)), 6)

        let hr = Double(restingHeartRate) + 14 + (slow * 12) + (fast * 4) + (drift * 9)
            + (surge * 58)
        let stress = 42 + (drift * 26) + (slow * 9) + (surge * 22)
        let temp = temperatureBaseline + (drift * 0.55) + (slow * 0.2) + (surge * 0.75)
        let activity = 30 + (slow * 24) + (fast * 8) + (surge * 55)

        return HumeMetrics(
            heartRate: Int(hr.rounded()),
            stress: Int(min(100, max(0, stress)).rounded()),
            skinTemperature: (temp * 10).rounded() / 10,
            activity: Int(min(100, max(0, activity)).rounded()),
            restingHeartRate: restingHeartRate,
            temperatureBaseline: temperatureBaseline,
            capturedAt: date,
            sleep: Self.synthesiseSleep(for: date, restingHeartRate: restingHeartRate)
        )
    }

    /// Builds a plausible night as a *timeline*, then lets every total fall
    /// out of it. Keyed to the calendar day rather than the clock, so "last
    /// night" stays put instead of drifting every ten seconds.
    ///
    /// The shape follows real sleep architecture rather than random noise:
    /// roughly 90-minute cycles, deep sleep concentrated in the first third
    /// of the night and fading, REM starting short and lengthening toward
    /// morning, with brief awakenings between cycles.
    static func synthesiseSleep(for date: Date, restingHeartRate: Int) -> SleepSummary {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let seed = Double(cal.ordinality(of: .day, in: .era, for: day) ?? 0)
        let wobble = { (phase: Double) in sin(seed * 1.7 + phase) }

        // One factor for the whole night, not just per-cycle jitter. Summing
        // five independently jittered cycles averaged the variation out: over
        // 365 nights the quality score only ever spanned 83–85 and efficiency
        // 94–97%, so the elevated and high sleep bands were unreachable and
        // the suggestions list showed the same single card every day.
        let nightly = wobble(0.0)                       // -1...1
        let lengthScale = 1 + nightly * 0.34            // 0.66...1.34
        let deepScale = 1 + nightly * 0.40
        // REM needs its own phase. `lengthScale` scales every stage equally,
        // so it moves totals without moving *shares* — REM's share of total
        // sleep stayed near 25% on all 365 nights and the "give REM more
        // room" suggestion could never fire.
        let remScale = 1 + wobble(0.9) * 0.48
        // A poor night is a broken one, not merely a short one.
        let fragmentation = max(0, -nightly)

        let cycles = 5
        var intervals: [StageInterval] = []
        var cursor = cal.date(bySettingHour: 23, minute: 20, second: 0, of: day)?
            .addingTimeInterval(-86400) ?? day
        cursor = cursor.addingTimeInterval(wobble(0.3) * 40 * 60)   // bedtime varies

        func add(_ stage: SleepSummary.Stage, _ minutes: Double) {
            guard minutes > 0.5 else { return }
            intervals.append(StageInterval(stage: stage, start: cursor, duration: minutes * 60))
            cursor = cursor.addingTimeInterval(minutes * 60)
        }

        add(.awake, (6 + wobble(1.0) * 3) * (1 + fragmentation * 4))   // settling
        for c in 0..<cycles {
            let t = Double(c) / Double(cycles - 1)              // 0 early -> 1 late
            let jitter = wobble(Double(c) * 1.3)
            add(.light, (22 + jitter * 6) * lengthScale)
            // Deep dominates early and all but vanishes by morning.
            add(.deep,  max(0, (34 * (1 - t) * (1 - t) + jitter * 4) * lengthScale * deepScale))
            add(.light, (16 + jitter * 5) * lengthScale)
            // REM does the opposite.
            add(.rem,   (8 + 26 * t + jitter * 4) * lengthScale * remScale)
            if c < cycles - 1 {
                add(.awake, max(0, (3 + jitter * 4) * (1 + fragmentation * 6)))
            }
        }
        add(.light, (12 + wobble(2.2) * 6) * lengthScale)

        let asleep = intervals.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
        let awake  = intervals.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration }
        let deep   = intervals.filter { $0.stage == .deep }.reduce(0) { $0 + $1.duration }

        // A stand-in for Hume's composite: duration against a 7h target, the
        // deep share, and continuity — roughly what their definition says.
        let durationScore = min(1, asleep / (7 * 3600))
        let deepScore = min(1, (deep / max(asleep, 1)) / 0.20)
        let continuity = 1 - min(1, awake / max(asleep, 1) / 0.15)
        let quality = (durationScore * 0.5 + deepScore * 0.3 + continuity * 0.2) * 100

        return SleepSummary(
            intervals: intervals,
            restingHeartRate: restingHeartRate - 6 + Int((wobble(4.2) * 3).rounded()),
            hrv: 58 + Int((wobble(5.1) * 14).rounded()),
            qualityScore: Int(min(100, max(0, quality)).rounded()),
            sleepDebt: max(0, (7 * 3600) - asleep)
        )
    }

}

// MARK: - Live transport (awaiting credentials)

/// The real client. It deliberately fails loudly rather than silently falling
/// back to mock data, so a missing key is obvious in testing instead of
/// shipping fake numbers to a user looking at their own health.
///
/// The endpoint shape here is a guess: there is no verified public Hume Band
/// 2.0 API reference behind it. Check it against the real documentation
/// before wiring a key in.
struct LiveHumeBandService: HumeBandService {
    var apiKey: String?
    var baseURL = URL(string: "https://api.hume.example/v2")!
    var session: URLSession = .shared

    func currentMetrics() async throws -> HumeMetrics {
        guard let apiKey, !apiKey.isEmpty else { throw HumeBandError.notConfigured }

        var request = URLRequest(url: baseURL.appending(path: "band/metrics"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Widgets run on a tight wall-clock budget; a hung socket is worse
        // than showing the last cached reading.
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HumeBandError.transport("Band API returned an unexpected response.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HumeMetrics.self, from: data)
    }

    func projection(from metrics: HumeMetrics, count: Int, interval: TimeInterval) -> [HumeMetrics] {
        // The real band does not forecast. Hold the last real value steady and
        // only advance `capturedAt`, so the widget ages the reading honestly
        // rather than inventing movement.
        (0..<max(1, count)).map { step in
            var copy = metrics
            copy.capturedAt = metrics.capturedAt.addingTimeInterval(Double(step) * interval)
            return copy
        }
    }
}

// MARK: - Selection
