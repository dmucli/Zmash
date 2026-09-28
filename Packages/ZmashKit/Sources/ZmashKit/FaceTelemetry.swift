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
    public enum EventKind: String, Sendable { case start, shift, km, summit, best, sprint, flying200 }

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
    /// Piste's lap: a best 200 m only counts once the ride is under way, and is celebrated at most once a minute.
    public static let flyingAfterM = 1000.0
    public static let flyingCooldown = 60.0
    /// Groupset's spin-up: this cadence, held this long.
    public static let spinCadence = 120.0
    public static let spinHold = 5.0

    public var ftp: Double
    public let unitMeters: Double
    public let unitName: String

    public private(set) var crankDegrees = 0.0
    public private(set) var power3 = 0.0
    public private(set) var bestPower = 0.0
    /// Change per second, over the last 5 s.
    public private(set) var trendSpeed = 0.0
    public private(set) var event: Event?
    /// Fastest 200 m of the session, seconds.
    public private(set) var best200: Double?
    /// Cadence at or above 120 rpm for 5 s.
    public private(set) var spinUp = false

    /// An event that arrived while another was showing: it's shown next rather than lost.
    private var queued: Event?
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
    private var track: [(t: Double, d: Double)] = []
    private var lastFlyingEvent = -Double.infinity
    private var fastSince: Double?
    /// The best 200 m a new one has to beat to be celebrated: the best when the first kilometre was done,
    /// then each celebrated best (a best improves a little on every tick, so compare with a fixed mark).
    private var flyingBenchmark: Double?

    public init(ftp: Double, unitMeters: Double = 1000, unitName: String = "Kilometre") {
        self.ftp = ftp
        self.unitMeters = unitMeters
        self.unitName = unitName
    }

    /// Whether a tick without movement would change anything: an event to expire, or a gear to take note of.
    /// (Standing still, the engine skips the update otherwise, so nothing redraws for nothing.)
    public func needsIdleUpdate(gear: Int) -> Bool { event != nil || queued != nil || lastGear != gear }

    /// Age of the current event in 0…1 at ride time `t`, nil when none is showing.
    public func eventAge(at t: Double) -> Double? {
        guard let event else { return nil }
        let age = (t - event.time) / Self.eventLifetime
        return age < 1 ? max(0, age) : nil
    }

    public mutating func update(t: Double, dt: Double, speedKph: Double, powerW: Double, cadenceRpm: Double,
                                gradePercent: Double, gear: Int, distanceM: Double, moving: Bool) {
        if let e = event, t - e.time > Self.eventLifetime {
            event = queued.map { Event(kind: $0.kind, label: $0.label, n: $0.n, time: t) }
            queued = nil
        }
        guard moving, dt > 0 else {
            lastGear = gear
            return
        }
        crankDegrees = (crankDegrees + cadenceRpm / 60 * 360 * dt).truncatingRemainder(dividingBy: 360)
        power3 += (powerW - power3) * min(1, dt / 3)

        history.append((t, speedKph, powerW))
        history.removeAll { t - $0.t > 5 }
        trendSpeed = Self.slope(history.map { ($0.t, $0.speed) })

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

        // Best 200 m: the time taken over the last 200 m, interpolated.
        track.append((t, distanceM))
        while track.count > 2, distanceM - track[1].d >= 200 { track.removeFirst() }
        if distanceM - track[0].d >= 200, track.count > 1 {
            let a = track[0], b = track[1]
            let target = distanceM - 200
            let f = b.d > a.d ? (target - a.d) / (b.d - a.d) : 0
            let split = t - (a.t + (b.t - a.t) * min(max(f, 0), 1))
            if split > 0, split < (best200 ?? .infinity) { best200 = split }
        }
        if distanceM >= Self.flyingAfterM, let best = best200 {
            if let mark = flyingBenchmark {
                if best < mark - 0.1, t - lastFlyingEvent >= Self.flyingCooldown {
                    lastFlyingEvent = t
                    flyingBenchmark = best
                    fire(.flying200, String(format: "Flying 200 · %.1f s", best), n: 0, at: t)
                }
            } else {
                flyingBenchmark = best
            }
        }

        if cadenceRpm >= Self.spinCadence { fastSince = fastSince ?? t } else { fastSince = nil }
        spinUp = fastSince.map { t - $0 >= Self.spinHold } ?? false

        if powerW > bestPower + 6, powerW > ftp * 1.25, t - lastBestEvent >= Self.bestCooldown {
            fire(.best, "Session best · \(Int(powerW.rounded())) w", n: Int(powerW.rounded()), at: t)
            lastBestEvent = t
        }
        bestPower = max(bestPower, powerW)
    }

    /// A new event replaces nothing but a shift (shifts are the lowest priority). Any other event that finds
    /// the stage taken waits its turn (the latest one), so a kilometre or a summit is never lost.
    private mutating func fire(_ kind: EventKind, _ label: String, n: Int, at t: Double) {
        if let current = event, current.kind != .shift, kind == .shift { return }
        if let current = event, current.kind != .shift, current.kind != kind {
            queued = Event(kind: kind, label: label, n: n, time: t)
            return
        }
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

/// Tapping the ride screen's big number (D159): the next of a few live numbers, round and back to the rider's own.
public enum HeroCycle {
    /// The number after `current` in `ring`, with `home` (the face's main number, from Settings) first when it isn't
    /// one of them, so the round always comes back to it. Skips what `available` rules out (heart rate without a
    /// strap), though never `home`. `current` when there's nothing else to show.
    public static func next<M: Equatable>(after current: M, home: M, ring: [M], available: (M) -> Bool = { _ in true }) -> M {
        var order = ring
        if !order.contains(home) { order.insert(home, at: 0) }
        let start = order.firstIndex(of: current) ?? -1
        for step in 1...order.count {
            let m = order[(start + step + order.count) % order.count]
            if m != current, m == home || available(m) { return m }
        }
        return current
    }
}
