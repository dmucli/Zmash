/// Zwift Ride controller protocol (only the left unit is a BLE peripheral; the right one relays through it).
/// Reference: makinolo.com/blog/2024/07/26/zwift-ride-protocol
public enum ZwiftRide {
    /// Bluetooth SIG company identifier for Zwift, Inc.
    public static let manufacturerID: UInt16 = 0x094A

    public enum DeviceType: UInt8, Sendable {
        case rideRight = 0x07
        case rideLeft = 0x08
    }

    /// Handshake written to sync RX. The controller echoes it on sync TX.
    public static let rideOn: [UInt8] = Array("RideOn".utf8)

    /// Short buzz, written to sync RX without response.
    public static let haptic: [UInt8] = [0x12, 0x12, 0x08, 0x0A, 0x06, 0x08, 0x02, 0x10, 0x00, 0x18, 0x20]

    public enum Opcode: UInt8, Sendable {
        case empty = 0x15
        case battery = 0x19
        case keypad = 0x23
        case rideOn = 0x52 // 'R' of the "RideOn" echo
    }

    public enum Message: Equatable, Sendable {
        case rideOn
        case keypad(Keypad)
        case battery(percent: Int)
        case empty
        case unknown(opcode: UInt8, payload: [UInt8])
    }

    public struct Keypad: Equatable, Sendable {
        public var pressed: Buttons
        public var paddles: [Paddle]
        /// Raw field-1 bitmap as sent (inverse logic, 0 = pressed).
        public var rawMap: UInt32
    }

    public struct Paddle: Equatable, Sendable {
        /// 0 = left, 1 = right (2/3 unused on the Ride).
        public var location: Int
        /// −100…100.
        public var value: Int
    }

    public struct Buttons: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        // Masks verified against the byte-level captures in the Zword sketch.
        public static let left = Buttons(rawValue: 0x00001)
        public static let up = Buttons(rawValue: 0x00002)
        public static let right = Buttons(rawValue: 0x00004)
        public static let down = Buttons(rawValue: 0x00008)
        public static let a = Buttons(rawValue: 0x00010)
        public static let b = Buttons(rawValue: 0x00020)
        public static let y = Buttons(rawValue: 0x00040)
        public static let z = Buttons(rawValue: 0x00080)
        public static let shiftUpLeft = Buttons(rawValue: 0x00100)   // left side, upper
        public static let shiftDownLeft = Buttons(rawValue: 0x00200) // left side, middle
        public static let powerUpLeft = Buttons(rawValue: 0x00400)   // left side, lower
        public static let onOffLeft = Buttons(rawValue: 0x00800)
        public static let shiftUpRight = Buttons(rawValue: 0x01000)  // right side, upper
        public static let shiftDownRight = Buttons(rawValue: 0x02000) // right side, middle
        public static let powerUpRight = Buttons(rawValue: 0x04000)  // right side, lower
        public static let onOffRight = Buttons(rawValue: 0x08000)

        public static let known = Buttons(rawValue: 0x0FFFF)

        public static let named: [(button: Buttons, name: String)] = [
            (.up, "Up"), (.down, "Down"), (.left, "Left"), (.right, "Right"),
            (.shiftUpLeft, "L shift up"), (.shiftDownLeft, "L shift down"), (.powerUpLeft, "L power-up"), (.onOffLeft, "L on/off"),
            (.a, "A"), (.b, "B"), (.y, "Y"), (.z, "Z"),
            (.shiftUpRight, "R shift up"), (.shiftDownRight, "R shift down"), (.powerUpRight, "R power-up"), (.onOffRight, "R on/off"),
        ]

        public var names: [String] { Self.named.filter { contains($0.button) }.map(\.name) }
    }

    /// Paddle presses below this magnitude are treated as noise.
    public static let paddleThreshold = 25

    public static func decode(_ bytes: [UInt8]) throws -> Message {
        guard let first = bytes.first else { throw ParseError.truncated(needed: 1, available: 0) }
        if bytes.starts(with: rideOn) { return .rideOn }
        let payload = Array(bytes.dropFirst())
        switch Opcode(rawValue: first) {
        case .keypad:
            return .keypad(try decodeKeypad(payload))
        case .battery:
            let level = try ProtoWire.fields(payload).first { $0.number == 2 }?.uint ?? 0
            return .battery(percent: Int(level))
        case .empty:
            return .empty
        case .rideOn, nil:
            return .unknown(opcode: first, payload: payload)
        }
    }

    static func decodeKeypad(_ payload: [UInt8]) throws -> Keypad {
        var map: UInt32 = 0xFFFF_FFFF
        var paddles: [Paddle] = []
        for field in try ProtoWire.fields(payload) {
            switch field.number {
            case 1:
                map = UInt32(truncatingIfNeeded: field.uint ?? 0xFFFF_FFFF)
            case 3:
                guard let sub = field.bytes else { continue }
                var location = 0
                var value = 0
                for f in try ProtoWire.fields(sub) {
                    if f.number == 1 { location = Int(f.uint ?? 0) }
                    if f.number == 2 { value = Int(f.sint ?? 0) }
                }
                paddles.append(Paddle(location: location, value: value))
            default:
                continue
            }
        }
        let pressed = Buttons(rawValue: ~map & Buttons.known.rawValue)
        return Keypad(pressed: pressed, paddles: paddles, rawMap: map)
    }
}

/// Turns repeated keypad frames into press/release edges.
public struct ButtonEdgeDetector: Sendable {
    public private(set) var held: ZwiftRide.Buttons = []

    public init() {}

    public mutating func update(_ pressed: ZwiftRide.Buttons) -> (down: ZwiftRide.Buttons, up: ZwiftRide.Buttons) {
        let down = pressed.subtracting(held)
        let up = held.subtracting(pressed)
        held = pressed
        return (down, up)
    }
}
