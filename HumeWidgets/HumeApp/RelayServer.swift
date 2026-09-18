import Foundation
import Network
import Observation

/// Receives readings from the iPhone companion over the local network.
///
/// HealthKit does not exist on macOS, so the Mac cannot read your Hume data
/// itself. The phone can — the Hume app writes into HealthKit, and HealthKit
/// is Apple's API, not Hume's, so nothing here needs the vendor's
/// permission. This listens for what the phone sends.
///
/// Local network only, by construction: `NWListener` with
/// `requiredInterfaceType = .wifi` plus an explicit check that the peer is a
/// private address. A health relay that answered the open internet would be
/// a genuinely bad idea.
@MainActor
@Observable
final class RelayServer {
    static let shared = RelayServer()

    enum State: Equatable {
        case stopped
        case listening(UInt16)
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var lastReading: Date?
    /// The most recent accepted payload, so the Mac can show the numbers it
    /// received rather than only a count.
    private(set) var lastAccepted: RelayReading?
    private(set) var accepted = 0
    private(set) var rejected = 0
    private(set) var note = "Not listening."

    var token: String = RelayConfig.token

    private static let enabledKey = "relayEnabled"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: HumeConfig.appGroup) }

    /// Restores whatever the user last chose. Without this the relay
    /// forgets it was receiving every time the app restarts, and a phone
    /// set to send automatically has nothing to send to.
    func restoreIfEnabled() {
        if defaultsEnabled { start() }
    }

    private var defaultsEnabled: Bool { Self.defaults?.bool(forKey: Self.enabledKey) ?? false }

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let store = MetricsStore.shared

    func start(port: UInt16 = RelayConfig.defaultPort) {
        guard listener == nil else { return }
        Self.defaults?.set(true, forKey: Self.enabledKey)
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                state = .failed("bad port"); note = "Invalid port \(port)."; return
            }
            let l = try NWListener(using: params, on: nwPort)
            l.service = NWListener.Service(name: Host.current().localizedName ?? "Mac",
                                           type: RelayConfig.serviceType)
            l.newConnectionHandler = { [weak self] (c: NWConnection) in
                Task { @MainActor in self?.accept(c) }
            }
            l.stateUpdateHandler = { [weak self] (s: NWListener.State) in
                Task { @MainActor in
                    switch s {
                    case .ready:
                        self?.state = .listening(port)
                        self?.note = "Listening on port \(port). Pair the phone with code \(self?.token ?? "")."
                    case .failed(let e):
                        self?.state = .failed(e.localizedDescription)
                        self?.note = "Could not listen: \(e.localizedDescription)"
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            state = .failed(error.localizedDescription)
            note = "Could not listen: \(error.localizedDescription)"
        }
    }

    func stop() {
        Self.defaults?.set(false, forKey: Self.enabledKey)
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        state = .stopped
        note = "Not listening."
    }

    func rotateToken() {
        token = RelayConfig.regenerateToken()
        note = "New pairing code: \(token). Existing phones must pair again."
    }

    // MARK: - Connections

    private func accept(_ c: NWConnection) {
        guard Self.isLocal(c.endpoint) else {
            rejected += 1
            c.cancel()
            return
        }
        connections.append(c)
        c.start(queue: .main)
        receive(c, buffer: Data())
    }

    /// Newline-delimited JSON. A single `receive` can land mid-object, so the
    /// tail is carried forward rather than parsed as-is.
    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }

                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = buf[buf.startIndex..<nl]
                    buf = buf[buf.index(after: nl)...]
                    self.handle(Data(line), on: c)
                }

                if done || error != nil {
                    self.connections.removeAll { $0 === c }
                    c.cancel()
                } else {
                    self.receive(c, buffer: Data(buf))
                }
            }
        }
    }

    private func handle(_ line: Data, on c: NWConnection) {
        guard !line.isEmpty else { return }
        guard let reading = try? HumeJSON.decoder.decode(RelayReading.self, from: line) else {
            rejected += 1
            reply(c, #"{"ok":false,"error":"malformed"}"#)
            return
        }
        guard reading.token == token else {
            rejected += 1
            reply(c, #"{"ok":false,"error":"bad token"}"#)
            return
        }

        let merged = reading.applied(to: store.load() ?? .placeholder)
        store.save(merged)
        accepted += 1
        lastReading = .now
        lastAccepted = reading
        note = "Receiving from the phone — \(accepted) reading\(accepted == 1 ? "" : "s") accepted."
        reply(c, #"{"ok":true}"#)
    }

    private func reply(_ c: NWConnection, _ json: String) {
        c.send(content: Data((json + "\n").utf8), completion: .idempotent)
    }

    /// Private-range peers only. This is the difference between a relay on
    /// your Wi-Fi and one exposed to anything that can route to the Mac.
    nonisolated static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a):
            let b = a.rawValue
            guard b.count == 4 else { return false }
            if b[0] == 127 { return true }                      // loopback
            if b[0] == 10 { return true }                       // 10.0.0.0/8
            if b[0] == 192 && b[1] == 168 { return true }       // 192.168.0.0/16
            if b[0] == 172 && (16...31).contains(b[1]) { return true } // 172.16.0.0/12
            if b[0] == 169 && b[1] == 254 { return true }       // link-local
            return false
        case .ipv6(let a):
            return a.isLoopback || a.isLinkLocal || a.rawValue.first.map { $0 & 0xFE == 0xFC } ?? false
        default:
            return false
        }
    }
}
