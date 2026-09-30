import Foundation
import Testing
@testable import ZmashKit

@Suite struct CourseTests {
    /// 3 km flat, 3 km at 6 %, 3 km flat.
    private var course: RideCourse {
        var e: [Double] = Array(repeating: 100, count: 31)
        for i in 1...30 { e.append(100 + Double(i) * 6) }
        e += Array(repeating: 280, count: 30)
        return RideCourse(route: Route(id: "c", name: "", place: "", elevations: e))
    }

    @Test func stoneOnTheFlatPointsToTheNextClimb() throws {
        let info = course.climbInfo(at: 1000)
        #expect(!info.inClimb)
        #expect(info.nextCategory != nil)
        #expect(abs(try #require(info.nextInM) - 2000) <= 200)
        #expect(abs(info.nextAverageGrade - 6) < 0.3)
    }

    @Test func stoneOnTheClimb() {
        let info = course.climbInfo(at: 4000)
        #expect(info.inClimb)
        #expect(abs(info.toSummitM - 2000) <= 200)
        #expect(abs(info.leftM - 120) < 15)
        #expect(abs(info.nextKmGrade - 6) < 0.5)
    }

    @Test func summitJustAfterTheTop() {
        let info = course.climbInfo(at: 6050)
        #expect(info.summit)
        #expect(info.lastCategory != nil)
        #expect(!course.climbInfo(at: 7000).summit)
    }

    @Test func generatedCourseFollowsTheClock() throws {
        let profile = TerrainProfile(segments: [.init(start: 0, duration: 600, grade: 0), .init(start: 600, duration: 600, grade: 5)])
        let c = try #require(RideCourse.generated(profile, rider: RiderModel(), powerW: 150))
        let half = c.position(elapsed: 600, distanceM: 0)
        #expect(half > c.lengthM * 0.6) // the flat half covers more ground than the climbing half
        #expect(abs(c.position(elapsed: 1200, distanceM: 0) - c.lengthM) <= 100)
        #expect(c.normalizedProfile().count == 201)
    }

    @Test func best200AndFlying200() {
        var f = FaceTelemetry(ftp: 200)
        var t = 0.0, d = 0.0
        // 36 km/h = 10 m/s: 200 m in 20 s.
        for _ in 0..<1500 { t += 0.1; d += 1; f.update(t: t, dt: 0.1, speedKph: 36, powerW: 200, cadenceRpm: 90, gradePercent: 0, gear: 12, distanceM: d, moving: true) }
        #expect(abs((f.best200 ?? 0) - 20) < 0.2)
        // Then 45 km/h: a new best, past the first kilometre.
        var celebrated = 0
        for _ in 0..<200 {
            t += 0.1; d += 1.25
            f.update(t: t, dt: 0.1, speedKph: 45, powerW: 200, cadenceRpm: 90, gradePercent: 0, gear: 12, distanceM: d, moving: true)
            if f.event?.kind == .flying200, f.event?.time == t { celebrated += 1 }
        }
        #expect(abs((f.best200 ?? 0) - 16) < 0.2)
        #expect(celebrated == 1) // once, then the cooldown holds
    }

    @Test func spinUpNeedsFiveSeconds() {
        var f = FaceTelemetry(ftp: 200)
        var t = 0.0
        for _ in 0..<40 { t += 0.1; f.update(t: t, dt: 0.1, speedKph: 30, powerW: 200, cadenceRpm: 125, gradePercent: 0, gear: 12, distanceM: t * 8, moving: true) }
        #expect(!f.spinUp)
        for _ in 0..<20 { t += 0.1; f.update(t: t, dt: 0.1, speedKph: 30, powerW: 200, cadenceRpm: 125, gradePercent: 0, gear: 12, distanceM: t * 8, moving: true) }
        #expect(f.spinUp)
        t += 0.1; f.update(t: t, dt: 0.1, speedKph: 30, powerW: 200, cadenceRpm: 90, gradePercent: 0, gear: 12, distanceM: t * 8, moving: true)
        #expect(!f.spinUp)
    }
}
