import Foundation
import Testing
@testable import ZmashKit

@Suite struct RecapTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }()
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func previousPeriods() {
        let aug = Recap.previousMonth(of: date(2026, 9, 3), calendar: cal)
        #expect(aug.start == date(2026, 8, 1, 0))
        #expect(aug.end == date(2026, 9, 1, 0))
        let year = Recap.previousYear(of: date(2027, 1, 2), calendar: cal)
        #expect(year.start == date(2026, 1, 1, 0))
    }

    @Test func sumsTheMonthOnly() throws {
        let rides = [
            Recap.Ride(date: date(2026, 7, 31, 23), seconds: 3600, distanceM: 30_000, elevationM: 300),
            Recap.Ride(date: date(2026, 8, 1, 0), seconds: 1800, distanceM: 15_000, elevationM: 100, routeID: "climb/a", face: "paper", best20W: 250),
            Recap.Ride(date: date(2026, 8, 12), seconds: 5400, distanceM: 45_000, elevationM: 900, routeID: "climb/a", face: "borne", best20W: 262),
            Recap.Ride(date: date(2026, 8, 20), seconds: 2700, distanceM: 20_000, elevationM: 50, routeID: "race/x/1", face: "paper"),
            Recap.Ride(date: date(2026, 9, 1, 0), seconds: 3600, distanceM: 30_000, elevationM: 300),
        ]
        let s = try #require(Recap.summarize(rides, in: Recap.previousMonth(of: date(2026, 9, 3), calendar: cal), calendar: cal))
        #expect(s.rides == 3)
        #expect(s.seconds == 9900)
        #expect(s.distanceM == 80_000)
        #expect(s.longestSeconds == 5400)
        #expect(s.best20W == 262)
        #expect(s.topRoute?.id == "climb/a" && s.topRoute?.count == 2)
        #expect(s.favouriteFace == "paper")
        // Weeks of 27 Jul (the 1st), 10 Aug and 17 Aug: the longest run is two.
        #expect(s.weekStreak == 2)
    }

    @Test func emptyMonthHasNoRecap() {
        #expect(Recap.summarize([], in: Recap.previousMonth(of: date(2026, 9, 3), calendar: cal), calendar: cal) == nil)
    }

    @Test func aRouteRiddenOnceIsNotTheTopRoute() throws {
        let rides = [Recap.Ride(date: date(2026, 8, 5), seconds: 600, distanceM: 1, elevationM: 1, routeID: "climb/a")]
        #expect(try #require(Recap.summarize(rides, in: Recap.previousMonth(of: date(2026, 9, 3), calendar: cal), calendar: cal)).topRoute == nil)
    }
}
