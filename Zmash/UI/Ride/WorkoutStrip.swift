import SwiftUI
import ZmashKit

/// A workout as blocks coloured by power zone (stone → blue → vermilion), 2 pt apart with rounded tops; gradient steps
/// as slopes, like a road (D152). Once riding, what's ahead dims and a line marks where you are.
struct WorkoutStrip: View {
    let workout: Workout
    var elapsed: Double = 0
    /// The position line (ink on the page, bone on tarmac).
    var color: Color = Design.Palette.fg1

    var body: some View {
        Canvas { ctx, size in
            let total = Double(max(workout.duration, 1))
            // Scale so the hardest step (or 1.2 × FTP) fills the height.
            let peak = max(1.2, workout.steps.map { s in
                switch s.target {
                case .steady(let f): f
                case .ramp(let a, let b): max(a, b)
                case .free: 0.6
                }
            }.max() ?? 1)
            let cut = min(1, elapsed / total) * size.width
            let gap: CGFloat = workout.steps.count > 60 ? 1 : 2
            var x = 0.0
            for step in workout.steps {
                let w = Double(step.seconds) / total * size.width
                let (a, b): (Double, Double) = switch step.target {
                case .steady(let f): (f, f)
                case .ramp(let f, let t): (f, t)
                case .free: (0.6, 0.6)
                }
                let right = x + max(w - gap, min(w, 1))
                if let grade = step.grade {
                    // A gradient step (D152) is terrain, drawn as the system draws a road: a slope rising across the
                    // step, steeper for a steeper grade, a 1.5-pt line over the terrain fill.
                    let top = size.height * (1 - min(max(grade, 1) / 12, 1) * 0.9)
                    var hill = Path()
                    hill.move(to: CGPoint(x: x, y: size.height))
                    hill.addLine(to: CGPoint(x: x, y: size.height * 0.85))
                    hill.addLine(to: CGPoint(x: right, y: top))
                    hill.addLine(to: CGPoint(x: right, y: size.height))
                    hill.closeSubpath()
                    var ridge = Path()
                    ridge.move(to: CGPoint(x: x, y: size.height * 0.85))
                    ridge.addLine(to: CGPoint(x: right, y: top))
                    let ahead = elapsed > 0 && x >= cut
                    ctx.fill(hill, with: .color(Design.Palette.terrainFill.opacity(ahead ? 0.5 : 1)))
                    ctx.stroke(ridge, with: .color(Design.Accent.teamBlue.opacity(ahead ? 0.5 : 1)), lineWidth: 1.5)
                    x += w
                    continue
                }
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height * (1 - a / peak) + 2))
                path.addQuadCurve(to: CGPoint(x: x + 2, y: size.height * (1 - a / peak)), control: CGPoint(x: x, y: size.height * (1 - a / peak)))
                path.addLine(to: CGPoint(x: right - 2, y: size.height * (1 - b / peak)))
                path.addQuadCurve(to: CGPoint(x: right, y: size.height * (1 - b / peak) + 2), control: CGPoint(x: right, y: size.height * (1 - b / peak)))
                path.addLine(to: CGPoint(x: right, y: size.height))
                path.closeSubpath()
                let tint = step.target == .free ? Design.Palette.blockRest : Design.Zone.color(forFTPFraction: max(a, b))
                if elapsed > 0 {
                    ctx.fill(path, with: .color(tint.opacity(0.35)))
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: 0, y: 0, width: cut, height: size.height)))
                        layer.fill(path, with: .color(tint))
                    }
                } else {
                    ctx.fill(path, with: .color(tint))
                }
                x += w
            }
            if elapsed > 0 {
                ctx.fill(Path(CGRect(x: cut - 1, y: -2, width: 2, height: size.height + 2)), with: .color(color))
            }
        }
    }
}

extension Workout {
    /// What to draw: the ramp test is open-ended, so its preview is the part most riders reach.
    var drawable: Workout {
        guard isRampTest else { return self }
        var p = self
        p.steps = Array(steps.prefix(16))
        return p
    }
}
