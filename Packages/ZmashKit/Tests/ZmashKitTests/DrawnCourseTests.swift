import Foundation
import Testing
@testable import ZmashKit

@Suite struct DrawnCourseTests {
    @Test func steepestClimbFollowsEffort() {
        for effort in Effort.allCases {
            let g = DrawnCourse.grades(DrawnCourse.starter, effort: effort)
            #expect(abs((g.max() ?? 0) - DrawnCourse.maxGrade(effort)) < 0.11)
        }
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
