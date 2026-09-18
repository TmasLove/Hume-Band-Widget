import SwiftUI

/// Liquid Glass surfaces for the app and the floating panel.
///
/// **Not for the widget.** A WidgetKit widget is a rendered snapshot the
/// system composites; there is nothing live behind it to refract, so
/// `glassEffect` there costs the blur and returns a flat grey. The widget
/// keeps Codenotch's pure-black card, which is what that surface is for.
/// Glass belongs where there is something behind it: the window, and above
/// all the panel, which floats over the desktop.
///
/// Every surface falls back to the solid card under Reduce Transparency.
/// That is an accessibility setting, not a style preference — honouring it is
/// why `Palette.card` still exists.
struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var design: Design
    /// Glass that reacts to the pointer. For surfaces the user actually
    /// presses, never for a passive readout.
    var interactive: Bool = false
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: design.cardCorner, style: .continuous)

        content
            .padding(design.cardPadding)
            .background {
                if reduceTransparency {
                    shape.fill(Palette.card)
                } else {
                    Color.clear.glassEffect(glass, in: shape)
                }
            }
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// A glass capsule, for the panel's resting pill and for chips.
struct GlassPill<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var interactive: Bool = false
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous).fill(Palette.card)
                } else {
                    Color.clear.glassEffect(glass, in: Capsule(style: .continuous))
                }
            }
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}
