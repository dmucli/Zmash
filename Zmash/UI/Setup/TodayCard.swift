import SwiftData
import SwiftUI
import ZmashKit

/// What to ride today, as a slim strip above home's three ways to ride (D144): one suggestion from how fresh you are
/// and what you've ridden lately, with a line of why. "Ride this" starts it; "Something else" shows the next
/// suggestion; × hides the strip until tomorrow.
struct TodayCard: View {
    /// Rides a suggestion (home starts it, or sets it up when there's no trainer yet).
    let ride: (SessionPlan) -> Void
    var compact = false
    @Environment(Preferences.self) private var prefs
    @AppStorage("today.hidden") private var hiddenOn = ""
    @State private var today: Today?
    @State private var index = 0

    var body: some View {
        content
            // Worked out again when someone else takes the bike, and when a ride is saved or deleted.
            .task(id: "\(prefs.riderID)|\(RideChanges.shared.revision)") {
                index = 0
                today = Today.compute(prefs: prefs)
            }
    }

    @ViewBuilder private var content: some View {
        if hiddenOn != Self.hiddenKey(rider: prefs.riderID), let today, !today.picks.isEmpty {
            let pick = today.picks[index % today.picks.count]
            // On one line when it fits; the buttons under the words when not (a phone, large text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    words(today, pick)
                    buttons(today, pick)
                }
                VStack(alignment: .leading, spacing: 12) {
                    words(today, pick)
                    HStack(spacing: 10) { Spacer(minLength: 0); buttons(today, pick) }
                }
            }
            .environment(\.onTarmac, true)
            .card(padding: compact ? 14 : 16, hero: true)
            .contentTransition(.opacity)
        } else {
            // Something for the task to hang on while today is worked out.
            Color.clear.frame(height: 0)
        }
    }

    private func words(_ today: Today, _ pick: Suggestions.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Today · " + today.reason).monoLabel().foregroundStyle(Design.Palette.fgOnHero2).lineLimit(1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title(pick).fixedSize()
                    facts(pick)
                }
                VStack(alignment: .leading, spacing: 3) {
                    title(pick).lineLimit(2)
                    facts(pick)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(pick.title), \(detail(pick)). \(today.reason).")
    }

    private func title(_ pick: Suggestions.Candidate) -> some View {
        Text(pick.title).textStyle(.h2, size: compact ? 18 : 21).foregroundStyle(Design.Palette.fgOnHero)
    }

    private func facts(_ pick: Suggestions.Candidate) -> some View {
        HStack(spacing: 10) {
            Text(detail(pick)).font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fgOnHeroBody).lineLimit(1)
            if let level = pick.difficulty {
                DifficultyGauge(level: level, compact: true)
                Text(Difficulty.label(level)).monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func buttons(_ today: Today, _ pick: Suggestions.Candidate) -> some View {
        HStack(spacing: 8) {
            if today.picks.count > 1 {
                RoundIconButton(icon: "dices", size: 40) {
                    withAnimation(Design.Motion.base) { index += 1 }
                }
                .accessibilityLabel("Something else")
            }
            RoundIconButton(icon: "x", size: 40) {
                withAnimation(Design.Motion.base) { hiddenOn = Self.hiddenKey(rider: prefs.riderID) }
            }
            .accessibilityLabel("Hide until tomorrow")
            PillButton(title: "Ride this", icon: "play", style: .primary) { ride(self.plan(for: pick)) }
        }
        .fixedSize()
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

    /// Hidden for today, by this rider (someone else taking the bike still sees theirs).
    static func hiddenKey(rider: String) -> String { rider + "@" + dayKey(.now) }

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

    /// Home works out today's suggestion twice in a row (the card, and the widgets' "next up"): the second time
    /// reuses the first, for the same rider and rides, within a few seconds.
    @MainActor private static var recent: (key: String, at: Date, today: Today)?

    @MainActor
    static func compute(prefs: Preferences, now: Date = .now) -> Today {
        let key = "\(prefs.riderID)|\(RideChanges.shared.revision)"
        if let recent, recent.key == key, abs(now.timeIntervalSince(recent.at)) < 5 { return recent.today }
        let today = work(prefs: prefs, now: now)
        recent = (key, now, today)
        return today
    }

    @MainActor
    private static func work(prefs: Preferences, now: Date) -> Today {
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
