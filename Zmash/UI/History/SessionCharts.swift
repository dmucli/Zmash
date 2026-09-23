import Charts
import SwiftUI
import ZmashKit

/// Speed, watts, cadence (and heart rate when recorded) over time as small multiples on a shared time axis
/// (different units never share a y-axis). One crosshair, synced across all three.
struct SessionCharts: View {
    let samples: [RideSample]
    let units: Units

    @State private var selected: Double?
    @State private var showTable = false

    private var points: [SeriesPoint] { SampleSeries.buckets(samples, maxPoints: 300) }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: Design.Space.gutter) {
            HStack {
                Spacer()
                Segmented(options: [(false, "Chart"), (true, "Table")], selection: $showTable)
                    .frame(width: 200)
            }
            if showTable {
                SeriesTable(samples: samples, units: units)
            } else {
                let at = selected.flatMap { m in points.min { abs($0.minute - m) < abs($1.minute - m) } }
                MetricChart(title: "Speed", unit: units.speedUnit, points: points, selected: $selected, at: at,
                            value: { units.speed($0.speedKph) }, format: "%.1f")
                MetricChart(title: "Power", unit: "w", points: points, selected: $selected, at: at,
                            value: { $0.powerW }, format: "%.0f")
                MetricChart(title: "Cadence", unit: "rpm", points: points, selected: $selected, at: at,
                            value: { $0.cadenceRpm }, format: "%.0f")
                if points.contains(where: { $0.heartRateBpm != nil }) {
                    MetricChart(title: "Heart rate", unit: "bpm", points: points, selected: $selected, at: at,
                                value: { $0.heartRateBpm }, format: "%.0f")
                }
            }
        }
    }
}

private struct MetricChart: View {
    let title: String
    let unit: String
    let points: [SeriesPoint]
    @Binding var selected: Double?
    let at: SeriesPoint?
    let value: (SeriesPoint) -> Double?
    let format: String

    /// Power is effort (vermilion); cadence and speed are the ride's rhythm (team blue, ink); heart rate zone 4.
    private var color: Color {
        switch title {
        case "Power": Design.Accent.vermilion
        case "Cadence": Design.Accent.teamBlue
        case "Heart rate": Design.Zone.z4
        default: Design.Palette.fg1
        }
    }

    var body: some View {
        let values = points.compactMap(value)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        VStack(alignment: .leading, spacing: 6) {
            // Title names the single series; the readout is the crosshair value (or the average).
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Capsule().fill(color).frame(width: 12, height: 3)
                    Text(title).monoLabel().foregroundStyle(Design.Palette.fg2)
                }
                Spacer()
                if let at, let v = value(at) {
                    Text("\(String(format: format, v)) \(unit) · \(TimeFormat.clock(Int(at.minute * 60)))")
                        .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg1)
                } else {
                    Text("avg \(String(format: format, avg)) \(unit)")
                        .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                }
            }
            Chart {
                ForEach(points) { p in
                    if let v = value(p) {
                        LineMark(x: .value("Minute", p.minute), y: .value(title, v))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(color)
                    }
                }
                if let at {
                    RuleMark(x: .value("Minute", at.minute))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Design.Palette.secondary)
                    if let v = value(at) {
                        PointMark(x: .value("Minute", at.minute), y: .value(title, v))
                            .symbolSize(64)
                            .foregroundStyle(color)
                    }
                }
            }
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Design.Palette.hairline)
                    AxisValueLabel {
                        if let m = v.as(Double.self) { Text("\(Int(m))′") }
                    }
                    .font(Design.Font.mono(10))
                    .foregroundStyle(Design.Palette.fg3)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Design.Palette.hairline)
                    AxisValueLabel().font(Design.Font.mono(10)).foregroundStyle(Design.Palette.fg3)
                }
            }
            .frame(height: 120)
            .accessibilityLabel("\(title) over time, average \(String(format: format, avg)) \(unit)")
        }
    }
}

/// Per-minute table: the accessible twin of the charts.
private struct SeriesTable: View {
    let samples: [RideSample]
    let units: Units

    var body: some View {
        let rows = SampleSeries.buckets(samples, bucketSeconds: 60)
        Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                ForEach(["min", units.speedUnit, "w", "rpm", "%"], id: \.self) {
                    Text($0).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
            }
            Divider().overlay(Design.Palette.hairline)
            ForEach(rows) { r in
                GridRow {
                    Text("\(Int(r.minute))")
                    Text(String(format: "%.1f", units.speed(r.speedKph)))
                    Text(String(format: "%.0f", r.powerW))
                    Text(r.cadenceRpm.map { String(format: "%.0f", $0) } ?? "—")
                    Text(String(format: "%+.1f", r.gradePercent))
                }
                .font(Design.Font.number(15, weight: .regular))
                .foregroundStyle(Design.Palette.primary)
            }
        }
    }
}
