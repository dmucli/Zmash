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

/// What the band says about the ride's plan, beside the profile: the route or the workout, and the links.
/// Built from the engine; empty in the gallery.
struct BandPlan {
    struct RoutePart {
        var name: String
        var toGoM: Double?
        /// Seconds ahead (+) or behind (−) your best on this route.
        var ghost: Double?
        var toSummitM: Double?
    }

    struct WorkoutPart {
        enum Hint: String { case onTarget = "on target", easeOff = "ease off", push }
        var workout: Workout
        var step: String
        var targetW: Int?
        var hint: Hint?
        var stepLeft: Double?
        var next: String
        var intensity: Int?
    }

    var route: RoutePart?
    var workout: WorkoutPart?
    /// Controller and trainer, for the two dots.
    var links: [LinkState] = []

    var isEmpty: Bool { route == nil && workout == nil }
}

extension BandPlan {
    @MainActor
    init(engine: SessionEngine) {
        if let r = engine.route {
            route = RoutePart(name: r.name, toGoM: engine.routeRemainingM, ghost: engine.ghostDelta, toSummitM: engine.toSummitM)
        }
        if let w = engine.workout {
            let pos = engine.workoutPosition
            var hint: WorkoutPart.Hint?
            if let target = engine.targetW, engine.clockStarted {
                let off = engine.telemetry.power3 - Double(target)
                let inRange = abs(off) <= max(8, Double(target) * 0.05)
                // With ERG the trainer holds the target: only say something when it's off.
                if !engine.ergActive || !inRange { hint = inRange ? .onTarget : off > 0 ? .easeOff : .push }
            }
            let next: String = if let n = pos?.next {
                "Next " + (n.label.isEmpty ? "" : n.label + " ") + (engine.watts(forFraction: n.fraction(at: 0)).map { "\($0) W" } ?? "free")
            } else {
                pos == nil ? "Workout complete" : "Last step"
            }
            workout = WorkoutPart(workout: w, step: pos?.step.label.isEmpty == false ? pos!.step.label : w.name,
                                  targetW: engine.targetW, hint: pos == nil ? nil : hint,
                                  stepLeft: pos?.remainingInStep, next: next,
                                  intensity: engine.ergActive && engine.intensity != 1 ? Int((engine.intensity * 100).rounded()) : nil)
        }
    }
}

/// The band along the bottom of the ride screen: the ride's plan (route or workout) on the left, the whole course's
/// elevation profile (or the workout's blocks) across the middle with you on it, zoom and connection dots on the right.
/// Short-lived event messages (a kilometre, a summit, a best) appear over it. Nothing else is drawn over a face.
struct RideBand: View {
    let data: FaceData
    /// False with the profile turned off in Settings, or in Split View: the plan still shows, the profile doesn't.
    let showProfile: Bool
    let ink: Color
    let accent: Color
    let background: Color
    @Binding var zoom: CourseZoom
    /// A short screen (an iPhone on its side): a slimmer band, so the face keeps its height.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Tall enough for the profile to read as a profile (D107).
    static func height(dense: Bool) -> CGFloat { dense ? 76 : 132 }
    private var dense: Bool { verticalSizeClass == .compact }

    /// Whether there's anything to show: a plan, or a profile to draw.
    static func shows(_ data: FaceData, profile: Bool) -> Bool {
        !data.plan.isEmpty || (profile && data.road != nil)
    }

    private var units: Units { data.units }
    private var drawsProfile: Bool { showProfile && data.plan.workout == nil && data.road != nil }

    var body: some View {
        HStack(spacing: 20) {
            if let route = data.plan.route {
                RoutePanel(route: route, altitudeM: data.altitudeM, units: units, ink: ink, dense: dense)
            } else if let workout = data.plan.workout {
                WorkoutPanel(workout: workout, ink: ink, dense: dense)
            }
            ZStack(alignment: .top) {
                if let workout = data.plan.workout {
                    WorkoutStrip(workout: workout.workout, elapsed: data.elapsed, color: ink)
                        .padding(.vertical, 6)
                        .accessibilityLabel("Workout")
                } else if drawsProfile, let road = data.road {
                    profile(road)
                } else {
                    Color.clear
                }
                BandEvent(data: data, ink: ink, accent: accent, background: background)
            }
            if drawsProfile, let road = data.road {
                zoomControls(lengthM: road.distanceM)
            }
            if !data.plan.links.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(zip(["Controller", "Trainer"], data.plan.links)), id: \.0) { name, link in
                        Circle().fill(link.isReady ? ink.opacity(0.45) : link.dotColor).frame(width: 8, height: 8)
                            .accessibilityLabel("\(name) \(link.label)")
                    }
                }
            }
        }
        .padding(.horizontal, dense ? 16 : 24)
        .padding(.vertical, dense ? 6 : 12)
        .frame(height: Self.height(dense: dense))
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.12)).frame(height: 1) }
    }

    private func profile(_ road: Route) -> some View {
        let window = self.window(road)
        let small = Font.system(size: 11, weight: .semibold).monospacedDigit()
        let climbs = data.roadKnown ? data.climbs : []
        return Canvas { ctx, size in draw(&ctx, size, road: road, climbs: climbs, window: window, labelFont: small) }
            .contentShape(Rectangle())
            .gesture(MagnifyGesture().onEnded { value in
                if value.magnification > 1.15 { withAnimation(.snappy) { zoom = zoom.step(1) } }
                if value.magnification < 0.87 { withAnimation(.snappy) { zoom = zoom.step(-1) } }
            })
            .accessibilityElement()
            .accessibilityLabel("Course profile")
            .accessibilityValue(String(format: "%.1f of %.1f %@", units.distance(data.roadAtM), units.distance(road.distanceM), units.distanceUnit))
            .accessibilityAdjustableAction { direction in
                zoom = zoom.step(direction == .increment ? 1 : -1)
            }
    }

    private func zoomControls(lengthM: Double) -> some View {
        VStack(spacing: 6) {
            if !dense {
                Text(data.roadKnown ? zoom.label(units, lengthM: lengthM) : "ridden · " + zoom.label(units, lengthM: lengthM))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1).fixedSize()
            }
            HStack(spacing: 8) {
                button("minus", enabled: zoom != .whole) { zoom = zoom.step(-1) }
                    .accessibilityLabel("Zoom out")
                button("plus", enabled: zoom != CourseZoom.allCases.last) { zoom = zoom.step(1) }
                    .accessibilityLabel("Zoom in")
            }
        }
        .frame(width: dense ? 104 : 118)
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Icon(icon, size: 18)
                .foregroundStyle(ink.opacity(enabled ? 0.9 : 0.25))
                .frame(width: dense ? 48 : 52, height: dense ? 44 : 40)
                .background(Capsule().fill(ink.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// The stretch of road shown: all of it, or the zoom window with you a quarter of the way in (more road ahead).
    private func window(_ road: Route) -> ClosedRange<Double> {
        let length = max(road.distanceM, 1)
        guard let w = zoom.windowM, w < length else { return 0...length }
        let start = min(max(data.roadAtM - w * 0.25, 0), length - w)
        return start...(start + w)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, road route: Route, climbs: [FaceClimb],
                      window: ClosedRange<Double>, labelFont: Font) {
        let atM = data.roadAtM
        let span = window.upperBound - window.lowerBound
        guard span > 0, route.elevations.count > 1 else { return }
        let top: CGFloat = 16, bottom: CGFloat = 14
        let plotH = size.height - top - bottom
        let step = max(Route.step, span / Double(max(size.width, 1)) / 1.5)
        var samples: [(m: Double, e: Double)] = []
        var m = window.lowerBound
        while m <= window.upperBound {
            samples.append((m, route.elevation(atDistance: m)))
            m += step
        }
        samples.append((window.upperBound, route.elevation(atDistance: window.upperBound)))
        let lo = samples.map(\.e).min()!, hi = samples.map(\.e).max()!
        // The shape fills the height (at least 12 m of range, so a truly flat road doesn't turn into noise);
        // the lowest and highest altitudes are written on the left so the scale can be read (D107).
        let relief = max(hi - lo, 12)
        // A gutter on the left for the altitude labels.
        let x0: CGFloat = 40, plotW = size.width - x0
        let x = { (m: Double) in x0 + CGFloat((m - window.lowerBound) / span) * plotW }
        let y = { (e: Double) in top + plotH - CGFloat((e - lo) / relief) * plotH }

        var outline = Path()
        outline.move(to: CGPoint(x: x(samples[0].m), y: y(samples[0].e)))
        for s in samples.dropFirst() { outline.addLine(to: CGPoint(x: x(s.m), y: y(s.e))) }
        var fill = outline
        fill.addLine(to: CGPoint(x: size.width, y: top + plotH))
        fill.addLine(to: CGPoint(x: x0, y: top + plotH))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(ink.opacity(0.2)))
        // What's behind you, darker.
        let here = x(min(max(atM, window.lowerBound), window.upperBound))
        ctx.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: x0, y: 0, width: max(here - x0, 0), height: size.height)))
            layer.fill(fill, with: .color(ink.opacity(0.3)))
        }
        ctx.stroke(outline, with: .color(ink.opacity(0.6)), lineWidth: 1.5)

        // Climbs in view: their category over the summit.
        for climb in climbs {
            let summit = climb.endKm * 1000
            guard summit >= window.lowerBound, summit <= window.upperBound, !climb.label.isEmpty else { continue }
            let sx = x(summit), sy = y(route.elevation(atDistance: summit))
            ctx.draw(Text(climb.label).font(labelFont).foregroundStyle(ink.opacity(0.8)),
                     at: CGPoint(x: min(max(sx, x0 + 10), size.width - 10), y: max(sy - 3, 13)), anchor: .bottom)
        }

        // You.
        if atM >= window.lowerBound, atM <= window.upperBound {
            let py = y(route.elevation(atDistance: atM))
            ctx.fill(Path(CGRect(x: here - 1, y: top - 4, width: 2, height: plotH + 4)), with: .color(accent))
            ctx.fill(Path(ellipseIn: CGRect(x: here - 6, y: py - 6, width: 12, height: 12)), with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: here - 6, y: py - 6, width: 12, height: 12)), with: .color(background), lineWidth: 2)
        }

        // Its altitude range.
        let up = units.elevation(hi), down = units.elevation(lo)
        ctx.draw(Text(String(format: "%.0f %@", up, units.elevationUnit)).font(labelFont).foregroundStyle(ink.opacity(0.55)),
                 at: CGPoint(x: 0, y: top - 2), anchor: .topLeading)
        ctx.draw(Text(String(format: "%.0f", down)).font(labelFont).foregroundStyle(ink.opacity(0.55)),
                 at: CGPoint(x: 0, y: top + plotH - 2), anchor: .bottomLeading)

        // The window's ends.
        let left = String(format: "%.1f", units.distance(window.lowerBound)), right = String(format: "%.1f %@", units.distance(window.upperBound), units.distanceUnit)
        ctx.draw(Text(left).font(labelFont).foregroundStyle(ink.opacity(0.55)), at: CGPoint(x: x0, y: size.height), anchor: .bottomLeading)
        ctx.draw(Text(right).font(labelFont).foregroundStyle(ink.opacity(0.55)), at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
    }
}

/// The route beside the profile: its name, distance to go, the gap to your best, and the summit.
private struct RoutePanel: View {
    let route: BandPlan.RoutePart
    let altitudeM: Double?
    let units: Units
    let ink: Color
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 1 : 3) {
            Text(route.name).textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold)).tracking(1.2)
                .foregroundStyle(ink.opacity(0.6))
                .lineLimit(1).truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let left = route.toGoM {
                    Text(String(format: "%.1f", units.distance(left)))
                        .font(.system(size: dense ? 20 : 28, weight: .semibold).monospacedDigit())
                    Text(units.distanceUnit + " to go").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                }
                Spacer(minLength: 8)
                if let ghost = route.ghost {
                    // Words, not only colour: ahead or behind your best.
                    Text(TimeFormat.clock(Int(abs(ghost).rounded())) + (ghost >= 0 ? " ahead" : " behind"))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                }
            }
            .foregroundStyle(ink)
            if !dense {
                Text(detail).font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.6)).lineLimit(1)
            }
        }
        .frame(width: dense ? 200 : 280, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let altitudeM { parts.append("\(Int(units.elevation(altitudeM).rounded())) \(units.elevationUnit)") }
        if let summit = route.toSummitM {
            parts.append("summit in " + String(format: "%.1f %@", units.distance(summit), units.distanceUnit))
        }
        return parts.joined(separator: " · ")
    }
}

/// The workout beside its blocks: the step, its target and how you're doing, time left in it, and what's next.
private struct WorkoutPanel: View {
    let workout: BandPlan.WorkoutPart
    let ink: Color
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 1 : 3) {
            Text(workout.step).textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold)).tracking(1.2)
                .foregroundStyle(ink.opacity(0.6))
                .lineLimit(1).truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let target = workout.targetW {
                    Text("\(target)").font(.system(size: dense ? 20 : 28, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("W").font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                    if let hint = workout.hint {
                        Text(hint.rawValue).textCase(.uppercase)
                            .font(.system(size: 11, weight: .bold)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(ink.opacity(hint == .onTarget ? 0.3 : 0.8), lineWidth: 1))
                    }
                } else {
                    Text("Free").font(.system(size: 26, weight: .medium))
                }
                Spacer(minLength: 8)
                if let left = workout.stepLeft {
                    Text(TimeFormat.clock(Int(left.rounded(.up))))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .foregroundStyle(ink)
            if !dense {
                Text(workout.intensity.map { workout.next + " · intensity \($0) %" } ?? workout.next)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.6)).lineLimit(1)
            }
        }
        .frame(width: dense ? 200 : 280, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A kilometre, a summit or a best: a short-lived label over the band's profile.
private struct BandEvent: View {
    let data: FaceData
    let ink: Color
    let accent: Color
    let background: Color

    var body: some View {
        if let e = data.event, !e.label.isEmpty, data.eventAge < 1, data.state == .riding {
            label(e.label, border: accent, age: data.eventAge)
        } else if let coach = data.coach, data.coachAge < 1, data.state == .riding || data.state == .done {
            // Also once done: a climb ridden on its own ends at its summit, where its time is said.
            label(coach, border: ink.opacity(0.35), age: data.coachAge)
        }
    }

    private func label(_ text: String, border: Color, age: Double) -> some View {
            Text(text).textCase(.uppercase)
                .font(.system(size: 13, weight: .bold)).tracking(1.6)
                .foregroundStyle(ink)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(background))
                .overlay(Capsule().stroke(border, lineWidth: 1.5))
                .opacity(1 - pow(age, 3))
                .lineLimit(1).minimumScaleFactor(0.7)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.updatesFrequently)
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
