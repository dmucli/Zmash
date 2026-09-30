import SwiftUI
import ZmashKit

// Home's cards (D149, D158, D162), after the design system's prototype: a heading that says what the card is for,
// the ride chosen on it, a quiet line of figures, a sentence about it, and the ride's shape large at the bottom. The
// plan is the hatch hero.

/// What a home card is for, as its heading (D162): an icon and a word, big enough to read at a glance, and a chevron,
/// as the card opens its page. A mono detail on the right when there's one (the plan's week).
struct CardHeader: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var compact = false
    var onHero = false

    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, size: compact ? 22 : 26)
                .foregroundStyle(onHero ? Design.Palette.fgOnHero : Design.Palette.fg1)
            Text(title).font(Design.Font.sans(compact ? 26 : 30, weight: 700)).tracking(-0.5)
                .foregroundStyle(onHero ? Design.Palette.fgOnHero : Design.Palette.fg1)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).monoLabel(12).foregroundStyle(onHero ? Design.Palette.fgOnHero2 : Design.Palette.fg3).lineLimit(1)
            }
            Icon("chevron-right", size: 18).foregroundStyle(onHero ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A plain card: Workout or Route. The whole card opens its page.
struct HomeTile<Shape: View>: View {
    let kind: String
    /// The heading's icon.
    let icon: String
    let title: String
    let line: String
    /// A sentence about the ride: the workout's description, the route's climbs. Cut to a line, then left out, when the
    /// card is too short for it.
    var description = ""
    /// A profile drawn edge to edge along the bottom, as the prototype's route cards.
    var fullBleed = false
    var compact = false
    let action: () -> Void
    @ViewBuilder var shape: Shape

    var body: some View {
        Button(action: action) {
            // Shorter cards keep a line of the description before they drop it.
            ViewThatFits(in: .vertical) {
                content(description: description, lines: 2)
                content(description: description, lines: 1)
                content(description: "", lines: 0)
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

    private func content(description: String, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                CardHeader(icon: icon, title: kind, compact: compact)
                    .padding(.bottom, 5)
                // The ride chosen on it, under what the card is for.
                Text(title).font(Design.Font.sans(compact ? 20 : 22, weight: 600))
                    .foregroundStyle(Design.Palette.fg1)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(line).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fg3).lineLimit(1)
                if !description.isEmpty {
                    Text(description).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fg2)
                        .lineLimit(lines)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
            shape
                .frame(maxWidth: .infinity)
                .frame(minHeight: 22, maxHeight: fullBleed ? 84 : 72)
                .padding(.horizontal, fullBleed ? -22 : 0)
        }
    }
}

/// A card that's only its heading: Free ride (D174), where there's nothing to choose before you pedal. Short, so the
/// cards with a ride to show get the room.
struct HomeBar: View {
    let kind: String
    let icon: String
    var compact = false
    let action: () -> Void

    static func height(compact: Bool) -> CGFloat { compact ? 72 : 84 }

    var body: some View {
        Button(action: action) {
            CardHeader(icon: icon, title: kind, compact: compact)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CardBackground())
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Opens \(kind.capitalized)")
    }
}

/// The hero: the training plan. Without one, what a plan is; on one (D158), the plan and its weeks, the next workout
/// with its shape, figures and Ride this, and the sessions after it; after one, the next. The card opens the Plan page;
/// the button rides.
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
        return layout(detail: "intervals.icu · today", title: w.name,
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
        let schedule = PlanStore.schedule(e)
        // The sessions after the next one, for the overview.
        let then = Array(schedule.filter { ($0.status == .today || $0.status == .upcoming) && $0.slot != next.slot }
            .prefix(compact ? 2 : 3))
        // With too little room, the sessions after it go first, then the weeks.
        return ViewThatFits(in: .vertical) {
            planLayout(e, plan, next, schedule: schedule, then: then, bars: true)
            planLayout(e, plan, next, schedule: schedule, then: [], bars: true)
            planLayout(e, plan, next, schedule: schedule, then: [], bars: false)
        }
    }

    private func planLayout(_ e: PlanEnrolment, _ plan: TrainingPlan, _ next: (slot: TrainingPlan.Slot, status: TrainingPlan.Status),
                            schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)],
                            then: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)], bars: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "calendar", title: "Training plan", detail: "Week \(next.slot.week + 1) of \(plan.weeks.count)",
                           compact: compact, onHero: true)
                    .padding(.bottom, 6)
                Text(plan.name).font(Design.Font.sans(compact ? 30 : 38, weight: 700)).tracking(-0.8)
                    .foregroundStyle(Design.Palette.fgOnHero)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text("\(PlanPage.source(plan)) · \(e.done.count) of \(schedule.count) done")
                    .font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fgOnHeroBody).lineLimit(1)
            }
            if bars {
                // The plan at a glance: its weeks as tall as their riding, yours in vermilion, numbered underneath.
                let week = PlanStore.week(e)
                VStack(spacing: 6) {
                    PlanBars(plan: plan, hero: true, week: week)
                        .frame(minHeight: compact ? 36 : 48, maxHeight: compact ? 70 : 190)
                    HStack(spacing: 0) {
                        ForEach(0..<plan.weeks.count, id: \.self) { w in
                            Text("\(w + 1)").font(Design.Font.mono(10))
                                .foregroundStyle(w == week ? Design.Accent.vermilion : Design.Palette.fgOnHero2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 16)
            nextPanel(e, next.slot, status: next.status)
            if !then.isEmpty {
                HStack(spacing: 8) {
                    ForEach(then.indices, id: \.self) { i in thenTile(e, then[i].slot) }
                }
                .padding(.top, 10)
            }
        }
    }

    /// The next workout, inset in the hero: when, what, its shape and figures, and Ride this.
    private func nextPanel(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot, status: TrainingPlan.Status) -> some View {
        let session = PlanStore.session(e, week: slot.week, index: slot.index)
        let workout = PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index))
        // " · 3 % harder after your last threshold sessions" → "3 % harder after your last threshold sessions."
        let change = String((session.map { PlanStore.notchNote(e, $0) } ?? "").dropFirst(3))
        let route: Route? = if case .route(let id)? = session { RaceStore.climb(id: id)?.route } else { nil }
        let sentence = [route == nil ? workout?.summary ?? "" : "", change.isEmpty ? "" : change + "."]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Text(status == .today ? "Today" : "Next · " + slot.day.formatted(.dateTime.weekday(.wide)))
                .monoLabel().foregroundStyle(status == .today ? Design.Accent.vermilion : Design.Palette.fgOnHero2)
            Text(session.map(PlanStore.name) ?? "").font(Design.Font.sans(compact ? 24 : 30, weight: 700)).tracking(-0.5)
                .foregroundStyle(Design.Palette.fgOnHero)
                .lineLimit(2).minimumScaleFactor(0.7)
                .padding(.top, 6)
            if !sentence.isEmpty {
                Text(sentence).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fgOnHeroBody)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Group {
                if let route {
                    RouteStrip(route: route, color: Design.Palette.fgOnHero, fill: Design.Accent.teamBlue.opacity(0.38))
                } else if let workout {
                    WorkoutStrip(workout: workout.drawable)
                }
            }
            .frame(maxWidth: .infinity).frame(minHeight: 44, maxHeight: 130)
            .padding(.vertical, 14)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    figures(route: route, workout: workout, session: session)
                    Spacer(minLength: 12)
                    rideButton(e, slot)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 24) { figures(route: route, workout: workout, session: session) }
                    rideButton(e, slot)
                }
            }
        }
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inset)
    }

    @ViewBuilder
    private func figures(route: Route?, workout: Workout?, session: TrainingPlan.Session?) -> some View {
        if let route {
            figure(String(format: "%.1f", prefs.units.distance(route.distanceM)), prefs.units.distanceUnit)
            figure(String(format: "%.0f", prefs.units.elevation(route.ascentM)), prefs.units.elevationUnit)
        } else if let workout {
            figure("\(session.map(PlanStore.minutes) ?? workout.duration / 60)", "min")
            figure("\(Int(workout.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))", "TSS")
        }
    }

    private func rideButton(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot) -> some View {
        PillButton(title: "Ride this", icon: "play", style: .primary) {
            if let p = PlanStore.rideablePlan(e, week: slot.week, index: slot.index, prefs: prefs) { ride(p) }
        }
        .fixedSize()
    }

    /// A session after the next one: its day, name and length.
    private func thenTile(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot) -> some View {
        let session = PlanStore.session(e, week: slot.week, index: slot.index)
        return VStack(alignment: .leading, spacing: 3) {
            Text(slot.day.formatted(.dateTime.weekday(.abbreviated))).monoLabel(10).foregroundStyle(Design.Palette.fgOnHero2)
            Text(session.map(PlanStore.name) ?? "").font(Design.Font.sans(14, weight: 600)).foregroundStyle(Design.Palette.fgOnHero)
                .lineLimit(1)
            Text("\(session.map(PlanStore.minutes) ?? 0) min").font(Design.Font.mono(11)).foregroundStyle(Design.Palette.fgOnHeroBody)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inset)
        .accessibilityElement(children: .combine)
    }

    /// A tile sunk into the hatch: tarmac glass with a hairline.
    private var inset: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
        return ZStack {
            shape.fill(Design.Tarmac.glass)
            shape.strokeBorder(Design.Tarmac.t700, lineWidth: 1)
        }
    }

    private func noPlan(finished: TrainingPlan?) -> some View {
        let weeks = PlanStore.plans.map(\.weeks.count)
        return layout(detail: finished == nil ? nil : "Done",
                      title: finished.map { "You finished \($0.name)" } ?? "Train with a plan",
                      sentence: (finished == nil ? "" : "Pick the next one. ")
                          + "Plans fit the days you ride. Zmash's adapt as you go: sessions you nail get harder, missed ones don't pile up.") {
            PlanBars(plan: TrainingPlans.all.first, hero: true)
        } figures: {
            figure("\(PlanStore.plans.count)", "plans")
            figure("\(weeks.min() ?? 3)–\(weeks.max() ?? 8)", "weeks")
        } button: {
            PillButton(title: "Choose a plan", icon: "calendar", style: .primary, action: open).fixedSize()
        }
    }

    private func layout(detail: String?, title: String, sentence: String, @ViewBuilder shape: () -> some View,
                        @ViewBuilder figures: () -> some View, @ViewBuilder button: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "calendar", title: "Training plan", detail: detail, compact: compact, onHero: true)
                    .padding(.bottom, 6)
                Text(title).font(Design.Font.sans(compact ? 30 : 38, weight: 700)).tracking(-0.8)
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

    private func figure(_ value: String, _ unit: String) -> some View { HeroFigure(value: value, unit: unit) }
}

/// A figure on a hero card in bib numerals, its unit small beside it.
struct HeroFigure: View {
    let value: String
    let unit: String
    /// On a plain card: ink, not bone (the Plan page's next session, D174).
    var hero = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(Design.Font.bib(30)).foregroundStyle(hero ? Design.Palette.fgOnHero : Design.Palette.fg1)
            Text(unit).font(Design.Font.sans(14)).foregroundStyle(hero ? Design.Palette.fgOnHeroBody : Design.Palette.fg3)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// A plan's weeks as bars, as tall as the week's riding. Before you start, the last one (the goal) in vermilion; on the
/// plan, the week you're in (D157).
struct PlanBars: View {
    /// A bar each: a plan's weeks, in minutes.
    let minutes: [Int]
    var hero = false
    /// On the plan: the week you're in, in vermilion, the ones before it ridden, in ink (bone on a hero). nil: the goal.
    var week: Int?

    init(plan: TrainingPlan?, hero: Bool = false, week: Int? = nil) {
        minutes = plan?.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) } ?? []
        self.hero = hero
        self.week = week
    }

    var body: some View {
        let minutes = minutes, week = week
        let ridden = hero ? Design.Palette.fgOnHero : Design.Palette.fg1
        let rest = hero ? Design.Palette.fgOnHero.opacity(0.28) : Design.Zone.z2
        Canvas { ctx, size in
            guard let peak = minutes.max(), peak > 0 else { return }
            let w = size.width / CGFloat(minutes.count)
            for (i, m) in minutes.enumerated() {
                let h = max(4, CGFloat(m) / CGFloat(peak) * size.height)
                let rect = CGRect(x: CGFloat(i) * w + 2, y: size.height - h, width: w - 4, height: h)
                let color = if let week { i < week ? ridden : i == week ? Design.Accent.vermilion : rest }
                    else { i == minutes.count - 1 ? Design.Accent.vermilion : rest }
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
