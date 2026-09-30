import SwiftUI
import ZmashKit

/// A route's elevation in the system's motif: a 1.5-pt line over a terrain-blue fill, the ridden part vermilion,
/// and the rider a bone dot with a tarmac halo.
struct RouteStrip: View {
    let route: Route
    var distanceM: Double = 0
    /// The line (ink on the page, bone on tarmac or a hero card).
    var color: Color = Design.Palette.fg1
    /// A shared elevation scale (e.g. every stage of a race), so a flat stage looks flat next to a mountain one.
    var range: ClosedRange<Double>?
    var fill: Color = Design.Palette.terrainFill

    var body: some View {
        Canvas { ctx, size in
            let e = route.elevations
            guard e.count > 1 else { return }
            let lo = range?.lowerBound ?? route.minElevationM, hi = range?.upperBound ?? route.maxElevationM
            let span = max(hi - lo, 20)
            let x = { (i: Int) in size.width * Double(i) / Double(e.count - 1) }
            let y = { (v: Double) in size.height - (v - lo) / span * size.height * 0.88 - size.height * 0.06 }
            var line = Path()
            for (i, v) in e.enumerated() {
                let p = CGPoint(x: x(i), y: y(v))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(fill))
            let cut = min(1, max(0, distanceM / max(route.distanceM, 1))) * size.width
            if distanceM > 0 {
                ctx.drawLayer { layer in
                    layer.clip(to: Path(CGRect(x: 0, y: 0, width: cut, height: size.height)))
                    layer.fill(area, with: .color(Design.Accent.vermilion.opacity(0.55)))
                }
            }
            ctx.stroke(line, with: .color(color), lineWidth: 1.5)
            if distanceM > 0 {
                let i = min(Int((distanceM / max(route.distanceM, 1)) * Double(e.count - 1)), e.count - 1)
                let c = CGPoint(x: cut, y: y(e[i]))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)), with: .color(Design.Tarmac.t900))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(Design.Tarmac.bone))
            }
        }
    }
}
