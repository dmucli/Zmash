import Foundation
import Testing
@testable import ZmashKit

@Suite struct RideInputMapperTests {
    typealias B = ZwiftRide.Buttons

    @Test func shiftsFireOnPressEdgeOnly() {
        var m = RideInputMapper()
        #expect(m.update(pressed: [.shiftUpRight], at: 0) == [.shiftUp])
        #expect(m.update(pressed: [.shiftUpRight], at: 0.1) == [])
        #expect(m.update(pressed: [], at: 0.2) == [])
        #expect(m.update(pressed: [.shiftDownRight], at: 0.3) == [.shiftDown])
        #expect(m.update(pressed: [.shiftUpLeft], at: 0.4) == [.shiftDown])
        #expect(m.update(pressed: [.shiftDownLeft], at: 0.5) == [.shiftDown])
    }

    @Test func pauseAndTheme() {
        var m = RideInputMapper()
        #expect(m.update(pressed: [.a], at: 0) == [.pauseToggle])
        #expect(m.update(pressed: [], at: 0.1) == [])
        #expect(m.update(pressed: [.z], at: 0.2) == [.pauseToggle])
        #expect(m.update(pressed: [.y], at: 0.3) == [.toggleTheme])
    }

    @Test func onOffShortPressPausesOnRelease() {
        var m = RideInputMapper()
        #expect(m.update(pressed: [.onOffRight], at: 0) == [])
        #expect(m.update(pressed: [], at: 0.3) == [.pauseToggle])
    }

    @Test func onOffLongHoldDoesNothing() {
        var m = RideInputMapper()
        _ = m.update(pressed: [.onOffLeft], at: 0)
        #expect(m.tick(at: 2) == [])
        #expect(m.update(pressed: [], at: 3) == [])
    }

    @Test func gradeRepeatsWhileHeld() {
        var m = RideInputMapper()
        #expect(m.update(pressed: [.up], at: 0) == [.gradeUp])
        #expect(m.tick(at: 0.3) == [])
        #expect(m.tick(at: 0.4) == [.gradeUp])
        #expect(m.tick(at: 0.5) == [])
        #expect(m.tick(at: 0.66) == [.gradeUp])
        #expect(m.needsTicks)
        #expect(m.update(pressed: [], at: 0.7) == [])
        #expect(!m.needsTicks)
    }

    @Test func endSessionFiresOnceAfterHold() {
        var m = RideInputMapper()
        #expect(m.update(pressed: [.b], at: 0) == [])
        #expect(m.tick(at: 0.9) == [])
        #expect(m.tick(at: 1.0) == [.endSession])
        #expect(m.tick(at: 1.5) == [])
        _ = m.update(pressed: [], at: 2)
        _ = m.update(pressed: [.powerUpLeft], at: 3)
        #expect(m.tick(at: 4.1) == [.endSession])
    }

    @Test func paddlesWithHysteresis() {
        var m = RideInputMapper()
        let right = { (v: Int) in [ZwiftRide.Paddle(location: 1, value: v)] }
        #expect(m.update(pressed: [], paddles: right(-40), at: 0) == [.shiftUp])
        #expect(m.update(pressed: [], paddles: right(-20), at: 0.1) == [])
        #expect(m.update(pressed: [], paddles: right(-30), at: 0.2) == [])
        #expect(m.update(pressed: [], paddles: right(-5), at: 0.3) == [])
        #expect(m.update(pressed: [], paddles: [.init(location: 0, value: 60)], at: 0.4) == [.shiftDown])
    }
}

@Suite struct ButtonMapTests {
    @Test func customMapping() {
        var map = ButtonMap.standard
        map[.left] = .shiftDown
        map[.right] = .shiftUp
        map[.y] = nil
        var m = RideInputMapper(map: map)
        #expect(m.update(pressed: [.right], at: 0) == [.shiftUp])
        #expect(m.update(pressed: [.left], at: 0.1) == [.shiftDown])
        #expect(m.update(pressed: [.y], at: 0.2) == [])
    }

    @Test func holdActionOnAnyButton() {
        var map = ButtonMap.standard
        map[.z] = .endSession
        var m = RideInputMapper(map: map)
        #expect(m.update(pressed: [.z], at: 0) == [])
        #expect(m.needsTicks)
        #expect(m.tick(at: 1.1) == [.endSession])
    }

    @Test func onOffRejectsHoldAndRepeat() {
        var map = ButtonMap.standard
        map[.onOffRight] = .endSession
        #expect(map[.onOffRight] == nil)
        map[.onOffRight] = .gradeUp
        #expect(map[.onOffRight] == nil)
        map[.onOffRight] = .toggleTheme
        #expect(map[.onOffRight] == .toggleTheme)
    }

    @Test func codableRoundTrip() throws {
        var map = ButtonMap.standard
        map[.left] = .shiftDown
        let data = try JSONEncoder().encode(map)
        #expect(try JSONDecoder().decode(ButtonMap.self, from: data) == map)
        #expect(String(decoding: data, as: UTF8.self).contains("\"left\""))
    }
}

@Suite struct RideControlsTests {
    @Test func gearLimits() {
        var c = RideControls(gear: 23)
        #expect(c.apply(.shiftUp) == .changed)
        #expect(c.gear == 24)
        #expect(c.apply(.shiftUp) == .atLimit)
        c = RideControls(gear: 1)
        #expect(c.apply(.shiftDown) == .atLimit)
        #expect(c.gearRatio == 0.75)
    }

    @Test func manualGradeClamp() {
        var c = RideControls(manualGrade: -9.5)
        #expect(c.apply(.gradeDown) == .changed)
        #expect(c.grade() == -10)
        #expect(c.apply(.gradeDown) == .atLimit)
    }

    @Test func autoModeAppliesBias() {
        var c = RideControls(mode: .auto)
        c.apply(.gradeUp)
        c.apply(.gradeUp)
        #expect(c.grade(autoProfile: 4) == 5)
        #expect(c.grade(autoProfile: 15.5) == 16)
    }
}

@Suite struct GearSetTests {
    @Test(arguments: GearSet.choices)
    func spansFullRange(count: Int) {
        let g = GearSet(count: count)
        #expect(g.count == count)
        #expect(g.ratios.first == 0.75)
        #expect(g.ratios.last == 5.49)
        #expect(zip(g.ratios, g.ratios.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(g.ratio(for: g.startGear) - 2.4) < 0.9)
    }

    @Test func standardIsTheTable() {
        #expect(GearSet(count: 24).ratios == Gears.ratios)
        #expect(GearSet(count: 24).startGear == 12)
    }

    @Test func controlsRespectGearCount() {
        var c = RideControls(gears: GearSet(count: 3))
        #expect(c.gear == 2)
        c.apply(.shiftUp)
        #expect(c.apply(.shiftUp) == .atLimit)
        #expect(c.gearRatio == 5.49)
    }
}

@Suite struct PhysicsTests {
    @Test func flatPowerIsPlausible() {
        // ~34 km/h on the flat should need roughly 200 W for 84 kg, CdA 0.32.
        let p = RiderModel().steadyPower(speedMps: 34 / 3.6, gradePercent: 0)
        #expect((180...220).contains(p))
    }

    @Test func demoRiderIsDeterministic() {
        var a = DemoRider(seed: 7)
        var b = DemoRider(seed: 7)
        for _ in 0..<20 {
            #expect(a.step(dt: 0.25, gearRatio: 2.4, gradePercent: 3) == b.step(dt: 0.25, gearRatio: 2.4, gradePercent: 3))
        }
    }

    @Test func demoRiderStopsWhenNotPedalling() {
        var r = DemoRider()
        for _ in 0..<20 { _ = r.step(dt: 0.25, gearRatio: 2.4, gradePercent: 0) }
        r.pedalling = false
        var last = DemoRider.Sample(powerW: 1, cadenceRpm: 1, speedKph: 1)
        for _ in 0..<60 { last = r.step(dt: 0.25, gearRatio: 2.4, gradePercent: 0) }
        #expect(last.powerW == 0)
        #expect(last.cadenceRpm == 0)
    }
}

@Suite struct DeviceModelTests {
    @Test(arguments: [
        ("1.2.0", true), ("1.1.0", true), ("1.2.0.24", true), ("v1.0", true),
        ("1.2.1", false), ("1.3.0", false), ("2.0", false),
    ])
    func firmwareSupport(firmware: String, supported: Bool) {
        #expect(ZwiftRide.isFirmwareSupported(firmware) == supported)
    }

    @Test func unparseableFirmware() {
        #expect(ZwiftRide.isFirmwareSupported("unknown") == nil)
    }

    @Test func sanitize() {
        let m = TrainerMetrics(powerW: 5000, cadenceRpm: -3, trainerSpeedKph: nil).sanitized
        #expect(m.powerW == 2000)
        #expect(m.cadenceRpm == 0)
    }
}
