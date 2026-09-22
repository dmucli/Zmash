import SwiftUI

/// Phase 2 background: faint wind streaks flying from a vanishing point towards the rider.
/// Their speed and number follow the ride speed; still when stopped or paused.
/// Off with Reduce Motion or Low Power Mode, and when disabled in Settings.
struct WindBackground: View {
    let speedKph: Double
    let paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var field = WindField()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        if reduceMotion || lowPower {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: paused || speedKph < 0.5)) { timeline in
                Canvas { context, size in
                    field.advance(to: timeline.date, speedKph: speedKph, size: size)
                    field.draw(in: &context, size: size, color: Design.Palette.primary)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

/// Perspective particle field. A reference type so the Canvas can advance it in place each frame.
@MainActor
final class WindField {
    struct Particle {
        var x: Double      // −1…1 across the view
        var y: Double      // −1…1
        var z: Double      // depth, 1 (far) → near 0
        var alive = true
    }

    private var particles: [Particle] = []
    private var last: Date?
    private var rng = SystemRandomNumberGenerator()

    static let maxParticles = 140
    /// Depth units travelled per second at 1 km/h.
    static let depthPerKph = 0.012

    func advance(to date: Date, speedKph: Double, size: CGSize) {
        let dt = min(last.map { date.timeIntervalSince($0) } ?? 0, 1 / 20)
        last = date
        let v = speedKph * Self.depthPerKph

        for i in particles.indices {
            particles[i].z -= v * dt
            if particles[i].z <= 0.05 { particles[i].alive = false }
        }
        particles.removeAll { !$0.alive }

        // Density rises with speed: none when stopped, full field from ~45 km/h.
        let target = Int(Double(Self.maxParticles) * min(1, speedKph / 45))
        while particles.count < target {
            particles.append(Particle(x: .random(in: -1...1, using: &rng), y: .random(in: -1...1, using: &rng),
                                      z: particles.isEmpty ? .random(in: 0.2...1, using: &rng) : .random(in: 0.8...1, using: &rng)))
        }
        if particles.count > target { particles.removeFirst(particles.count - target) }
    }

    func draw(in context: inout GraphicsContext, size: CGSize, color: Color) {
        let cx = size.width / 2, cy = size.height * 0.45
        let scale = max(size.width, size.height) * 0.35
        for p in particles {
            // Streak from its position a moment ago to now; longer and brighter as it nears.
            let z0 = min(1, p.z + 0.04)
            let a = CGPoint(x: cx + p.x / z0 * scale, y: cy + p.y / z0 * scale)
            let b = CGPoint(x: cx + p.x / p.z * scale, y: cy + p.y / p.z * scale)
            guard b.x > -40, b.x < size.width + 40, b.y > -40, b.y < size.height + 40 else { continue }
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let nearness = 1 - p.z
            context.stroke(path, with: .color(color.opacity(0.04 + 0.16 * nearness)),
                           style: StrokeStyle(lineWidth: 0.5 + 1.5 * nearness, lineCap: .round))
        }
    }
}
