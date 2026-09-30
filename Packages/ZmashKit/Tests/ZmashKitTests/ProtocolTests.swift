import Testing
@testable import ZmashKit

@Suite struct ProtoWireTests {
    @Test func varintRoundTrip() throws {
        for v: UInt64 in [0, 1, 127, 128, 300, 0xFFFF_FFFF, .max] {
            var i = 0
            #expect(try ProtoWire.readVarint(ProtoWire.varint(v), at: &i) == v)
        }
    }

    @Test func zigzag() {
        #expect(ProtoWire.zigzag(0) == 0)
        #expect(ProtoWire.zigzag(-1) == 1)
        #expect(ProtoWire.zigzag(1) == 2)
        #expect(ProtoWire.unzigzag(ProtoWire.zigzag(-450)) == -450)
    }

    @Test func truncatedInputThrows() {
        #expect(throws: ParseError.self) { try ProtoWire.fields([0x08]) }
        #expect(throws: ParseError.self) { try ProtoWire.fields([0x1A, 0x05, 0x00]) }
    }
}

@Suite struct ZwiftRideTests {
    /// All released, as captured by the Zword sketch.
    static let released: [UInt8] = [
        0x23, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F,
        0x1A, 0x04, 0x08, 0x00, 0x10, 0x00,
        0x1A, 0x04, 0x08, 0x01, 0x10, 0x00,
        0x1A, 0x04, 0x08, 0x02, 0x10, 0x00,
        0x1A, 0x04, 0x08, 0x03, 0x10, 0x00,
    ]

    /// Replaces one byte of the varint bitmap (byte index 2…4 in the frame), as in the Zword captures.
    static func frame(byte index: Int, value: UInt8) -> [UInt8] {
        var f = released
        f[index] = value
        return f
    }

    @Test func releasedFrameHasNoButtons() throws {
        guard case .keypad(let k) = try ZwiftRide.decode(Self.released) else { Issue.record("not keypad"); return }
        #expect(k.pressed.isEmpty)
        #expect(k.paddles.count == 4)
        #expect(k.paddles.allSatisfy { $0.value == 0 })
    }

    /// Byte captures from Zword_v0-0-1.ino, mapped to our masks.
    @Test(arguments: [
        (2, UInt8(0xFD), ZwiftRide.Buttons.up),
        (2, 0xF7, .down),
        (2, 0xFE, .left),
        (2, 0xFB, .right),
        (2, 0xEF, .a),
        (2, 0xBF, .y),
        (2, 0xDF, .b),
        (3, 0xFE, .z),
        (3, 0xEF, .onOffLeft),
        (3, 0xFD, .shiftUpLeft),
        (3, 0xFB, .shiftDownLeft),
        (3, 0xF7, .powerUpLeft),
        (3, 0xDF, .shiftUpRight),
        (3, 0xBF, .shiftDownRight),
        (4, 0xFD, .onOffRight),
        (4, 0xFE, .powerUpRight),
    ])
    func singleButtonCaptures(index: Int, value: UInt8, expected: ZwiftRide.Buttons) throws {
        guard case .keypad(let k) = try ZwiftRide.decode(Self.frame(byte: index, value: value)) else {
            Issue.record("not keypad"); return
        }
        #expect(k.pressed == expected)
    }

    @Test func paddleIsSignedZigzag() throws {
        // Right paddle (location 1) pulled to −100: zigzag(−100) = 199 = varint C7 01.
        let f: [UInt8] = [0x23, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x1A, 0x05, 0x08, 0x01, 0x10, 0xC7, 0x01]
        guard case .keypad(let k) = try ZwiftRide.decode(f) else { Issue.record("not keypad"); return }
        #expect(k.paddles == [.init(location: 1, value: -100)])
    }

    @Test func batteryAndRideOn() throws {
        #expect(try ZwiftRide.decode([0x19, 0x10, 0x62]) == .battery(percent: 98))
        #expect(try ZwiftRide.decode(Array("RideOn".utf8) + [0x01, 0x03]) == .rideOn)
        #expect(try ZwiftRide.decode([0x15]) == .empty)
    }

    @Test func edgeDetector() {
        var d = ButtonEdgeDetector()
        #expect(d.update([.a]) == ([.a], []))
        #expect(d.update([.a]) == ([], []))
        #expect(d.update([.a, .b]) == ([.b], []))
        #expect(d.update([]) == ([], [.a, .b]))
    }
}

@Suite struct FTMSTests {
    @Test func indoorBikeDataSpeedCadencePower() throws {
        // flags 0x0044: speed present (bit 0 clear), cadence (bit 2), power (bit 6)
        let bytes: [UInt8] = [0x44, 0x00, 0x7E, 0x0D, 0xB4, 0x00, 0xC8, 0x00]
        let d = try FTMS.parseIndoorBikeData(bytes)
        #expect(d.speedKph == 34.54)
        #expect(d.cadenceRpm == 90)
        #expect(d.powerW == 200)
        #expect(d.heartRateBpm == nil)
    }

    @Test func indoorBikeDataWalksAllFlags() throws {
        // flags: speed, avg speed(1), cadence(2), distance(4), power(6), energy(8), HR(9), elapsed(11)
        let flags: UInt16 = 1 << 1 | 1 << 2 | 1 << 4 | 1 << 6 | 1 << 8 | 1 << 9 | 1 << 11
        var bytes: [UInt8] = [UInt8(flags & 0xFF), UInt8(flags >> 8)]
        bytes += [0x10, 0x27]        // speed 100.00
        bytes += [0x00, 0x00]        // avg speed
        bytes += [0xA0, 0x00]        // cadence 80
        bytes += [0x10, 0x27, 0x00]  // distance 10000 m
        bytes += [0xFA, 0x00]        // power 250
        bytes += [0x2C, 0x01, 0, 0, 0] // energy 300 kcal
        bytes += [0x8C]              // HR 140
        bytes += [0x3C, 0x00]        // elapsed 60 s
        let d = try FTMS.parseIndoorBikeData(bytes)
        #expect(d.speedKph == 100)
        #expect(d.cadenceRpm == 80)
        #expect(d.totalDistanceM == 10000)
        #expect(d.powerW == 250)
        #expect(d.expendedEnergyKcal == 300)
        #expect(d.heartRateBpm == 140)
        #expect(d.elapsedTimeS == 60)
    }

    @Test func moreDataFrameHasNoSpeed() throws {
        let d = try FTMS.parseIndoorBikeData([0x41, 0x00, 0x64, 0x00])
        #expect(d.speedKph == nil)
        #expect(d.powerW == 100)
    }

    @Test func truncatedThrows() {
        #expect(throws: ParseError.self) { try FTMS.parseIndoorBikeData([0x44, 0x00, 0x7E]) }
    }

    @Test func simulationCommand() {
        // grade 4.5 % → 450 = 0x01C2; crr 0.004 → 40; cw 0.51 → 51
        #expect(FTMS.ControlCommand.simulation(gradePercent: 4.5) == [0x11, 0x00, 0x00, 0xC2, 0x01, 40, 51])
        // grade −10 % → −1000 = 0xFC18
        #expect(Array(FTMS.ControlCommand.simulation(gradePercent: -10)[3...4]) == [0x18, 0xFC])
    }

    @Test func controlResponse() throws {
        let r = try FTMS.parseControlResponse([0x80, 0x11, 0x05])
        #expect(r.requestOpcode == 0x11)
        #expect(r.result == .controlNotPermitted)
    }

    @Test func features() throws {
        let f = try FTMS.parseFeatures([0, 0, 0, 0, 0x08, 0x20, 0, 0])
        #expect(f.supportsPowerTarget)
        #expect(f.supportsIndoorBikeSimulation)
    }

    @Test func cyclingPowerWithCrank() throws {
        var c = CrankCadence()
        let m1 = try CyclingPower.parse([0x20, 0x00, 0xC8, 0x00, 0x0A, 0x00, 0x00, 0x04])
        #expect(m1.powerW == 200)
        #expect(c.update(revolutions: m1.crankRevolutions!, eventTime: m1.crankEventTime!) == nil)
        // +1.5 rev in 1 s (1024 ticks) → 90 rpm; use +3 revs in 2 s
        #expect(c.update(revolutions: 13, eventTime: 0x0400 &+ 2048) == 90)
    }

    @Test func crankCadenceDropsToZeroWhenPedallingStops() {
        var c = CrankCadence()
        _ = c.update(revolutions: 10, eventTime: 0, at: 0)
        #expect(c.update(revolutions: 13, eventTime: 2048, at: 2) == 90)
        // The cranks stop: the meter keeps repeating the last event.
        #expect(c.update(revolutions: 13, eventTime: 2048, at: 3) == nil)
        #expect(c.update(revolutions: 13, eventTime: 2048, at: 5.5) == 0)
    }
}

@Suite struct ZwiftTrainerTests {
    @Test func configSetEncodesGradeAndGear() throws {
        let bytes = ZwiftTrainer.configSet(gradePercent: -2.5, gearRatio: 2.4, bikeKg: 9, riderKg: 75)
        #expect(bytes.first == 0x04)
        let fields = try ProtoWire.fields(Array(bytes.dropFirst()))
        let env = try ProtoWire.fields(try #require(fields.first { $0.number == 4 }?.bytes))
        #expect(env.first { $0.number == 2 }?.sint == -250)
        #expect(env.first { $0.number == 3 }?.uint == 5100)
        #expect(env.first { $0.number == 4 }?.uint == 400)
        let bike = try ProtoWire.fields(try #require(fields.first { $0.number == 5 }?.bytes))
        #expect(bike.first { $0.number == 2 }?.uint == 24000)
        #expect(bike.first { $0.number == 4 }?.uint == 900)
        #expect(bike.first { $0.number == 5 }?.uint == 7500)
    }

    @Test func ridingDataFromMakinoloSample() throws {
        // "03 08 be 01 10 50 18 bd 06 20 00 28 e2 ba 01 30 8b eb 01" → 190 W, 80 rpm, 8.29 km/h
        let bytes: [UInt8] = [0x03, 0x08, 0xBE, 0x01, 0x10, 0x50, 0x18, 0xBD, 0x06, 0x20, 0x00, 0x28, 0xE2, 0xBA, 0x01, 0x30, 0x8B, 0xEB, 0x01]
        let d = try ZwiftTrainer.decodeRidingData(bytes)
        #expect(d.powerW == 190)
        #expect(d.cadenceRpm == 80)
        #expect(d.speedKph == 8.29)
    }
}
