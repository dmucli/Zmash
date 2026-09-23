import SwiftData
import SwiftUI
import ZmashKit

/// What to ride today: one suggestion from how fresh you are and what you've ridden lately, with a line of why.
/// "Ride this" sets up the ride; "Something else" shows the next suggestion; × hides the card until tomorrow.
struct TodayCard: View {
    /// Applies a suggestion to the home screen's plan.
    let choose: (SessionPlan) -> Void
    @Environment(Preferences.self) private var prefs
    @AppStorage("today.hidden") private var hiddenOn = ""
    @State private var today: Today?
    @State private var index = 0

    var body: some View {
        if hiddenOn != Self.dayKey(.now), let today, !today.picks.isEmpty {
            let pick = today.picks[index % today.picks.count]
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(today.reason).textCase(.uppercase)
                        .font(.system(size: 12, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Design.Palette.secondary)
                    Text(pick.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Design.Palette.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        Text(detail(pick)).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        if let level = pick.difficulty {
                            DifficultyGauge(level: level, compact: true)
                            Text(Difficulty.label(level)).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Today: \(pick.title). \(today.reason).")

                if today.picks.count > 1 {
                    iconButton("dices", label: "Something else") {
                        withAnimation(.snappy(duration: 0.25)) { index += 1 }
                    }
                }
                Button { choose(plan(for: pick)) } label: {
                    Text("Ride this").font(Design.Font.label).foregroundStyle(Design.Palette.background)
                        .padding(.horizontal, 20).frame(minHeight: 44)
                        .background(Capsule().fill(Design.Palette.primary))
                }
                .buttonStyle(.plain)
                iconButton("x", label: "Hide until tomorrow") {
                    withAnimation(.snappy(duration: 0.25)) { hiddenOn = Self.dayKey(.now) }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
            .contentTransition(.opacity)
        } else {
            Color.clear.frame(height: 0)
                .task { if today == nil { today = Today.compute(prefs: prefs) } }
        }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 18).foregroundStyle(Design.Palette.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Design.Palette.background))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func detail(_ c: Suggestions.Candidate) -> String {
        let length = c.minutes > 60 ? "\(c.minutes / 60) h \(String(format: "%02d", c.minutes % 60))" : "\(c.minutes) min"
        switch c.kind {
        case .workout: return "\(length) · workout"
        // A climb's time is an estimate at your pace; the others are what you set.
        case .route: return "≈ \(length) at your pace · climb"
        case .free: return "\(length) · free ride"
        }
    }

    private func plan(for c: Suggestions.Candidate) -> SessionPlan { Today.plan(for: c, prefs: prefs) }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

/// Today's suggestions and why, worked out once when home appears.
struct Today {
    let reason: String
    let picks: [Suggestions.Candidate]

    /// The home plan for a suggestion.
    @MainActor
    static func plan(for c: Suggestions.Candidate, prefs: Preferences) -> SessionPlan {
        var p = prefs.lastPlan
        switch c.kind {
        case .workout:
            p.routeID = nil
            p.workoutID = c.id
        case .route:
            p.workoutID = nil
            p.routeID = c.id
        case .free:
            p.workoutID = nil
            p.routeID = nil
            p.plannedMinutes = c.minutes
            p.terrainMode = .auto
            p.drawn = false
            p.terrainType = .rolling
            p.effort = .easy
        }
        return p
    }

    /// An easy spin on rolling roads, for tired legs or a first ride.
    static func easySpin(_ minutes: Int) -> Suggestions.Candidate {
        .init(id: "free/easy-\(minutes)", kind: .free, title: "Easy spin on rolling roads", minutes: minutes, bands: [.recover, .maintain],
              difficulty: 1)
    }

    @MainActor
    static func compute(prefs: Preferences, now: Date = .now) -> Today {
        let since = Calendar.current.date(byAdding: .day, value: -120, to: now)!
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.startedAt >= since },
                                             sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let rides = (try? RideStore.context.fetch(d)) ?? []
        guard !rides.isEmpty else {
            return Today(reason: prefs.suggestRampTest ? "Find your FTP" : "First ride?", picks: rampTest(prefs) + [easySpin(30)])
        }
        let state = Readiness.state(rides.map { ($0.startedAt, $0.tss ?? 0) }, on: now)
        let band = Readiness.Band.of(state.form)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let recent = Set(rides.filter { $0.startedAt >= weekAgo }.flatMap { r in
            [r.workoutID, r.routeID.map { RouteStore.split($0).base }].compactMap { $0 }
        })
        let usual = Suggestions.usualMinutes(rides.prefix(10).map(\.activeSeconds))
        let picks = Suggestions.pick(candidates(prefs: prefs, usual: usual), band: band, usualMinutes: usual, ridden: recent,
                                     firsts: planSession() + rampTest(prefs) + campaignStage(usual: usual))
        let form = Int(state.form.rounded())
        return Today(reason: "\(band.reason) · form \(form > 0 ? "+" : "")\(form)", picks: picks)
    }

    /// Today's session on the plan you're on.
    @MainActor
    private static func planSession() -> [Suggestions.Candidate] {
        guard let e = PlanStore.current, let slot = PlanStore.today(e),
              let session = PlanStore.session(e, week: slot.week, index: slot.index) else { return [] }
        let title = "Plan · " + PlanStore.name(session)
        if case .route(let id) = session {
            return [Suggestions.Candidate(id: id, kind: .route, title: title, minutes: PlanStore.minutes(session), bands: [])]
        }
        let id = PlanStore.workoutID(e, week: slot.week, index: slot.index)
        let w = PlanStore.workout(id: id)
        return [Suggestions.Candidate(id: id, kind: .workout, title: title, minutes: PlanStore.minutes(session), bands: [],
                                      difficulty: w.map { Difficulty.workout(tss: $0.estimatedLoad(ftp: Double(Preferences.shared.ftp)).tss) })]
    }

    /// The next stage of the campaign in progress: its finale, as long as you usually ride (or all of it if shorter).
    @MainActor
    private static func campaignStage(usual: Int) -> [Suggestions.Candidate] {
        guard let c = CampaignStore.current, let race = CampaignStore.race(c), let stage = CampaignStore.nextStage(c) else { return [] }
        let route = race.route(stage)
        let stats = RouteStats.of(route)
        let seconds = Double(max(usual, 30) * 60)
        let base = race.routeID(stage)
        let whole = stats.estimatedSeconds <= seconds * 1.1
        let id = whole ? base : RouteStore.segmentID(base, fromM: stats.timing.latestStart(for: seconds), toM: stats.distanceM)
        let minutes = Int(((whole ? stats.estimatedSeconds : seconds) / 60).rounded())
        return [Suggestions.Candidate(id: id, kind: .route, title: "\(race.name) · stage \(stage.number)" + (whole ? "" : ", the finale"),
                                      minutes: minutes, bands: [], difficulty: Difficulty.route(route, estimatedSeconds: min(stats.estimatedSeconds, seconds)))]
    }

    /// A ramp test first, when FTP was a guess at setup.
    @MainActor
    private static func rampTest(_ prefs: Preferences) -> [Suggestions.Candidate] {
        guard prefs.suggestRampTest else { return [] }
        let w = WorkoutLibrary.rampTest
        return [Suggestions.Candidate(id: w.id, kind: .workout, title: w.name, minutes: 20, bands: [.push], difficulty: 4)]
    }

    /// Everything that could be suggested: the workouts, the famous climbs at your pace, and an easy spin.
    @MainActor
    private static func candidates(prefs: Preferences, usual: Int) -> [Suggestions.Candidate] {
        let workouts = WorkoutStore.all.map { w in
            Suggestions.Candidate(id: w.id, kind: .workout, title: w.name,
                                  minutes: w.isRampTest ? 20 : w.duration / 60, bands: w.suitsBands,
                                  difficulty: w.isRampTest ? 4 : Difficulty.workout(tss: w.estimatedLoad(ftp: Double(prefs.ftp)).tss))
        }
        let climbs = RaceStore.climbs.map { c in
            let route = c.route
            let seconds = RouteStats.of(route, prefs: prefs).estimatedSeconds
            let minutes = Int((seconds / 60).rounded())
            // Steep climbs are for fresh legs; gentler ones do for an ordinary day too.
            let bands: Set<Readiness.Band> = route.averageGrade >= 6 ? [.push] : [.maintain, .push]
            return Suggestions.Candidate(id: c.id, kind: .route, title: "\(c.name) · \(c.side)", minutes: max(minutes, 5), bands: bands,
                                         difficulty: Difficulty.route(route, estimatedSeconds: seconds))
        }
        return workouts + climbs + [easySpin(min(max(usual, 30), 60) / 15 * 15)]
    }
}
