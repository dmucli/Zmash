import SwiftUI
import ZmashKit

/// A shareable card of a finished ride, set like the Paper face: ink on warm paper.
struct RidePostcard: View {
    let startedAt: Date
    let summary: SessionSummary
    let samples: [RideSample]
    let units: Units
    var title: String?
    var tss: Double?

    static let size = CGSize(width: 1200, height: 1320)
    private let paper = Color(hex: 0xF2EFE8)
    private let ink = Color(hex: 0x141414)
    private let accent = Color(hex: 0xC8341B)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ZMASH").font(FaceFont.font(.archivo, 34, weight: 600)).tracking(34 * 0.3)
                Spacer()
                Text(startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FaceFont.font(.archivo, 26, weight: 450)).tracking(26 * 0.1)
            }
            .foregroundStyle(ink)
            rule.padding(.top, 22)

            if let title {
                Text(title.uppercased())
                    .font(FaceFont.font(.archivo, 28, weight: 500)).tracking(28 * 0.2)
                    .foregroundStyle(accent)
                    .padding(.top, 34)
            }

            Text(TimeFormat.clock(summary.activeSeconds))
                .font(FaceFont.font(.archivo, 210, weight: 300))
                .foregroundStyle(ink)
                .padding(.top, title == nil ? 40 : 6)
            Text("MOVING TIME")
                .font(FaceFont.font(.archivo, 22, weight: 500)).tracking(22 * 0.28)
                .foregroundStyle(ink.opacity(0.5))

            // A flat indoor ride has no skyline worth drawing: show the power trace instead.
            Group {
                if summary.elevationGainM >= 10 {
                    ElevationStrip(grades: profileGrades, color: ink.opacity(0.75))
                } else {
                    PowerTrace(watts: samples.map(\.powerW), color: ink.opacity(0.75))
                }
            }
            .frame(height: 190)
            .padding(.top, 40)
            Text((summary.elevationGainM >= 10 ? "ELEVATION" : "POWER") + " · \(TimeFormat.clock(summary.activeSeconds))")
                .font(FaceFont.font(.archivo, 18, weight: 500)).tracking(18 * 0.26)
                .foregroundStyle(ink.opacity(0.4))
                .padding(.top, 8)
            rule.padding(.top, 18)

            let cells = stats
            VStack(spacing: 0) {
                ForEach(0..<((cells.count + 2) / 3), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            let i = row * 3 + col
                            VStack(alignment: .leading, spacing: 2) {
                                if i < cells.count {
                                    Text(cells[i].0).font(FaceFont.font(.archivo, 74, weight: 400)).foregroundStyle(ink)
                                    Text(cells[i].1.uppercased())
                                        .font(FaceFont.font(.archivo, 20, weight: 500)).tracking(20 * 0.24)
                                        .foregroundStyle(ink.opacity(0.5))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 26)
                    if row < (cells.count + 2) / 3 - 1 { rule }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(70)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(paper)
    }

    private var rule: some View { Rectangle().fill(ink.opacity(0.25)).frame(height: 1) }

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
    static func write(_ card: RidePostcard, name: String) -> URL? {
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
