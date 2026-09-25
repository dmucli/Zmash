import Foundation

/// One 1 Hz sample of a ride.
public struct RideSample: Codable, Equatable, Sendable {
    public var t: Int              // active seconds since start
    public var powerW: Int
    public var cadenceRpm: Int
    public var speedKph: Double
    public var gradePercent: Double
    public var gear: Int
    /// From a heart-rate strap, when one is paired.
    public var heartRateBpm: Int?
    /// Seconds the ride was paused just before this second (on the first sample after a pause; nil otherwise, and
    /// in rides from before pauses were kept).
    public var pausedBefore: Double?
    /// The strap's beat-to-beat intervals that arrived during this second, ms (D150); nil without them.
    public var rrMs: [Int]?

    public init(t: Int, powerW: Int, cadenceRpm: Int, speedKph: Double, gradePercent: Double, gear: Int,
                heartRateBpm: Int? = nil, pausedBefore: Double? = nil, rrMs: [Int]? = nil) {
        self.heartRateBpm = heartRateBpm
        self.pausedBefore = pausedBefore
        self.rrMs = rrMs
        self.t = t
        self.powerW = powerW
        self.cadenceRpm = cadenceRpm
        self.speedKph = speedKph
        self.gradePercent = gradePercent
        self.gear = gear
    }
}

/// A ride on the wall clock: samples are in active seconds, and pauses (`RideSample.pausedBefore`) put the gaps back.
public struct RideTimeline: Sendable {
    public struct Pause: Equatable, Sendable {
        /// Seconds from the start on the wall clock.
        public var from: Double
        public var seconds: Double
    }

    public private(set) var pauses: [Pause] = []
    /// Wall-clock offset of each active second that begins after a pause, for `wall(active:)`.
    private var steps: [(active: Int, pausedSoFar: Double)] = []

    public init(samples: [RideSample]) {
        var paused = 0.0
        for s in samples {
            guard let p = s.pausedBefore, p > 0 else { continue }
            pauses.append(Pause(from: Double(s.t) + paused, seconds: p))
            paused += p
            steps.append((s.t, paused))
        }
    }

    public var pausedSeconds: Double { pauses.map(\.seconds).reduce(0, +) }

    /// Seconds from the start on the wall clock, for an active second.
    public func wall(active t: Double) -> Double {
        t + (steps.last { Double($0.active) <= t }?.pausedSoFar ?? 0)
    }
}

/// Aggregates shown in the end-of-session modal and stored with the session.
public struct SessionSummary: Codable, Equatable, Sendable {
    public var activeSeconds: Int
    public var distanceM: Double
    public var elevationGainM: Double
    public var kcal: Double
    public var avgPowerW: Int
    public var maxPowerW: Int
    /// Average while pedalling (zeros excluded), like head units report.
    public var avgCadenceRpm: Int
    public var avgSpeedKph: Double
    public var avgHeartRateBpm: Int?
    public var maxHeartRateBpm: Int?

    public init(activeSeconds: Int, distanceM: Double, elevationGainM: Double, kcal: Double,
                avgPowerW: Int, maxPowerW: Int, avgCadenceRpm: Int, avgSpeedKph: Double,
                avgHeartRateBpm: Int? = nil, maxHeartRateBpm: Int? = nil) {
        self.avgHeartRateBpm = avgHeartRateBpm
        self.maxHeartRateBpm = maxHeartRateBpm
        self.activeSeconds = activeSeconds
        self.distanceM = distanceM
        self.elevationGainM = elevationGainM
        self.kcal = kcal
        self.avgPowerW = avgPowerW
        self.maxPowerW = maxPowerW
        self.avgCadenceRpm = avgCadenceRpm
        self.avgSpeedKph = avgSpeedKph
    }

    public static func from(samples: [RideSample], activeSeconds: Int, distanceM: Double,
                            elevationGainM: Double, kcal: Double) -> SessionSummary {
        let powers = samples.map(\.powerW)
        let cadences = samples.map(\.cadenceRpm).filter { $0 > 0 }
        let hr = samples.compactMap(\.heartRateBpm).filter { $0 > 0 }
        return SessionSummary(
            activeSeconds: activeSeconds,
            distanceM: distanceM,
            elevationGainM: elevationGainM,
            kcal: kcal,
            avgPowerW: powers.isEmpty ? 0 : Int((Double(powers.reduce(0, +)) / Double(powers.count)).rounded()),
            maxPowerW: powers.max() ?? 0,
            avgCadenceRpm: cadences.isEmpty ? 0 : Int((Double(cadences.reduce(0, +)) / Double(cadences.count)).rounded()),
            avgSpeedKph: activeSeconds > 0 ? distanceM / Double(activeSeconds) * 3.6 : 0,
            avgHeartRateBpm: hr.isEmpty ? nil : Int((Double(hr.reduce(0, +)) / Double(hr.count)).rounded()),
            maxHeartRateBpm: hr.max()
        )
    }
}

public enum Units: String, CaseIterable, Codable, Sendable {
    case metric, imperial

    public func speed(_ kph: Double) -> Double { self == .metric ? kph : kph / 1.609_344 }
    public func distance(_ meters: Double) -> Double { self == .metric ? meters / 1000 : meters / 1609.344 }
    public func elevation(_ meters: Double) -> Double { self == .metric ? meters : meters * 3.280_84 }
    public var speedUnit: String { self == .metric ? "km/h" : "mph" }
    public var distanceUnit: String { self == .metric ? "km" : "mi" }
    public var elevationUnit: String { self == .metric ? "m" : "ft" }
}

public enum TimeFormat {
    /// `m:ss`, or `h:mm:ss` from one hour.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// Bucketed averages of a ride's samples, for charts and the table view.
public struct SeriesPoint: Equatable, Sendable, Identifiable {
    public var id: Double { minute }
    /// Bucket start, in minutes of active time.
    public var minute: Double
    public var speedKph: Double
    public var powerW: Double
    /// Average while pedalling; nil when the bucket had no pedalling.
    public var cadenceRpm: Double?
    public var gradePercent: Double
    /// Average heart rate in the bucket, nil when no strap data.
    public var heartRateBpm: Double? = nil
}

public enum SampleSeries {
    /// Averages samples into at most `maxPoints` equal-time buckets (or `bucketSeconds` if given).
    public static func buckets(_ samples: [RideSample], maxPoints: Int = 300, bucketSeconds: Int? = nil) -> [SeriesPoint] {
        guard let last = samples.last, maxPoints > 0 else { return [] }
        let span = last.t + 1
        let size = bucketSeconds ?? max(1, Int((Double(span) / Double(maxPoints)).rounded(.up)))
        var groups: [Int: [RideSample]] = [:]
        for s in samples { groups[s.t / size, default: []].append(s) }
        return groups.keys.sorted().map { key in
            let g = groups[key]!
            let n = Double(g.count)
            let pedalling = g.filter { $0.cadenceRpm > 0 }
            let hr = g.compactMap(\.heartRateBpm).filter { $0 > 0 }
            return SeriesPoint(
                minute: Double(key * size) / 60,
                speedKph: g.map(\.speedKph).reduce(0, +) / n,
                powerW: Double(g.map(\.powerW).reduce(0, +)) / n,
                cadenceRpm: pedalling.isEmpty ? nil : Double(pedalling.map(\.cadenceRpm).reduce(0, +)) / Double(pedalling.count),
                gradePercent: g.map(\.gradePercent).reduce(0, +) / n,
                heartRateBpm: hr.isEmpty ? nil : Double(hr.reduce(0, +)) / Double(hr.count)
            )
        }
    }
}
