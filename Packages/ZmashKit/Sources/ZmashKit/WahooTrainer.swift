import Foundation

/// Wahoo's trainer control from before FTMS (older KICKR, SNAP and CORE firmware): a vendor characteristic on the
/// Cycling Power service. Power and cadence come from the standard Cycling Power measurement; this only steers.
///
/// Byte layouts follow the protocol as open-source trainer apps implement it (GoldenCheetah's Kickr support):
/// an opcode, then little-endian fields. Every command is written with response, one at a time.
public enum WahooTrainer {
    public enum Opcode: UInt8, Sendable {
        case unlock = 0x20
        case setErgMode = 0x42
        case setSimMode = 0x43
        case setSimGrade = 0x46
        case setSimWindSpeed = 0x47
    }

    /// Unlocks the control characteristic; nothing else is accepted before it.
    public static let unlock: [UInt8] = [Opcode.unlock.rawValue, 0xEE, 0xFC]

    /// Hold a power (ERG).
    public static func erg(watts: Int) -> [UInt8] {
        [Opcode.setErgMode.rawValue] + le16(UInt16(clamping: min(max(watts, 0), 2000)))
    }

    /// Switch to simulation: total mass (kg × 100), rolling resistance (Crr × 10 000) and wind resistance
    /// (CdA·ρ/2 in kg/m, × 1000).
    public static func simMode(totalKg: Double, crr: Double = 0.004, windResistance: Double = 0.51) -> [UInt8] {
        [Opcode.setSimMode.rawValue]
            + le16(UInt16(clamping: Int((totalKg * 100).rounded())))
            + le16(UInt16(clamping: Int((crr * 10_000).rounded())))
            + le16(UInt16(clamping: Int((windResistance * 1000).rounded())))
    }

    /// The road's grade in simulation mode: −100 %…+100 % mapped onto 0…65535 (0 % = 32767).
    public static func grade(percent: Double) -> [UInt8] {
        let fraction = min(max(percent / 100, -1), 1)
        return [Opcode.setSimGrade.rawValue] + le16(UInt16(((fraction + 1) * 65535 / 2).rounded(.down)))
    }

    /// Head wind in m/s (negative for a tail wind), offset by 32.768 m/s, × 1000.
    public static func windSpeed(metresPerSecond: Double) -> [UInt8] {
        [Opcode.setSimWindSpeed.rawValue] + le16(UInt16(clamping: Int(((metresPerSecond + 32.768) * 1000).rounded())))
    }

    /// The trainer answers each command on the same characteristic: 0x01, the opcode, then a status (0x01 = done).
    public static func isSuccess(_ response: [UInt8], for opcode: Opcode) -> Bool? {
        guard response.count >= 2, response[0] == 0x01, response[1] == opcode.rawValue else { return nil }
        return response.count < 3 || response[2] == 0x01
    }

    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
}
