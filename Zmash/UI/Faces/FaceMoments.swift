import SwiftUI
import ZmashKit

// MARK: - Moments

/// The moments a face can play (DESIGN.md §7), and what the gallery lets you preview.
enum FaceMoment: String, CaseIterable, Identifiable {
    case start, shift, km, summit, best, sprint, pause, finish
    /// Round 3 faces' own magic moments.
    case flying200, spinUp, flammeRouge, paintedRoad

    /// What the gallery offers for a face: the shared moments, plus the face's own magic if it has one.
    static func moments(for face: FaceID) -> [FaceMoment] {
        let shared: [FaceMoment] = [.start, .shift, .km, .summit, .best, .sprint, .pause, .finish]
        switch face {
        case .piste: return shared + [.flying200]
        case .groupset: return shared + [.spinUp]
        case .broadcast: return shared + [.flammeRouge]
        case .tarmac: return shared + [.paintedRoad]
        default: return shared
        }
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .start: "Start"
        case .shift: "Shift"
        case .km: "Kilometre"
        case .summit: "Summit"
        case .best: "Best"
        case .sprint: "Sprint"
        case .pause: "Pause"
        case .finish: "Finish"
        case .flying200: "Flying 200"
        case .spinUp: "Spin-up"
        case .flammeRouge: "Flamme rouge"
        case .paintedRoad: "Painted road"
        }
    }

}

/// What a moment is drawn in: the face's own colours. `additive` lets light add up (Night).
struct MomentInk {
    var ink: Color
    var accent: Color
    var bg: Color
    var additive = false
}

/// One visual element of a moment, drawn on the 1194×834 face canvas as a function of the moment's age (0…1).
enum MomentFX {
    /// The face rises out of a colour.
    case veil(Color)
    /// The page is printed left to right, an accent roller at its edge.
    case wipe
    /// The whole face tints briefly (peak opacity).
    case flash(Double)
    /// A ring spreads out from a point.
    case ring(CGPoint, from: CGFloat, to: CGFloat, width: CGFloat, delay: Double = 0)
    /// A soft band of light rises through the face.
    case band(thickness: CGFloat)
    /// A thin line of light crosses left to right.
    case scan
    /// Registration marks draw into the corners, as on a printed sheet.
    case corners
    /// A rubber stamp lands and fades.
    case stamp(String, CGPoint, angle: Double)
    /// Huge faint type widening behind the numbers.
    case echo(String, CGPoint, size: CGFloat)
    /// A roadside marker passes right to left.
    case post(String)
    /// Specks of light rise from a point.
    case motes(CGPoint)
    /// A horizontal flare through a line of the face.
    case lensLine(y: CGFloat)
    /// A bar grows under a value and fades.
    case underline(CGRect)
    /// The edges warm up and relax.
    case vignette

    /// Effects that don't move: the only ones kept under Calm motion or Reduce Motion (as plain fades).
    var isStill: Bool {
        switch self {
        case .flash, .corners, .underline, .stamp: true
        default: false
        }
    }
}

enum FaceMoments {
    /// How each face plays each moment. Positions are on the design canvas and follow each face's layout.
    static func effects(_ face: FaceID, _ kind: FaceTelemetry.EventKind, _ d: FaceData) -> [MomentFX] {
        let centre = CGPoint(x: FaceCanvas.size.width / 2, y: FaceCanvas.size.height / 2)
        let rider = CGPoint(x: 398, y: 690 - (d.profile.count > 20 ? d.profile[20] : 0.5) * 300 - 2)
        switch face {
        case .paper:
            // Print: ink, rules, stamps. Crisp, never glowing.
            switch kind {
            case .start: return [.wipe]
            case .shift: return [.underline(CGRect(x: 1008, y: 790, width: 130, height: 3))]
            case .km: return [.corners]
            case .summit: return [.stamp("Summit", CGPoint(x: 330, y: 640), angle: -6)]
            case .best: return [.stamp("Best · \(d.event?.n ?? 0) w", CGPoint(x: 760, y: 470), angle: -7)]
            case .sprint: return [.corners, .flash(0.07)]
            case .flying200: return []
            }
        case .aura:
            // Light in the colour field, spreading from where things happen.
            switch kind {
            case .start: return [.veil(.black)]
            case .shift: return [.ring(CGPoint(x: 990, y: 745), from: 10, to: 110, width: 2)]
            case .km: return [.band(thickness: 240)]
            case .summit: return [.flash(0.16), .motes(CGPoint(x: centre.x, y: 560))]
            case .best: return [.ring(centre, from: 260, to: 760, width: 3, delay: 0.14), .flash(0.06)]
            case .sprint: return [.vignette, .ring(centre, from: 180, to: 620, width: 4)]
            case .flying200: return []
            }
        case .night:
            // Everything is light, and light adds up.
            switch kind {
            case .start: return [.scan, .flash(0.08)]
            case .shift:
                let x = 60 + 48 + 22 + CGFloat(max(d.gear, 1) - 1) * 16 + 4.5
                return [.ring(CGPoint(x: x, y: 764), from: 4, to: 36, width: 2)]
            case .km: return [.post("\(d.event?.n ?? 0)")]
            case .summit: return [.ring(rider, from: 8, to: 260, width: 2), .motes(rider)]
            case .best: return [.lensLine(y: 250)]
            case .sprint: return [.lensLine(y: 250), .lensLine(y: 600), .flash(0.07)]
            case .flying200: return []
            }
        case .horizon:
            // The landscape: morning comes up, markers pass, the view opens at the top.
            switch kind {
            case .start: return [.veil(Color(hex: 0x0E1320))]
            case .shift: return [.ring(rider, from: 12, to: 46, width: 1.5)]
            case .km: return [.post("\(d.event?.n ?? 0)")]
            case .summit: return [.flash(0.18), .ring(rider, from: 10, to: 340, width: 2)]
            case .best: return [.motes(rider), .ring(rider, from: 12, to: 120, width: 2)]
            case .sprint: return [.ring(rider, from: 10, to: 160, width: 3), .vignette]
            case .flying200: return []
            }
        case .kinetic:
            // Type is the only graphic, so the moments are type too.
            switch kind {
            case .start: return [.echo("GO", centre, size: 470)]
            case .shift: return [.underline(CGRect(x: 1000, y: 764, width: 130, height: 4))]
            case .km: return [.echo("\(d.event?.n ?? 0)", centre, size: 560)]
            case .summit: return [.echo("TOP", centre, size: 420)]
            case .best: return [.echo("\(d.event?.n ?? 0)", centre, size: 380)]
            case .sprint: return [.flash(0.10), .corners]
            case .flying200: return []
            }
        // Round 3 faces carry their own magic in the face (the stone, the tick, the lap trail, the spin disc,
        // the kite, the painted road), so the shared layer only adds small, quiet marks.
        case .borne:
            switch kind {
            case .start: return [.wipe]
            case .shift: return [.underline(CGRect(x: 474, y: 548, width: 150, height: 3))]
            case .best: return [.flash(0.06)]
            case .sprint: return [.corners]
            case .km, .summit, .flying200: return []
            }
        case .stem:
            switch kind {
            case .start: return [.wipe]
            case .best: return [.flash(0.05)]
            case .sprint: return [.corners]
            case .shift, .km, .summit, .flying200: return []
            }
        case .piste:
            switch kind {
            case .start: return [.flash(0.08)]
            case .best: return [.flash(0.06)]
            case .sprint: return [.corners]
            case .shift, .km, .summit, .flying200: return []
            }
        case .groupset:
            switch kind {
            case .start: return [.ring(CGPoint(x: 720, y: 450), from: 150, to: 280, width: 3)]
            case .shift: return [.ring(CGPoint(x: 1052, y: 450), from: 40, to: 120, width: 2)]
            case .summit: return [.flash(0.08)]
            case .best: return [.flash(0.06)]
            case .sprint: return [.corners]
            case .km, .flying200: return []
            }
        case .broadcast:
            switch kind {
            case .start: return [.wipe]
            case .km: return [.band(thickness: 200)]
            case .summit: return [.flash(0.08)]
            case .best: return [.lensLine(y: 300)]
            case .sprint: return [.vignette]
            case .shift, .flying200: return []
            }
        case .tarmac:
            switch kind {
            case .start: return [.veil(.black)]
            case .summit: return [.flash(0.1)]
            case .best: return [.lensLine(y: 416)]
            case .sprint: return [.vignette]
            case .shift, .km, .flying200: return []
            }
        case .classic:
            return []
        }
    }
}

// MARK: - Layer

/// Plays the current moment over a face. It keeps its own 60 fps clock from the moment it first sees an event,
/// so effects stay smooth even though a live ride only publishes data at 10 Hz.
struct MomentLayer: View {
    let face: FaceID
    let data: FaceData
    let ink: MomentInk
    let calm: Bool

    @State private var playing: (id: String, kind: FaceTelemetry.EventKind, start: Date)?

    private var eventID: String? {
        guard let e = data.event, data.eventAge < 1, data.state == .riding else { return nil }
        return "\(e.kind.rawValue)·\(e.time)"
    }

    var body: some View {
        // Built here, on the main actor (fonts come from a main-actor cache); Canvas draws off it.
        let effects = playing.map { p in FaceMoments.effects(face, p.kind, data).filter { !calm || $0.isStill } } ?? []
        let fonts = MomentFonts(effects)
        let start = playing?.start
        TimelineView(.animation(minimumInterval: 1 / 60, paused: playing == nil)) { timeline in
            Canvas { ctx, size in
                guard let start else { return }
                let age = timeline.date.timeIntervalSince(start) / FaceTelemetry.eventLifetime
                guard age >= 0, age < 1 else { return }
                if ink.additive { ctx.blendMode = .plusLighter }
                for fx in effects { MomentPainter.draw(fx, age: age, ink: ink, fonts: fonts, calm: calm, in: &ctx, size: size) }
            }
        }
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: eventID, initial: true) { _, id in
            guard let id, let e = data.event, id != playing?.id else { return }
            // Joined late (face switched mid-moment): start where the moment already is.
            playing = (id, e.kind, Date.now.addingTimeInterval(-data.eventAge * FaceTelemetry.eventLifetime))
        }
        // Stop the 60 fps clock once the moment has played out.
        .task(id: playing?.id) {
            guard let p = playing else { return }
            let left = FaceTelemetry.eventLifetime - Date.now.timeIntervalSince(p.start)
            try? await Task.sleep(for: .seconds(max(0, left)))
            if playing?.id == p.id { playing = nil }
        }
    }
}

// MARK: - Drawing

/// The typefaces the current moment needs, resolved up front.
private struct MomentFonts {
    let stamp: Font
    let post: Font
    var echo: [CGFloat: Font] = [:]

    @MainActor
    init(_ effects: [MomentFX]) {
        stamp = FaceFont.font(.archivo, 34, weight: 700)
        post = FaceFont.font(.archivo, 26, weight: 600)
        for fx in effects {
            if case .echo(_, _, let size) = fx { echo[size] = FaceFont.font(.robotoFlex, size, weight: 1000, width: 150) }
        }
    }
}

private enum MomentPainter {
    /// Up fast, then down slowly: most moments.
    static func swell(_ a: Double) -> Double { a < 0.12 ? a / 0.12 : pow(1 - (a - 0.12) / 0.88, 2) }
    static func easeOut(_ a: Double) -> Double { 1 - pow(1 - min(max(a, 0), 1), 3) }

    static func draw(_ fx: MomentFX, age a: Double, ink: MomentInk, fonts: MomentFonts, calm: Bool,
                     in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        switch fx {
        case .veil(let colour):
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colour.opacity(1 - easeOut(a))))

        case .wipe:
            let x = w * easeOut(a * 1.25)
            ctx.fill(Path(CGRect(x: x, y: 0, width: w - x, height: h)), with: .color(ink.bg))
            ctx.fill(Path(CGRect(x: x - 2, y: 0, width: 3, height: h)), with: .color(ink.accent.opacity(1 - a)))

        case .flash(let peak):
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ink.accent.opacity(peak * swell(a))))

        case .ring(let c, let from, let to, let width, let delay):
            let t = max(0, (a - delay) / (1 - delay))
            guard t > 0 else { return }
            let r = from + (to - from) * easeOut(t)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(ink.accent.opacity(1 - t)), lineWidth: width * (1 - t * 0.6))

        case .band(let thickness):
            let y = h - (h + thickness) * easeOut(a)
            let rect = CGRect(x: 0, y: y, width: w, height: thickness)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [ink.ink.opacity(0), ink.ink.opacity(0.16 * swell(a)), ink.ink.opacity(0)]),
                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))

        case .scan:
            let x = -60 + (w + 120) * easeOut(a)
            let soft = CGRect(x: x - 50, y: 0, width: 100, height: h)
            ctx.fill(Path(soft), with: .linearGradient(
                Gradient(colors: [ink.accent.opacity(0), ink.accent.opacity(0.22 * (1 - a)), ink.accent.opacity(0)]),
                startPoint: CGPoint(x: soft.minX, y: 0), endPoint: CGPoint(x: soft.maxX, y: 0)))
            ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: h)), with: .color(ink.accent.opacity(1 - a)))

        case .corners:
            let inset: CGFloat = 26, length: CGFloat = 46
            let l = calm ? length : length * min(1, a / 0.22)
            let opacity = 1 - max(0, (a - 0.6) / 0.4)
            var p = Path()
            for (x, y, sx, sy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0),
                                   (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x + sx * l, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + sy * l))
            }
            ctx.stroke(p, with: .color(ink.accent.opacity(opacity)), lineWidth: 2)

        case .stamp(let text, let c, let angle):
            let landed = calm ? 1 : easeOut(a / 0.2)
            var layer = ctx
            layer.opacity = swell(a) * 0.9
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .degrees(angle))
            layer.scaleBy(x: 1.35 - 0.35 * landed, y: 1.35 - 0.35 * landed)
            let label = layer.resolve(Text(text.uppercased())
                .font(fonts.stamp).tracking(34 * 0.2)
                .foregroundStyle(ink.accent))
            let s = label.measure(in: CGSize(width: 1000, height: 200))
            let box = CGRect(x: -s.width / 2 - 22, y: -s.height / 2 - 12, width: s.width + 44, height: s.height + 24)
            layer.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(ink.accent), lineWidth: 3)
            layer.draw(label, at: .zero, anchor: .center)

        case .echo(let text, let c, let size):
            var layer = ctx
            layer.opacity = 0.16 * swell(a)
            layer.translateBy(x: c.x, y: c.y)
            let grow = 0.9 + 0.28 * easeOut(a)
            layer.scaleBy(x: grow, y: grow)
            let t = layer.resolve(Text(text).font(fonts.echo[size] ?? .system(size: size, weight: .black))
                .foregroundStyle(ink.ink))
            layer.draw(t, at: .zero, anchor: .center)

        case .post(let text):
            let x = w + 40 - (w + 140) * a
            let fade = min(1, min(a, 1 - a) * 8)
            var layer = ctx
            layer.opacity = fade
            layer.fill(Path(CGRect(x: x - 2, y: 560, width: 4, height: 150)), with: .color(ink.ink.opacity(0.85)))
            let plate = CGRect(x: x - 34, y: 520, width: 68, height: 44)
            layer.fill(Path(roundedRect: plate, cornerRadius: 4), with: .color(ink.ink.opacity(0.9)))
            let label = layer.resolve(Text(text).font(fonts.post).foregroundStyle(ink.bg))
            layer.draw(label, at: CGPoint(x: plate.midX, y: plate.midY), anchor: .center)

        case .motes(let c):
            for i in 0..<16 {
                let seed = Double((i * 37) % 16) / 16
                let x = c.x + CGFloat(i - 8) * 13 + CGFloat(sin(Double(i) * 1.7)) * 10
                let rise = 260 * easeOut(a) * (0.55 + 0.45 * seed)
                let r = 2.5 + 2 * seed
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: c.y - rise - r, width: 2 * r, height: 2 * r)),
                         with: .color(ink.accent.opacity(swell(a) * (0.5 + 0.5 * seed))))
            }

        case .lensLine(let y):
            let halo = CGRect(x: 0, y: y - 14, width: w, height: 28)
            let centre = w * (0.35 + 0.3 * a)
            ctx.fill(Path(halo), with: .radialGradient(
                Gradient(colors: [ink.accent.opacity(0.35 * swell(a)), ink.accent.opacity(0)]),
                center: CGPoint(x: centre, y: y), startRadius: 0, endRadius: w * 0.55))
            ctx.fill(Path(CGRect(x: 0, y: y - 1, width: w, height: 2)), with: .linearGradient(
                Gradient(colors: [ink.accent.opacity(0), ink.accent.opacity(swell(a)), ink.accent.opacity(0)]),
                startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: w, y: y)))

        case .underline(let rect):
            let grown = calm ? rect.width : rect.width * easeOut(a / 0.25)
            ctx.fill(Path(CGRect(x: rect.maxX - grown, y: rect.minY, width: grown, height: rect.height)),
                     with: .color(ink.accent.opacity(swell(a))))

        case .vignette:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [ink.accent.opacity(0), ink.accent.opacity(0.38 * swell(a))]),
                center: CGPoint(x: w / 2, y: h / 2), startRadius: h * 0.34, endRadius: w * 0.72))
        }
    }
}
