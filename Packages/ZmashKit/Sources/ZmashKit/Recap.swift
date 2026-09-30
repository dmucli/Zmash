import Foundation

/// A month or a year of riding, summed up for a shareable card (roadmap Phase 13).
public enum Recap {
    public struct Ride: Sendable {
        public var date: Date
        public var seconds: Int
        public var distanceM: Double
        public var elevationM: Double
        /// Base route id (no window), if it was a route.
        public var routeID: String?
        public var face: String?
        /// Best 20-minute power in the ride, if it lasted that long.
        public var best20W: Int?

        public init(date: Date, seconds: Int, distanceM: Double, elevationM: Double, routeID: String? = nil,
                    face: String? = nil, best20W: Int? = nil) {
            self.date = date
            self.seconds = seconds
            self.distanceM = distanceM
            self.elevationM = elevationM
            self.routeID = routeID
            self.face = face
            self.best20W = best20W
        }
    }

    public struct Summary: Equatable, Sendable {
        public var interval: DateInterval
        public var rides = 0
        public var seconds = 0
        public var distanceM = 0.0
        public var elevationM = 0.0
        /// The longest ride by time.
        public var longestSeconds = 0
        public var longestDate: Date?
        public var best20W: Int?
        /// The route ridden most (base id) and how often, when one was ridden more than once.
        public var topRoute: (id: String, count: Int)?
        public var favouriteFace: String?
        /// The longest run of consecutive calendar weeks with at least one ride.
        public var weekStreak = 0

        public static func == (a: Summary, b: Summary) -> Bool {
            a.interval == b.interval && a.rides == b.rides && a.seconds == b.seconds && a.distanceM == b.distanceM
                && a.elevationM == b.elevationM && a.longestSeconds == b.longestSeconds && a.best20W == b.best20W
                && a.topRoute?.id == b.topRoute?.id && a.topRoute?.count == b.topRoute?.count
                && a.favouriteFace == b.favouriteFace && a.weekStreak == b.weekStreak
        }
    }

    /// The month before the one containing `date`.
    public static func previousMonth(of date: Date, calendar: Calendar = .current) -> DateInterval {
        let thisMonth = calendar.dateInterval(of: .month, for: date)!
        return calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1))!
    }

    /// The year before the one containing `date`.
    public static func previousYear(of date: Date, calendar: Calendar = .current) -> DateInterval {
        let thisYear = calendar.dateInterval(of: .year, for: date)!
        return calendar.dateInterval(of: .year, for: thisYear.start.addingTimeInterval(-1))!
    }

    /// The rides in `interval`, summed up; nil when there were none.
    public static func summarize(_ all: [Ride], in interval: DateInterval, calendar: Calendar = .current) -> Summary? {
        let rides = all.filter { interval.contains($0.date) && $0.date < interval.end }
        guard !rides.isEmpty else { return nil }
        var s = Summary(interval: interval)
        s.rides = rides.count
        s.seconds = rides.map(\.seconds).reduce(0, +)
        s.distanceM = rides.map(\.distanceM).reduce(0, +)
        s.elevationM = rides.map(\.elevationM).reduce(0, +)
        if let longest = rides.max(by: { $0.seconds < $1.seconds }) {
            s.longestSeconds = longest.seconds
            s.longestDate = longest.date
        }
        s.best20W = rides.compactMap(\.best20W).max()
        let routes = Dictionary(grouping: rides.compactMap(\.routeID), by: { $0 }).mapValues(\.count)
        if let top = routes.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }), top.value > 1 {
            s.topRoute = (top.key, top.value)
        }
        let faces = Dictionary(grouping: rides.compactMap(\.face), by: { $0 }).mapValues(\.count)
        s.favouriteFace = faces.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        // Weeks with a ride, as week starts; then the longest run of consecutive ones.
        let weeks = Set(rides.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start }).sorted()
        var run = 0, best = 0
        var previous: Date?
        for w in weeks {
            if let p = previous, calendar.date(byAdding: .weekOfYear, value: 1, to: p) == w { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = w
        }
        s.weekStreak = best
        return s
    }
}
