import Foundation

/// The wire format between the iPhone companion and this Mac.
///
/// One JSON object per line over TCP on the local network. Newline-delimited
/// rather than HTTP because it needs no parser on either end and is trivial
/// to test with `nc`.
///
/// The phone is the only thing that reads HealthKit — HealthKit does not
/// exist on macOS — so the Mac's role is purely to receive.
struct RelayReading: Codable, Sendable, Equatable {
    /// Rejects anything that is not the paired phone. Checked before the
    /// payload is trusted.
    var token: String
    var capturedAt: Date

    var heartRate: Int?
    var restingHeartRate: Int?
    /// Heart rate variability (SDNN) in milliseconds.
    var hrv: Int?
    var skinTemperature: Double?
    var temperatureBaseline: Double?
    /// Hume's 0–100 stress score, when the phone can see one.
    var stress: Int?
    var activity: Int?
    var sleep: SleepSummary?

    /// Merge into the last known reading. The phone sends whatever HealthKit
    /// gave it, which is rarely everything at once — a heart-rate sample
    /// arrives without a sleep summary attached, and overwriting the rest
    /// with nils would make the dashboard flicker between full and empty.
    func applied(to base: HumeMetrics) -> HumeMetrics {
        var m = base
        m.capturedAt = capturedAt
        m.isLive = true
        if let heartRate { m.heartRate = heartRate }
        if let restingHeartRate { m.restingHeartRate = restingHeartRate }
        if let skinTemperature { m.skinTemperature = skinTemperature }
        if let temperatureBaseline { m.temperatureBaseline = temperatureBaseline }
        if let stress {
            m.stress = stress
            m.stressIsSimulated = false
        }
        if let activity { m.activity = activity }
        if let sleep { m.sleep = sleep }
        return m
    }
}

/// One JSON configuration for everything that persists or transmits a
/// reading.
///
/// Plain `.iso8601` truncates to whole seconds, so a timestamp does not
/// survive a round trip — two readings a few hundred milliseconds apart
/// arrive indistinguishable, which breaks ordering and de-duplication. The
/// fractional variant costs nothing and removes that class of bug.
enum HumeJSON {
    /// `.iso8601WithFractionalSeconds` is an `ISO8601DateFormatter` option,
    /// not a `JSONEncoder` strategy, so this goes through `.custom`.
    /// Formatters are built per call rather than shared: they are classes
    /// with no Sendable guarantee, and encoding happens once per save, not
    /// per timeline entry.
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds]
                                     : [.withInternetDateTime]
        return f
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatter(fractional: true).string(from: date))
        }
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // Tolerant on the way in: a cache written before fractional
            // seconds, or a phone that sends whole seconds, must still parse.
            if let date = formatter(fractional: true).date(from: text) { return date }
            if let date = formatter(fractional: false).date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "not an ISO-8601 date: \(text)"))
        }
        return d
    }
}

enum RelayConfig {
    /// Bonjour type, so the phone can find the Mac without typing an address.
    static let serviceType = "_humeband._tcp"
    static let defaultPort: UInt16 = 8787
    static let tokenKey = "relayPairingToken"

    /// A short code the user can read off the Mac and type into the phone.
    static func newToken() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    static var token: String {
        let store = UserDefaults(suiteName: HumeConfig.appGroup)
        if let existing = store?.string(forKey: tokenKey) { return existing }
        let fresh = newToken()
        store?.set(fresh, forKey: tokenKey)
        return fresh
    }

    static func regenerateToken() -> String {
        let fresh = newToken()
        UserDefaults(suiteName: HumeConfig.appGroup)?.set(fresh, forKey: tokenKey)
        return fresh
    }
}
