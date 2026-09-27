import SwiftUI
import ZmashKit

/// Training plans (D148, D149, D155): Zmash's adaptive plans, then the plans in the workout catalog (Zwift's and
/// others': FTP Builder, Zwift Academy, 4wk FTP Booster…), as cards by what they're for. A Zmash plan opens in place
/// (start it on your days, or this week and Ride this); a catalog plan opens its sessions in order, one to choose and
/// start from the bar. It opens on the plan you're on.
struct PlanPage: View {
    let context: RideContext
    var compact = false
    @Environment(Preferences.self) private var prefs
    /// The Zmash plan shown in place of the grid; nil: the grid.
    @State private var open: String?
    /// The catalog plan whose sessions are shown, by collection.
    @State private var openCatalog: String?
    /// The catalog session chosen, to ride.
    @State private var session: SessionPlan?
    /// nil: every goal.
    @State private var goal: TrainingPlan.Goal?

    init(context: RideContext, compact: Bool = false) {
        self.context = context
        self.compact = compact
        var id = PlanStore.current?.planID
        var catalog: String?
        // A catalog plan's session chosen last opens that plan, on it.
        if let last = Preferences.shared.lastWorkoutID, let c = WorkoutCatalog.planCollection(of: last), id == nil {
            catalog = c
        }
        #if DEBUG
        if DebugLaunch.homeShow == "plan" { id = DebugLaunch.plan }
        if let c = UserDefaults.standard.string(forKey: "ZmashCatalogPlan") { catalog = c; id = nil }
        #endif
        _open = State(initialValue: id)
        _openCatalog = State(initialValue: catalog)
        if let catalog, let first = WorkoutCatalog.plan(catalog)?.sessions.first {
            var p = Preferences.shared.lastPlan
            p.routeID = nil
            let last = Preferences.shared.lastWorkoutID
            p.workoutID = last.flatMap { WorkoutCatalog.planCollection(of: $0) == catalog ? $0 : nil } ?? first.id
            _session = State(initialValue: p)
        }
    }

    var body: some View {
        // Follows a plan started or left, for the tags.
        let _ = PlanChanges.shared.revision
        RidePage(context: context, selection: openCatalog == nil ? nil : session.flatMap(selection), compact: compact) {
            if open != nil || openCatalog != nil {
                Chip(title: "All plans", icon: "chevron-left", selected: false) {
                    withAnimation(Design.Motion.base) {
                        open = nil
                        openCatalog = nil
                    }
                }
                if let openCatalog {
                    Text(openCatalog).textStyle(.h2, size: compact ? 18 : 22).foregroundStyle(Design.Palette.fg1).lineLimit(1)
                }
            } else {
                FilterChips(options: [(TrainingPlan.Goal?.none, "All")] + TrainingPlan.Goal.allCases.map { (Optional($0), $0.title) },
                            selection: $goal)
            }
        } tools: {
            Spacer(minLength: 0)
        } content: {
            if let plan = open.flatMap(TrainingPlans.plan) {
                PlanView(plan: plan, close: {}, embedded: true)
                    .id(plan.id)
                    .card(padding: 0)
            } else if let plan = openCatalog.flatMap(WorkoutCatalog.plan) {
                sessions(plan)
            } else {
                PickerGrid(columns: compact ? 1 : 2, rowHeight: compact ? 170 : 190, scrollTo: PlanStore.current?.planID,
                           showing: goal?.rawValue ?? "") {
                    ForEach(TrainingPlans.all.filter { goal == nil || $0.goal == goal }, id: \.id) { plan in
                        let on = PlanStore.current?.planID == plan.id
                        PickerCard(title: plan.name, meta: Self.meta(plan), selected: on,
                                   tag: on ? "You're on it" : Self.doneBefore(plan), caption: "Zmash · adapts as you ride",
                                   action: { withAnimation(Design.Motion.base) { open = plan.id } }) {
                            PlanBars(plan: plan)
                        }
                        .id(plan.id)
                    }
                    ForEach(WorkoutCatalog.plans.filter { goal == nil || $0.goal == goal }) { plan in
                        PickerCard(title: plan.collection, meta: Self.meta(plan), caption: plan.author,
                                   action: { withAnimation(Design.Motion.base) { choosePlan(plan) } }) {
                            PlanBars(minutes: plan.sessions.map { $0.seconds / 60 })
                        }
                        .id(plan.id)
                    }
                }
            }
        }
    }

    /// A catalog plan's sessions, in order, each with its week when the plan has them.
    private func sessions(_ plan: WorkoutCatalog.Plan) -> some View {
        PickerGrid(columns: compact ? 1 : 3, rowHeight: compact ? 160 : 186, scrollTo: session?.workoutID, showing: plan.collection) {
            ForEach(plan.sessions) { entry in
                let w = entry.workout
                let week = WorkoutCatalogFile.sessionOrder(entry.name).week
                let load = w.estimatedLoad(ftp: Double(prefs.ftp))
                PickerCard(title: w.name,
                           meta: (week.map { "Week \($0) · " } ?? "") + "\(TimeFormat.clock(w.duration)) · TSS \(Int(load.tss.rounded()))",
                           selected: session?.workoutID == entry.id,
                           action: { withAnimation(Design.Motion.base) { choose(entry.id) } }) {
                    WorkoutStrip(workout: w.drawable)
                }
                .id(entry.id)
            }
        }
    }

    private func choosePlan(_ plan: WorkoutCatalog.Plan) {
        openCatalog = plan.collection
        if let first = plan.sessions.first { choose(first.id) }
    }

    private func choose(_ id: String) {
        var p = session ?? prefs.lastPlan
        p.routeID = nil
        p.workoutID = id
        session = p
        prefs.lastWorkoutID = id
    }

    /// The bar for a catalog session: its figures, ERG or gradients, and Start.
    private func selection(_ p: SessionPlan) -> Selection? {
        guard let w = p.workout else { return nil }
        let erg = p.usesERG && context.hub.trainer.supportsERG
        return Selection(title: w.name,
                         meta: "\(TimeFormat.clock(w.duration)) · TSS \(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded())) · \(erg ? "ERG" : "Gradient") · FTP \(prefs.ftp) W",
                         option: AnyView(Segmented(options: [(true, "ERG"), (false, "Gradient")],
                                                   selection: Binding(get: { session?.usesERG ?? true }, set: { session?.workoutERG = $0 }))
                                            .frame(width: 200)),
                         start: {
                             prefs.lastPlan = p
                             context.start(p)
                         })
    }

    /// "29 sessions · 8 weeks · ≈ 2 h 50 a week", or "12 sessions · ≈ 11 h in all" without weeks.
    static func meta(_ plan: WorkoutCatalog.Plan) -> String {
        let total = plan.totalSeconds / 60
        func hours(_ m: Int) -> String { m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min" }
        let sessions = "\(plan.sessions.count) session\(plan.sessions.count == 1 ? "" : "s")"
        if let weeks = plan.weeks, weeks > 1 {
            return "\(sessions) · \(weeks) weeks · ≈ \(hours(total / weeks)) a week"
        }
        return "\(sessions) · ≈ \(hours(total)) in all"
    }

    /// "6 weeks · 3 rides a week · ≈ 2 h 38 a week".
    static func meta(_ plan: TrainingPlan) -> String {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        let hours = perWeek >= 60 ? "\(perWeek / 60) h \(String(format: "%02d", perWeek % 60))" : "\(perWeek) min"
        return "\(plan.weeks.count) weeks · \(plan.sessionsPerWeek) rides a week · ≈ \(hours)"
    }

    /// "Done · 16 of 18": the last time this rider finished or left the plan.
    static func doneBefore(_ plan: TrainingPlan) -> String? {
        let rider = Riders.currentID
        guard let last = PlanStore.all.first(where: { $0.riderID == rider && $0.planID == plan.id && ($0.left || PlanStore.isFinished($0)) })
        else { return nil }
        let total = plan.weeks.map(\.count).reduce(0, +)
        return "Done · \(last.done.count) of \(total)"
    }
}
