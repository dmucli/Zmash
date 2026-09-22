/// Zwift trainer protocol ("Zwift Hub" protocol), carried on the same custom service as the Ride.
/// Trainers that support Zwift virtual shifting accept a gear ratio and grade and handle the feel themselves.
/// Reference: makinolo.com/blog/2024/10/20/zwift-trainer-protocol
public enum ZwiftTrainer {
    public enum Opcode: UInt8, Sendable {
        case get = 0x00
        case ridingData = 0x03      // trainer → app
        case configSet = 0x04       // app → trainer
        case configStatus = 0x05
        case battery = 0x19
        case getResponse = 0x3C
        case statusResponse = 0x3E
    }

    /// Values Zwift itself sends; Makinolo reports erratic behaviour when they differ much.
    public static let zwiftCWa: UInt64 = 5100   // CW·a × 10000
    public static let zwiftCrr: UInt64 = 400    // Crr × 100000

    /// Builds a `TRAINER_CONFIG_SET` (0x04) command.
    /// Layout: TrainerConfigSet { 4: envSim { 1: wind sint, 2: grade sint, 3: CW, 4: Crr }, 5: bikeSim { 2: virtual gear ratio, 4: bike mass, 5: rider mass } }
    public static func configSet(
        gradePercent: Double? = nil,
        windMps: Double = 0,
        gearRatio: Double? = nil,
        bikeKg: Double? = nil,
        riderKg: Double? = nil
    ) -> [UInt8] {
        var message = ProtoWire.Writer()
        if let gradePercent {
            var env = ProtoWire.Writer()
            env.sint(1, Int64((windMps * 100).rounded()))
            env.sint(2, Int64((gradePercent * 100).rounded()))
            env.uint(3, zwiftCWa)
            env.uint(4, zwiftCrr)
            message.message(4, env)
        }
        if gearRatio != nil || bikeKg != nil || riderKg != nil {
            var bike = ProtoWire.Writer()
            if let gearRatio { bike.uint(2, UInt64(max(0, (gearRatio * 10000).rounded()))) }
            if let bikeKg { bike.uint(4, UInt64(max(0, (bikeKg * 100).rounded()))) }
            if let riderKg { bike.uint(5, UInt64(max(0, (riderKg * 100).rounded()))) }
            message.message(5, bike)
        }
        return [Opcode.configSet.rawValue] + message.bytes
    }

    public struct RidingData: Equatable, Sendable {
        public var powerW: Int
        public var cadenceRpm: Int
        public var speedKph: Double
        public var averagePowerW: Int?
        public var wheelSpeed: Int?
        public var realGearRatio: Double?
    }

    /// Decodes a `TRAINER_NOTIF` (0x03) frame, opcode included.
    public static func decodeRidingData(_ bytes: [UInt8]) throws -> RidingData {
        guard bytes.first == Opcode.ridingData.rawValue else { throw ParseError.malformed("not riding data") }
        var d = RidingData(powerW: 0, cadenceRpm: 0, speedKph: 0)
        for f in try ProtoWire.fields(Array(bytes.dropFirst())) {
            guard let v = f.uint else { continue }
            switch f.number {
            case 1: d.powerW = Int(v)
            case 2: d.cadenceRpm = Int(v)
            case 3: d.speedKph = Double(v) / 100
            case 4: d.averagePowerW = Int(v)
            case 5: d.wheelSpeed = Int(v)
            case 6: d.realGearRatio = Double(v) / 10000
            default: break
            }
        }
        return d
    }
}
