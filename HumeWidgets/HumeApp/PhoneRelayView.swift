import SwiftUI

/// The route that does not depend on Hume publishing anything.
///
/// The band writes into Apple Health on the phone. HealthKit is Apple's API,
/// not Hume's, so reading your own data there needs nobody's permission —
/// and it carries sleep stages and HRV that the band's Bluetooth profile
/// never would.
struct PhoneRelayView: View {
    @State private var relay = RelayServer.shared

    private var running: Bool { relay.state != .stopped }

    var body: some View {
        SettingsPane {
            VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
                VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
                    SettingsSectionHeader(title: "Receive from your iPhone")

                    SettingsRow(selected: running, accent: .green) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button(running ? "Stop receiving" : "Start receiving") {
                                    running ? relay.stop() : relay.start()
                                }
                                .buttonStyle(.borderedProminent)

                                if running {
                                    Spacer(minLength: 0)
                                    Text("\(relay.accepted) received")
                                        .font(.caption)
                                        .foregroundStyle(relay.accepted > 0 ? .green : .secondary)
                                }
                            }

                            Text(relay.note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if running { pairingRow }
                    if let last = relay.lastAccepted { receivedRow(last) }
                }

                steps

                SettingsFootnote(text: "The Mac accepts connections from private network addresses only — loopback, 10.x, 192.168.x, 172.16–31.x and link-local. Anything routed from outside your network is refused before the payload is read.")
            }
            .padding(SettingsChrome.windowPadding)
        }
    }

    private var pairingRow: some View {
        SettingsRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing code").font(.caption).foregroundStyle(.secondary)
                    Text(relay.token)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("New code") { relay.rotateToken() }
                    .controlSize(.small)
            }
        }
    }

    /// Proof, in the user's own numbers.
    private func receivedRow(_ r: RelayReading) -> some View {
        SettingsRow(selected: true, accent: .green) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Received from your iPhone", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)

                HStack(alignment: .top, spacing: 18) {
                    if let hr = r.heartRate { figure("\(hr)", "BPM") }
                    if let hrv = r.hrv { figure("\(hrv)", "HRV ms") }
                    if let rhr = r.restingHeartRate { figure("\(rhr)", "Resting") }
                    if let t = r.skinTemperature {
                        figure(t.formatted(.number.precision(.fractionLength(1))), "Wrist °C")
                    }
                    if let s = r.sleep { figure(s.formattedDuration, "Slept") }
                    Spacer(minLength: 0)
                }

                Text("at \(r.capturedAt.formatted(date: .omitted, time: .standard))"
                     + (r.stress == nil ? " · stress not carried by Health, still simulated" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
            SettingsSectionHeader(title: "How it works")
            SettingsRow {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Your Hume Band writes readings into Apple Health on your iPhone.")
                    step(2, "The companion app reads them from HealthKit — heart rate, HRV, sleep stages, steps.")
                    step(3, "It finds this Mac on your Wi-Fi and sends them to the pairing code above.")
                    step(4, "The dashboard, widget and desktop panel stop simulating and show your real numbers.")
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview { PhoneRelayView() }
