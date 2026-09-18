import SwiftUI

struct CompanionView: View {
    @State private var health = HealthReader()
    @State private var sender = RelaySender()
    @State private var busy = false
    /// On by default once a phone is paired: someone who has entered a
    /// pairing code has already said they want their readings on the Mac,
    /// and making them tap Send forever is just friction.
    @State private var autoSend = UserDefaults.standard.object(forKey: "autoSend") as? Bool
        ?? !(UserDefaults.standard.string(forKey: "pairingCode") ?? "").isEmpty
    @State private var watching = false
    @State private var lastSummary: String?
    /// `.numberPad` has no return key, so without somewhere to send focus
    /// the keyboard cannot be dismissed and the field looks unsubmitted.
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("1 · Apple Health") {
                    if health.authorised {
                        Label("Connected to Health", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Health access") {
                            Task { await health.requestAuthorisation() }
                        }
                    }
                    Text(health.status).font(.footnote).foregroundStyle(.secondary)
                }

                Section("2 · Your Mac") {
                    Button("Find my Mac") { sender.findMac() }
                    HStack {
                        TextField("Pairing code", text: $sender.pairingCode)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced))
                            .focused($codeFocused)
                            .onChange(of: sender.pairingCode) { _, new in
                                // Six digits, digits only, and the keypad
                                // puts itself away once the code is whole.
                                let digits = String(new.filter(\.isNumber).prefix(6))
                                if digits != new { sender.pairingCode = digits }
                                if digits.count == 6 { codeFocused = false }
                            }
                        if sender.pairingCode.count == 6 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    Text(sender.note).font(.footnote).foregroundStyle(.secondary)
                }

                Section("3 · Send") {
                    Toggle("Send automatically", isOn: $autoSend)
                        .onChange(of: autoSend) { _, on in
                            UserDefaults.standard.set(on, forKey: "autoSend")
                            Task { await configureWatching(on) }
                        }

                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            Text(busy ? "Sending…" : "Send my latest readings")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || !health.authorised)

                    if let lastSummary {
                        Text(lastSummary).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(autoSend
                         ? "Automatic sending is on. While this app is open, readings go over as soon as Apple Health has them. In the background iOS wakes the app roughly hourly — it will not stop you, but it is not second-by-second, and it stops if you force-quit this app."
                         : "Turn on automatic sending and you will not need to tap this again.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("How often")
                }

                Section {
                    Text("Stress is the one metric this cannot carry. Hume computes it in their own app and there is no Apple Health type for it, so the Mac keeps showing a simulated value for stress until we find a real source. Everything else sent from here is measured.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("What this does not send")
                }
            }
            .navigationTitle("Hume Relay")
            .task {
                // Reconnect and resume on launch, so an already-paired phone
                // needs no tapping at all.
                if !sender.pairingCode.isEmpty { sender.findMac() }
                if autoSend { await configureWatching(true) }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { codeFocused = false }
                }
            }
        }
    }

    /// Turn automatic sending on or off.
    private func configureWatching(_ on: Bool) async {
        guard on else {
            health.stopWatching()
            watching = false
            return
        }
        guard health.authorised else { return }
        if sender.pairingCode.isEmpty { return }
        await health.startWatching {
            // Hops back to the main actor; the observer fires on a
            // background queue.
            Task { @MainActor in await sync() }
        }
        watching = true
        await sync()
    }

    private func sync() async {
        busy = true
        defer { busy = false }
        guard let reading = await health.currentReading(token: sender.pairingCode) else {
            lastSummary = nil
            return
        }
        await sender.send(reading)

        var parts: [String] = []
        if let hr = reading.heartRate { parts.append("\(hr) BPM") }
        if let hrv = reading.hrv { parts.append("HRV \(hrv) ms") }
        if let s = reading.sleep { parts.append("sleep \(s.formattedDuration)") }
        lastSummary = parts.isEmpty ? nil : "Sent: " + parts.joined(separator: " · ")
    }
}

#Preview { CompanionView() }
