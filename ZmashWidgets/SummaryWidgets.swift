import SwiftUI
import WidgetKit

/// One timeline for all three: the summary the app last wrote, refreshed hourly (and by the app after each ride).
struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: .now, summary: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: .now, summary: context.isPreview ? .sample : WidgetSummary.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = SummaryEntry(date: .now, summary: WidgetSummary.load() ?? WidgetSummary())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
}

private func hours(_ seconds: Int) -> String {
    String(format: "%d h %02d", seconds / 3600, seconds / 60 % 60)
}

// MARK: This week

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "zmash.week", provider: SummaryProvider()) { entry in
            WeekView(summary: entry.summary).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("Hours, training load and a bar for each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct WeekView: View {
    let summary: WidgetSummary
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week").font(.caption2.weight(.semibold))
                Text(hours(summary.weekSeconds)).font(.headline).monospacedDigit()
                Bars(values: summary.weekDays).frame(height: 14)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS WEEK").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(hours(summary.weekSeconds)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    if family == .systemMedium {
                        Text("\(Int(summary.weekTSS.rounded())) TSS · \(summary.weekRides) ride\(summary.weekRides == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Bars(values: summary.weekDays).frame(maxHeight: 54)
                HStack {
                    // The week's days are fixed: keyed by position in the week.
                    ForEach(0..<7, id: \.self) { i in
                        Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// A bar per day, Monday first; empty days show as a short stub.
private struct Bars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<values.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(values[i] > 0 ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(height: values[i] > 0 ? max(4, geo.size.height * values[i] / peak) : 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: Next up

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "zmash.next", provider: SummaryProvider()) { entry in
            NextView(summary: entry.summary).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("Today's suggestion: a plan session, your campaign's next stage, or what suits your legs.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct NextView: View {
    let summary: WidgetSummary
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(family == .accessoryRectangular ? "Next up" : "NEXT UP").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(summary.nextTitle ?? "Open Zmash to plan a ride")
                .font(family == .accessoryRectangular ? .headline : .system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(family == .accessoryRectangular ? 2 : 3)
            if family != .accessoryRectangular {
                Spacer(minLength: 0)
                if let detail = summary.nextDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Form

struct FormWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "zmash.form", provider: SummaryProvider()) { entry in
            FormView(summary: entry.summary).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Form")
        .description("How fresh you are, from your recent training load.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private struct FormView: View {
    let summary: WidgetSummary
    @Environment(\.widgetFamily) private var family

    private var number: String {
        let f = Int(summary.form.rounded())
        return (f > 0 ? "+" : "") + "\(f)"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(summary.formWord) · form \(number)")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(number).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(summary.formWord).font(.system(size: 9, weight: .medium))
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("FORM").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(summary.formWord).font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(number).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("fitness minus fatigue").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
