import Foundation
import Testing
@testable import ZmashKit

@Suite struct RaceTests {
    /// 10 km flat, then 5 km at 6 %, then 5 km flat.
    private var course: Route {
        var e: [Double] = Array(repeating: 100, count: 101)
        for i in 1...50 { e.append(100 + Double(i) * 6) }
        e += Array(repeating: 400, count: 50)
        return Route(id: "c", name: "Course", place: "", elevations: e)
    }

    @Test func slice() {
        let s = course.slice(fromM: 10_000, toM: 15_000)
        #expect(s.distanceM == 5000)
        #expect(abs(s.ascentM - 300) < 0.001)
        // Out-of-range bounds are clamped, never crash.
        #expect(course.slice(fromM: -500, toM: 999_999).distanceM == course.distanceM)
    }

    @Test func steadySpeedIsPlausible() {
        let r = RiderModel()
        let flat = Route.steadySpeed(powerW: 200, gradePercent: 0, rider: r) * 3.6
        #expect((30...36).contains(flat))
        let climb = Route.steadySpeed(powerW: 200, gradePercent: 8, rider: r) * 3.6
        #expect((8...12).contains(climb))
        // Steep descents cap at 80 km/h.
        #expect(Route.steadySpeed(powerW: 200, gradePercent: -10, rider: r) * 3.6 <= 80.001)
    }

    @Test func estimatedTimeFollowsPhysics() {
        let r = RiderModel()
        let base = course.estimatedTime(rider: r, powerW: 200)
        #expect(course.estimatedTime(rider: r, powerW: 250) < base)
        #expect(course.estimatedTime(rider: RiderModel(riderKg: 95), powerW: 200) > base)
        // 15 km flat at ~33 km/h plus a 5 km climb at ~11 km/h: roughly 55 minutes.
        #expect((2800...3700).contains(base))
    }

    @Test func windowPlacement() {
        let timing = RouteTiming(times: course.cumulativeTimes(rider: RiderModel(), powerW: 200))
        // Ten minutes from the start stays on the flat: about 5.5 km.
        let end = timing.end(after: 600, from: 0)
        #expect((5000...6000).contains(end))
        // The finale ends at the finish.
        let start = timing.latestStart(for: 600)
        #expect(abs(timing.end(after: 600, from: start) - course.distanceM) <= 200)
        // The hardest ten minutes are on the climb.
        let hardest = timing.hardestStart(for: 600, elevations: course.elevations)
        #expect((9000...12_000).contains(hardest))
        // A window longer than the route starts at 0.
        #expect(timing.latestStart(for: 999_999) == 0)
    }

    @Test func climbsFoundAndCategorised() {
        let climbs = Climbs.find(course)
        #expect(climbs.count == 1)
        let c = try! #require(climbs.first)
        #expect(abs(c.startM - 10_000) <= 100)
        #expect(abs(c.gainM - 300) < 1)
        #expect(abs(c.averageGrade - 6) < 0.2)
        #expect(c.category == .two) // 300 m × 6 % = 18
    }

    @Test func alpeDHuezIsOneHorsCategorieClimb() throws {
        let alpe = try #require(ClimbLibrary.route(id: "alpe-dhuez"))
        let climbs = Climbs.find(alpe)
        #expect(climbs.count == 1)
        #expect(climbs.first?.category == .hc)
    }

    @Test func falseFlatsAndTinyBumpsAreNotClimbs() {
        let gentle = Route(id: "g", name: "", place: "", elevations: (0...100).map { Double($0) * 1.5 }) // 1.5 %
        #expect(Climbs.find(gentle).isEmpty)
        let bump = Route(id: "b", name: "", place: "", elevations: [0, 10, 20, 20, 20, 20]) // 20 m
        #expect(Climbs.find(bump).isEmpty)
    }

    @Test func aFlatApproachIsNotPartOfTheClimb() {
        // 20 km of coast road creeping up 1 m per km, then 3 km at 5 %.
        var e: [Double] = (0...200).map { Double($0) * 0.1 }
        for i in 1...30 { e.append(20 + Double(i) * 5) }
        e += Array(repeating: 170, count: 20)
        let climbs = Climbs.find(Route(id: "s", name: "", place: "", elevations: e))
        #expect(climbs.count == 1)
        #expect(abs((climbs.first?.startM ?? 0) - 20_000) <= 300)
        #expect(abs((climbs.first?.averageGrade ?? 0) - 5) < 0.3)
    }

    @Test func aFlemishBergCounts() {
        // 60 m over 800 m (7.5 %) in the middle of a flat road.
        var e: [Double] = Array(repeating: 20, count: 30)
        for i in 1...8 { e.append(20 + Double(i) * 7.5) }
        e += Array(repeating: 80, count: 30)
        let climbs = Climbs.find(Route(id: "k", name: "", place: "", elevations: e))
        #expect(climbs.count == 1)
        #expect(climbs.first?.category == .four)
    }

    @Test func catalogRoundTripAndNames() throws {
        let race = Race(id: "2026/tour-de-france", name: "Tour de France", year: 2026, kind: .grandTour, country: "FR",
                        stages: [Stage(number: 17, elevations: [100, 120, 150])])
        let data = try JSONEncoder().encode(RaceCatalog(races: [race]))
        let back = try JSONDecoder().decode(RaceCatalog.self, from: data)
        #expect(back.races == [race])
        #expect(race.routeID(race.stages[0]) == "race/2026/tour-de-france/17")
        #expect(race.route(race.stages[0]).name == "Tour de France · Stage 17")
        #expect(RaceNames.name("li-ge-bastogne-li-ge").name == "Liège–Bastogne–Liège")
        #expect(RaceNames.name("some-new-race").name == "Some New Race")
    }
}
