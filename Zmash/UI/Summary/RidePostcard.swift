import SwiftUI
import ZmashKit

/// A shareable card of a finished ride, as a design-system hero card: bone on the bar-tape hatch, bib numerals,
/// the tri-stripe across the top.
struct RidePostcard: View {
    let startedAt: Date
    let summary: SessionSummary
    let samples: [RideSample]
    let units: Units
    var title: String?
    var tss: Double?

    static let size = CGSize(width: 1200, height: 1320)
    private let bone = Design.Tarmac.bone
    private let bone2 = Design.Tarmac.bone2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TriStripe(height: 14, mid: bone)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Wordmark(size: 56, color: bone)
                    Spacer()
                    mono(startedAt.formatted(date: .abbreviated, time: .shortened), 26)
                }
                if let title {
                    Text(title).font(Design.Font.sans(52, weight: 700)).tracking(52 * -0.02)
                        .foregroundStyle(bone).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 44)
                }
                mono("Moving time", 24).padding(.top, title == nil ? 48 : 30)
                Text(TimeFormat.clock(summary.activeSeconds))
                    .font(Design.Font.bib(230))
                    .foregroundStyle(Design.Accent.vermilion)

                // A flat indoor ride has no skyline worth drawing: show the power trace instead.
                Group {
                    if summary.elevationGainM >= 10 {
                        ElevationStrip(grades: profileGrades, color: bone, fill: Design.Accent.teamBlue.opacity(0.38))
                    } else {
                        PowerTrace(watts: samples.map(\.powerW), color: bone.opacity(0.85))
                    }
                }
                .frame(height: 180)
                .padding(.top, 30)
                mono((summary.elevationGainM >= 10 ? "Elevation" : "Power") + " · \(TimeFormat.clock(summary.activeSeconds))", 20)
                    .padding(.top, 10)
                rule.padding(.top, 18)

                let cells = stats
                VStack(spacing: 0) {
                    ForEach(0..<((cells.count + 2) / 3), id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { col in
                                let i = row * 3 + col
                                VStack(alignment: .leading, spacing: 4) {
                                    if i < cells.count {
                                        mono(cells[i].1, 20)
                                        Text(cells[i].0).font(Design.Font.bib(88)).foregroundStyle(bone)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 22)
                        if row < (cells.count + 2) / 3 - 1 { rule }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(70)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(HatchFill(raised: false))
        .environment(\.colorScheme, .dark)
    }

    private var rule: some View { Rectangle().fill(Design.Tarmac.t700).frame(height: 2) }

    private func mono(_ text: String, _ size: CGFloat) -> some View {
        Text(text).font(Design.Font.mono(size)).tracking(size * 0.14).textCase(.uppercase).foregroundStyle(bone2)
    }

    private var profileGrades: [Double] {
        let g = samples.map(\.gradePercent)
        guard g.count > 2 else { return [0, 0] }
        return stride(from: 0, to: g.count, by: max(1, g.count / 240)).map { g[$0] }
    }

    private var stats: [(String, String)] {
        var out: [(String, String)] = [
            (String(format: "%.1f", units.distance(summary.distanceM)), units.distanceUnit),
            ("\(summary.avgPowerW)", "avg watts"),
            (String(format: "%.0f", units.elevation(summary.elevationGainM)), units.elevationUnit + " climbed"),
            (String(format: "%.1f", units.speed(summary.avgSpeedKph)), "avg " + units.speedUnit),
            ("\(summary.maxPowerW)", "max watts"),
            (String(format: "%.0f", summary.kcal), "kcal"),
        ]
        if let tss { out.append(("\(Int(tss.rounded()))", "tss")) }
        if let hr = summary.avgHeartRateBpm { out.append(("\(hr)", "avg bpm")) }
        out.append(("\(summary.avgCadenceRpm)", "avg rpm"))
        return out
    }
}

@MainActor
enum PostcardRenderer {
    /// Renders the card to a PNG in the temporary directory, for the share sheet.
    static func write(_ card: some View, name: String) -> URL? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}


/// Watts over the ride as a filled trace, with the average as a hairline.
private struct PowerTrace: View {
    let watts: [Int]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard watts.count > 2 else { return }
            let step = max(1, watts.count / 300)
            let series = stride(from: 0, to: watts.count, by: step).map { Double(watts[$0]) }
            let peak = max(series.max() ?? 1, 1)
            let x = { (i: Int) in size.width * Double(i) / Double(max(series.count - 1, 1)) }
            let y = { (w: Double) in size.height * (1 - w / peak * 0.92) }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, w) in series.enumerated() { path.addLine(to: CGPoint(x: x(i), y: y(w))) }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.18)))
            var line = Path()
            for (i, w) in series.enumerated() {
                let p = CGPoint(x: x(i), y: y(w))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            ctx.stroke(line, with: .color(color), lineWidth: 2)
            let avg = series.reduce(0, +) / Double(series.count)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(avg))); $0.addLine(to: CGPoint(x: size.width, y: y(avg))) },
                       with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        }
    }
}
