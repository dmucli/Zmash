import SwiftUI
import ZmashKit

// MARK: - A. Borne

/// A. Borne — the kilometre stone of the great climbs: distance to the summit, metres still to climb,
/// the grade of the next kilometre. On the flat it points to the next col; at the top it becomes the summit sign.
struct BorneFace: View {
    let d: FaceData
    let dark: Bool
    var style: FaceStyle = .default(.borne)

    /// 1 → the stone is sliding in (passing a kilometre), 0 → standing.
    @State private var slide: Double = 0

    private enum Stone { case flat, climb, summit }

    private var stone: Stone {
        if d.isEvent(.summit) || d.climb.summit { return .summit }
        return d.climb.inClimb ? .climb : .flat
    }

    var body: some View {
        let p = style.palette(.borne)
        let ink = p.ink(dark: dark), sub = ink.opacity(dark ? 0.66 : 0.72)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in drawScene(&ctx, size) }
            left(ink: ink, sub: sub).at(56, 60)
            stoneText
                .frame(width: 340)
                .at(770, 64)
                .offset(x: slide * 180)
                .opacity(1 - slide)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg(dark: dark))
        // Passing a kilometre: the next stone slides in, like riding past one.
        .onChange(of: kmEvent) { _, id in
            guard id != nil else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { slide = 1 }
            Task { @MainActor in withAnimation(.easeOut(duration: 0.45)) { slide = 0 } }
        }
    }

    private var kmEvent: Double? { d.event?.kind == .km ? d.event?.time : nil }

    private func left(ink: Color, sub: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.barlow), 210, weight: 700)).lineLimit(1).minimumScaleFactor(0.5).tracking(-2).foregroundStyle(ink)
                .frame(height: 176)
            Text(style.heroLabel(d, speed: d.speedUnit)).font(FaceFont.font(style.family(.barlow), 15)).tracking(15 * 0.32).textCase(.uppercase)
                .foregroundStyle(sub).padding(.top, 14)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 30) {
                GridRow {
                    R3Cell(value: d.powerI, label: "watts", size: 64, ink: ink, sub: sub).frame(width: 181, alignment: .leading)
                    R3Cell(value: d.cadenceText, label: "rpm", size: 64, ink: ink, sub: sub).frame(width: 181, alignment: .leading)
                    R3Cell(value: d.gradeText, label: "grade", size: 64, ink: ink, sub: sub).frame(width: 181, alignment: .leading)
                }
                GridRow {
                    R3Cell(value: d.elapsedText, label: "elapsed", size: 64, ink: ink, sub: sub)
                    R3Cell(value: d.remainingClock, label: "remaining", size: 64, ink: ink, sub: sub)
                    R3Cell(value: d.gearText, label: "gear", size: 64, ink: ink, sub: sub)
                }
            }
            .padding(.top, 46)
        }
    }

    // What the stone says, in French and in metric as on the real ones (whatever the app's units).
    private var stoneLines: (cap: String, top: String, big: String, unit: String, l2: String, l2label: String, l3: String, l3label: String) {
        let c = d.climb
        func cat(_ k: Climb.Category?) -> String { k.map { $0 == .hc ? "HC" : "CAT \($0.rawValue)" } ?? "" }
        switch stone {
        case .summit:
            return ("SOMMET", cat(c.lastCategory ?? c.category), "+\(Int(c.lastGainM.rounded()))", "M",
                    d.elapsedText, "temps", "\(Int(d.climbedM.rounded())) m", "dénivelé total")
        case .climb:
            return (cat(c.category), "SOMMET", String(format: "%.1f", c.toSummitM / 1000), "KM",
                    "+\(Int(c.leftM.rounded())) m", "à gravir", String(format: "%.1f %%", c.nextKmGrade), "pente km suivant")
        case .flat:
            if let next = c.nextInM {
                return (c.nextCategory.map { cat($0) } ?? "PLAT", "PROCHAIN COL", String(format: "%.1f", next / 1000), "KM",
                        String(format: "%.1f %%", c.nextAverageGrade), "pente moyenne",
                        String(format: "%.1f km", c.nextLengthM / 1000), "longueur")
            }
            // No climb ahead (or no known road): what has been climbed so far.
            return ("PLAT", "DÉNIVELÉ", "\(Int(d.climbedM.rounded()))", "M", d.elapsedText, "temps",
                    String(format: "%.1f km", d.distanceM / 1000), "distance")
        }
    }

    private var capColor: Color {
        switch stone {
        case .summit: return Color(hex: 0x141414)
        case .climb: return d.climb.category?.capColor ?? Color(hex: 0x9A968C)
        case .flat: return d.climb.nextCategory?.capColor ?? Color(hex: 0x9A968C)
        }
    }

    private var capInk: Color {
        let hc = stone == .climb ? d.climb.category == .hc : stone == .flat && d.climb.nextCategory == .hc
        return stone == .summit || hc ? .white : Color(hex: 0x141414)
    }

    private var stoneText: some View {
        let s = stoneLines
        let ink = Color(hex: 0x141414)
        return VStack(spacing: 0) {
            Text(s.cap).font(FaceFont.font(style.family(.barlow), 34, weight: 700)).tracking(34 * 0.14).foregroundStyle(capInk)
                .frame(height: 186, alignment: .bottom).padding(.bottom, 26).frame(height: 186)
            Text(s.top).font(FaceFont.font(style.family(.barlow), 24, weight: 700)).tracking(24 * 0.22).padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.big).font(FaceFont.font(style.family(.barlow), 150, weight: 700)).frame(height: 135)
                Text(s.unit).font(FaceFont.font(style.family(.barlow), 40, weight: 700))
            }
            .padding(.top, 6)
            Rectangle().fill(ink).frame(width: 236, height: 3).padding(.top, 16)
            Text(s.l2).font(FaceFont.font(style.family(.barlow), 56, weight: 700)).frame(height: 56).padding(.top, 16)
            Text(s.l2label).font(FaceFont.font(style.family(.barlow), 17, weight: 600)).tracking(17 * 0.2).textCase(.uppercase).padding(.top, 4)
            Text(s.l3).font(FaceFont.font(style.family(.barlow), 56, weight: 700)).frame(height: 56).padding(.top, 14)
            Text(s.l3label).font(FaceFont.font(style.family(.barlow), 17, weight: 600)).tracking(17 * 0.2).textCase(.uppercase).padding(.top, 4)
        }
        .foregroundStyle(ink)
        .lineLimit(1).minimumScaleFactor(0.5)
    }

    private func drawScene(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let W = size.width
        // The road verge the stone stands on.
        ctx.fill(Path(CGRect(x: 0, y: 716, width: W, height: 118)), with: .color(Color(hex: dark ? 0x121316 : 0xCFCCC3)))
        ctx.fill(Path(CGRect(x: 0, y: 764, width: W, height: 3)), with: .color(Color(hex: dark ? 0x2A2B2F : 0xF4F3EE)))
        if dark {
            // At night the stone is lit by a headlamp.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.9, opacity: 0.22), .clear]),
                center: CGPoint(x: 940, y: 420), startRadius: 60, endRadius: 520))
        }

        var stoneCtx = ctx
        stoneCtx.translateBy(x: slide * 180, y: 0)
        stoneCtx.opacity = 1 - slide
        stoneCtx.fill(Path(ellipseIn: CGRect(x: 744, y: 704, width: 400, height: 28)),
                      with: .color(dark ? .black.opacity(0.5) : Color(red: 0.24, green: 0.2, blue: 0.16, opacity: 0.18)))
        let x0: CGFloat = 770, x1: CGFloat = 1110, r: CGFloat = 170, top: CGFloat = 64, bottom: CGFloat = 716
        var shape = Path()
        shape.move(to: CGPoint(x: x0, y: bottom))
        shape.addLine(to: CGPoint(x: x0, y: top + r))
        shape.addArc(center: CGPoint(x: x0 + r, y: top + r), radius: r, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
        shape.addLine(to: CGPoint(x: x1, y: bottom))
        shape.closeSubpath()
        stoneCtx.fill(shape, with: .linearGradient(
            Gradient(colors: [Color(hex: dark ? 0xF2EFE7 : 0xFFFFFF), Color(hex: dark ? 0xCFCBC0 : 0xE6E3DA)]),
            startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
        stoneCtx.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: x0, y: top, width: x1 - x0, height: 186)), with: .color(capColor))
            layer.fill(Path(CGRect(x: x0 + (x1 - x0) * 0.7, y: top, width: (x1 - x0) * 0.3, height: bottom - top)), with: .color(.black.opacity(0.08)))
            // Weathering: chips in the paint, lichen at the foot. Seeded, so the stone never changes.
            var rng = SeededRandom(11)
            for _ in 0..<46 {
                let x = x0 + rng.next() * 340, y = top + 40 + rng.next() * 600, s = 1 + rng.next() * 3.5
                var chip = Path()
                chip.move(to: CGPoint(x: x, y: y))
                chip.addLine(to: CGPoint(x: x + s, y: y + s * 0.4))
                chip.addLine(to: CGPoint(x: x + s * 0.3, y: y + s))
                layer.fill(chip, with: .color(Color(red: 0.35, green: 0.33, blue: 0.29, opacity: 0.08 + rng.next() * 0.14)))
            }
            for _ in 0..<90 {
                let x = x0 + rng.next() * 340, y = bottom - pow(rng.next(), 2) * 90, s = 2 + rng.next() * 6
                layer.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s)),
                           with: .color(Color(red: 0.48, green: 0.53, blue: 0.36, opacity: 0.12 + rng.next() * 0.2)))
            }
        }

        // The roadside strip: the next stones coming towards you at your real speed.
        let km = d.roadKm, strip: CGFloat = 790
        let tick = Color(hex: dark ? 0x3A3B40 : 0x9C988E)
        var hm = (km * 10).rounded(.up)
        while hm < km * 10 + 60 {
            let x = 80 + (hm / 10 - km) * 200
            if x > 1150 { break }
            if Int(hm) % 10 != 0 { ctx.fill(Path(CGRect(x: x, y: strip + 14, width: 2, height: 4)), with: .color(tick)) }
            hm += 1
        }
        var k = km.rounded(.up)
        while k < km + 6 {
            let x = 80 + (k - km) * 200
            if x > 1150 { break }
            let climb = d.climbs.first { k >= $0.startKm && k <= $0.endKm }
            var post = Path()
            post.move(to: CGPoint(x: x - 9, y: strip + 20))
            post.addLine(to: CGPoint(x: x - 9, y: strip - 2))
            post.addArc(center: CGPoint(x: x, y: strip - 2), radius: 9, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            post.addLine(to: CGPoint(x: x + 9, y: strip + 20))
            ctx.fill(post, with: .color(Color(hex: dark ? 0xD9D6CD : 0xFFFFFF)))
            var cap = Path()
            cap.addArc(center: CGPoint(x: x, y: strip - 2), radius: 9, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            ctx.fill(cap, with: .color(climb?.category?.capColor ?? Color(hex: 0x9A968C)))
            k += 1
        }
    }
}

// MARK: - B. Stem card

/// B. Stem card — the profile taped to the stem: the whole ride, every categorised climb, and you on it.
/// Cresting a climb, a felt-tip tick is drawn over it in one stroke.
struct StemFace: View {
    let d: FaceData
    let dark: Bool
    var style: FaceStyle = .default(.stem)

    var body: some View {
        let p = style.palette(.stem)
        let ink = p.ink(dark: dark), sub = ink.opacity(dark ? 0.66 : 0.72), felt = p.accent(dark: false)
        let ticking = d.isEvent(.summit)
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !ticking)) { _ in
                Canvas { ctx, size in drawCard(&ctx, size, felt: felt) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(style.heroValue(d, speed: d.speed1)).font(FaceFont.font(style.family(.archivo), 196, weight: 800)).lineLimit(1).minimumScaleFactor(0.5).tracking(-196 * 0.03).foregroundStyle(ink)
                    .frame(height: 168)
                Text(style.heroLabel(d, speed: d.speedUnit)).font(FaceFont.font(style.family(.archivo), 15)).tracking(15 * 0.32).textCase(.uppercase)
                    .foregroundStyle(sub).padding(.top, 12)
            }
            .at(56, 44)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 28) {
                GridRow {
                    cell(d.powerI, "watts", ink, sub)
                    cell(d.cadenceText, "rpm", ink, sub)
                    cell(d.gradeText, "grade", ink, sub)
                }
                GridRow {
                    cell(d.elapsedText, "elapsed", ink, sub)
                    cell(d.remainingClock, "remaining", ink, sub)
                    cell(d.distText, d.course.isEmpty ? d.distUnit : String(format: "%@ of %.1f", d.distUnit, d.units.distance(d.courseKm * 1000)), ink, sub)
                }
            }
            .at(560, 52)
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg(dark: dark))
    }

    private func cell(_ v: String, _ l: String, _ ink: Color, _ sub: Color) -> some View {
        R3Cell(value: v, label: l, size: 60, weight: 700, family: .archivo, ink: ink, sub: sub).frame(width: 179, alignment: .leading)
    }

    private func drawCard(_ ctx: inout GraphicsContext, _ size: CGSize, felt: Color) {
        let print = Color(hex: 0x1B1A18)
        var card = ctx
        // The card is taped on slightly crooked.
        card.translateBy(x: 597, y: 548)
        card.rotate(by: .radians(-0.006))
        card.translateBy(x: -597, y: -548)
        let cx0: CGFloat = 44, cx1: CGFloat = 1150, cy0: CGFloat = 330, cy1: CGFloat = 772
        let cardRect = CGRect(x: cx0, y: cy0, width: cx1 - cx0, height: cy1 - cy0)
        card.fill(Path(cardRect), with: .color(Color(hex: dark ? 0xCFC9BA : 0xFBF9F3)))
        if dark {
            card.fill(Path(cardRect), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.94, blue: 0.82, opacity: 0.12), .black.opacity(0.25)]),
                center: CGPoint(x: 560, y: 520), startRadius: 50, endRadius: 720))
        }
        let px0: CGFloat = 90, px1: CGFloat = 1104, base: CGFloat = 690, height: CGFloat = 250
        let L = d.roadLengthKm
        let profile = d.wholeProfile
        let xOf = { (km: Double) in px0 + CGFloat(min(max(km / L, 0), 1)) * (px1 - px0) }
        let yOf = { (km: Double) in base - CGFloat(sampleProfile(profile, km / L)) * height }
        let pos = xOf(d.roadKm)
        // The part already ridden: a card that's been sweated on.
        card.fill(Path(CGRect(x: cx0, y: cy0, width: pos - cx0, height: cy1 - cy0)),
                  with: .color(dark ? Color(red: 0.35, green: 0.27, blue: 0.16, opacity: 0.16) : Color(red: 0.59, green: 0.47, blue: 0.27, opacity: 0.1)))
        var hill = Path()
        hill.move(to: CGPoint(x: px0, y: base))
        var x = px0
        while x <= px1 {
            hill.addLine(to: CGPoint(x: x, y: yOf(Double((x - px0) / (px1 - px0)) * L)))
            x += 3
        }
        hill.addLine(to: CGPoint(x: px1, y: base))
        hill.closeSubpath()
        card.fill(hill, with: .color(print))

        // Kilometre scale.
        card.fill(Path(CGRect(x: px0, y: base + 4, width: px1 - px0, height: 1.5)), with: .color(print))
        let unit = d.units == .metric ? 1.0 : 1.609344
        let marks = Int(L / unit)
        let every = marks > 120 ? 20 : marks > 60 ? 10 : 5
        for k in 0...max(marks, 0) {
            let px = xOf(Double(k) * unit)
            let major = k % every == 0
            if marks <= 150 || major { card.fill(Path(CGRect(x: px, y: base + 6, width: 1.5, height: major ? 12 : 6)), with: .color(print)) }
            if major {
                card.draw(Text("\(k)").font(FaceFont.font(style.family(.archivo), 15, weight: 600)).foregroundStyle(print),
                          at: CGPoint(x: px, y: base + 36), anchor: .bottom)
            }
        }

        // Climbs: category in felt tip over each summit, ticked once ridden.
        var lastX: CGFloat = -999, lift: CGFloat = 0
        var lastDone: FaceClimb?
        for climb in d.climbs {
            let sx = xOf(climb.endKm), sy = yOf(climb.endKm)
            lift = sx - lastX < 44 ? lift + 30 : 0
            lastX = sx
            card.draw(Text(climb.label).font(FaceFont.font(.marker, 26)).foregroundStyle(felt),
                      at: CGPoint(x: sx, y: sy - 22 - lift), anchor: .bottom)
            if d.roadKm > climb.endKm { lastDone = climb }
        }
        let magic = d.isEvent(.summit) ? d.eventAge : -1
        for climb in d.climbs where d.roadKm > climb.endKm && !(magic >= 0 && climb == lastDone) {
            tick(&card, at: CGPoint(x: xOf(climb.endKm), y: yOf(climb.endKm)), progress: 1, felt: felt)
        }
        if magic >= 0, let climb = lastDone ?? d.climbs.first {
            tick(&card, at: CGPoint(x: xOf(climb.endKm), y: yOf(climb.endKm)), progress: min(1, magic / 0.4), felt: felt)
        }

        // You.
        let py = yOf(d.roadKm)
        card.stroke(Path { $0.move(to: CGPoint(x: pos, y: py - 8)); $0.addLine(to: CGPoint(x: pos, y: base)) }, with: .color(felt), lineWidth: 2)
        card.fill(Path(ellipseIn: CGRect(x: pos - 9, y: py - 17, width: 18, height: 18)), with: .color(felt))
        card.fill(Path(ellipseIn: CGRect(x: pos - 3.5, y: py - 11.5, width: 7, height: 7)), with: .color(Color(hex: dark ? 0xE9E3D4 : 0xFFFFFF)))

        // Clear tape at both ends.
        for (tx, ty, angle) in [(62.0, 404.0, -1.2), (1132.0, 700.0, -1.35)] {
            var tape = ctx
            tape.translateBy(x: tx, y: ty)
            tape.rotate(by: .radians(angle))
            let rect = CGRect(x: -60, y: -24, width: 120, height: 48)
            tape.fill(Path(rect), with: .color(.white.opacity(dark ? 0.16 : 0.55)))
            tape.stroke(Path(rect), with: .color(.black.opacity(0.07)), lineWidth: 1)
            tape.fill(Path(CGRect(x: -60, y: -24, width: 120, height: 6)), with: .color(.white.opacity(0.25)))
        }
    }

    /// The felt-tip tick, drawn in one stroke over `progress` (0…1).
    private func tick(_ ctx: inout GraphicsContext, at p: CGPoint, progress: Double, felt: Color) {
        let a = CGPoint(x: p.x - 16, y: p.y - 70), b = CGPoint(x: p.x - 4, y: p.y - 56), c = CGPoint(x: p.x + 22, y: p.y - 94)
        var path = Path()
        path.move(to: a)
        if progress < 0.35 {
            let f = progress / 0.35
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        } else {
            path.addLine(to: b)
            let f = (progress - 0.35) / 0.65
            path.addLine(to: CGPoint(x: b.x + (c.x - b.x) * f, y: b.y + (c.y - b.y) * f))
        }
        ctx.stroke(path, with: .color(felt), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}
