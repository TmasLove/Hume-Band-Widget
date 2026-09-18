import SwiftUI

/// The panel's contents: a resting pill hugging the bezel that unfolds into a
/// full readout on hover.
///
/// Only the pill or the card is ever drawn — the rest of the panel is empty,
/// with no background, so SwiftUI hit testing returns nil there and clicks
/// pass through to whatever is behind. That is what lets the panel keep a
/// fixed frame while appearing to fold.
struct PanelRootView: View {
    @Bindable var controller: PanelController
    @Bindable var model: MetricsViewModel
    /// Observed rather than passed in, so a palette change made anywhere —
    /// the View menu, Settings — repaints the panel immediately.
    @State private var settings = ZoneSettings.shared

    /// Lets the pill morph into the card rather than crossfading — the one
    /// place a glass transition is genuinely better than a plain one.
    @Namespace private var glassNamespace

    private let resting = Design(ringDiameter: 26)
    private let open = Design(ringDiameter: 40)

    var body: some View {
        ZStack(alignment: alignment) {
            // A hole. Without an explicit clear colour the ZStack would size
            // to its content instead of the panel.
            Color.clear

            GlassEffectContainer(spacing: 24) {
                if controller.isExpanded { expanded } else { pill }
            }
            .onHover { controller.setExpanded($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.zonePalette, settings.palette)
        .animation(Motion.contents, value: controller.isExpanded)
    }

    /// Content hugs the bezel, so the panel grows inward as it unfolds.
    private var alignment: Alignment {
        switch controller.edge {
        case .top:    .top
        case .bottom: .bottom
        case .left:   .leading
        case .right:  .trailing
        }
    }

    // MARK: - Resting

    private var pill: some View {
        GlassPill(interactive: true) {
            stack(spacing: resting.px(26)) {
                ForEach(model.metrics.allReadings) { reading in
                    ring(reading, design: resting)
                }
            }
            .padding(resting.px(26))
        }
        .glassEffectID("panel", in: glassNamespace)
    }

    // MARK: - Expanded

    private var expanded: some View {
        GlassCard(design: open, interactive: true) {
            expandedBody
        }
        .glassEffectID("panel", in: glassNamespace)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: open.px(18)) {
            HStack(spacing: open.px(10)) {
                Text("HUME BAND")
                    .font(open.bodyFont.weight(.semibold))
                    .tracking(open.px(3))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Text("simulated")
                    .font(open.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
            }

            stack(spacing: open.px(26)) {
                ForEach(model.metrics.allReadings) { reading in
                    VStack(spacing: open.px(10)) {
                        ring(reading, design: open)
                        Text(reading.value)
                            .font(open.valueFont)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Palette.textPrimary)
                        Text(reading.shortTitle.uppercased())
                            .font(open.bodyFont)
                            .tracking(open.px(2))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    /// The stack runs along the edge: across the screen on top/bottom, down it
    /// on left/right.
    @ViewBuilder
    private func stack<C: View>(spacing: CGFloat, @ViewBuilder content: () -> C) -> some View {
        if controller.edge.isVertical {
            VStack(spacing: spacing) { content() }
        } else {
            HStack(spacing: spacing) { content() }
        }
    }

    private func ring(_ reading: MetricReading, design: Design) -> some View {
        ZoneRing(reading: reading, design: design, showsValue: false)
    }
}
