import Foundation

/// A multi-week training plan (roadmap Phase 16): sessions each week, placed on the days you ride, adapting to how
/// the last one went.
public struct TrainingPlan: Identifiable, Sendable {
    public enum Session: Equatable, Sendable {
        /// A library workout by id, or a catalog one (`zc/…`) in a catalog plan (D156).
        case workout(String)
        /// A generated interval session.
        case intervals(Family, sets: Int, minutes: Int)
        /// Steady riding for this long.
        case endurance(minutes: Int)
        /// A route by id (a famous climb, a stage).
        case route(String)
    }

    /// Interval families, each with its target and recovery; the notch moves a family's targets together.
    public enum Family: String, Codable, Sendable, CaseIterable {
        case tempo, sweetspot, threshold, vo2

        public var target: Double {
            switch self {
            case .tempo: 0.82
            case .sweetspot: 0.90
            case .threshold: 1.00
            case .vo2: 1.15
            }
        }

        /// Recovery between sets, as a share of the set's length (VO₂ efforts get as long again).
        var recoveryShare: Double {
            switch self {
            case .tempo: 0.25
            case .sweetspot: 0.25
            case .threshold: 0.3
            case .vo2: 1
            }
        }

        public var name: String {
            switch self {
            case .tempo: "Tempo"
            case .sweetspot: "Sweet spot"
            case .threshold: "Threshold"
            case .vo2: "VO₂max"
            }
        }
    }

    /// What a plan is for, to group them in the picker (D143).
    public enum Goal: String, CaseIterable, Sendable {
        case build, climb, endurance, maintain

        public var title: String {
            switch self {
            case .build: "Build"
            case .climb: "Climb"
            case .endurance: "Endurance"
            case .maintain: "Maintain"
            }
        }
    }

    public let id: String
    public let name: String
    public let summary: String
    /// Week by week, sessions in order of importance (the first ones are kept when you ride fewer days); a catalog
    /// plan's in its own order.
    public let weeks: [[Session]]
    public var goal: Goal = .build
    /// Who a plan from the workout catalog is from ("Zwift"), or "" when its files don't say (D156). nil: Zmash's own,
    /// which adapts as you ride; a catalog plan's sessions ride as written.
    public var author: String? = nil

    public var isZmash: Bool { author == nil }

    public var sessionsPerWeek: Int { weeks.map(\.count).max() ?? 0 }

    // MARK: Generated workouts

    /// A session as a workout: warm-up, the work, cool-down. `notch` raises or lowers the work 3 % a step.
    public static func workout(_ session: Session, id: String, notch: Int = 0) -> Workout? {
        switch session {
        case .workout, .route:
            return nil
        case .endurance(let minutes):
            let work = max(minutes - 10, 5) * 60
            return Workout(id: id, name: "Endurance \(minutes) min", summary: "Steady Z2 riding.",
                           steps: [.init(300, .ramp(0.5, 0.65), "Warm-up"), .init(work, .steady(0.65 + Double(notch) * 0.02), "Endurance"),
                                   .init(300, .ramp(0.6, 0.45), "Cool-down")])
        case .intervals(let family, let sets, let minutes):
            let target = family.target * (1 + Double(notch) * 0.03)
            let recover = max(Int((Double(minutes * 60) * family.recoveryShare).rounded()), 60)
            var steps: [Workout.Step] = [.init(600, .ramp(0.5, 0.75), "Warm-up")]
            for i in 1...max(sets, 1) {
                steps.append(.init(minutes * 60, .steady(target), "\(family.name) \(i)/\(sets)"))
                if i < sets { steps.append(.init(recover, .steady(0.5), "Recover")) }
            }
            steps.append(.init(300, .ramp(0.6, 0.45), "Cool-down"))
            let pct = Int((target * 100).rounded())
            return Workout(id: id, name: "\(family.name) \(sets) × \(minutes)",
                           summary: "\(sets) × \(minutes) min at \(pct) % FTP.", steps: steps)
        }
    }

    // MARK: Schedule

    /// Where a session sits: its week and slot in the plan, and the day it's on.
    public struct Slot: Equatable, Sendable {
        public var week: Int
        public var index: Int
        public var day: Date
    }

    public enum Status: Equatable, Sendable { case done, missed, today, upcoming }

    /// Every session placed on a day, from the start date, the weekdays you ride (1 = Sunday … 7 = Saturday) and what's
    /// been done. A session not done by its day moves to your next ride day that week; with none left, it's missed.
    public func schedule(start: Date, weekdays: Set<Int>, done: Set<[Int]>, today: Date,
                         calendar: Calendar = .mondayFirst) -> [(slot: Slot, status: Status)] {
        let first = calendar.dateInterval(of: .weekOfYear, for: start)!.start
        let todayStart = calendar.startOfDay(for: today)
        var out: [(Slot, Status)] = []
        for (w, sessions) in weeks.enumerated() {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: w, to: first)!
            let days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! }
                .filter { weekdays.contains(calendar.component(.weekday, from: $0)) && $0 >= calendar.startOfDay(for: start) }
            let kept = Array(sessions.indices.prefix(days.count))
            // Days already used by a session that's done, in order; the rest are free for what's left.
            var free = days
            var pending: [Int] = []
            for i in kept {
                if done.contains([w, i]) {
                    out.append((Slot(week: w, index: i, day: free.isEmpty ? days.last! : free.removeFirst()), .done))
                } else {
                    pending.append(i)
                }
            }
            // Past days can't take a session any more.
            let past = free.filter { $0 < todayStart }
            free.removeAll { $0 < todayStart }
            for (k, i) in pending.enumerated() {
                if k < free.count {
                    let day = free[k]
                    out.append((Slot(week: w, index: i, day: day), day == todayStart ? .today : .upcoming))
                } else {
                    out.append((Slot(week: w, index: i, day: past.last ?? days.last ?? weekStart), .missed))
                }
            }
        }
        return out.sorted { ($0.0.day, $0.0.week, $0.0.index) < ($1.0.day, $1.0.week, $1.0.index) }
    }

    // MARK: Adapting

    /// How a ridden session went: average power in the work steps as a share of their targets (nil without samples).
    public static func adherence(_ workout: Workout, watts: [Int], ftp: Double) -> Double? {
        var t = 0, got = 0.0, wanted = 0.0
        for step in workout.steps {
            defer { t += step.seconds }
            guard let f = step.fraction(at: 0), f >= 0.85 else { continue }
            let end = min(t + step.seconds, watts.count)
            guard end > t else { continue }
            got += Double(watts[t..<end].reduce(0, +))
            wanted += f * ftp * Double(end - t)
        }
        return wanted > 0 ? got / wanted : nil
    }

    /// The notch change after a session: up after a comfortable one (105 %+), down after a short or struggling one.
    public static func notchChange(adherence: Double?, completed: Bool) -> Int {
        if !completed { return -1 }
        guard let a = adherence else { return 0 }
        return a > 1.05 ? 1 : a < 0.9 ? -1 : 0
    }
}

public enum TrainingPlans {
    /// Zmash's plans: the first nine, then more for the goals a big library covers (D168).
    public static let all: [TrainingPlan] = [ftpBuild, sweetSpotBase, shortOnTime, ventoux, climber, base, granFondo,
                                             backOnTheBike, winter] + more

    public static func plan(id: String) -> TrainingPlan? { all.first { $0.id == id } }

    public static let ftpBuild = TrainingPlan(
        id: "ftp-build", name: "FTP Build", summary: "6 weeks, 3 rides a week: threshold and VO₂ work, a lighter 4th week, and a ramp test to finish.",
        weeks: [
            [.intervals(.threshold, sets: 3, minutes: 8), .intervals(.vo2, sets: 4, minutes: 3), .endurance(minutes: 60)],
            [.intervals(.threshold, sets: 3, minutes: 10), .intervals(.vo2, sets: 5, minutes: 3), .endurance(minutes: 75)],
            [.intervals(.threshold, sets: 4, minutes: 10), .intervals(.vo2, sets: 5, minutes: 4), .endurance(minutes: 90)],
            [.intervals(.sweetspot, sets: 2, minutes: 12), .workout("recovery-30"), .endurance(minutes: 60)],
            [.intervals(.threshold, sets: 3, minutes: 15), .intervals(.vo2, sets: 6, minutes: 3), .endurance(minutes: 90)],
            [.intervals(.threshold, sets: 2, minutes: 15), .workout("recovery-30"), .workout("ramp-test")],
        ])

    public static let sweetSpotBase = TrainingPlan(
        id: "sweet-spot-base", name: "Sweet spot base", summary: "6 weeks, 3 rides a week: sweet spot sets that lengthen, tempo and a steady ride, with a lighter 4th week.",
        weeks: [
            [.intervals(.sweetspot, sets: 3, minutes: 10), .endurance(minutes: 60), .intervals(.tempo, sets: 2, minutes: 12)],
            [.intervals(.sweetspot, sets: 3, minutes: 12), .endurance(minutes: 75), .intervals(.tempo, sets: 2, minutes: 15)],
            [.intervals(.sweetspot, sets: 2, minutes: 20), .endurance(minutes: 90), .intervals(.tempo, sets: 3, minutes: 12)],
            [.intervals(.sweetspot, sets: 2, minutes: 12), .workout("recovery-30"), .endurance(minutes: 60)],
            [.intervals(.sweetspot, sets: 3, minutes: 15), .endurance(minutes: 90), .intervals(.tempo, sets: 2, minutes: 20)],
            [.intervals(.sweetspot, sets: 2, minutes: 25), .endurance(minutes: 105), .intervals(.threshold, sets: 2, minutes: 10)],
        ])

    public static let shortOnTime = TrainingPlan(
        id: "short-on-time", name: "Short on time", summary: "4 weeks of 3 short, hard sessions: VO₂, threshold and sweet spot, about 45 minutes each.",
        weeks: [
            [.intervals(.vo2, sets: 5, minutes: 3), .intervals(.threshold, sets: 3, minutes: 8), .intervals(.sweetspot, sets: 2, minutes: 10)],
            [.intervals(.vo2, sets: 6, minutes: 3), .intervals(.threshold, sets: 3, minutes: 9), .intervals(.sweetspot, sets: 2, minutes: 12)],
            [.intervals(.vo2, sets: 4, minutes: 4), .intervals(.threshold, sets: 2, minutes: 12), .intervals(.sweetspot, sets: 3, minutes: 8)],
            [.intervals(.vo2, sets: 4, minutes: 3), .workout("recovery-30"), .intervals(.threshold, sets: 2, minutes: 10)],
        ], goal: .build)

    public static let ventoux = TrainingPlan(
        id: "ventoux", name: "Ready for Ventoux", summary: "8 weeks of long efforts at sweet spot and threshold, building to the real climb from Bédoin.",
        weeks: [
            [.intervals(.sweetspot, sets: 3, minutes: 10), .endurance(minutes: 75), .intervals(.tempo, sets: 2, minutes: 15)],
            [.intervals(.sweetspot, sets: 3, minutes: 12), .endurance(minutes: 90), .intervals(.tempo, sets: 2, minutes: 20)],
            [.intervals(.sweetspot, sets: 2, minutes: 20), .endurance(minutes: 105), .route("climb/col-du-tourmalet-sainte-marie-de-campan")],
            [.intervals(.tempo, sets: 2, minutes: 15), .workout("recovery-30"), .endurance(minutes: 75)],
            [.intervals(.threshold, sets: 3, minutes: 12), .endurance(minutes: 120), .intervals(.sweetspot, sets: 2, minutes: 25)],
            [.intervals(.threshold, sets: 2, minutes: 20), .endurance(minutes: 120), .route("climb/alpe-d-huez-bourg-d-oisans")],
            [.intervals(.sweetspot, sets: 3, minutes: 20), .endurance(minutes: 135), .intervals(.threshold, sets: 3, minutes: 15)],
            [.intervals(.tempo, sets: 2, minutes: 10), .workout("recovery-30"), .route("climb/mont-ventoux-bedoin")],
        ], goal: .climb)

    public static let climber = TrainingPlan(
        id: "climber", name: "Climber", summary: "6 weeks of long threshold and over-unders, with a famous climb each weekend, ending on the Tourmalet.",
        weeks: [
            [.intervals(.threshold, sets: 3, minutes: 10), .route("climb/col-du-telegraphe-saint-michel-de-maurienne"), .workout("over-under-3x9")],
            [.intervals(.threshold, sets: 3, minutes: 12), .route("climb/col-de-peyresourde-from-the-north-west"), .intervals(.vo2, sets: 5, minutes: 3)],
            [.workout("over-under-3x9"), .route("climb/hautacam-argeles-gazost"), .intervals(.threshold, sets: 2, minutes: 20)],
            [.intervals(.sweetspot, sets: 2, minutes: 12), .workout("recovery-30"), .endurance(minutes: 60)],
            [.intervals(.threshold, sets: 3, minutes: 15), .route("climb/alpe-d-huez-bourg-d-oisans"), .intervals(.vo2, sets: 5, minutes: 4)],
            [.workout("over-under-3x9"), .route("climb/col-du-tourmalet-sainte-marie-de-campan"), .workout("recovery-30")],
        ], goal: .climb)

    public static let base = TrainingPlan(
        id: "base", name: "Base", summary: "4 weeks of steady endurance with some tempo: the foundation for everything else.",
        weeks: [
            [.endurance(minutes: 60), .intervals(.tempo, sets: 2, minutes: 12), .endurance(minutes: 75)],
            [.endurance(minutes: 75), .intervals(.tempo, sets: 3, minutes: 12), .endurance(minutes: 90)],
            [.endurance(minutes: 75), .intervals(.tempo, sets: 2, minutes: 20), .endurance(minutes: 105)],
            [.endurance(minutes: 60), .workout("recovery-30"), .endurance(minutes: 90)],
        ], goal: .endurance)

    public static let granFondo = TrainingPlan(
        id: "gran-fondo", name: "Gran fondo", summary: "8 weeks, 3–4 rides a week: a long ride building to 3 hours, tempo and sweet spot, and Ventoux to finish.",
        weeks: [
            [.endurance(minutes: 90), .intervals(.tempo, sets: 2, minutes: 15), .intervals(.sweetspot, sets: 2, minutes: 12), .endurance(minutes: 60)],
            [.endurance(minutes: 105), .intervals(.tempo, sets: 2, minutes: 20), .intervals(.sweetspot, sets: 3, minutes: 10), .endurance(minutes: 60)],
            [.endurance(minutes: 120), .intervals(.tempo, sets: 3, minutes: 15), .intervals(.sweetspot, sets: 2, minutes: 15), .endurance(minutes: 75)],
            [.endurance(minutes: 90), .workout("recovery-30"), .intervals(.tempo, sets: 2, minutes: 12)],
            [.endurance(minutes: 150), .intervals(.tempo, sets: 2, minutes: 25), .intervals(.sweetspot, sets: 3, minutes: 12), .endurance(minutes: 75)],
            [.endurance(minutes: 165), .intervals(.sweetspot, sets: 2, minutes: 20), .intervals(.threshold, sets: 3, minutes: 8), .endurance(minutes: 60)],
            [.endurance(minutes: 180), .intervals(.tempo, sets: 3, minutes: 20), .intervals(.sweetspot, sets: 2, minutes: 20), .endurance(minutes: 75)],
            [.route("climb/mont-ventoux-bedoin"), .workout("recovery-30"), .intervals(.tempo, sets: 2, minutes: 10)],
        ], goal: .endurance)

    public static let backOnTheBike = TrainingPlan(
        id: "back", name: "Back on the bike", summary: "3 easy weeks after a break: short rides that get a little longer and a little livelier.",
        weeks: [
            [.workout("recovery-30"), .endurance(minutes: 40), .endurance(minutes: 45)],
            [.endurance(minutes: 45), .intervals(.tempo, sets: 2, minutes: 8), .endurance(minutes: 60)],
            [.endurance(minutes: 60), .intervals(.sweetspot, sets: 2, minutes: 10), .endurance(minutes: 75)],
        ], goal: .maintain)

    public static let winter = TrainingPlan(
        id: "winter", name: "Winter maintenance", summary: "4 weeks of 2 rides: enough to keep your FTP through a busy month. Start it again when it ends.",
        weeks: [
            [.intervals(.sweetspot, sets: 2, minutes: 15), .endurance(minutes: 60)],
            [.intervals(.threshold, sets: 3, minutes: 8), .endurance(minutes: 75)],
            [.intervals(.sweetspot, sets: 2, minutes: 20), .endurance(minutes: 60)],
            [.intervals(.vo2, sets: 5, minutes: 3), .endurance(minutes: 75)],
        ], goal: .maintain)
}

public extension Calendar {
    /// The user's calendar with weeks starting on Monday: plan weeks, "this week" and weekly totals use it everywhere,
    /// whatever the locale's first weekday.
    static var mondayFirst: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }
}
