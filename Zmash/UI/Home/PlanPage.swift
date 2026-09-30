import SwiftUI
import ZmashKit

/// Training plans (D148, D149, D155, D156): Zmash's adaptive plans, then the plans in the workout catalog (Zwift's and
/// others': FTP Builder, Zwift Academy, 4wk FTP Booster…), as cards by what they're for. Either kind opens in place:
/// start it on your days, or, once you're on it, this week and Ride this. It opens on the plan you're on.
struct PlanPage: View {
    let context: RideContext
    var compact = false
    /// The plan shown in place of the grid; nil: the grid.
    @State private var open: String?
    /// nil: every goal.
    @State private var goal: TrainingPlan.Goal?

    init(context: RideContext, compact: Bool = false) {
        self.context = context
        self.compact = compact
        var id = PlanStore.current?.planID
        #if DEBUG
        if DebugLaunch.homeShow == "plan" { id = DebugLaunch.plan }
        #endif
        _open = State(initialValue: id)
    }

    var body: some View {
        // Follows a plan started or left, for the tags.
        let _ = PlanChanges.shared.revision
        RidePage(context: context, selection: nil, compact: compact) {
            if open != nil {
                Chip(title: "All plans", icon: "chevron-left", selected: false) {
                    withAnimation(Design.Motion.base) { open = nil }
                }
            } else {
                FilterChips(options: [(TrainingPlan.Goal?.none, "All")] + TrainingPlan.Goal.allCases.map { (Optional($0), $0.title) },
                            selection: $goal)
            }
        } tools: {
            Spacer(minLength: 0)
        } content: {
            if let plan = open.flatMap(PlanStore.plan) {
                PlanView(plan: plan, close: {}, embedded: true, compact: compact,
                         changePlan: { withAnimation(Design.Motion.base) { open = nil } })
                    .id(plan.id)
            } else {
                PickerGrid(columns: compact ? 1 : 2, rowHeight: compact ? 170 : 190, scrollTo: PlanStore.current?.planID,
                           showing: goal?.rawValue ?? "") {
                    ForEach(PlanStore.plans.filter { goal == nil || $0.goal == goal }, id: \.id) { plan in
                        let on = PlanStore.current?.planID == plan.id
                        PickerCard(title: plan.name, meta: Self.meta(plan), selected: on,
                                   tag: on ? "You're on it" : Self.doneBefore(plan), caption: Self.source(plan),
                                   action: { withAnimation(Design.Motion.base) { open = plan.id } }) {
                            PlanBars(plan: plan)
                        }
                        .id(plan.id)
                    }
                }
            }
        }
    }

    /// Who a plan is from: Zmash's adapt as you ride, the catalog's ride as written (D156).
    static func source(_ plan: TrainingPlan) -> String {
        guard let author = plan.author else { return "Zmash · adapts as you ride" }
        return (author.isEmpty ? "Workout catalog" : author) + " · as written"
    }

    /// "6 weeks · 3 rides a week · ≈ 2 h 38 a week".
    static func meta(_ plan: TrainingPlan) -> String {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        let hours = perWeek >= 60 ? "\(perWeek / 60) h \(String(format: "%02d", perWeek % 60))" : "\(perWeek) min"
        let weeks = plan.weeks.count, rides = plan.sessionsPerWeek
        return "\(weeks) week\(weeks == 1 ? "" : "s") · \(rides) ride\(rides == 1 ? "" : "s") a week · ≈ \(hours)"
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
