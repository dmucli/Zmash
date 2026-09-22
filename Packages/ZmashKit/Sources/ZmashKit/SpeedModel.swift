import Foundation

/// Road model integrated over time (brief §6.1): power in, speed/distance/elevation/work out.
public struct SpeedModel: Equatable, Sendable {
    public var rider: RiderModel
    public private(set) var speedMps: Double = 0
    public private(set) var distanceM: Double = 0
    public private(set) var elevationGainM: Double = 0
    public private(set) var workJ: Double = 0

    /// Wheel/drivetrain rotational inertia, as extra equivalent mass.
    public static let inertiaKg = 1.0
    /// Longer gaps (app backgrounded, Bluetooth dropout) are clamped instead of integrated.
    public static let maxStep = 2.0

    public init(rider: RiderModel = RiderModel()) { self.rider = rider }

    public var speedKph: Double { speedMps * 3.6 }
    /// Mechanical work in kJ ≈ kcal burned (≈24 % gross efficiency × 4.184).
    public var kcal: Double { workJ / 1000 }

    public mutating func step(powerW: Double, gradePercent: Double, dt rawDt: Double) {
        guard rawDt > 0 else { return }
        let dt = min(rawDt, Self.maxStep)
        let power = max(powerW, 0)
        // Sub-step so large dt (up to 2 s) stays stable.
        let steps = max(1, Int((dt / 0.1).rounded(.up)))
        let h = dt / Double(steps)
        let theta = atan(gradePercent / 100)
        let m = rider.massKg + Self.inertiaKg
        for _ in 0..<steps {
            let v = speedMps
            let drive = power / max(v, 0.5)
            let gravity = rider.massKg * RiderModel.g * sin(theta)
            let rolling = v > 0.01 || drive > gravity ? rider.massKg * RiderModel.g * rider.crr * cos(theta) : 0
            let aero = 0.5 * rider.airDensity * rider.cdA * v * v
            var next = v + (drive - gravity - rolling - aero) / m * h
            if next < 0.05 && power == 0 && gravity >= 0 { next = 0 }
            speedMps = max(0, next)
            let avg = (v + speedMps) / 2
            distanceM += avg * h
            elevationGainM += max(0, avg * sin(theta) * h)
        }
        workJ += power * dt
    }

    public mutating func reset() {
        speedMps = 0
        distanceM = 0
        elevationGainM = 0
        workJ = 0
    }
}

/// FTMS virtual shifting (brief §6.3, path B): the simulated grade that makes the trainer — whose flywheel
/// speed is fixed by the physical gear — demand the power the chosen virtual gear needs at this cadence.
public enum EffectiveGrade {
    public static let range = -10.0...16.0
    public static let minCadence = 20.0
    public static let minTrainerSpeedMps = 3 / 3.6

    public static func compute(cadenceRpm: Double, gearRatio: Double, gradePercent: Double,
                               trainerSpeedMps: Double?, rider: RiderModel) -> Double {
        guard cadenceRpm >= minCadence, let vt = trainerSpeedMps, vt >= minTrainerSpeedMps else {
            return clamp(gradePercent)
        }
        let vGear = cadenceRpm / 60 * gearRatio * Gears.wheelCircumferenceM
        let required = rider.steadyPower(speedMps: vGear, gradePercent: gradePercent)
        let aeroAtTrainer = 0.5 * rider.airDensity * rider.cdA * vt * vt
        let slopeTerm = (required / vt - aeroAtTrainer) / (rider.massKg * RiderModel.g) - rider.crr
        // Small-angle: sin θ ≈ tan θ below ~16 %, good enough for the resistance target.
        return clamp(slopeTerm * 100)
    }

    private static func clamp(_ g: Double) -> Double { min(max(g, range.lowerBound), range.upperBound) }
}

/// First-order low-pass with time constant `tau` seconds.
public struct LowPass: Sendable {
    public var tau: Double
    public private(set) var value: Double?

    public init(tau: Double) { self.tau = tau }

    public mutating func update(_ x: Double, dt: Double) -> Double {
        guard let v = value, dt > 0 else { value = x; return x }
        let alpha = min(1, dt / (tau + dt))
        let next = v + (x - v) * alpha
        value = next
        return next
    }

    public mutating func reset() { value = nil }
}

/// Time-windowed rolling average with single-sample spike rejection (brief §6.4).
public struct RollingAverage: Sendable {
    public var window: Double
    private var samples: [(t: Double, v: Double)] = []

    public init(window: Double) { self.window = window }

    public mutating func add(_ value: Double, at t: Double) {
        // Drop a lone spike > 3× the recent median (typical BLE glitch), but only once there's history.
        if samples.count >= 4 {
            let sorted = samples.map(\.v).sorted()
            let median = sorted[sorted.count / 2]
            if median > 20, value > 3 * median { return }
        }
        samples.append((t, value))
        samples.removeAll { t - $0.t > max(window, 3) }
    }

    public func average(at t: Double) -> Double? {
        let recent = samples.filter { t - $0.t <= window }
        guard !recent.isEmpty else { return samples.last?.v }
        return recent.map(\.v).reduce(0, +) / Double(recent.count)
    }

    public mutating func reset() { samples.removeAll() }
}
