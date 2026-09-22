import SwiftUI
import ZmashKit

/// Ridge geometry shared by Horizon and Night: 61 points across the canvas (x = i × 19.9).
private enum Ridge {
    static let dotIndex = 20
    static var dotX: CGFloat { CGFloat(dotIndex) * 19.9 }

    static func near(_ profile: [Double], _ i: Int) -> CGFloat {
        CGFloat(690 - profile[min(max(i, 0), profile.count - 1)] * 300)
    }

    static func line(_ y: (Int) -> CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: y(0)))
            for i in 1...60 { p.addLine(to: CGPoint(x: CGFloat(i) * 19.9, y: y(i))) }
        }
    }

    static func hill(_ y: (Int) -> CGFloat) -> Path {
        var p = line(y)
        p.addLine(to: CGPoint(x: 1194, y: 834))
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

    private static let skies: [[UInt32]] = [
        [0xF3D9C8, 0xEFC6A8, 0xD9E2EA], [0xCFE2F0, 0xEAF1F6, 0xF7F9FA],
        [0xBFD8EC, 0xDCE9F2, 0xF2F6F8], [0xF6D9B8, 0xE9B98E, 0xC9B4C4], [0x2A3550, 0x1B2338, 0x0E1320],
    ]
    private static let times = ["dawn", "morning", "midday", "dusk", "night"]

    static func skyIndex(_ progress: Double) -> Int { min(4, Int(min(0.999, progress) * 5)) }
    static func background(progress: Double) -> Color { Color(hex: skies[skyIndex(progress)][1]) }

    var body: some View {
        let idx = Self.skyIndex(d.progress)
        let sky = Self.skies[idx]
        let deepNight = idx == 4 || (dark && idx >= 3)
        let ink = deepNight ? Color(hex: 0xEDF0F4) : Color(hex: 0x1A2230)
        let base = Color(hex: 0x1A2230)
        let hillFar = deepNight ? Color(hex: 0x141B2A) : base.opacity(0.14)
        let hillMid = deepNight ? Color(hex: 0x0E1421) : base.opacity(0.26)
        let hillNear = deepNight ? Color(hex: 0x060A12) : Color(hex: 0x141A26, opacity: 0.86)
        let groundInk = deepNight ? Color(hex: 0xC9D6E4) : Color(hex: 0xF2F5F8)
        let dotFill = d.climbing ? Color(hex: 0xFF7A4D) : (deepNight ? Color(hex: 0x9FE8FF) : .white)
        let gradeInk = d.climbing ? (deepNight ? Color(hex: 0xFF9C6E) : Color(hex: 0xB23A14)) : ink
        let s = d.distanceM / 1000
        let angle = Double(170 + idx * 2) * .pi / 180
        let dir = CGPoint(x: sin(angle) / 2, y: -cos(angle) / 2)
        let dotY = Ridge.near(d.profile, Ridge.dotIndex) - 2
        let summit = d.profile.indices.max { d.profile[$0] < d.profile[$1] } ?? 0

        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Color(hex: sky[0]), location: 0), .init(color: Color(hex: sky[1]), location: 0.46),
                                   .init(color: Color(hex: sky[2]), location: 1)],
                           startPoint: UnitPoint(x: 0.5 - dir.x, y: 0.5 - dir.y), endPoint: UnitPoint(x: 0.5 + dir.x, y: 0.5 + dir.y))
                .animation(.easeInOut(duration: 4), value: idx)

            Ridge.hill { i in CGFloat(452 - 62 * sin(Double(i) * 0.07 - s * 0.3) - 26 * sin(Double(i) * 0.19 - s * 0.18)) }.fill(hillFar)
            Ridge.hill { i in CGFloat(520 - 78 * sin(Double(i) * 0.13 - s * 0.9) - 34 * sin(Double(i) * 0.33 - s * 0.5)) }.fill(hillMid)
            Ridge.hill { Ridge.near(d.profile, $0) }.fill(hillNear)

            Circle().fill(dotFill).frame(width: 22, height: 22).position(x: Ridge.dotX, y: dotY)
            Circle().stroke(dotFill, lineWidth: 1.5).frame(width: 40, height: 40).opacity(0.4).position(x: Ridge.dotX, y: dotY)

            // Magic moment: the summit just taken is marked with a thin line.
            Rectangle().fill(ink).frame(width: 1, height: 834)
                .position(x: CGFloat(summit) / 60 * 1194, y: 417)
                .opacity(d.isEvent(.summit) ? 0.5 * (1 - d.eventAge) : 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(d.speed0).font(FaceFont.font(.newsreader, 236, weight: 200)).tracking(-0.02 * 236).frame(height: 194)
                Text(d.speedUnit).faceLabel(.archivo, 20, tracking: 0.34).opacity(0.78).padding(.top, 12)
            }
            .padding(.leading, 56).padding(.top, 52)

            HStack(alignment: .top, spacing: 56) {
                big(d.powerI, "watts")
                big(d.cadenceText, "rpm")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 56).padding(.top, 56)

            VStack(alignment: .trailing, spacing: 0) {
                Text(d.elapsedText).font(FaceFont.font(.newsreader, 68, weight: 300))
                Text("elapsed · \(d.remainingText) left").faceLabel(.archivo, 15, tracking: 0.3).opacity(0.78)
                Text(d.gradeText).font(FaceFont.font(.newsreader, 58, weight: 400)).foregroundStyle(gradeInk).padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 56).padding(.top, 250)

            HStack(alignment: .firstTextBaseline, spacing: 46) {
                Text("\(d.distText) \(d.distUnit)")
                Text("\(d.climbedText) \(d.elevUnit) climbed")
                Text("gear \(d.gearText)")
                Text(Self.times[idx])
            }
            .faceLabel(.archivo, 15, tracking: 0.24)
            .foregroundStyle(groundInk.opacity(0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 56).padding(.bottom, 40)
        }
        .foregroundStyle(ink)
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(FaceFont.font(.newsreader, 92, weight: 300))
            Text(label).faceLabel(.archivo, 15, tracking: 0.3).opacity(0.78)
        }
    }
}

// MARK: - Night

/// H. Night — a dark face made of light: glowing lines, wind streaks at speed, numbers lit from within.
struct NightFace: View {
    let d: FaceData
    let calm: Bool
    let animate: Bool

    var body: some View {
        let glow = d.climbing ? Color(hex: 0xFFC49F) : Color(hex: 0x9FE8FF)
        let led = Color(hex: 0x9FE8FF)
        let bloom = 14 + (d.powerW / d.ftp) * 34
        let dotY = Ridge.near(d.profile, Ridge.dotIndex) - 2

        ZStack(alignment: .topLeading) {
            Color.black
            NightStreaks(speedKph: d.speedKph, warp: d.isEvent(.best), calm: calm, glow: glow,
                         running: animate && d.state == .riding)

            Ridge.line { Ridge.near(d.profile, $0) }
                .stroke(glow, lineWidth: 2)
                .opacity(0.85)
                .shadow(color: glow, radius: 5)
            Circle().fill(.white).frame(width: 14, height: 14)
                .shadow(color: glow, radius: 7)
                .position(x: Ridge.dotX, y: dotY)

            VStack(alignment: .leading, spacing: 0) {
                Text(d.speed1).font(FaceFont.font(.archivo, 252, weight: 300))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.7), radius: 6)
                    .shadow(color: glow, radius: bloom / 2)
                    .frame(height: 212)
                Text(d.speedUnit).faceLabel(.archivo, 18, tracking: 0.36).foregroundStyle(glow).padding(.top, 10)
            }
            .padding(.leading, 60).padding(.top, 56)

            HStack(alignment: .top, spacing: 52) {
                lit(d.powerI, "watts", glow: glow, bloom: bloom)
                lit(d.cadenceText, "rpm", glow: glow, bloom: bloom)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 60).padding(.top, 60)

            VStack(alignment: .trailing, spacing: 0) {
                Text(d.elapsedText).font(FaceFont.font(.archivo, 74, weight: 300)).foregroundStyle(.white)
                Text("elapsed · \(d.remainingText) left").faceLabel(.archivo, 15, tracking: 0.32).foregroundStyle(glow).padding(.top, 4)
                Text(d.gradeText).font(FaceFont.font(.archivo, 64, weight: 400))
                    .foregroundStyle(glow).shadow(color: glow, radius: 11).padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 60).padding(.top, 280)

            HStack(alignment: .center, spacing: 22) {
                Text("gear").faceLabel(.archivo, 14, tracking: 0.3).foregroundStyle(glow.opacity(0.8))
                HStack(spacing: 7) {
                    ForEach(1...d.gearCount, id: \.self) { i in
                        let on = i <= d.gear
                        RoundedRectangle(cornerRadius: 2).fill(led)
                            .frame(width: 9, height: 26)
                            .opacity(on ? 0.95 : 0.14)
                            .shadow(color: on ? led : .clear, radius: 5)
                    }
                }
                Text(d.gearText).font(FaceFont.font(.archivo, 40, weight: 300)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 60).padding(.bottom, 46)

            HStack(spacing: 44) {
                Text("\(d.distText) \(d.distUnit)")
                Text("\(d.climbedText) \(d.elevUnit)")
                Text("\(d.kcalText) kcal")
            }
            .faceLabel(.archivo, 15, tracking: 0.28)
            .foregroundStyle(glow.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 60).padding(.bottom, 46)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
    }

    private func lit(_ value: String, _ label: String, glow: Color, bloom: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(FaceFont.font(.archivo, 104, weight: 300)).foregroundStyle(.white)
                .shadow(color: glow, radius: bloom / 2)
            Text(label).faceLabel(.archivo, 15, tracking: 0.32).foregroundStyle(glow)
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
            Canvas { ctx, _ in
                let speedF = max(0.25, speedKph / 34)
                let phase = clock.advance(to: timeline.date, rate: running ? speedF : 0)
                let n = calm ? 12 : 30
                let stretch = warp ? 3.4 : 1
                for i in 0..<n {
                    let seed = Double((i * 137) % 100) / 100
                    let seed2 = Double((i * 61) % 100) / 100
                    let y = seed2 < 0.5 ? 470 + seed * 330 : 60 + seed * 180
                    var x = (seed * 1700 - phase * (180 + seed2 * 280)).truncatingRemainder(dividingBy: 1700)
                    if x < -300 { x += 1700 }
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
