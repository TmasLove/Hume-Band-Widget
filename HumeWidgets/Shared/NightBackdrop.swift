import SwiftUI

/// A slow aurora behind the sleep page.
///
/// Two purposes. It gives the Liquid Glass something worth refracting — glass
/// over near-flat black is a blur of nothing, which is most of why it looked
/// underwhelming. And it uses the stage hues that are already on the page, so
/// the colour is part of the same system rather than decoration bolted on.
///
/// Kept very low contrast on purpose: this sits under numbers people are
/// reading, and a gradient that competes with them is worse than no gradient.
struct NightBackdrop: View {
    @Environment(\.zonePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drift = false

    var body: some View {
        ZStack {
            Palette.page

            if !reduceTransparency {
                // Deep violet low-left, REM teal high-right — the two ends of
                // the stage ramp, so the page is tinted by its own data.
                ellipse(palette.stageTint(.deep), opacity: 0.30)
                    .offset(x: drift ? -70 : -30, y: drift ? 150 : 90)
                ellipse(palette.stageTint(.light), opacity: 0.22)
                    .offset(x: drift ? 120 : 60, y: drift ? -120 : -60)
                ellipse(palette.stageTint(.rem), opacity: 0.16)
                    .offset(x: drift ? -40 : 40, y: drift ? -260 : -200)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            // Long enough that it never reads as motion, only as depth.
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func ellipse(_ color: Color, opacity: Double) -> some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: 520, height: 420)
            .blur(radius: 140)
    }
}
