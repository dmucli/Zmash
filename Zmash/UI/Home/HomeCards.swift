import SwiftUI
import ZmashKit

/// One of home's four cards (D148): a title, a sentence about what it is, and a picture of it; the whole card opens
/// its page. An accessory (the plan's Ride this) sits in the bottom corner, outside the card's own tap.
struct HomeCard<Art: View, Accessory: View>: View {
    /// A mono line over the title (the plan's week); nil: none.
    var kicker: String? = nil
    let title: String
    let description: String
    var hero = false
    var compact = false
    let action: () -> Void
    @ViewBuilder var art: Art
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let kicker {
                                Text(kicker).monoLabel().foregroundStyle(hero ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
                                    .lineLimit(1)
                            }
                            Text(title).textStyle(.display, size: compact ? 26 : 34)
                                .foregroundStyle(hero ? Design.Palette.fgOnHero : Design.Palette.fg1)
                                .lineLimit(2).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        Icon("chevron-right", size: 20).foregroundStyle(hero ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
                    }
                    Text(description).font(Design.Font.sans(compact ? 15 : 16))
                        .foregroundStyle(hero ? Design.Palette.fgOnHeroBody : Design.Palette.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                    Spacer(minLength: compact ? 8 : 14)
                    art.frame(maxWidth: .infinity).frame(minHeight: compact ? 36 : 48, maxHeight: compact ? 56 : 120)
                        // Room for the accessory beside the picture.
                        .padding(.trailing, Accessory.self == EmptyView.self ? 0 : 150)
                }
                .padding(compact ? 18 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(CardBackground(hero: hero))
                .environment(\.onHero, hero)
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(title)")
            accessory.padding(compact ? 16 : 20)
        }
    }
}

extension HomeCard where Accessory == EmptyView {
    init(kicker: String? = nil, title: String, description: String, hero: Bool = false, compact: Bool = false,
         action: @escaping () -> Void, @ViewBuilder art: () -> Art) {
        self.init(kicker: kicker, title: title, description: description, hero: hero, compact: compact, action: action,
                  art: art, accessory: { EmptyView() })
    }
}

/// The plan card: what a training plan is, or, on one, the session that's next and Ride this; after one, the next.
struct PlanHomeCard: View {
    var compact = false
    let open: () -> Void
    /// Rides a session (home starts it, or opens its page when there's no trainer yet).
    let ride: (SessionPlan) -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        // Follows plans started, changed or left, and rides saved or deleted.
        let _ = (PlanChanges.shared.revision, RideChanges.shared.revision)
        if let e = PlanStore.current, let plan = e.plan, let next = PlanStore.upNext(e) {
            onPlan(e, plan, next)
        } else {
            let finished = PlanStore.lastFinished(rider: prefs.riderID)?.plan
            HomeCard(kicker: finished == nil ? nil : "Plan done",
                     title: finished.map { "You finished \($0.name)" } ?? "Training plan",
                     description: finished == nil ? "Structured weeks on your days, adapting as you ride."
                                                  : "Pick the next one: \(TrainingPlans.all.count) plans, from base to climbing.",
                     hero: true, compact: compact, action: open) {
                PlanBars(plan: TrainingPlans.all.first)
            }
        }
    }

    private func onPlan(_ e: PlanEnrolment, _ plan: TrainingPlan, _ next: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)) -> some View {
        let slot = next.slot
        let session = PlanStore.session(e, week: slot.week, index: slot.index)
        let marks = PlanStore.schedule(e).filter { $0.slot.week == slot.week }.map(\.status)
        let when = next.status == .today ? "Today" : "Next · " + slot.day.formatted(.dateTime.weekday(.wide))
        let line = when + " · \(session.map(PlanStore.minutes) ?? 0) min" + (session.map { PlanStore.notchNote(e, $0, short: true) } ?? "")
        return HomeCard(kicker: "\(plan.name) · week \(slot.week + 1) of \(plan.weeks.count)",
                        title: session.map(PlanStore.name) ?? plan.name, description: line, hero: true, compact: compact,
                        action: open) {
            VStack(alignment: .leading, spacing: 10) {
                WeekMarks(marks: marks)
                sessionShape(e, slot, session)
            }
        } accessory: {
            PillButton(title: "Ride this", icon: "play", style: .primary) {
                if let p = PlanStore.rideablePlan(e, week: slot.week, index: slot.index, prefs: prefs) { ride(p) }
            }
            .fixedSize()
        }
    }

    @ViewBuilder private func sessionShape(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot, _ session: TrainingPlan.Session?) -> some View {
        if case .route(let id)? = session, let route = RaceStore.climb(id: id)?.route {
            RouteStrip(route: route, color: Design.Palette.fgOnHero, fill: Design.Accent.teamBlue.opacity(0.38))
        } else if let w = PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index)) {
            WorkoutStrip(workout: w.drawable)
        }
    }
}

/// A plan's weeks as bars, as tall as the week's riding: what a plan looks like before you're on one.
private struct PlanBars: View {
    let plan: TrainingPlan?

    var body: some View {
        let minutes = plan?.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) } ?? []
        Canvas { ctx, size in
            guard let peak = minutes.max(), peak > 0 else { return }
            let w = size.width / CGFloat(minutes.count)
            for (i, m) in minutes.enumerated() {
                let h = max(4, CGFloat(m) / CGFloat(peak) * size.height)
                let rect = CGRect(x: CGFloat(i) * w + 3, y: size.height - h, width: w - 6, height: h)
                let color = i == minutes.count - 1 ? Design.Accent.vermilion : Design.Palette.fgOnHero.opacity(0.28)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A plan week at a glance: a mark per session, filled once done, vermilion today, open to come, a dash if missed.
struct WeekMarks: View {
    let marks: [TrainingPlan.Status]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, status in
                switch status {
                case .done: Circle().fill(Design.Palette.fgOnHero).frame(width: 10, height: 10)
                case .today: Circle().fill(Design.Accent.vermilion).frame(width: 10, height: 10)
                case .upcoming: Circle().strokeBorder(Design.Palette.fgOnHero2, lineWidth: 1.5).frame(width: 10, height: 10)
                case .missed: Capsule().fill(Design.Palette.fgOnHero2).frame(width: 10, height: 2).frame(height: 10)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        let count = { (s: TrainingPlan.Status) in marks.filter { $0 == s }.count }
        var parts = ["\(count(.done)) done"]
        if count(.today) > 0 { parts.append("1 today") }
        if count(.upcoming) > 0 { parts.append("\(count(.upcoming)) to come") }
        if count(.missed) > 0 { parts.append("\(count(.missed)) missed") }
        return "This week: " + parts.joined(separator: ", ")
    }
}
