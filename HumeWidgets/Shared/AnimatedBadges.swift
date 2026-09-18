import SwiftUI

/// A score on a ring that draws itself in, with a slow breath while the value
/// is in an alarming zone.
///
/// The breath is the only decorative motion in the app and it is deliberately
/// slow — a badge that pulses quickly beside a health figure reads as an
/// alarm, which is a claim this data cannot support. It stops entirely under
/// Reduce Motion, where the ring simply appears at its final value.
struct AnimatedScoreBadge: View {
    @Environment(\.zonePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var score: Int
    var zone: MetricZone
    var caption: String
    var design: Design

    /// `nil` until the entry animation runs. Falling back to the real
    /// fraction means a context where `onAppear` never fires — a static
    /// render, a preview, a snapshot — shows the correct ring rather than an
    /// empty one.
    @State private var drawn: Double?
    @State private var breathing = false

    private var fraction: Double { min(1, max(0, Double(score) / 100)) }

    var body: some View {
        VStack(spacing: design.px(10)) {
            ZStack {
                Circle()
                    .strokeBorder(Palette.ringTrack, lineWidth: design.trackStroke)

                Circle()
                    .inset(by: design.trackStroke / 2)
                    .trim(from: 0, to: drawn ?? fraction)
                    .stroke(zone.tint(palette),
                            style: StrokeStyle(lineWidth: design.progressStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(design.valueFont)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.textPrimary)
                    Image(systemName: zone.symbol)
                        .font(.system(size: design.px(28), weight: .semibold))
                        .foregroundStyle(zone.tint(palette))
                }
            }
            .frame(width: design.ringDiameter, height: design.ringDiameter)
            .scaleEffect(breathing ? 1.025 : 1)
            .shadow(color: zone.tint(palette).opacity(breathing ? 0.35 : 0.15),
                    radius: breathing ? design.px(30) : design.px(14))

            Text(caption)
                .font(design.bodyFont)
                .tracking(design.px(2))
                .foregroundStyle(Palette.textSecondary)
        }
        .onAppear { animateIn() }
        .onChange(of: score) { _, _ in animateIn() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(score) out of 100. \(zone.label).")
    }

    private func animateIn() {
        guard !reduceMotion else {
            drawn = fraction
            breathing = false
            return
        }
        drawn = 0
        withAnimation(.easeOut(duration: 0.9)) { drawn = fraction }
        // Only the concerning end breathes. A good score should sit still.
        if zone == .high {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            breathing = false
        }
    }
}

/// The small live-state dot, which pulses only while data is actually moving.
struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var color: Color
    var active: Bool
    var size: CGFloat

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(color, lineWidth: 1)
                    .scaleEffect(on ? 2.4 : 1)
                    .opacity(on ? 0 : 0.8)
            }
            .onAppear { start() }
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active, !reduceMotion else { on = false; return }
        on = false
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true }
    }
}
