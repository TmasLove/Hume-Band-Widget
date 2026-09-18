import SwiftUI

/// Codenotch's ring: a wide dim track with a *thinner* bright arc riding
/// inside it. The stroke-width difference is the whole character of the mark —
/// equal widths read as an ordinary progress ring.
struct ZoneRing: View {
    @Environment(\.zonePalette) private var palette
    var reading: MetricReading
    var design: Design
    /// The big number inside the ring. Off for the small satellite rings.
    var showsValue: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.ringTrack, lineWidth: design.trackStroke)

            Circle()
                .inset(by: design.trackStroke / 2)
                .trim(from: 0, to: reading.fraction)
                .stroke(reading.zone.tint(palette),
                        style: StrokeStyle(lineWidth: design.progressStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.reading, value: reading.fraction)
                .animation(Motion.reading, value: reading.zone)
                .animation(Motion.crossfade, value: palette)

            if showsValue {
                VStack(spacing: 0) {
                    Text(reading.value)
                        .font(design.valueFont)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.textPrimary)
                    Text(reading.unit)
                        .font(design.bodyFont)
                        .foregroundStyle(Palette.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Keep three digits off the track; without this "118" kisses
                // the ring at widget scale.
                .padding(.horizontal, design.trackStroke)
            } else {
                Image(systemName: reading.symbol)
                    .font(.system(size: design.px(30), weight: .semibold))
                    .foregroundStyle(reading.zone.tint(palette))
            }
        }
        .frame(width: design.ringDiameter, height: design.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityDescription)
    }
}

/// The bar form of the same mark, for rows where a ring does not fit.
struct ZoneBar: View {
    @Environment(\.zonePalette) private var palette
    var reading: MetricReading
    var design: Design

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Palette.barTrack)
                Capsule(style: .continuous)
                    .fill(reading.zone.tint(palette))
                    .frame(width: max(design.barHeight, proxy.size.width * reading.fraction))
                    .animation(Motion.reading, value: reading.fraction)
            }
        }
        .frame(height: design.barHeight)
        .accessibilityHidden(true)
    }
}

/// Icon + name + value + bar. The label stays `textPrimary` rather than the
/// zone colour: the light-mode ramp clears 3:1, which is the bar for a bar or
/// a ring, but not the 4.5:1 that small coloured text needs.
struct MetricRow: View {
    @Environment(\.zonePalette) private var palette
    var reading: MetricReading
    var design: Design

    var body: some View {
        VStack(alignment: .leading, spacing: design.px(14)) {
            HStack(spacing: design.px(10)) {
                Image(systemName: reading.symbol)
                    .font(.system(size: design.fontSize(capPixels: 18), weight: .semibold))
                    .foregroundStyle(reading.zone.tint(palette))

                Text(reading.title)
                    .font(design.bodyFont)
                    .foregroundStyle(Palette.textSecondary)

                Spacer(minLength: design.px(8))

                Text(reading.value)
                    .font(design.titleFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.textPrimary)

                Text(reading.unit)
                    .font(design.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
            }
            .lineLimit(1)

            ZoneBar(reading: reading, design: design)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityDescription)
    }
}

/// A black card with the frame's corner radius and padding.
struct NotchCard<Content: View>: View {
    var design: Design
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(design.cardPadding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: design.cardCorner, style: .continuous))
    }
}
