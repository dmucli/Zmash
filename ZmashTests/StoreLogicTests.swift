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
