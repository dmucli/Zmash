import Foundation

/// Latest reading from the trainer, whatever protocol produced it.
public struct TrainerMetrics: Equatable, Sendable {
    public var powerW: Int
    public var cadenceRpm: Double
    /// Speed as reported by the trainer (flywheel speed on FTMS, virtual speed on the Zwift protocol).
    public var trainerSpeedKph: Double?
    public var timestamp: Date

    public init(powerW: Int, cadenceRpm: Double, trainerSpeedKph: Double?, timestamp: Date = .now) {
        self.powerW = powerW
        self.cadenceRpm = cadenceRpm
        self.trainerSpeedKph = trainerSpeedKph
        self.timestamp = timestamp
    }

    /// Clamps out-of-range values (brief §6.4).
    public var sanitized: TrainerMetrics {
        var m = self
        m.powerW = min(max(powerW, 0), 2000)
        m.cadenceRpm = min(max(cadenceRpm, 0), 200)
        return m
    }
}

public enum LinkState: Equatable, Sendable {
    case bluetoothOff
    case unpaired
    /// Paired; waiting for the device to appear (connect requests never time out).
    case searching
    /// Connected; discovering services or handshaking.
    case connecting
    case ready

    public var isReady: Bool { self == .ready }
}

public enum TrainerProtocol: String, CaseIterable, Sendable {
    case ftms
    case zwift
}

public enum TrainerProtocolPreference: String, CaseIterable, Sendable {
    case auto
    case ftms
    case zwift
}

public extension ZwiftRide {
    /// Last firmware known to work with third-party apps.
    static let lastSupportedFirmware = "1.2.0"

    /// `false` when `firmware` is newer than 1.2.0 (possibly locked), `nil` if it can't be parsed.
    static func isFirmwareSupported(_ firmware: String) -> Bool? {
        func parts(_ s: String) -> [Int]? {
            let numbers = s.split(whereSeparator: { !$0.isNumber }).prefix(3).compactMap { Int($0) }
            return numbers.isEmpty ? nil : numbers + Array(repeating: 0, count: 3 - numbers.count)
        }
        guard let f = parts(firmware), let s = parts(lastSupportedFirmware) else { return nil }
        return f.lexicographicallyPrecedes(s) || f == s
    }
}
