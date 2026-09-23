import Foundation

/// Power zones from FTP (Coggan's 7 zones, as used by the ride faces).
public enum PowerZones {
    /// Upper bounds of zones 1–6 as a fraction of FTP; zone 7 is everything above.
    public static let cuts = [0.55, 0.75, 0.9, 1.05, 1.2, 1.5]
    public static let names = ["Z1 recovery", "Z2 endurance", "Z3 tempo", "Z4 threshold", "Z5 vo2max", "Z6 anaerobic", "Z7 sprint"]

    public static func zone(powerW: Double, ftp: Double) -> Int {
        let r = powerW / max(ftp, 1)
        for (i, c) in cuts.enumerated() where r < c { return i + 1 }
        return 7
    }

    public static func name(_ zone: Int) -> String { names[min(max(zone, 1), 7) - 1] }
}

/// Terrain shape for the faces: elevations normalised into 0.08…0.98 (with a minimum span so gentle
/// terrain stays gentle).
public enum FaceProfile {
    /// Elevation (m) after each step, from grades sampled every `stepSeconds` at a constant speed.
    public static func elevations(grades: [Double], stepSeconds: Double, speedMps: Double) -> [Double] {
        guard let first = grades.first else { return [] }
        var h = [0.0]
        var prev = first
        for g in grades.dropFirst() {
            h.append(h.last! + (prev + g) / 2 / 100 * max(speedMps, 3) * stepSeconds)
            prev = g
        }
        return h
    }

    public static func normalized(_ elevations: [Double], minSpan: Double = 15) -> [Double] {
        guard let lo = elevations.min(), let hi = elevations.max() else { return [] }
        let span = max(minSpan, hi - lo)
        return elevations.map { 0.08 + ($0 - lo) / span * 0.9 }
    }

    /// Resamples to `count` points (linear), e.g. 31 profile samples → 61 drawing points.
    public static func resample(_ values: [Double], count: Int) -> [Double] {
        guard values.count > 1, count > 1 else { return Array(repeating: values.first ?? 0.5, count: max(count, 0)) }
        return (0..<count).map { i in
            let x = Double(i) / Double(count - 1) * Double(values.count - 1)
            let lo = Int(x), hi = min(lo + 1, values.count - 1)
            return values[lo] + (values[hi] - values[lo]) * (x - Double(lo))
        }
    }
}

/// Everything the faces need beyond the raw metrics: pedal phase, 3 s power, trends and "magic moment" events.
/// Pure and clock-driven: call `update` on every engine tick with active ride time.
public struct FaceTelemetry: Sendable {
    public enum EventKind: String, Sendable { case start, shift, km, summit, best, sprint }

    public struct Event: Equatable, Sendable {
        public var kind: EventKind
        public var label: String
        public var n: Int
        /// Ride time the event fired at.
        public var time: Double

        public init(kind: EventKind, label: String, n: Int, time: Double) {
            self.kind = kind
            self.label = label
            self.n = n
            self.time = time
        }
    }

    /// How long an event stays on screen.
    public static let eventLifetime = 2.2
    /// A climb must last this long before cresting counts as a summit.
    public static let summitMinClimb = 30.0
    public static let bestCooldown = 30.0
    /// Sprint starts above this share of FTP, and ends once power drops below `sprintEnd`.
    public static let sprintStart = 1.5
    public static let sprintEnd = 1.35
    public static let sprintCooldown = 30.0

    public var ftp: Double
    public let unitMeters: Double
    public let unitName: String

    public private(set) var crankDegrees = 0.0
    public private(set) var power3 = 0.0
    public private(set) var bestPower = 0.0
    public private(set) var topSpeed = 0.0
    /// Change per second, over the last 5 s.
    public private(set) var trendSpeed = 0.0
    public private(set) var trendPower = 0.0
    public private(set) var event: Event?

    private var history: [(t: Double, speed: Double, power: Double)] = []
    private var lastGear: Int?
    private var lastGrade = 0.0
    private var climbStart: Double?
    private var units = 0
    private var lastUnitTime = 0.0
    private var lastBestEvent = -Double.infinity
    private var started = false
    private var sprinting = false
    private var lastSprintEvent = -Double.infinity

    public init(ftp: Double, unitMeters: Double = 1000, unitName: String = "Kilometre") {
        self.ftp = ftp
        self.unitMeters = unitMeters
        self.unitName = unitName
    }

    /// Age of the current event in 0…1 at ride time `t`, nil when none is showing.
    public func eventAge(at t: Double) -> Double? {
        guard let event else { return nil }
        let age = (t - event.time) / Self.eventLifetime
        return age < 1 ? max(0, age) : nil
    }

    public mutating func update(t: Double, dt: Double, speedKph: Double, powerW: Double, cadenceRpm: Double,
                                gradePercent: Double, gear: Int, distanceM: Double, moving: Bool) {
        if let e = event, t - e.time > Self.eventLifetime { event = nil }
        guard moving, dt > 0 else {
            lastGear = gear
            return
        }
        crankDegrees = (crankDegrees + cadenceRpm / 60 * 360 * dt).truncatingRemainder(dividingBy: 360)
        power3 += (powerW - power3) * min(1, dt / 3)
        topSpeed = max(topSpeed, speedKph)

        history.append((t, speedKph, powerW))
        history.removeAll { t - $0.t > 5 }
        trendSpeed = Self.slope(history.map { ($0.t, $0.speed) })
        trendPower = Self.slope(history.map { ($0.t, $0.power) })

        // The first moving tick of the ride: the face's "go".
        if !started {
            started = true
            fire(.start, "", n: 0, at: t)
        }

        if let lastGear, lastGear != gear { fire(.shift, "", n: gear, at: t) }
        lastGear = gear

        let unit = Int(distanceM / unitMeters)
        if unit > units {
            units = unit
            let split = t - lastUnitTime
            lastUnitTime = t
            fire(.km, "\(unitName) \(unit) · \(TimeFormat.clock(Int(split.rounded())))", n: unit, at: t)
        }

        if gradePercent > 0.6 {
            climbStart = climbStart ?? t
        } else {
            if lastGrade > 0.6, let start = climbStart, t - start >= Self.summitMinClimb { fire(.summit, "Summit", n: 0, at: t) }
            climbStart = nil
        }
        lastGrade = gradePercent

        // Sprint before best: crossing 150 % FTP usually sets a best too, and the sprint is the bigger moment.
        if !sprinting, powerW > ftp * Self.sprintStart, t - lastSprintEvent >= Self.sprintCooldown {
            sprinting = true
            lastSprintEvent = t
            fire(.sprint, "", n: Int(powerW.rounded()), at: t)
        } else if sprinting, powerW < ftp * Self.sprintEnd {
            sprinting = false
        }

        if powerW > bestPower + 6, powerW > ftp * 1.25, t - lastBestEvent >= Self.bestCooldown {
            fire(.best, "Session best · \(Int(powerW.rounded())) w", n: Int(powerW.rounded()), at: t)
            lastBestEvent = t
        }
        bestPower = max(bestPower, powerW)
    }

    /// A new event replaces nothing but a shift (shifts are the lowest priority).
    private mutating func fire(_ kind: EventKind, _ label: String, n: Int, at t: Double) {
        if let current = event, current.kind != .shift, kind == .shift { return }
        if let current = event, current.kind != .shift, current.kind != kind { return }
        event = Event(kind: kind, label: label, n: n, time: t)
    }

    /// Least-squares slope of (t, value) points.
    static func slope(_ points: [(Double, Double)]) -> Double {
        guard points.count >= 3 else { return 0 }
        let n = Double(points.count)
        let mt = points.map(\.0).reduce(0, +) / n
        let mv = points.map(\.1).reduce(0, +) / n
        let num = points.map { ($0.0 - mt) * ($0.1 - mv) }.reduce(0, +)
        let den = points.map { ($0.0 - mt) * ($0.0 - mt) }.reduce(0, +)
        return den > 0 ? num / den : 0
    }
}
