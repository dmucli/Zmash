import SwiftUI
import ZmashKit

/// Home's top card (D147): the training plan, as a slim strip over the three ways to ride.
/// - No plan: where to pick one. The plans open in "Your ride".
/// - On a plan: the session that's next, this week at a glance, Ride this and the plan itself.
/// - After one: the next.
struct PlanCard: View {
    /// Rides a session (home starts it, or sets it up when there's no trainer yet).
    let ride: (SessionPlan) -> Void
    /// Opens the plans in "Your ride" on this plan (nil: the first).
    let openPlans: (String?) -> Void
    var compact = false
    @Environment(Preferences.self) private var prefs
    /// Riders who said "not now" to picking a plan, separated by "|". Starting a plan takes them off.
    @AppStorage("plancard.notNow") private var notNow = ""

    var body: some View {
        // Follows plans started, changed or left, and rides saved or deleted.
        let _ = (PlanChanges.shared.revision, RideChanges.shared.revision)
        if let e = PlanStore.current, let plan = e.plan, let next = PlanStore.upNext(e) {
            onPlan(e, plan, next: next)
                .onAppear { setNotNow(false) }
        } else if !notNow.split(separator: "|").contains(Substring(prefs.riderID.isEmpty ? "first" : prefs.riderID)) {
            pick(finished: PlanStore.lastFinished(rider: prefs.riderID)?.plan)
        }
    }

    // MARK: On a plan

    private func onPlan(_ e: PlanEnrolment, _ plan: TrainingPlan, next: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)) -> some View {
        let slot = next.slot
        let session = PlanStore.session(e, week: slot.week, index: slot.index)
        let marks = PlanStore.schedule(e).filter { $0.slot.week == slot.week }.map(\.status)
        let when = next.status == .today ? "Today" : "Next · " + slot.day.formatted(.dateTime.weekday(.wide))
        let line = when + " · \(session.map(PlanStore.minutes) ?? 0) min" + (session.map { PlanStore.notchNote(e, $0, short: true) } ?? "")
        return strip {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text("\(plan.name) · week \(slot.week + 1) of \(plan.weeks.count)").monoLabel()
                        .foregroundStyle(Design.Palette.fgOnHero2).lineLimit(1)
                    WeekMarks(marks: marks)
                }
                headline(session.map(PlanStore.name) ?? plan.name, line: line, level: difficulty(e, slot, session))
            }
            .accessibilityElement(children: .combine)
        } buttons: {
            PillButton(title: "Plan", icon: "calendar", style: .glass) { openPlans(plan.id) }
            PillButton(title: "Ride this", icon: "play", style: .primary) {
                if let p = PlanStore.rideablePlan(e, week: slot.week, index: slot.index, prefs: prefs) { ride(p) }
            }
        }
    }

    /// 1–5, from the workout's load at your FTP, or the climb at your pace.
    private func difficulty(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot, _ session: TrainingPlan.Session?) -> Int? {
        if case .route(let id)? = session, let route = RaceStore.climb(id: id)?.route {
            return Difficulty.route(route, estimatedSeconds: RouteStats.of(route).estimatedSeconds)
        }
        return PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index))
            .map { Difficulty.workout(tss: $0.estimatedLoad(ftp: Double(prefs.ftp)).tss) }
    }

    // MARK: No plan, or one just finished

    private func pick(finished: TrainingPlan?) -> some View {
        let weeks = TrainingPlans.all.map(\.weeks.count)
        let range = "\(weeks.min() ?? 4) to \(weeks.max() ?? 8) weeks"
        return strip {
            VStack(alignment: .leading, spacing: 3) {
                Text(finished == nil ? "Training plan" : "Plan done").monoLabel()
                    .foregroundStyle(Design.Palette.fgOnHero2)
                headline(finished.map { "You finished \($0.name)" } ?? "Pick a training plan",
                         line: (finished == nil ? "" : "Pick the next one: ")
                             + "\(TrainingPlans.all.count) plans, \(range), on your days, adapting as you ride.",
                         level: nil)
            }
            .accessibilityElement(children: .combine)
        } buttons: {
            RoundIconButton(icon: "x", size: 40) {
                withAnimation(Design.Motion.base) { setNotNow(true) }
            }
            .accessibilityLabel("Not now")
            PillButton(title: "Choose a plan", icon: "calendar", style: .primary) { openPlans(nil) }
        }
    }

    private func setNotNow(_ on: Bool) {
        let me = prefs.riderID.isEmpty ? "first" : prefs.riderID
        var riders = Set(notNow.split(separator: "|").map(String.init))
        guard riders.contains(me) != on else { return }
        if on { riders.insert(me) } else { riders.remove(me) }
        notNow = riders.sorted().joined(separator: "|")
    }

    // MARK: Pieces

    /// The words on the left and the buttons on the right, on one line when they fit (the buttons under the words
    /// on a phone or with large text), on the hatch.
    private func strip(@ViewBuilder words: () -> some View, @ViewBuilder buttons: () -> some View) -> some View {
        let words = words(), buttons = HStack(spacing: 8) { buttons() }.fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                words.frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
            VStack(alignment: .leading, spacing: 12) {
                words.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) { Spacer(minLength: 0); buttons }
            }
        }
        .environment(\.onTarmac, true)
        .card(padding: compact ? 14 : 16, hero: true)
        .contentTransition(.opacity)
    }

    /// The title, and a line with the difficulty: side by side when they fit.
    private func headline(_ title: String, line: String, level: Int?) -> some View {
        let title = Text(title).textStyle(.h2, size: compact ? 18 : 21).foregroundStyle(Design.Palette.fgOnHero)
        let facts = HStack(spacing: 10) {
            Text(line).font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fgOnHeroBody).lineLimit(1)
            if let level {
                DifficultyGauge(level: level, compact: true)
                Text(Difficulty.label(level)).monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title.fixedSize()
                facts.fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                title.lineLimit(2)
                facts
            }
        }
    }
}

/// A plan week at a glance: a mark per session, filled once done, vermilion today, open to come, a dash if missed.
private struct WeekMarks: View {
    let marks: [TrainingPlan.Status]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, status in
                switch status {
                case .done: Circle().fill(Design.Palette.fgOnHero).frame(width: 8, height: 8)
                case .today: Circle().fill(Design.Accent.vermilion).frame(width: 8, height: 8)
                case .upcoming: Circle().strokeBorder(Design.Palette.fgOnHero2, lineWidth: 1.5).frame(width: 8, height: 8)
                case .missed: Capsule().fill(Design.Palette.fgOnHero2).frame(width: 8, height: 2).frame(height: 8)
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
