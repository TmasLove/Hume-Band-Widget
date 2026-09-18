import Foundation

/// Turns last night's numbers into a short list of things to try.
///
/// **Where the advice comes from.** Every suggestion's guidance is taken from
/// Hume Health's own published "Improvement" line for the metric that
/// triggered it, in their Sleep Architecture Metrics catalog. Nothing here is
/// invented clinical advice, and nothing here diagnoses anything — these are
/// sleep-hygiene prompts tied to a number, which is the most an app looking
/// at wrist data can honestly offer.
///
/// The thresholds are ordinary population reference ranges, not a Hume API:
/// deep 13–23% of total sleep, REM 20–25%, efficiency above 85%. They decide
/// only which prompt to surface, never a verdict.
struct SleepAdvisor {
    struct Suggestion: Identifiable, Sendable {
        let id: String
        /// What to do.
        let title: String
        /// The number that prompted it, stated plainly so the user can judge
        /// whether it is worth acting on.
        let because: String
        /// Hume's own improvement guidance for that metric.
        let guidance: String
        let symbol: String
        /// Higher sorts first.
        let weight: Int
    }

    var sleep: SleepSummary

    /// At most three. A list of eight things to fix is a list nobody acts on.
    func suggestions(limit: Int = 3) -> [Suggestion] {
        var out: [Suggestion] = []

        let deepPct = sleep.percentage(.deep)
        let remPct = sleep.percentage(.rem)
        let target: TimeInterval = 7 * 3600

        if sleep.asleep < target {
            let short = target - sleep.asleep
            out.append(Suggestion(
                id: "duration",
                title: "Go to bed \(SleepSummary.format(short)) earlier",
                because: "You slept \(sleep.formattedDuration), short of a 7-hour target, leaving \(SleepSummary.format(sleep.sleepDebt)) of sleep debt.",
                guidance: "Hume suggests a consistent bedtime routine, optimising the sleep environment, and stress management.",
                symbol: "moon.zzz.fill",
                weight: 100 - Int(sleep.asleep / target * 50)))
        }

        if deepPct < 13 {
            out.append(Suggestion(
                id: "deep",
                title: "Protect your deep sleep",
                because: "Deep was \(deepPct)% of total sleep, below the usual 13–23%. Deep sleep is when physical recovery happens.",
                guidance: "Hume suggests regular exercise, a cool sleep environment, a consistent schedule, and avoiding alcohol and caffeine.",
                symbol: "figure.strengthtraining.traditional",
                weight: 80 + (13 - deepPct)))
        }

        if remPct < 20 {
            out.append(Suggestion(
                id: "rem",
                title: "Give REM more room",
                because: "REM was \(remPct)% of total sleep, below the usual 20–25%. REM is when memory and mood consolidate.",
                guidance: "Hume suggests stress reduction, a regular sleep schedule, managing anxiety, and avoiding sleep medications.",
                symbol: "brain.head.profile",
                weight: 70 + (20 - remPct)))
        }

        if sleep.efficiency < 85 {
            out.append(Suggestion(
                id: "efficiency",
                title: "Cut the interruptions",
                because: "You were awake \(SleepSummary.format(sleep.durations[.awake] ?? 0)) of \(SleepSummary.format(sleep.inBed)) in bed — \(sleep.efficiency)% efficiency, below the usual 85%.",
                guidance: "Hume suggests optimising the sleep environment and stress management, and evaluating potential sleep disorders if it persists.",
                symbol: "bed.double.fill",
                weight: 75 + (85 - sleep.efficiency)))
        }

        // Bedtime drifting late is the most actionable thing on this list, so
        // it is worth saying even when the night was otherwise fine.
        let hour = Calendar.current.component(.hour, from: sleep.bedtime)
        if hour >= 0 && hour < 4 {
            out.append(Suggestion(
                id: "timing",
                title: "Pull your bedtime back before midnight",
                because: "You fell asleep at \(sleep.bedtime.formatted(date: .omitted, time: .shortened)), which pushes deep sleep past the window it usually favours.",
                guidance: "Hume suggests an earlier bedtime and schedule consistency to clear accumulated sleep debt.",
                symbol: "clock.badge.exclamationmark",
                weight: 60))
        }

        if out.isEmpty {
            out.append(Suggestion(
                id: "steady",
                title: "Keep doing what you did",
                because: "\(sleep.formattedDuration) asleep, \(sleep.efficiency)% efficiency, quality \(sleep.qualityScore). Nothing here needs fixing.",
                guidance: "Hume's guidance for holding a good score is schedule consistency and sleep-environment hygiene.",
                symbol: "checkmark.seal.fill",
                weight: 0))
        }

        return Array(out.sorted { $0.weight > $1.weight }.prefix(limit))
    }
}
