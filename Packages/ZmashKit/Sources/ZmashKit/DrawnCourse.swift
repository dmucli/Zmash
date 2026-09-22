import Foundation

/// A course drawn with a finger on the home screen. The drawing is the hill's silhouette,
/// stretched over the whole ride; Effort decides how steep its steepest climb gets, so any sketch rides sensibly.
public enum DrawnCourse {
    /// Heights kept per drawing, left to right.
    public static let points = 64
    /// Descents never go below the trainer's limit (U5).
    public static let minGrade = -10.0

    /// The steepest climb a drawing turns into, per effort.
    public static func maxGrade(_ effort: Effort) -> Double {
        switch effort {
        case .easy: 4
        case .medium: 7
        case .hard: 10
        }
    }

    /// Two hills, so the card never opens empty.
    public static let starter: [Double] = (0..<points).map { i in
        let x = Double(i) / Double(points - 1)
        return 0.18 + 0.42 * exp(-pow((x - 0.34) / 0.14, 2)) + 0.28 * exp(-pow((x - 0.76) / 0.1, 2))
    }

    /// Flat, for drawing from scratch.
    public static let blank = Array(repeating: 0.2, count: points)

    /// Gradient between consecutive points: the shape from the drawing, scaled so the steepest climb
    /// equals the effort's maximum (or, with no climbs at all, the steepest descent does).
    public static func grades(_ heights: [Double], effort: Effort) -> [Double] {
        let h = RouteBuilder.smooth(resample(heights, count: points))
        let rises = zip(h, h.dropFirst()).map { $1 - $0 }
        let steepestClimb = rises.max() ?? 0
        let reference = steepestClimb > 0.002 ? steepestClimb : (rises.map(abs).max() ?? 0)
        guard reference > 0.002 else { return rises.map { _ in 0 } }
        let scale = maxGrade(effort) / reference
        return rises.map { rise in
            let g = min(max(rise * scale, minGrade), maxGrade(effort))
            return (g * 10).rounded() / 10
        }
    }

    /// The drawing as a time-based profile lasting `duration` seconds.
    public static func profile(_ heights: [Double], duration: Double, effort: Effort) -> TerrainProfile {
        let g = grades(heights, effort: effort)
        let step = duration / Double(max(g.count, 1))
        return TerrainProfile(segments: g.enumerated().map { i, grade in
            TerrainProfile.Segment(start: Double(i) * step, duration: step, grade: grade)
        })
    }

    /// Linear resampling to `count` points (drawings from other sizes, or older saved ones).
    public static func resample(_ values: [Double], count: Int) -> [Double] {
        guard values.count > 1, count > 1 else { return Array(repeating: values.first ?? 0, count: max(count, 1)) }
        return (0..<count).map { i in
            let x = Double(i) / Double(count - 1) * Double(values.count - 1)
            let lo = Int(x), hi = min(lo + 1, values.count - 1)
            return values[lo] + (values[hi] - values[lo]) * (x - Double(lo))
        }
    }
}
