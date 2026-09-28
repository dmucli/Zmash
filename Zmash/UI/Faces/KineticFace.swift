import SwiftUI
import ZmashKit

/// F. Kinetic — type is the only graphic: power drives weight, speed drives width, grade drives slant.
struct KineticFace: View {
    let d: FaceData
    let dark: Bool
    var style: FaceStyle = .default(.kinetic)
    @Environment(\.faceWidth) private var canvasWidth

    static func palette(dark: Bool, style: FaceStyle = .default(.kinetic)) -> (bg: Color, ink: Color, ac: Color) {
        let p = style.palette(.kinetic)
        return (p.bg(dark: dark), p.ink(dark: dark), p.accent(dark: dark))
    }

    var body: some View {
        let p = Self.palette(dark: dark, style: style)
        // The type follows the ride in steps (D165): weight by power zone, width by 5 km/h, the cadence numeral by
        // 10 rpm, slant by whole percent of grade; all from the calm numbers.
        let sprint = d.shownSprint
        let weight = sprint ? 1000 : 200 + min(1, d.zoneShare / 1.5) * 640
        let cadWeight = 200 + min(1, (d.shownCadence / 10).rounded() * 10 / 120) * 500
        let width = sprint ? 128 : 62 + min(1, (d.shownSpeedKph / 5).rounded() * 5 / 52) * 54
        let slant = max(-10, min(0, -d.shownGrade.rounded() * 1.3))
        let accent = sprint ? p.ac : p.ink
        let gradeInk = d.climbing ? p.ac : p.ink
        let gearWeight: Double = d.isEvent(.shift) ? 900 : 420
        // The first two numerals take 3/8 of the row each (400 pt at the design width), the third the rest.
        let column = (canvasWidth - 128) * 0.375
        // The big number swaps with the numeral that showed it (D161).
        let power = style.small(.power, d, d.powerI, "watts"), cadence = style.small(.cadence, d, d.cadenceText, "rpm")

        VStack(spacing: 0) {
            HStack {
                Text("Kinetic")
                Spacer()
                Text("weight ∝ power · width ∝ speed · slant ∝ grade")
            }
            .font(FaceFont.font(style.family(.robotoFlex), 15, weight: 500)).tracking(15 * 0.3).textCase(.uppercase).opacity(0.78)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 0) {
                numeral(style.heroValue(d, speed: d.speed0), weight: weight, width: width, slant: slant).foregroundStyle(accent)
                    .frame(width: column, height: 270, alignment: .bottomLeading)
                    .heroTap()
                numeral(power.value, weight: weight, width: width, slant: slant)
                    .frame(width: column, height: 270, alignment: .bottomLeading)
                numeral(cadence.value, weight: cadWeight, width: width, slant: slant)
                    .frame(maxWidth: .infinity, maxHeight: 270, alignment: .bottomTrailing)
            }
            .frame(height: 270)
            .clipped()
            .animation(.easeOut(duration: 0.25), value: sprint)

            HStack(spacing: 0) {
                Text(style.heroLabel(d, speed: d.speedUnit)).frame(width: column, alignment: .leading)
                Text(power.label).frame(width: column, alignment: .leading)
                Text(cadence.label).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(FaceFont.font(style.family(.robotoFlex), 17, weight: 500)).tracking(17 * 0.3).textCase(.uppercase).opacity(0.78)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                let slots = style.slotItems(.kinetic)
                ForEach(slots) { slot in
                    let metric = slot.metric
                    cell(metric.value(d), metric.short(d),
                         color: metric.tintsWhenClimbing && d.climbing ? gradeInk : p.ink,
                         weight: metric == .gear ? gearWeight : 420,
                         trailing: slot.id == slots.count - 1,
                         width: (canvasWidth - 128) / CGFloat(max(slots.count, 1)))
                }
            }
            .padding(.top, 20)
            .overlay(alignment: .top) { Rectangle().fill(p.ink).frame(height: 1) }
        }
        .foregroundStyle(p.ink)
        .padding(EdgeInsets(top: 60, leading: 64, bottom: 60, trailing: 64))
        .frame(width: canvasWidth, height: FaceCanvas.size.height)
        .background(p.bg)
    }

    private func numeral(_ s: String, weight: Double, width: Double, slant: Double) -> some View {
        Text(s)
            .font(FaceFont.font(style.family(.robotoFlex), 196, weight: weight, width: width, slant: slant))
            // Shrinks to its column (a sprint's four digits at full width, an hour-long clock) rather than spill over.
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    /// An equal share of the row, with a gap, so a long value (an hour-plus countdown) shrinks instead of overlapping.
    private func cell(_ value: String, _ label: String, color: Color, weight: Double = 420, trailing: Bool = false,
                      width: CGFloat) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(value).font(FaceFont.font(style.family(.robotoFlex), 60, weight: weight)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 70, alignment: .bottom)
            Text(label).font(FaceFont.font(style.family(.robotoFlex), 14, weight: 500)).tracking(14 * 0.24).textCase(.uppercase).opacity(0.78)
        }
        .frame(width: width - 28, alignment: trailing ? .trailing : .leading)
        .frame(width: width, alignment: trailing ? .trailing : .leading)
    }
}
