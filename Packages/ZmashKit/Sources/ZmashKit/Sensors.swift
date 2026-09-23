import Foundation

/// Cycling Speed and Cadence (0x1816): wheel and crank revolution counters from a speed or cadence sensor.
public enum CSC {
    public static let service = "1816"
    public static let measurement = "2A5B"

    public struct Measurement: Equatable, Sendable {
        public var wheelRevolutions: UInt32?
        /// Last wheel event time, 1/1024 s.
        public var wheelEventTime: UInt16?
        public var crankRevolutions: UInt16?
        /// Last crank event time, 1/1024 s.
        public var crankEventTime: UInt16?
    }

    public static func parse(_ bytes: [UInt8]) throws -> Measurement {
        var r = ByteReader(bytes)
        let flags = try r.uint8()
        var m = Measurement()
        if flags & 0x01 != 0 {
            m.wheelRevolutions = try r.uint32()
            m.wheelEventTime = try r.uint16()
        }
        if flags & 0x02 != 0 {
            m.crankRevolutions = try r.uint16()
            m.crankEventTime = try r.uint16()
        }
        return m
    }
}

/// Wheel speed from successive cumulative wheel-revolution samples.
public struct WheelSpeed: Sendable {
    /// Event-time ticks per second: 1024 for a CSC sensor, 2048 for a power meter.
    public let ticksPerSecond: Double
    private var last: (revs: UInt32, time: UInt16)?
    private var lastChange = Date.distantPast

    public init(ticksPerSecond: Double = 1024) { self.ticksPerSecond = ticksPerSecond }

    /// km/h, or nil when it can't tell yet. A wheel that hasn't turned for 3 s reads 0 (sensors repeat the last
    /// event time while stopped).
    public mutating func update(revolutions: UInt32, eventTime: UInt16, circumferenceM: Double, now: Date = .now) -> Double? {
        defer { last = (revolutions, eventTime) }
        guard let last else { lastChange = now; return nil }
        let dRevs = revolutions &- last.revs
        let dTime = eventTime &- last.time
        guard dRevs > 0, dTime > 0 else { return now.timeIntervalSince(lastChange) > 3 ? 0 : nil }
        lastChange = now
        guard dRevs < 100 else { return nil } // a counter reset, not 100 turns
        return Double(dRevs) * circumferenceM / (Double(dTime) / ticksPerSecond) * 3.6
    }
}

/// How hard a basic (non-smart) trainer is to push at a given wheel speed: its power curve.
/// The named curves are the makers' published formulas; the two generic ones are rough averages.
public enum TrainerPowerCurve: String, CaseIterable, Codable, Sendable, Identifiable {
    case kineticFluid
    case cycleOpsFluid2
    case genericFluid
    case genericMagnetic

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .kineticFluid: "Kinetic Road Machine / Rock and Roll"
        case .cycleOpsFluid2: "CycleOps (Saris) Fluid 2"
        case .genericFluid: "Other fluid trainer (rough)"
        case .genericMagnetic: "Magnetic trainer, middle setting (rough)"
        }
    }

    /// Watts at a wheel speed in km/h.
    public func watts(speedKph: Double) -> Double {
        let kph = max(speedKph, 0)
        let mph = kph / 1.609344
        let w: Double = switch self {
        // Kurt Kinetic's published curve.
        case .kineticFluid, .genericFluid: 5.244820 * mph + 0.019168 * mph * mph * mph
        // CycleOps' published curve for the Fluid 2.
        case .cycleOpsFluid2: 8.9788 * mph - 0.0137 * mph * mph + 0.0115 * mph * mph * mph
        // Magnetic units stiffen less with speed than fluid ones.
        case .genericMagnetic: 6.6 * kph + 0.0008 * kph * kph * kph
        }
        return max(w, 0)
    }
}

/// Keeps a trainer's ERG honest against a power meter: the smoothed ratio of what the pedals read to what the
/// trainer reads, so a target of 250 W at the pedals asks the trainer for 250 ÷ ratio.
public struct PowerMatch: Sendable {
    public private(set) var ratio = 1.0
    private var samples = 0

    public init() {}

    /// Feed a pair of simultaneous readings. Only steady pedalling (both above 60 W) counts; the ratio moves slowly
    /// (about a minute to settle at 1 Hz) and stays within ±25 %, so a dropout or a sprint can't swing it.
    public mutating func add(powerMeterW: Double, trainerW: Double) {
        guard powerMeterW > 60, trainerW > 60 else { return }
        let r = min(max(powerMeterW / trainerW, 0.75), 1.25)
        samples += 1
        let weight = max(1 / Double(samples), 1.0 / 60)
        ratio += (r - ratio) * weight
    }

    /// What to ask the trainer for, so the power meter reads `watts`.
    public func trainerTarget(for watts: Int) -> Int { Int((Double(watts) / ratio).rounded()) }
}
