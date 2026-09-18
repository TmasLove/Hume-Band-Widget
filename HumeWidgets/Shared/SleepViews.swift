import SwiftUI

/// Tint for a stage. Stages are told apart by weight and label rather than
/// hue: the three asleep stages are the palette's optimal tint at increasing
/// opacity, and only Awake borrows the caution tint. That keeps the chart
/// readable in the monochrome palette and for any colour vision.
func stageTint(_ stage: SleepSummary.Stage, _ palette: ZonePalette) -> Color {
    palette.stageTint(stage)
}

/// The hypnogram: last night as it actually unfolded.
///
/// Four lanes, shallowest at the top, with one rounded bar per continuous
/// stretch of a stage — the arrangement every sleep chart uses, and the
/// reason the stage colours are worth having. A stacked proportional bar can
/// tell you *how much* deep sleep you got; only this can show you that it all
/// happened before 2am.
struct SleepHypnogram: View {
    @Environment(\.zonePalette) private var palette
    var sleep: SleepSummary
    var design: Design
    /// Stage names down the left. Off where there is no room.
    var showsLaneLabels: Bool = true
    /// Expanded is not merely taller: it adds hour gridlines and a real time
    /// axis, which is the detail that makes a hypnogram worth reading
    /// closely rather than glancing at.
    var isExpanded: Bool = false

    private let lanes = 4

    /// Labels and chart must be pinned to the same height. Left to grow, the
    /// label column expands to whatever the parent offers while the chart
    /// stays fixed, and the two drift apart by hundreds of points.
    private var chartHeight: CGFloat { design.px(isExpanded ? 460 : 210) }

    var body: some View {
        HStack(alignment: .top, spacing: design.px(16)) {
            if showsLaneLabels {
                VStack(spacing: 0) {
                    ForEach(SleepSummary.Stage.allCases.sorted { $0.lane < $1.lane }) { stage in
                        VStack(alignment: .leading, spacing: design.px(2)) {
                            Text(stage.title)
                                .font(design.bodyFont)
                                .foregroundStyle(Palette.textSecondary)
                            if isExpanded {
                                Text(SleepSummary.format(sleep.durations[stage] ?? 0))
                                    .font(design.bodyFont)
                                    .monospacedDigit()
                                    .foregroundStyle(stageTint(stage, palette))
                            }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: design.px(isExpanded ? 130 : 96), height: chartHeight)
            }

            VStack(spacing: design.px(10)) {
                chart.frame(height: chartHeight)
                axis
            }
        }
        .animation(Motion.contents, value: isExpanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel)
    }

    /// Midnight and every hour between going to bed and waking.
    private var hourMarks: [Date] {
        let cal = Calendar.current
        var marks: [Date] = []
        var t = cal.date(bySetting: .minute, value: 0, of: sleep.bedtime) ?? sleep.bedtime
        if t < sleep.bedtime { t = t.addingTimeInterval(3600) }
        while t < sleep.wakeTime {
            marks.append(t)
            t = t.addingTimeInterval(3600)
        }
        return marks
    }

    private var chart: some View {
        GeometryReader { proxy in
            let total = max(sleep.inBed, 1)
            let laneH = proxy.size.height / CGFloat(lanes)
            let barH = laneH * (isExpanded ? 0.42 : 0.5)
            let x = { (d: Date) in CGFloat(d.timeIntervalSince(sleep.bedtime) / total) * proxy.size.width }

            ZStack(alignment: .topLeading) {
                if isExpanded {
                    ForEach(hourMarks, id: \.self) { mark in
                        Rectangle()
                            .fill(Palette.ringTrack.opacity(0.5))
                            .frame(width: 1)
                            .offset(x: x(mark))
                    }
                }

                // Faint rails so an empty lane still reads as a lane.
                ForEach(0..<lanes, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(Palette.ringTrack.opacity(0.4))
                        .frame(height: design.px(3))
                        .offset(y: laneH * CGFloat(i) + (laneH - design.px(3)) / 2)
                }

                ForEach(sleep.intervals) { interval in
                    Capsule(style: .continuous)
                        .fill(stageTint(interval.stage, palette))
                        .frame(width: max(design.px(7), x(interval.end) - x(interval.start)),
                               height: barH)
                        .offset(x: x(interval.start),
                                y: laneH * CGFloat(interval.stage.lane) + (laneH - barH) / 2)
                }
            }
        }
    }

    private var axis: some View {
        Group {
            if isExpanded {
                GeometryReader { proxy in
                    let total = max(sleep.inBed, 1)
                    ZStack(alignment: .topLeading) {
                        ForEach(hourMarks, id: \.self) { mark in
                            Text(mark.formatted(.dateTime.hour()))
                                .font(design.bodyFont)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize()
                                .offset(x: CGFloat(mark.timeIntervalSince(sleep.bedtime) / total) * proxy.size.width - design.px(30))
                        }
                    }
                }
                .frame(height: design.px(36))
            } else {
                HStack {
                    Text(sleep.bedtime.formatted(date: .omitted, time: .shortened))
                    Spacer(minLength: 0)
                    Text(SleepSummary.format(sleep.inBed) + " in bed")
                    Spacer(minLength: 0)
                    Text(sleep.wakeTime.formatted(date: .omitted, time: .shortened))
                }
                .font(design.bodyFont)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            }
        }
    }

    private var summaryLabel: String {
        "Sleep timeline from \(sleep.bedtime.formatted(date: .omitted, time: .shortened)) to "
        + "\(sleep.wakeTime.formatted(date: .omitted, time: .shortened)). "
        + SleepSummary.Stage.allCases.map {
            "\($0.title) \(sleep.percentage($0)) percent"
        }.joined(separator: ", ")
    }
}

/// The night as a single track: one rounded rail, with each stage drawn as a
/// coloured band at its **real time position**. Stage is carried by colour,
/// time by position — no lanes.
///
/// This exists because the lane hypnogram needs height the widget does not
/// have, and the stacked proportional bar it fell back to threw away the one
/// thing worth knowing: *when*. A brief 3am waking and a 3am waking at the
/// very end of the night are the same stacked bar and obviously different
/// here.
///
/// The form is the conventional one for sleep tracking — Apple Health, Oura
/// and most sleep apps draw the night this way.
struct SleepTimelineTrack: View {
    @Environment(\.zonePalette) private var palette
    var sleep: SleepSummary
    var design: Design
    /// Clock labels beneath the rail. Off in the tightest tiles.
    var showsTicks: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: design.px(12)) {
            GeometryReader { proxy in
                let total = max(sleep.inBed, 1)
                let x = { (d: Date) in
                    CGFloat(d.timeIntervalSince(sleep.bedtime) / total) * proxy.size.width
                }
                ZStack(alignment: .leading) {
                    // The rail reads as the whole night even where a stage is
                    // too brief to paint.
                    Capsule(style: .continuous).fill(Palette.ringTrack.opacity(0.55))

                    // A hairline of rail between bands. Butted together, a
                    // night with twenty-odd transitions reads as a barcode;
                    // the gap is what turns it into distinct blocks.
                    let gap = design.px(5)
                    ForEach(sleep.intervals) { interval in
                        let w = x(interval.end) - x(interval.start)
                        RoundedRectangle(cornerRadius: design.px(8), style: .continuous)
                            .fill(stageTint(interval.stage, palette))
                            .frame(width: max(design.px(6), w - gap))
                            .offset(x: x(interval.start) + gap / 2)
                    }
                }
                .clipShape(Capsule(style: .continuous))
            }
            .frame(height: design.px(104))

            if showsTicks {
                GeometryReader { proxy in
                    let total = max(sleep.inBed, 1)
                    ZStack(alignment: .topLeading) {
                        ForEach(ticks, id: \.self) { t in
                            Text(t.formatted(date: .omitted, time: .shortened))
                                .font(design.bodyFont)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize()
                                .offset(x: min(max(0,
                                    CGFloat(t.timeIntervalSince(sleep.bedtime) / total) * proxy.size.width - design.px(50)),
                                    proxy.size.width - design.px(110)))
                        }
                    }
                }
                .frame(height: design.px(34))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night from \(sleep.bedtime.formatted(date: .omitted, time: .shortened)) to "
                            + "\(sleep.wakeTime.formatted(date: .omitted, time: .shortened)). "
                            + SleepSummary.Stage.allCases.map { "\($0.title) \(sleep.percentage($0)) percent" }
                                .joined(separator: ", "))
    }

    /// Four evenly spaced marks across the night, ends included.
    private var ticks: [Date] {
        (0..<4).map { sleep.bedtime.addingTimeInterval(sleep.inBed * Double($0) / 3) }
    }
}

/// The breakdown proper: one row per stage with its share and duration.
///
/// A row per stage rather than a grid of cells — "Light 55% · 3h 52m" needs
/// horizontal room, and four columns of it in a narrow window wraps the words
/// letter by letter.
struct SleepStageList: View {
    @Environment(\.zonePalette) private var palette
    var sleep: SleepSummary
    var design: Design
    /// The one-line description of what each stage is for. Off in tight space.
    var showsDetail: Bool = true

    private static let order: [SleepSummary.Stage] = [.deep, .rem, .light, .awake]

    var body: some View {
        VStack(spacing: design.px(18)) {
            ForEach(Self.order) { stage in
                HStack(spacing: design.px(16)) {
                    Capsule(style: .continuous)
                        .fill(stageTint(stage, palette))
                        .frame(width: design.px(10), height: design.px(40))

                    VStack(alignment: .leading, spacing: design.px(2)) {
                        Text(stage.title)
                            .font(design.titleFont)
                            .foregroundStyle(Palette.textPrimary)
                        if showsDetail {
                            Text(stage.detail)
                                .font(design.bodyFont)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }

                    Spacer(minLength: design.px(12))

                    Text("\(sleep.percentage(stage))%")
                        .font(design.titleFont)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .frame(minWidth: design.px(70), alignment: .trailing)

                    Text(SleepSummary.format(sleep.durations[stage] ?? 0))
                        .font(design.bodyFont)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minWidth: design.px(96), alignment: .trailing)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A compact legend for the widget, where a full row per stage will not fit.
struct SleepLegend: View {
    @Environment(\.zonePalette) private var palette
    var sleep: SleepSummary
    var design: Design
    var columns: Int = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: design.px(14)),
                                 count: columns),
                  alignment: .leading, spacing: design.px(16)) {
            ForEach(SleepSummary.Stage.allCases) { stage in
                // Figure first, label under it: the number is what you are
                // scanning for, and the colour dot ties it to the track.
                VStack(alignment: .leading, spacing: design.px(4)) {
                    Text(SleepSummary.format(sleep.durations[stage] ?? 0))
                        .font(design.titleFont)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: design.px(8)) {
                        Circle()
                            .fill(stageTint(stage, palette))
                            .frame(width: design.px(14), height: design.px(14))
                        Text(stage.title)
                            .font(design.bodyFont)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                // Without these a narrow tile breaks "Awake" across lines one
                // letter at a time.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Total sleep duration and the quality score — the two figures Hume leads
/// with.
struct SleepHeadline: View {
    @Environment(\.zonePalette) private var palette
    var sleep: SleepSummary
    var design: Design

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: design.px(18)) {
            VStack(alignment: .leading, spacing: design.px(2)) {
                Text(sleep.formattedDuration)
                    .font(.system(size: design.fontSize(capPixels: 34), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.textPrimary)
                Text("TOTAL SLEEP")
                    .font(design.bodyFont)
                    .tracking(design.px(2))
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: design.px(12))

            VStack(alignment: .trailing, spacing: design.px(2)) {
                HStack(spacing: design.px(8)) {
                    Image(systemName: sleep.zone.symbol)
                    Text("\(sleep.qualityScore)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: design.fontSize(capPixels: 26), weight: .semibold))
                .foregroundStyle(sleep.zone.tint(palette))

                Text("QUALITY")
                    .font(design.bodyFont)
                    .tracking(design.px(2))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        // The window can be narrow; shrink rather than truncate to "5…".
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
