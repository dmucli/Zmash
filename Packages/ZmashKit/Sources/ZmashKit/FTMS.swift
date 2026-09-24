import Foundation

/// Bluetooth SIG Fitness Machine Service (FTMS 1.0) — the parts an indoor bike needs.
public enum FTMS {

    // MARK: Indoor Bike Data (0x2AD2)

    public struct IndoorBikeData: Equatable, Sendable {
        public var speedKph: Double?
        public var averageSpeedKph: Double?
        public var cadenceRpm: Double?
        public var averageCadenceRpm: Double?
        public var totalDistanceM: Int?
        public var resistanceLevel: Int?
        public var powerW: Int?
        public var averagePowerW: Int?
        public var expendedEnergyKcal: Int?
        public var heartRateBpm: Int?
        public var elapsedTimeS: Int?
        public var remainingTimeS: Int?

        public init() {}
    }

    public static func parseIndoorBikeData(_ bytes: [UInt8]) throws -> IndoorBikeData {
        var r = ByteReader(bytes)
        let flags = try r.uint16()
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        var d = IndoorBikeData()
        // Bit 0 is "More Data": when CLEAR, instantaneous speed is present.
        if !has(0) { d.speedKph = Double(try r.uint16()) / 100 }
        if has(1) { d.averageSpeedKph = Double(try r.uint16()) / 100 }
        if has(2) { d.cadenceRpm = Double(try r.uint16()) / 2 }
        if has(3) { d.averageCadenceRpm = Double(try r.uint16()) / 2 }
        if has(4) { d.totalDistanceM = Int(try r.uint24()) }
        if has(5) { d.resistanceLevel = Int(try r.int16()) }
        if has(6) { d.powerW = Int(try r.int16()) }
        if has(7) { d.averagePowerW = Int(try r.int16()) }
        if has(8) {
            d.expendedEnergyKcal = Int(try r.uint16())
            try r.skip(3) // energy per hour (uint16) + per minute (uint8)
        }
        if has(9) { d.heartRateBpm = Int(try r.uint8()) }
        if has(10) { try r.skip(1) } // metabolic equivalent
        if has(11) { d.elapsedTimeS = Int(try r.uint16()) }
        if has(12) { d.remainingTimeS = Int(try r.uint16()) }
        return d
    }

    // MARK: Fitness Machine Feature (0x2ACC)

    public struct Features: Equatable, Sendable {
        public var machine: UInt32
        public var targetSettings: UInt32

        public var supportsPowerTarget: Bool { targetSettings & (1 << 3) != 0 }
        public var supportsIndoorBikeSimulation: Bool { targetSettings & (1 << 13) != 0 }
        public var supportsResistanceTarget: Bool { targetSettings & (1 << 2) != 0 }
    }

    public static func parseFeatures(_ bytes: [UInt8]) throws -> Features {
        var r = ByteReader(bytes)
        return Features(machine: try r.uint32(), targetSettings: try r.uint32())
    }

    // MARK: Control Point (0x2AD9)

    public enum ControlOpcode: UInt8, Sendable {
        case requestControl = 0x00
        case reset = 0x01
        case setTargetResistance = 0x04
        case setTargetPower = 0x05
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case setIndoorBikeSimulation = 0x11
        case setWheelCircumference = 0x12
        case spinDownControl = 0x13
        case responseCode = 0x80
    }

    public enum ControlCommand {
        public static let requestControl: [UInt8] = [ControlOpcode.requestControl.rawValue]
        public static let reset: [UInt8] = [ControlOpcode.reset.rawValue]
        public static let start: [UInt8] = [ControlOpcode.startOrResume.rawValue]
        public static let stop: [UInt8] = [ControlOpcode.stopOrPause.rawValue, 0x01]
        /// Spin Down Control, "start" (FTMS 4.16.2.20).
        public static let startSpinDown: [UInt8] = [ControlOpcode.spinDownControl.rawValue, 0x01]

        public static func targetPower(_ watts: Int) -> [UInt8] {
            var w = ByteWriter()
            w.uint8(ControlOpcode.setTargetPower.rawValue)
            w.int16(Int16(clamping: watts))
            return w.bytes
        }

        /// - Parameters:
        ///   - windMps: headwind, m/s (resolution 0.001)
        ///   - gradePercent: % (resolution 0.01)
        ///   - crr: rolling resistance coefficient (resolution 0.0001)
        ///   - cw: wind resistance coefficient, kg/m (resolution 0.01)
        public static func simulation(windMps: Double = 0, gradePercent: Double, crr: Double = 0.004, cw: Double = 0.51) -> [UInt8] {
            var w = ByteWriter()
            w.uint8(ControlOpcode.setIndoorBikeSimulation.rawValue)
            w.int16(Int16(clamping: Int((windMps * 1000).rounded())))
            w.int16(Int16(clamping: Int((gradePercent * 100).rounded())))
            w.uint8(UInt8(clamping: Int((crr * 10000).rounded())))
            w.uint8(UInt8(clamping: Int((cw * 100).rounded())))
            return w.bytes
        }
    }

    public enum ResultCode: UInt8, Sendable {
        case success = 0x01
        case notSupported = 0x02
        case invalidParameter = 0x03
        case failed = 0x04
        case controlNotPermitted = 0x05

        public var label: String {
            switch self {
            case .success: "success"
            case .notSupported: "not supported"
            case .invalidParameter: "invalid parameter"
            case .failed: "failed"
            case .controlNotPermitted: "control not permitted"
            }
        }
    }

    public struct ControlResponse: Equatable, Sendable {
        public var requestOpcode: UInt8
        public var result: ResultCode?
        public var rawResult: UInt8
    }

    public static func parseControlResponse(_ bytes: [UInt8]) throws -> ControlResponse {
        var r = ByteReader(bytes)
        guard try r.uint8() == ControlOpcode.responseCode.rawValue else {
            throw ParseError.malformed("not a control point response")
        }
        let op = try r.uint8()
        let result = try r.uint8()
        return ControlResponse(requestOpcode: op, result: ResultCode(rawValue: result), rawResult: result)
    }

    /// The speeds to reach before coasting, from a successful Spin Down Control response (km/h).
    public static func spinDownTargets(_ bytes: [UInt8]) -> (lowKph: Double, highKph: Double)? {
        var r = ByteReader(bytes)
        guard (try? r.uint8()) == ControlOpcode.responseCode.rawValue, (try? r.uint8()) == ControlOpcode.spinDownControl.rawValue,
              (try? r.uint8()) == ResultCode.success.rawValue,
              let low = try? r.uint16(), let high = try? r.uint16() else { return nil }
        return (Double(low) / 100, Double(high) / 100)
    }

    public enum SpinDownStatus: UInt8, Sendable {
        case requested = 0x01, success = 0x02, error = 0x03, stopPedalling = 0x04
    }

    /// A Spin Down Status notification (Fitness Machine Status op 0x14), if that's what this is.
    public static func spinDownStatus(_ bytes: [UInt8]) -> SpinDownStatus? {
        guard bytes.count >= 2, bytes[0] == 0x14 else { return nil }
        return SpinDownStatus(rawValue: bytes[1])
    }

    // MARK: Fitness Machine Status (0x2ADA)

    public static func describeStatus(_ bytes: [UInt8]) -> String {
        guard let op = bytes.first else { return "empty" }
        switch op {
        case 0x01: return "reset"
        case 0x02: return "stopped/paused by user"
        case 0x04: return "started/resumed by user"
        case 0x07: return "target power changed"
        case 0x12: return "indoor bike simulation parameters changed"
        case 0xFF: return "control permission lost"
        default: return String(format: "status 0x%02x", op)
        }
    }

    // MARK: Supported Inclination Range (0x2AD5)

    public static func parseInclinationRange(_ bytes: [UInt8]) throws -> (min: Double, max: Double, step: Double) {
        var r = ByteReader(bytes)
        return (Double(try r.int16()) / 10, Double(try r.int16()) / 10, Double(try r.uint16()) / 10)
    }
}

/// Cycling Power Service measurement (0x2A63) — fallback source for power and cadence.
public enum CyclingPower {
    public struct Measurement: Equatable, Sendable {
        public var powerW: Int
        public var crankRevolutions: UInt16?
        /// Last crank event time, 1/1024 s.
        public var crankEventTime: UInt16?
        /// Cumulative wheel revolutions and last wheel event time (1/2048 s), from power meters that count them.
        public var wheelRevolutions: UInt32?
        public var wheelEventTime: UInt16?
    }

    public static func parse(_ bytes: [UInt8]) throws -> Measurement {
        var r = ByteReader(bytes)
        let flags = try r.uint16()
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        var m = Measurement(powerW: Int(try r.int16()))
        if has(0) { try r.skip(1) } // pedal power balance
        if has(2) { try r.skip(2) } // accumulated torque
        if has(4) {
            m.wheelRevolutions = try r.uint32()
            m.wheelEventTime = try r.uint16()
        }
        if has(5) {
            m.crankRevolutions = try r.uint16()
            m.crankEventTime = try r.uint16()
        }
        return m
    }
}

/// Derives cadence from successive cumulative crank-revolution samples.
public struct CrankCadence: Sendable {
    /// With no new crank event for this long, the cranks have stopped.
    public static let stoppedAfter: TimeInterval = 3
    private var last: (revs: UInt16, time: UInt16)?
    private var lastEventAt: TimeInterval?
    public init() {}

    /// `now` is a clock in seconds (the system uptime by default), used to notice that pedalling stopped.
    public mutating func update(revolutions: UInt16, eventTime: UInt16,
                                at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        defer { last = (revolutions, eventTime) }
        guard let last else {
            lastEventAt = now
            return nil
        }
        let dRevs = revolutions &- last.revs
        let dTime = eventTime &- last.time
        guard dTime > 0 else {
            // The same crank event again: no new pedal stroke. After a few seconds, that's 0 rpm.
            if let at = lastEventAt, now - at >= Self.stoppedAfter { return 0 }
            return nil
        }
        lastEventAt = now
        return Double(dRevs) * 60 * 1024 / Double(dTime)
    }
}
