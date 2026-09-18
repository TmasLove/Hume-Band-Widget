import Foundation

/// Budget notes — the whole battery story for this widget lives here.
///
/// WidgetKit does not let an extension wake every ten seconds; each widget
/// gets on the order of a few dozen background refreshes a day. So the widget
/// does NOT poll. Instead each refresh does one fetch and emits a long
/// timeline of pre-rendered entries spaced `displayInterval` apart. WidgetKit
/// swaps those in without waking the extension, which costs no energy, and
/// the on-screen numbers advance every ten seconds.
///
/// Genuinely-new data arrives by the app calling `WidgetCenter.reloadTimelines`
/// (see `MetricsStore.save`), which is free against the background budget.
enum RefreshPolicy {
    /// How often the displayed value steps forward.
    static let displayInterval: TimeInterval = 10

    /// One timeline covers 30 minutes, i.e. ~48 refreshes a day — comfortably
    /// inside WidgetKit's budget with headroom for app-driven reloads.
    static let horizon: TimeInterval = 30 * 60

    static var entryCount: Int { Int(horizon / displayInterval) }
}
