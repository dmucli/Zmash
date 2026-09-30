import SwiftUI
import ZmashKit

// Shared pieces for the round 3 faces (design/new round/RideFace3.dc.html): absolute placement on the
// 1194×834 canvas, number cells, seeded randomness, and clocks that keep motion smooth between 10 Hz samples.

extension View {
    /// Places a view with its top-left corner at (x, y) on the face canvas, like the design's absolute positioning.
    func at(_ x: CGFloat, _ y: CGFloat) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).offset(x: x, y: y)
    }
}

/// A value over its tracked uppercase label, the building block of every round 3 face.
struct R3Cell: View {
    let value: String
    let label: String
    var size: CGFloat = 60
    var weight: Double = 600
    var family: FaceFont.Family = .barlow
    var ink: Color
    var sub: Color
    var valueInk: Color? = nil
    var labelSize: CGFloat = 15
    var labelWeight: Double = 400
    var gap: CGFloat = 6
    var trailing = false
    var centered = false
    @Environment(\.faceFont) private var chosen

    var body: some View {
        let family = self.family == .marker ? .marker : (chosen ?? self.family)
        VStack(alignment: centered ? .center : trailing ? .trailing : .leading, spacing: gap) {
            Text(value).font(FaceFont.font(family, size, weight: weight))
                .foregroundStyle(valueInk ?? ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: size)
            Text(label).font(FaceFont.font(family, labelSize, weight: labelWeight))
                .tracking(labelSize * 0.3).textCase(.uppercase)
                .foregroundStyle(sub).lineLimit(1)
        }
    }
}

/// The design's seeded generator (Park–Miller), so textures and weathering look the same every time.
struct SeededRandom {
    private var s: Double
    init(_ seed: Int) { s = Double(seed) }
    mutating func next() -> Double {
        s = (s * 16807).truncatingRemainder(dividingBy: 2147483647)
        return s / 2147483647
    }
}

/// Integrates motion between samples: a crank angle, a road scroll, a lap position, a chain.
/// Data arrives at ~10 Hz; drawing runs at 60 fps, so positions advance from rates and ease back to the data.
@MainActor
final class MotionClock {
    private var last: Date?
    var value: Double = 0
    var value2: Double = 0
    var extra: Double = 0

    /// Seconds since the previous frame (capped, so a paused view doesn't jump when it resumes).
    func tick(_ date: Date) -> Double {
        let dt = min(max(last.map { date.timeIntervalSince($0) } ?? 0, 0), 0.1)
        last = date
        return dt
    }
}

/// Sample a normalised profile at 0…1 (linear interpolation), as the design's `samp`.
func sampleProfile(_ p: [Double], _ f: Double) -> Double {
    guard p.count > 1 else { return p.first ?? 0.5 }
    let x = min(max(f, 0), 1) * Double(p.count - 1)
    let i = Int(x), k = x - Double(i)
    return p[i] * (1 - k) + p[min(p.count - 1, i + 1)] * k
}

extension FaceData {
    /// Where the rider is, in km along the course if there is one, else ridden distance.
    var roadKm: Double { course.isEmpty ? distanceM / 1000 : courseAtKm }
    /// The course length, or (with no course) a little beyond where the rider is.
    var roadLengthKm: Double { course.isEmpty ? max(distanceM / 1000, 1) : max(courseKm, 0.1) }

    /// The whole road across 0…`roadLengthKm`, normalised 0.06…0.96 like `course`: the course when it's known,
    /// otherwise what's been ridden so far (a workout, manual gradient) on an honest scale, at least 40 m of relief,
    /// so a flat ride draws a low line rather than a slab.
    var wholeProfile: [Double] {
        guard course.isEmpty else { return course }
        guard let road, road.elevations.count > 1 else { return [0.06, 0.06] }
        let lengthM = roadLengthKm * 1000
        let samples = (0...200).map { road.elevation(atDistance: Double($0) / 200 * lengthM) }
        let lo = samples.min()!, relief = max(samples.max()! - lo, 40)
        return samples.map { 0.06 + ($0 - lo) / relief * 0.9 }
    }
}

extension EnvironmentValues {
    /// The font a rider picked for the face being drawn (nil: its own), for shared pieces like `R3Cell` (D109).
    @Entry var faceFont: FaceFont.Family? = nil
}
