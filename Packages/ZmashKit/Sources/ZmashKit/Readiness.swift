import Foundation

/// How fresh you are, from the training load of recent rides: fitness is the 42-day average daily load,
/// fatigue the 7-day one, and form the difference (both exponentially weighted, the usual CTL/ATL model).
public enum Readiness {
    public struct State: Equatable, Sendable {
        public var fitness: Double
        public var fatigue: Double
        public var form: Double { fitness - fatigue }
        public init(fitness: Double = 0, fatigue: Double = 0) {
            self.fitness = fitness
            self.fatigue = fatigue
        }
    }

    /// What today's ride should be, from form.
    public enum Band: String, Sendable, CaseIterable {
        case recover, maintain, push

        public static func of(_ form: Double) -> Band {
            form < -20 ? .recover : form > 5 ? .push : .maintain
        }

        /// A line for the rider.
        public var reason: String {
            switch self {
            case .recover: "Tired from recent rides"
            case .maintain: "A steady day"
            case .push: "Fresh legs"
            }
        }
    }

    public static let fitnessDays = 42.0
    public static let fatigueDays = 7.0

    /// State at the start of `day` (before today's riding), from each ride's date and load.
    public static func state(_ loads: [(date: Date, tss: Double)], on day: Date, calendar: Calendar = .current) -> State {
        let today = calendar.startOfDay(for: day)
        var daily: [Date: Double] = [:]
        for l in loads {
            let d = calendar.startOfDay(for: l.date)
            guard d < today else { continue }
            daily[d, default: 0] += max(l.tss, 0)
        }
        guard var d = daily.keys.min() else { return State() }
        var s = State()
        while d < today {
            let tss = daily[d] ?? 0
            s.fitness += (tss - s.fitness) / fitnessDays
            s.fatigue += (tss - s.fatigue) / fatigueDays
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return s
    }
}

/// Picks what to suggest riding today.
public enum Suggestions {
    public struct Candidate: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case workout, route, free }
        /// Workout id, or route id (a climb or a stage window).
        public var id: String
        public var kind: Kind
        public var title: String
        public var minutes: Int
        /// The days it suits.
        public var bands: Set<Readiness.Band>

        public init(id: String, kind: Kind, title: String, minutes: Int, bands: Set<Readiness.Band>) {
            self.id = id
            self.kind = kind
            self.title = title
            self.minutes = minutes
            self.bands = bands
        }
    }

    /// Up to `limit` candidates for today: ones that suit the band, not ridden in the last week, closest to your usual
    /// ride length first. `firsts` (a plan's session, a campaign's next stage) always lead, whatever the band.
    public static func pick(_ candidates: [Candidate], band: Readiness.Band, usualMinutes: Int,
                            ridden recentIDs: Set<String>, firsts: [Candidate] = [], limit: Int = 3) -> [Candidate] {
        // Ties keep the given order (the library's), so the pick is the same every time.
        let fitting = candidates.enumerated()
            .filter { $0.element.bands.contains(band) && !recentIDs.contains($0.element.id) }
            .sorted { a, b in
                let da = abs(a.element.minutes - usualMinutes), db = abs(b.element.minutes - usualMinutes)
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)
        var out = firsts
        for c in fitting where !out.contains(where: { $0.id == c.id }) { out.append(c) }
        return Array(out.prefix(limit))
    }

    /// The median length of recent rides (45 min with none).
    public static func usualMinutes(_ recentSeconds: [Int]) -> Int {
        let s = recentSeconds.filter { $0 >= 300 }.sorted()
        guard !s.isEmpty else { return 45 }
        return s[s.count / 2] / 60
    }
}

public extension Workout {
    /// The load it asks for when every target is held (free steps counted at 60 % FTP).
    func estimatedLoad(ftp: Double) -> Training.Load {
        let watts = steps.flatMap { s in
            (0..<s.seconds).map { Int(((s.fraction(at: Double($0)) ?? 0.6) * ftp).rounded()) }
        }
        return Training.load(watts, ftp: ftp)
    }

    /// The days it suits, from its intensity: easy rides for tired legs, hard ones for fresh.
    var suitsBands: Set<Readiness.Band> {
        guard !isRampTest else { return [.push] }
        let f = estimatedLoad(ftp: 250).intensityFactor
        if f < 0.7 { return [.recover, .maintain] }
        if f < 0.85 { return [.maintain, .push] }
        return [.push]
    }
}
