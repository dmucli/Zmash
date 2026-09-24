import Foundation
import Testing
@testable import ZmashKit

@Suite struct TrainingTests {
    @Test func powerCurve() {
        let easy: [Int] = Array(repeating: 200, count: 600)
        let hard: [Int] = Array(repeating: 400, count: 60)
        let down: [Int] = Array(repeating: 150, count: 600)
        let c = Training.powerCurve(easy + hard + down)
        #expect(c[5] == 400)
        #expect(c[60] == 400)
        let fiveMinutes: Double = (400.0 * 60 + 200.0 * 240) / 300
        #expect(c[300] == Int(fiveMinutes.rounded()))
        #expect(c[1200] != nil)
        #expect(c[1800] == nil) // longer than the ride
    }

    @Test func normalizedPowerSteadyEqualsAverage() {
        #expect(abs(Training.normalizedPower(Array(repeating: 250, count: 600)) - 250) < 0.001)
        // Surges push NP above the average.
        let surgy = (0..<600).map { ($0 / 30) % 2 == 0 ? 350 : 150 }
        #expect(Training.normalizedPower(surgy) > 250)
    }

    @Test func tssOfOneHourAtFTPIs100() {
        let load = Training.load(Array(repeating: 250, count: 3600), ftp: 250)
        #expect(abs(load.tss - 100) < 0.01)
        #expect(abs(load.intensityFactor - 1) < 0.001)
    }

    @Test func ftpEstimates() {
        #expect(Training.estimateFTP(curve: [1200: 300]) == 285)
        #expect(Training.estimateFTP(curve: [60: 400]) == nil)
        #expect(Training.rampTestFTP(watts: Array(repeating: 200, count: 120) + Array(repeating: 360, count: 60)) == 270)
    }

    @Test func newBestsOnlyAgainstExistingHistory() {
        let bests = Training.newBests(ride: [60: 400, 300: 300, 1200: 250], previous: [60: 380, 300: 310])
        #expect(bests.map(\.duration) == [60])
    }
}

@Suite struct WorkoutTests {
    @Test func positionAndRamp() throws {
        let w = Workout(id: "t", name: "t", summary: "", steps: [.init(60, .ramp(0.5, 1.0)), .init(120, .steady(0.9)), .init(30, .free)])
        #expect(w.duration == 210)
        let p = try #require(w.position(at: 30))
        #expect(p.index == 0)
        #expect(abs(p.fraction! - 0.75) < 1e-9)
        #expect(w.targetWatts(at: 90, ftp: 200) == 180)
        #expect(w.position(at: 190)?.fraction == nil) // free
        #expect(w.position(at: 500)?.finished == true)
        #expect(w.position(at: 61)?.remainingInStep == 119)
    }

    @Test func libraryIsSane() {
        for w in WorkoutLibrary.all {
            #expect(w.duration > 0)
            #expect(Set(WorkoutLibrary.all.map(\.id)).count == WorkoutLibrary.all.count)
        }
        #expect(WorkoutLibrary.all.first { $0.id == "sweetspot-2x20" }?.duration == 600 + 1200 * 2 + 300 + 300)
    }

    @Test func gradeForWatts() {
        let r = RiderModel()
        let g200 = WorkoutGrade.grade(forWatts: 200, rider: r)
        #expect((2.5...4).contains(g200))
        #expect(WorkoutGrade.grade(forWatts: 300, rider: r) > g200)
        #expect(WorkoutGrade.grade(forWatts: 0, rider: r) < 0)
        #expect(WorkoutGrade.grade(forWatts: 2000, rider: r) == 12)
    }

    @Test func zwoImport() throws {
        let xml = """
        <workout_file>
          <author>Coach</author>
          <name>Test ZWO</name>
          <description>Short test</description>
          <sportType>bike</sportType>
          <workout>
            <Warmup Duration="300" PowerLow="0.4" PowerHigh="0.75"/>
            <IntervalsT Repeat="3" OnDuration="60" OffDuration="30" OnPower="1.2" OffPower="0.5"/>
            <SteadyState Duration="600" Power="0.88"/>
            <FreeRide Duration="120"/>
            <Cooldown Duration="240" PowerLow="0.6" PowerHigh="0.4"/>
          </workout>
        </workout_file>
        """
        let w = try #require(ZWOParser.parse(Data(xml.utf8), id: "x"))
        #expect(w.name == "Test ZWO")
        #expect(w.summary == "Short test")
        #expect(w.steps.count == 1 + 6 + 1 + 1 + 1)
        #expect(w.duration == 300 + 3 * 90 + 600 + 120 + 240)
        #expect(w.steps[1].target == .steady(1.2))
        #expect(w.steps[8].target == .free)
        #expect(ZWOParser.parse(Data("<nope/>".utf8), id: "y") == nil)
    }
}
