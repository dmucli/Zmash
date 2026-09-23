import Foundation
import SwiftData
import WidgetKit
import ZmashKit

/// Keeps the widgets' summary up to date (D104): after a ride is saved and whenever home appears.
@MainActor
enum WidgetBridge {
    static func refresh(prefs: Preferences = .shared) {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -120, to: .now)!
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.startedAt >= since })
        let rides = (try? RideStore.context.fetch(d)) ?? []
        var s = WidgetSummary()
        // Monday-first week, whatever the locale's first weekday.
        var monday = cal
        monday.firstWeekday = 2
        let week = monday.dateInterval(of: .weekOfYear, for: .now)!
        for r in rides where week.contains(r.startedAt) {
            let day = (cal.component(.weekday, from: r.startedAt) + 5) % 7
            s.weekDays[day] += r.tss ?? 0
            s.weekSeconds += r.activeSeconds
            s.weekTSS += r.tss ?? 0
            s.weekRides += 1
        }
        let state = Readiness.state(rides.map { ($0.startedAt, $0.tss ?? 0) }, on: .now)
        s.form = state.form
        s.formWord = switch Readiness.Band.of(state.form) {
        case .push: "Fresh"
        case .maintain: "OK"
        case .recover: "Tired"
        }
        let today = Today.compute(prefs: prefs)
        if let pick = today.picks.first {
            s.nextTitle = pick.title
            s.nextDetail = today.reason
        }
        s.updated = .now
        guard s != WidgetSummary.load() else { return }
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
