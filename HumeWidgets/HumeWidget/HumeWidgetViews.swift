import SwiftUI
import AppIntents
import WidgetKit

// MARK: - Collapsed

/// Icon-only. Each metric is its glyph in its zone colour with a hairline
/// ring around it, so the state is still readable at a glance but the widget
/// takes up almost no visual weight.
///
/// This is the same idea as Codenotch's resting pill: when you are not
/// looking at it, it should be a colour and a shape, not a readout.
struct CollapsedHumeView: View {
    @Environment(\.zonePalette) private var palette
    var entry: HumeEntry

    private let design = Design(ringDiameter: 44)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Four rings in a row do not fit a small tile. Rather than branch
            // on `widgetFamily`, offer the row first and let SwiftUI fall back
            // to a 2x2 block when the tile is too narrow — that also covers
            // whatever sizes a future macOS adds.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: design.px(28)) {
                    ForEach(entry.metrics.allReadings) { glyph($0) }
                }
                VStack(spacing: design.px(22)) {
                    ForEach(Array(entry.metrics.allReadings.chunked(2).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: design.px(22)) {
                            ForEach(row) { glyph($0) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlaid rather than in the flow, so it never squeezes the row.
            ExpandButton(design: design, isCollapsed: true)
        }
    }

    private func glyph(_ reading: MetricReading) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.ringTrack, lineWidth: design.px(9))
            Circle()
                .inset(by: design.px(4.5))
                .trim(from: 0, to: reading.fraction)
                .stroke(reading.zone.tint(palette),
                        style: StrokeStyle(lineWidth: design.px(9), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.reading, value: reading.fraction)
            Image(systemName: reading.symbol)
                .font(.system(size: design.px(42), weight: .semibold))
                .foregroundStyle(reading.zone.tint(palette))
        }
        .frame(width: design.ringDiameter, height: design.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityDescription)
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// A widget chrome control: glyph on a filled circle.
///
/// These were bare grey glyphs, which on a black card read as decoration
/// rather than something you can press — the collapse control in particular
/// was effectively invisible. The filled circle is the affordance.
struct WidgetChromeButton<I: AppIntent>: View {
    var intent: I
    var symbol: String
    var label: String
    var design: Design
    var prominent: Bool = false

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: design.fontSize(capPixels: 15), weight: .bold))
                .foregroundStyle(prominent ? Palette.card : Palette.textPrimary)
                .frame(width: design.px(58), height: design.px(58))
                .background(prominent ? AnyShapeStyle(Palette.textPrimary)
                                      : AnyShapeStyle(Palette.ringTrack),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The fold control. Shared by both states so it never moves.
struct ExpandButton: View {
    var design: Design
    var isCollapsed: Bool

    var body: some View {
        WidgetChromeButton(
            intent: ToggleWidgetLayoutIntent(),
            symbol: isCollapsed ? "chevron.down" : "chevron.up",
            label: isCollapsed ? "Expand widget" : "Collapse widget",
            design: design,
            // The one control that should always be findable.
            prominent: true
        )
    }
}

// MARK: - Small

/// One ring, the way the notch shows one provider.
struct SmallHumeView: View {
    @Environment(\.zonePalette) private var palette
    var entry: HumeEntry
    private let design = Design.widget

    private var focused: MetricReading {
        let all = entry.metrics.allReadings
        return all.first { $0.kind == entry.configuration.focus.kind } ?? all[0]
    }

    private var others: [MetricReading] {
        entry.metrics.allReadings.filter { $0.kind != focused.kind }
    }

    var body: some View {
        VStack(spacing: design.px(20)) {
            ZoneRing(reading: focused, design: design)

            Text(focused.shortTitle.uppercased())
                .font(design.bodyFont.weight(.semibold))
                .tracking(design.px(3))
                .foregroundStyle(Palette.textSecondary)

            HStack(spacing: design.px(14)) {
                ForEach(others) { reading in
                    Circle()
                        .fill(reading.zone.tint(palette))
                        .frame(width: design.px(16), height: design.px(16))
                }
                ExpandButton(design: design, isCollapsed: false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(focused.accessibilityDescription)
    }
}

// MARK: - Medium

/// Four rings in a row — the notch's own arrangement.
struct MediumHumeView: View {
    var entry: HumeEntry
    private let design = Design.widget

    var body: some View {
        VStack(alignment: .leading, spacing: design.px(22)) {
            HumeHeader(entry: entry, design: design)

            HStack(spacing: 0) {
                ForEach(entry.metrics.allReadings) { reading in
                    VStack(spacing: design.px(14)) {
                        ZoneRing(reading: reading, design: design, showsValue: false)
                        Text(reading.value)
                            .font(design.valueFont)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Palette.textPrimary)
                        Text(reading.shortTitle.uppercased())
                            .font(design.bodyFont)
                            .tracking(design.px(2))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Large / Extra large

struct LargeHumeView: View {
    @Environment(\.zonePalette) private var palette
    var entry: HumeEntry
    private let design = Design(ringDiameter: 76)

    var body: some View {
        VStack(alignment: .leading, spacing: design.px(26)) {
            HumeHeader(entry: entry, design: design)

            HStack(spacing: design.px(26)) {
                ZoneRing(reading: entry.metrics.heartRateReading, design: design)

                VStack(alignment: .leading, spacing: design.px(8)) {
                    Text(entry.metrics.heartRateReading.title.uppercased())
                        .font(design.bodyFont.weight(.semibold))
                        .tracking(design.px(3))
                        .foregroundStyle(Palette.textSecondary)
                    HStack(spacing: design.px(8)) {
                        Image(systemName: entry.metrics.heartRateReading.zone.symbol)
                        Text(entry.metrics.heartRateReading.zone.label)
                    }
                    .font(design.titleFont)
                    .foregroundStyle(entry.metrics.heartRateReading.zone.tint(palette))
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: design.px(22)) {
                ForEach(entry.metrics.allReadings.filter { $0.kind != .heartRate }) { reading in
                    MetricRow(reading: reading, design: design)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared chrome

struct HumeHeader: View {
    var entry: HumeEntry
    var design: Design

    var body: some View {
        HStack(spacing: design.px(14)) {
            Text("HUME BAND")
                .font(design.bodyFont.weight(.semibold))
                .tracking(design.px(3))
                .foregroundStyle(Palette.textSecondary)
                // Three chrome buttons leave a small tile short of room for
                // the full word; shrink the label rather than clip it.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(-1)

            Spacer(minLength: 0)

            if entry.metrics.isStale(asOf: entry.date) {
                Text(entry.metrics.capturedAt, style: .relative)
                    .font(design.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            WidgetChromeButton(intent: RefreshMetricsIntent(),
                               symbol: "arrow.clockwise",
                               label: "Refresh band data",
                               design: design)

            WidgetChromeButton(intent: SwitchWidgetPageIntent(),
                               symbol: entry.page.next.symbol,
                               label: "Show \(entry.page.next.title)",
                               design: design)

            ExpandButton(design: design, isCollapsed: false)
        }
    }
}

// MARK: - Sleep page

/// Last night, broken down. Scales itself across the families rather than
/// having three near-identical variants: the small tile drops the legend to
/// two columns and hides the bedtime row, because there is no room for either.
struct SleepHumeView: View {
    var entry: HumeEntry

    private let design = Design(ringDiameter: 58)
    private let compactDesign = Design(ringDiameter: 46)

    var body: some View {
        if let sleep = entry.metrics.sleep {
            // Three self-contained layouts, largest first. Branching on
            // `widgetFamily` would be untestable outside a real widget host
            // and would miss any tile size a future macOS adds; letting
            // SwiftUI pick by measurement covers both.
            ViewThatFits(in: [.horizontal, .vertical]) {
                layout(sleep, design: design, legendColumns: 4, showsTimes: true, showsDetails: true, showsHypnogram: true)
                layout(sleep, design: design, legendColumns: 4, showsTimes: false, showsDetails: false, showsHypnogram: true)
                layout(sleep, design: design, legendColumns: 4, showsTimes: true, showsDetails: false)
                // A wide-but-short tile has room for four columns even
                // though the bedtime row will not fit; without this rung it
                // drops straight to the two-column layout and looks sparse.
                layout(sleep, design: design, legendColumns: 4, showsTimes: false, showsDetails: false)
                layout(sleep, design: compactDesign, legendColumns: 2, showsTimes: false, showsDetails: false)
            }
        } else {
            Text("No sleep recorded")
                .font(design.bodyFont)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func layout(_ sleep: SleepSummary, design: Design,
                        legendColumns: Int, showsTimes: Bool, showsDetails: Bool,
                        showsHypnogram: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: design.px(18)) {
            HumeHeader(entry: entry, design: design)

            if showsTimes {
                SleepHeadline(sleep: sleep, design: design)
            } else {
                Text(sleep.formattedDuration)
                    .font(.system(size: design.fontSize(capPixels: 34), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
            }

            if showsHypnogram {
                SleepHypnogram(sleep: sleep, design: design, showsLaneLabels: showsDetails)
            } else {
                SleepTimelineTrack(sleep: sleep, design: design, showsTicks: showsTimes)
            }
            SleepLegend(sleep: sleep, design: design, columns: legendColumns)

            if showsTimes {
                HStack(spacing: design.px(10)) {
                    Label(sleep.bedtime.formatted(date: .omitted, time: .shortened),
                          systemImage: "moon.fill")
                    Text("\u{2192}")
                    Label(sleep.wakeTime.formatted(date: .omitted, time: .shortened),
                          systemImage: "sun.max.fill")
                    Spacer(minLength: 0)
                    Label("\(sleep.restingHeartRate) BPM · \(sleep.hrv) ms", systemImage: "heart.fill")
                }
                .font(design.bodyFont)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            }

            if showsDetails {
                Divider().overlay(Palette.ringTrack)
                VStack(spacing: design.px(16)) {
                    detail("Time in bed", SleepSummary.format(sleep.inBed), "bed.double.fill", design)
                    detail("Efficiency", "\(sleep.efficiency)%", "chart.pie.fill", design)
                    detail("Sleep debt", SleepSummary.format(sleep.sleepDebt), "hourglass", design)
                    detail("Resting heart rate", "\(sleep.restingHeartRate) BPM", "heart.fill", design)
                    detail("HRV", "\(sleep.hrv) ms", "waveform.path.ecg", design)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func detail(_ title: String, _ value: String, _ symbol: String, _ design: Design) -> some View {
        HStack(spacing: design.px(12)) {
            Image(systemName: symbol)
                .font(.system(size: design.fontSize(capPixels: 16)))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: design.px(34), alignment: .leading)
            Text(title)
                .font(design.bodyFont)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(design.titleFont)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .lineLimit(1)
    }
}
