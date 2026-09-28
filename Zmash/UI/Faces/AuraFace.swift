import SwiftUI
import ZmashKit

/// D. Aura — no instruments: a living colour field that is your effort, one enormous number floating in it.
struct AuraFace: View {
    let d: FaceData
    let dark: Bool
    let calm: Bool
    var style: FaceStyle = .default(.aura)
    @Environment(\.faceWidth) private var canvasWidth

    static func background(dark: Bool, style: FaceStyle = .default(.aura)) -> Color {
        style.palette(.aura).bg(dark: dark)
    }

    var body: some View {
        let palette = style.palette(.aura)
        let ink = palette.ink(dark: dark)
        let z = d.zone
        let gradeInk = d.climbing ? palette.accent(dark: dark) : ink
        let breath = calm ? 1 : 1 + 0.018 * sin(d.crankDegrees * .pi / 180) * min(1.6, d.powerW / d.ftp)
        let weight = 300 + min(1, d.powerW / (d.ftp * 1.6)) * 600

        ZStack {
            Color.clear.overlay {
                // No blur: the blobs are soft radial gradients already, and blurring a 1.36× full-screen canvas on
                // every tick cost more than it showed.
                AuraMesh(zone: z, dark: dark, style: style)
                    .scaleEffect(breath)
                    .animation(.linear(duration: 0.9), value: z)
            }

            VStack(spacing: 0) {
                // Its % of FTP swaps with the big number when that's % of FTP (D161).
                let ftp = style.small(.ftpPercent, d, "\(Int((d.powerW / d.ftp * 100).rounded()))%", "ftp")
                Text("\(PowerZones.name(z)) · \(ftp.value) \(ftp.label)")
                    .faceLabel(style.family(.outfit), 16, tracking: 0.46).opacity(0.75).lineLimit(1)
                    .padding(.bottom, 4)
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(style.heroValue(d, speed: d.speed0))
                        .font(FaceFont.font(style.family(.outfit), 300, weight: weight))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .tracking(-0.03 * 300)
                        .frame(height: 258)
                        .heroTap()
                    Text(style.heroLabel(d, speed: d.speedUnit)).font(FaceFont.font(style.family(.outfit), 58, weight: 500)).opacity(0.8)
                }
                Capsule().fill(dark ? Color.white.opacity(0.22) : Color(hex: 0x14141A, opacity: 0.18))
                    .frame(width: 520, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.85))
                            .frame(width: 520 * min(1, d.powerW / d.ftp * 0.66))
                            .animation(.linear(duration: 0.4), value: d.powerW)
                    }
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .top, spacing: 0) {
                ForEach(style.slotItems(.aura)) { slot in
                    let metric = slot.metric
                    stat(metric.value(d), metric.short(d), metric.tintsWhenClimbing && d.climbing ? gradeInk : ink)
                }
            }
            .padding(.horizontal, 56)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 44)

            // Magic moment: a new session best blooms outwards from the number.
            if d.isEvent(.best) {
                let size = 240 + d.eventAge * 620
                Circle().stroke(ink, lineWidth: 2)
                    .frame(width: size, height: size)
                    .opacity(1 - d.eventAge)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(ink)
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
        .background(Self.background(dark: dark, style: style))
        .clipped()
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(FaceFont.font(style.family(.outfit), 64, weight: 500)).foregroundStyle(color)
            Text(label).faceLabel(style.family(.outfit), 15, tracking: 0.26).opacity(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The design's four radial blobs in the current, next and previous zone colours over the base tone.
/// Drawn 36 % larger than the canvas (CSS `inset: -18%`) so breathing never shows an edge.
private struct AuraMesh: View {
    let zone: Int
    let dark: Bool
    var style: FaceStyle = .default(.aura)
    @Environment(\.faceWidth) private var canvasWidth

    var body: some View {
        let ramp = style.palette(.aura).mesh
        let a = ZoneColors.color(zone, ramp: ramp), b = ZoneColors.color(zone + 1, ramp: ramp),
            c = ZoneColors.color(zone - 1, ramp: ramp)
        let fade = dark ? 0.70 : 0.60
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AuraFace.background(dark: dark, style: style)))
            // (color, centre x%, centre y%, radius x%, radius y%) — CSS radial-gradient(Rx Ry at X Y, c 0%, transparent fade)
            let blobs: [(Color, Double, Double, Double, Double)] = [
                (a, 0.22, 0.30, 0.60, 0.55), (b, 0.78, 0.26, 0.55, 0.60),
                (c, 0.62, 0.82, 0.70, 0.60), (b, 0.12, 0.86, 0.50, 0.50),
            ]
            for (color, x, y, rx, ry) in blobs.reversed() {
                let r = rx * size.width
                var layer = ctx
                layer.translateBy(x: x * size.width, y: y * size.height)
                layer.scaleBy(x: 1, y: (ry * size.height) / r)
                layer.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                           with: .radialGradient(Gradient(stops: [.init(color: color, location: 0),
                                                                  .init(color: color.opacity(0), location: fade)]),
                                                 center: .zero, startRadius: 0, endRadius: r))
            }
        }
        .frame(width: canvasWidth * 1.36, height: FaceCanvas.size.height * 1.36)
    }
}
