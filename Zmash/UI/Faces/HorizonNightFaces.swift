import SwiftUI
import ZmashKit

/// Ridge geometry shared by Horizon and Night: 61 points across the canvas (x = i × width / 60; 19.9 at the design
/// width).
private enum Ridge {
    static let dotIndex = 20
    static func dotX(_ width: CGFloat) -> CGFloat { CGFloat(dotIndex) * width / 60 }

    /// A far hill: two sine waves under a baseline, drifting with the ride (`amplitude`, `frequency`, `phase` each).
    static func wave(_ i: Int, base: Double, _ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> CGFloat {
        let x = Double(i)
        return CGFloat(base - a.0 * sin(x * a.1 - a.2) - b.0 * sin(x * b.1 - b.2))
    }

    static func near(_ profile: [Double], _ i: Int) -> CGFloat {
        CGFloat(690 - profile[min(max(i, 0), profile.count - 1)] * 300)
    }

    static func line(width: CGFloat, _ y: (Int) -> CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: y(0)))
            for i in 1...60 { p.addLine(to: CGPoint(x: CGFloat(i) * width / 60, y: y(i))) }
        }
    }

    static func hill(width: CGFloat, _ y: (Int) -> CGFloat) -> Path {
        var p = line(width: width, y)
        p.addLine(to: CGPoint(x: width, y: 834))
        p.addLine(to: CGPoint(x: 0, y: 834))
        p.closeSubpath()
        return p
    }
}

// MARK: - Horizon

/// B. Horizon — the terrain becomes a ridge you ride into; the sky drifts from dawn to night across the ride.
struct HorizonFace: View {
    let d: FaceData
    let dark: Bool
    var style: FaceStyle = .default(.horizon)
    @Environment(\.faceWidth) private var canvasWidth

    private static let times = ["dawn", "morning", "midday", "dusk", "night"]

    static func skies(_ style: FaceStyle) -> [[UInt32]] {
        style.palette(.horizon).skies ?? FacePalettes.horizon[0].skies!
    }

    static func skyIndex(_ progress: Double) -> Int { min(4, Int(min(0.999, progress) * 5)) }

    static func background(progress: Double, style: FaceStyle = .default(.horizon)) -> Color {
        Color(hex: skies(style)[skyIndex(progress)][1])
    }

    var body: some View {
        let palette = style.palette(.horizon)
        let idx = Self.skyIndex(d.progress)
        let sky = Self.skies(style)[idx]
        let deepNight = idx == 4 || (dark && idx >= 3)
        let ink = deepNight ? palette.ink(dark: true) : palette.ink(dark: false)
        let base = Color(hex: 0x1A2230)
        let hillFar = deepNight ? Color(hex: 0x141B2A) : base.opacity(0.14)
        let hillMid = deepNight ? Color(hex: 0x0E1421) : base.opacity(0.26)
        let hillNear = deepNight ? Color(hex: 0x060A12) : Color(hex: 0x141A26, opacity: 0.86)
        let groundInk = deepNight ? Color(hex: 0xC9D6E4) : Color(hex: 0xF2F5F8)
        let dotFill = d.climbing ? palette.accent(dark: deepNight) : (deepNight ? Color(hex: 0x9FE8FF) : .white)
        let gradeInk = d.climbing ? palette.accent(dark: deepNight) : ink
        let s = d.distanceM / 1000
        let angle = Double(170 + idx * 2) * .pi / 180
        let dir = CGPoint(x: sin(angle) / 2, y: -cos(angle) / 2)
        let dotY = Ridge.near(d.profile, Ridge.dotIndex) - 2

        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Color(hex: sky[0]), location: 0), .init(color: Color(hex: sky[1]), location: 0.46),
                                   .init(color: Color(hex: sky[2]), location: 1)],
                           startPoint: UnitPoint(x: 0.5 - dir.x, y: 0.5 - dir.y), endPoint: UnitPoint(x: 0.5 + dir.x, y: 0.5 + dir.y))
                .animation(.easeInOut(duration: 4), value: idx)

            Ridge.hill(width: canvasWidth) { Ridge.wave($0, base: 452, (62, 0.07, s * 0.3), (26, 0.19, s * 0.18)) }.fill(hillFar)
            Ridge.hill(width: canvasWidth) { Ridge.wave($0, base: 520, (78, 0.13, s * 0.9), (34, 0.33, s * 0.5)) }.fill(hillMid)
            Ridge.hill(width: canvasWidth) { Ridge.near(d.profile, $0) }.fill(hillNear)

            Circle().fill(dotFill).frame(width: 22, height: 22).position(x: Ridge.dotX(canvasWidth), y: dotY)
            Circle().stroke(dotFill, lineWidth: 1.5).frame(width: 40, height: 40).opacity(0.4).position(x: Ridge.dotX(canvasWidth), y: dotY)

            // Magic moment: the summit just taken is marked with a thin line, where you are (the profile is the road
            // ahead, so its high point would be the next climb, not this one).
            Rectangle().fill(ink).frame(width: 1, height: 834)
                .position(x: Ridge.dotX(canvasWidth), y: 417)
                .opacity(d.isEvent(.summit) ? 0.5 * (1 - d.eventAge) : 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(style.heroValue(d, speed: d.speed0)).font(FaceFont.font(style.family(.newsreader), 236, weight: 200)).lineLimit(1).minimumScaleFactor(0.5).tracking(-0.02 * 236)
                    // Bounded, so a long custom value shrinks before it reaches the watts and rpm.
                    .frame(maxWidth: 600, alignment: .leading).frame(height: 194)
                Text(style.heroLabel(d, speed: d.speedUnit)).faceLabel(style.family(.archivo), 20, tracking: 0.34).opacity(0.78).padding(.top, 12)
            }
            .padding(.leading, 56).padding(.top, 52)

            HStack(alignment: .top, spacing: 56) {
                big(d.powerI, "watts")
                big(d.cadenceText, "rpm")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 56).padding(.top, 56)

            VStack(alignment: .trailing, spacing: 0) {
                Text(d.elapsedText).font(FaceFont.font(style.family(.newsreader), 68, weight: 300))
                Text("elapsed · \(d.remainingText) left").faceLabel(style.family(.archivo), 15, tracking: 0.3).opacity(0.78)
                Text(d.gradeText).font(FaceFont.font(style.family(.newsreader), 58, weight: 400)).foregroundStyle(gradeInk).padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 56).padding(.top, 250)

            HStack(alignment: .firstTextBaseline, spacing: 46) {
                ForEach(style.slotItems(.horizon).filter { $0.metric != .empty }) { slot in
                    Text("\(slot.metric.value(d)) \(slot.metric.unit(d))")
                }
                Text(Self.times[idx])
            }
            .faceLabel(style.family(.archivo), 15, tracking: 0.24)
            .foregroundStyle(groundInk.opacity(0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 56).padding(.bottom, 40)
        }
        .foregroundStyle(ink)
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(FaceFont.font(style.family(.newsreader), 92, weight: 300))
            Text(label).faceLabel(style.family(.archivo), 15, tracking: 0.3).opacity(0.78)
        }
    }
}

// MARK: - Night

/// H. Night — a dark face made of light: glowing lines, wind streaks at speed, numbers lit from within.
struct NightFace: View {
    let d: FaceData
    let calm: Bool
    let animate: Bool
    var style: FaceStyle = .default(.night)
    @Environment(\.faceWidth) private var canvasWidth

    /// The light this face is made of.
    static func glow(_ style: FaceStyle) -> Color { Color(hex: style.palette(.night).glow ?? 0x9FE8FF) }

    var body: some View {
        let led = Self.glow(style)
        let glow = d.climbing ? Color(hex: 0xFFC49F) : led
        let bloom = 14 + (d.powerW / d.ftp) * 34
        let dotY = Ridge.near(d.profile, Ridge.dotIndex) - 2

        ZStack(alignment: .topLeading) {
            Color.black
            NightStreaks(speedKph: d.speedKph, warp: d.isEvent(.best), calm: calm, glow: glow,
                         running: animate && d.state == .riding)

            Ridge.line(width: canvasWidth) { Ridge.near(d.profile, $0) }
                .stroke(glow, lineWidth: 2)
                .opacity(0.85)
                .shadow(color: glow, radius: 5)
            Circle().fill(.white).frame(width: 14, height: 14)
                .shadow(color: glow, radius: 7)
                .position(x: Ridge.dotX(canvasWidth), y: dotY)

            VStack(alignment: .leading, spacing: 0) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.archivo), 252, weight: 300)).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.7), radius: 6)
                    .shadow(color: glow, radius: bloom / 2)
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(height: 212)
                Text(style.heroLabel(d, speed: d.speedUnit)).faceLabel(style.family(.archivo), 18, tracking: 0.36).foregroundStyle(glow).padding(.top, 10)
            }
            .padding(.leading, 60).padding(.top, 56)

            HStack(alignment: .top, spacing: 52) {
                lit(d.powerI, "watts", glow: glow, bloom: bloom)
                lit(d.cadenceText, "rpm", glow: glow, bloom: bloom)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 60).padding(.top, 60)

            VStack(alignment: .trailing, spacing: 0) {
                Text(d.elapsedText).font(FaceFont.font(style.family(.archivo), 74, weight: 300)).foregroundStyle(.white)
                Text("elapsed · \(d.remainingText) left").faceLabel(style.family(.archivo), 15, tracking: 0.32).foregroundStyle(glow).padding(.top, 4)
                Text(d.gradeText).font(FaceFont.font(style.family(.archivo), 64, weight: 400))
                    .foregroundStyle(glow).shadow(color: glow, radius: 11).padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 60).padding(.top, 280)

            HStack(alignment: .center, spacing: 22) {
                Text("gear").faceLabel(style.family(.archivo), 14, tracking: 0.3).foregroundStyle(glow.opacity(0.8))
                HStack(spacing: 7) {
                    ForEach(1...d.gearCount, id: \.self) { i in
                        let on = i <= d.gear
                        RoundedRectangle(cornerRadius: 2).fill(led)
                            .frame(width: 9, height: 26)
                            .opacity(on ? 0.95 : 0.14)
                            .shadow(color: on ? led : .clear, radius: 5)
                    }
                }
                Text(d.gearText).font(FaceFont.font(style.family(.archivo), 40, weight: 300)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 60).padding(.bottom, 46)

            HStack(spacing: 44) {
                ForEach(style.slotItems(.night).filter { $0.metric != .empty }) { slot in
                    Text("\(slot.metric.value(d)) \(slot.metric.unit(d))")
                }
            }
            .faceLabel(style.family(.archivo), 15, tracking: 0.28)
            .foregroundStyle(glow.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 60).padding(.bottom, 46)
        }
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
    }

    private func lit(_ value: String, _ label: String, glow: Color, bloom: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(FaceFont.font(style.family(.archivo), 104, weight: 300)).foregroundStyle(.white)
                .shadow(color: glow, radius: bloom / 2)
            Text(label).faceLabel(style.family(.archivo), 15, tracking: 0.32).foregroundStyle(glow)
        }
    }
}

/// Wind streaks flying across at the rider's speed; a session best "warps" them long.
private struct NightStreaks: View {
    let speedKph: Double
    let warp: Bool
    let calm: Bool
    let glow: Color
    let running: Bool
    @State private var clock = StreakClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !running)) { timeline in
            Canvas { ctx, size in
                let speedF = max(0.25, speedKph / 34)
                // Streaks cycle over the canvas and 500 pt beyond it (1700 at the design width).
                let span = size.width + 506
                let phase = clock.advance(to: timeline.date, rate: running ? speedF : 0)
                let n = calm ? 12 : 30
                let stretch = warp ? 3.4 : 1
                for i in 0..<n {
                    let seed = Double((i * 137) % 100) / 100
                    let seed2 = Double((i * 61) % 100) / 100
                    let y = seed2 < 0.5 ? 470 + seed * 330 : 60 + seed * 180
                    var x = (seed * span - phase * (180 + seed2 * 280)).truncatingRemainder(dividingBy: span)
                    if x < -300 { x += span }
                    let w = (70 + seed2 * 190) * speedF * stretch
                    let rect = CGRect(x: x, y: y, width: w, height: 1.5)
                    ctx.opacity = 0.2 + seed2 * 0.42
                    ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [glow.opacity(0), glow]),
                                                               startPoint: CGPoint(x: rect.minX, y: y),
                                                               endPoint: CGPoint(x: rect.maxX, y: y)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Integrates speed-scaled time so streaks never jump when speed changes.
@MainActor
private final class StreakClock {
    private var phase = 0.0
    private var last: Date?

    func advance(to date: Date, rate: Double) -> Double {
        let dt = min(last.map { date.timeIntervalSince($0) } ?? 0, 0.1)
        last = date
        phase += dt * rate
        return phase
    }
}
