import Foundation

/// Rider + bike parameters for the road model.
public struct RiderModel: Equatable, Sendable {
    public var riderKg: Double
    public var bikeKg: Double
    public var cdA: Double
    public var crr: Double
    public var airDensity: Double

    public static let g = 9.81

    public init(riderKg: Double = 75, bikeKg: Double = 9, cdA: Double = 0.32, crr: Double = 0.004, airDensity: Double = 1.225) {
        self.riderKg = riderKg
        self.bikeKg = bikeKg
        self.cdA = cdA
        self.crr = crr
        self.airDensity = airDensity
    }

    public var massKg: Double { riderKg + bikeKg }

    /// Power needed to hold `speed` (m/s) steady on `gradePercent`.
    public func steadyPower(speedMps v: Double, gradePercent: Double) -> Double {
        let theta = atan(gradePercent / 100)
        let resist = massKg * Self.g * (sin(theta) + crr * cos(theta)) + 0.5 * airDensity * cdA * v * v
        return resist * v
    }
}

/// Synthetic rider for demo mode and the Simulator: holds a target cadence and produces the power
/// the virtual drivetrain demands, with a little noise.
public struct DemoRider: Sendable {
    public var targetCadence: Double = 85
    public var pedalling = true
    public var model = RiderModel()

    private var cadence: Double = 0
    private var rng: SplitMix64

    public init(seed: UInt64 = 42) { rng = SplitMix64(seed: seed) }

    public struct Sample: Equatable, Sendable {
        public var powerW: Int
        public var cadenceRpm: Double
        public var speedKph: Double
    }

    public mutating func step(dt: Double, gearRatio: Double, gradePercent: Double) -> Sample {
        let target = pedalling ? targetCadence + rng.noise(amplitude: 2) : 0
        // Cadence eases towards the target (~1.5 s time constant).
        cadence += (target - cadence) * min(1, dt / 1.5)
        if cadence < 1 { cadence = 0 }
        let v = cadence / 60 * gearRatio * Gears.wheelCircumferenceM
        var power = cadence > 0 ? model.steadyPower(speedMps: v, gradePercent: gradePercent) : 0
        power = min(max(power * (1 + rng.noise(amplitude: 0.03)), 0), 1200)
        return Sample(powerW: Int(power.rounded()), cadenceRpm: cadence.rounded(), speedKph: v * 3.6)
    }
}

/// Small, fast, seedable PRNG (reproducible terrain and demo data).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in −amplitude…amplitude.
    public mutating func noise(amplitude: Double) -> Double {
        Double.random(in: -amplitude...amplitude, using: &self)
    }
}

public extension Double {
    /// A gradient to one decimal for display, with −0.0 made 0.0 (so "%+.1f" never prints "-0.0").
    var displayGrade: Double { (self * 10).rounded() / 10 + 0 }
}
