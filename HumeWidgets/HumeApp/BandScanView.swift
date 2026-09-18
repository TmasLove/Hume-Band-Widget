import SwiftUI
import AppKit

/// Shows what this Mac can actually see over Bluetooth, and — if the band
/// speaks standard GATT — reads live heart rate from it.
struct BandScanView: View {
    @State private var scanner: BandScanner

    /// `BandScanner` is main-actor isolated, so a default argument cannot
    /// construct one — the view is too, hence the explicit annotation.
    @MainActor
    init(scanner: BandScanner? = nil) {
        _scanner = State(initialValue: scanner ?? BandScanner())
    }

    var body: some View {
        SettingsPane {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            if scanner.heartRate == nil { banner }

            HStack(spacing: 10) {
                Button(scanner.phase.isBusy ? "Scanning…" : "Scan for my band") { scanner.start() }
                    .disabled(scanner.phase.isBusy)
                Button("Stop") { scanner.stop() }
                    .disabled(!scanner.phase.isBusy)
                Spacer(minLength: 0)
                if !scanner.devices.isEmpty {
                    Button("Copy results") { copyResults() }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                if scanner.phase.isBusy { ProgressView().controlSize(.small) }
                Text(scanner.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if scanner.heartRate != nil || scanner.battery != nil { liveCard }
            if !scanner.devices.isEmpty { deviceList }
            if !scanner.gatt.isEmpty { gattDump }
            if scanner.isListening || !scanner.packets.isEmpty { packetLog }
        }
        .padding(SettingsChrome.windowPadding)
        .frame(width: SettingsChrome.paneWidth, alignment: .leading)
    }

    // MARK: - Pieces

    private var banner: some View {
        SettingsRow {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 3) {
                    Text("The dashboard is showing simulated data")
                        .font(.body.weight(.medium))
                    Text("No Bluetooth connection to a Hume Band exists yet. Every number in this app is generated from the clock.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var liveCard: some View {
        SettingsRow(selected: true, accent: .green) {
            HStack(spacing: 16) {
                if let bpm = scanner.heartRate {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(bpm)")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("BPM").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Live from the band").font(.caption).foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
                if let battery = scanner.battery {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(battery)%").font(.body.weight(.medium)).monospacedDigit()
                        Text("Battery").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// A plain stack rather than a `ScrollView`: a scroll view has no
    /// intrinsic height, and in a Settings window — which sizes itself to
    /// fit — `maxHeight` alone collapses it to nothing.
    private var deviceList: some View {
        let shown = Array(scanner.devices.prefix(8))
        return VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
            SettingsSectionHeader(title: "Devices in range")
            ForEach(shown) { d in deviceRow(d) }
            if scanner.devices.count > shown.count {
                Text("+ \(scanner.devices.count - shown.count) weaker signals not shown")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func deviceRow(_ d: BandScanner.Found) -> some View {
        Button { scanner.connect(d) } label: {
            SettingsRow {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(d.name).font(.body.weight(.medium))
                        if d.advertisesHeartRate {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                        Spacer(minLength: 0)
                        Text("\(d.rssi) dBm")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(d.services.isEmpty
                         ? "No services advertised — click to connect and look anyway"
                         : d.services.map(BandScanner.label(for:)).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.name), signal \(d.rssi) decibel-milliwatts. Click to connect.")
    }

    private var gattDump: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
            SettingsSectionHeader(title: "What this device exposes")
            SettingsRow {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(scanner.gatt.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(scanner.isListening ? "Listening…" : "Listen for data") { scanner.listen() }
                    .disabled(scanner.isListening)
                Spacer(minLength: 0)
            }

            SettingsFootnote(text: "Anything marked proprietary needs Hume's own documentation to decode. Listening is read-only — nothing is written to the band, because writing unknown commands to an unknown characteristic can change its settings.")
        }
    }

    /// Raw notification traffic. If a byte tracks your pulse, it will show up
    /// here as a value that drifts while the rest stay fixed.
    private var packetLog: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
            SettingsSectionHeader(title: "Raw notifications (\(scanner.packets.count))")
            SettingsRow {
                if scanner.packets.isEmpty {
                    Text("Subscribed, but the band has not sent anything yet. Most vendor profiles stay silent until the phone app sends them a start command.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(scanner.packets.suffix(12)) { p in
                            HStack(alignment: .top, spacing: 8) {
                                Text(p.characteristic)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(p.hex).textSelection(.enabled)
                            }
                            .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    private func copyResults() {
        var lines = ["Hume Band scan — \(Date().formatted())", ""]
        for d in scanner.devices {
            lines.append("\(d.name)  rssi=\(d.rssi)  heartRateService=\(d.advertisesHeartRate)")
            lines.append("   advertised: \(d.services.isEmpty ? "none" : d.services.joined(separator: ", "))")
        }
        if !scanner.gatt.isEmpty {
            lines.append(""); lines.append("GATT of connected device:")
            lines.append(contentsOf: scanner.gatt)
        }
        if !scanner.packets.isEmpty {
            lines.append(""); lines.append("Raw notifications:")
            for p in scanner.packets { lines.append("  \(p.characteristic)  \(p.hex)") }
        }
        if let hr = scanner.heartRate { lines.append(""); lines.append("LIVE heartRate=\(hr)") }
        if let b = scanner.battery { lines.append("LIVE battery=\(b)%") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

#Preview { BandScanView() }
