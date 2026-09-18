import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.zonePalette) private var palette
    @State private var model = MetricsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Set when the user arrives from the widget, so the tapped metric is
    /// scrolled to and highlighted.
    var highlighted: MetricReading.Kind?
    /// Set when the widget's sleep page was tapped.
    var requestedTab: WidgetPage?
    var requestedGraphExpanded: Bool = false

    @State private var selection: MetricReading.Kind?
    /// The app is a real window, so this is a real tab — unlike the widget,
    /// where the equivalent is a page you step through with a button.
    @State private var page: WidgetPage = .vitals
    @State private var graphExpanded = false
    @State private var showsSuggestions = false

    private let design = Design.dashboard

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onAppear { reveal(highlighted, using: proxy) }
            .onChange(of: highlighted) { _, new in reveal(new, using: proxy) }
        }
        .background(Palette.page)
        .task { model.startPolling() }
        .onDisappear { model.stopPolling() }
        // On macOS `.inactive` only means the window is not frontmost, which
        // happens constantly; `.background` is the real "nobody is looking".
        .onChange(of: scenePhase) { _, phase in
            phase == .background ? model.stopPolling() : model.startPolling()
        }
    }

    /// Split out from `body` so it can be rendered headlessly for pixel
    /// checks — `ImageRenderer` cannot lay out a `ScrollView`.
    var content: some View {
        VStack(spacing: design.px(40)) {
            header
            tabs
            if page == .vitals {
                ringCluster
                if let errorMessage = model.errorMessage {
                    errorBanner(errorMessage)
                }
                detailStack
            } else {
                sleepSection
            }
            footer
        }
        .padding(design.px(48))
        .frame(maxWidth: .infinity)
        // The aurora only appears behind sleep; the vitals page is a
        // readout and does not want a mood.
        .background {
            if page == .sleep { NightBackdrop() } else { Palette.page }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: design.px(16)) {
            Text("HUME BAND")
                .font(design.bodyFont.weight(.semibold))
                .tracking(design.px(4))
                .foregroundStyle(Palette.textSecondary)

            Spacer(minLength: 0)

            // A quiet live dot rather than a coloured pill: the zone colours
            // have to stay meaningful, so chrome does not borrow them.
            // Says where the numbers came from. A screen mixing measured and
            // invented values without saying which is which is the failure
            // mode worth designing against.
            HStack(spacing: design.px(10)) {
                PulsingDot(color: model.isPolling ? palette.tint(.optimal) : Palette.textSecondary,
                           active: model.isPolling,
                           size: design.px(18))
                Text(model.metrics.isLive ? "From your band" : "Simulated")
                    .font(design.bodyFont)
                    .foregroundStyle(model.metrics.isLive ? palette.tint(.optimal)
                                                          : Palette.textSecondary)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: design.px(10)) {
            ForEach(WidgetPage.allCases, id: \.self) { option in
                let on = page == option
                Button {
                    withAnimation(Motion.contents) { page = option }
                } label: {
                    HStack(spacing: design.px(10)) {
                        Image(systemName: option.symbol)
                        Text(option.title)
                    }
                    .font(design.bodyFont.weight(.semibold))
                    .foregroundStyle(on ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, design.px(26))
                    .padding(.vertical, design.px(16))
                    .background(on ? Palette.card : .clear,
                                in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
    }

    /// The sleep section has its own anchor. The dashboard's 112pt ring puts
    /// body text at 24pt and the headline near 53pt, which truncated every
    /// figure on this page to an ellipsis in a 460pt window.
    private var sleepDesign: Design { Design(ringDiameter: 62) }

    @ViewBuilder
    private var sleepSection: some View {
        if let sleep = model.metrics.sleep {
            let d = sleepDesign
            let advice = SleepAdvisor(sleep: sleep).suggestions()
            VStack(spacing: d.px(24)) {
                GlassCard(design: d) {
                    VStack(alignment: .leading, spacing: d.px(26)) {
                        HStack(alignment: .center, spacing: d.px(24)) {
                            VStack(alignment: .leading, spacing: d.px(2)) {
                                Text(sleep.formattedDuration)
                                    .font(.system(size: d.fontSize(capPixels: 34),
                                                  weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(Palette.textPrimary)
                                Text("TOTAL SLEEP")
                                    .font(d.bodyFont)
                                    .tracking(d.px(2))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                            Spacer(minLength: 0)

                            AnimatedScoreBadge(score: sleep.qualityScore,
                                               zone: sleep.zone,
                                               caption: "QUALITY",
                                               design: Design(ringDiameter: 84))
                        }

                        HStack(spacing: d.px(12)) {
                            Text("TIMELINE")
                                .font(d.bodyFont.weight(.semibold))
                                .tracking(d.px(3))
                                .foregroundStyle(Palette.textSecondary)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(Motion.contents) { graphExpanded.toggle() }
                            } label: {
                                HStack(spacing: d.px(8)) {
                                    Image(systemName: graphExpanded
                                          ? "arrow.down.right.and.arrow.up.left"
                                          : "arrow.up.left.and.arrow.down.right")
                                    Text(graphExpanded ? "Smaller" : "Expand")
                                }
                                .font(d.bodyFont.weight(.semibold))
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel(graphExpanded ? "Shrink sleep timeline" : "Expand sleep timeline")
                        }

                        if graphExpanded {
                            SleepHypnogram(sleep: sleep, design: d, isExpanded: true)
                        } else {
                            // Collapsed, the single track says everything the
                            // lanes do in a quarter of the height.
                            SleepTimelineTrack(sleep: sleep, design: d)
                            SleepLegend(sleep: sleep, design: d)
                        }
                        Divider().overlay(Palette.ringTrack)
                        SleepStageList(sleep: sleep, design: d)
                    }
                }

                suggestionSection(advice, d)

                GlassCard(design: d) {
                    VStack(alignment: .leading, spacing: d.px(20)) {
                        Text("SLEEP ARCHITECTURE")
                            .font(d.bodyFont.weight(.semibold))
                            .tracking(d.px(3))
                            .foregroundStyle(Palette.textSecondary)

                        sleepRow("Time in bed", SleepSummary.format(sleep.inBed), "bed.double.fill", d)
                        sleepRow("Efficiency", "\(sleep.efficiency)%", "chart.pie.fill", d)
                        sleepRow("Sleep debt", SleepSummary.format(sleep.sleepDebt), "hourglass", d)
                        sleepRow("Resting heart rate", "\(sleep.restingHeartRate) BPM", "heart.fill", d)
                        sleepRow("HRV", "\(sleep.hrv) ms", "waveform.path.ecg", d)
                        sleepRow("Bedtime",
                                 sleep.bedtime.formatted(date: .omitted, time: .shortened),
                                 "moon.fill", d)
                        sleepRow("Wake",
                                 sleep.wakeTime.formatted(date: .omitted, time: .shortened),
                                 "sun.max.fill", d)
                    }
                }

                Text("Resting heart rate and HRV are measured during deep sleep, as Hume defines them. Deep, REM and Light are shares of total sleep; Awake is a share of the whole sleep period, so they do not sum to 100.")
                    .font(d.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No sleep recorded for last night.")
                .font(sleepDesign.bodyFont)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func suggestionSection(_ advice: [SleepAdvisor.Suggestion], _ d: Design) -> some View {
        VStack(spacing: d.px(18)) {
            Button {
                withAnimation(Motion.contents) { showsSuggestions.toggle() }
            } label: {
                HStack(spacing: d.px(12)) {
                    Image(systemName: "sparkles")
                    Text(showsSuggestions ? "Hide suggestions"
                                          : "How to improve this  ·  \(advice.count)")
                    Spacer(minLength: 0)
                    Image(systemName: showsSuggestions ? "chevron.up" : "chevron.down")
                }
                .font(d.titleFont)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel(showsSuggestions ? "Hide sleep suggestions" : "Show sleep suggestions")

            if showsSuggestions {
                VStack(spacing: d.px(16)) {
                    ForEach(advice) { s in
                        GlassCard(design: d) {
                            HStack(alignment: .top, spacing: d.px(18)) {
                                Image(systemName: s.symbol)
                                    .font(.system(size: d.px(46), weight: .semibold))
                                    .foregroundStyle(palette.tint(.optimal))
                                    .frame(width: d.px(56))

                                VStack(alignment: .leading, spacing: d.px(8)) {
                                    Text(s.title)
                                        .font(d.titleFont)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(s.because)
                                        .font(d.bodyFont)
                                        .foregroundStyle(Palette.textPrimary.opacity(0.75))
                                    Text(s.guidance)
                                        .font(d.bodyFont)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Guidance is quoted from Hume Health's published improvement notes for each metric. General sleep-hygiene prompts, not medical advice — and right now they are reacting to simulated data, not your band.")
                        .font(d.bodyFont)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sleepRow(_ title: String, _ value: String, _ symbol: String, _ d: Design) -> some View {
        HStack(spacing: d.px(14)) {
            Image(systemName: symbol)
                .font(.system(size: d.fontSize(capPixels: 18)))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: d.px(40), alignment: .leading)
            Text(title)
                .font(d.bodyFont)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: d.px(12))
            Text(value)
                .font(d.titleFont)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .lineLimit(1)
    }

    // MARK: - Rings

    /// Heart rate as the hero ring, the other three as satellites — the notch's
    /// own arrangement, which is a row of rings reading left to right.
    private var ringCluster: some View {
        NotchCard(design: design) {
            VStack(spacing: design.px(34)) {
                VStack(spacing: design.ringLabelGap) {
                    ZoneRing(reading: model.metrics.heartRateReading, design: design)
                    zoneCaption(model.metrics.heartRateReading)
                }

                Divider().overlay(Palette.ringTrack)

                HStack(spacing: design.px(30)) {
                    ForEach(model.metrics.allReadings.filter { $0.kind != .heartRate }) { reading in
                        VStack(spacing: design.px(14)) {
                            ZoneRing(reading: reading, design: satellite, showsValue: false)
                            Text(reading.value)
                                .font(satellite.valueFont)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(Palette.textPrimary)
                            Text(reading.shortTitle.uppercased())
                                .font(satellite.bodyFont)
                                .tracking(design.px(2))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var satellite: Design { Design(ringDiameter: design.ringDiameter * 0.52) }

    private func zoneCaption(_ reading: MetricReading) -> some View {
        HStack(spacing: design.px(10)) {
            Image(systemName: reading.zone.symbol)
            Text(reading.zone.label.uppercased())
                .tracking(design.px(3))
        }
        .font(design.bodyFont.weight(.semibold))
        // Large enough to clear 4.5:1 is not guaranteed for the light ramp, so
        // the caption carries a matching glyph and never relies on hue alone.
        .foregroundStyle(reading.zone.tint(palette))
    }

    // MARK: - Detail rows

    private var detailStack: some View {
        VStack(spacing: design.px(24)) {
            ForEach(model.metrics.allReadings) { reading in
                NotchCard(design: design) {
                    VStack(alignment: .leading, spacing: design.px(24)) {
                        MetricRow(reading: reading, design: design)
                        sparkline(for: reading)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: design.cardCorner, style: .continuous)
                        .strokeBorder(reading.zone.tint(palette),
                                      lineWidth: selection == reading.kind ? design.px(5) : 0)
                }
                .animation(Motion.contents, value: selection)
                .id(reading.kind)
            }
        }
    }

    @ViewBuilder
    private func sparkline(for reading: MetricReading) -> some View {
        // Two points only ever draw a straight line, which reads as data when
        // it is not; wait until the series can actually show a shape.
        if model.history.count > 2 {
            Chart(model.history, id: \.capturedAt) { sample in
                LineMark(x: .value("Time", sample.capturedAt),
                         y: .value(reading.title, series(reading.kind, sample)))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: design.px(5), lineCap: .round))
                .foregroundStyle(reading.zone.tint(palette))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            // Without this the domain snaps to zero and a heart rate of 81
            // draws as a flat line pinned to the top of the frame.
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: design.px(110))
            .accessibilityHidden(true)
        }
    }

    private func series(_ kind: MetricReading.Kind, _ sample: HumeMetrics) -> Double {
        switch kind {
        case .heartRate:   Double(sample.heartRate)
        case .stress:      Double(sample.stress)
        case .temperature: sample.skinTemperature
        case .activity:    Double(sample.activity)
        }
    }

    // MARK: - Chrome

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: design.px(12)) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(design.bodyFont)
        .foregroundStyle(palette.tint(.high))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(design.px(26))
        .background(palette.tint(.high).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: design.px(30), style: .continuous))
    }

    private var footer: some View {
        // Built as a plain String: `Text` takes a LocalizedStringKey, which
        // cannot be concatenated with `+`.
        HStack(spacing: 0) {
            Text("Updated ")
            Text(model.metrics.capturedAt, style: .relative)
            Text(" ago · " + provenance)
        }
            .font(design.bodyFont)
            .foregroundStyle(Palette.textSecondary)
    }

    private func applyDeepLink(using proxy: ScrollViewProxy) {
        if let requestedTab {
            withAnimation(Motion.contents) { page = requestedTab }
            if requestedTab == .sleep { graphExpanded = requestedGraphExpanded }
        }
        reveal(highlighted, using: proxy)
    }

    private var provenance: String {
        guard model.metrics.isLive else { return "simulated data" }
        return "from your Hume Band via iPhone"
             + (model.metrics.stressIsSimulated ? " · stress still simulated" : "")
    }

    private func reveal(_ metric: MetricReading.Kind?, using proxy: ScrollViewProxy) {
        selection = metric
        guard let metric else { return }
        withAnimation(Motion.contents) { proxy.scrollTo(metric, anchor: .center) }
    }
}

#Preview {
    DashboardView()
        .frame(width: 460, height: 900)
}
