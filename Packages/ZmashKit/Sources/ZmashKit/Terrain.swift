import Foundation

public enum Effort: String, CaseIterable, Codable, Sendable {
    case easy, medium, hard

    var multiplier: Double {
        switch self {
        case .easy: 0.6
        case .medium: 1.0
        case .hard: 1.35
        }
    }
}

public enum TerrainType: String, CaseIterable, Codable, Sendable {
    case flat, rolling, hilly, mountain
}

/// A time-based grade profile (brief §9): grade as a function of active seconds.
public struct TerrainProfile: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public var start: Double
        public var duration: Double
        public var grade: Double
        public var end: Double { start + duration }
    }

    /// Max grade change rate, %/s.
    public static let rampRate = 0.5
    public static let maxGrade = 16.0

    public private(set) var segments: [Segment]

    public init(segments: [Segment]) { self.segments = segments }

    public var duration: Double { segments.last?.end ?? 0 }

    /// Target (step) grade at `t`, before ramp smoothing.
    public func targetGrade(at t: Double) -> Double {
        guard let first = segments.first else { return 0 }
        if t <= first.start { return first.grade }
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return segments[lo].grade
    }

    /// Smoothed grade: each transition ramps at `rampRate` starting at the segment boundary.
    public func grade(at t: Double) -> Double {
        guard !segments.isEmpty else { return 0 }
        var g = segments[0].grade
        for s in segments.dropFirst() {
            guard t > s.start else { break }
            let elapsed = t - s.start
            let delta = s.grade - g
            let maxChange = Self.rampRate * elapsed
            g += max(-maxChange, min(maxChange, delta))
        }
        return g
    }

    /// Sampled profile for drawing (value per `step` seconds between `from` and `to`).
    public func samples(from: Double = 0, to: Double? = nil, step: Double = 10) -> [Double] {
        let end = to ?? duration
        guard end > from else { return [] }
        return stride(from: from, through: end, by: step).map(grade(at:))
    }

    public mutating func append(_ other: TerrainProfile) {
        let offset = duration
        segments += other.segments.map { Segment(start: $0.start + offset, duration: $0.duration, grade: $0.grade) }
    }
}

/// Seeded, reproducible terrain generator.
public enum TerrainGenerator {
    struct Style {
        var gradeRange: ClosedRange<Double>
        var segmentLength: ClosedRange<Double> // seconds
        var climbShare: Double                 // probability a segment climbs
    }

    static func style(_ type: TerrainType) -> Style {
        switch type {
        case .flat: Style(gradeRange: -1...2, segmentLength: 45...120, climbShare: 0.55)
        case .rolling: Style(gradeRange: -3...4, segmentLength: 60...180, climbShare: 0.55)
        case .hilly: Style(gradeRange: -5...7, segmentLength: 120...300, climbShare: 0.55)
        case .mountain: Style(gradeRange: -6...10, segmentLength: 60...360, climbShare: 0.6)
        }
    }

    /// Profile covering exactly `duration` seconds: warm-up, body, cool-down.
    public static func generate(duration: Double, type: TerrainType, effort: Effort, seed: UInt64) -> TerrainProfile {
        var rng = SplitMix64(seed: seed)
        let short = duration <= 15 * 60
        let warmup = short ? 120.0 : 180.0
        let cooldown = short ? 60.0 : 120.0
        let bodyLength = max(0, duration - warmup - cooldown)

        var segments: [TerrainProfile.Segment] = [
            .init(start: 0, duration: warmup / 2, grade: 0),
            .init(start: warmup / 2, duration: warmup / 2, grade: 1),
        ]
        segments += body(length: bodyLength, start: warmup, type: type, effort: effort, rng: &rng)
        segments.append(.init(start: warmup + bodyLength, duration: cooldown, grade: 0))
        return TerrainProfile(segments: segments)
    }

    /// An open-ended block (free ride + auto): no warm-up/cool-down, 10 minutes long.
    public static func block(index: Int, type: TerrainType, effort: Effort, seed: UInt64) -> TerrainProfile {
        var rng = SplitMix64(seed: seed &+ UInt64(index) &* 0x9E37_79B9)
        return TerrainProfile(segments: body(length: 600, start: 0, type: type, effort: effort, rng: &rng))
    }

    static func body(length: Double, start: Double, type: TerrainType, effort: Effort,
                     rng: inout SplitMix64) -> [TerrainProfile.Segment] {
        guard length > 0 else { return [] }
        let style = style(type)
        let climbShare = min(0.8, style.climbShare * (effort == .hard ? 1.15 : effort == .easy ? 0.9 : 1))
        var out: [TerrainProfile.Segment] = []
        var t = 0.0
        var climbed = 0.0, descended = 0.0
        var usedMax = false

        if type == .mountain {
            // 1–3 long climbs covering ≥ 25 % of the body, descents between.
            let climbs = length < 1200 ? 1 : length < 2700 ? 2 : 3
            let climbLength = length * Double.random(in: 0.3...0.45, using: &rng) / Double(climbs)
            let gap = (length - climbLength * Double(climbs)) / Double(climbs + 1)
            for _ in 0..<climbs {
                out += fill(gap, from: t, range: -6...2, effort: effort, lengths: 60...180, climbShare: 0.3, rng: &rng)
                t += gap
                // A long climb built from steady ramps.
                let pieces = max(1, Int(climbLength / 240))
                let base = Double.random(in: 4...7, using: &rng) * effort.multiplier
                for i in 0..<pieces {
                    let g = min(TerrainProfile.maxGrade, base + Double.random(in: -1...3, using: &rng) * effort.multiplier)
                    let d = climbLength / Double(pieces)
                    out.append(.init(start: t + Double(i) * d, duration: d, grade: rounded(g)))
                }
                t += climbLength
            }
            out += fill(length - t, from: t, range: -6...2, effort: effort, lengths: 60...180, climbShare: 0.3, rng: &rng)
            t = length
        } else {
            while t < length {
                let remaining = length - t
                var d = Double.random(in: style.segmentLength, using: &rng)
                if remaining - d < style.segmentLength.lowerBound / 2 { d = remaining }
                let climbing = Double.random(in: 0...1, using: &rng) < climbShare || climbed < descended
                var g: Double
                if climbing {
                    g = Double.random(in: 0.5...style.gradeRange.upperBound, using: &rng) * effort.multiplier
                    if effort == .easy, g >= style.gradeRange.upperBound * effort.multiplier - 0.25 {
                        if usedMax { g *= 0.8 } else { usedMax = true }
                    }
                } else {
                    g = Double.random(in: style.gradeRange.lowerBound...0, using: &rng)
                }
                // No descent in the last 30 s of the body (it flows into the cool-down).
                if remaining - d < 30, g < 0 { g = 0 }
                g = rounded(min(g, TerrainProfile.maxGrade))
                out.append(.init(start: t, duration: d, grade: g))
                if g > 0 { climbed += g * d } else { descended += -g * d }
                t += d
            }
        }
        return out.map { .init(start: $0.start + start, duration: $0.duration, grade: $0.grade) }
    }

    private static func fill(_ length: Double, from start: Double, range: ClosedRange<Double>, effort: Effort,
                             lengths: ClosedRange<Double>, climbShare: Double,
                             rng: inout SplitMix64) -> [TerrainProfile.Segment] {
        var out: [TerrainProfile.Segment] = []
        var t = 0.0
        while t < length - 0.5 {
            var d = min(Double.random(in: lengths, using: &rng), length - t)
            if length - t - d < lengths.lowerBound / 2 { d = length - t }
            let climbing = Double.random(in: 0...1, using: &rng) < climbShare
            let g = climbing
                ? Double.random(in: 0...range.upperBound, using: &rng) * effort.multiplier
                : Double.random(in: range.lowerBound...0, using: &rng)
            out.append(.init(start: start + t, duration: d, grade: rounded(g)))
            t += d
        }
        return out
    }

    private static func rounded(_ g: Double) -> Double { (g * 2).rounded() / 2 }
}
