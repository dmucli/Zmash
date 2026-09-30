import Testing
@testable import ZmashKit

@Suite struct SoundCuesTests {
    @Test func freewheelOnlyWhenCoasting() {
        var s = SoundCues()
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90)).freewheelRate == 0)
        let coasting = s.update(.init(speedKph: 30, cadenceRpm: 0)).freewheelRate
        #expect(abs(coasting - 30 / 3.6 / 2.105 * 18) < 0.001)
        #expect(s.update(.init(speedKph: 3, cadenceRpm: 0)).freewheelRate == 0)
    }

    @Test func windRisesWithSpeed() {
        var s = SoundCues()
        #expect(s.update(.init(speedKph: 20, cadenceRpm: 90)).wind == 0)
        #expect(s.update(.init(speedKph: 45, cadenceRpm: 90)).wind > s.update(.init(speedKph: 35, cadenceRpm: 90)).wind)
        #expect(s.update(.init(speedKph: 90, cadenceRpm: 90)).wind <= 0.6)
    }

    @Test func crowdInTheLastKilometre() {
        var s = SoundCues()
        #expect(s.update(.init(speedKph: 12, cadenceRpm: 80, finalKmOf: .hc)).crowd == 1)
        #expect(s.update(.init(speedKph: 12, cadenceRpm: 80, finalKmOf: .four)).crowd < 0.5)
        #expect(s.update(.init(speedKph: 12, cadenceRpm: 80)).crowd == 0)
    }

    @Test func oneShots() {
        var s = SoundCues(kilometreChime: false)
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, shifted: 1)).oneShots == [.shift(heavy: false)])
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, shifted: -3)).oneShots == [.shift(heavy: true)])
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, event: .km)).oneShots.isEmpty)
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, event: .summit)).oneShots == [.summit])
    }

    @Test func countInOncePerStep() {
        var s = SoundCues()
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, stepEnding: (2, 2.9))).oneShots == [.countIn])
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, stepEnding: (2, 2.5))).oneShots.isEmpty)
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, stepEnding: (3, 2.8))).oneShots == [.countIn])
    }

    @Test func finishOnceAndSilenceWhenPaused() {
        var s = SoundCues()
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, finished: true)).oneShots == [.finish])
        #expect(s.update(.init(speedKph: 30, cadenceRpm: 90, finished: true)).oneShots.isEmpty)
        #expect(s.update(.init(speedKph: 50, cadenceRpm: 0, paused: true)) == SoundCues.Output())
    }
}
