import SwiftUI
import ZmashKit

/// The workout target layer, drawn over any face: current step, target, how far off it you are,
/// time left in the step, what's next, and the whole workout as a strip with a playhead.
struct WorkoutLayer: View {
    let engine: SessionEngine
    var compact = false

    var body: some View {
        if let workout = engine.workout {
            let pos = engine.workoutPosition
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(pos?.step.label.isEmpty == false ? pos!.step.label : workout.name)
                        .font(FaceFont.font(.archivo, 14, weight: 500)).tracking(14 * 0.16).textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(-1)
                    Spacer(minLength: 8)
                    target(pos)
                    if let pos {
                        Text(TimeFormat.clock(Int(pos.remainingInStep.rounded(.up))))
                            .font(FaceFont.font(.archivo, 24, weight: 500))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                WorkoutStrip(workout: workout, elapsed: engine.elapsed)
                    .frame(height: compact ? 22 : 30)
                HStack {
                    if let next = pos?.next {
                        Text("Next  " + (next.label.isEmpty ? "" : next.label + "  ") + (engine.watts(forFraction: next.fraction(at: 0)).map { "\($0) W" } ?? "free"))
                    } else if pos == nil {
                        Text("Workout complete")
                    } else {
                        Text("Last step")
                    }
                    Spacer()
                    if engine.ergActive, engine.intensity != 1 {
                        Text("Intensity \(Int((engine.intensity * 100).rounded())) %")
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

    @ViewBuilder
    private func target(_ pos: Workout.Position?) -> some View {
        if let target = engine.targetW {
            let power = engine.telemetry.power3
            let off = power - Double(target)
            let inRange = abs(off) <= max(8, Double(target) * 0.05)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(target)").font(FaceFont.font(.archivo, 30, weight: 600)).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("W").font(FaceFont.font(.archivo, 15, weight: 500)).foregroundStyle(.white.opacity(0.6))
                if engine.clockStarted, !engine.ergActive || !inRange {
                    Text(inRange ? "on target" : (off > 0 ? "ease off" : "push"))
                        .font(FaceFont.font(.archivo, 13, weight: 500)).tracking(13 * 0.12).textCase(.uppercase)
                        .foregroundStyle(inRange ? Color(hex: 0x8FE3A8) : off > 0 ? Color(hex: 0xFFB38A) : Color(hex: 0x9FD4FF))
                }
            }
        } else if pos != nil {
            Text("Free").font(FaceFont.font(.archivo, 26, weight: 500)).foregroundStyle(.white)
        }
    }
}

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
