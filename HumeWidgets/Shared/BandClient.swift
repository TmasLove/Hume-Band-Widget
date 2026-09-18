import Foundation

// Which service the app and widget read from. Kept apart from the transports
// themselves because it reaches into `MetricsStore`, which is a Mac and
// widget concern — the iPhone companion shares the model and the wire
// format, not this.

/// Prefers what the iPhone relayed over anything synthesised.
///
/// This exists because of a real bug: the relay wrote a measured reading to
/// the shared cache and the dashboard's ten-second poll overwrote it with
/// mock data moments later. Every surface kept showing invented numbers
/// while the relay reported success.
///
/// Once a real reading has arrived it is **never** replaced by a simulated
/// one, even when it goes stale. An hour-old measurement of your actual
/// heart is worth more than a fresh invention of it, and the UI already
/// dims a reading as it ages.
struct RelayBackedService: HumeBandService {
    var fallback: any HumeBandService
    var store = MetricsStore.shared

    func currentMetrics() async throws -> HumeMetrics {
        if let cached = store.load(), cached.isLive { return cached }
        return try await fallback.currentMetrics()
    }

    func projection(from metrics: HumeMetrics, count: Int, interval: TimeInterval) -> [HumeMetrics] {
        guard metrics.isLive else {
            return fallback.projection(from: metrics, count: count, interval: interval)
        }
        // Real data is not forecast. Hold the value and let `capturedAt`
        // advance so the widget ages it honestly instead of inventing drift.
        return (0..<max(1, count)).map { step in
            var copy = metrics
            copy.capturedAt = metrics.capturedAt.addingTimeInterval(Double(step) * interval)
            return copy
        }
    }
}

enum HumeBandClient {
    /// Simulated until the phone sends something real, then real for good.
    static let live: any HumeBandService = RelayBackedService(fallback: MockHumeBandService())
}
