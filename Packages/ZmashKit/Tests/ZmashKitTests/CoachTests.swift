import Testing
@testable import ZmashKit

@Suite struct CoachTests {
    private func input(_ t: Double, cadence: Double = 90, power: Double = 200, atM: Double? = nil,
                       climbs: [Climb] = [], last: Double? = nil, ghost: Double? = nil, erg: Bool = false) -> Coach.Input {
        Coach.Input(t: t, cadenceRpm: cadence, powerW: power, ftp: 250, erg: erg, lastEffortLeft: last, atM: atM,
                    climbs: climbs, ghostDelta: ghost)
    }

    private func said(_ c: inout Coach, from: Double, to: Double, cadence: Double, erg: Bool = false,
                      band: ClosedRange<Int> = 80...95, stepAge: ((Double) -> Double?)? = nil) -> [(Double, String)] {
        stride(from: from, through: to, by: 1).compactMap { t in
            c.update(Coach.Input(t: t, cadenceRpm: cadence, powerW: 200, ftp: 250, erg: erg,
                                 cadenceBand: band, stepAge: stepAge?(t))).map { (t, $0) }
        }
    }

    @Test func cadenceOutOfItsBandForHalfAMinute() {
        var c = Coach(kinds: [.cadence])
        // Quiet in the first minute, then 30 s out of the band.
        let s = said(&c, from: 0, to: 100, cadence: 72)
        #expect(s.count == 1)
        #expect(s.first?.0 == 90)
        #expect(s.first?.1 == "Cadence 72 · aim for 80–95")
    }

    @Test func cadenceHintsInERGToo() {
        var c = Coach(kinds: [.cadence])
        #expect(said(&c, from: 0, to: 100, cadence: 70, erg: true).count == 1)
    }

    @Test func cadenceHintsAreSpacedAndForgiving() {
        var c = Coach(kinds: [.cadence])
        // Out of the band for five minutes: a hint, then the next no sooner than 3 minutes later.
        let s = said(&c, from: 0, to: 360, cadence: 70)
        #expect(s.map(\.0) == [90, 270])
        // A few rpm under, or up to 5 over, is fine.
        var near = Coach(kinds: [.cadence])
        #expect(said(&near, from: 0, to: 200, cadence: 78).isEmpty)
        #expect(said(&near, from: 201, to: 400, cadence: 99).isEmpty)
    }

    @Test func cadenceWaitsForANewStepToSettle() {
        var c = Coach(kinds: [.cadence])
        // Steps change every 25 s: never 30 s out of the band past the first 20 s of a step.
        #expect(said(&c, from: 0, to: 300, cadence: 60, stepAge: { $0.truncatingRemainder(dividingBy: 25) }).isEmpty)
        // A step's own band.
        var own = Coach(kinds: [.cadence])
        #expect(said(&own, from: 0, to: 100, cadence: 60, band: 55...65).isEmpty)
    }

    @Test func lastEffortOnce() {
        var c = Coach(kinds: [.lastEffort])
        #expect(c.update(input(100, last: 44)) == "Last effort · 44 s")
        #expect(c.update(input(200, last: 30)) == nil)
    }

    @Test func halfwayUpWithTheGhost() {
        let climb = Climb(startM: 1000, lengthM: 4000, gainM: 300, summitElevationM: 500)
        var c = Coach(kinds: [.climbs])
        #expect(c.update(input(100, atM: 2900, climbs: [climb])) == nil)
        let m = c.update(input(101, atM: 3010, climbs: [climb], ghost: 20))
        #expect(m == "Halfway up · 2.0 km to the top · 0:20 up on your best")
        #expect(c.update(input(200, atM: 3100, climbs: [climb])) == nil)
    }

    @Test func spacingAndSprints() {
        var c = Coach(kinds: [.lastEffort, .climbs])
        let climb = Climb(startM: 0, lengthM: 2000, gainM: 150, summitElevationM: 300)
        _ = c.update(input(0, atM: 900, climbs: [climb]))
        #expect(c.update(input(10, atM: 1010, climbs: [climb])) != nil)
        // Within a minute: held back.
        #expect(c.update(input(30, last: 40)) == nil)
        // Sprinting: held back too.
        #expect(c.update(input(100, power: 500, last: 40)) == nil)
        #expect(c.update(input(101, last: 39)) != nil)
    }

    @Test func famousClimbTimes() {
        let famous = [Coach.FamousClimb(name: "Mont Ventoux", startM: 1000, endM: 5000, bestSeconds: 1500)]
        var c = Coach(kinds: [.bests], famous: famous)
        _ = c.update(input(0, atM: 990))
        _ = c.update(input(10, atM: 1010))
        #expect(c.update(input(1400, atM: 4990)) == nil)
        #expect(c.update(input(1410, atM: 5010)) == "New best on Mont Ventoux · 23:20, 1:40 quicker")
        var first = Coach(kinds: [.bests], famous: [Coach.FamousClimb(name: "Hautacam", startM: 0, endM: 100, bestSeconds: nil)])
        _ = first.update(input(0, atM: -1))
        _ = first.update(input(1, atM: 1))
        #expect(first.update(input(61, atM: 101)) == "First time up Hautacam · 1:00")
    }

    @Test func aClimbRiddenOnItsOwnStartsAtZero() {
        var c = Coach(kinds: [.bests], famous: [Coach.FamousClimb(name: "Paterberg", startM: 0, endM: 400, bestSeconds: nil)])
        _ = c.update(input(0, atM: 0))
        _ = c.update(input(30, atM: 200))
        #expect(c.update(input(58, atM: 401)) == "First time up Paterberg · 0:58")
    }

    @Test func offKindsSayNothing() {
        var c = Coach(kinds: [])
        #expect(c.update(input(100, last: 40)) == nil)
    }
}
