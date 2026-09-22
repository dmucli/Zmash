import Testing
@testable import ZmashKit

@Suite struct SpeedModelTests {
    func settle(power: Double, grade: Double, seconds: Double = 300) -> SpeedModel {
        var m = SpeedModel()
        for _ in 0..<Int(seconds * 4) { m.step(powerW: power, gradePercent: grade, dt: 0.25) }
        return m
    }

    @Test func flat200WIsAbout34kph() {
        #expect((32...36).contains(settle(power: 200, grade: 0).speedKph))
    }

    @Test func climbIsSlower() {
        let m = settle(power: 250, grade: 8)
        #expect((10...15).contains(m.speedKph))
        #expect(m.elevationGainM > 50)
    }

    @Test func coastsDownhillWithZeroPower() {
        #expect(settle(power: 0, grade: -6).speedKph > 40)
    }

    @Test func stopsOnFlatWithoutPower() {
        var m = settle(power: 200, grade: 0)
        for _ in 0..<(120 * 4) { m.step(powerW: 0, gradePercent: 0, dt: 0.25) }
        #expect(m.speedKph < 8)
        for _ in 0..<(600 * 4) { m.step(powerW: 0, gradePercent: 0, dt: 0.25) }
        #expect(m.speedKph < 1)
    }

    @Test func workAndLongGapClamp() {
        var m = SpeedModel()
        m.step(powerW: 200, gradePercent: 0, dt: 60) // clamped to 2 s
        #expect(m.workJ == 400)
        #expect(m.kcal == 0.4)
    }
}

@Suite struct EffectiveGradeTests {
    let rider = RiderModel()

    @Test func harderGearRaisesResistance() {
        let vt = 30 / 3.6
        let low = EffectiveGrade.compute(cadenceRpm: 85, gearRatio: 1.5, gradePercent: 0, trainerSpeedMps: vt, rider: rider)
        let high = EffectiveGrade.compute(cadenceRpm: 85, gearRatio: 3.5, gradePercent: 0, trainerSpeedMps: vt, rider: rider)
        #expect(high > low)
    }

    @Test func steeperTerrainRaisesResistance() {
        let vt = 20 / 3.6
        let flat = EffectiveGrade.compute(cadenceRpm: 80, gearRatio: 2.0, gradePercent: 0, trainerSpeedMps: vt, rider: rider)
        let hill = EffectiveGrade.compute(cadenceRpm: 80, gearRatio: 2.0, gradePercent: 6, trainerSpeedMps: vt, rider: rider)
        #expect(hill > flat)
    }

    @Test func matchingGearGivesTerrainGrade() {
        // When the virtual gear speed equals the trainer speed, the effective grade ≈ terrain grade.
        let cadence = 90.0, ratio = 2.4
        let v = cadence / 60 * ratio * Gears.wheelCircumferenceM
        let g = EffectiveGrade.compute(cadenceRpm: cadence, gearRatio: ratio, gradePercent: 4, trainerSpeedMps: v, rider: rider)
        #expect(abs(g - 4) < 0.1)
    }

    @Test func fallsBackAndClamps() {
        #expect(EffectiveGrade.compute(cadenceRpm: 10, gearRatio: 5, gradePercent: 3, trainerSpeedMps: 8, rider: rider) == 3)
        #expect(EffectiveGrade.compute(cadenceRpm: 90, gearRatio: 5.49, gradePercent: 15, trainerSpeedMps: 3, rider: rider) == 16)
    }
}

@Suite struct SmoothingTests {
    @Test func rollingAverageAndSpike() {
        var r = RollingAverage(window: 3)
        for i in 0..<6 { r.add(200, at: Double(i) * 0.5) }
        r.add(1500, at: 3.0) // spike: rejected
        #expect(r.average(at: 3.0) == 200)
        r.add(260, at: 3.5)
        #expect(r.average(at: 3.5)! > 200)
    }

    @Test func lowPassConverges() {
        var lp = LowPass(tau: 1)
        _ = lp.update(0, dt: 0.1)
        var v = 0.0
        for _ in 0..<100 { v = lp.update(10, dt: 0.1) }
        #expect(abs(v - 10) < 0.01)
    }
}

@Suite struct TerrainTests {
    @Test(arguments: TerrainType.allCases)
    func fitsDurationExactly(type: TerrainType) {
        for duration in [15.0, 30, 45, 60, 90].map({ $0 * 60 }) {
            for effort in Effort.allCases {
                let p = TerrainGenerator.generate(duration: duration, type: type, effort: effort, seed: 99)
                #expect(abs(p.duration - duration) < 0.001)
                #expect(p.segments.allSatisfy { $0.grade <= TerrainProfile.maxGrade && $0.grade >= -10 })
                #expect(p.segments.allSatisfy { $0.duration > 0 })
                // Contiguous
                for (a, b) in zip(p.segments, p.segments.dropFirst()) { #expect(abs(a.end - b.start) < 0.001) }
                // Starts and ends flat
                #expect(p.grade(at: 0) == 0)
                #expect(p.targetGrade(at: duration - 1) == 0)
            }
        }
    }

    @Test func sameSeedSameProfile() {
        let a = TerrainGenerator.generate(duration: 1800, type: .hilly, effort: .medium, seed: 7)
        let b = TerrainGenerator.generate(duration: 1800, type: .hilly, effort: .medium, seed: 7)
        let c = TerrainGenerator.generate(duration: 1800, type: .hilly, effort: .medium, seed: 8)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func rampIsSmooth() {
        let p = TerrainProfile(segments: [.init(start: 0, duration: 10, grade: 0), .init(start: 10, duration: 60, grade: 8)])
        #expect(p.grade(at: 10) == 0)
        #expect(p.grade(at: 12) == 1)
        #expect(p.grade(at: 30) == 8)
        var last = p.grade(at: 0)
        for t in stride(from: 0.1, through: 70, by: 0.1) {
            let g = p.grade(at: t)
            #expect(abs(g - last) <= TerrainProfile.rampRate * 0.1 + 1e-9)
            last = g
        }
    }

    @Test func harderEffortClimbsMore() {
        func climbing(_ e: Effort) -> Double {
            (0..<20).map { seed in
                TerrainGenerator.generate(duration: 3600, type: .rolling, effort: e, seed: UInt64(seed))
                    .segments.filter { $0.grade > 0 }.map { $0.grade * $0.duration }.reduce(0, +)
            }.reduce(0, +)
        }
        #expect(climbing(.hard) > climbing(.medium))
        #expect(climbing(.medium) > climbing(.easy))
    }

    @Test func mountainHasLongClimbs() {
        let p = TerrainGenerator.generate(duration: 3600, type: .mountain, effort: .medium, seed: 3)
        let climbTime = p.segments.filter { $0.grade >= 4 }.map(\.duration).reduce(0, +)
        #expect(climbTime >= 0.25 * (3600 - 300))
    }

    @Test func freeRideBlocksAppend() {
        var p = TerrainGenerator.block(index: 0, type: .flat, effort: .easy, seed: 1)
        p.append(TerrainGenerator.block(index: 1, type: .flat, effort: .easy, seed: 1))
        #expect(abs(p.duration - 1200) < 0.001)
    }
}

@Suite struct SummaryTests {
    @Test func aggregates() {
        let samples = [
            RideSample(t: 0, powerW: 100, cadenceRpm: 0, speedKph: 10, gradePercent: 0, gear: 12),
            RideSample(t: 1, powerW: 200, cadenceRpm: 80, speedKph: 30, gradePercent: 0, gear: 12),
            RideSample(t: 2, powerW: 300, cadenceRpm: 90, speedKph: 35, gradePercent: 0, gear: 13),
        ]
        let s = SessionSummary.from(samples: samples, activeSeconds: 3600, distanceM: 30_000, elevationGainM: 120, kcal: 700)
        #expect(s.avgPowerW == 200)
        #expect(s.maxPowerW == 300)
        #expect(s.avgCadenceRpm == 85)
        #expect(abs(s.avgSpeedKph - 30) < 1e-9)
    }

    @Test func formats() {
        #expect(TimeFormat.clock(65) == "1:05")
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(abs(Units.imperial.speed(160.9344) - 100) < 1e-9)
    }
}

@Suite struct SeriesTests {
    func ride(seconds: Int) -> [RideSample] {
        (0..<seconds).map { RideSample(t: $0, powerW: $0 % 2 == 0 ? 100 : 300, cadenceRpm: $0 < 60 ? 0 : 90,
                                        speedKph: 30, gradePercent: 2, gear: 12) }
    }

    @Test func capsPointCount() {
        let points = SampleSeries.buckets(ride(seconds: 3600), maxPoints: 300)
        #expect(points.count <= 300)
        #expect(points.count >= 290)
        #expect(points.allSatisfy { $0.powerW == 200 && $0.speedKph == 30 })
    }

    @Test func perMinuteBucketsAndCadenceGaps() {
        let points = SampleSeries.buckets(ride(seconds: 180), bucketSeconds: 60)
        #expect(points.map(\.minute) == [0, 1, 2])
        #expect(points[0].cadenceRpm == nil)
        #expect(points[1].cadenceRpm == 90)
    }

    @Test func empty() {
        #expect(SampleSeries.buckets([]).isEmpty)
    }
}
