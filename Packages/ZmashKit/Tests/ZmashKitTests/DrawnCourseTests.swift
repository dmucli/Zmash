import Foundation
import Testing
@testable import ZmashKit

@Suite struct DrawnCourseTests {
    @Test func effortScalesTheSameDrawing() {
        let easy = DrawnCourse.grades(DrawnCourse.starter, effort: .easy).max() ?? 0
        let hard = DrawnCourse.grades(DrawnCourse.starter, effort: .hard).max() ?? 0
        #expect(hard > easy)
        // The two starter hills ride as real climbs, well short of a wall.
        for effort in Effort.allCases {
            let steepest = DrawnCourse.grades(DrawnCourse.starter, effort: effort).max() ?? 0
            #expect(steepest > DrawnCourse.maxGrade(effort) * 0.3)
            #expect(steepest <= DrawnCourse.maxGrade(effort))
        }
    }

    /// A single hill of the given height, centred.
    private func hill(_ height: Double) -> [Double] {
        (0..<64).map { i in 0.1 + height * exp(-pow((Double(i) / 63 - 0.5) / 0.15, 2)) }
    }

    @Test func steepnessFollowsTheDrawing() {
        let gentle = DrawnCourse.grades(hill(0.15), effort: .medium).max() ?? 0
        let steep = DrawnCourse.grades(hill(0.6), effort: .medium).max() ?? 0
        #expect(gentle > 0)
        #expect(steep > gentle * 2)
        // Twice as tall is twice as steep, until the cap.
        let double = DrawnCourse.grades(hill(0.3), effort: .medium).max() ?? 0
        #expect(abs(double - gentle * 2) < 0.25)
    }

    @Test func aWallRidesAtTheLimit() {
        let wall = (0..<64).map { $0 < 32 ? 0.05 : 0.95 }
        #expect(DrawnCourse.grades(wall, effort: .medium).max() == DrawnCourse.maxGrade(.medium))
    }

    @Test func descentsNeverBelowTheTrainerLimit() {
        // A gentle climb then a cliff: the cliff would be far steeper than −10 % at the same scale.
        let heights = (0..<64).map { i in i < 60 ? Double(i) * 0.005 : 0.0 }
        let g = DrawnCourse.grades(heights, effort: .hard)
        #expect((g.min() ?? 0) >= DrawnCourse.minGrade)
        #expect((g.max() ?? 0) <= DrawnCourse.maxGrade(.hard))
    }

    @Test func aFlatDrawingRidesFlat() {
        #expect(DrawnCourse.grades(DrawnCourse.blank, effort: .medium).allSatisfy { $0 == 0 })
    }

    @Test func onlyDownhillStillRides() {
        let heights = (0..<64).map { 0.9 - Double($0) * 0.01 }
        let g = DrawnCourse.grades(heights, effort: .medium)
        #expect((g.min() ?? 0) < -1)
        #expect((g.max() ?? 0) <= 0)
    }

    @Test func profileSpansTheRide() {
        let p = DrawnCourse.profile(DrawnCourse.starter, duration: 1800, effort: .medium)
        #expect(abs(p.duration - 1800) < 0.001)
        #expect(p.segments.count == DrawnCourse.points - 1)
    }

    @Test func resampleKeepsTheEnds() {
        let r = DrawnCourse.resample([0, 1], count: 5)
        #expect(r == [0, 0.25, 0.5, 0.75, 1])
    }
}
