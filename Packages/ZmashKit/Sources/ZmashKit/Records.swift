import Foundation

/// Personal records on the roads you've ridden, and lifetime totals told in cycling terms (roadmap Phase 13).
public enum Records {
    /// What records need from a saved ride.
    public struct Ride: Sendable {
        public var id: UUID
        public var date: Date
        /// The route id as saved: a race stage, a famous climb, an import, maybe with a "#from-to" window.
        public var routeID: String?
        public var activeSeconds: Int
        public var distanceM: Double
        public var elevationGainM: Double
        /// 1 Hz samples' speeds (km/h), for timing a climb inside a longer ride.
        public var speedsKph: [Double]

        public init(id: UUID, date: Date, routeID: String?, activeSeconds: Int, distanceM: Double,
                    elevationGainM: Double, speedsKph: [Double]) {
            self.id = id
            self.date = date
            self.routeID = routeID
            self.activeSeconds = activeSeconds
            self.distanceM = distanceM
            self.elevationGainM = elevationGainM
            self.speedsKph = speedsKph
        }
    }

    /// Where a famous climb runs inside a route: the climb ridden on its own spans all of it; on a stage, part.
    public struct Place: Equatable, Sendable {
        public var climbID: String
        public var startM: Double
        public var lengthM: Double
        public var gainM: Double

        public init(climbID: String, startM: Double, lengthM: Double, gainM: Double) {
            self.climbID = climbID
            self.startM = startM
            self.lengthM = lengthM
            self.gainM = gainM
        }
    }

    public struct Effort: Equatable, Sendable {
        public var climbID: String
        public var seconds: Int
        public var date: Date
        public var rideID: UUID
        /// Vertical metres per hour.
        public var vam: Double
    }

    /// Times for each famous climb a ride went over from foot to top. `places` gives the climbs on the ride's route
    /// (base id, before any window) in that route's metres; a windowed ride ("…#from-to") starts at `from`.
    public static func efforts(_ ride: Ride, places: [Place], window: ClosedRange<Double>?) -> [Effort] {
        guard !places.isEmpty, !ride.speedsKph.isEmpty else { return [] }
        let offset = window?.lowerBound ?? 0
        // Distance along the route at the end of each second.
        var along: [Double] = []
        along.reserveCapacity(ride.speedsKph.count)
        var m = offset
        for v in ride.speedsKph {
            m += max(v, 0) / 3.6
            along.append(m)
        }
        // The samples' integral can drift from the engine's distance; stretch it to agree at the end.
        let integrated = (along.last ?? offset) - offset
        if integrated > 0, ride.distanceM > 0 {
            let k = ride.distanceM / integrated
            along = along.map { offset + ($0 - offset) * k }
        }
        return places.compactMap { p in
            let end = p.startM + p.lengthM
            guard p.startM >= offset - 1, let a = along.firstIndex(where: { $0 >= p.startM }),
                  let b = along.firstIndex(where: { $0 >= end - 1 }), b > a else { return nil }
            let seconds = b - a
            return Effort(climbID: p.climbID, seconds: seconds, date: ride.date, rideID: ride.id,
                          vam: p.gainM / (Double(seconds) / 3600))
        }
    }

    /// The best (quickest) effort per climb.
    public static func bests(_ efforts: [Effort]) -> [String: Effort] {
        efforts.reduce(into: [:]) { best, e in
            if let b = best[e.climbID], b.seconds <= e.seconds { return }
            best[e.climbID] = e
        }
    }

    // MARK: Totals and milestones

    public struct Totals: Equatable, Sendable {
        public var distanceM: Double = 0
        public var elevationM: Double = 0
        public var seconds: Double = 0
        public var rides = 0
        public init() {}
    }

    public static func totals(_ rides: [Ride]) -> Totals {
        rides.reduce(into: Totals()) { t, r in
            t.distanceM += r.distanceM
            t.elevationM += r.elevationGainM
            t.seconds += Double(r.activeSeconds)
            t.rides += 1
        }
    }

    public static let everestM = 8848.0

    public enum Milestone: Equatable, Sendable {
        /// The n-th Everest climbed in total.
        case everest(Int)
        /// Every 1,000 km.
        case kilometres(Int)
        /// Every 100 hours.
        case hours(Int)

        public var title: String {
            switch self {
            case .everest(1): "Everest climbed: 8,848 m in total"
            case .everest(let n): "\(n) Everests climbed in total"
            case .kilometres(let k): "\(k.formatted()) km ridden"
            case .hours(let h): "\(h) hours in the saddle"
            }
        }
    }

    /// Milestones crossed going from `before` to `after` (a ride just saved).
    public static func crossed(from before: Totals, to after: Totals) -> [Milestone] {
        var out: [Milestone] = []
        let e0 = Int(before.elevationM / everestM), e1 = Int(after.elevationM / everestM)
        if e1 > e0 { out.append(.everest(e1)) }
        let k0 = Int(before.distanceM / 1_000_000), k1 = Int(after.distanceM / 1_000_000)
        if k1 > k0 { out.append(.kilometres(k1 * 1000)) }
        let h0 = Int(before.seconds / 360_000), h1 = Int(after.seconds / 360_000)
        if h1 > h0 { out.append(.hours(h1 * 100)) }
        return out
    }
}
