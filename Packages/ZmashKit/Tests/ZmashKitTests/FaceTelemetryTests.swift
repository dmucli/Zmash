import Testing
@testable import ZmashKit

@Suite struct FaceTelemetryTests {
    @Test func zones() {
        #expect(PowerZones.zone(powerW: 100, ftp: 200) == 1)
        #expect(PowerZones.zone(powerW: 200, ftp: 200) == 4)
        #expect(PowerZones.zone(powerW: 290, ftp: 200) == 6)
        #expect(PowerZones.zone(powerW: 400, ftp: 200) == 7)
        #expect(PowerZones.name(4) == "Z4 threshold")
    }

    @Test func profileNormalisation() {
        let h = FaceProfile.elevations(grades: [0, 0, 5, 5, 0], stepSeconds: 10, speedMps: 8)
        #expect(h.count == 5)
        #expect(h.last! > h.first!)
        let n = FaceProfile.normalized(h)
        #expect(n.min() == 0.08)
        #expect(n.allSatisfy { (0.08...0.98).contains($0) })
        #expect(FaceProfile.normalized([1, 1, 1]).allSatisfy { $0 == 0.08 })
        #expect(FaceProfile.resample([0, 1], count: 3) == [0, 0.5, 1])
    }

    func ride(_ f: inout FaceTelemetry, seconds: Double, power: Double = 200, grade: Double = 0, gear: Int = 12,
              speed: Double = 30, from t0: Double = 0, dist0: Double = 0) -> (Double, Double) {
        var t = t0, d = dist0
        while t < t0 + seconds {
            t += 0.1
            d += speed / 3.6 * 0.1
            f.update(t: t, dt: 0.1, speedKph: speed, powerW: power, cadenceRpm: 90, gradePercent: grade,
                     gear: gear, distanceM: d, moving: true)
        }
        return (t, d)
    }

    @Test func crankAndPower3() {
        var f = FaceTelemetry(ftp: 200)
        _ = ride(&f, seconds: 20)
        #expect(abs(f.power3 - 200) < 5)
        // 90 rpm for 20 s = 30 turns → back to ~0°.
        #expect(f.crankDegrees < 5 || f.crankDegrees > 355)
    }

    @Test func shiftEventAndExpiry() {
        var f = FaceTelemetry(ftp: 200)
        let (t, d) = ride(&f, seconds: 3) // past the start moment
        _ = ride(&f, seconds: 0.2, gear: 13, from: t, dist0: d)
        #expect(f.event?.kind == .shift)
        #expect(f.eventAge(at: t + 0.2) != nil)
        #expect(f.eventAge(at: t + 5) == nil)
    }

    @Test func kilometreSplit() {
        var f = FaceTelemetry(ftp: 200)
        _ = ride(&f, seconds: 121, speed: 30) // 30 km/h → 1 km at 120 s; event lives 2.2 s
        #expect(f.event?.kind == .km)
        #expect(f.event?.label == "Kilometre 1 · 2:00")
    }

    @Test func summitNeedsARealClimb() {
        var f = FaceTelemetry(ftp: 200)
        var (t, d) = ride(&f, seconds: 10, grade: 4)
        (t, d) = ride(&f, seconds: 1, grade: 0, from: t, dist0: d)
        #expect(f.event?.kind != .summit) // 10 s climb: too short
        (t, d) = ride(&f, seconds: 40, grade: 4, from: t, dist0: d)
        _ = ride(&f, seconds: 1, grade: 0, from: t, dist0: d)
        #expect(f.event?.kind == .summit)
    }

    @Test func sessionBestAboveThreshold() {
        var f = FaceTelemetry(ftp: 200)
        var (t, d) = ride(&f, seconds: 5, power: 240) // below 1.25 × FTP
        #expect(f.event == nil)
        (t, d) = ride(&f, seconds: 1, power: 280, from: t, dist0: d) // 140 %: a best, not a sprint
        #expect(f.event?.kind == .best)
        #expect(f.event?.label == "Session best · 280 w")
    }

    @Test func startFiresOnceOnTheFirstStroke() {
        var f = FaceTelemetry(ftp: 200)
        f.update(t: 0, dt: 0, speedKph: 0, powerW: 0, cadenceRpm: 0, gradePercent: 0, gear: 12, distanceM: 0, moving: false)
        #expect(f.event == nil)
        let (t, d) = ride(&f, seconds: 0.2)
        #expect(f.event?.kind == .start)
        _ = ride(&f, seconds: 10, from: t, dist0: d)
        #expect(f.event == nil) // expired, and never again
    }

    @Test func sprintOnCrossingAndCooldown() {
        var f = FaceTelemetry(ftp: 200)
        var (t, d) = ride(&f, seconds: 3, power: 200)
        (t, d) = ride(&f, seconds: 0.5, power: 320, from: t, dist0: d) // 160 % FTP
        #expect(f.event?.kind == .sprint)
        // Drop out and straight back in: inside the cooldown, no second sprint.
        (t, d) = ride(&f, seconds: 3, power: 200, from: t, dist0: d)
        (t, d) = ride(&f, seconds: 0.5, power: 330, from: t, dist0: d)
        #expect(f.event?.kind != .sprint)
    }

    @Test func trends() {
        var f = FaceTelemetry(ftp: 200)
        var t = 0.0
        for i in 0..<50 {
            t += 0.1
            f.update(t: t, dt: 0.1, speedKph: 20 + Double(i) * 0.1, powerW: 200, cadenceRpm: 90,
                     gradePercent: 0, gear: 12, distanceM: t * 6, moving: true)
        }
        #expect(abs(f.trendSpeed - 1) < 0.01) // +0.1 km/h per 0.1 s
    }
}
