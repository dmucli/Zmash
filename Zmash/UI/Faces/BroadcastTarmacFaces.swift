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

    private static let navy = Color(hex: 0x0A1A36)
    private static let yellow = Color(hex: 0xFFD23F)
    private static let soft = Color(hex: 0xC9D4E8)

    var body: some View {
        let flagFont = FaceFont.font(.barlow, 14, weight: 700)
        let tickFont = FaceFont.font(.barlow, 15, weight: 700)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x132B52), Color(hex: 0x0B1A33)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, _ in drawProfile(&ctx, flagFont: flagFont, tickFont: tickFont) }

            HStack(spacing: 10) {
                Circle().fill(Self.yellow).frame(width: 10, height: 10)
                Text("LIVE").font(FaceFont.font(.barlow, 18, weight: 700)).tracking(18 * 0.24)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Self.navy)
            .at(44, 36)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(toGo.value).font(FaceFont.font(.barlow, 64, weight: 700)).foregroundStyle(Self.yellow)
                Text(toGo.unit).font(FaceFont.font(.barlow, 18, weight: 700)).tracking(18 * 0.2).foregroundStyle(.white)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Self.navy)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 44)
            .at(0, 36)

            VStack(alignment: .leading, spacing: 10) {
                Text(d.speed1).font(FaceFont.font(.barlow, 200, weight: 700, slant: -10)).foregroundStyle(.white).frame(height: 172)
                Text("\(d.speedUnit.uppercased()) · GEAR \(d.gearText)").font(FaceFont.font(.barlow, 18, weight: 700))
                    .tracking(18 * 0.24).foregroundStyle(Self.soft)
            }
            .at(52, 108)

            telemetry
                .frame(height: 104)
                .padding(.horizontal, 44)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 36)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
    }

    /// Kilometres to go on a known road (metres in the last one); otherwise time to go, or time ridden.
    private var toGo: (value: String, unit: String) {
        if !d.course.isEmpty {
            let left = max(0, d.courseKm - d.roadKm) * 1000
            if left < 1000 { return ("\(Int(left.rounded()))", d.units == .metric ? "M TO GO" : "YD TO GO") }
            return (String(format: "%.1f", d.units.distance(left)), "\(d.distUnit.uppercased()) TO GO")
        }
        if let remaining = d.remaining { return (TimeFormat.clock(Int(remaining)), "TO GO") }
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
            Text(value).font(FaceFont.font(.barlow, 62, weight: 700)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            if let unit { Text(unit).font(FaceFont.font(.barlow, 18, weight: 700)).tracking(18 * 0.16).foregroundStyle(Self.soft) }
        }
        .padding(.leading, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x22375E)).frame(width: 1) }
    }

    private func drawProfile(_ ctx: inout GraphicsContext, flagFont: Font, tickFont: Font) {
        let L = d.roadLengthKm
        let profile = d.wholeProfile
        let here = d.roadKm
        let k0 = here - 3.5, k1 = here + 8.5, x0: CGFloat = 40, x1: CGFloat = 1154
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
            view.translateBy(x: 597, y: 450); view.rotate(by: .radians(-tilt)); view.translateBy(x: -597, y: -450)
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

/// G. Tarmac — a mountain road from above, scrolling under you at your real speed: centre dashes, painted
/// kilometre markers, chevrons in the verge on climbs (one per percent). Over the last 500 m of a categorised
/// climb the road fills with the fans' paint.
struct TarmacFace: View {
    let d: FaceData
    let dark: Bool
    let animate: Bool
    var style: FaceStyle = .default(.tarmac)

    @State private var clock = MotionClock()

    private static let paint = Color(hex: 0xF4F4F0)
    private static let yellow = Color(hex: 0xF2C230)

    private var climbing: Bool { d.grade > 1.5 }

    var body: some View {
        let kmFont = FaceFont.font(.barlow, 120, weight: 700)
        ZStack(alignment: .topLeading) {
            Image(uiImage: AsphaltTexture.image(dark: dark)).resizable()
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animate)) { timeline in
                Canvas { ctx, size in draw(&ctx, size, date: timeline.date, kmFont: kmFont) }
            }
            VStack(alignment: .leading, spacing: 18) {
                Text(d.speed1).font(FaceFont.font(.barlow, 250, weight: 600)).scaleEffect(x: 1, y: 1.12, anchor: .bottomLeading)
                    .frame(height: 200)
                Text(d.speedUnit.uppercased()).font(FaceFont.font(.barlow, 18, weight: 600)).tracking(18 * 0.34)
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
                    cell(d.remaining.map { TimeFormat.clock(Int($0)) } ?? "—", "TO GO", size: 72, trailing: false)
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
        .foregroundStyle(Self.paint)
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
    }

    private func cell(_ v: String, _ l: String, size: CGFloat, ink: Color = paint, trailing: Bool = true) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            Text(v).font(FaceFont.font(.barlow, size, weight: 600)).foregroundStyle(ink).frame(height: size * 0.9)
            Text(l).font(FaceFont.font(.barlow, 16, weight: 600)).tracking(16 * 0.3)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, date: Date, kmFont: Font) {
        let W = size.width
        let dt = clock.tick(date)
        let pxPerM = 12.0
        // Your position on the road, advanced at your speed and eased back to the ride's distance.
        let riding = d.state == .riding
        clock.value += riding ? d.speedKph / 3.6 * dt : 0
        clock.value += (d.distanceM - clock.value) * min(1, dt * 1.5)
        if abs(d.distanceM - clock.value) > 200 { clock.value = d.distanceM }
        let road = clock.value * pxPerM

        let verge = climbing ? Color(hex: dark ? 0x4A4843 : 0x7B776E) : Color(hex: dark ? 0x2B3A24 : 0x4F6B3A)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: 96)), with: .color(verge))
        ctx.fill(Path(CGRect(x: 0, y: 738, width: W, height: 96)), with: .color(verge))
        ctx.fill(Path(CGRect(x: 0, y: 108, width: W, height: 5)), with: .color(Self.paint.opacity(0.75)))
        ctx.fill(Path(CGRect(x: 0, y: 721, width: W, height: 5)), with: .color(Self.paint.opacity(0.75)))

        // Centre dashes.
        let spacing = 150.0, offset = road.truncatingRemainder(dividingBy: spacing)
        var x = -offset
        while x < W {
            ctx.fill(Path(CGRect(x: x, y: 412, width: 80, height: 8)), with: .color(Self.paint.opacity(0.26)))
            x += spacing
        }
        // Painted kilometre markers, and hectometre ticks in the verge.
        let dm = clock.value
        var hm = (dm / 100).rounded(.down)
        while hm <= (dm / 100).rounded(.down) + 2 {
            let px = 200 + (hm * 100 - dm) * pxPerM
            if px > -300, px < W + 300 {
                if Int(hm) % 10 == 0 {
                    var mark = ctx
                    mark.translateBy(x: px, y: 380)
                    mark.scaleBy(x: 1, y: 1.4)
                    mark.draw(Text("\(Int(hm / 10)) KM").font(kmFont).foregroundStyle(Self.paint.opacity(0.22)), at: .zero, anchor: .bottom)
                } else {
                    ctx.fill(Path(CGRect(x: px - 2, y: 128, width: 4, height: 20)), with: .color(Self.paint.opacity(0.18)))
                    ctx.fill(Path(CGRect(x: px - 2, y: 686, width: 4, height: 20)), with: .color(Self.paint.opacity(0.18)))
                }
            }
            hm += 1
        }
        // Chevrons in the verge on climbs, one per percent.
        if climbing {
            let n = Int(min(max(d.grade, 0), 12).rounded())
            let co = (road * 0.5).truncatingRemainder(dividingBy: 90)
            for i in 0..<n {
                let cx = W - 60 - CGFloat(i) * 38 - CGFloat(co.truncatingRemainder(dividingBy: 38))
                for y: CGFloat in [48, 786] {
                    var chevron = Path()
                    chevron.move(to: CGPoint(x: cx - 10, y: y - 18)); chevron.addLine(to: CGPoint(x: cx + 8, y: y)); chevron.addLine(to: CGPoint(x: cx - 10, y: y + 18))
                    ctx.stroke(chevron, with: .color(Self.yellow), style: StrokeStyle(lineWidth: 5, lineJoin: .miter))
                }
            }
        }
        // Painted road: the last 500 m of a categorised climb.
        let fan = d.climb.inClimb && d.climb.category != nil && d.climb.toSummitM < 500 ? 1.0 : 0
        if fan > 0 {
            var rng = SeededRandom(Int(road / 400) + 3)
            for _ in 0..<26 {
                let bx = ((rng.next() * 1600 - road.truncatingRemainder(dividingBy: 1600)) + 1600).truncatingRemainder(dividingBy: 1600) - 200
                let by = 140 + rng.next() * 560, bw = 60 + rng.next() * 220, angle = rng.next() * 0.6 - 0.3
                var brush = ctx
                brush.translateBy(x: bx, y: by)
                brush.rotate(by: .radians(angle))
                brush.opacity = fan * (0.12 + rng.next() * 0.12)
                let colour = rng.next() > 0.8 ? Self.yellow : Self.paint
                brush.fill(Path(CGRect(x: 0, y: 0, width: bw, height: 6 + rng.next() * 10)), with: .color(colour))
            }
        }
    }
}

/// The asphalt's aggregate, drawn once per theme (26,000 specks is too many to draw every frame).
@MainActor
enum AsphaltTexture {
    private static var cache: [Bool: UIImage] = [:]

    static func image(dark: Bool) -> UIImage {
        if let hit = cache[dark] { return hit }
        let size = FaceCanvas.size
        let image = UIGraphicsImageRenderer(size: size).image { r in
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
