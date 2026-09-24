import Charts
import SwiftUI
import ZmashKit

/// Progress across rides (roadmap Phase 7): the power curve and personal bests, weekly load and time,
/// and an FTP estimate from the last three months.
struct TrendsView: View {
    let sessions: [RideSession]
    @Environment(Preferences.self) private var prefs
    @State private var showTable = false

    private var recentCutoff: Date { Calendar.current.date(byAdding: .day, value: -42, to: .now)! }

    private var allTime: [Int: Int] { Training.best(of: sessions.map(\.powerCurve)) }
    private var recent: [Int: Int] { Training.best(of: sessions.filter { $0.startedAt >= recentCutoff }.map(\.powerCurve)) }

    private var estimatedFTP: Int? {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        return Training.estimateFTP(curve: Training.best(of: sessions.filter { $0.startedAt >= since }.map(\.powerCurve)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                RecapLinks()
                ftpCard
                powerCurve
                WeeklyChart(title: "Weekly load", unit: "tss", weeks: weeks, value: { $0.tss })
                WeeklyChart(title: "Weekly time", unit: "hours", weeks: weeks, value: { $0.hours })
            }
            .frame(maxWidth: 720)
            .padding(Design.Space.gutter * 1.5)
            .frame(maxWidth: .infinity)
        }
        .task { RideStore.backfillTraining() }
    }

    // MARK: FTP

    private var ftpCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(prefs.ftp)").font(Design.Font.bib(56)).foregroundStyle(Design.Palette.primary)
                Text("ftp · watts").font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.1f", Double(prefs.ftp) / prefs.riderKg))
                    .font(Design.Font.bib(56)).foregroundStyle(Design.Palette.primary)
                Text("w / kg").font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
            }
            Spacer()
            if let estimate = estimatedFTP, abs(Double(estimate - prefs.ftp)) / Double(prefs.ftp) > 0.03 {
                Button {
                    prefs.ftp = estimate
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Set \(estimate) W").font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                        Text("from your best 20 min").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Design.Palette.background))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    // MARK: Power curve

    private struct CurvePoint: Identifiable {
        var id: String { series + "\(duration)" }
        let duration: Int
        let watts: Int
        let series: String
    }

    private var curvePoints: [CurvePoint] {
        let all = allTime, six = recent
        return Training.curveDurations.flatMap { d -> [CurvePoint] in
            var out: [CurvePoint] = []
            if let w = all[d] { out.append(CurvePoint(duration: d, watts: w, series: "All time")) }
            if let w = six[d] { out.append(CurvePoint(duration: d, watts: w, series: "Last 6 weeks")) }
            return out
        }
    }

    private var powerCurve: some View {
        let points = curvePoints
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Power curve").monoLabel().foregroundStyle(Design.Palette.fg2)
                Spacer()
                Segmented(options: [(false, "Chart"), (true, "Table")], selection: $showTable).frame(width: 180)
            }
            if points.isEmpty {
                Text("Ride a few times and your bests show up here.")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            } else if showTable {
                curveTable
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Duration", Training.durationLabel(p.duration)),
                             y: .value("Watts", p.watts))
                        .foregroundStyle(by: .value("Best", p.series))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Duration", Training.durationLabel(p.duration)),
                              y: .value("Watts", p.watts))
                        .foregroundStyle(by: .value("Best", p.series))
                        .symbolSize(60)
                }
                .chartForegroundStyleScale(["All time": Design.Accent.vermilion, "Last 6 weeks": Design.Accent.teamBlue])
                .chartXScale(domain: Training.curveDurations.filter { d in points.contains { $0.duration == d } }
                    .map(Training.durationLabel))
                .chartYAxisLabel("watts")
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 240)
            }
        }
        .padding(16)
        .background(CardBackground())
    }

    private var curveTable: some View {
        let all = allTime, six = recent
        return VStack(spacing: 0) {
            ForEach(Training.curveDurations.filter { all[$0] != nil }, id: \.self) { d in
                HStack {
                    Text(Training.durationLabel(d)).frame(width: 80, alignment: .leading)
                    Text(all[d].map { "\($0) W" } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                    Text(six[d].map { "\($0) W" } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Design.Font.small.monospacedDigit())
                .foregroundStyle(Design.Palette.primary)
                .padding(.vertical, 6)
                Divider().overlay(Design.Palette.hairline)
            }
            HStack {
                Text("").frame(width: 80)
                Text("all time").frame(maxWidth: .infinity, alignment: .leading)
                Text("last 6 weeks").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary).padding(.top, 6)
        }
    }

    // MARK: Weeks

    struct Week: Identifiable {
        let start: Date
        var tss: Double = 0
        var hours: Double = 0
        var id: Date { start }
    }

    private var weeks: [Week] {
        let cal = Calendar.mondayFirst
        let first = cal.date(byAdding: .weekOfYear, value: -11, to: cal.dateInterval(of: .weekOfYear, for: .now)!.start)!
        var buckets: [Date: Week] = [:]
        var d = first
        while d <= .now {
            buckets[d] = Week(start: d)
            d = cal.date(byAdding: .weekOfYear, value: 1, to: d)!
        }
        for s in sessions where s.startedAt >= first {
            guard let start = cal.dateInterval(of: .weekOfYear, for: s.startedAt)?.start, var w = buckets[start] else { continue }
            w.tss += s.tss ?? 0
            w.hours += Double(s.activeSeconds) / 3600
            buckets[start] = w
        }
        return buckets.values.sorted { $0.start < $1.start }
    }
}

private struct WeeklyChart: View {
    let title: String
    let unit: String
    let weeks: [TrendsView.Week]
    let value: (TrendsView.Week) -> Double

    var body: some View {
        let total = weeks.map(value).reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).monoLabel().foregroundStyle(Design.Palette.fg2)
                Spacer()
                Text(String(format: total < 100 ? "%.1f" : "%.0f", total) + " \(unit) in 12 weeks")
                    .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
            }
            Chart(weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value(unit, value(w)))
                    .foregroundStyle(unit == "tss" ? Design.Accent.vermilion : Design.Accent.teamBlue)
                    .cornerRadius(4)
            }
            .chartYAxisLabel(unit)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                    AxisGridLine().foregroundStyle(Design.Palette.hairline)
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(CardBackground())
    }
}
