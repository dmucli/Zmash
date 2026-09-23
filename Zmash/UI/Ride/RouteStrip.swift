import SwiftUI
import ZmashKit

/// The whole route as a silhouette, filled up to where the rider is.
struct RouteStrip: View {
    let route: Route
    var distanceM: Double = 0
    var color: Color = .white
    /// A shared elevation scale (e.g. every stage of a race), so a flat stage looks flat next to a mountain one.
    var range: ClosedRange<Double>?

    var body: some View {
        Canvas { ctx, size in
            let e = route.elevations
            guard e.count > 1 else { return }
            let lo = range?.lowerBound ?? route.minElevationM, hi = range?.upperBound ?? route.maxElevationM
            let span = max(hi - lo, 20)
            let x = { (i: Int) in size.width * Double(i) / Double(e.count - 1) }
            let y = { (v: Double) in size.height - (v - lo) / span * size.height * 0.88 - size.height * 0.06 }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in e.enumerated() { path.addLine(to: CGPoint(x: x(i), y: y(v))) }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.3)))
            let cut = min(1, max(0, distanceM / max(route.distanceM, 1))) * size.width
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: cut, height: size.height)))
                layer.fill(path, with: .color(color.opacity(0.85)))
            }
            if distanceM > 0 {
                ctx.fill(Path(CGRect(x: cut - 1, y: -2, width: 2, height: size.height + 2)), with: .color(color))
            }
        }
    }
}
