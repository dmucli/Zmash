import Foundation
import Testing
@testable import ZmashKit

@Suite struct ReadinessTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400 + 3600) }

    @Test func noRidesIsNeutral() {
        let s = Readiness.state([], on: day(10), calendar: cal)
        #expect(s.fitness == 0 && s.fatigue == 0)
        #expect(Readiness.Band.of(s.form) == .maintain)
    }

    @Test func oneRideWorkedExample() {
        // 100 TSS on day 0, looked at on day 1: fitness 100/42, fatigue 100/7.
        let s = Readiness.state([(day(0), 100)], on: day(1), calendar: cal)
        #expect(abs(s.fitness - 100 / 42) < 1e-9)
        #expect(abs(s.fatigue - 100 / 7) < 1e-9)
        // A day later both decay.
        let t = Readiness.state([(day(0), 100)], on: day(2), calendar: cal)
        #expect(abs(t.fatigue - 100 / 7 * 6 / 7) < 1e-9)
    }

    @Test func todaysRideDoesNotCountYet() {
        let s = Readiness.state([(day(3), 200)], on: day(3), calendar: cal)
        #expect(s.fitness == 0)
    }

    @Test func aHardWeekMeansRecover() {
        // Six weeks of 50 a day, then a week of 150 a day.
        var loads = (0..<42).map { (day($0), 50.0) }
        loads += (42..<49).map { (day($0), 150.0) }
        let s = Readiness.state(loads, on: day(49), calendar: cal)
        #expect(Readiness.Band.of(s.form) == .recover)
        // Then a week off: fresh.
        #expect(Readiness.Band.of(Readiness.state(loads, on: day(58), calendar: cal).form) == .push)
    }

    @Test func bands() {
        #expect(Readiness.Band.of(-25) == .recover)
        #expect(Readiness.Band.of(0) == .maintain)
        #expect(Readiness.Band.of(8) == .push)
    }
}

@Suite struct SuggestionTests {
    private let candidates: [Suggestions.Candidate] = [
        .init(id: "recovery", kind: .workout, title: "Recovery", minutes: 30, bands: [.recover, .maintain]),
        .init(id: "threshold", kind: .workout, title: "Threshold", minutes: 60, bands: [.push]),
        .init(id: "vo2", kind: .workout, title: "VO2", minutes: 50, bands: [.push]),
        .init(id: "climb/ventoux", kind: .route, title: "Ventoux", minutes: 150, bands: [.push, .maintain]),
    ]

    @Test func followsTheBandAndUsualLength() {
        let push = Suggestions.pick(candidates, band: .push, usualMinutes: 55, ridden: [])
        #expect(push.map(\.id) == ["threshold", "vo2", "climb/ventoux"])
        #expect(Suggestions.pick(candidates, band: .recover, usualMinutes: 55, ridden: []).map(\.id) == ["recovery"])
    }

    @Test func skipsWhatWasRiddenThisWeek() {
        let push = Suggestions.pick(candidates, band: .push, usualMinutes: 55, ridden: ["vo2"])
        #expect(!push.contains { $0.id == "vo2" })
    }

    @Test func firstsLead() {
        let stage = Suggestions.Candidate(id: "race/x/1", kind: .route, title: "Stage 1", minutes: 60, bands: [])
        let out = Suggestions.pick(candidates, band: .recover, usualMinutes: 30, ridden: [], firsts: [stage])
        #expect(out.first?.id == "race/x/1")
        #expect(out.count == 2)
    }

    @Test func usualMinutes() {
        #expect(Suggestions.usualMinutes([]) == 45)
        #expect(Suggestions.usualMinutes([1800, 3600, 2700, 60]) == 45)
    }

    @Test func workoutBands() {
        #expect(WorkoutLibrary.all.first { $0.id == "recovery-30" }!.suitsBands.contains(.recover))
        #expect(WorkoutLibrary.all.first { $0.id == "vo2-5x3" }!.suitsBands == [.push])
        #expect(WorkoutLibrary.rampTest.suitsBands == [.push])
    }
}
