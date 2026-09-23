import Foundation
import Testing
@testable import ZmashKit

@Suite struct RecordsTests {
    private func ride(_ speeds: [Double], route: String? = "race/x/1", distance: Double? = nil, day: Int = 0) -> Records.Ride {
        Records.Ride(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), routeID: route,
                     activeSeconds: speeds.count, distanceM: distance ?? speeds.reduce(0) { $0 + $1 / 3.6 },
                     elevationGainM: 0, speedsKph: speeds)
    }

    @Test func timesAClimbInsideAStage() {
        // 36 km/h (10 m/s) for 100 s, then 18 km/h (5 m/s) for 200 s: the climb is metres 1000–2000.
        let r = ride(Array(repeating: 36, count: 100) + Array(repeating: 18, count: 200))
        let place = Records.Place(climbID: "c", startM: 1000, lengthM: 1000, gainM: 80)
        let e = Records.efforts(r, places: [place], window: nil)
        #expect(e.count == 1)
        #expect(abs(e[0].seconds - 200) <= 1)
        #expect(abs(e[0].vam - 80 / (200.0 / 3600)) < 30)
    }

    @Test func aWindowedRideStartsPartWay() {
        // Ridden from metre 900: the climb starts 100 m in.
        let r = ride(Array(repeating: 18, count: 300))
        let place = Records.Place(climbID: "c", startM: 1000, lengthM: 1000, gainM: 80)
        let e = Records.efforts(r, places: [place], window: 900...2100)
        #expect(e.count == 1)
        #expect(abs(e[0].seconds - 200) <= 1)
        // A window starting after the foot doesn't count.
        #expect(Records.efforts(r, places: [place], window: 1200...2500).isEmpty)
    }

    @Test func unfinishedClimbsDontCount() {
        let r = ride(Array(repeating: 18, count: 250)) // 1250 m: stopped on the climb
        let place = Records.Place(climbID: "c", startM: 1000, lengthM: 1000, gainM: 80)
        #expect(Records.efforts(r, places: [place], window: nil).isEmpty)
    }

    @Test func distanceDriftIsCorrected() {
        // Samples add up to 3000 m but the engine rode 2000 m: the climb (1000–2000) ends at the ride's end.
        let r = ride(Array(repeating: 36, count: 300), distance: 2000)
        let place = Records.Place(climbID: "c", startM: 1000, lengthM: 1000, gainM: 80)
        let e = Records.efforts(r, places: [place], window: nil)
        #expect(e.count == 1)
        #expect(abs(e[0].seconds - 150) <= 1)
    }

    @Test func bestIsQuickest() {
        let slow = Records.Effort(climbID: "c", seconds: 900, date: .now, rideID: UUID(), vam: 1000)
        let fast = Records.Effort(climbID: "c", seconds: 800, date: .now, rideID: UUID(), vam: 1100)
        #expect(Records.bests([slow, fast])["c"]?.seconds == 800)
    }

    @Test func milestonesFireOnce() {
        var before = Records.Totals()
        before.elevationM = 8000
        before.distanceM = 990_000
        var after = before
        after.elevationM = 9000
        after.distanceM = 1_010_000
        #expect(Records.crossed(from: before, to: after) == [.everest(1), .kilometres(1000)])
        #expect(Records.crossed(from: after, to: after).isEmpty)
    }
}
