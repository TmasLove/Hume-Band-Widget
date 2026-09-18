import Foundation
import Network
import Observation

/// Finds the Mac on the local network and sends readings to it.
///
/// Bonjour rather than a typed-in IP address: the Mac's address changes and
/// nobody should have to care. The pairing code is what authorises the
/// payload; discovery only finds the host.
@MainActor
@Observable
final class RelaySender {
    enum State: Equatable {
        case idle
        case searching
        case found(String)
        case sent(Int)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var note = "Not connected."
    private(set) var sentCount = 0

    /// Persisted so the phone stays paired between launches.
    var pairingCode: String {
        didSet { UserDefaults.standard.set(pairingCode, forKey: "pairingCode") }
    }

    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?

    init() {
        pairingCode = UserDefaults.standard.string(forKey: "pairingCode") ?? ""
    }

    // MARK: - Discovery

    func findMac() {
        browser?.cancel()
        state = .searching
        note = "Looking for your Mac on this Wi-Fi…"

        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: RelayConfig.serviceType, domain: nil), using: params)

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let first = results.first else {
                    self.note = "No Mac found yet. Make sure HumeWidgets is open and 'Start receiving' is on, and that both devices are on the same Wi-Fi."
                    return
                }
                self.endpoint = first.endpoint
                if case let .service(name, _, _, _) = first.endpoint {
                    self.state = .found(name)
                    self.note = "Found \(name). Ready to send."
                } else {
                    self.state = .found("Mac")
                    self.note = "Found a Mac. Ready to send."
                }
            }
        }
        b.stateUpdateHandler = { [weak self] s in
            Task { @MainActor in
                if case let .failed(e) = s {
                    self?.state = .failed(e.localizedDescription)
                    self?.note = "Could not search the network: \(e.localizedDescription)"
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        endpoint = nil
        state = .idle
        note = "Not connected."
    }

    // MARK: - Sending

    func send(_ reading: RelayReading) async {
        guard let endpoint else {
            note = "No Mac found yet — tap Find my Mac first."
            return
        }
        guard !pairingCode.isEmpty else {
            note = "Enter the 6-digit pairing code shown on the Mac."
            return
        }

        var payload = reading
        payload.token = pairingCode
        guard let data = try? HumeJSON.encoder.encode(payload) else {
            note = "Could not encode the reading."
            return
        }

        let reply = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let c = NWConnection(to: endpoint, using: .tcp)
            // Exactly one of ready/failed/timeout may resume the
            // continuation, and they arrive on different callbacks, so the
            // "first one wins" rule needs somewhere thread-safe to live.
            let once = ResumeOnce(cont) { c.cancel() }

            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var line = data
                    line.append(0x0A)
                    c.send(content: line, completion: .idempotent)
                    c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { d, _, _, _ in
                        once.finish(d.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                    }
                case .failed(let e):
                    once.finish("error: \(e.localizedDescription)")
                default:
                    break
                }
            }
            c.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { once.finish("timeout") }
        }

        if reply.contains("\"ok\":true") {
            sentCount += 1
            state = .sent(sentCount)
            note = "Sent. The Mac has \(sentCount) reading\(sentCount == 1 ? "" : "s") from this phone."
        } else if reply.contains("bad token") {
            note = "The Mac rejected the pairing code. Check the six digits shown in HumeWidgets › Settings › iPhone."
        } else if reply.contains("timeout") {
            note = "The Mac did not answer. Is 'Start receiving' still on?"
        } else {
            note = "The Mac replied: \(reply.isEmpty ? "nothing" : reply)"
        }
    }
}


/// Resumes a continuation at most once, from whichever callback gets there
/// first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let cont: CheckedContinuation<String, Never>
    private let cleanup: @Sendable () -> Void

    init(_ cont: CheckedContinuation<String, Never>, cleanup: @escaping @Sendable () -> Void) {
        self.cont = cont
        self.cleanup = cleanup
    }

    func finish(_ value: String) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        cleanup()
        cont.resume(returning: value)
    }
}
