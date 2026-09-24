import Foundation
import Testing
@testable import ZmashKit

@Suite struct TrainingPlanTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // weeks start on Monday
        return c
    }()
    /// Monday 7 September 2026.
    private func day(_ offset: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 7 + offset))! }
    private let tueThuSat: Set<Int> = [3, 5, 7]

    @Test func generatedIntervals() throws {
        let w = try #require(TrainingPlan.workout(.intervals(.threshold, sets: 3, minutes: 10), id: "p"))
        #expect(w.name == "Threshold 3 × 10")
        #expect(w.steps.filter { $0.label.hasPrefix("Threshold") }.count == 3)
        #expect(w.steps.first { $0.label.hasPrefix("Threshold") }?.target == .steady(1.0))
        // A notch up is 3 % harder.
        let harder = try #require(TrainingPlan.workout(.intervals(.threshold, sets: 3, minutes: 10), id: "p", notch: 1))
        #expect(harder.steps.first { $0.label.hasPrefix("Threshold") }?.target == .steady(1.03))
        #expect(TrainingPlan.workout(.workout("recovery-30"), id: "p") == nil)
    }

    @Test func sessionsLandOnYourDays() {
        let plan = TrainingPlans.base
        let s = plan.schedule(start: day(0), weekdays: tueThuSat, done: [], today: day(0), calendar: cal)
        #expect(s.count == 12)
        let firstWeek = s.prefix(3).map { cal.component(.weekday, from: $0.slot.day) }
        #expect(firstWeek == [3, 5, 7])
        #expect(s.allSatisfy { $0.status == .upcoming })
    }

    @Test func fewerDaysKeepTheImportantSessions() {
        let s = TrainingPlans.ftpBuild.schedule(start: day(0), weekdays: [3, 6], done: [], today: day(0), calendar: cal)
        #expect(s.filter { $0.slot.week == 0 }.map(\.slot.index) == [0, 1])
    }

    @Test func aMissedSessionMovesOn() {
        // Tuesday's session wasn't ridden; it's Wednesday: it moves to Thursday, and Thursday's to Saturday.
        let s = TrainingPlans.base.schedule(start: day(0), weekdays: tueThuSat, done: [], today: day(2), calendar: cal)
        let week0 = s.filter { $0.slot.week == 0 }
        #expect(week0.first { $0.slot.index == 0 }.map { cal.component(.weekday, from: $0.slot.day) } == 5)
        #expect(week0.first { $0.slot.index == 1 }.map { cal.component(.weekday, from: $0.slot.day) } == 7)
        // No day left for the third: missed, not stacked.
        #expect(week0.first { $0.slot.index == 2 }?.status == .missed)
    }

    @Test func doneSessionsAndToday() {
        let s = TrainingPlans.base.schedule(start: day(0), weekdays: tueThuSat, done: [[0, 0]], today: day(3), calendar: cal)
        let week0 = s.filter { $0.slot.week == 0 }
        #expect(week0.first { $0.slot.index == 0 }?.status == .done)
        #expect(week0.first { $0.slot.index == 1 }?.status == .today)
    }

    @Test func daysStayOnYourWeekdaysAcrossTheClockChange() {
        // Paris goes back an hour on Sunday 25 October 2026: sessions stay at midnight, on Tuesday, Thursday, Saturday.
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        paris.firstWeekday = 2
        let start = paris.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let s = TrainingPlans.base.schedule(start: start, weekdays: tueThuSat, done: [], today: start, calendar: paris)
        #expect(s.allSatisfy { [3, 5, 7].contains(paris.component(.weekday, from: $0.slot.day)) })
        #expect(s.allSatisfy { paris.component(.hour, from: $0.slot.day) == 0 })
        #expect(s.filter { $0.slot.week == 1 }.map { paris.component(.day, from: $0.slot.day) } == [27, 29, 31])
    }

    @Test func weeksStartOnMondayWhateverTheLocale() {
        // Started on a Sunday: with Monday-first weeks that's the last day of week 1, so it holds one session.
        let sunday = day(6)
        let monday = TrainingPlans.base.schedule(start: sunday, weekdays: [1, 3], done: [], today: sunday, calendar: cal)
        #expect(monday.filter { $0.slot.week == 0 }.count == 1)
        #expect(Calendar.mondayFirst.firstWeekday == 2)
    }

    @Test func adherenceAndNotches() throws {
        let w = try #require(TrainingPlan.workout(.intervals(.threshold, sets: 1, minutes: 10), id: "p"))
        // Warm-up 600 s at 150 W, then 600 s at 220 W against a 200 W target, then the cool-down.
        let watts = Array(repeating: 150, count: 600) + Array(repeating: 220, count: 600) + Array(repeating: 100, count: 300)
        let a = try #require(TrainingPlan.adherence(w, watts: watts, ftp: 200))
        #expect(abs(a - 1.1) < 0.001)
        #expect(TrainingPlan.notchChange(adherence: a, completed: true) == 1)
        #expect(TrainingPlan.notchChange(adherence: 0.85, completed: true) == -1)
        #expect(TrainingPlan.notchChange(adherence: 1.0, completed: true) == 0)
        #expect(TrainingPlan.notchChange(adherence: 1.2, completed: false) == -1)
    }

    @Test func plansPointAtRealThings() {
        for plan in TrainingPlans.all {
            for week in plan.weeks {
                for session in week {
                    switch session {
                    case .workout(let id): #expect(WorkoutLibrary.all.contains { $0.id == id } || id == WorkoutLibrary.rampTest.id)
                    case .route(let id): #expect(id.hasPrefix("climb/"))
                    default: break
                    }
                }
            }
        }
    }
}
