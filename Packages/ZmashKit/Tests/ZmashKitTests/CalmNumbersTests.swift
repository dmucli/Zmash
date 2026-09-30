import Foundation
import Testing
@testable import ZmashKit

/// The ride's numbers, calm (D164): at most once a second, no flicker between neighbours, real changes at once.
@Suite struct CalmNumbersTests {
    /// Feeds `values` at 10 Hz and returns what was shown after each.
    private func run(_ n: inout CalmNumber, _ values: [Double?], from t0: Double = 0) -> [Double?] {
        values.enumerated().map { i, v in n.update(v, at: t0 + Double(i) / 10) }
    }

    @Test func noisySpeedChangesAtMostOnceASecond() {
        var speed = CalmNumber(smoothing: 0.8, step: 0.1, deadband: 0.15, jump: 3)
        // 30 km/h, wobbling ±0.3 at 10 Hz for 10 s.
        let shown = run(&speed, (0..<100).map { 30 + 0.3 * sin(Double($0) * 1.7) })
        let changes = zip(shown, shown.dropFirst()).filter { $0 != $1 }.count
        #expect(changes <= 10)
        #expect(shown.allSatisfy { abs(($0 ?? 0) - 30) <= 0.3 })
    }

    @Test func neighboursDontFlicker() {
        var cadence = CalmNumber(smoothing: 1.5, step: 1, deadband: 1.5, jump: 12)
        // A trainer reporting 84, 85, 84, 85… for 10 s.
        let shown = run(&cadence, (0..<100).map { Double(84 + $0 % 2) })
        #expect(Set(shown.dropFirst(10).compactMap { $0 }).count == 1)
    }

    @Test func aRealChangeShowsAtOnce() {
        var power = CalmNumber(smoothing: 0, step: 1, deadband: 3, jump: 40, jumpShare: 0.25)
        _ = run(&power, Array(repeating: 200, count: 20))
        // A sprint: 600 W on the very next frame.
        #expect(power.update(600, at: 2.05) == 600)
        // A grade button's half a percent, straight away.
        var grade = CalmNumber(smoothing: 0.5, step: 0.1, deadband: 0.15, jump: 0.45)
        _ = run(&grade, Array(repeating: 2.0, count: 20))
        #expect(grade.update(2.5, at: 2.05) == 2.5)
    }

    @Test func aSlowChangeIsFollowed() {
        var cadence = CalmNumber(smoothing: 1.5, step: 1, deadband: 1.5, jump: 12)
        // 80 to 90 rpm over 10 s, then steady.
        let shown = run(&cadence, (0..<150).map { Double(80 + min($0, 100) / 10) })
        let values = shown.compactMap { $0 }
        #expect(values.last == 90 || values.last == 89)
        // Up in steps, never back.
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Set(values).count >= 4)
    }

    @Test func aSensorGoneTakesItsNumber() {
        var heart = CalmNumber(smoothing: 1, step: 1, deadband: 1.5, jump: 12)
        _ = run(&heart, [140, 141, 140])
        #expect(heart.update(nil, at: 0.3) == nil)
        #expect(heart.update(150, at: 0.4) == 150)
    }

    @Test func theRideSet() {
        var calm = CalmNumbers()
        let v = calm.update(.init(speedKph: 31.44, powerW: 212, cadenceRpm: 88, heartRateBpm: nil, grade: 3.46), at: 0)
        #expect(v == .init(speedKph: 31.4, powerW: 212, cadenceRpm: 88, heartRateBpm: nil, grade: 3.5))
    }
}
