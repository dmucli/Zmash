import Foundation

/// The road a ride follows, known in advance: a route by distance, or generated terrain ridden at the rider's pace.
/// The round 3 faces read it for the climbs ahead (Borne), the whole card (Stem), the TV profile (Broadcast)
/// and the painted finish of a climb (Tarmac).
public struct RideCourse: Sendable {
    public let route: Route
    public let climbs: [Climb]
    /// For generated (time-based) terrain: where the rider is on the course is found from elapsed time,
    /// because the terrain changes with time, not with distance.
    public let timing: RouteTiming?

    public init(route: Route, timing: RouteTiming? = nil) {
        self.route = route
        self.climbs = Climbs.find(route)
        self.timing = timing
    }

    /// A course from generated terrain, ridden at `powerW`.
    public static func generated(_ profile: TerrainProfile, rider: RiderModel, powerW: Double) -> RideCourse? {
        guard let route = profile.route(rider: rider, powerW: powerW) else { return nil }
        return RideCourse(route: route, timing: RouteTiming(times: route.cumulativeTimes(rider: rider, powerW: powerW)))
    }

    public var lengthM: Double { route.distanceM }

    /// Metres along the course.
    public func position(elapsed: Double, distanceM: Double) -> Double {
        guard let timing, timing.total > 0 else { return min(distanceM, lengthM) }
        // Generated terrain is the rider's own pace ridden for the ride's length, so the course clock is the ride's.
        let t = elapsed
        guard let i = timing.times.firstIndex(where: { $0 >= t }) else { return lengthM }
        guard i > 0 else { return 0 }
        let a = timing.times[i - 1], b = timing.times[i]
        let f = b > a ? (t - a) / (b - a) : 0
        return (Double(i - 1) + f) * Route.step
    }

    /// The whole course, normalised to 0.06…0.96 (as the design draws it), `count` points.
    public func normalizedProfile(count: Int = 201) -> [Double] {
        let lo = route.minElevationM, hi = route.maxElevationM, span = max(hi - lo, 1)
        return (0..<count).map { i in
            0.06 + (route.elevation(atDistance: Double(i) / Double(count - 1) * lengthM) - lo) / span * 0.9
        }
    }

    /// What the kilometre stone says at `m` metres along the course.
    public func climbInfo(at m: Double) -> ClimbInfo {
        var info = ClimbInfo()
        let last = climbs.last { $0.startM + $0.lengthM <= m }
        if let last {
            info.lastCategory = last.category
            info.lastGainM = last.gainM
            info.summit = m - (last.startM + last.lengthM) < 150
        }
        if let current = climbs.first(where: { m >= $0.startM && m < $0.startM + $0.lengthM }) {
            let top = current.startM + current.lengthM
            info.inClimb = true
            info.category = current.category
            info.gainM = current.gainM
            info.toSummitM = top - m
            info.leftM = max(0, current.summitElevationM - route.elevation(atDistance: m))
            let ahead = min(m + 1000, lengthM)
            info.nextKmGrade = ahead > m ? (route.elevation(atDistance: ahead) - route.elevation(atDistance: m)) / (ahead - m) * 100 : 0
        }
        if let next = climbs.first(where: { $0.startM > m }) {
            info.nextCategory = next.category
            info.nextInM = next.startM - m
            info.nextAverageGrade = next.averageGrade
            info.nextLengthM = next.lengthM
        }
        return info
    }
}

/// The current climb, the one just crested, and the next one.
public struct ClimbInfo: Equatable, Sendable {
    public var inClimb = false
    public var category: Climb.Category?
    public var gainM: Double = 0
    public var toSummitM: Double = 0
    /// Metres still to climb to the summit.
    public var leftM: Double = 0
    /// Average gradient of the next kilometre.
    public var nextKmGrade: Double = 0
    /// Crested within the last 150 m.
    public var summit = false
    public var lastCategory: Climb.Category?
    public var lastGainM: Double = 0
    public var nextCategory: Climb.Category?
    public var nextInM: Double?
    public var nextAverageGrade: Double = 0
    public var nextLengthM: Double = 0

    public init() {}
}
