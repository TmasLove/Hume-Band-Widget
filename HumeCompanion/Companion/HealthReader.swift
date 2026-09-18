import Foundation
import HealthKit
import Observation

/// Reads your Hume Band data out of Apple Health.
///
/// HealthKit is Apple's API, not Hume's. The band writes into it, so reading
/// your own readings back needs no vendor account, key or blessing — which
/// is the whole reason this route exists.
///
/// What it cannot get: **stress**. Hume computes that in their own app and
/// there is no HealthKit type for it, so it is the one metric this cannot
/// make real. Everything sent from here is measured; nothing is invented.
@MainActor
@Observable
final class HealthReader {
    private let store = HKHealthStore()

    private(set) var authorised = false
    private(set) var status = "Not connected to Health yet."
    private(set) var lastRead: Date?

    /// Only the types the band actually produces. Asking for more than is
    /// needed is a worse consent prompt for no benefit.
    private var readTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        for id: HKQuantityTypeIdentifier in [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .stepCount, .appleSleepingWristTemperature,
        ] {
            if let q = HKObjectType.quantityType(forIdentifier: id) { t.insert(q) }
        }
        return t
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Fires whenever Health gains new data of a type we care about.
    private var observers: [HKObserverQuery] = []

    /// Ask iOS to wake the app when new samples land, and watch for them
    /// while the app is open.
    ///
    /// **What "live" honestly means here.** Three things gate it, none of
    /// them ours: Hume decides how often the band syncs into Health; iOS
    /// throttles background delivery to roughly hourly for most types
    /// regardless of the frequency requested; and background wake stops
    /// entirely if the app is force-quit. While the app is open updates
    /// arrive as soon as Health has them.
    func startWatching(onUpdate: @escaping @Sendable () -> Void) async {
        guard authorised else { return }
        let types: [HKSampleType] = [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
        ].compactMap { $0 }

        for type in types {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                onUpdate()
                // Must be called or iOS stops delivering.
                completion()
            }
            store.execute(q)
            observers.append(q)
            // `.immediate` is a request, not a promise — iOS coalesces most
            // types to about once an hour in the background.
            try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
        status = "Watching Health. New readings will send on their own."
    }

    func stopWatching() {
        observers.forEach { store.stop($0) }
        observers.removeAll()
    }

    func requestAuthorisation() async {
        guard isAvailable else {
            status = "This device has no Health data."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorised = true
            status = "Health access granted. Reading your latest data…"
        } catch {
            status = "Health access failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reading

    /// The most recent sample of a quantity type, in the unit given.
    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    /// Steps since midnight, as a stand-in for the band's activity score —
    /// scaled against a 10,000-step day. Derived, and labelled as such.
    private func stepsToday() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        return await withCheckedContinuation { cont in
            let p = HKQuery.predicateForSamples(withStart: start, end: .now)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: p,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(q)
        }
    }

    /// Last night's sleep, rebuilt from HealthKit's stage samples.
    private func lastNightSleep() async -> SleepSummary? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        // A generous window: the "night" is whatever contiguous run of
        // samples ended most recently, not a fixed clock range, because
        // people sleep at odd hours.
        let since = Calendar.current.date(byAdding: .hour, value: -36, to: .now)!
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let p = HKQuery.predicateForSamples(withStart: since, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: p, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return nil }

        var intervals: [StageInterval] = []
        for s in samples {
            guard let stage = Self.stage(for: s.value) else { continue }
            intervals.append(StageInterval(stage: stage, start: s.startDate,
                                           duration: s.endDate.timeIntervalSince(s.startDate)))
        }
        guard !intervals.isEmpty else { return nil }

        // Keep only the most recent block — anything separated by more than
        // three hours is a different night (or a nap).
        intervals.sort { $0.start < $1.start }
        var block: [StageInterval] = [intervals.removeLast()]
        while let prev = intervals.last,
              block[0].start.timeIntervalSince(prev.end) < 3 * 3600 {
            block.insert(prev, at: 0)
            intervals.removeLast()
        }

        let asleep = block.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
        let awake = block.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration }
        let deep = block.filter { $0.stage == .deep }.reduce(0) { $0 + $1.duration }

        // Hume's own Sleep Quality Score is computed in their app and is not
        // published to Health, so this is derived here from duration, deep
        // share and continuity. It is an approximation, not their number.
        let durationScore = min(1, asleep / (7 * 3600))
        let deepScore = min(1, (deep / max(asleep, 1)) / 0.20)
        let continuity = 1 - min(1, awake / max(asleep, 1) / 0.15)
        let quality = (durationScore * 0.5 + deepScore * 0.3 + continuity * 0.2) * 100

        let restingHR = await latest(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        let hrv = await latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))

        return SleepSummary(intervals: block,
                            restingHeartRate: Int(restingHR ?? 0),
                            hrv: Int(hrv ?? 0),
                            qualityScore: Int(min(100, max(0, quality)).rounded()),
                            sleepDebt: max(0, 7 * 3600 - asleep))
    }

    static func stage(for value: Int) -> SleepSummary.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake:              .awake
        case .asleepREM:          .rem
        case .asleepDeep:         .deep
        case .asleepCore:         .light
        case .asleepUnspecified:  .light
        // `inBed` brackets the whole night and would double-count against
        // the stage samples inside it.
        default:                  nil
        }
    }

    /// Everything the phone can see right now, as one reading.
    func currentReading(token: String) async -> RelayReading? {
        guard authorised else { return nil }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hr = latest(.heartRate, unit: bpm)
        async let resting = latest(.restingHeartRate, unit: bpm)
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let wristTemp = latest(.appleSleepingWristTemperature, unit: .degreeCelsius())
        async let steps = stepsToday()
        async let sleep = lastNightSleep()

        let (h, r, v, t, st, sl) = await (hr, resting, hrv, wristTemp, steps, sleep)
        guard h != nil || sl != nil else {
            status = "Health has no Hume data yet. Open the Hume app to sync, then try again."
            return nil
        }

        lastRead = .now
        status = "Read from Health at \(Date().formatted(date: .omitted, time: .standard))."

        return RelayReading(
            token: token,
            capturedAt: .now,
            heartRate: h.map { Int($0.rounded()) },
            restingHeartRate: r.map { Int($0.rounded()) },
            hrv: v.map { Int($0.rounded()) },
            skinTemperature: t,
            temperatureBaseline: nil,
            // No HealthKit type carries Hume's stress score, so it is left
            // out rather than guessed at.
            stress: nil,
            activity: st.map { Int(min(100, $0 / 100).rounded()) },
            sleep: sl
        )
    }
}
