import SwiftUI
import WidgetKit

/// The colour ramp used for the three metric zones.
///
/// Every option was checked by simulating protanopia, deuteranopia and
/// tritanopia (Viénot et al. 1999) and measuring the worst-case CIELAB ΔE
/// between the three zones as each dichromat sees them, plus WCAG contrast
/// against the surface. The numbers in each case's comment are that worst
/// case — ΔE below ~20 is easily confused, above ~40 is comfortably distinct.
enum ZonePalette: String, CaseIterable, Identifiable, Sendable {
    /// Codenotch's own ramp. Strong in dark mode (ΔE 38) because its three
    /// colours differ steeply in luminance, which dichromats retain.
    ///
    /// Its *light* values score ΔE 5.7 — mid-green `#00A356` against dark
    /// amber `#B08800` really is confusable with red–green colour blindness.
    /// That measured weakness is why the other options exist.
    case classic

    /// Teal → amber → rose. ΔE 48.6 dark, 45.9 light: the widest separation
    /// found under a constrained search that still keeps an ordinal
    /// calm→alarm reading.
    case distinct

    /// No hue at all — severity is carried by lightness, plus the zone glyph
    /// and the bar length. ΔE 26.7 dark / 24.7 light, and it is the only
    /// option that also works for achromatopsia.
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:    "Classic"
        case .distinct:   "High separation"
        case .monochrome: "Monochrome"
        }
    }

    var detail: String {
        switch self {
        case .classic:    "Green, yellow, red. Best if you see colour typically."
        case .distinct:   "Teal, amber, rose. Stays distinct with red–green or blue–yellow colour blindness."
        case .monochrome: "Lightness only. Works with any colour vision, including full colour blindness."
        }
    }

    /// Sleep stages get their own night-time family rather than borrowing the
    /// zone ramp, because green/amber/red means *health state* here and
    /// reusing it for "REM" would be a false signal.
    ///
    /// These were not chosen by eye. A constrained search over hue bands —
    /// violet, blue, teal, amber — maximised the worst-case CIELAB ΔE across
    /// normal, protan, deutan and tritan vision subject to 3:1 contrast:
    /// **45.9 dark / 41.6 light**. For comparison, the Apple-Health-style set
    /// of indigo/blue/cyan/orange that seemed the obvious pick scores 7.5,
    /// because its three cool hues sit at nearly the same lightness.
    ///
    /// Classic and High separation share these, since the values already are
    /// the maximum-separation result — there is no weaker variant worth
    /// having. Monochrome drops to a lightness ramp, where hue cannot exist.
    func stageTint(_ stage: SleepSummary.Stage) -> Color {
        switch (self, stage) {
        case (.monochrome, .deep):  Color(dark: NSColor(hex: 0xFFFFFF), light: NSColor(hex: 0x101010))
        case (.monochrome, .rem):   Color(dark: NSColor(hex: 0xC4C4C4), light: NSColor(hex: 0x454545))
        case (.monochrome, .light): Color(dark: NSColor(hex: 0x8A8A8A), light: NSColor(hex: 0x6E6E6E))
        case (.monochrome, .awake): Color(dark: NSColor(hex: 0x5E5E5E), light: NSColor(hex: 0x949494))

        case (_, .deep):  Color(dark: NSColor(hex: 0xB330BF), light: NSColor(hex: 0xA855D6))
        case (_, .light): Color(dark: NSColor(hex: 0x2E4BFF), light: NSColor(hex: 0x000073))
        case (_, .rem):   Color(dark: NSColor(hex: 0x73FFDE), light: NSColor(hex: 0x26997E))
        case (_, .awake): Color(dark: NSColor(hex: 0xFFE573), light: NSColor(hex: 0xE66000))
        }
    }

    func tint(_ zone: MetricZone) -> Color {
        switch (self, zone) {
        case (.classic, .optimal):     Color(dark: NSColor(hex: 0x00FF88), light: NSColor(hex: 0x00A356))
        case (.classic, .elevated):    Color(dark: NSColor(hex: 0xF2FF00), light: NSColor(hex: 0xB08800))
        case (.classic, .high):        Color(hex: 0xFF3F00)

        case (.distinct, .optimal):    Color(dark: NSColor(hex: 0x73FFF3), light: NSColor(hex: 0x459992))
        case (.distinct, .elevated):   Color(dark: NSColor(hex: 0xFFC926), light: NSColor(hex: 0xBF891D))
        case (.distinct, .high):       Color(dark: NSColor(hex: 0xFF1A5C), light: NSColor(hex: 0x730013))

        case (.monochrome, .optimal):  Color(dark: NSColor(hex: 0x6E6E6E), light: NSColor(hex: 0x8A8A8A))
        case (.monochrome, .elevated): Color(dark: NSColor(hex: 0xB4B4B4), light: NSColor(hex: 0x4D4D4D))
        case (.monochrome, .high):     Color(dark: NSColor(hex: 0xFFFFFF), light: NSColor(hex: 0x000000))
        }
    }
}

/// Reads and writes the palette in the App Group, which is the only way the
/// widget can see a choice made in the app.
///
/// The widget extension is a separate process that is launched, asked to
/// render, and killed, so it reads this fresh every time rather than
/// observing it.
@MainActor
@Observable
final class ZoneSettings {
    static let shared = ZoneSettings()

    nonisolated private static let key = "zonePalette"

    var palette: ZonePalette {
        didSet {
            guard palette != oldValue else { return }
            Self.defaults?.set(palette.rawValue, forKey: Self.key)
            // The widget is a different process and will not notice a
            // defaults write on its own.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// `UserDefaults` is thread-safe, so these two need no actor — and the
    /// widget's timeline provider is not on the main actor.
    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: HumeConfig.appGroup)
    }

    /// Safe to call from the widget extension, which has no observation.
    nonisolated static func current() -> ZonePalette {
        guard let raw = defaults?.string(forKey: key),
              let palette = ZonePalette(rawValue: raw) else { return .classic }
        return palette
    }

    private init() { palette = Self.current() }
}

/// Whether the widget is showing its full layout or the collapsed, icon-only
/// one.
///
/// A WidgetKit widget cannot change its own *frame* — the family is chosen by
/// the user when the widget is placed, and the extension has no say in it.
/// What it can change is what it draws inside that frame, so "collapsed" here
/// means a compact glyph strip instead of rings and rows. Stored in the App
/// Group beside the palette so the widget and the app agree.
@MainActor
@Observable
final class WidgetLayoutSettings {
    static let shared = WidgetLayoutSettings()

    nonisolated private static let key = "widgetCollapsed"
    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: HumeConfig.appGroup)
    }

    var isCollapsed: Bool {
        didSet {
            guard isCollapsed != oldValue else { return }
            Self.defaults?.set(isCollapsed, forKey: Self.key)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated static func current() -> Bool {
        defaults?.bool(forKey: key) ?? false
    }

    nonisolated static func toggle() {
        defaults?.set(!current(), forKey: key)
    }

    private init() { isCollapsed = Self.current() }
}

/// Which page the widget is showing.
///
/// A WidgetKit widget has no tab bar — it renders a snapshot and the only
/// interaction available is an `AppIntent` button. So "tab" here is a page
/// the user steps through with a control, stored in the App Group like the
/// other widget state.
enum WidgetPage: String, CaseIterable, Sendable {
    case vitals, sleep

    var title: String {
        switch self {
        case .vitals: "Vitals"
        case .sleep:  "Sleep"
        }
    }

    var symbol: String {
        switch self {
        case .vitals: "waveform.path.ecg"
        case .sleep:  "bed.double.fill"
        }
    }

    var next: WidgetPage { self == .vitals ? .sleep : .vitals }
}

extension WidgetLayoutSettings {
    nonisolated private static var pageKey: String { "widgetPage" }

    nonisolated static func currentPage() -> WidgetPage {
        guard let raw = UserDefaults(suiteName: HumeConfig.appGroup)?.string(forKey: pageKey),
              let p = WidgetPage(rawValue: raw) else { return .vitals }
        return p
    }

    nonisolated static func advancePage() {
        UserDefaults(suiteName: HumeConfig.appGroup)?
            .set(currentPage().next.rawValue, forKey: pageKey)
    }
}

extension EnvironmentValues {
    /// Injected once at each root — the app's window and the widget's entry
    /// view — so no component has to know where the preference lives.
    @Entry var zonePalette: ZonePalette = .classic
}


extension MetricZone {
    /// Colour lives with the palette, not the zone: the zone is a meaning
    /// and the palette is how it is drawn. Keeping them apart is also what
    /// lets the model layer compile for iOS, which has no AppKit.
    func tint(_ palette: ZonePalette) -> Color { palette.tint(self) }
}
