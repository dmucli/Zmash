import SwiftUI
import ZmashKit

/// The route layer, drawn over any face like the workout layer: where you are on the climb,
/// how far and how much is left, the summit, and how you're doing against your last attempt.
struct RouteLayer: View {
    let engine: SessionEngine
    let units: Units
    var compact = false

    var body: some View {
        if let route = engine.route {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(route.name.uppercased())
                        .font(FaceFont.font(.archivo, 14, weight: 500)).tracking(14 * 0.16)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                    Spacer(minLength: 8)
                    if let ghost = engine.ghostDelta {
                        Text((ghost >= 0 ? "+" : "−") + TimeFormat.clock(Int(abs(ghost).rounded())))
                            .font(FaceFont.font(.archivo, 20, weight: 500)).monospacedDigit()
                            .foregroundStyle(ghost >= 0 ? Color(hex: 0x8FE3A8) : Color(hex: 0xFFB38A))
                            .accessibilityLabel(ghost >= 0 ? "Ahead of your best" : "Behind your best")
                    }
                    if let left = engine.routeRemainingM {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.1f", units.distance(left)))
                                .font(FaceFont.font(.archivo, 30, weight: 600)).monospacedDigit()
                                .foregroundStyle(.white)
                            Text("to go").font(FaceFont.font(.archivo, 14, weight: 500))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                RouteStrip(route: route, distanceM: engine.distanceM)
                    .frame(height: compact ? 24 : 34)
                HStack(spacing: 14) {
                    if let altitude = engine.altitudeM {
                        Text("\(Int(units.elevation(altitude).rounded())) \(units.elevationUnit)")
                    }
                    if let summit = engine.toSummitM {
                        Text("summit in " + String(format: "%.1f", units.distance(summit)) + " " + units.distanceUnit)
                    }
                    Spacer()
                    if let name = engine.ghostName {
                        Text("best \(name)")
                    } else if route.approximate {
                        Text("approximate profile")
                    }
                }
                .font(FaceFont.font(.archivo, 13, weight: 450)).tracking(13 * 0.08)
                .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: compact ? 320 : 480)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0x0A0A0C, opacity: 0.78))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, compact ? 12 : 22)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }
}

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
