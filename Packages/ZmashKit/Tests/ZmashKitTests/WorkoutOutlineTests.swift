import Testing
@testable import ZmashKit

/// A workout told in words for its details (D163), from the library's own.
@Suite struct WorkoutOutlineTests {
    private func library(_ id: String) -> Workout { WorkoutLibrary.all.first { $0.id == id }! }

    @Test func intervalsWithTheirRecoveryBetween() {
        #expect(WorkoutOutline.lines(library("sweetspot-2x20"), ftp: 200) == [
            "10 min warm-up, 45 → 75 %",
            "2 × 20 min at 90 % (180 W), 5 min easy between",
            "5 min cool-down, 60 → 40 %",
        ])
        #expect(WorkoutOutline.lines(library("threshold-4x8"), ftp: 250)[1] == "4 × 8 min at 100 % (250 W), 4 min easy between")
    }

    @Test func setsOfIntervals() {
        #expect(WorkoutOutline.lines(library("vo2-30-30"), ftp: 250)[1]
                == "3 sets of 8 × 30 s at 120 % (300 W), 30 s easy between, 5 min easy between sets")
        #expect(WorkoutOutline.lines(library("over-under-3x9"), ftp: 200)[1]
                == "3 sets of 3 × (1:30 at 95 % (190 W), 1:30 at 105 % (210 W)), 5 min easy between sets")
    }

    @Test func climbsAndStairs() {
        #expect(WorkoutOutline.lines(library("hills-6x3"), ftp: 200)[1] == "6 × 3 min climbing at 6 %, around 105 %, 3 min easy between")
        #expect(WorkoutOutline.lines(WorkoutLibrary.rampTest, ftp: 200) == ["5 min warm-up at 50 %", "30 × 1 min, rising from 50 to 224 %"])
    }

    @Test func singleStepsAndCadence() {
        let w = Workout(id: "x", name: "x", summary: "", steps: [
            .init(1800, .steady(0.68), "Endurance", cadence: 90...100), .init(45, .free), .init(90, .steady(1.1)),
        ])
        #expect(WorkoutOutline.lines(w, ftp: 300) == ["30 min at 68 % (204 W) at 90–100 rpm", "45 s free riding, no target", "1:30 at 110 % (330 W)"])
        // The same block twice in a row is one block.
        let split = Workout(id: "y", name: "y", summary: "", steps: [.init(600, .steady(0.9)), .init(600, .steady(0.9))])
        #expect(WorkoutOutline.lines(split, ftp: 200) == ["20 min at 90 % (180 W)"])
    }

    /// Video-timed intervals (59 s, 1:01, 1:03) still fold, and a run of short uneven efforts reads as one stretch.
    @Test func unevenFilesStillRead() {
        let steps: [Workout.Step] = [.init(61, .steady(1.24)), .init(63, .steady(0.5)), .init(59, .steady(1.24)),
                                     .init(60, .steady(0.5)), .init(62, .steady(1.25))]
        #expect(WorkoutOutline.lines(Workout(id: "a", name: "a", summary: "", steps: steps), ftp: 200)
                == ["3 × 1 min at 124 % (248 W), 1:05 easy between"])
        let bursts: [Workout.Step] = [.init(34, .steady(0.9)), .init(51, .steady(1.0)), .init(61, .steady(1.05)),
                                      .init(46, .steady(1.14)), .init(35, .steady(0.95)), .init(240, .steady(0.5))]
        #expect(WorkoutOutline.lines(Workout(id: "b", name: "b", summary: "", steps: bursts), ftp: 200)
                == ["3:45 of efforts between 90 and 114 % (180–228 W)", "4 min easy"])
        // A "rest" nearly as hard as the work isn't one.
        let hard: [Workout.Step] = [.init(9, .steady(1.14)), .init(33, .steady(1.05)), .init(9, .steady(1.14)), .init(33, .steady(1.05))]
        #expect(!WorkoutOutline.lines(Workout(id: "c", name: "c", summary: "", steps: hard), ftp: 200)[0].contains("between"))
    }

    @Test func timeInZones() {
        let w = library("sweetspot-2x20")
        let zones = WorkoutOutline.zoneSeconds(w)
        #expect(zones.reduce(0, +) == w.duration)
        // 90 % of FTP is the bottom of zone 4 in the faces' seven zones.
        #expect(zones[3] == 2400)
    }
}
