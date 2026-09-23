import SwiftUI
import ZmashKit

/// A workout as blocks coloured by power zone (stone → blue → vermilion), 2 pt apart with rounded tops. Once riding,
/// what's ahead dims and a line marks where you are.
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
