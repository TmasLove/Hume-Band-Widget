import SwiftUI
import Observation

/// Drives the in-app dashboard.
///
/// True 10-second polling is allowed here because the app is in the
/// foreground and the user is looking at it. The timer is torn down the
/// moment the view disappears or the app backgrounds, which is what keeps
/// this from being a battery drain.
@MainActor
@Observable
final class MetricsViewModel {
    private(set) var metrics: HumeMetrics
    private(set) var history: [HumeMetrics] = []
    private(set) var errorMessage: String?
    private(set) var isPolling = false

    /// Matches the widget's display cadence so the two never disagree on screen.
    private let pollInterval = RefreshPolicy.displayInterval
    private let service: any HumeBandService
    private let store = MetricsStore.shared
    private var task: Task<Void, Never>?

    /// Keeps the chart bounded; ten minutes at a ten-second cadence.
    private let historyLimit = 60

    init(service: any HumeBandService = HumeBandClient.live) {
        self.service = service
        self.metrics = MetricsStore.shared.load() ?? .placeholder
    }

    func startPolling() {
        guard task == nil else { return }
        isPolling = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 10))
            }
        }
    }

    func stopPolling() {
        task?.cancel()
        task = nil
        isPolling = false
    }

    func refresh() async {
        do {
            let fresh = try await service.currentMetrics()
            metrics = fresh
            history.append(fresh)
            if history.count > historyLimit {
                history.removeFirst(history.count - historyLimit)
            }
            errorMessage = nil
            // Writing here is what keeps the widget in step with the app; it
            // also triggers a free widget reload.
            store.save(fresh)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
