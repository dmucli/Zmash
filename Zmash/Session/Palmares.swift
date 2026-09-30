import Foundation
import SwiftData
import ZmashKit

/// Records on the famous climbs and lifetime totals, from saved rides (D91).
@MainActor
enum Palmares {
    /// The famous climbs on a route (by base id): the climb itself, or the ones a race stage goes over.
    static func places(routeID base: String) -> [Records.Place] {
        if base.hasPrefix("climb/"), let climb = RaceStore.climb(id: base) {
            let r = climb.route
            return [Records.Place(climbID: climb.id, startM: 0, lengthM: r.distanceM, gainM: r.ascentM)]
        }
        guard let (_, stage) = RaceStore.stage(routeID: base) else { return [] }
        return stage.famousClimbs.compactMap { p in
            guard let climb = RaceStore.climb(id: p.id) else { return nil }
            return Records.Place(climbID: p.id, startM: p.startM, lengthM: p.lengthM, gainM: climb.route.ascentM)
        }
    }

    static func ride(id: UUID, date: Date, routeID: String?, summary: SessionSummary, samples: [RideSample]) -> Records.Ride {
        Records.Ride(id: id, date: date, routeID: routeID, activeSeconds: summary.activeSeconds, distanceM: summary.distanceM,
                     elevationGainM: summary.elevationGainM, speedsKph: samples.map(\.speedKph))
    }

    static func efforts(_ ride: Records.Ride) -> [Records.Effort] {
        guard let id = ride.routeID else { return [] }
        let (base, window) = RouteStore.split(id)
        let base2 = RouteStore.legacyIDs[base] ?? base
        return Records.efforts(ride, places: places(routeID: base2), window: window)
    }

    /// Every saved ride's climb efforts. Only rides on a climb or a stage are read in full.
    static func allEfforts(excluding: UUID? = nil) -> [Records.Effort] {
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.routeID != nil })
        let rides = (try? RideStore.context.fetch(d)) ?? []
        return rides.filter { $0.id != excluding }.flatMap { s -> [Records.Effort] in
            guard let id = s.routeID, !places(routeID: RouteStore.split(id).base).isEmpty else { return [] }
            return efforts(ride(id: s.id, date: s.startedAt, routeID: id, summary: s.summary, samples: s.samples))
        }
    }

    static func totals(excluding: UUID? = nil) -> Records.Totals {
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid })
        let rides = ((try? RideStore.context.fetch(d)) ?? []).filter { $0.id != excluding }
        return rides.reduce(into: Records.Totals()) { t, s in
            t.distanceM += s.distanceM
            t.elevationM += s.elevationGainM
            t.seconds += Double(s.activeSeconds)
            t.rides += 1
        }
    }

    /// What a just-finished ride achieved: climbs ridden (with the previous best, if any) and milestones crossed.
    struct Result {
        struct Climb {
            let climb: FamousClimb
            let effort: Records.Effort
            let previousBest: Int?
            var isBest: Bool { previousBest.map { effort.seconds < $0 } ?? true }
        }
        let climbs: [Climb]
        let milestones: [Records.Milestone]
        var isEmpty: Bool { climbs.isEmpty && milestones.isEmpty }
    }

    static func result(for finished: FinishedRide) -> Result {
        let this = ride(id: finished.id, date: finished.startedAt, routeID: finished.plan.routeID,
                        summary: finished.summary, samples: finished.samples)
        let mine = efforts(this)
        let previous = mine.isEmpty ? [:] : Records.bests(allEfforts(excluding: finished.id))
        let climbs = mine.compactMap { e -> Result.Climb? in
            RaceStore.climb(id: e.climbID).map { Result.Climb(climb: $0, effort: e, previousBest: previous[e.climbID]?.seconds) }
        }
        let before = totals(excluding: finished.id)
        var after = before
        after.distanceM += finished.summary.distanceM
        after.elevationM += finished.summary.elevationGainM
        after.seconds += Double(finished.summary.activeSeconds)
        return Result(climbs: climbs, milestones: Records.crossed(from: before, to: after))
    }
}
