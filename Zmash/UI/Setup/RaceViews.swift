import SwiftUI
import ZmashKit

// MARK: - Races

/// A stage race at a glance: one bar per stage, as tall as its climbing: rest-grey when flat, terrain blue when hilly,
/// vermilion for the mountain stages.
struct StageBars: View {
    let routes: [Route]

    var body: some View {
        Canvas { ctx, size in
            guard !routes.isEmpty else { return }
            let peak = max(routes.map(\.ascentM).max() ?? 1, 1)
            let w = size.width / CGFloat(routes.count)
            for (i, r) in routes.enumerated() {
                let h = max(3, CGFloat(r.ascentM / peak) * size.height)
                let rect = CGRect(x: CGFloat(i) * w, y: size.height - h, width: max(w - 2, 1), height: h)
                let tint = r.ascentM > 3000 ? Design.Accent.vermilion : r.ascentM > 1500 ? Design.Zone.z2 : Design.Palette.blockRest
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, w / 3)), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Route part

/// Which part of a route to ride (D149): all of it, or a length of it ending at the finish, as races are decided in the
/// finale. The part lives in the route id ("…#fromM-toM"), so history and the ghost follow it.
enum RoutePart {
    static let lengths: [(Double?, String)] = [(nil, "Full"), (1800, "30′"), (2700, "45′"), (3600, "1 h"), (5400, "1 h 30"), (7200, "2 h")]

    /// The lengths this route can be cut to (a short road only rides whole).
    @MainActor static func options(_ id: String) -> [(Double?, String)] {
        guard let route = RouteStore.route(id: RouteStore.split(id).base) else { return [(nil, "Full")] }
        let seconds = RouteStats.of(route).estimatedSeconds
        return lengths.filter { $0.0 == nil || $0.0! < seconds * 0.9 }
    }

    /// The route cut to `length` seconds from the finish, or whole.
    @MainActor static func id(_ id: String, length: Double?) -> String {
        let base = RouteStore.split(id).base
        guard let length, let route = RouteStore.route(id: base) else { return base }
        let stats = RouteStats.of(route)
        let from = stats.timing.latestStart(for: length)
        return RouteStore.segmentID(base, fromM: from, toM: max(from + Route.step, stats.timing.end(after: length, from: from)))
    }

    /// The length a route id is cut to, as the nearest of the options (nil: whole).
    @MainActor static func length(_ id: String) -> Double? {
        let (base, segment) = RouteStore.split(id)
        guard let segment, let route = RouteStore.route(id: base) else { return nil }
        let timing = RouteStats.of(route).timing
        let index = { (m: Double) in min(max(Int((m / Route.step).rounded()), 0), timing.times.count - 1) }
        let seconds = timing.times[index(segment.upperBound)] - timing.times[index(segment.lowerBound)]
        return options(id).compactMap(\.0).min { abs($0 - seconds) < abs($1 - seconds) }
    }

    /// A route to ride from a list: a long race stage starts on its last hour; everything else whole.
    @MainActor static func chosenID(_ base: String) -> String {
        guard base.hasPrefix("race/"), let route = RouteStore.route(id: base),
              RouteStats.of(route).estimatedSeconds > 4500 else { return base }
        return id(base, length: 3600)
    }
}

// MARK: - Profile

/// An elevation profile in real metres, with its climbs picked out, distance marks, and a segment window if there
/// is one. Used for race stages and for the home screen's generated course.
struct ElevationProfile: View {
    let route: Route
    let climbs: [Climb]
    var window: ClosedRange<Double>? = nil
    let units: Units
    /// Called with the drag's horizontal movement as a fraction of the profile's width.
    var drag: ((Double) -> Void)? = nil
    /// Called when the finger lifts.
    var dragEnded: (() -> Void)? = nil
    /// The smallest height range drawn, so gentle roads look gentle instead of being stretched to fill the card.
    var minRelief: Double = 60

    @State private var lastX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(in: &ctx, size: size)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard let drag else { return }
                    let dx = v.location.x - (lastX ?? v.location.x)
                    lastX = v.location.x
                    drag(Double(dx / max(geo.size.width, 1)))
                }
                .onEnded { _ in
                    lastX = nil
                    dragEnded?()
                },
                including: drag == nil ? .subviews : .all)
        }
        .accessibilityElement()
        .accessibilityLabel("Elevation profile")
        .accessibilityValue(window.map { String(format: "Segment from km %.0f to %.0f", $0.lowerBound / 1000, $0.upperBound / 1000) } ?? "")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let e = route.elevations
        guard e.count > 1 else { return }
        let top: CGFloat = 26, bottom: CGFloat = 22
        let plotH = size.height - top - bottom
        let lo = route.minElevationM, hi = route.maxElevationM
        let span = max(hi - lo, minRelief)
        let x = { (m: Double) in CGFloat(m / max(route.distanceM, 1)) * size.width }
        let y = { (v: Double) in top + plotH - CGFloat((v - lo) / span) * plotH }
        let point = { (i: Int) in CGPoint(x: x(Double(i) * Route.step), y: y(e[i])) }

        var outline = Path()
        outline.move(to: point(0))
        for i in 1..<e.count { outline.addLine(to: point(i)) }
        var fill = outline
        fill.addLine(to: CGPoint(x: size.width, y: top + plotH))
        fill.addLine(to: CGPoint(x: 0, y: top + plotH))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(Design.Palette.terrainFill))

        // Climbs: filled darker, with their category above the summit.
        for climb in climbs {
            let a = Int(climb.startM / Route.step), b = min(Int((climb.startM + climb.lengthM) / Route.step), e.count - 1)
            guard b > a else { continue }
            var p = Path()
            p.move(to: CGPoint(x: point(a).x, y: top + plotH))
            for i in a...b { p.addLine(to: point(i)) }
            p.addLine(to: CGPoint(x: point(b).x, y: top + plotH))
            p.closeSubpath()
            ctx.fill(p, with: .color(Design.Palette.terrain.opacity(0.3)))
            if let category = climb.category {
                let label = ctx.resolve(Text(category == .hc ? "HC" : category.rawValue)
                    .font(Design.Font.mono(11, weight: 700)).foregroundStyle(Design.Palette.fg1))
                ctx.draw(label, at: CGPoint(x: min(max(point(b).x, 10), size.width - 10), y: point(b).y - 10), anchor: .bottom)
            }
        }
        ctx.stroke(outline, with: .color(Design.Palette.fg1), lineWidth: 1.5)

        // Distance marks.
        let unitM = units == .metric ? 1000.0 : 1609.344
        let total = route.distanceM / unitM
        let step: Double = total > 150 ? 50 : total > 60 ? 20 : total > 25 ? 10 : 5
        var mark = step
        while mark < total {
            let px = x(mark * unitM)
            let label = ctx.resolve(Text("\(Int(mark))").font(Design.Font.mono(10)).foregroundStyle(Design.Palette.fg3))
            // A mark at the very end sits inside the edge rather than half off it.
            let half = label.measure(in: size).width / 2
            ctx.draw(label, at: CGPoint(x: min(max(px, half), size.width - half), y: size.height - 2), anchor: .bottom)
            ctx.fill(Path(CGRect(x: px - 0.5, y: top + plotH, width: 1, height: 4)), with: .color(Design.Palette.secondary))
            mark += step
        }

        // The segment: everything outside it dims, and its edges are marked.
        if let window {
            let a = x(window.lowerBound), b = x(window.upperBound)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: a, height: size.height - bottom)), with: .color(Design.Palette.background.opacity(0.6)))
            ctx.fill(Path(CGRect(x: b, y: 0, width: size.width - b, height: size.height - bottom)), with: .color(Design.Palette.background.opacity(0.6)))
            for edge in [a, b] {
                ctx.fill(Path(CGRect(x: edge - 1, y: 0, width: 2, height: size.height - bottom)), with: .color(Design.Accent.vermilion))
            }
            ctx.fill(Path(roundedRect: CGRect(x: a, y: 0, width: b - a, height: 4), cornerRadius: 2), with: .color(Design.Accent.vermilion))
        }
    }
}
