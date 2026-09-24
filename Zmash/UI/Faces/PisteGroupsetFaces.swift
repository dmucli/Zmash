import SwiftUI
import ZmashKit

// MARK: - E. Piste

/// The 250 m track as a stadium: two straights joined by half-circles.
private enum Track {
    static let cx: CGFloat = 536, cy: CGFloat = 417, straight: CGFloat = 200, rIn: CGFloat = 176, rOut: CGFloat = 276

    static func stadium(_ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - straight, y: cy + r))
        p.addLine(to: CGPoint(x: cx + straight, y: cy + r))
        p.addArc(center: CGPoint(x: cx + straight, y: cy), radius: r, startAngle: .radians(.pi / 2), endAngle: .radians(-.pi / 2), clockwise: true)
        p.addLine(to: CGPoint(x: cx - straight, y: cy - r))
        p.addArc(center: CGPoint(x: cx - straight, y: cy), radius: r, startAngle: .radians(-.pi / 2), endAngle: .radians(.pi / 2), clockwise: true)
        p.closeSubpath()
        return p
    }

    /// A point `f` of the way round (0…1), on the line at radius `r`, riding anticlockwise from the finish straight.
    static func point(_ r: CGFloat, _ f: Double) -> CGPoint {
        let perimeter = 4 * straight + 2 * .pi * r
        var s = CGFloat((f.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * perimeter
        if s < 2 * straight { return CGPoint(x: cx - straight + s, y: cy + r) }
        s -= 2 * straight
        if s < .pi * r { let a = .pi / 2 - s / r; return CGPoint(x: cx + straight + cos(a) * r, y: cy + sin(a) * r) }
        s -= .pi * r
        if s < 2 * straight { return CGPoint(x: cx + straight - s, y: cy - r) }
        s -= 2 * straight
        let a = -.pi / 2 - s / r
        return CGPoint(x: cx - straight + cos(a) * r, y: cy + sin(a) * r)
    }
}

/// E. Piste — a 250 m velodrome from above. Your dot rides the black line at your real speed and swoops up the
/// banking when you ease off; the lap board flips each lap. A new best 200 m lights the last 200 m behind you.
struct PisteFace: View {
    let d: FaceData
    let dark: Bool
    let animate: Bool
    var style: FaceStyle = .default(.piste)

    @State private var clock = MotionClock()

    var body: some View {
        let p = style.palette(.piste)
        let ink = p.ink(dark: dark), sub = ink.opacity(dark ? 0.66 : 0.72)
        let flying = d.isEvent(.flying200)
        ZStack(alignment: .topLeading) {
            // The track is its own view, so it's drawn once per theme rather than on every tick; only the dot moves.
            PisteTrack(dark: dark)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animate)) { timeline in
                Canvas { ctx, _ in drawRider(&ctx, date: timeline.date, flying: flying) }
            }
            infield(ink: ink, sub: sub, flying: flying)
                .frame(width: 720)
                .at(176, 262)
            lapBoard(sub: sub).frame(width: 134).at(1040, 318)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg(dark: dark))
    }

    private func infield(ink: Color, sub: Color, flying: Bool) -> some View {
        VStack(spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.barlow), 184, weight: 600)).lineLimit(1).minimumScaleFactor(0.5).frame(height: 158)
                Text(style.heroLabel(d, speed: d.speedUnit)).font(FaceFont.font(style.family(.barlow), 18)).tracking(18 * 0.3).textCase(.uppercase).foregroundStyle(sub)
            }
            .foregroundStyle(ink)
            // The infield scoreboard: four equal, centred columns.
            HStack(spacing: 20) {
                R3Cell(value: d.powerI, label: "watts", size: 58, weight: 500, ink: ink, sub: sub, gap: 4, centered: true).frame(maxWidth: .infinity)
                R3Cell(value: d.cadenceText, label: "rpm", size: 58, weight: 500, ink: ink, sub: sub, gap: 4, centered: true).frame(maxWidth: .infinity)
                R3Cell(value: d.elapsedText, label: "elapsed", size: 58, weight: 500, ink: ink, sub: sub, gap: 4, centered: true).frame(maxWidth: .infinity)
                R3Cell(value: d.best200.map { String(format: "%.1f", $0) } ?? "—", label: "best 200 m", size: 58, weight: 500,
                       ink: ink, sub: flying ? Color(hex: 0xC8261C) : sub, gap: 4, centered: true).frame(maxWidth: .infinity)
            }
            .frame(width: 640)
        }
    }

    /// Laps done on the flip board, three digits.
    private func lapBoard(sub: Color) -> some View {
        let digits = Array(String(d.laps).leftPadded(3))
        return VStack(spacing: 10) {
            Text("LAPS").font(FaceFont.font(style.family(.barlow), 15)).tracking(15 * 0.3).foregroundStyle(sub)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x1E1F22))
                        Text(String(digits[i])).font(FaceFont.font(style.family(.barlow), 80, weight: 600)).foregroundStyle(Color(hex: 0xF4F3EE))
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.25), value: d.laps)
                        Rectangle().fill(Color(hex: 0x0C0C0E)).frame(height: 2)
                    }
                    .frame(width: 42, height: 92)
                    .clipped()
                }
            }
            Text("250 M TRACK").font(FaceFont.font(style.family(.barlow), 15)).tracking(15 * 0.2).foregroundStyle(sub)
        }
    }

    fileprivate static func drawTrack(_ t: inout GraphicsContext, dark: Bool) {
        let cx = Track.cx, cy = Track.cy, rIn = Track.rIn, rOut = Track.rOut
        t.fill(Track.stadium(rOut), with: .color(Color(hex: dark ? 0x7A5B37 : 0xDDBE8E)))
        // Pine boards, round the whole track.
        var r = rIn + 14
        while r < rOut {
            let shade = 0.05 + (Double(Int(r * 7) % 5)) * 0.012
            t.stroke(Track.stadium(r), with: .color(Color(red: 0.31, green: 0.2, blue: 0.08, opacity: shade)), lineWidth: 0.8)
            r += 4.2
        }
        // Banking: the turns darken towards the top.
        for (tx, right) in [(cx + Track.straight, true), (cx - Track.straight, false)] {
            t.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: right ? tx : 0, y: 0, width: right ? 1194 - tx : tx, height: 834)))
                var band = Track.stadium(rOut)
                band.addPath(Track.stadium(rIn))
                layer.fill(band, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.16)]),
                                                       center: CGPoint(x: tx, y: cy), startRadius: rIn, endRadius: rOut),
                           style: FillStyle(eoFill: true))
            }
        }
        t.fill(Track.stadium(rIn + 14), with: .color(Color(hex: 0x3E77C8)))   // the blue band (côte d'azur)
        t.fill(Track.stadium(rIn), with: .color(Color(hex: dark ? 0x121317 : 0xF7F7F4)))
        t.stroke(Track.stadium(rIn + 20), with: .color(Color(hex: 0x141414)), lineWidth: 2.5)  // measurement line
        t.stroke(Track.stadium(rIn + 32), with: .color(Color(hex: 0xC8261C)), lineWidth: 2.5)  // sprinter's line
        t.stroke(Track.stadium(rIn + 64), with: .color(Color(hex: 0x3E77C8)), lineWidth: 2)    // stayers' line
        t.stroke(Track.stadium(rOut), with: .color(Color(hex: dark ? 0x3A3C42 : 0xB9B4A8)), lineWidth: 3)
        t.fill(Path(CGRect(x: cx + Track.straight - 60, y: cy + rIn + 14, width: 4, height: rOut - rIn - 14)), with: .color(.white))
        t.fill(Path(CGRect(x: cx + Track.straight - 56, y: cy + rIn + 14, width: 2, height: rOut - rIn - 14)), with: .color(Color(hex: 0x141414)))
    }

    private func drawRider(_ ctx: inout GraphicsContext, date: Date, flying: Bool) {
        let dt = clock.tick(date)
        // Lap position: advance at your speed, then ease towards the ride's own distance so it never drifts.
        var f = clock.value + d.speedKph / 3.6 * dt / 250
        var error = d.lapFraction - f.truncatingRemainder(dividingBy: 1)
        if error > 0.5 { error -= 1 }
        if error < -0.5 { error += 1 }
        f += error * min(1, dt * 2)
        clock.value = f
        // Easing off, you drift up the banking; accelerating, you drop back to the line.
        let target = min(max(-d.trendSpeed * 30, 0), 48)
        clock.extra += (target - clock.extra) * min(1, dt * 2)
        let r = Track.rIn + 20 + CGFloat(clock.extra)

        if flying {
            // Flying 200: the last 200 m behind you light up.
            let a = 1 - d.eventAge
            for i in 0..<60 {
                let f0 = f - 0.8 * Double(i) / 60, f1 = f - 0.8 * Double(i + 1) / 60
                var seg = Path()
                seg.move(to: Track.point(Track.rIn + 20, f0))
                seg.addLine(to: Track.point(Track.rIn + 20, f1))
                ctx.stroke(seg, with: .color(Color(red: 1, green: 0.84, blue: 0.35, opacity: a * (1 - Double(i) / 60) * 0.95)),
                           style: StrokeStyle(lineWidth: 10, lineCap: .round))
            }
        }
        let p = Track.point(r, f)
        let dot = Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
        ctx.fill(dot, with: .color(dark ? .white : Color(hex: 0x141414)))
        ctx.stroke(dot, with: .color(dark ? Color(hex: 0x141414) : .white), lineWidth: 2.5)
    }
}

private extension String {
    func leftPadded(_ n: Int) -> String { String(repeating: " ", count: max(0, n - count)) + self }
}

// MARK: - F. Groupset

/// F. Groupset — your drivetrain in side view. The crank turns at your cadence, the chain runs, and on a shift the
/// cog grows or shrinks under the chain. Freewheeling, the cranks stop. Hold 120 rpm and the crank blurs into a disc.
struct GroupsetFace: View {
    let d: FaceData
    let dark: Bool
    let calm: Bool
    let animate: Bool
    var style: FaceStyle = .default(.groupset)

    @State private var clock = MotionClock()

    static func teeth(gear: Int, of count: Int) -> Int {
        count > 1 ? Int((34 - Double(gear - 1) / Double(count - 1) * 23).rounded()) : 17
    }

    var body: some View {
        let p = style.palette(.groupset)
        let ink = p.ink(dark: dark), sub = ink.opacity(dark ? 0.66 : 0.72), accent = p.accent(dark: dark)
        let teeth = Self.teeth(gear: d.gear, of: d.gearCount)
        // Fonts come from a main-actor cache; resolve them here for the canvas.
        let labelFont = FaceFont.font(style.family(.archivo), 15, weight: 600)
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animate)) { timeline in
                Canvas { ctx, _ in draw(&ctx, date: timeline.date, accent: accent, labelFont: labelFont) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.archivo), 196, weight: 500)).lineLimit(1).minimumScaleFactor(0.5).tracking(-196 * 0.03).frame(height: 168)
                Text(style.heroLabel(d, speed: d.speedUnit)).font(FaceFont.font(style.family(.archivo), 15)).tracking(15 * 0.32).textCase(.uppercase)
                    .foregroundStyle(sub).padding(.top, 14)
                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 30) {
                    GridRow {
                        cell(d.powerI, "watts", ink, sub)
                        cell(d.cadenceText, d.coasting ? "coasting" : "rpm", ink, sub)
                    }
                    GridRow {
                        cell(d.elapsedText, d.remainingText, ink, sub)
                        cell(d.gradeText, "grade", ink, sub)
                    }
                }
                .padding(.top, 48)
            }
            .foregroundStyle(ink)
            .at(56, 60)
            R3Cell(value: d.gearText, label: String(format: "50 × %d · %.2f", teeth, 50 / Double(teeth)), size: 60, weight: 500,
                   family: .archivo, ink: ink, sub: sub)
                .at(600, 696)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg(dark: dark))
    }

    private func cell(_ v: String, _ l: String, _ ink: Color, _ sub: Color) -> some View {
        R3Cell(value: v, label: l, size: 60, weight: 500, family: .archivo, ink: ink, sub: sub).frame(width: 235, alignment: .leading)
    }

    /// A toothed wheel: `teeth` teeth round radius `r`, turned by `rotation`.
    private func wheel(_ c: CGPoint, _ r: CGFloat, teeth: Int, rotation: Double) -> Path {
        var p = Path()
        let n = Double(max(teeth, 3))
        for i in 0..<Int(n) {
            let a0 = rotation + Double(i) / n * 2 * .pi
            let a1 = a0 + .pi / n * 0.5, a2 = a0 + .pi / n, a3 = a0 + .pi / n * 1.5, a4 = a0 + 2 * .pi / n
            let ro = Double(r) + 6, ri = Double(r) - 2
            func pt(_ a: Double, _ rr: Double) -> CGPoint { CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr) }
            if i == 0 { p.move(to: pt(a0, ri)) }
            p.addLine(to: pt(a1, ro)); p.addLine(to: pt(a2, ro)); p.addLine(to: pt(a3, ri)); p.addLine(to: pt(a4, ri))
        }
        p.closeSubpath()
        return p
    }

    private func draw(_ ctx: inout GraphicsContext, date: Date, accent: Color, labelFont: Font) {
        let dt = clock.tick(date)
        let black = Color(hex: dark ? 0x1D1E21 : 0x2A2B2E), edge = Color(hex: dark ? 0x5E636A : 0x6E7379)
        let alu = Color(hex: dark ? 0xB9BDC3 : 0x9EA3AA), bg = style.palette(.groupset).bg(dark: dark)
        let ring = CGPoint(x: 720, y: 450), ringR: CGFloat = 145, cassette = CGPoint(x: 1052, y: 450)
        let n = d.gearCount, teeth = Self.teeth(gear: d.gear, of: n)

        // The crank turns at your cadence (integrated here, smooth between samples); it stops when you freewheel.
        let cadence = d.coasting ? 0 : d.cadenceRpm
        clock.value += cadence / 60 * 2 * .pi * dt
        let crank = clock.value
        // The cog grows or shrinks to the new gear in ~150 ms: the chain climbing onto it.
        let targetR = CGFloat(teeth) * 2.9
        if clock.extra == 0 { clock.extra = Double(targetR) }
        clock.extra += (Double(targetR) - clock.extra) * min(1, dt / 0.05)
        let cogR = CGFloat(clock.extra)

        // The cassette's other cogs, faint.
        for g in 1...max(n, 1) {
            let r = CGFloat(Self.teeth(gear: g, of: n)) * 2.9 + 3
            ctx.stroke(Path(ellipseIn: CGRect(x: cassette.x - r, y: cassette.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(dark ? Color(red: 0.78, green: 0.8, blue: 0.83, opacity: 0.1) : Color(red: 0.16, green: 0.16, blue: 0.17, opacity: 0.1)), lineWidth: 1)
        }
        ctx.fill(wheel(cassette, cogR, teeth: teeth, rotation: crank * 50 / Double(teeth)), with: .color(accent))
        ctx.fill(Path(ellipseIn: CGRect(x: cassette.x - 20, y: cassette.y - 20, width: 40, height: 40)), with: .color(black))

        // Rear derailleur cage.
        let jx = cassette.x - 14, jy = cassette.y + cogR + 64
        var cage = Path()
        cage.move(to: CGPoint(x: cassette.x + 6, y: cassette.y + 34))
        cage.addLine(to: CGPoint(x: jx, y: jy - 34))
        cage.addLine(to: CGPoint(x: jx - 4, y: jy + 6))
        ctx.stroke(cage, with: .color(Color(hex: dark ? 0x8A8F96 : 0x3A3C40)), style: StrokeStyle(lineWidth: 9, lineCap: .round))

        // The chain, its links running at your cadence.
        clock.value2 = (clock.value2 + cadence / 60 * 50 * 12.7 * dt * 0.25).truncatingRemainder(dividingBy: 20)
        var chain = Path()
        chain.move(to: CGPoint(x: ring.x, y: ring.y - ringR - 3)); chain.addLine(to: CGPoint(x: cassette.x, y: cassette.y - cogR - 3))
        chain.move(to: CGPoint(x: cassette.x - 4, y: cassette.y + cogR + 3)); chain.addLine(to: CGPoint(x: jx, y: jy - 32))
        chain.move(to: CGPoint(x: jx, y: jy)); chain.addLine(to: CGPoint(x: ring.x, y: ring.y + ringR + 3))
        ctx.stroke(chain, with: .color(Color(hex: dark ? 0x8C9198 : 0x55595F)),
                   style: StrokeStyle(lineWidth: 7, lineCap: .butt, dash: [8, 4.7], dashPhase: -clock.value2))
        for y in [jy - 32, jy] {
            let jockey = Path(ellipseIn: CGRect(x: jx - 12, y: y - 12, width: 24, height: 24))
            ctx.fill(jockey, with: .color(black))
            ctx.stroke(jockey, with: .color(edge), lineWidth: 1.5)
        }

        // The chainring, with its cut-outs.
        let chainring = wheel(ring, ringR, teeth: 50, rotation: crank)
        ctx.fill(chainring, with: .color(black))
        ctx.stroke(chainring, with: .color(edge), lineWidth: 1.2)
        for i in 0..<5 {
            let a = crank + Double(i) / 5 * 2 * .pi + 0.63
            var cut = ctx
            cut.translateBy(x: ring.x + CGFloat(cos(a)) * 84, y: ring.y + CGFloat(sin(a)) * 84)
            cut.rotate(by: .radians(a + .pi / 2))
            cut.fill(Path(ellipseIn: CGRect(x: -36, y: -22, width: 72, height: 44)), with: .color(bg))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: ring.x - ringR + 22, y: ring.y - ringR + 22, width: 2 * (ringR - 22), height: 2 * (ringR - 22))),
                   with: .color(edge), lineWidth: 1)

        if d.spinUp && !calm {
            // Spin-up: the crank blurs into a disc; the chain stays sharp.
            let disc = Path(ellipseIn: CGRect(x: ring.x - 172, y: ring.y - 172, width: 344, height: 344))
            ctx.fill(disc, with: .color(dark ? Color(red: 0.73, green: 0.74, blue: 0.76, opacity: 0.28) : Color(red: 0.47, green: 0.49, blue: 0.52, opacity: 0.25)))
            ctx.stroke(disc, with: .color(dark ? Color(red: 0.73, green: 0.74, blue: 0.76, opacity: 0.4) : Color(red: 0.47, green: 0.49, blue: 0.52, opacity: 0.4)), lineWidth: 2)
        } else {
            let pedal = CGPoint(x: ring.x + CGFloat(cos(crank)) * 165, y: ring.y + CGFloat(sin(crank)) * 165)
            ctx.stroke(Path { $0.move(to: ring); $0.addLine(to: pedal) }, with: .color(alu), style: StrokeStyle(lineWidth: 22, lineCap: .round))
            ctx.fill(Path(CGRect(x: pedal.x - 26, y: pedal.y - 9, width: 52, height: 18)), with: .color(Color(hex: dark ? 0x2A2B2F : 0x3A3B40)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: ring.x - 20, y: ring.y - 20, width: 40, height: 40)), with: .color(alu))

        let grey = Color(hex: dark ? 0x8A8F96 : 0x6E7379)
        ctx.draw(Text("50T").font(labelFont).foregroundStyle(grey), at: CGPoint(x: ring.x, y: ring.y - ringR - 26), anchor: .bottom)
        ctx.draw(Text("\(teeth)T").font(labelFont).foregroundStyle(grey), at: CGPoint(x: cassette.x, y: cassette.y - cogR - 26), anchor: .bottom)
        if d.coasting {
            ctx.draw(Text("COASTING").font(labelFont).foregroundStyle(accent), at: CGPoint(x: cassette.x, y: min(cassette.y + cogR + 110, 660)), anchor: .bottom)
        }

        // The whole cassette as a ladder, the current cog in the anodised colour.
        for g in 1...max(n, 1) {
            let h = CGFloat(Self.teeth(gear: g, of: n)) * 2.4
            ctx.fill(Path(CGRect(x: 780 + CGFloat(g - 1) * 15, y: 780 - h, width: 9, height: h)),
                     with: .color(g == d.gear ? accent : Color(hex: dark ? 0x4A4E55 : 0xB3B6BB)))
        }
    }
}

/// Piste's track and infield, which change only with the theme.
private struct PisteTrack: View {
    let dark: Bool

    var body: some View {
        Canvas { ctx, _ in PisteFace.drawTrack(&ctx, dark: dark) }
    }
}
