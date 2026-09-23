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
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Metric(value: "\(s.powerW)", unit: "W")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockText(state: s).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
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
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("\(s.powerW) W").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            } compactTrailing: {
                ClockText(state: s).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Text("\(s.powerW)").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
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
                Text(state.finished ? "Ride done · " + title : title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if state.paused, !state.finished { Text("Paused").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange) }
            }
            .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                Metric(value: "\(state.powerW)", unit: "W")
                VStack(alignment: .leading, spacing: 0) {
                    ClockText(state: state).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(state.toGo ?? "time").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
                Metric(value: state.gear, unit: "gear")
                Metric(value: String(format: "%+.1f", state.gradePercent), unit: "%")
                if let hr = state.heartRateBpm { Metric(value: "\(hr)", unit: "bpm") }
            }
            if let step = state.step {
                Text(step + (state.targetW.map { " · target \($0) W" } ?? "")).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct Metric: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
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
