import SwiftData
import SwiftUI
import ZmashKit

/// What to ride today, as home's hero card (bib 01 on the bar-tape hatch): one suggestion from how fresh you are and
/// what you've ridden lately, with a line of why, its shape and its numbers. "Ride this" sets up the ride;
/// "Something else" shows the next suggestion; × hides the card until tomorrow.
struct TodayCard: View {
    /// Applies a suggestion to the home screen's plan.
    let choose: (SessionPlan) -> Void
    var compact = false
    @Environment(Preferences.self) private var prefs
    @AppStorage("today.hidden") private var hiddenOn = ""
    @State private var today: Today?
    @State private var index = 0
    /// The pick's plan, worked out once per pick (a route means loading it).
    @State private var shown: (id: String, plan: SessionPlan)?

    /// Whether the card shows today (home lays out around it).
    static var isHidden: Bool { UserDefaults.standard.string(forKey: "today.hidden") == dayKey(.now) }

    var body: some View {
        content
            // Worked out again when someone else takes the bike.
            .task(id: prefs.riderID) {
                index = 0
                today = Today.compute(prefs: prefs)
            }
    }

    @ViewBuilder private var content: some View {
        if hiddenOn != Self.dayKey(.now), let today, !today.picks.isEmpty {
            let pick = today.picks[index % today.picks.count]
            let plan = shown?.id == pick.id ? shown?.plan : nil
            VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(today.reason).monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
                        Text(pick.title)
                            .textStyle(.display, size: compact ? 28 : 40)
                            .foregroundStyle(Design.Palette.fgOnHero)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        HStack(spacing: 10) {
                            Text(detail(pick)).font(Design.Font.body).foregroundStyle(Color(hex: 0xC9C4B8))
                            if let level = pick.difficulty {
                                DifficultyGauge(level: level, compact: true)
                                Text(Difficulty.label(level)).monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Today: \(pick.title). \(today.reason).")
                    BibIndex(n: 1, size: compact ? 56 : 96, hero: true)
                }
                shape(plan)
                    .frame(maxWidth: .infinity, minHeight: compact ? 60 : 110, maxHeight: compact ? 72 : .infinity)
                // Figures beside the buttons when they fit, above them when not.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        stats(plan).fixedSize()
                        Spacer(minLength: 8)
                        buttons(today, pick)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        stats(plan).fixedSize()
                        HStack(spacing: 10) { Spacer(minLength: 0); buttons(today, pick) }
                    }
                }
                .environment(\.onTarmac, true)
            }
            .card(padding: compact ? 20 : 28, hero: true)
            .contentTransition(.opacity)
            .task(id: pick.id) { shown = (pick.id, self.plan(for: pick)) }
        } else {
            // Something for the task to hang on while today is worked out.
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder private func buttons(_ today: Today, _ pick: Suggestions.Candidate) -> some View {
                    if today.picks.count > 1 {
                        RoundIconButton(icon: "dices", size: 44) {
                            withAnimation(Design.Motion.base) { index += 1 }
                        }
                        .accessibilityLabel("Something else")
                    }
                    RoundIconButton(icon: "x", size: 44) {
                        withAnimation(Design.Motion.base) { hiddenOn = Self.dayKey(.now) }
                    }
                    .accessibilityLabel("Hide until tomorrow")
                    PillButton(title: "Ride this", icon: "play", style: .primary) { choose(self.plan(for: pick)) }
    }

    @ViewBuilder private func shape(_ plan: SessionPlan?) -> some View {
        if let w = plan?.workout {
            WorkoutStrip(workout: w.drawable)
        } else if let r = plan?.route {
            RouteStrip(route: r, color: Design.Palette.fgOnHero, fill: Design.Accent.teamBlue.opacity(0.38))
        } else {
            VStack { Spacer(); LaneDashes(color: Design.Palette.fgOnHero.opacity(0.7), thickness: 4) }
        }
    }

    @ViewBuilder private func stats(_ plan: SessionPlan?) -> some View {
        let units = prefs.units
        HStack(spacing: compact ? 16 : 26) {
            if let r = plan?.route {
                heroStat(String(format: "%.1f", units.distance(r.distanceM)), units.distanceUnit)
                heroStat(String(format: "%.0f", units.elevation(r.ascentM)), units.elevationUnit)
                if !compact { heroStat(String(format: "%.1f", r.averageGrade), "% avg") }
            } else if let w = plan?.workout, !w.isRampTest {
                heroStat(TimeFormat.clock(w.duration), "")
                heroStat("\(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))", "TSS")
            } else if let m = plan?.plannedMinutes {
                heroStat("\(m)", "min")
            }
        }
    }

    private func heroStat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(Design.Font.bib(compact ? 24 : 30)).foregroundStyle(Design.Palette.fgOnHero)
            if !unit.isEmpty { Text(unit).font(Design.Font.sans(14)).foregroundStyle(Color(hex: 0xC9C4B8)) }
        }
        .lineLimit(1)
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
        let rid = prefs.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.startedAt >= since },
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
