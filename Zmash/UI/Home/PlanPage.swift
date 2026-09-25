import SwiftUI
import ZmashKit

/// Training plans (D148): the plans by what they're for on the left; on the right the plan, to start it on your days
/// or, once you're on it, this week and Ride this.
struct PlanPage: View {
    let context: RideContext
    @State private var shown: String

    init(context: RideContext) {
        self.context = context
        var id = PlanStore.current?.planID ?? TrainingPlans.all.first?.id ?? ""
        #if DEBUG
        if DebugLaunch.homeShow == "plan" { id = DebugLaunch.plan }
        #endif
        _shown = State(initialValue: id)
    }

    var body: some View {
        // Follows a plan started or left in the preview, for the tags.
        let _ = PlanChanges.shared.revision
        RidePage(title: "Training plan", context: context) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Each plan fits the days you ride, and adapts as you go: sessions you nail get harder, ones you miss don't pile up.")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.top, 16)
                ChooseList(scrollTo: shown) { plans }
            }
        } preview: {
            if let plan = TrainingPlans.plan(id: shown) {
                PlanPreview(plan: plan)
            }
        }
    }

    /// Plans by what they're for (D143), each with its length and hours a week, and whether you're on it.
    @ViewBuilder private var plans: some View {
        ForEach(TrainingPlan.Goal.allCases, id: \.self) { goal in
            let list = TrainingPlans.all.filter { $0.goal == goal }
            if !list.isEmpty {
                ChooseSection(goal.title)
                ForEach(list, id: \.id) { plan in
                    ChooseRow(title: plan.name, subtitle: Self.meta(plan), selected: shown == plan.id, shapeWidth: nil,
                              action: { withAnimation(Design.Motion.base) { shown = plan.id } }) {
                        if PlanStore.current?.planID == plan.id {
                            Tag(title: "You're on it", fill: Design.Accent.vermilion)
                        } else if let before = Self.doneBefore(plan) {
                            Tag(title: before)
                        }
                    }
                    .id(plan.id)
                }
            }
        }
    }

    /// "6 weeks · 3 rides a week · ≈ 3 h 30 a week".
    static func meta(_ plan: TrainingPlan) -> String {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        let hours = perWeek >= 60 ? "\(perWeek / 60) h \(String(format: "%02d", perWeek % 60))" : "\(perWeek) min"
        return "\(plan.weeks.count) weeks · \(plan.sessionsPerWeek) rides a week · ≈ \(hours) a week"
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

/// The plan in the preview card: it scrolls itself, so on a phone it gets a height to scroll in.
private struct PlanPreview: View {
    let plan: TrainingPlan
    @Environment(\.ridePageStacked) private var stacked

    var body: some View {
        PlanView(plan: plan, close: {}, embedded: true)
            .id(plan.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: stacked ? 560 : nil)
    }
}
