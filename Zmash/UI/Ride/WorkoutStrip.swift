import SwiftUI
import ZmashKit

/// A workout as blocks (height = target), filled up to `elapsed`.
struct WorkoutStrip: View {
    let workout: Workout
    var elapsed: Double = 0
    var color: Color = .white

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
            var x = 0.0
            for step in workout.steps {
                let w = Double(step.seconds) / total * size.width
                let (a, b): (Double, Double) = switch step.target {
                case .steady(let f): (f, f)
                case .ramp(let f, let t): (f, t)
                case .free: (0.6, 0.6)
                }
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height * (1 - a / peak)))
                path.addLine(to: CGPoint(x: x + w, y: size.height * (1 - b / peak)))
                path.addLine(to: CGPoint(x: x + w, y: size.height))
                path.closeSubpath()
                // 1 pt gap between steps; free steps are hatched-looking (dimmer).
                let dim = step.target == .free ? 0.18 : 0.32
                ctx.fill(path, with: .color(color.opacity(dim)))
                ctx.drawLayer { layer in
                    layer.clip(to: Path(CGRect(x: 0, y: 0, width: cut, height: size.height)))
                    layer.fill(path, with: .color(color.opacity(step.target == .free ? 0.5 : 0.9)))
                }
                if w > 2 {
                    ctx.fill(Path(CGRect(x: x + w - 0.5, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.35)))
                }
                x += w
            }
            if elapsed > 0 {
                ctx.fill(Path(CGRect(x: cut - 1, y: -2, width: 2, height: size.height + 2)), with: .color(color))
            }
        }
    }
}
