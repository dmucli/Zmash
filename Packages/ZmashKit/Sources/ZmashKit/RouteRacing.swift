import Foundation

// MARK: - Pieces of a route, and how long they take

public extension Route {
    /// The part of the route between two distances, as a route of its own.
    func slice(fromM: Double, toM: Double, id: String? = nil, name: String? = nil) -> Route {
        let last = elevations.count - 1
        let a = min(max(Int((fromM / Self.step).rounded()), 0), max(last - 1, 0))
        let b = min(max(Int((toM / Self.step).rounded()), a + 1), last)
        return Route(id: id ?? self.id, name: name ?? self.name, place: place,
                     elevations: Array(elevations[a...b]), approximate: approximate)
    }

    /// The speed held steadily at `powerW` on `gradePercent` (solves the ride's own road model).
    /// Capped at 80 km/h downhill, as nobody holds more than that on a real descent.
    static func steadySpeed(powerW: Double, gradePercent: Double, rider: RiderModel) -> Double {
        let floor = 0.8, cap = 80 / 3.6
        if rider.steadyPower(speedMps: cap, gradePercent: gradePercent) <= powerW { return cap }
        if rider.steadyPower(speedMps: floor, gradePercent: gradePercent) >= powerW { return floor }
        var lo = floor, hi = cap
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if rider.steadyPower(speedMps: mid, gradePercent: gradePercent) < powerW { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Seconds to reach each profile point from the start, riding at a steady `powerW`.
    func cumulativeTimes(rider: RiderModel, powerW: Double) -> [Double] {
        var times = [0.0]
        times.reserveCapacity(elevations.count)
        for i in 0..<max(elevations.count - 1, 0) {
            let v = Self.steadySpeed(powerW: powerW, gradePercent: grade(atDistance: Double(i) * Self.step + 1), rider: rider)
            times.append(times[i] + Self.step / v)
        }
        return times
    }

    func estimatedTime(rider: RiderModel, powerW: Double) -> Double {
        cumulativeTimes(rider: rider, powerW: powerW).last ?? 0
    }
}

/// Where to put a window of `seconds` along a route, given its cumulative times.
public struct RouteTiming: Sendable {
    public let times: [Double]

    public init(times: [Double]) { self.times = times }

    public var total: Double { times.last ?? 0 }

    /// Distance reached `seconds` after starting at `fromM` (clamped to the end).
    public func end(after seconds: Double, from fromM: Double) -> Double {
        let i = index(fromM)
        let target = times[i] + seconds
        guard let j = times[i...].firstIndex(where: { $0 >= target }) else { return distance(times.count - 1) }
        return distance(j)
    }

    /// The latest start that still leaves `seconds` of riding: the finale.
    public func latestStart(for seconds: Double) -> Double {
        let target = total - seconds
        guard target > 0 else { return 0 }
        let i = times.lastIndex(where: { $0 <= target }) ?? 0
        return distance(i)
    }

    /// The start whose `seconds`-long window climbs the most.
    public func hardestStart(for seconds: Double, elevations: [Double]) -> Double {
        guard total > seconds, elevations.count == times.count else { return 0 }
        var ascent = [0.0]
        for (a, b) in zip(elevations, elevations.dropFirst()) { ascent.append(ascent.last! + max(0, b - a)) }
        var best = (start: 0, gain: -1.0)
        var j = 0
        for i in times.indices {
            if j < i { j = i }
            while j < times.count - 1, times[j] - times[i] < seconds { j += 1 }
            guard times[j] - times[i] >= seconds * 0.98 else { break }
            let gain = ascent[j] - ascent[i]
            if gain > best.gain { best = (i, gain) }
        }
        return distance(best.start)
    }

    private func index(_ m: Double) -> Int { min(max(Int((m / Route.step).rounded()), 0), times.count - 1) }
    private func distance(_ i: Int) -> Double { Double(i) * Route.step }
}

// MARK: - Climbs

public struct Climb: Equatable, Sendable {
    public enum Category: String, Sendable, CaseIterable {
        case hc = "HC", one = "1", two = "2", three = "3", four = "4"
    }

    public var startM: Double
    public var lengthM: Double
    public var gainM: Double
    public var summitElevationM: Double

    public var averageGrade: Double { lengthM > 0 ? gainM / lengthM * 100 : 0 }
    /// Gain × average gradient: long and steep both count, as in race categorisation.
    public var score: Double { gainM * averageGrade / 100 }

    public var category: Category? {
        switch score {
        case 60...: .hc
        case 35..<60: .one
        case 18..<35: .two
        case 8..<18: .three
        case 3..<8: .four
        default: nil
        }
    }
}

public enum Climbs {
    /// Climbs along a route, in order. A climb runs from a low point for as long as the road stays within
    /// max(20 m, 10 % of the gain so far) of its high point, and counts from 40 m of gain over 300 m at 3 %,
    /// so Flemish bergs make it and false flats don't.
    /// `categorisedOnly: false` also keeps short climbs too small for a category (a Flemish berg smoothed to 100 m).
    public static func find(_ route: Route, categorisedOnly: Bool = true) -> [Climb] {
        let e = route.elevations
        guard e.count > 2 else { return [] }
        var climbs: [Climb] = []
        var i = 0
        while i < e.count - 1 {
            // Start at a low point.
            guard e[i + 1] > e[i] else { i += 1; continue }
            var peak = i
            var j = i + 1
            while j < e.count {
                if e[j] > e[peak] { peak = j }
                let gain = e[peak] - e[i]
                if e[peak] - e[j] > max(20, gain * 0.1) { break }
                j += 1
            }
            // The foot and the top: the stretch where gain² ÷ length peaks. A flat approach or a flat summit
            // plateau adds length without gain and is trimmed (a section stays only if it's at least half as steep
            // as the climb); a steady climb keeps adding gain and stays whole.
            var foot = i, top = peak
            var bestScore = -1.0
            if peak > i {
                for s in i..<peak {
                    for t in (s + 1)...peak where e[t] > e[s] {
                        let gain = e[t] - e[s]
                        let score = gain * gain / Double(t - s)
                        if score > bestScore { bestScore = score; foot = s; top = t }
                    }
                }
            }
            let climb = Climb(startM: Double(foot) * Route.step, lengthM: Double(top - foot) * Route.step,
                              gainM: e[top] - e[foot], summitElevationM: e[top])
            if climb.gainM >= (categorisedOnly ? 40 : 25), climb.lengthM >= 300, climb.averageGrade >= 3,
               climb.category != nil || !categorisedOnly {
                climbs.append(climb)
            }
            i = max(peak, i + 1)
        }
        return climbs
    }
}

// MARK: - Race catalog

/// Real races, bundled as elevation profiles (generated from GPX by the `race-catalog` tool).
public struct RaceCatalog: Codable, Equatable, Sendable {
    public var races: [Race]
    /// Famous climbs cut from the races (plan part A).
    public var climbs: [FamousClimb]

    public init(races: [Race], climbs: [FamousClimb] = []) {
        self.races = races
        self.climbs = climbs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        races = try c.decode([Race].self, forKey: .races)
        climbs = try c.decodeIfPresent([FamousClimb].self, forKey: .climbs) ?? []
    }
}

public struct Race: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case grandTour = "grand-tour", stageRace = "stage-race", classic

        public var title: String {
            switch self {
            case .grandTour: "Grand Tours"
            case .stageRace: "Stage races"
            case .classic: "Classics"
            }
        }
    }

    /// "2026/tour-de-france"
    public var id: String
    public var name: String
    public var year: Int
    public var kind: Kind
    /// ISO country code(s), e.g. "FR", "IT AT".
    public var country: String
    public var stages: [Stage]

    public init(id: String, name: String, year: Int, kind: Kind, country: String, stages: [Stage]) {
        self.id = id
        self.name = name
        self.year = year
        self.kind = kind
        self.country = country
        self.stages = stages
    }

    /// Classics are one-day races; stage races stay stage races even if only one stage is on file.
    public var isOneDay: Bool { kind == .classic }
}

public struct Stage: Codable, Equatable, Sendable {
    /// A famous climb on this stage: which one, and where it runs along the stage.
    public struct FamousClimbPlace: Codable, Equatable, Sendable {
        /// `FamousClimb.id`
        public var id: String
        public var startM: Double
        public var lengthM: Double

        public init(id: String, startM: Double, lengthM: Double) {
            self.id = id
            self.startM = startM
            self.lengthM = lengthM
        }
    }

    /// 1-based; 1 for a one-day race.
    public var number: Int
    /// Elevation every `Route.step` metres, whole metres.
    public var elevations: [Int]
    /// The famous climbs it rides, in order (empty in catalogs built before they were recorded).
    public var famousClimbs: [FamousClimbPlace]

    public init(number: Int, elevations: [Int], famousClimbs: [FamousClimbPlace] = []) {
        self.number = number
        self.elevations = elevations
        self.famousClimbs = famousClimbs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        elevations = try c.decode([Int].self, forKey: .elevations)
        famousClimbs = try c.decodeIfPresent([FamousClimbPlace].self, forKey: .famousClimbs) ?? []
    }
}

public extension Race {
    /// Route id for a stage: "race/2026/tour-de-france/17".
    func routeID(_ stage: Stage) -> String { "race/\(id)/\(stage.number)" }

    func route(_ stage: Stage) -> Route {
        Route(id: routeID(stage), name: isOneDay ? name : "\(name) · Stage \(stage.number)",
              place: "\(year) · \(country)", elevations: stage.elevations.map(Double.init))
    }
}

/// Proper names for the race folders, whose slugs have lost their accents and punctuation.
public enum RaceNames {
    public static let known: [String: (name: String, country: String)] = [
        "tour-de-france": ("Tour de France", "FR"),
        "giro-d-italia": ("Giro d'Italia", "IT"),
        "vuelta-a-espa-a": ("Vuelta a España", "ES"),
        "paris-nice": ("Paris–Nice", "FR"),
        "tirreno-adriatico": ("Tirreno–Adriatico", "IT"),
        "volta-a-catalunya": ("Volta a Catalunya", "ES"),
        "itzulia-basque-country": ("Itzulia Basque Country", "ES"),
        "tour-of-the-alps": ("Tour of the Alps", "IT AT"),
        "uae-tour": ("UAE Tour", "AE"),
        "volta-ao-algarve": ("Volta ao Algarve", "PT"),
        "ruta-del-sol": ("Ruta del Sol", "ES"),
        "tour-of-valencia": ("Volta a la Comunitat Valenciana", "ES"),
        "o-gran-cami-o": ("O Gran Camiño", "ES"),
        "milan-sanremo": ("Milan–San Remo", "IT"),
        "tour-of-flanders": ("Tour of Flanders", "BE"),
        "tour-of-flanders-women": ("Tour of Flanders Women", "BE"),
        "paris-roubaix": ("Paris–Roubaix", "FR"),
        "paris-roubaix-femmes": ("Paris–Roubaix Femmes", "FR"),
        "li-ge-bastogne-li-ge": ("Liège–Bastogne–Liège", "BE"),
        "amstel-gold-race": ("Amstel Gold Race", "NL"),
        "amstel-gold-race-ladies-edition": ("Amstel Gold Race Women", "NL"),
        "strade-bianche": ("Strade Bianche", "IT"),
        "strade-bianche-donne": ("Strade Bianche Donne", "IT"),
        "omloop-het-nieuwsblad": ("Omloop Het Nieuwsblad", "BE"),
        "kuurne-brussels-kuurne": ("Kuurne–Brussels–Kuurne", "BE"),
        "e3-saxo-classic": ("E3 Saxo Classic", "BE"),
        "in-flanders-fields": ("Gent–Wevelgem In Flanders Fields", "BE"),
        "dwars-door-vlaanderen": ("Dwars door Vlaanderen", "BE"),
        "brabantse-pijl": ("Brabantse Pijl", "BE"),
    ]

    /// The race's proper name, or the slug in title case when it isn't known.
    public static func name(_ slug: String) -> (name: String, country: String) {
        known[slug] ?? (slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " "), "")
    }
}

// MARK: - Generated terrain as a real road

public extension TerrainProfile {
    /// The course as a real road: ridden at a steady `powerW`, time-based gradients become distance and metres
    /// of elevation, so a preview can show what you'll actually climb.
    func route(rider: RiderModel, powerW: Double, id: String = "course", name: String = "Course") -> Route? {
        let dt = 2.0
        var t = 0.0, distance = 0.0, elevation = 0.0
        var points: [(distanceM: Double, elevationM: Double)] = [(0, 0)]
        while t < duration {
            let g = grade(at: t)
            let v = Route.steadySpeed(powerW: powerW, gradePercent: g, rider: rider)
            let step = v * min(dt, duration - t)
            distance += step
            elevation += step * sin(atan(g / 100))
            points.append((distance, elevation))
            t += dt
        }
        return RouteBuilder.make(id: id, name: name, points: points)
    }
}
