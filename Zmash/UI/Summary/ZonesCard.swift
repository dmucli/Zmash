import SwiftUI
import ZmashKit

/// Where a ride's effort went (D140): a stacked bar of time in each power zone, and in each heart-rate zone when the
/// ride has heart rate and a maximum is set, with the minutes underneath.
struct ZonesCard: View {
    let entry: ZoneStore.Entry

    static let powerColors: [Color] = [Design.Zone.z1, Design.Zone.z2, Design.Zone.z3, Design.Zone.z4, Design.Zone.z5,
                                       Design.Zone.z6, Color(hex: 0x7E1A12)]
    static let heartColors: [Color] = [Design.Zone.z1, Design.Zone.z2, Design.Zone.z3, Design.Zone.z4, Design.Zone.z5]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Time in zones")
            row("Power", seconds: entry.power, names: PowerZones.names, colors: Self.powerColors)
            if let heart = entry.heart {
                row("Heart rate", seconds: heart, names: Zones.heartNames, colors: Self.heartColors)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 22)
    }

    private func row(_ title: String, seconds: [Int], names: [String], colors: [Color]) -> some View {
        let total = max(seconds.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(seconds.indices, id: \.self) { i in
                        if seconds[i] > 0 {
                            Rectangle().fill(colors[i])
                                .frame(width: max(2, (geo.size.width - 12) * CGFloat(seconds[i]) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(seconds.indices, id: \.self) { i in
                    if seconds[i] >= 30 {
                        HStack(spacing: 8) {
                            Circle().fill(colors[i]).frame(width: 8, height: 8)
                            Text(names[i]).font(Design.Font.small).foregroundStyle(Design.Palette.fg2)
                            Spacer(minLength: 4)
                            Text(Self.minutes(seconds[i])).font(Design.Font.number(15)).foregroundStyle(Design.Palette.fg1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    static func minutes(_ s: Int) -> String {
        s >= 3600 ? "\(s / 3600) h \(String(format: "%02d", s / 60 % 60))" : "\(Int((Double(s) / 60).rounded())) min"
    }
}
