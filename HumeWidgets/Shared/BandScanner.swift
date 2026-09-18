import Foundation
import CoreBluetooth
import Observation
import OSLog

/// The scan logs what it finds. A Bluetooth diagnostic whose results only
/// exist on screen is hard to help with — this way the findings can be read
/// back with `log show --predicate 'subsystem == "com.tomasroldan.humewidgets"'`.
private let bandLog = Logger(subsystem: "com.tomasroldan.humewidgets", category: "bluetooth")

/// Finds the Hume Band over Bluetooth and, where the band exposes standard
/// GATT services, reads from it.
///
/// This is deliberately two jobs in one screen. The first is diagnostic:
/// list what is advertising and dump a candidate's service tree, because
/// until we have seen it we do not know whether a Mac can read this band at
/// all. The second is the payoff: if the band offers the **standard Heart
/// Rate service (0x180D)**, subscribe to it and show live BPM — that is
/// proof the pipe works, and the point at which the dashboard can stop
/// making numbers up.
///
/// What this cannot do: stress, skin temperature, activity and sleep have no
/// standard GATT service. If the band exposes them at all it will be through
/// proprietary characteristics, which is what the GATT dump is for.
@MainActor
@Observable
final class BandScanner: NSObject {
    struct Found: Identifiable, Sendable {
        let id: UUID
        var name: String
        var rssi: Int
        var services: [String]
        var advertisesHeartRate: Bool
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case connecting(String)
        case inspecting(String)
        case live(String)
        /// Discovery finished and there was no standard service to read.
        case inspected(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .scanning, .connecting, .inspecting: true
            default: false
            }
        }
    }

    private(set) var devices: [Found] = []
    private(set) var phase: Phase = .idle
    private(set) var note: String = "Bluetooth scan has not run yet."
    /// Service UUID -> its characteristic lines, so the tree stays a tree.
    private(set) var gattTree: [(service: String, characteristics: [String])] = []

    /// Flattened for display and for the clipboard.
    var gatt: [String] {
        gattTree.flatMap { entry in
            ["Service \(Self.label(for: entry.service))"]
            + (entry.characteristics.isEmpty ? ["    (no characteristics)"] : entry.characteristics)
        }
    }

    /// Raw notification traffic, newest last. Passive only — nothing is ever
    /// written to the band.
    private(set) var packets: [Packet] = []
    private(set) var isListening = false

    struct Packet: Identifiable, Sendable {
        let id = UUID()
        let at: Date
        let characteristic: String
        let bytes: [UInt8]
        var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    }

    /// Live values, once subscribed.
    private(set) var heartRate: Int?
    private(set) var battery: Int?
    private(set) var lastBeat: Date?

    /// Previews and static renders only: a scanner pre-loaded with findings,
    /// so the results layout can be checked without a band in the room. The
    /// list collapsing to nothing was invisible until it was rendered.
    init(sampleDevices: [Found],
         gattTree: [(service: String, characteristics: [String])] = [],
         heartRate: Int? = nil, battery: Int? = nil) {
        super.init()
        self.devices = sampleDevices
        self.gattTree = gattTree
        self.heartRate = heartRate
        self.battery = battery
        self.phase = .scanning
        self.note = "Scanning… \(sampleDevices.count) devices found. Tap one to inspect it."
    }

    override init() { super.init() }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    /// Services still waiting on `didDiscoverCharacteristicsFor`. Without
    /// this there is no moment at which discovery is *done*, so a band with
    /// no Heart Rate service leaves the UI reading "Reading services…"
    /// forever — which is exactly what it did.
    private var pendingServices = 0
    private var foundHeartRate = false
    private var watchdog: Task<Void, Never>?

    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private static let known: [String: String] = [
        "180D": "Heart Rate (standard)",
        "2A37": "Heart Rate Measurement (standard)",
        "180F": "Battery (standard)",
        "1809": "Health Thermometer (standard)",
        "181C": "User Data (standard)",
        "1826": "Fitness Machine (standard)",
        "180A": "Device Information (standard)",
    ]

    static func label(for uuid: String) -> String {
        let short = uuid.uppercased()
        for (k, v) in known where short.hasPrefix(k) { return "\(uuid) — \(v)" }
        return "\(uuid) — proprietary"
    }

    // MARK: - Control

    func start() {
        guard !phase.isBusy else { return }
        devices.removeAll()
        gattTree.removeAll()
        packets.removeAll()
        heartRate = nil
        battery = nil
        note = "Starting Bluetooth…"
        // Creating the manager is what triggers the permission prompt.
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            centralManagerDidUpdateState(central!)
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        phase = .idle
        note = devices.isEmpty ? "Nothing was advertising." : "Stopped."
    }

    /// Connect to a device the user picked, rather than grabbing the first
    /// thing that happens to offer heart rate — that could be a chest strap,
    /// a neighbour's watch, or anything else in range.
    func connect(_ found: Found) {
        guard let central, let p = central.retrievePeripherals(withIdentifiers: [found.id]).first
        else {
            note = "That device is no longer in range."
            return
        }
        central.stopScan()
        watchdog?.cancel()
        gattTree.removeAll()
        packets.removeAll()
        foundHeartRate = false
        pendingServices = 0
        peripheral = p
        p.delegate = self
        phase = .connecting(found.name)
        note = "Connecting to \(found.name)…"
        central.connect(p, options: nil)
    }

    // MARK: - Heart Rate Measurement (Bluetooth SIG 0x2A37)

    /// Layout: a flags byte, then the rate as either uint8 or uint16
    /// little-endian depending on bit 0. The optional energy-expended and
    /// RR-interval fields that follow are not needed here.
    static func parseHeartRate(_ data: Data) -> Int? {
        guard let flags = data.first else { return nil }
        let isWide = flags & 0x01 == 1
        if isWide {
            guard data.count >= 3 else { return nil }
            return Int(UInt16(data[1]) | UInt16(data[2]) << 8)
        } else {
            guard data.count >= 2 else { return nil }
            return Int(data[1])
        }
    }
}

extension BandScanner: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            bandLog.notice("BAND state=poweredOn, scanning")
            phase = .scanning
            note = "Scanning. Keep the band on your wrist and close to the Mac."
            c.scanForPeripherals(withServices: nil,
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .unauthorized:
            bandLog.error("BAND state=unauthorized")
            phase = .failed("denied")
            note = "Bluetooth permission was denied. Turn it on in System Settings › Privacy & Security › Bluetooth, then scan again."
        case .poweredOff:
            bandLog.error("BAND state=poweredOff")
            phase = .failed("off")
            note = "Bluetooth is turned off on this Mac."
        case .unsupported:
            phase = .failed("unsupported")
            note = "This Mac reports no Bluetooth support."
        default:
            note = "Waiting for Bluetooth…"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData d: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (d[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let services = (d[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        // Anonymous beacons with neither a name nor a service tell us nothing
        // and would bury the list.
        guard !name.isEmpty || !services.isEmpty else { return }
        let hr = services.contains { $0.uppercased().hasPrefix("180D") }

        if let i = devices.firstIndex(where: { $0.id == p.identifier }) {
            devices[i].rssi = RSSI.intValue
            if !name.isEmpty { devices[i].name = name }
            if !services.isEmpty { devices[i].services = services }
        } else {
            devices.append(Found(id: p.identifier,
                                 name: name.isEmpty ? "(unnamed device)" : name,
                                 rssi: RSSI.intValue,
                                 services: services,
                                 advertisesHeartRate: hr))
        }
        // Strongest signal first — the band on your wrist should float up.
        devices.sort { $0.rssi > $1.rssi }
        bandLog.notice("BAND found name=\(name, privacy: .public) rssi=\(RSSI.intValue) hr=\(hr) services=\(services.joined(separator: ","), privacy: .public)")
        note = "Scanning… \(devices.count) device\(devices.count == 1 ? "" : "s") found. Tap one to inspect it."
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        phase = .inspecting(p.name ?? "device")
        note = "Connected. Reading services…"
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        bandLog.error("BAND connectFailed \(error?.localizedDescription ?? "unknown", privacy: .public)")
        phase = .failed("connect")
        note = "Could not connect: \(error?.localizedDescription ?? "unknown reason"). Many bands only accept one connection at a time — try closing the Hume app on your phone."
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        heartRate = nil
        phase = .idle
        note = "Disconnected." + (error.map { " (\($0.localizedDescription))" } ?? "")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            phase = .failed("discover")
            note = "Connected, but reading services failed: \(error.localizedDescription)"
            bandLog.error("BAND discoverServices failed \(error.localizedDescription, privacy: .public)")
            return
        }
        let services = p.services ?? []
        guard !services.isEmpty else {
            finishInspection(p, reason: "the band exposed no services to this Mac")
            return
        }
        pendingServices = services.count
        gattTree = services.map { (service: $0.uuid.uuidString, characteristics: []) }
        for s in services {
            p.discoverCharacteristics(nil, for: s)
        }
        note = "Connected. Reading \(services.count) service\(services.count == 1 ? "" : "s")…"
        startWatchdog(p)
    }

    /// Some peripherals simply never answer for a service. Without a deadline
    /// the screen would sit on "Reading…" with no way to tell a slow band
    /// from a silent one.
    private func startWatchdog(_ p: CBPeripheral) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.pendingServices > 0 else { return }
            self.finishInspection(p, reason: "\(self.pendingServices) service(s) never answered")
        }
    }

    private func append(to service: String, _ line: String) {
        guard let i = gattTree.firstIndex(where: { $0.service == service }) else { return }
        gattTree[i].characteristics.append(line)
    }

    /// Subscribe to every characteristic that can notify, and record the raw
    /// bytes. **Read-only**: nothing is written to the band.
    ///
    /// A vendor profile like FFF0/FFF6/FFF7 usually needs a command written
    /// to the write characteristic before it streams anything, but writing
    /// unknown bytes to an unknown characteristic on someone's device can
    /// change settings or worse. Listening costs nothing and cannot break
    /// anything, so it is what this does.
    func listen() {
        guard let p = peripheral else { return }
        var count = 0
        for service in p.services ?? [] {
            for ch in service.characteristics ?? [] where ch.properties.contains(.notify) {
                p.setNotifyValue(true, for: ch)
                count += 1
            }
        }
        isListening = count > 0
        note = isListening
            ? "Listening to \(count) notifying characteristic\(count == 1 ? "" : "s"). Move around or take a reading on the band — anything it sends will appear below as raw bytes."
            : "This device has nothing that notifies, so there is no stream to listen to."
    }

    /// The one place discovery ends, so the UI always reaches a verdict.
    private func finishInspection(_ p: CBPeripheral, reason: String? = nil) {
        watchdog?.cancel()
        watchdog = nil
        pendingServices = 0
        let name = p.name ?? "the band"
        if foundHeartRate {
            phase = .live(name)
            note = "Subscribed to the standard Heart Rate service on \(name). This is live."
        } else {
            phase = .inspected(name)
            let detail = reason.map { " — \($0)" } ?? ""
            note = "\(name) is connected, but it offers no standard service this Mac can read\(detail). "
                 + "Its characteristics are listed below; decoding them needs Hume's own documentation."
            bandLog.notice("BAND inspection complete, no standard HR service. gattLines=\(self.gatt.count)")
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        defer {
            pendingServices = max(0, pendingServices - 1)
            if pendingServices == 0 { finishInspection(p) }
        }
        if let error {
            append(to: s.uuid.uuidString, "    (could not read: \(error.localizedDescription))")
            return
        }
        for ch in s.characteristics ?? [] {
            var props: [String] = []
            if ch.properties.contains(.read) { props.append("read") }
            if ch.properties.contains(.notify) { props.append("notify") }
            if ch.properties.contains(.write) { props.append("write") }
            append(to: s.uuid.uuidString,
                   "    \(Self.label(for: ch.uuid.uuidString)) [\(props.joined(separator: ", "))]")
            bandLog.notice("BAND gatt service=\(s.uuid.uuidString, privacy: .public) char=\(ch.uuid.uuidString, privacy: .public) props=\(props.joined(separator: "|"), privacy: .public)")

            // The two we can actually interpret without vendor documentation.
            if ch.uuid == Self.heartRateMeasurement, ch.properties.contains(.notify) {
                p.setNotifyValue(true, for: ch)
                foundHeartRate = true
            }
            if ch.uuid == Self.batteryLevel, ch.properties.contains(.read) {
                p.readValue(for: ch)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        switch ch.uuid {
        case Self.heartRateMeasurement:
            if let bpm = Self.parseHeartRate(data) {
                heartRate = bpm
                lastBeat = .now
                bandLog.notice("BAND heartRate=\(bpm)")
            }
        case Self.batteryLevel:
            battery = data.first.map(Int.init)
        default:
            // Unknown vendor characteristic: keep the raw bytes so a pattern
            // can be spotted by eye.
            packets.append(Packet(at: .now, characteristic: ch.uuid.uuidString,
                                  bytes: [UInt8](data)))
            if packets.count > 40 { packets.removeFirst(packets.count - 40) }
            bandLog.notice("BAND packet \(ch.uuid.uuidString, privacy: .public) \(data.map { String(format: "%02X", $0) }.joined(), privacy: .public)")
        }
    }
}
