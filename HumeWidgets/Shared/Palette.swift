import AppKit
import SwiftUI

/// Visual language adapted from Codenotch (github.com/vinzdg/codenotch, MIT),
/// whose palette, proportional layout system and motion curves are reused here
/// so the two apps read as siblings on the same desktop.
///
/// Three things carried over verbatim, because they are the identity:
///   * the three-state ramp — ample / watch / critical (now in `ZonePalette`,
///     alongside two alternatives for atypical colour vision)
///   * pure-black cards with *translucent* tracks, so a track darkens what is
///     behind it instead of looking like painted-on grey
///   * a wide dim ring track with a thinner bright arc riding inside it
enum Palette {
    /// Card and page fills.
    ///
    /// Codenotch's `card` is pure black unconditionally, because its notch is a
    /// bezel and its solid style pins the panel to `darkAqua` so the white ink
    /// stays white. A window and a widget cannot pin the appearance, so a black
    /// card in Light Appearance would draw black `textPrimary` and a
    /// black-translucent track onto black — the numbers and the ring tracks
    /// disappear entirely. So `card` adapts, and is pure black in dark, which
    /// is where the identity lives. Codenotch makes the same concession for its
    /// glass style, and for the same reason.
    static let card = Color(dark: .black, light: NSColor(hex: 0xFFFFFF))
    static let page = Color(dark: NSColor(hex: 0x0A0A0A), light: NSColor(hex: 0xF2F2F2))

    /// Translucent rather than a fixed grey, so they composite with the card.
    static let ringTrack = Color(dark: .white.withAlphaComponent(0.188),
                                 light: .black.withAlphaComponent(0.16))
    static let barTrack  = Color(dark: .white.withAlphaComponent(0.176),
                                 light: .black.withAlphaComponent(0.15))

    static let textPrimary   = Color(dark: .white, light: .black)
    static let textSecondary = Color(dark: NSColor(hex: 0x808080), light: NSColor(hex: 0x6B6B6B))
}

/// Proportional layout, the way Codenotch does it: every number is a ratio
/// measured off a design frame, and one anchor picks the absolute scale.
///
/// Codenotch has a single global scale because it draws one object. This app
/// draws the same object at two very different sizes — a window and a widget —
/// so the anchor is an instance rather than a constant. Change `ringDiameter`
/// and type, strokes, padding and corners all move with it.
struct Design {
    /// Points per pixel of the design frame. 117px is the ring in the frame.
    let scale: CGFloat

    init(ringDiameter: CGFloat) { self.scale = ringDiameter / 117 }

    /// The window. Large enough for the ring to carry the headline number.
    static let dashboard = Design(ringDiameter: 112)
    /// The widget, where the whole surface is roughly one dashboard card.
    static let widget = Design(ringDiameter: 58)

    func px(_ pixels: CGFloat) -> CGFloat { pixels * scale }

    /// Cap-height fraction of an em for SF Pro; the frame can only be measured
    /// by cap height, so this converts back to a point size.
    private static let capRatio: CGFloat = 0.714
    func fontSize(capPixels pixels: CGFloat) -> CGFloat { px(pixels) / Self.capRatio }

    // Ratios measured off the Codenotch frame.
    var ringDiameter: CGFloat    { px(117) }
    var trackStroke: CGFloat     { px(15.5) }   // the wide dim track
    var progressStroke: CGFloat  { px(8) }      // the thinner bright arc
    var ringLabelGap: CGFloat    { px(26.9) }
    var cardCorner: CGFloat      { px(49.5) }
    var cardPadding: CGFloat     { px(32) }
    var barHeight: CGFloat       { px(10.5) }

    var valueFont: Font { .system(size: fontSize(capPixels: 27), weight: .semibold) }
    var titleFont: Font { .system(size: fontSize(capPixels: 26), weight: .semibold) }
    var bodyFont:  Font { .system(size: fontSize(capPixels: 18), weight: .regular) }
}

/// Codenotch's motion curves. `reading` is the slow, heavily damped spring it
/// uses for any value the user is reading off a ring — it settles rather than
/// bounces, which is what keeps a number that changes every 10 seconds from
/// being distracting.
enum Motion {
    static let reading  = Animation.spring(response: 0.9, dampingFraction: 0.9)
    static let contents = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let crossfade = Animation.easeInOut(duration: 0.16)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Resolved against whatever appearance is current when the colour is drawn.
    init(dark: NSColor, light: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >> 8) & 0xFF) / 255,
                  blue:    CGFloat(hex & 0xFF) / 255,
                  alpha:   1)
    }
}
