import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ZmashWidgets: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
        WeekWidget()
        NextUpWidget()
        FormWidget()
    }
}

/// The ride on the lock screen and in the Dynamic Island (D103).
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenRide(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(Brand.tarmac)
                .activitySystemActionForegroundColor(Brand.bone)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Metric(value: "\(s.powerW)", unit: "W")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockText(state: s).font(Brand.mono(24))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title).lineLimit(1)
                        Spacer()
                        if let step = s.step {
                            Text(step + (s.targetW.map { " · \($0) W" } ?? "")).lineLimit(1)
                        } else {
                            Text(String(format: "%+.1f %% · gear %@", s.gradePercent, s.gear))
                        }
                    }
                    .font(Brand.mono(13)).foregroundStyle(Brand.bone2)
                }
            } compactLeading: {
                Text("\(s.powerW) W").font(Brand.bib(17)).foregroundStyle(Brand.vermilion)
            } compactTrailing: {
                ClockText(state: s).font(Brand.mono(14))
                    .frame(maxWidth: 52)
            } minimal: {
                Text("\(s.powerW)").font(Brand.bib(16)).foregroundStyle(Brand.vermilion)
            }
        }
    }
}

private struct LockScreenRide: View {
    let title: String
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.finished ? "Ride done · " + title : title).brandLabel(12).lineLimit(1)
                Spacer()
                if state.paused, !state.finished { Text("Paused").brandLabel(12).foregroundStyle(Brand.caution) }
            }
            .foregroundStyle(Brand.bone2)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                Metric(value: "\(state.powerW)", unit: "W", lit: true)
                VStack(alignment: .leading, spacing: 2) {
                    ClockText(state: state).font(Brand.mono(26))
                    Text(state.toGo ?? "time").brandLabel(10).foregroundStyle(Brand.bone2)
                }
                Metric(value: state.gear, unit: "gear")
                Metric(value: String(format: "%+.1f", state.gradePercent), unit: "%")
                if let hr = state.heartRateBpm { Metric(value: "\(hr)", unit: "bpm") }
            }
            if let step = state.step {
                Text(step + (state.targetW.map { " · hold \($0) W" } ?? "")).font(Brand.mono(13))
                    .foregroundStyle(Brand.bone2)
            }
        }
        .foregroundStyle(Brand.bone)
        .padding(16)
    }
}

private struct Metric: View {
    let value: String
    let unit: String
    var lit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Brand.bib(36)).foregroundStyle(lit ? Brand.vermilion : Brand.bone)
            Text(unit).brandLabel(10).foregroundStyle(Brand.bone2)
        }
    }
}

/// The ride clock: counting by itself while riding, fixed while paused or done.
private struct ClockText: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.paused || state.finished {
            Text(Duration.seconds(state.elapsed).formatted(.time(pattern: state.elapsed >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        } else {
            Text(timerInterval: state.clockStart...Date.distantFuture, countsDown: false)
        }
    }
}
