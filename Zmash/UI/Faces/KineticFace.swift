import SwiftUI
import ZmashKit

/// F. Kinetic — type is the only graphic: power drives weight, speed drives width, grade drives slant.
struct KineticFace: View {
    let d: FaceData
    let dark: Bool

    static func palette(dark: Bool) -> (bg: Color, ink: Color) {
        dark ? (Color(hex: 0x0B0B0C), Color(hex: 0xF4F3F0)) : (Color(hex: 0xFBFAF7), Color(hex: 0x111112))
    }

    var body: some View {
        let p = Self.palette(dark: dark)
        let sprint = d.sprint
        let weight = sprint ? 1000 : 200 + min(1, d.powerW / (d.ftp * 1.5)) * 640
        let cadWeight = 200 + min(1, d.cadenceRpm / 120) * 500
        let width = sprint ? 128 : 62 + min(1, d.speedKph / 52) * 54
        let slant = max(-10, min(0, -d.grade * 1.3))
        let accent = sprint ? (dark ? Color(hex: 0xFF6B4A) : Color(hex: 0xC8341B)) : p.ink
        let gradeInk = d.climbing ? (dark ? Color(hex: 0xFF6B4A) : Color(hex: 0xC8341B)) : p.ink
        let gearWeight: Double = d.isEvent(.shift) ? 900 : 420

        VStack(spacing: 0) {
            HStack {
                Text("Kinetic")
                Spacer()
                Text("weight ∝ power · width ∝ speed · slant ∝ grade")
            }
            .font(FaceFont.font(.robotoFlex, 15, weight: 500)).tracking(15 * 0.3).textCase(.uppercase).opacity(0.78)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 0) {
                numeral(d.speed0, weight: weight, width: width, slant: slant).foregroundStyle(accent)
                    .frame(width: 400, height: 270, alignment: .bottomLeading)
                numeral(d.powerI, weight: weight, width: width, slant: slant)
                    .frame(width: 400, height: 270, alignment: .bottomLeading)
                numeral(d.cadenceText, weight: cadWeight, width: width, slant: slant)
                    .frame(maxWidth: .infinity, maxHeight: 270, alignment: .bottomTrailing)
            }
            .frame(height: 270)
            .clipped()
            .animation(.easeOut(duration: 0.25), value: sprint)

            HStack(spacing: 0) {
                Text(d.speedUnit).frame(width: 400, alignment: .leading)
                Text("watts").frame(width: 400, alignment: .leading)
                Text("rpm").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(FaceFont.font(.robotoFlex, 17, weight: 500)).tracking(17 * 0.3).textCase(.uppercase).opacity(0.78)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                cell(d.elapsedText, "elapsed", color: p.ink)
                cell(d.remainingText, "remaining", color: p.ink)
                cell(d.distText, d.distUnit, color: p.ink)
                cell(d.gradeText, "grade", color: gradeInk)
                cell(d.gearText, "gear", color: p.ink, weight: gearWeight, trailing: true)
            }
            .padding(.top, 20)
            .overlay(alignment: .top) { Rectangle().fill(p.ink).frame(height: 1) }
        }
        .foregroundStyle(p.ink)
        .padding(EdgeInsets(top: 60, leading: 64, bottom: 60, trailing: 64))
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg)
    }

    private func numeral(_ s: String, weight: Double, width: Double, slant: Double) -> some View {
        Text(s)
            .font(FaceFont.font(.robotoFlex, 196, weight: weight, width: width, slant: slant))
            .lineLimit(1)
            .fixedSize()
    }

    private func cell(_ value: String, _ label: String, color: Color, weight: Double = 420, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(value).font(FaceFont.font(.robotoFlex, 60, weight: weight)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(FaceFont.font(.robotoFlex, 14, weight: 500)).tracking(14 * 0.24).textCase(.uppercase).opacity(0.78)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}
