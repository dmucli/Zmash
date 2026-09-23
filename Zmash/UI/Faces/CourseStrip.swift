import SwiftUI
import ZmashKit

/// How much of the course the profile under the face shows: all of it, or a window around you.
enum CourseZoom: String, CaseIterable, Codable {
    case whole, km20, km10, km5, km2

    /// Window length in metres; nil for the whole course.
    var windowM: Double? {
        switch self {
        case .whole: nil
        case .km20: 20_000
        case .km10: 10_000
        case .km5: 5000
        case .km2: 2000
        }
    }

    /// One step in (+1) or out (−1), stopping at the ends.
    func step(_ direction: Int) -> CourseZoom {
        let all = Self.allCases
        let i = all.firstIndex(of: self)! + direction
        return all[min(max(i, 0), all.count - 1)]
    }

    func label(_ units: Units, lengthM: Double) -> String {
        guard let windowM else {
            let d = units.distance(lengthM)
            return String(format: d < 10 ? "Whole · %.1f %@" : "Whole · %.0f %@", d, units.distanceUnit)
        }
        return String(format: "%.0f %@", units.distance(windowM), units.distanceUnit)
    }
}

/// The whole elevation profile, start to finish, across the full width under the face, with you on it.
/// Zoom in and out with the − / + buttons, a pinch, or the controller (if a button is mapped to it).
struct CourseStrip: View {
    let route: Route
    let atM: Double
    let climbs: [FaceClimb]
    /// False when the road ahead isn't known and the profile is what has been ridden so far.
    let known: Bool
    let ink: Color
    let accent: Color
    let background: Color
    let units: Units
    @Binding var zoom: CourseZoom

    static let height: CGFloat = 92

    var body: some View {
        let window = self.window
        let small = Font.system(size: 11, weight: .semibold).monospacedDigit()
        HStack(spacing: 16) {
            Canvas { ctx, size in draw(&ctx, size, window: window, labelFont: small) }
                .contentShape(Rectangle())
                .gesture(MagnifyGesture().onEnded { value in
                    if value.magnification > 1.15 { withAnimation(.snappy) { zoom = zoom.step(1) } }
                    if value.magnification < 0.87 { withAnimation(.snappy) { zoom = zoom.step(-1) } }
                })
                .accessibilityElement()
                .accessibilityLabel("Course profile")
                .accessibilityValue(String(format: "%.1f of %.1f %@", units.distance(atM), units.distance(route.distanceM), units.distanceUnit))
                .accessibilityAdjustableAction { direction in
                    zoom = zoom.step(direction == .increment ? 1 : -1)
                }
            VStack(spacing: 6) {
                Text(known ? zoom.label(units, lengthM: route.distanceM) : "ridden · " + zoom.label(units, lengthM: route.distanceM))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1).fixedSize()
                HStack(spacing: 8) {
                    button("minus", enabled: zoom != .whole) { zoom = zoom.step(-1) }
                        .accessibilityLabel("Zoom out")
                    button("plus", enabled: zoom != CourseZoom.allCases.last) { zoom = zoom.step(1) }
                        .accessibilityLabel("Zoom in")
                }
            }
            .frame(width: 118)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.12)).frame(height: 1) }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Icon(icon, size: 18)
                .foregroundStyle(ink.opacity(enabled ? 0.9 : 0.25))
                .frame(width: 52, height: 40)
                .background(Capsule().fill(ink.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// The stretch of road shown: all of it, or the zoom window with you a quarter of the way in (more road ahead).
    private var window: ClosedRange<Double> {
        let length = max(route.distanceM, 1)
        guard let w = zoom.windowM, w < length else { return 0...length }
        let start = min(max(atM - w * 0.25, 0), length - w)
        return start...(start + w)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, window: ClosedRange<Double>, labelFont: Font) {
        let span = window.upperBound - window.lowerBound
        guard span > 0, route.elevations.count > 1 else { return }
        let top: CGFloat = 12, bottom: CGFloat = 14
        let plotH = size.height - top - bottom
        // Honest heights: at least 8 m of relief per km shown, so a flat road stays flat.
        let step = max(Route.step, span / Double(max(size.width, 1)) / 1.5)
        var samples: [(m: Double, e: Double)] = []
        var m = window.lowerBound
        while m <= window.upperBound {
            samples.append((m, route.elevation(atDistance: m)))
            m += step
        }
        samples.append((window.upperBound, route.elevation(atDistance: window.upperBound)))
        let lo = samples.map(\.e).min()!, hi = samples.map(\.e).max()!
        let relief = max(hi - lo, max(40, span / 1000 * 8))
        let x = { (m: Double) in CGFloat((m - window.lowerBound) / span) * size.width }
        let y = { (e: Double) in top + plotH - CGFloat((e - lo) / relief) * plotH }

        var outline = Path()
        outline.move(to: CGPoint(x: x(samples[0].m), y: y(samples[0].e)))
        for s in samples.dropFirst() { outline.addLine(to: CGPoint(x: x(s.m), y: y(s.e))) }
        var fill = outline
        fill.addLine(to: CGPoint(x: size.width, y: top + plotH))
        fill.addLine(to: CGPoint(x: 0, y: top + plotH))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(ink.opacity(0.14)))
        // What's behind you, darker.
        let here = x(min(max(atM, window.lowerBound), window.upperBound))
        ctx.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: here, height: size.height)))
            layer.fill(fill, with: .color(ink.opacity(0.3)))
        }
        ctx.stroke(outline, with: .color(ink.opacity(0.6)), lineWidth: 1.5)

        // Climbs in view: their category over the summit.
        for climb in climbs {
            let summit = climb.endKm * 1000
            guard summit >= window.lowerBound, summit <= window.upperBound, !climb.label.isEmpty else { continue }
            let sx = x(summit), sy = y(route.elevation(atDistance: summit))
            ctx.draw(Text(climb.label).font(labelFont).foregroundStyle(ink.opacity(0.8)),
                     at: CGPoint(x: min(max(sx, 10), size.width - 10), y: max(sy - 3, 9)), anchor: .bottom)
        }

        // You.
        if atM >= window.lowerBound, atM <= window.upperBound {
            let py = y(route.elevation(atDistance: atM))
            ctx.fill(Path(CGRect(x: here - 1, y: top - 4, width: 2, height: plotH + 4)), with: .color(accent))
            ctx.fill(Path(ellipseIn: CGRect(x: here - 6, y: py - 6, width: 12, height: 12)), with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: here - 6, y: py - 6, width: 12, height: 12)), with: .color(background), lineWidth: 2)
        }

        // The window's ends.
        let left = String(format: "%.1f", units.distance(window.lowerBound)), right = String(format: "%.1f %@", units.distance(window.upperBound), units.distanceUnit)
        ctx.draw(Text(left).font(labelFont).foregroundStyle(ink.opacity(0.55)), at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
        ctx.draw(Text(right).font(labelFont).foregroundStyle(ink.opacity(0.55)), at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
    }
}

extension Color {
    /// True for light colours (relative luminance above 0.5): the strip picks dark ink on them, light ink otherwise.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5
    }
}
