import Foundation

/// ANT+ FE-C (fitness equipment control) carried over Bluetooth, as older Tacx trainers (Neo, Flux, Vortex, Genius)
/// speak it: ANT messages on a Nordic UART-style service. Pages and units follow the ANT+ FE-C device profile.
public enum TacxFEC {
    /// ANT message framing: sync, length, message id, channel, 8 data bytes, XOR checksum.
    static let sync: UInt8 = 0xA4
    static let broadcastData: UInt8 = 0x4E
    static let acknowledgedData: UInt8 = 0x4F
    static let channel: UInt8 = 0x05

    public enum Page: UInt8, Sendable {
        case calibrationRequest = 0x01
        case calibrationProgress = 0x02
        case generalFE = 0x10
        case trainerData = 0x19
        case basicResistance = 0x30
        case targetPower = 0x31
        case windResistance = 0x32
        case trackResistance = 0x33
        case userConfiguration = 0x37
    }

    /// What the trainer reports.
    public struct Reading: Equatable, Sendable {
        public var powerW: Int?
        public var cadenceRpm: Int?
        public var speedKph: Double?
        public var heartRateBpm: Int?
        public var calibration: Calibration?
    }

    public enum Calibration: Equatable, Sendable {
        /// Page 2: spin-down pending; the speed to reach, and whether the current speed is right (nil: not said).
        case inProgress(targetKph: Double?, speedOK: Bool?)
        /// Page 1 back from the trainer: whether the spin-down worked, and how long it took.
        case result(success: Bool, spinDownMs: Int?)
    }

    /// Page 1: ask for a spin-down calibration.
    public static let spinDownRequest: [UInt8] = message([Page.calibrationRequest.rawValue, 0x80, 0, 0, 0, 0, 0, 0])

    // MARK: Out

    /// A data page wrapped as an acknowledged ANT message, ready to write.
    public static func message(_ page: [UInt8]) -> [UInt8] {
        precondition(page.count == 8, "an ANT data page is 8 bytes")
        let body = [sync, 9, acknowledgedData, channel] + page
        return body + [body.reduce(0, ^)]
    }

    /// Page 49: hold a power (ERG), in 0.25 W.
    public static func targetPower(watts: Int) -> [UInt8] {
        let raw = UInt16(clamping: min(max(watts, 0), 4000) * 4)
        return message([Page.targetPower.rawValue, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, UInt8(raw & 0xFF), UInt8(raw >> 8)])
    }

    /// Page 51: the road's grade (0.01 % steps from −200 %) and rolling resistance (5 × 10⁻⁵ steps).
    public static func trackResistance(gradePercent: Double, crr: Double = 0.004) -> [UInt8] {
        let grade = UInt16(clamping: Int(((min(max(gradePercent, -200), 200) + 200) * 100).rounded()))
        let rolling = UInt8(clamping: Int((crr / 0.00005).rounded()))
        return message([Page.trackResistance.rawValue, 0xFF, 0xFF, 0xFF, 0xFF, UInt8(grade & 0xFF), UInt8(grade >> 8), rolling])
    }

    /// Page 50: wind resistance coefficient (0.01 kg/m), wind speed (km/h, offset 127) and drafting factor (0.01).
    public static func windResistance(coefficient: Double = 0.51, windKph: Double = 0, drafting: Double = 1) -> [UInt8] {
        message([Page.windResistance.rawValue, 0xFF, 0xFF, 0xFF, 0xFF,
                 UInt8(clamping: Int((coefficient * 100).rounded())),
                 UInt8(clamping: Int((windKph + 127).rounded())),
                 UInt8(clamping: Int((drafting * 100).rounded()))])
    }

    /// Page 55: rider weight (0.01 kg), bike weight (0.05 kg, 12 bits) and wheel diameter (0.01 m).
    public static func userConfiguration(riderKg: Double, bikeKg: Double, wheelDiameterM: Double = 0.7) -> [UInt8] {
        let rider = UInt16(clamping: Int((riderKg * 100).rounded()))
        let bike = UInt16(clamping: min(Int((bikeKg / 0.05).rounded()), 0xFFF))
        return message([Page.userConfiguration.rawValue, UInt8(rider & 0xFF), UInt8(rider >> 8), 0xFF,
                        0x0F | UInt8((bike & 0x0F) << 4), UInt8(bike >> 4),
                        UInt8(clamping: Int((wheelDiameterM * 100).rounded())), 0x00])
    }

    // MARK: In

    /// Decodes one notification: an ANT broadcast (or acknowledged) message carrying a data page.
    /// Returns nil for anything else, or when the checksum is wrong.
    public static func parse(_ bytes: [UInt8]) -> (page: UInt8, reading: Reading)? {
        guard bytes.count >= 13, bytes[0] == sync, bytes[1] == 9,
              bytes[2] == broadcastData || bytes[2] == acknowledgedData,
              bytes[..<12].reduce(0, ^) == bytes[12] else { return nil }
        let p = Array(bytes[4..<12])
        var r = Reading()
        switch p[0] {
        case Page.generalFE.rawValue:
            let speed = UInt16(p[4]) | UInt16(p[5]) << 8   // 0.001 m/s; 0xFFFF = invalid
            if speed != 0xFFFF { r.speedKph = Double(speed) / 1000 * 3.6 }
            if p[6] != 0xFF, p[6] > 0 { r.heartRateBpm = Int(p[6]) }
        case Page.calibrationProgress.rawValue:
            guard p[1] & 0x80 != 0 else { break }
            let target = UInt16(p[4]) | UInt16(p[5]) << 8   // 0.001 m/s; 0xFFFF = invalid
            let condition = (p[2] >> 6) & 0x03              // 0 n/a, 1 too low, 2 OK
            r.calibration = .inProgress(targetKph: target == 0xFFFF ? nil : Double(target) / 1000 * 3.6,
                                        speedOK: condition == 0 ? nil : condition == 2)
        case Page.calibrationRequest.rawValue:
            let ms = UInt16(p[5]) | UInt16(p[6]) << 8
            r.calibration = .result(success: p[1] & 0x80 != 0, spinDownMs: ms == 0xFFFF ? nil : Int(ms))
        case Page.trainerData.rawValue:
            if p[2] != 0xFF { r.cadenceRpm = Int(p[2]) }
            let power = UInt16(p[5]) | UInt16(p[6] & 0x0F) << 8   // 12 bits; 0xFFF = invalid
            if power != 0xFFF { r.powerW = Int(power) }
        default:
            break
        }
        return (p[0], r)
    }
}
