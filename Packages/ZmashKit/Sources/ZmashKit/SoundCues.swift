import Foundation

/// What the ride should sound like right now (roadmap Phase 15): continuous levels for wind, freewheel and crowd,
/// and one-off sounds for shifts, kilometres, summits, workout count-ins and the finish. Pure, so it can be tested;
/// the app's synthesiser plays it.
public struct SoundCues: Sendable {
    public enum OneShot: Equatable, Sendable {
        case shift(heavy: Bool)
        case kilometre
        case summit
        case countIn
        case finish
    }

    public struct Input: Sendable {
        public var speedKph: Double
        public var cadenceRpm: Double
        public var paused: Bool
        /// Gears moved since the last update (+ harder), 0 when none.
        public var shifted: Int
        /// A face event fired since the last update.
        public var event: FaceTelemetry.EventKind?
        /// Inside the last kilometre of a categorised climb: its category.
        public var finalKmOf: Climb.Category?
        /// A workout step is about to change: its index and the seconds left.
        public var stepEnding: (index: Int, left: Double)?
        public var finished: Bool

        public init(speedKph: Double, cadenceRpm: Double, paused: Bool = false, shifted: Int = 0,
                    event: FaceTelemetry.EventKind? = nil, finalKmOf: Climb.Category? = nil,
                    stepEnding: (index: Int, left: Double)? = nil, finished: Bool = false) {
            self.speedKph = speedKph
            self.cadenceRpm = cadenceRpm
            self.paused = paused
            self.shifted = shifted
            self.event = event
            self.finalKmOf = finalKmOf
            self.stepEnding = stepEnding
            self.finished = finished
        }
    }

    public struct Output: Equatable, Sendable {
        /// 0…1
        public var wind = 0.0
        /// Freewheel clicks per second (0 when pedalling or stopped).
        public var freewheelRate = 0.0
        /// 0…1
        public var crowd = 0.0
        public var oneShots: [OneShot] = []
    }

    public var kilometreChime: Bool
    /// Wheel circumference and freewheel engagement points, for the ticking rate.
    public static let wheelM = 2.105
    public static let pawls = 18.0

    private var countedIn: Set<Int> = []
    private var finishPlayed = false

    public init(kilometreChime: Bool = true) {
        self.kilometreChime = kilometreChime
    }

    public mutating func update(_ i: Input) -> Output {
        var out = Output()
        guard !i.paused else { return out }
        out.wind = min(max((i.speedKph - 25) / 35, 0), 1) * 0.6
        if i.cadenceRpm == 0, i.speedKph > 5 {
            out.freewheelRate = i.speedKph / 3.6 / Self.wheelM * Self.pawls
        }
        out.crowd = switch i.finalKmOf {
        case .hc: 1
        case .one: 0.8
        case .two: 0.6
        case .three: 0.45
        case .four: 0.35
        case nil: 0
        }
        if i.shifted != 0 { out.oneShots.append(.shift(heavy: abs(i.shifted) >= 2)) }
        switch i.event {
        case .km where kilometreChime: out.oneShots.append(.kilometre)
        case .summit: out.oneShots.append(.summit)
        default: break
        }
        if let s = i.stepEnding, s.left <= 3, s.left > 2, !countedIn.contains(s.index) {
            countedIn.insert(s.index)
            out.oneShots.append(.countIn)
        }
        if i.finished, !finishPlayed {
            finishPlayed = true
            out.oneShots.append(.finish)
        }
        return out
    }
}
