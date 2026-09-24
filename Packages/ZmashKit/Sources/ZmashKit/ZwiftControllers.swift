/// Phase 4: other Zwift controllers, decoded into the Ride's button/paddle vocabulary so the same
/// `RideInputMapper` and `ButtonMap` drive them.
///
/// All share the Ride's service, characteristics and "RideOn" handshake (unencrypted firmware):
/// - **Zwift Ride** and **Zwift Play firmware 2**: keypad opcode 0x23 (see `ZwiftRide`).
/// - **Zwift Play (firmware 1.x)**: each side is its own peripheral; keypad opcode 0x07.
/// - **Zwift Click (v1)**: keypad opcode 0x37, two buttons.
/// - **Zwift Click v2** is not supported: Zwift locks it to third-party apps (24 h unlock via Zwift).
public enum ZwiftController {
    public enum Kind: String, Codable, Sendable {
        case ride          // Zwift Ride, left unit (right relays through it)
        case playFw2       // Zwift Play on firmware 2.x: one peripheral, Ride protocol
        case playLeft      // Zwift Play 1.x, left
        case playRight     // Zwift Play 1.x, right
        case click         // Zwift Click v1

        /// Manufacturer-data device type byte (after the 0x094A company id).
        public init?(deviceType: UInt8) {
            switch deviceType {
            case 0x08: self = .ride
            case 0x0E: self = .playFw2
            case 0x03: self = .playLeft
            case 0x02: self = .playRight
            case 0x09: self = .click
            default: return nil  // 0x07 Ride right (can't connect directly), 0x0A/0x0B Click v2 (locked)
            }
        }

        public var displayName: String {
            switch self {
            case .ride: "Zwift Ride"
            case .playFw2: "Zwift Play"
            case .playLeft: "Zwift Play (left)"
            case .playRight: "Zwift Play (right)"
            case .click: "Zwift Click"
            }
        }

    }

    public static let playKeypadOpcode: UInt8 = 0x07
    public static let clickKeypadOpcode: UInt8 = 0x37

    /// Decodes a Play (1.x) keypad frame, opcode included, into Ride buttons/paddles for `side`.
    /// Fields: 1 RightPad, 2 Y/Up, 3 Z/Left, 4 A/Right, 5 B/Down, 6 Shift, 7 On, 8 Analog LR (sint), 9 Analog UD.
    /// Button status 0 = pressed, 1 = released; absent fields count as released.
    public static func decodePlay(_ bytes: [UInt8], side: Kind) throws -> ZwiftRide.Keypad? {
        guard bytes.first == playKeypadOpcode else { return nil }
        var status: [Int: UInt64] = [:]
        var analogLR = 0
        for f in try ProtoWire.fields(Array(bytes.dropFirst())) {
            if f.number == 8 { analogLR = Int(f.sint ?? 0) }
            else if let v = f.uint { status[f.number] = v }
        }
        func pressed(_ n: Int) -> Bool { status[n] == 0 }
        let right = side == .playRight
        var b: ZwiftRide.Buttons = []
        if pressed(2) { b.insert(right ? .y : .up) }
        if pressed(3) { b.insert(right ? .z : .left) }
        if pressed(4) { b.insert(right ? .a : .right) }
        if pressed(5) { b.insert(right ? .b : .down) }
        if pressed(6) { b.insert(right ? .shiftUpRight : .shiftUpLeft) }
        if pressed(7) { b.insert(right ? .onOffRight : .onOffLeft) }
        let paddle = ZwiftRide.Paddle(location: right ? 1 : 0, value: analogLR)
        return ZwiftRide.Keypad(pressed: b, paddles: [paddle], rawMap: 0)
    }

    /// Decodes a Click (v1) keypad frame: + acts as the right upper button (harder), − as the left upper (easier).
    public static func decodeClick(_ bytes: [UInt8]) throws -> ZwiftRide.Keypad? {
        guard bytes.first == clickKeypadOpcode else { return nil }
        var status: [Int: UInt64] = [:]
        for f in try ProtoWire.fields(Array(bytes.dropFirst())) {
            if let v = f.uint { status[f.number] = v }
        }
        var b: ZwiftRide.Buttons = []
        if status[1] == 0 { b.insert(.shiftUpRight) }
        if status[2] == 0 { b.insert(.shiftUpLeft) }
        return ZwiftRide.Keypad(pressed: b, paddles: [], rawMap: 0)
    }

    /// Decodes any frame for a controller of `kind` into a keypad state (nil for non-keypad frames).
    public static func keypad(_ bytes: [UInt8], kind: Kind) throws -> ZwiftRide.Keypad? {
        switch kind {
        case .ride, .playFw2:
            if case .keypad(let k) = try ZwiftRide.decode(bytes) { return k }
            return nil
        case .playLeft, .playRight:
            return try decodePlay(bytes, side: kind)
        case .click:
            return try decodeClick(bytes)
        }
    }
}

/// Bluetooth SIG Heart Rate service (0x180D), measurement characteristic 0x2A37.
public enum HeartRate {
    public static let service = "180D"
    public static let measurement = "2A37"

    public static func parse(_ bytes: [UInt8]) throws -> Int {
        var r = ByteReader(bytes)
        let flags = try r.uint8()
        return flags & 0x01 == 0 ? Int(try r.uint8()) : Int(try r.uint16())
    }
}
