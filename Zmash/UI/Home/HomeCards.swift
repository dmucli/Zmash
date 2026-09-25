import SwiftUI
import ZmashKit

// Home's cards (D149), after the design system's prototype: a mono label for the kind, a title that is the ride itself,
// a quiet line of figures, and the ride's shape large at the bottom. The plan is the hatch hero.

/// A plain card: Workout, Route or Free ride. The whole card opens its page.
struct HomeTile<Shape: View>: View {
    let kind: String
    let title: String
    let line: String
    /// A profile drawn edge to edge along the bottom, as the prototype's route cards.
    var fullBleed = false
    var compact = false
    let action: () -> Void
    @ViewBuilder var shape: Shape

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind).monoLabel().foregroundStyle(Design.Palette.fg3)
                    Text(title).font(Design.Font.sans(compact ? 21 : 24, weight: 700)).foregroundStyle(Design.Palette.fg1)
                        .lineLimit(2).minimumScaleFactor(0.75)
                    Text(line).font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fg3).lineLimit(1)
                }
                Spacer(minLength: 0)
                shape
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 28, maxHeight: fullBleed ? 84 : 72)
                    .padding(.horizontal, fullBleed ? -22 : 0)
            }
            .padding(.top, 22).padding(.horizontal, 22).padding(.bottom, fullBleed ? 0 : 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CardBackground())
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(kind.capitalized)")
    }
}

/// The hero: the training plan. Without one, what a plan is; on one, the next session, its shape and figures, and
/// Ride this; after one, the next. The card opens the Plan page; the button rides.
struct PlanHero: View {
    var compact = false
    let open: () -> Void
    /// Rides a session (home starts it, or opens its page when there's no trainer yet).
    let ride: (SessionPlan) -> Void
    /// Opens a workout on the Workout page (today's from intervals.icu).
    let openWorkout: (SessionPlan) -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        // Follows plans started, changed or left, and rides saved or deleted.
        let _ = (PlanChanges.shared.revision, RideChanges.shared.revision)
        Group {
            if let e = PlanStore.current, let plan = e.plan, let next = PlanStore.upNext(e) {
                onPlan(e, plan, next)
            } else if let entry = PlannedWorkouts.shared.today {
                // No plan here, but one on intervals.icu (D153): today's workout from its calendar.
                planned(entry)
            } else {
                noPlan(finished: PlanStore.lastFinished(rider: prefs.riderID)?.plan)
            }
        }
        .padding(compact ? 22 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground(hero: true))
        .environment(\.onHero, true)
        .environment(\.onTarmac, true)
        .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
        .onTapGesture { if let entry = plannedToday { openWorkout(session(entry)) } else { open() } }
        .accessibilityAction(named: plannedToday == nil ? "Open the plans" : "Open the workout") {
            if let entry = plannedToday { openWorkout(session(entry)) } else { open() }
        }
    }

    /// Today's intervals.icu workout, when that's what the card shows.
    private var plannedToday: PlannedWorkouts.Entry? {
        PlanStore.current == nil ? PlannedWorkouts.shared.today : nil
    }

    private func session(_ entry: PlannedWorkouts.Entry) -> SessionPlan {
        var p = prefs.lastPlan
        p.routeID = nil
        p.workoutID = entry.id
        return p
    }

    private func planned(_ entry: PlannedWorkouts.Entry) -> some View {
        let w = entry.workout
        let load = w.estimatedLoad(ftp: Double(prefs.ftp))
        return layout(kicker: "intervals.icu · today", title: w.name,
                      sentence: w.summary.isEmpty ? "Planned on your intervals.icu calendar." : w.summary) {
            WorkoutStrip(workout: w.drawable)
        } figures: {
            figure("\(w.duration / 60)", "min")
            figure("\(Int(load.tss.rounded()))", "TSS")
        } button: {
            PillButton(title: "Ride this", icon: "play", style: .primary) { ride(session(entry)) }.fixedSize()
        }
    }

    private func onPlan(_ e: PlanEnrolment, _ plan: TrainingPlan, _ next: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)) -> some View {
        let slot = next.slot
        let session = PlanStore.session(e, week: slot.week, index: slot.index)
        let marks = PlanStore.schedule(e).filter { $0.slot.week == slot.week }.map(\.status)
        let when = next.status == .today ? "Today." : "Next, on " + slot.day.formatted(.dateTime.weekday(.wide)) + "."
        // " · 3 % harder after your last threshold sessions" → "3 % harder after your last threshold sessions."
        let change = String((session.map { PlanStore.notchNote(e, $0) } ?? "").dropFirst(3))
        let sentence = change.isEmpty ? when : "\(when) \(change)."
        return layout(kicker: "Training plan · \(plan.name) · week \(slot.week + 1) of \(plan.weeks.count)",
                      title: session.map(PlanStore.name) ?? plan.name, sentence: sentence) {
            VStack(alignment: .leading, spacing: 12) {
                WeekMarks(marks: marks)
                sessionShape(e, slot, session)
            }
        } figures: {
            if case .route(let id)? = session, let route = RaceStore.climb(id: id)?.route {
                figure(String(format: "%.1f", prefs.units.distance(route.distanceM)), prefs.units.distanceUnit)
                figure(String(format: "%.0f", prefs.units.elevation(route.ascentM)), prefs.units.elevationUnit)
            } else if let w = PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index)) {
                figure("\(w.duration / 60)", "min")
                figure("\(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))", "TSS")
            }
        } button: {
            PillButton(title: "Ride this", icon: "play", style: .primary) {
                if let p = PlanStore.rideablePlan(e, week: slot.week, index: slot.index, prefs: prefs) { ride(p) }
            }
            .fixedSize()
        }
    }

    private func noPlan(finished: TrainingPlan?) -> some View {
        let weeks = TrainingPlans.all.map(\.weeks.count)
        return layout(kicker: finished == nil ? "Training plan" : "Plan done",
                      title: finished.map { "You finished \($0.name)" } ?? "Train with a plan",
                      sentence: (finished == nil ? "" : "Pick the next one. ")
                          + "Plans fit the days you ride and adapt as you go: sessions you nail get harder, missed ones don't pile up.") {
            PlanBars(plan: TrainingPlans.all.first, hero: true)
        } figures: {
            figure("\(TrainingPlans.all.count)", "plans")
            figure("\(weeks.min() ?? 3)–\(weeks.max() ?? 8)", "weeks")
        } button: {
            PillButton(title: "Choose a plan", icon: "calendar", style: .primary, action: open).fixedSize()
        }
    }

    private func layout(kicker: String, title: String, sentence: String, @ViewBuilder shape: () -> some View,
                        @ViewBuilder figures: () -> some View, @ViewBuilder button: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(kicker).monoLabel().foregroundStyle(Design.Palette.fgOnHero2).lineLimit(1)
                Text(title).font(Design.Font.sans(compact ? 32 : 42, weight: 700)).tracking(-0.8)
                    .foregroundStyle(Design.Palette.fgOnHero)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(sentence).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fgOnHeroBody)
                    .lineSpacing(3)
                    .frame(maxWidth: 420, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            shape().frame(maxWidth: .infinity).frame(minHeight: 60, maxHeight: 150)
            Spacer(minLength: 16)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 28) {
                    figures()
                    Spacer(minLength: 12)
                    button()
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 24) { figures() }
                    button()
                }
            }
        }
    }

    /// A figure in bib numerals, its unit small beside it.
    private func figure(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(Design.Font.bib(30)).foregroundStyle(Design.Palette.fgOnHero)
            Text(unit).font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fgOnHeroBody)
        }
        .lineLimit(1)
    }

    @ViewBuilder private func sessionShape(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot, _ session: TrainingPlan.Session?) -> some View {
        if case .route(let id)? = session, let route = RaceStore.climb(id: id)?.route {
            RouteStrip(route: route, color: Design.Palette.fgOnHero, fill: Design.Accent.teamBlue.opacity(0.38))
        } else if let w = PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index)) {
            WorkoutStrip(workout: w.drawable)
        }
    }
}

/// A plan's weeks as bars, as tall as the week's riding, the last one (the goal) in vermilion.
struct PlanBars: View {
    let plan: TrainingPlan?
    var hero = false

    var body: some View {
        let minutes = plan?.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) } ?? []
        Canvas { ctx, size in
            guard let peak = minutes.max(), peak > 0 else { return }
            let w = size.width / CGFloat(minutes.count)
            for (i, m) in minutes.enumerated() {
                let h = max(4, CGFloat(m) / CGFloat(peak) * size.height)
                let rect = CGRect(x: CGFloat(i) * w + 2, y: size.height - h, width: w - 4, height: h)
                let rest = hero ? Design.Palette.fgOnHero.opacity(0.28) : Design.Zone.z2
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(i == minutes.count - 1 ? Design.Accent.vermilion : rest))
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
