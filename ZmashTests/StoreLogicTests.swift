import Foundation
import Testing
import ZmashKit
@testable import Zmash

/// The app's own logic that needs no Bluetooth or live store: route ids, plan workout ids, the widgets' week,
/// the decode cache, and Siri refusing a second ride.
@MainActor
@Suite struct StoreLogicTests {
    @Test func routeSegmentIDsRoundTrip() {
        let id = RouteStore.segmentID("race/2025/tour-de-france/16", fromM: 120_000, toM: 171_500)
        #expect(id == "race/2025/tour-de-france/16#120000-171500")
        let (base, segment) = RouteStore.split(id)
        #expect(base == "race/2025/tour-de-france/16")
        #expect(segment == 120_000...171_500)
        // A segment of a segment is cut from the base, not nested.
        #expect(RouteStore.segmentID(id, fromM: 0, toM: 1000) == "race/2025/tour-de-france/16#0-1000")
        // A malformed or empty range keeps the base and drops the segment.
        #expect(RouteStore.split("climb/x#9-3").segment == nil)
        #expect(RouteStore.split("climb/x").segment == nil)
    }

    @Test func routesResolveFromTheCatalogAndOldIDs() throws {
        let ventoux = try #require(RouteStore.route(id: "climb/mont-ventoux-bedoin"))
        #expect(ventoux.distanceM > 15_000) // cut at the summit from the race file: about 18.7 km
        // Rides saved before the catalog used "ventoux".
        #expect(RouteStore.route(id: "ventoux")?.distanceM == ventoux.distanceM)
        let part = try #require(RouteStore.route(id: "climb/mont-ventoux-bedoin#0-5000"))
        #expect(abs(part.distanceM - 5000) < 150)
    }

    @Test func planWorkoutIDs() throws {
        let plan = try #require(TrainingPlans.all.first)
        let w = try #require(PlanStore.workout(id: "plan/\(plan.id)/0-0"))
        #expect(w.id == "plan/\(plan.id)/0-0")
        #expect(PlanStore.workout(id: "plan/\(plan.id)/99-0") == nil)
        #expect(PlanStore.workout(id: "plan/nope/0-0") == nil)
        #expect(PlanStore.workout(id: "threshold-4x8") == nil)
    }

    /// Zmash's library is its own (D167): no workout shares a name with one in the catalog, standalone or a plan's
    /// session, however it's spaced or cased.
    @Test func libraryNamesAreOurOwn() {
        func key(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "×", with: "x").filter { $0.isLetter || $0.isNumber }
        }
        let sessions = WorkoutCatalog.plans.flatMap(\.weeks).joined().compactMap { session -> String? in
            if case .workout(let id) = session { return WorkoutCatalog.entry(id: id)?.name }
            return nil
        }
        let theirs = Set((WorkoutCatalog.entries.map(\.name) + sessions).map(key))
        #expect(theirs.count > 2000)
        // A standard protocol's plain name, which every app uses (ours rises 6 % of FTP a minute).
        let generic: Set = ["ramptest"]
        let shared = WorkoutLibrary.all.filter { theirs.contains(key($0.name)) && !generic.contains(key($0.name)) }.map(\.name)
        #expect(shared.isEmpty, "\(shared)")
    }

    /// A catalog plan is enrolled in like Zmash's (D156): its sessions ride as plan sessions, with the catalog's steps,
    /// named without the week and day the plan shows.
    @Test func catalogPlanSessions() throws {
        let builder = try #require(PlanStore.plan(id: "zc-ftp-builder"))
        #expect(builder.name == "FTP Builder" && !builder.isZmash)
        #expect(builder.weeks.count == 6 && builder.sessionsPerWeek == 5)
        #expect(PlanStore.plans.count == TrainingPlans.all.count + WorkoutCatalog.plans.count)
        guard case .workout(let id)? = builder.weeks[0].first else { Issue.record("FTP Builder starts on a workout"); return }
        let entry = try #require(WorkoutCatalog.entry(id: id))
        let w = try #require(PlanStore.workout(id: "plan/zc-ftp-builder/0-0"))
        #expect(w.id == "plan/zc-ftp-builder/0-0" && w.duration == entry.seconds)
        #expect(WorkoutStore.workout(id: "plan/zc-ftp-builder/0-0") != nil)
        #expect(PlanStore.minutes(.workout(id)) == entry.seconds / 60)
        #expect(PlanStore.name(.workout(id)) == WorkoutCatalogFile.sessionTitle(entry.name))
        #expect(!PlanStore.name(.workout(id)).hasPrefix("Week"))
    }

    /// Home's plan card rides the next session not done: today's, then the next to come, then nothing (D147).
    @Test func planUpNext() throws {
        let plan = try #require(TrainingPlans.all.first { $0.weeks.count > 1 && $0.weeks[0].count == 3 })
        let cal = Calendar.mondayFirst
        let monday = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let day = { (n: Int, hour: Int) in cal.date(byAdding: .hour, value: n * 24 + hour, to: monday)! }
        // Tuesdays, Thursdays and Saturdays.
        var e = PlanEnrolment(planID: plan.id, start: monday, weekdays: [3, 5, 7])

        let tuesday = try #require(PlanStore.upNext(e, today: day(1, 12)))
        #expect(tuesday.slot.week == 0 && tuesday.slot.index == 0 && tuesday.status == .today)

        // Ridden on Tuesday: Thursday's is next.
        e.done = [.init(week: 0, index: 0, date: day(1, 18))]
        let thursday = try #require(PlanStore.upNext(e, today: day(1, 20)))
        #expect(thursday.slot.index == 1 && thursday.status == .upcoming)
        #expect(cal.component(.weekday, from: thursday.slot.day) == 5)

        // The whole week ridden: next week's first.
        e.done += [.init(week: 0, index: 1, date: day(3, 18)), .init(week: 0, index: 2, date: day(5, 10))]
        let nextWeek = try #require(PlanStore.upNext(e, today: day(5, 20)))
        #expect(nextWeek.slot.week == 1 && nextWeek.slot.index == 0)

        // Long after the last week: nothing left.
        #expect(PlanStore.upNext(e, today: day(7 * (plan.weeks.count + 1), 12)) == nil)
    }

    /// Favourites (D148): per rider, newest first, and a part of a route favourites the whole route.
    @Test func favouritesToggleAndStayPerRider() throws {
        let defaults = try #require(UserDefaults(suiteName: "zmash.tests.favourites"))
        defaults.removePersistentDomain(forName: "zmash.tests.favourites")
        let f = Favourites(defaults: defaults)
        f.toggle("threshold-4x8", .workouts, rider: "a")
        f.toggle("vo2-4x4", .workouts, rider: "a")
        #expect(f.ids(.workouts, rider: "a") == ["vo2-4x4", "threshold-4x8"])
        #expect(!f.contains("threshold-4x8", .workouts, rider: "b"))
        f.toggle("race/2025/tour-de-france/16#120000-171000", .routes, rider: "a")
        #expect(f.contains("race/2025/tour-de-france/16", .routes, rider: "a"))
        #expect(f.ids(.routes, rider: "a") == ["race/2025/tour-de-france/16"])
        f.toggle("threshold-4x8", .workouts, rider: "a")
        #expect(f.ids(.workouts, rider: "a") == ["vo2-4x4"])
        // Kept: a new store reads them back.
        #expect(Favourites(defaults: defaults).ids(.workouts, rider: "a") == ["vo2-4x4"])
        defaults.removePersistentDomain(forName: "zmash.tests.favourites")
    }

    /// The bundled catalog (D154) loads, and its ids resolve like any workout's, so a catalog ride can be ridden again.
    @Test func catalogWorkoutsResolve() throws {
        #expect(WorkoutCatalog.entries.count > 800)
        // Plans' sessions are on the Plan page, not among the workouts (D155).
        #expect(WorkoutCatalog.plans.count > 50)
        #expect(!WorkoutCatalog.entries.contains { $0.collection == "FTP Builder" })
        let builder = try #require(PlanStore.plan(id: "zc-ftp-builder"))
        guard case .workout(let first)? = builder.weeks.first?.first else { Issue.record("FTP Builder starts on a workout"); return }
        #expect(WorkoutCatalog.entry(id: first).map { WorkoutCatalogFile.sessionOrder($0.name).week } == 1)
        #expect(WorkoutStore.workout(id: first) != nil)
        let entry = try #require(WorkoutCatalog.entries.first { $0.collection == "The Sufferfest" })
        let w = try #require(WorkoutStore.workout(id: entry.id))
        #expect(w.name == entry.name && w.duration == entry.seconds)
        #expect(WorkoutCatalog.collections.contains("The Sufferfest"))
    }

    @Test func widgetWeekEmptiesOnMonday() {
        var s = WidgetSummary()
        let week = WidgetSummary.week(containing: .now)
        s.weekStart = week.start
        s.weekSeconds = 3600
        s.weekRides = 2
        #expect(s.asOf(.now).weekSeconds == 3600)
        let nextWeek = s.asOf(week.end.addingTimeInterval(60))
        #expect(nextWeek.weekSeconds == 0 && nextWeek.weekRides == 0)
        // A summary from before weeks were stamped is left as it is.
        s.weekStart = nil
        #expect(s.asOf(week.end.addingTimeInterval(60)).weekSeconds == 3600)
    }

    @Test func weeksStartOnMonday() {
        let start = WidgetSummary.week(containing: .now).start
        #expect(Calendar.current.component(.weekday, from: start) == 2)
        #expect(Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: .now)?.start == start)
    }

    @Test func decodedCacheFollowsTheData() throws {
        let cache = DecodedCache<[Int]>(capacity: 2)
        let id = UUID()
        let a = try JSONEncoder().encode([1, 2, 3])
        let b = try JSONEncoder().encode([4])
        #expect(cache.value(id: id, data: a) == [1, 2, 3])
        #expect(cache.value(id: id, data: b) == [4]) // the ride was saved again: new data, new value
        #expect(cache.value(id: id, data: nil) == nil)
        // Oldest out first.
        for _ in 0..<3 { _ = cache.value(id: UUID(), data: a) }
        #expect(cache.value(id: id, data: b) == [4])
    }

    @Test func siriWontStartASecondRide() {
        let router = IntentRouter.shared
        let plan = SessionPlan() // each one has its own random terrain seed
        router.riding = true
        #expect(throws: IntentError.self) { try router.ride(plan) }
        #expect(router.pending == nil)
        router.riding = false
        #expect(throws: Never.self) { try router.ride(plan) }
        #expect(router.pending == .ride(plan))
        router.pending = nil
    }

    @Test func uploadRetriesWaitLongerThenGiveUp() throws {
        let now = Date(timeIntervalSince1970: 0)
        let waits = (1...5).map { UploadQueue.nextTry(after: $0, from: now)?.timeIntervalSince(now) }
        #expect(waits == [60, 300, 1800, 7200, 43_200])
        #expect(UploadQueue.nextTry(after: 6, from: now) == nil)
    }

    @Test func onlySomeUploadErrorsAreWorthRetrying() {
        #expect(UploadQueue.isRetryable(URLError(.notConnectedToInternet)))
        #expect(UploadQueue.isRetryable(URLError(.timedOut)))
        #expect(UploadQueue.isRetryable(UploadError.http(503, "down")))
        #expect(UploadQueue.isRetryable(UploadError.http(429, "slow down")))
        #expect(!UploadQueue.isRetryable(UploadError.http(401, "bad key")))
        #expect(!UploadQueue.isRetryable(UploadError.http(200, "duplicate of activity 1")))
        #expect(!UploadQueue.isRetryable(UploadError.notConfigured(.strava)))
    }

    @Test func theQueueAddsOnceAndForgets() {
        let queue = UploadQueue()
        let saved = queue.entries
        defer { queue.entries = saved }
        queue.entries = []
        let ride = UUID()
        queue.add(ride, .strava)
        queue.add(ride, .strava)
        #expect(queue.entries.count == 1)
        queue.failed(ride, .strava)
        #expect(queue.entries.first?.attempts == 1)
        for _ in 0..<5 { queue.failed(ride, .strava) }
        #expect(queue.entries.isEmpty) // gave up
        queue.add(ride, .intervals)
        queue.remove(ride, .intervals)
        #expect(!queue.contains(ride, .intervals))
    }

    @Test func preferenceRangesAgree() {
        #expect(Preferences.ftpRange.contains(200))
        #expect(Preferences.ftpRange.lowerBound == 60)
        #expect(Preferences.riderKgRange.contains(75))
    }
}
