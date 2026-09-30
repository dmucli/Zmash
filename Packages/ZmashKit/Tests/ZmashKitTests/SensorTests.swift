import Foundation
import Testing
@testable import ZmashKit

@Suite struct SensorTests {
    @Test func cscWheelAndCrank() throws {
        // Flags 0x03: wheel 1000 revs at t = 2048, crank 50 revs at t = 1024.
        let m = try CSC.parse([0x03, 0xE8, 0x03, 0x00, 0x00, 0x00, 0x08, 0x32, 0x00, 0x00, 0x04])
        #expect(m.wheelRevolutions == 1000)
        #expect(m.wheelEventTime == 2048)
        #expect(m.crankRevolutions == 50)
        #expect(m.crankEventTime == 1024)
    }

    @Test func cscCrankOnly() throws {
        let m = try CSC.parse([0x02, 0x0A, 0x00, 0x00, 0x04])
        #expect(m.wheelRevolutions == nil)
        #expect(m.crankRevolutions == 10)
        #expect(throws: ParseError.self) { try CSC.parse([0x01, 0x00]) }
    }

    @Test func cyclingPowerWheelData() throws {
        // Flags 0x0010 (wheel data): power 200 W, wheel 500 revs, event 4096 (2 s at 1/2048).
        let m = try CyclingPower.parse([0x10, 0x00, 0xC8, 0x00, 0xF4, 0x01, 0x00, 0x00, 0x00, 0x10])
        #expect(m.powerW == 200)
        #expect(m.wheelRevolutions == 500)
        #expect(m.wheelEventTime == 4096)
    }

    @Test func wheelSpeed() {
        var w = WheelSpeed(ticksPerSecond: 1024)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(w.update(revolutions: 100, eventTime: 0, circumferenceM: 2.105, now: t0) == nil)
        // 4 turns of 2.105 m in 1 s = 8.42 m/s = 30.3 km/h.
        let v = w.update(revolutions: 104, eventTime: 1024, circumferenceM: 2.105, now: t0 + 1)
        #expect(abs(v! - 30.312) < 0.01)
        // Counters wrap.
        var wrap = WheelSpeed(ticksPerSecond: 1024)
        _ = wrap.update(revolutions: .max, eventTime: 65000, circumferenceM: 2, now: t0)
        #expect(wrap.update(revolutions: 1, eventTime: 1000, circumferenceM: 2, now: t0 + 1) != nil)
        // Stopped: no new events for more than 3 s reads 0.
        #expect(w.update(revolutions: 104, eventTime: 1024, circumferenceM: 2.105, now: t0 + 1.5) == nil)
        #expect(w.update(revolutions: 104, eventTime: 1024, circumferenceM: 2.105, now: t0 + 5) == 0)
    }

    @Test func powerCurves() {
        // Kinetic at 20 mph: 5.24482 × 20 + 0.019168 × 8000 = 258.2 W.
        #expect(abs(TrainerPowerCurve.kineticFluid.watts(speedKph: 20 * 1.609344) - 258.24) < 0.1)
        // Every curve rises with speed and is zero at rest.
        for curve in TrainerPowerCurve.allCases {
            #expect(curve.watts(speedKph: 0) == 0)
            #expect(curve.watts(speedKph: 35) > curve.watts(speedKph: 25))
            #expect((120...400).contains(curve.watts(speedKph: 30)))
        }
    }

    @Test func powerMatch() {
        var m = PowerMatch()
        #expect(m.trainerTarget(for: 250) == 250)
        // The power meter reads 10 % above the trainer.
        for _ in 0..<300 { m.add(powerMeterW: 220, trainerW: 200) }
        #expect(abs(m.ratio - 1.1) < 0.01)
        #expect(m.trainerTarget(for: 220) == 200)
        // Coasting and wild readings don't count or are capped.
        m.add(powerMeterW: 20, trainerW: 0)
        #expect(abs(m.ratio - 1.1) < 0.01)
        var wild = PowerMatch()
        wild.add(powerMeterW: 900, trainerW: 100)
        #expect(wild.ratio == 1.25)
    }
}
