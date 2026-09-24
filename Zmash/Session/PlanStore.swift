import Foundation
import Synchronization
import ZmashKit

/// Being on a training plan: which one, from when, on which days, and what's been ridden (D101).
struct PlanEnrolment: Codable, Identifiable, Equatable {
    struct Done: Codable, Equatable {
        var week: Int
        var index: Int
        var date: Date
        var adherence: Double?
    }

    var id = UUID()
    var planID: String
    /// Whose plan (D112); "" is the first rider.
    var riderID = Riders.currentID
    var start: Date
    /// Calendar weekdays (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int>
    var done: [Done] = []
    /// Per interval family: how many 3 % steps harder (or easier) its sessions are now.
    var notches: [String: Int] = [:]
    var left = false

    var plan: TrainingPlan? { TrainingPlans.plan(id: planID) }

    init(planID: String, start: Date, weekdays: Set<Int>) {
        self.planID = planID
        self.start = start
        self.weekdays = weekdays
    }

    /// Enrolments saved before riders had profiles belong to the first rider.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        planID = try c.decode(String.self, forKey: .planID)
        riderID = try c.decodeIfPresent(String.self, forKey: .riderID) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        done = try c.decodeIfPresent([Done].self, forKey: .done) ?? []
        notches = try c.decodeIfPresent([String: Int].self, forKey: .notches) ?? [:]
        left = try c.decodeIfPresent(Bool.self, forKey: .left) ?? false
    }
}

@MainActor
enum PlanStore {
    nonisolated private static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Plans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Read once, then kept until a save: workouts on a plan are looked up from view bodies.
    nonisolated private static let cache = Mutex<[PlanEnrolment]?>(nil)

    nonisolated static var all: [PlanEnrolment] {
        if let hit = cache.withLock({ $0 }) { return hit }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let list = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PlanEnrolment.self, from: Data(contentsOf: $0)) }
            .sorted { $0.start > $1.start }
        cache.withLock { $0 = list }
        return list
    }

    nonisolated static func delete(_ e: PlanEnrolment) {
        try? FileManager.default.removeItem(at: directory.appending(path: e.id.uuidString + ".json"))
        cache.withLock { $0 = nil }
    }

    nonisolated static func save(_ e: PlanEnrolment) {
        try? JSONEncoder().encode(e).write(to: directory.appending(path: e.id.uuidString + ".json"), options: .atomic)
        cache.withLock { $0 = nil }
    }

    /// The plan the current rider is on (one at a time each).
    nonisolated static var current: PlanEnrolment? {
        let rider = Riders.currentID
        return all.first { $0.riderID == rider && !$0.left && !isFinished($0) }
    }

    static func enrol(_ plan: TrainingPlan, weekdays: Set<Int>, start: Date) -> PlanEnrolment {
        for var e in all where !e.left && e.riderID == Riders.currentID { e.left = true; save(e) }
        let e = PlanEnrolment(planID: plan.id, start: start, weekdays: weekdays)
        save(e)
        return e
    }

    nonisolated static func schedule(_ e: PlanEnrolment, today: Date = .now) -> [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)] {
        guard let plan = e.plan else { return [] }
        return plan.schedule(start: e.start, weekdays: e.weekdays, done: Set(e.done.map { [$0.week, $0.index] }), today: today)
    }

    nonisolated static func isFinished(_ e: PlanEnrolment) -> Bool {
        let s = schedule(e)
        return !s.isEmpty && s.allSatisfy { $0.status == .done || $0.status == .missed }
    }

    // MARK: Sessions

    static func session(_ e: PlanEnrolment, week: Int, index: Int) -> TrainingPlan.Session? {
        guard let plan = e.plan, week < plan.weeks.count, index < plan.weeks[week].count else { return nil }
        return plan.weeks[week][index]
    }

    static func workoutID(_ e: PlanEnrolment, week: Int, index: Int) -> String { "plan/\(e.planID)/\(week)-\(index)" }

    /// A plan session as a workout (library ones keep their steps under the plan's id), at the family's notch.
    nonisolated static func workout(id: String) -> Workout? {
        let parts = id.split(separator: "/")
        guard parts.count == 3, parts[0] == "plan", let plan = TrainingPlans.plan(id: String(parts[1])) else { return nil }
        let wi = parts[2].split(separator: "-").compactMap { Int($0) }
        guard wi.count == 2, wi[0] < plan.weeks.count, wi[1] < plan.weeks[wi[0]].count else { return nil }
        let session = plan.weeks[wi[0]][wi[1]]
        let notch = current.flatMap { e -> Int? in
            guard e.planID == plan.id, case .intervals(let family, _, _) = session else { return nil }
            return e.notches[family.rawValue]
        } ?? 0
        if case .workout(let libraryID) = session, var w = WorkoutLibrary.all.first(where: { $0.id == libraryID }) {
            w.id = id
            return w
        }
        return TrainingPlan.workout(session, id: id, notch: notch)
    }

    static func name(_ session: TrainingPlan.Session) -> String {
        switch session {
        case .workout(let id): WorkoutLibrary.all.first { $0.id == id }?.name ?? id
        case .intervals, .endurance: TrainingPlan.workout(session, id: "")?.name ?? ""
        case .route(let id): RaceStore.climb(id: id).map { "\($0.name) · \($0.side)" } ?? id
        }
    }

    static func minutes(_ session: TrainingPlan.Session) -> Int {
        switch session {
        case .workout(let id): (WorkoutLibrary.all.first { $0.id == id }).map { $0.isRampTest ? 20 : $0.duration / 60 } ?? 0
        case .intervals, .endurance: (TrainingPlan.workout(session, id: "")?.duration ?? 0) / 60
        case .route(let id): RaceStore.climb(id: id).map { Int(RouteStats.of($0.route).estimatedSeconds / 60) } ?? 0
        }
    }

    /// The home plan for a session.
    static func rideablePlan(_ e: PlanEnrolment, week: Int, index: Int, prefs: Preferences) -> SessionPlan? {
        guard let session = session(e, week: week, index: index) else { return nil }
        var p = prefs.lastPlan
        if case .route(let id) = session {
            p.workoutID = nil
            p.routeID = id
        } else {
            p.routeID = nil
            p.workoutID = workoutID(e, week: week, index: index)
        }
        return p
    }

    /// Today's session, if one falls today.
    static func today(_ e: PlanEnrolment) -> TrainingPlan.Slot? {
        schedule(e).first { $0.status == .today }?.slot
    }

    // MARK: Recording

    /// A deleted ride no longer counts: its session goes back to not done (the notch it moved stays).
    static func unrecord(rideStartedAt date: Date, riderID: String) {
        for var e in all where e.riderID == riderID && e.done.contains(where: { $0.date == date }) {
            e.done.removeAll { $0.date == date }
            save(e)
        }
    }

    /// Marks the session a saved ride rode as done, and adapts the family's notch.
    static func record(_ ride: FinishedRide) {
        guard var e = current else { return }
        var slot: (week: Int, index: Int)?
        if let id = ride.plan.workoutID, id.hasPrefix("plan/\(e.planID)/") {
            let wi = id.split(separator: "/").last?.split(separator: "-").compactMap { Int($0) } ?? []
            if wi.count == 2 { slot = (wi[0], wi[1]) }
        } else if let route = ride.plan.routeID.map({ RouteStore.split($0).base }) {
            // A route session: the one on the schedule that's today or still to come this week.
            slot = schedule(e).first { entry in
                guard entry.status == .today || entry.status == .upcoming,
                      case .route(let id)? = session(e, week: entry.slot.week, index: entry.slot.index) else { return false }
                return id == route
            }.map { ($0.slot.week, $0.slot.index) }
        }
        guard let slot, !e.done.contains(where: { $0.week == slot.week && $0.index == slot.index }) else { return }
        var adherence: Double?
        if let session = session(e, week: slot.week, index: slot.index), case .intervals(let family, _, _) = session,
           let workout = ride.plan.workout {
            adherence = TrainingPlan.adherence(workout, watts: ride.samples.map(\.powerW), ftp: Double(Preferences.shared.ftp))
            let completed = Double(ride.summary.activeSeconds) >= Double(workout.duration) * 0.9
            e.notches[family.rawValue, default: 0] += TrainingPlan.notchChange(adherence: adherence, completed: completed)
            e.notches[family.rawValue] = min(max(e.notches[family.rawValue]!, -3), 3)
        }
        e.done.append(.init(week: slot.week, index: slot.index, date: ride.startedAt, adherence: adherence))
        save(e)
    }
}
