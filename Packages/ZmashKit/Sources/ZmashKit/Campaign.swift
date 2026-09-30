import Foundation

/// A stage race ridden as a campaign (roadmap Phase 14): stage by stage, against 20 virtual rivals, with a general
/// classification on time and a mountains classification on points.
///
/// Rivals ride each stage's real profile with the same physics as you, at a steady share of your estimate pace
/// (85–115 %), give or take a few percent a day. Your time for a stage is what you rode, plus, for a finale, the part
/// you skipped at your estimate pace, so short rides still move you through a Tour.
public enum Campaign {
    public struct Rival: Codable, Equatable, Sendable {
        public var name: String
        /// Power as a share of your estimate pace.
        public var factor: Double
    }

    /// Mountains points for the first three over each categorised climb.
    public static func points(_ category: Climb.Category) -> [Int] {
        switch category {
        case .hc: [20, 15, 12]
        case .one: [10, 8, 6]
        case .two: [5, 3, 2]
        case .three: [2, 1]
        case .four: [1]
        }
    }

    // MARK: Rivals

    private static let first = ["Luca", "Mathis", "Jonas", "Pablo", "Tom", "Arne", "Nico", "Iker", "Simon", "Oskar",
                                "Rémi", "Matteo", "Jasper", "Hugo", "Lars", "Diego", "Felix", "Bram", "Enzo", "Kai",
                                "Aurélien", "Mikel", "Timo", "Victor"]
    private static let last = ["Varenne", "Bellandi", "Oosterhuis", "Urkiola", "Kessler", "Dufresne", "Marchetti",
                               "Lindqvist", "Etxeberria", "Vandamme", "Moreau", "Castellano", "Brandt", "Rinaldi",
                               "Verhulst", "Laborde", "Holmqvist", "Ferrand", "Novak", "De Wolf", "Garmendia", "Pellegrini"]

    /// 20 invented riders (names chosen not to match real pros), spread evenly from 85 % to 115 % of your pace, in a seeded order.
    public static func rivals(seed: UInt64, count: Int = 20) -> [Rival] {
        var rng = Seeded(seed)
        var names: Set<String> = []
        return (0..<count).map { i in
            var name: String
            repeat {
                name = first[Int(rng.next() * Double(first.count))] + " " + last[Int(rng.next() * Double(last.count))]
            } while names.contains(name)
            names.insert(name)
            let spread = count > 1 ? Double(i) / Double(count - 1) : 0.5
            return Rival(name: name, factor: 0.85 + 0.30 * spread + (rng.next() - 0.5) * 0.01)
        }
    }

    /// A rival's form on a stage: within ±3 %, the same every time for that seed, rival and stage.
    static func dayFactor(seed: UInt64, rival: Int, stage: Int) -> Double {
        var rng = Seeded(seed &+ UInt64(rival) &* 7919 &+ UInt64(stage) &* 104_729)
        return 0.97 + rng.next() * 0.06
    }

    // MARK: A stage

    /// What the rider did on a stage, as the app records it.
    public struct Ridden: Codable, Equatable, Sendable {
        public var stage: Int
        /// The part ridden, metres along the stage.
        public var fromM: Double
        public var toM: Double
        /// Time to ride that part.
        public var seconds: Double
        /// Time from the start of the part to each categorised climb's top inside it (nil if not reached), in the
        /// order `categorisedClimbs` lists them.
        public var summitSeconds: [Double?]
        /// The saved ride that rode it (nil in campaigns from before this was kept).
        public var rideID: UUID?

        public init(stage: Int, fromM: Double, toM: Double, seconds: Double, summitSeconds: [Double?]) {
            self.stage = stage
            self.fromM = fromM
            self.toM = toM
            self.seconds = seconds
            self.summitSeconds = summitSeconds
        }
    }

    public struct StageResult: Equatable, Sendable {
        public var stage: Int
        /// Index 0 is you, then each rival in order.
        public var seconds: [Double]
        public var points: [Int]
        /// Your time for the part you skipped, at your estimate pace.
        public var handicap: Double

        /// Your place on the stage, 1-based.
        public var place: Int { seconds.filter { $0 < seconds[0] }.count + 1 }
    }

    /// The categorised climbs whose tops fall inside the ridden part, in order.
    public static func categorisedClimbs(_ route: Route, within window: ClosedRange<Double>) -> [Climb] {
        Climbs.find(route).filter { c in
            let top = c.startM + c.lengthM
            return c.category != nil && top > window.lowerBound && top <= window.upperBound + 1
        }
    }

    /// Everyone's time for a stage, and the mountains points on the part ridden.
    public static func result(route: Route, ridden: Ridden, rivals: [Rival], seed: UInt64,
                              rider: RiderModel, pacePowerW: Double) -> StageResult {
        let window = ridden.fromM...max(ridden.toM, ridden.fromM)
        let pace = RouteTiming(times: route.cumulativeTimes(rider: rider, powerW: pacePowerW))
        let time = { (t: RouteTiming, m: Double) in t.times[index(m, t)] }
        let handicap = time(pace, window.lowerBound) + (pace.total - time(pace, window.upperBound))

        var seconds = [ridden.seconds + handicap]
        var rivalTimings: [RouteTiming] = []
        for (i, rival) in rivals.enumerated() {
            let power = pacePowerW * rival.factor * dayFactor(seed: seed, rival: i, stage: ridden.stage)
            let t = RouteTiming(times: route.cumulativeTimes(rider: rider, powerW: power))
            rivalTimings.append(t)
            seconds.append(t.total)
        }

        var awarded = Array(repeating: 0, count: rivals.count + 1)
        for (k, climb) in categorisedClimbs(route, within: window).enumerated() {
            guard let category = climb.category else { continue }
            let top = climb.startM + climb.lengthM
            // Everyone over the top, timed from the start of the part ridden.
            var crossings: [(who: Int, t: Double)] = rivalTimings.enumerated().map { i, t in
                (i + 1, time(t, top) - time(t, window.lowerBound))
            }
            if k < ridden.summitSeconds.count, let mine = ridden.summitSeconds[k] { crossings.append((0, mine)) }
            crossings.sort { $0.t < $1.t }
            for (place, award) in points(category).enumerated() where place < crossings.count {
                awarded[crossings[place].who] += award
            }
        }
        return StageResult(stage: ridden.stage, seconds: seconds, points: awarded, handicap: handicap)
    }

    private static func index(_ m: Double, _ t: RouteTiming) -> Int {
        min(max(Int((m / Route.step).rounded()), 0), t.times.count - 1)
    }

    // MARK: Classifications

    public struct Standing: Equatable, Sendable {
        public var name: String
        public var isYou: Bool
        public var seconds: Double
        public var points: Int
    }

    /// The general classification (least total time first) and the mountains (most points first; time breaks ties).
    public static func classifications(_ results: [StageResult], rivals: [Rival], you: String = "You")
        -> (general: [Standing], mountains: [Standing]) {
        let names = [you] + rivals.map(\.name)
        let standings = names.indices.map { i in
            Standing(name: names[i], isYou: i == 0,
                     seconds: results.map { $0.seconds[i] }.reduce(0, +),
                     points: results.map { $0.points[i] }.reduce(0, +))
        }
        let general = standings.sorted { $0.seconds < $1.seconds }
        let mountains = standings.sorted { $0.points != $1.points ? $0.points > $1.points : $0.seconds < $1.seconds }
        return (general, mountains)
    }
}

/// A small seeded generator (SplitMix64), so a campaign's rivals and their days are the same every time.
struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
