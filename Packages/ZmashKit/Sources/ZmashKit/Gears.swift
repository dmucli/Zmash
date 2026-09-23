/// Virtual drivetrain: 24 gears with Zwift-like ratios (approximation; small steps low, bigger steps high).
public enum Gears {
    public static let ratios: [Double] = [
        0.75, 0.87, 0.99, 1.11, 1.23, 1.38, 1.53, 1.68,
        1.86, 2.04, 2.22, 2.40, 2.61, 2.82, 3.03, 3.24,
        3.49, 3.74, 3.99, 4.24, 4.54, 4.84, 5.14, 5.49,
    ]
    public static var count: Int { ratios.count }
    /// 1-based gear the rider starts in (ratio 2.40).
    public static let startGear = 12
    /// 700×25c.
    public static let wheelCircumferenceM = 2.105

    public static func ratio(for gear: Int) -> Double { ratios[min(max(gear, 1), count) - 1] }

    /// Speed the drivetrain implies at `cadence` in `gear`.
    public static func speedMps(cadenceRpm: Double, gear: Int) -> Double {
        cadenceRpm / 60 * ratio(for: gear) * wheelCircumferenceM
    }
}

/// A virtual cassette: `count` gears spanning the same 0.75–5.49 range as the 24-gear table.
/// Fewer gears = bigger jumps per shift.
public struct GearSet: Equatable, Sendable {
    public static let choices = [3, 6, 9, 12, 18, 24]
    public static let standard = GearSet(count: 24)

    public let ratios: [Double]
    /// 1-based gear closest to 2.40 (the neutral "flat road" ratio).
    public let startGear: Int

    public init(count: Int) {
        let n = min(max(count, 2), Gears.ratios.count)
        if n == Gears.ratios.count {
            ratios = Gears.ratios
        } else {
            // Sample the progressive 24-gear curve at n evenly spaced positions.
            let last = Double(Gears.ratios.count - 1)
            ratios = (0..<n).map { i in
                let x = Double(i) / Double(n - 1) * last
                let lo = Int(x.rounded(.down)), hi = min(lo + 1, Gears.ratios.count - 1)
                let f = x - Double(lo)
                let r = Gears.ratios[lo] + (Gears.ratios[hi] - Gears.ratios[lo]) * f
                return (r * 100).rounded() / 100
            }
        }
        startGear = (ratios.enumerated().min { abs($0.element - 2.4) < abs($1.element - 2.4) }?.offset ?? 0) + 1
    }

    public var count: Int { ratios.count }
    public func ratio(for gear: Int) -> Double { ratios[min(max(gear, 1), count) - 1] }
}

/// Gear and terrain state driven by `RideCommand`s. Pure; the session engine owns one.
public struct RideControls: Equatable, Sendable {
    public static let gradeStep = 0.5
    public static let gradeRange = -10.0...16.0
    public static let biasRange = -5.0...5.0

    public enum TerrainMode: String, Codable, Sendable { case manual, auto }

    public enum Outcome: Equatable, Sendable {
        case changed
        case atLimit
        case ignored
    }

    public private(set) var gear: Int
    public let gears: GearSet
    /// Manual grade, or the bias added on top of the auto profile.
    public private(set) var manualGrade: Double
    public private(set) var autoBias: Double
    public var mode: TerrainMode

    public init(gear: Int? = nil, gears: GearSet = .standard, manualGrade: Double = 0, autoBias: Double = 0,
                mode: TerrainMode = .manual) {
        self.gears = gears
        self.gear = min(max(gear ?? gears.startGear, 1), gears.count)
        self.manualGrade = manualGrade
        self.autoBias = autoBias
        self.mode = mode
    }

    public var gearRatio: Double { gears.ratio(for: gear) }

    /// Grade to ride at, given the auto profile's value when in auto mode.
    public func grade(autoProfile: Double = 0) -> Double {
        switch mode {
        case .manual: manualGrade
        case .auto: min(max(autoProfile + autoBias, Self.gradeRange.lowerBound), Self.gradeRange.upperBound)
        }
    }

    @discardableResult
    public mutating func apply(_ command: RideCommand) -> Outcome {
        switch command {
        case .shiftUp:
            guard gear < gears.count else { return .atLimit }
            gear += 1
        case .shiftDown:
            guard gear > 1 else { return .atLimit }
            gear -= 1
        case .gradeUp, .gradeDown:
            let delta = command == .gradeUp ? Self.gradeStep : -Self.gradeStep
            switch mode {
            case .manual:
                let next = manualGrade + delta
                guard Self.gradeRange.contains(next) else { return .atLimit }
                manualGrade = next
            case .auto:
                let next = autoBias + delta
                guard Self.biasRange.contains(next) else { return .atLimit }
                autoBias = next
            }
        case .pauseToggle, .endSession, .toggleTheme, .nextFace, .previousFace, .zoomIn, .zoomOut, .toggleControls:
            return .ignored
        }
        return .changed
    }
}
