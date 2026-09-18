import SwiftUI

/// Zone colour choice. Native Settings typography — the Codenotch scale is
/// for the data surfaces, not for a preferences pane.
struct SettingsView: View {
    @State private var settings = ZoneSettings.shared

    var body: some View {
        SettingsPane {
            body_
        }
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
                SettingsSectionHeader(title: "Zone colours")
                ForEach(ZonePalette.allCases) { option in
                    paletteRow(option)
                }
            }

            SettingsFootnote(text: "Colour is never the only signal — each zone keeps its own icon and label, so a reading stays clear in any palette. The widget and the desktop panel follow this choice too. Also available from the View menu.")
        }
        .padding(SettingsChrome.windowPadding)
    }

    private func paletteRow(_ option: ZonePalette) -> some View {
        let on = settings.palette == option
        return Button {
            settings.palette = option
        } label: {
            SettingsRow(selected: on, accent: option.tint(.optimal)) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: on ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(on ? option.tint(.optimal) : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title).font(.body.weight(.medium))
                        Text(option.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        swatches(option)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("\(option.title). \(option.detail)")
    }

    /// Zones on the left, sleep stages on the right — both ramps change with
    /// the choice, so both are previewed.
    private func swatches(_ option: ZonePalette) -> some View {
        HStack(spacing: 10) {
            ForEach(MetricZone.allCases, id: \.self) { zone in
                HStack(spacing: 3) {
                    Image(systemName: zone.symbol)
                    Text(zone.label)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(option.tint(zone))
            }

            Divider().frame(height: 11)

            ForEach(SleepSummary.Stage.allCases) { stage in
                HStack(spacing: 3) {
                    Circle().fill(option.stageTint(stage)).frame(width: 7, height: 7)
                    Text(stage.title)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

#Preview { SettingsView() }
