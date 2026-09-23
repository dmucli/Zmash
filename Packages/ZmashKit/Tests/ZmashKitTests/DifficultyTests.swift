import Testing
@testable import ZmashKit

@Suite struct DifficultyTests {
    @Test func lengthSetsTheBase() {
        #expect(Difficulty.ride(minutes: 15) == 1)
        #expect(Difficulty.ride(minutes: 30) == 2)
        #expect(Difficulty.ride(minutes: 60) == 3)
        #expect(Difficulty.ride(minutes: 120) == 4)
        #expect(Difficulty.ride(minutes: 300) == 5)
    }

    @Test func steepGroundIsOneHarder() {
        #expect(Difficulty.ride(minutes: 30, steepestPercent: 9) == 3)
        #expect(Difficulty.ride(minutes: 30, climbingPerHourM: 700) == 3)
        #expect(Difficulty.ride(minutes: 300, steepestPercent: 12) == 5)
    }

    @Test func routesAtPace() {
        // 10 km at 8 %: steep, and about an hour at a steady pace.
        let climb = Route(id: "c", name: "", place: "", elevations: (0...100).map { Double($0) * 8 })
        #expect(Difficulty.route(climb, estimatedSeconds: 3600) == 4)
        let flat = Route(id: "f", name: "", place: "", elevations: Array(repeating: 100, count: 101))
        #expect(Difficulty.route(flat, estimatedSeconds: 1200) == 2)
    }

    @Test func workoutsByLoad() {
        func level(_ id: String) -> Int {
            let w = WorkoutLibrary.all.first { $0.id == id }!
            return Difficulty.workout(tss: w.estimatedLoad(ftp: 200).tss)
        }
        #expect(level("recovery-30") == 1)
        #expect(level("recovery-30") < level("endurance-45"))
        #expect(level("sweetspot-2x20") >= 4)
    }

    @Test func labels() {
        #expect(Difficulty.label(1) == "Easy")
        #expect(Difficulty.label(5) == "Very hard")
    }
}
