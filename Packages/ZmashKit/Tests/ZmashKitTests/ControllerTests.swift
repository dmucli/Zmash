import Foundation
import Testing
@testable import ZmashKit

@Suite struct ControllerTests {
    @Test func kindsFromManufacturerData() {
        #expect(ZwiftController.Kind(deviceType: 0x08) == .ride)
        #expect(ZwiftController.Kind(deviceType: 0x0E) == .playFw2)
        #expect(ZwiftController.Kind(deviceType: 0x03) == .playLeft)
        #expect(ZwiftController.Kind(deviceType: 0x02) == .playRight)
        #expect(ZwiftController.Kind(deviceType: 0x09) == .click)
        #expect(ZwiftController.Kind(deviceType: 0x07) == nil) // Ride right: relays through the left
        #expect(ZwiftController.Kind(deviceType: 0x0A) == nil) // Click v2: locked
    }

    /// Play frame: RightPad=1 (left pad), Y/Up pressed (0), others released (1), analog LR = −100.
    @Test func playLeftUpAndPaddle() throws {
        var w = ProtoWire.Writer()
        w.uint(1, 1)
        w.uint(2, 0)
        for n in 3...7 { w.uint(n, 1) }
        w.sint(8, -100)
        let k = try #require(try ZwiftController.decodePlay([0x07] + w.bytes, side: .playLeft))
        #expect(k.pressed == [.up])
        #expect(k.paddles == [.init(location: 0, value: -100)])
    }

    @Test func playRightMapsToRightButtons() throws {
        var w = ProtoWire.Writer()
        w.uint(1, 0)
        for n in 2...5 { w.uint(n, 1) }
        w.uint(6, 0)   // shift pressed
        w.uint(7, 1)
        let k = try #require(try ZwiftController.decodePlay([0x07] + w.bytes, side: .playRight))
        #expect(k.pressed == [.shiftUpRight])
        var m = RideInputMapper()
        #expect(m.update(pressed: k.pressed, paddles: k.paddles, at: 0) == [.shiftUp])
    }

    @Test func clickPlusMinus() throws {
        var plus = ProtoWire.Writer(); plus.uint(1, 0); plus.uint(2, 1)
        var minus = ProtoWire.Writer(); minus.uint(1, 1); minus.uint(2, 0)
        #expect(try ZwiftController.decodeClick([0x37] + plus.bytes)?.pressed == [.shiftUpRight])
        #expect(try ZwiftController.decodeClick([0x37] + minus.bytes)?.pressed == [.shiftUpLeft])
        var m = RideInputMapper()
        #expect(m.update(pressed: [.shiftUpRight], at: 0) == [.shiftUp])
        #expect(m.update(pressed: [.shiftUpLeft], at: 0.1) == [.shiftDown])
    }

    @Test func nonKeypadFramesIgnored() throws {
        #expect(try ZwiftController.keypad([0x15], kind: .playLeft) == nil)
        #expect(try ZwiftController.keypad([0x19, 0x10, 0x50], kind: .ride) == nil)
    }

    @Test func heartRate() throws {
        #expect(try HeartRate.parse([0x00, 142]) == 142)
        #expect(try HeartRate.parse([0x01, 0x2C, 0x01]) == 300)
    }

    /// RR intervals (D150): flag bit 4, 1/1024 s each, after the energy expended when that's there.
    @Test func heartRateCarriesRRIntervals() throws {
        // 72 bpm, two intervals: 850/1024 s and 830/1024 s.
        let m = try HeartRate.measurement([0x10, 72, 0x52, 0x03, 0x3E, 0x03])
        #expect(m.bpm == 72)
        #expect(m.rrMs == [830, 811])
        // With energy expended (flag bit 3) before them.
        let e = try HeartRate.measurement([0x18, 60, 0x10, 0x00, 0x00, 0x04])
        #expect(e.rrMs == [1000])
        // No RR flag: none, even if bytes follow.
        #expect(try HeartRate.measurement([0x00, 60]).rrMs.isEmpty)
    }

    @Test func summaryAndFITCarryHeartRate() {
        let samples = (0..<60).map {
            RideSample(t: $0, powerW: 200, cadenceRpm: 90, speedKph: 30, gradePercent: 0, gear: 12, heartRateBpm: 130 + $0 % 10)
        }
        let s = SessionSummary.from(samples: samples, activeSeconds: 60, distanceM: 500, elevationGainM: 0, kcal: 12)
        #expect(s.maxHeartRateBpm == 139)
        #expect(s.avgHeartRateBpm == 135)
        let fit = Array(FITWriter.encode(startedAt: .now, samples: samples, summary: s))
        #expect(FITWriter.crc16(fit) == 0)
        // Record definition with heart rate: local 6, global 20.
        let def: [UInt8] = [0x46, 0, 0, 20, 0]
        #expect((0...(fit.count - def.count)).contains { Array(fit[$0..<$0 + def.count]) == def })
    }

    @Test func oldSamplesDecodeWithoutHeartRate() throws {
        let json = #"[{"t":0,"powerW":1,"cadenceRpm":2,"speedKph":3,"gradePercent":0,"gear":12}]"#
        let decoded = try JSONDecoder().decode([RideSample].self, from: Data(json.utf8))
        #expect(decoded.first?.heartRateBpm == nil)
    }
}
