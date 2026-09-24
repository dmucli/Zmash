import SwiftUI
import ZmashKit

// The home screen's previews of the ride: the course, manual gradient, drawn course, workout and route.

/// A number and what it is, for the facts under a preview.
struct Fact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // One line each: a narrow card shrinks the figure a little rather than breaking it up.
            Text(label).monoLabel().foregroundStyle(Design.Palette.fg3)
                .lineLimit(1)
            Text(value).font(Design.Font.bib(30)).foregroundStyle(Design.Palette.fg1)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PreviewTitle: View {
    let title: String
    var subtitle: String = ""
    /// 1–5, shown on the right of the title; nil when it can't be told (an open-ended ride).
    var difficulty: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).textStyle(.h2, size: 24).foregroundStyle(Design.Palette.fg1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let difficulty {
                Spacer(minLength: 8)
                DifficultyGauge(level: difficulty)
            }
        }
    }
}

/// Difficulty 1–5: five short bars, filled up to the level in the grade colours, with the word under them.
struct DifficultyGauge: View {
    let level: Int
    var compact = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Capsule()
                        .fill(i <= level ? Design.Accent.vermilion : Design.Palette.fgGhost)
                        .frame(width: compact ? 10 : 14, height: compact ? 4 : 5)
                }
            }
            if !compact {
                Text(Difficulty.label(level)).monoLabel().foregroundStyle(Design.Palette.fg3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Difficulty \(level) of 5, \(Difficulty.label(level).lowercased())")
    }
}

/// Auto terrain: the generated course as the real road you'll ride — metres of climbing and kilometres at your pace,
/// on an honest scale (a flat course looks flat) — plus a way to roll another.
struct CoursePreview: View {
    let plan: SessionPlan
    let reroll: () -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let route = course
        let stats = route.map { RouteStats.of($0) }
        let units = prefs.units
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PreviewTitle(title: "Your course", subtitle: subtitle(stats),
                             difficulty: plan.plannedMinutes == nil ? nil : route.flatMap { r in stats.map { Difficulty.route(r, estimatedSeconds: $0.estimatedSeconds) } })
                Spacer()
                PillButton(title: "New course", icon: "dices", compact: true, action: reroll)
            }
            if let route, let stats {
                ElevationProfile(route: route, climbs: stats.climbs, units: units, minRelief: honestRelief)
                    .frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: route.elevations)
                HStack(spacing: 28) {
                    Fact(value: plan.plannedMinutes.map { "\($0) min" } ?? "10 min", label: plan.plannedMinutes == nil ? "first block" : "length")
                    Fact(value: String(format: "≈ %.1f", units.distance(route.distanceM)), label: units.distanceUnit)
                    Fact(value: String(format: "%.0f", units.elevation(route.ascentM)), label: units.elevationUnit + " climbing")
                    Fact(value: String(format: "%.1f %%", route.steepestKmGrade), label: "steepest km")
                    Fact(value: "\(stats.climbs.count)", label: stats.climbs.count == 1 ? "climb" : "climbs")
                }
            }
        }
    }

    @MainActor private static var cache: [String: Route] = [:]

    /// The height scale: 40 % of what your pace could climb in this time (≈ P ÷ m·g per second). A mountain course
    /// fills the card at any length, and a flat one stays a gentle line, instead of every course being stretched to fit.
    private var honestRelief: Double {
        let seconds = plan.plannedSeconds ?? 600
        let climbRate = Double(prefs.ftp) * RouteStats.paceShare / (prefs.rider.massKg * RiderModel.g)
        return max(40, 0.4 * climbRate * seconds)
    }

    /// The generated course ridden at the estimate pace (70 % FTP), cached per plan and pace.
    private var course: Route? {
        let pace = Double(prefs.ftp) * RouteStats.paceShare
        let id = "course|\(plan.seed)|\(plan.terrainType.rawValue)|\(plan.effort.rawValue)|\(plan.plannedMinutes ?? 0)|\(Int(pace))|\(prefs.riderKg)|\(prefs.bikeKg)"
        if let hit = Self.cache[id] { return hit }
        guard let route = plan.profile()?.route(rider: prefs.rider, powerW: pace, id: id, name: "Your course") else { return nil }
        Self.cache[id] = route
        return route
    }

    private func subtitle(_ stats: RouteStats?) -> String {
        let what = "\(plan.terrainType.rawValue.capitalized) · \(plan.effort.rawValue.capitalized)"
        let pace = stats.map { " · ridden at \($0.paceW) W" } ?? ""
        return plan.plannedMinutes == nil ? "\(what) · the first ten minutes; more is made as you ride" : what + pace
    }
}

/// Manual gradient: nothing to preview, so say how it works.
struct ManualPreview: View {
    let gearCount: Int
    /// nil for an open-ended ride.
    var minutes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewTitle(title: "Manual gradient",
                         subtitle: "You set the gradient as you ride, with the D-pad or the on-screen controls.",
                         difficulty: minutes.map { Difficulty.ride(minutes: Double($0)) })
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("where you start").monoLabel().foregroundStyle(Design.Palette.fg3)
                Text("0.0 %").font(Design.Font.bib(96)).foregroundStyle(Design.Palette.fg1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                Fact(value: String(format: "±%.1f %%", RideControls.gradeStep), label: "per press")
                Fact(value: String(format: "−%.0f to +%.0f %%", abs(RideControls.gradeRange.lowerBound), RideControls.gradeRange.upperBound),
                     label: "range")
                Fact(value: "\(gearCount)", label: "gears")
            }
        }
    }
}

/// A workout: its shape, and what it will cost.
struct WorkoutPreview: View {
    let workout: Workout
    let ftp: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewTitle(title: workout.name, subtitle: workout.summary,
                         difficulty: workout.isRampTest ? 4 : Difficulty.workout(tss: estimatedLoad.tss))
            WorkoutStrip(workout: workout.isRampTest ? rampPreview : workout)
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
            HStack(spacing: 28) {
                if workout.isRampTest {
                    Fact(value: "~20 min", label: "typical")
                    Fact(value: "\(ftp / 2) W", label: "first step")
                    Fact(value: "+6 %", label: "each minute")
                } else {
                    let load = estimatedLoad
                    Fact(value: TimeFormat.clock(workout.duration), label: "length")
                    Fact(value: "\(Int(load.tss.rounded()))", label: "tss")
                    Fact(value: String(format: "%.2f", load.intensityFactor), label: "intensity")
                }
                Fact(value: "\(ftp) W", label: "ftp")
            }
        }
    }

    /// The load the workout asks for if every target is held (free steps counted at 60 % FTP).
    private var estimatedLoad: Training.Load { workout.estimatedLoad(ftp: Double(ftp)) }

    /// The ramp test is open-ended; preview the part most riders reach.
    private var rampPreview: Workout {
        var p = workout
        p.steps = Array(workout.steps.prefix(16))
        return p
    }
}

/// Draw: drag a finger across the card to shape the course. The line is the hill's silhouette over the
/// whole ride; Effort sets how steep its steepest climb gets. Dragging again repaints only what you cross.
struct DrawCoursePreview: View {
    @Binding var heights: [Double]
    let effort: Effort
    let minutes: Int?

    /// The stroke in progress, committed when the finger lifts (one write to the plan per stroke).
    @State private var live: [Double]?
    @State private var last: (index: Int, value: Double)?

    var body: some View {
        let shown = live ?? heights
        let grades = DrawnCourse.grades(shown, effort: effort)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PreviewTitle(title: "Draw your course",
                             subtitle: "Drag across the card to shape the hill. Effort sets how steep it gets.",
                             difficulty: Difficulty.ride(minutes: Double(minutes ?? 30), steepestPercent: grades.max() ?? 0))
                Spacer()
                PillButton(title: "Clear", compact: true) {
                    withAnimation(Design.Motion.base) { heights = DrawnCourse.blank }
                }
            }
            GeometryReader { geo in
                DrawnSilhouette(heights: shown, drawing: live != nil)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { paint(at: $0.location, in: geo.size) }
                            .onEnded { _ in
                                if let live { heights = live }
                                live = nil
                                last = nil
                            })
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
            .accessibilityLabel("Course drawing")
            .accessibilityHint("Drag across to shape the course")
            HStack(spacing: 28) {
                Fact(value: minutes.map { "\($0) min" } ?? "30 min", label: minutes == nil ? "per lap" : "length")
                Fact(value: String(format: "%+.1f %%", grades.max() ?? 0), label: "steepest")
                Fact(value: String(format: "−%.1f %%", abs(min(grades.min() ?? 0, 0))), label: "fastest descent")
            }
        }
    }

    /// Sets the heights under the finger, filling any points a fast stroke skipped.
    private func paint(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        var h = live ?? DrawnCourse.resample(heights, count: DrawnCourse.points)
        let n = h.count
        let index = min(max(Int((point.x / size.width * Double(n - 1)).rounded()), 0), n - 1)
        let value = Double(min(max(1 - point.y / size.height, 0.02), 0.98))
        if let last, last.index != index {
            let step = index > last.index ? 1 : -1
            for i in stride(from: last.index, through: index, by: step) {
                let t = Double(i - last.index) / Double(index - last.index)
                h[i] = last.value + (value - last.value) * t
            }
        } else {
            h[index] = value
        }
        live = h
        last = (index, value)
    }
}

/// The drawing as a filled hill with its outline, over a quiet baseline grid.
struct DrawnSilhouette: View {
    let heights: [Double]
    let drawing: Bool

    var body: some View {
        Canvas { ctx, size in
            for f in [0.25, 0.5, 0.75] {
                let y = size.height * f
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(Design.Palette.border), style: StrokeStyle(lineWidth: 1, dash: [20, 12]))
            }
            guard heights.count > 1 else { return }
            let point = { (i: Int) in
                CGPoint(x: size.width * Double(i) / Double(heights.count - 1), y: size.height * (1 - heights[i]))
            }
            var outline = Path()
            outline.move(to: point(0))
            for i in 1..<heights.count { outline.addLine(to: point(i)) }
            var fill = outline
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Design.Palette.terrainFill))
            ctx.stroke(outline, with: .color(drawing ? Design.Accent.vermilion : Design.Palette.fg1),
                       style: StrokeStyle(lineWidth: drawing ? 3 : 2, lineCap: .round, lineJoin: .round))
        }
    }
}
