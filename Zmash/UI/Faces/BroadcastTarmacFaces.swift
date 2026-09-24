import SwiftUI
import ZmashKit

// MARK: - D. Broadcast

/// D. Broadcast — the race on TV: the road ahead as an extruded profile, climbs flagged on their summits, a
/// five-value telemetry bar and kilometres to go. The red kite hangs at one kilometre to go; under it the
/// counter switches to metres.
struct BroadcastFace: View {
    let d: FaceData
    let calm: Bool
    var style: FaceStyle = .default(.broadcast)
    @Environment(\.faceWidth) private var canvasWidth

    private static let navy = Color(hex: 0x0A1A36)
    private static let yellow = Color(hex: 0xFFD23F)
    private static let soft = Color(hex: 0xC9D4E8)

    var body: some View {
        let flagFont = FaceFont.font(style.family(.barlow), 14, weight: 700)
        let tickFont = FaceFont.font(style.family(.barlow), 15, weight: 700)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x132B52), Color(hex: 0x0B1A33)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in drawProfile(&ctx, width: size.width, flagFont: flagFont, tickFont: tickFont) }

            HStack(spacing: 10) {
                Circle().fill(Self.yellow).frame(width: 10, height: 10)
                Text("LIVE").font(FaceFont.font(style.family(.barlow), 18, weight: 700)).tracking(18 * 0.24)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Self.navy)
            .at(44, 36)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(toGo.value).font(FaceFont.font(style.family(.barlow), 64, weight: 700)).foregroundStyle(Self.yellow)
                Text(toGo.unit).font(FaceFont.font(style.family(.barlow), 18, weight: 700)).tracking(18 * 0.2).foregroundStyle(.white)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Self.navy)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 44)
            .at(0, 36)

            VStack(alignment: .leading, spacing: 10) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.barlow), 200, weight: 700, slant: -10)).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(.white).frame(height: 172)
                Text("\(style.heroLabel(d, speed: d.speedUnit).uppercased()) · GEAR \(d.gearText)").font(FaceFont.font(style.family(.barlow), 18, weight: 700))
                    .tracking(18 * 0.24).foregroundStyle(Self.soft)
            }
            .at(52, 108)

            telemetry
                .frame(height: 104)
                .padding(.horizontal, 44)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 36)
        }
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
    }

    /// Kilometres to go on a known road (metres in the last one); otherwise time to go, or time ridden.
    private var toGo: (value: String, unit: String) {
        if !d.course.isEmpty {
            let left = max(0, d.courseKm - d.roadKm) * 1000
            // The last kilometre in metres, the last mile in yards.
            if d.units == .metric, left < 1000 { return ("\(Int(left.rounded()))", "M TO GO") }
            if d.units == .imperial, left < 1609.344 { return ("\(Int((left / 0.9144).rounded()))", "YD TO GO") }
            return (String(format: "%.1f", d.units.distance(left)), "\(d.distUnit.uppercased()) TO GO")
        }
        if d.remaining != nil { return (d.remainingClock, "TO GO") }
        return (d.elapsedText, "RIDDEN")
    }

    private var telemetry: some View {
        HStack(spacing: 0) {
            slot(d.powerI, "W")
            slot(d.cadenceText, "RPM")
            slot(d.gradeText, nil)
            slot(d.elapsedText, nil)
            slot(d.hrText, "BPM")
        }
        .background(Self.navy)
        .overlay(alignment: .top) { Rectangle().fill(Self.yellow).frame(height: 3) }
    }

    private func slot(_ value: String, _ unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value).font(FaceFont.font(style.family(.barlow), 62, weight: 700)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            if let unit { Text(unit).font(FaceFont.font(style.family(.barlow), 18, weight: 700)).tracking(18 * 0.16).foregroundStyle(Self.soft) }
        }
        .padding(.leading, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x22375E)).frame(width: 1) }
    }

    private func drawProfile(_ ctx: inout GraphicsContext, width: CGFloat, flagFont: Font, tickFont: Font) {
        let L = d.roadLengthKm
        let profile = d.wholeProfile
        let here = d.roadKm
        // 12 km across the design width; a wider canvas shows more road ahead at the same scale.
        let x0: CGFloat = 40, x1: CGFloat = width - 40
        let k0 = here - 3.5, k1 = k0 + 12 * Double((x1 - x0) / (FaceCanvas.size.width - 80))
        let xOf = { (k: Double) in x0 + CGFloat((k - k0) / (k1 - k0)) * (x1 - x0) }
        let hOf = { (k: Double) in CGFloat(sampleProfile(profile, k / L)) * 250 }
        let base: CGFloat = 640, dx: CGFloat = 40, dy: CGFloat = -28
        // Real gradient from the normalised profile (0.9 of the height is the course's relief).
        let metresPerUnit = d.courseReliefM > 0 ? d.courseReliefM / 0.9 : 100
        func colors(_ grade: Double) -> (Color, Color) {
            grade < 2 ? (Color(hex: 0x3FAF5A), Color(hex: 0x2B7E40))
                : grade < 4.5 ? (Color(hex: 0xE8C43A), Color(hex: 0xA88A1E))
                : grade < 7 ? (Color(hex: 0xE9822E), Color(hex: 0xA8561A)) : (Color(hex: 0xD8412F), Color(hex: 0x962A1E))
        }
        var view = ctx
        if !calm {
            // The helicopter shot tilts a few degrees with the slope.
            let tilt = min(max(d.grade, -8), 8) * 0.004
            view.translateBy(x: width / 2, y: 450); view.rotate(by: .radians(-tilt)); view.translateBy(x: -width / 2, y: -450)
        }
        let step = 0.08
        var k = k0
        var slices: [(x: CGFloat, x2: CGFloat, y: CGFloat, y2: CGFloat, grade: Double)] = []
        while k < k1 {
            let h1 = hOf(k), h2 = hOf(k + step)
            let grade = Double(h2 - h1) / 250 * metresPerUnit / (step * 1000) * 100
            slices.append((xOf(k), xOf(k + step), base - h1, base - h2, grade))
            k += step
        }
        for s in slices {  // the top of the ribbon
            var top = Path()
            top.move(to: CGPoint(x: s.x, y: s.y)); top.addLine(to: CGPoint(x: s.x2 + 0.6, y: s.y2))
            top.addLine(to: CGPoint(x: s.x2 + dx + 0.6, y: s.y2 + dy)); top.addLine(to: CGPoint(x: s.x + dx, y: s.y + dy))
            top.closeSubpath()
            view.fill(top, with: .color(colors(s.grade).0))
        }
        for s in slices {  // its side
            var side = Path()
            side.move(to: CGPoint(x: s.x, y: s.y)); side.addLine(to: CGPoint(x: s.x2 + 0.6, y: s.y2))
            side.addLine(to: CGPoint(x: s.x2 + 0.6, y: base)); side.addLine(to: CGPoint(x: s.x, y: base))
            side.closeSubpath()
            view.fill(side, with: .color(colors(s.grade).1))
        }
        // Kilometres to go under the ribbon.
        if !d.course.isEmpty {
            var km = k0.rounded(.up)
            while km <= k1 {
                if km >= 0, km <= L {
                    let x = xOf(km)
                    view.fill(Path(CGRect(x: x, y: base + 2, width: 1, height: 8)), with: .color(.white.opacity(0.5)))
                    if Int(km) % 2 == 0 {
                        view.draw(Text("\(Int((L - km).rounded()))").font(tickFont).foregroundStyle(.white.opacity(0.5)),
                                  at: CGPoint(x: x, y: base + 26), anchor: .bottom)
                    }
                }
                km += 1
            }
        }
        // Climb flags on the summits in view.
        for climb in d.climbs where climb.endKm >= k0 && climb.endKm <= k1 {
            let x = xOf(climb.endKm) + dx / 2, y = base - hOf(climb.endKm) + dy / 2
            view.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: y - 54)) }, with: .color(.white), lineWidth: 2)
            var flag = Path()
            flag.move(to: CGPoint(x: x, y: y - 54)); flag.addLine(to: CGPoint(x: x + 44, y: y - 46)); flag.addLine(to: CGPoint(x: x, y: y - 36))
            flag.closeSubpath()
            view.fill(flag, with: .color(.white))
            view.draw(Text(climb.label).font(flagFont).foregroundStyle(Color(hex: 0x0B1A33)), at: CGPoint(x: x + 5, y: y - 41), anchor: .leading)
        }
        // The flamme rouge: the red kite over the road at one kilometre to go.
        if !d.course.isEmpty, L - 1 > k0, L - 1 < k1 {
            let x = xOf(L - 1) + dx / 2, y = base - hOf(L - 1) + dy / 2
            var arch = Path()
            arch.move(to: CGPoint(x: x - 24, y: y)); arch.addLine(to: CGPoint(x: x - 24, y: y - 70))
            arch.addLine(to: CGPoint(x: x + 24, y: y - 70)); arch.addLine(to: CGPoint(x: x + 24, y: y))
            view.stroke(arch, with: .color(Color(hex: 0xD8261C)), lineWidth: 6)
            var kite = Path()
            kite.move(to: CGPoint(x: x - 16, y: y - 70)); kite.addLine(to: CGPoint(x: x + 16, y: y - 70)); kite.addLine(to: CGPoint(x: x, y: y - 46))
            kite.closeSubpath()
            view.fill(kite, with: .color(Color(hex: 0xD8261C)))
        }
        // You.
        let mx = xOf(here) + dx / 2, my = base - hOf(here) + dy / 2
        view.stroke(Path { $0.move(to: CGPoint(x: mx, y: my - 12)); $0.addLine(to: CGPoint(x: mx, y: my - 60)) }, with: .color(Self.yellow), lineWidth: 2)
        let dot = Path(ellipseIn: CGRect(x: mx - 9, y: my - 15, width: 18, height: 18))
        view.fill(dot, with: .color(Self.yellow))
        view.stroke(dot, with: .color(Color(hex: 0x0B1A33)), lineWidth: 2.5)
    }
}

// MARK: - G. Tarmac

/// G. Tarmac — the road from the saddle, running away up the screen at your real speed (D111): centre dashes,
/// the next kilometre painted on the road, chevrons in the verge on climbs (one per percent), and a horizon that
/// drops as the road climbs. Over the last 500 m of a categorised climb the road fills with the fans' paint.
struct TarmacFace: View {
    let d: FaceData
    let dark: Bool
    let animate: Bool
    var style: FaceStyle = .default(.tarmac)

    @State private var clock = MotionClock()
    @Environment(\.faceWidth) private var canvasWidth

    private static let paint = Color(hex: 0xF4F4F0)
    private static let yellow = Color(hex: 0xF2C230)

    private var climbing: Bool { d.grade > 1.5 }

    var body: some View {
        let kmFont = FaceFont.font(style.family(.barlow), 120, weight: 700)
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animate)) { timeline in
                Canvas { ctx, size in draw(&ctx, size, date: timeline.date, kmFont: kmFont) }
            }
            // The numbers cast the shadow, not the road: a shadow over the 60 fps canvas is a full-screen offscreen
            // pass every frame, invisible over an opaque road anyway.
            Group {
            VStack(alignment: .leading, spacing: 18) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.barlow), 250, weight: 600)).lineLimit(1).minimumScaleFactor(0.5).scaleEffect(x: 1, y: 1.12, anchor: .bottomLeading)
                    .frame(height: 200)
                Text(style.heroLabel(d, speed: d.speedUnit).uppercased()).font(FaceFont.font(style.family(.barlow), 18, weight: 600)).tracking(18 * 0.34)
            }
            .at(64, 150)
            HStack(spacing: 48) {
                cell(d.powerI, "WATTS", size: 92)
                cell(d.cadenceText, "RPM", size: 92)
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 64).at(0, 150)
            HStack(alignment: .bottom) {
                HStack(spacing: 56) {
                    cell(d.elapsedText, "ELAPSED", size: 72, trailing: false)
                    cell(d.remainingClock, "TO GO", size: 72, trailing: false)
                }
                Spacer()
                HStack(spacing: 56) {
                    cell(d.gradeText, "GRADE", size: 72, ink: climbing ? Self.yellow : Self.paint)
                    cell(d.gearText, "GEAR", size: 72)
                }
            }
            .padding(.horizontal, 64)
            .at(0, 520)
            }
            .shadow(color: .black.opacity(0.45), radius: 6)
        }
        .foregroundStyle(Self.paint)
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
    }

    private func cell(_ v: String, _ l: String, size: CGFloat, ink: Color = paint, trailing: Bool = true) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            Text(v).font(FaceFont.font(style.family(.barlow), size, weight: 600)).foregroundStyle(ink).frame(height: size * 0.9)
            Text(l).font(FaceFont.font(style.family(.barlow), 16, weight: 600)).tracking(16 * 0.3)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, date: Date, kmFont: Font) {
        let W = size.width, H = size.height
        let dt = clock.tick(date)
        // Your position on the road, advanced at your speed and eased back to the ride's distance.
        let riding = d.state == .riding
        clock.value += riding ? d.speedKph / 3.6 * dt : 0
        clock.value += (d.distanceM - clock.value) * min(1, dt * 1.5)
        if abs(d.distanceM - clock.value) > 200 { clock.value = d.distanceM }
        let dist = clock.value

        // The road seen from the saddle, running away up the screen (D111). A climb lowers the horizon, so the
        // road rises ahead of you; a descent lifts it.
        clock.value2 += ((min(max(d.grade, -8), 12)) - clock.value2) * min(1, dt * 2)
        let horizon = CGFloat(230 - clock.value2 * 9)
        let z0 = 7.0, halfW0 = 340.0, cx = W / 2
        let y = { (z: Double) in horizon + (H - horizon) * CGFloat(z0 / (z + z0)) }
        let hw = { (z: Double) in CGFloat(halfW0 * z0 / (z + z0)) }
        let far = 3000.0

        // Sky, with a far ridge on the horizon.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: horizon + 1)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0x0B0F14), Color(hex: dark ? 0x27303A : 0x3E4A56)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: horizon))
        var rx = 0.0
        var rng = SeededRandom(11)
        while rx <= Double(W) {
            ridge.addLine(to: CGPoint(x: rx, y: Double(horizon) - 14 - rng.next() * 34))
            rx += 60
        }
        ridge.addLine(to: CGPoint(x: W, y: horizon))
        ridge.closeSubpath()
        ctx.fill(ridge, with: .color(Color(hex: 0x161B21)))

        // Verge: grass on the flat, rock on climbs, in bands that sweep past at your speed.
        let verge = climbing ? Color(hex: dark ? 0x4A4843 : 0x6E6A62) : Color(hex: dark ? 0x2B3A24 : 0x3F5A2E)
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: W, height: H - horizon)), with: .color(verge))
        let band = 24.0
        var z = band - dist.truncatingRemainder(dividingBy: band) - band
        while z < 400 {
            if z + band / 2 > 0 {
                let a = y(max(z, 0)), b = y(z + band / 2)
                ctx.fill(Path(CGRect(x: 0, y: b, width: W, height: a - b)), with: .color(.black.opacity(0.1)))
            }
            z += band
        }

        // The road: asphalt between two edge lines, narrowing to the horizon.
        var road = Path()
        road.move(to: CGPoint(x: cx - halfW0, y: H))
        road.addLine(to: CGPoint(x: cx + halfW0, y: H))
        road.addLine(to: CGPoint(x: cx + hw(far), y: y(far)))
        road.addLine(to: CGPoint(x: cx - hw(far), y: y(far)))
        road.closeSubpath()
        ctx.drawLayer { layer in
            layer.clip(to: road)
            // The texture is drawn at the design size and tiled across a wider canvas, rather than stretched.
            let tile = AsphaltTexture.size
            var x: CGFloat = 0
            while x < size.width {
                layer.draw(Image(uiImage: AsphaltTexture.image(dark: dark)), in: CGRect(x: x, y: 0, width: tile.width, height: size.height))
                x += tile.width
            }
            // Farther is hazier.
            layer.fill(Path(CGRect(x: 0, y: horizon, width: W, height: (H - horizon) * 0.35)),
                       with: .linearGradient(Gradient(colors: [Color(hex: 0x27303A, opacity: 0.55), .clear]),
                                             startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: horizon + (H - horizon) * 0.35)))
        }
        for side: CGFloat in [-1, 1] {
            var edge = Path()
            edge.move(to: CGPoint(x: cx + side * halfW0 * 0.92, y: H))
            edge.addLine(to: CGPoint(x: cx + side * hw(far) * 0.92, y: y(far)))
            edge.addLine(to: CGPoint(x: cx + side * hw(far) * 0.88, y: y(far)))
            edge.addLine(to: CGPoint(x: cx + side * halfW0 * 0.88, y: H))
            edge.closeSubpath()
            ctx.fill(edge, with: .color(Self.paint.opacity(0.7)))
        }

        /// A patch lying on the road: across from u0 to u1 (−1…1 of the half-width), along from z1 to z2 metres.
        func patch(u0: Double, u1: Double, z1: Double, z2: Double) -> Path {
            let a = max(z1, 0), b = max(z2, 0.01)
            var p = Path()
            p.move(to: CGPoint(x: cx + CGFloat(u0) * hw(a), y: y(a)))
            p.addLine(to: CGPoint(x: cx + CGFloat(u1) * hw(a), y: y(a)))
            p.addLine(to: CGPoint(x: cx + CGFloat(u1) * hw(b), y: y(b)))
            p.addLine(to: CGPoint(x: cx + CGFloat(u0) * hw(b), y: y(b)))
            p.closeSubpath()
            return p
        }

        // Centre dashes: 4 m painted, 8 m gap.
        let dash = 12.0
        z = dash - dist.truncatingRemainder(dividingBy: dash) - dash
        while z < 600 {
            if z + 4 > 0 { ctx.fill(patch(u0: -0.025, u1: 0.025, z1: z, z2: z + 4), with: .color(Self.paint.opacity(0.4))) }
            z += dash
        }

        // The next kilometre, painted across the road and foreshortened.
        let nextKm = (dist / 1000).rounded(.down) + 1
        let kmZ = nextKm * 1000 - dist
        if kmZ < 250 {
            let scale = CGFloat(z0 / (kmZ + z0)) * 2.2
            var mark = ctx
            mark.translateBy(x: cx, y: y(kmZ))
            mark.scaleBy(x: scale, y: scale * 0.45)
            mark.draw(Text("\(Int(nextKm)) KM").font(kmFont).foregroundStyle(Self.paint.opacity(0.35)), at: .zero, anchor: .bottom)
        }

        // Chevrons in the verge on climbs, one per percent, passing by.
        if climbing {
            let n = Int(min(max(d.grade, 0), 12).rounded())
            let gap = 9.0
            let off = dist.truncatingRemainder(dividingBy: gap)
            for i in 0..<n {
                // Kept in the distance, clear of the numbers.
                let cz = 18 + Double(i) * gap + gap - off
                let s = hw(cz) / CGFloat(halfW0) * 70
                for side: CGFloat in [-1, 1] {
                    let bx = cx + side * (hw(cz) + s * 0.9), by = y(cz)
                    var chevron = Path()
                    chevron.move(to: CGPoint(x: bx - s * 0.5, y: by))
                    chevron.addLine(to: CGPoint(x: bx, y: by - s * 0.45))
                    chevron.addLine(to: CGPoint(x: bx + s * 0.5, y: by))
                    ctx.stroke(chevron, with: .color(Self.yellow), style: StrokeStyle(lineWidth: max(1.5, s * 0.1), lineJoin: .miter))
                }
            }
        }

        // Painted road: the last 500 m of a categorised climb.
        let fan = d.climb.inClimb && d.climb.category != nil && d.climb.toSummitM < 500 ? 1.0 : 0
        if fan > 0 {
            let span = 80.0
            var paint = SeededRandom(Int(dist / span) + 3)
            let base = (dist / span).rounded(.down) * span
            for _ in 0..<30 {
                let wz = base + paint.next() * span * 2 - dist
                let u = paint.next() * 1.6 - 0.8, len = 1 + paint.next() * 3, wide = 0.05 + paint.next() * 0.2
                var brush = ctx
                brush.opacity = 0.14 + paint.next() * 0.14
                let colour = paint.next() > 0.8 ? Self.yellow : Self.paint
                if wz > 0 { brush.fill(patch(u0: u, u1: u + wide, z1: wz, z2: wz + len), with: .color(colour)) }
            }
        }
    }
}

/// The asphalt's aggregate, drawn once per theme (26,000 specks is too many to draw every frame).
@MainActor
enum AsphaltTexture {
    private static var cache: [Bool: UIImage] = [:]
    static let size = FaceCanvas.size

    static func image(dark: Bool) -> UIImage {
        if let hit = cache[dark] { return hit }
        let size = Self.size
        // 2×: fine enough for specks the canvas scales down anyway, and a third of the memory of a 3× screen.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
            let cg = r.cgContext
            cg.setFillColor(UIColor(hex: dark ? 0x1E1F21 : 0x35363A).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            var rng = SeededRandom(5)
            for _ in 0..<26_000 {
                let v = rng.next()
                let alpha = v > 0.5 ? 0.02 + rng.next() * 0.05 : 0.05 + rng.next() * 0.08
                cg.setFillColor((v > 0.5 ? UIColor.white : UIColor.black).withAlphaComponent(alpha).cgColor)
                cg.fill(CGRect(x: rng.next() * size.width, y: rng.next() * size.height, width: 1 + rng.next() * 1.6, height: 1 + rng.next() * 1.6))
            }
        }
        cache[dark] = image
        return image
    }
}
