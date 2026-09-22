import SwiftUI
import ZmashKit

/// A. Paper — a printed race programme: rigorous grid, hairline rules, ink on warm paper.
struct PaperFace: View {
    let d: FaceData
    let dark: Bool

    static func palette(dark: Bool) -> (bg: Color, ink: Color, ac: Color) {
        dark ? (Color(hex: 0x16151A), Color(hex: 0xEDEAE2), Color(hex: 0xFF6B4A))
             : (Color(hex: 0xF2EFE8), Color(hex: 0x141414), Color(hex: 0xC8341B))
    }

    var body: some View {
        let p = Self.palette(dark: dark)
        let ink = p.ink
        VStack(alignment: .leading, spacing: 0) {
            // Column heads
            HStack(spacing: 0) {
                head("01 — Speed").frame(maxWidth: .infinity, alignment: .leading)
                head("02 — Power").padding(.leading, 26).frame(width: 268, alignment: .leading)
                head("03 — Cadence").padding(.leading, 26).frame(width: 268, alignment: .leading)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1.5) }

            // Primary numbers
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.speed1)
                        .font(FaceFont.font(.archivo, 252, weight: 500))
                        .tracking(-0.04 * 252)
                        .frame(height: 212)
                    Text(d.speedUnitLong).faceLabel(.archivo, 19, tracking: 0.22).opacity(0.78).padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                column(d.powerI, "watts", "3s avg", d.power3Text, ink: ink)
                column(d.cadenceText, "rpm", "heart", d.hrText, ink: ink)
            }
            .padding(.top, 6)

            // Secondary row
            HStack(spacing: 0) {
                cell("Elapsed", d.elapsedText)
                cell("Remaining", d.remainingText)
                cell("Distance", d.distText)
                cell("Climbed", d.climbedText)
                cell("Energy", d.kcalText)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
            .padding(.top, 22)

            Spacer(minLength: 18)

            // Terrain + gear
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<56, id: \.self) { i in
                            let g = d.profile[Int((Double(i) / 55 * Double(d.profile.count - 1)).rounded())]
                            Rectangle().fill(ink).frame(width: 9, height: 10 + g * 146).opacity(i < 3 ? 1 : 0.4)
                        }
                    }
                    .frame(height: 158, alignment: .bottom)
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text("Grade now").faceLabel(.archivo, 14, tracking: 0.18).opacity(0.78)
                        Text(d.gradeText).font(FaceFont.font(.archivo, 46, weight: 500))
                            .foregroundStyle(d.climbing ? p.ac : ink)
                        Text("Next five minutes").faceLabel(.archivo, 14, tracking: 0.18).opacity(0.78)
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 1) }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(1...d.gearCount, id: \.self) { i in
                            let on = i == d.gear
                            Rectangle().fill(on ? p.ac : ink)
                                .frame(width: 6, height: on ? 98 : (i % 4 == 0 ? 52 : 30))
                                .opacity(on ? 1 : 0.3)
                        }
                    }
                    .frame(height: 100, alignment: .bottom)
                    .animation(.snappy(duration: 0.2), value: d.gear)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Gear").faceLabel(.archivo, 14, tracking: 0.18).opacity(0.78)
                        Spacer()
                        Text(d.gearText).font(FaceFont.font(.archivo, 46, weight: 500))
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 1) }
                    .padding(.top, 12)
                }
                .frame(width: 360)
            }
        }
        .foregroundStyle(ink)
        .padding(EdgeInsets(top: 48, leading: 56, bottom: 40, trailing: 56))
        .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
        .background(p.bg)
    }

    private func head(_ s: String) -> some View {
        Text(s).faceLabel(.archivo, 16, tracking: 0.18).opacity(0.78)
    }

    private func column(_ value: String, _ unit: String, _ label: String, _ second: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(FaceFont.font(.archivo, 112, weight: 400)).frame(height: 112)
            Text(unit).faceLabel(.archivo, 16, tracking: 0.2).opacity(0.78).padding(.top, 2)
            Text(label).faceLabel(.archivo, 15, tracking: 0.18).opacity(0.78).padding(.top, 26)
            Text(second).font(FaceFont.font(.archivo, 58, weight: 300))
        }
        .padding(.leading, 26)
        .frame(width: 268, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(ink).frame(width: 1) }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).faceLabel(.archivo, 14, tracking: 0.18).opacity(0.78)
            Text(value).font(FaceFont.font(.archivo, 60, weight: 400)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
