import Foundation

/// A number on the ride screen made easy to read (D164), as a bike computer shows it: it changes at most once a
/// `interval`, it's smoothed, and it ignores wobbles within `deadband` of what it shows (no 84 ↔ 85 flicker). A real
/// change (at least `jump` away, or `jumpShare` of the value) shows at once: a sprint, a grade button.
public struct CalmNumber: Sendable {
    public var interval: Double = 1
    /// The exponential average's time constant, seconds; 0: no smoothing (the input is averaged already).
    public var smoothing: Double
    /// How finely it's shown: 1 for whole numbers, 0.1 for one decimal.
    public var step: Double
    public var deadband: Double
    public var jump: Double
    public var jumpShare: Double = 0

    public private(set) var shown: Double?
    private var average: Double?
    private var lastInput: Double?
    private var shownAt = -Double.infinity

    public init(smoothing: Double, step: Double, deadband: Double, jump: Double, jumpShare: Double = 0, interval: Double = 1) {
        self.smoothing = smoothing
        self.step = step
        self.deadband = deadband
        self.jump = jump
        self.jumpShare = jumpShare
        self.interval = interval
    }

    /// Takes the latest value (nil: the sensor's gone, and so is the number) at time `t`, seconds, and returns what to
    /// show.
    public mutating func update(_ value: Double?, at t: Double) -> Double? {
        guard let value else {
            (shown, average, lastInput) = (nil, nil, nil)
            return nil
        }
        if let a = average, let last = lastInput, smoothing > 0 {
            let dt = max(0, t - last)
            average = a + (value - a) * (1 - exp(-dt / smoothing))
        } else {
            average = value
        }
        lastInput = t
        guard let shownValue = shown else { return show(value, at: t) }
        // A real change: at once, and the average starts again from it.
        if abs(value - shownValue) >= max(jump, abs(shownValue) * jumpShare) {
            average = value
            return show(value, at: t)
        }
        guard t - shownAt >= interval, let a = average else { return shownValue }
        if abs(a - shownValue) < deadband { return shownValue }
        return show(a, at: t)
    }

    private mutating func show(_ value: Double, at t: Double) -> Double {
        // By the scale, not the step, so 31.44 is exactly 31.4.
        let scale = (1 / step).rounded()
        let rounded = (value * scale).rounded() / scale
        shown = rounded
        shownAt = t
        return rounded
    }
}

/// The ride's live numbers, calm (D164): speed, power (and its 3 s average), cadence, heart rate and grade.
public struct CalmNumbers: Sendable {
    public struct Values: Equatable, Sendable {
        public var speedKph: Double?
        public var powerW: Int?
        public var power3W: Int?
        public var cadenceRpm: Int?
        public var heartRateBpm: Int?
        public var grade: Double?

        public init(speedKph: Double? = nil, powerW: Int? = nil, power3W: Int? = nil, cadenceRpm: Int? = nil,
                    heartRateBpm: Int? = nil, grade: Double? = nil) {
            self.speedKph = speedKph
            self.powerW = powerW
            self.power3W = power3W
            self.cadenceRpm = cadenceRpm
            self.heartRateBpm = heartRateBpm
            self.grade = grade
        }
    }

    /// Speed moves smoothly already (it has the bike's inertia): only its decimal flickers.
    var speed = CalmNumber(smoothing: 0.8, step: 0.1, deadband: 0.15, jump: 3)
    /// Power comes averaged over the rider's window (Settings' Watts): held for a second, and a surge shows at once.
    var power = CalmNumber(smoothing: 0, step: 1, deadband: 3, jump: 40, jumpShare: 0.25)
    var power3 = CalmNumber(smoothing: 0, step: 1, deadband: 3, jump: 40, jumpShare: 0.25)
    /// A trainer's cadence wobbles a rpm or two from frame to frame.
    var cadence = CalmNumber(smoothing: 1.5, step: 1, deadband: 1.5, jump: 12)
    var heartRate = CalmNumber(smoothing: 1, step: 1, deadband: 1.5, jump: 12)
    /// Auto terrain eases the grade in tenths; a grade button's half-percent step shows at once.
    var grade = CalmNumber(smoothing: 0.5, step: 0.1, deadband: 0.15, jump: 0.45)

    public init() {}

    public mutating func update(_ live: Values, at t: Double) -> Values {
        Values(speedKph: speed.update(live.speedKph, at: t),
               powerW: power.update(live.powerW.map(Double.init), at: t).map { Int($0) },
               power3W: power3.update(live.power3W.map(Double.init), at: t).map { Int($0) },
               cadenceRpm: cadence.update(live.cadenceRpm.map(Double.init), at: t).map { Int($0) },
               heartRateBpm: heartRate.update(live.heartRateBpm.map(Double.init), at: t).map { Int($0) },
               grade: grade.update(live.grade, at: t))
    }
}
