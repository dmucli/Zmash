import Foundation

/// Gentle coaching (roadmap Phase 14): short messages for the band, at most one a minute, never mid-sprint.
/// Everything it needs comes in through `Input` each tick; it remembers only what it has already said.
public struct Coach: Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case cadence, lastEffort, climbs, bests

        public var title: String {
            switch self {
            case .cadence: "Cadence"
            case .lastEffort: "Last effort of a workout"
            case .climbs: "Halfway up a climb"
            case .bests: "Your time at the top of a famous climb"
            }
        }
    }

    /// A famous climb on the route, and your best time on it.
    public struct FamousClimb: Sendable {
        public var name: String
        public var startM: Double
        public var endM: Double
        public var bestSeconds: Int?
        public init(name: String, startM: Double, endM: Double, bestSeconds: Int?) {
            self.name = name
            self.startM = startM
            self.endM = endM
            self.bestSeconds = bestSeconds
        }
    }

    public struct Input: Sendable {
        public var t: Double
        public var cadenceRpm: Double
        public var powerW: Double
        public var ftp: Double
        /// True when the trainer holds a workout target (cadence is then the rider's own business).
        public var erg: Bool
        /// In the last hard step of a workout: seconds left in it.
        public var lastEffortLeft: Double?
        /// Position along the course, and its categorised climbs.
        public var atM: Double?
        public var climbs: [Climb]
        /// Seconds ahead (+) or behind (−) your best on this route.
        public var ghostDelta: Double?

        public init(t: Double, cadenceRpm: Double, powerW: Double, ftp: Double, erg: Bool = false,
                    lastEffortLeft: Double? = nil, atM: Double? = nil, climbs: [Climb] = [], ghostDelta: Double? = nil) {
            self.t = t
            self.cadenceRpm = cadenceRpm
            self.powerW = powerW
            self.ftp = ftp
            self.erg = erg
            self.lastEffortLeft = lastEffortLeft
            self.atM = atM
            self.climbs = climbs
            self.ghostDelta = ghostDelta
        }
    }

    public var kinds: Set<Kind>
    public var famous: [FamousClimb]
    /// Metres per distance unit and its short name ("km" or "mi").
    public var unitM: Double
    public var unitName: String
    public static let spacing = 60.0

    private var lastSaid = -Double.infinity
    private var lowCadenceSince: Double?
    private var said: Set<String> = []
    private var enteredAt: [Int: Double] = [:]
    private var lastAtM: Double?

    public init(kinds: Set<Kind>, famous: [FamousClimb] = [], unitM: Double = 1000, unitName: String = "km") {
        self.kinds = kinds
        self.famous = famous
        self.unitM = unitM
        self.unitName = unitName
    }

    /// A message to show now, if any.
    public mutating func update(_ i: Input) -> String? {
        let previousM = lastAtM
        lastAtM = i.atM
        let sprinting = i.powerW > i.ftp * 1.5

        // At the top of a famous climb: always said (it's the moment), whatever the spacing.
        if kinds.contains(.bests), let m = i.atM {
            for (k, c) in famous.enumerated() {
                // Entered: crossing the foot, or starting on it (a climb ridden on its own starts at 0).
                if enteredAt[k] == nil, m >= c.startM, m < c.endM, previousM.map({ $0 < c.startM }) ?? (m - c.startM < 50) {
                    enteredAt[k] = i.t
                }
                guard let p = previousM, p < c.endM, m >= c.endM, let start = enteredAt[k] else { continue }
                enteredAt[k] = nil
                return say(summit(c, seconds: Int((i.t - start).rounded())), at: i.t)
            }
        }
        guard !sprinting, i.t - lastSaid >= Self.spacing else {
            trackCadence(i)
            return nil
        }

        if kinds.contains(.lastEffort), let left = i.lastEffortLeft, left <= 45, left > 5, !said.contains("last") {
            said.insert("last")
            return say("Last effort · \(Int(left.rounded())) s", at: i.t)
        }
        if kinds.contains(.climbs), let m = i.atM, let p = previousM {
            for c in i.climbs where c.category != nil {
                let half = c.startM + c.lengthM / 2
                let key = "half-\(Int(c.startM))"
                guard p < half, m >= half, !said.contains(key) else { continue }
                said.insert(key)
                var text = String(format: "Halfway up · %.1f %@ to the top", c.lengthM / 2 / unitM, unitName)
                if let g = i.ghostDelta, abs(g) >= 5 {
                    text += " · " + clock(abs(g)) + (g > 0 ? " up on your best" : " down on your best")
                }
                return say(text, at: i.t)
            }
        }
        if kinds.contains(.cadence), trackCadence(i) {
            lowCadenceSince = nil
            return say("Cadence has sat at \(Int(i.cadenceRpm.rounded())) for a minute: try a lighter gear", at: i.t)
        }
        return nil
    }

    /// True once cadence has been low (under 65 while pushing) for a full minute, outside ERG.
    @discardableResult
    private mutating func trackCadence(_ i: Input) -> Bool {
        guard !i.erg, i.powerW > 50, i.cadenceRpm > 0, i.cadenceRpm < 65 else {
            lowCadenceSince = nil
            return false
        }
        lowCadenceSince = lowCadenceSince ?? i.t
        return i.t - lowCadenceSince! >= 60
    }

    private mutating func say(_ text: String, at t: Double) -> String {
        lastSaid = t
        return text
    }

    private func summit(_ c: FamousClimb, seconds: Int) -> String {
        guard let best = c.bestSeconds else { return "First time up \(c.name) · \(clock(Double(seconds)))" }
        let diff = seconds - best
        if diff < 0 { return "New best on \(c.name) · \(clock(Double(seconds))), \(clock(Double(-diff))) quicker" }
        return "\(c.name) in \(clock(Double(seconds))) · \(clock(Double(diff))) off your best"
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
