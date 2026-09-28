import SwiftUI
import ZmashKit

/// A training plan, Zmash's or the catalog's (D156), as cards (D157). Before you start it: the plan as the hero, beside
/// how to start it, then its weeks. Once you're on it: the next session as the hero, beside where you are and what you
/// can change (the plan, your days), then this week's sessions, then every week, the one you're in ringed.
struct PlanView: View {
    let plan: TrainingPlan
    /// Home's preview goes back to the workout once a session is set up.
    let close: () -> Void
    /// On the Plan page (D144): no page background or margins of its own.
    var embedded = false
    var compact = false
    /// Back to every plan, to pick another; nil: no button.
    var changePlan: (() -> Void)? = nil
    @Environment(Preferences.self) private var prefs
    @State private var enrolment: PlanEnrolment?
    @State private var weekdays: Set<Int> = [3, 5, 7]
    @State private var startNextWeek = false
    @State private var confirmLeave = false
    /// Changing ride days while on the plan: the days being picked, or nil when not editing.
    @State private var newDays: Set<Int>?

    /// Plan weeks run Monday to Sunday (the schedule uses the same calendar).
    private let calendar = Calendar.mondayFirst
    /// The side card's width beside the hero.
    private let side: CGFloat = 400

    var body: some View {
        let schedule = enrolment.map { PlanStore.schedule($0) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 20 : 28) {
                if let enrolment { onPlan(enrolment, schedule: schedule) } else { setUp }
                weeks(schedule: schedule)
            }
            .padding(embedded ? 0 : 24)
            .padding(.bottom, 8)
            .frame(maxWidth: embedded ? .infinity : 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(embedded ? .clear : Design.Palette.background)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            enrolment = PlanStore.current.flatMap { $0.planID == plan.id ? $0 : nil }
            if enrolment == nil { weekdays = Self.defaultDays(for: plan) }
        }
        .confirmationDialog("Leave the plan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                guard var e = enrolment else { return }
                e.left = true
                PlanStore.save(e)
                enrolment = nil
            }
        }
    }

    /// The hero and a card beside it, as tall as each other; stacked on a phone.
    @ViewBuilder
    private func pair(@ViewBuilder hero: () -> some View, @ViewBuilder side: () -> some View) -> some View {
        if compact {
            VStack(spacing: 14) {
                hero()
                side()
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                hero()
                side().frame(width: self.side)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Starting

    private var setUp: some View {
        pair {
            overview
        } side: {
            startCard
        }
    }

    /// What the plan is: who it's from, its name and summary, its weeks as bars, and its figures.
    private var overview: some View {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(PlanPage.source(plan)).monoLabel().foregroundStyle(Design.Palette.fgOnHero2).lineLimit(1)
            Text(plan.name).textStyle(.display, size: compact ? 30 : 42).foregroundStyle(Design.Palette.fgOnHero)
                .lineLimit(2).minimumScaleFactor(0.7)
                .padding(.top, 8)
            Text(plan.summary).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fgOnHeroBody)
                .lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 20)
            PlanBars(plan: plan, hero: true).frame(height: compact ? 70 : 110)
            Spacer(minLength: 20)
            HStack(alignment: .lastTextBaseline, spacing: 24) {
                HeroFigure(value: "\(plan.weeks.count)", unit: plan.weeks.count == 1 ? "week" : "weeks")
                HeroFigure(value: "\(plan.sessionsPerWeek)", unit: "rides a week")
                HeroFigure(value: String(format: "%d:%02d", perWeek / 60, perWeek % 60), unit: "h a week")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: compact ? 22 : 28, hero: true)
    }

    /// Your days, this week or next, and Start.
    private var startCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Your ride days")
            dayPicker($weekdays)
            Text(daysNote)
                .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
            Segmented(options: [(false, "This week"), (true, "Next Monday")], selection: $startNextWeek)
            if !startNextWeek, let short = shortFirstWeek {
                Text(short).font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let other = PlanStore.current?.plan, other.id != plan.id {
                Text("Starting this ends \(other.name), the plan you're on.")
                    .font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            PrimaryButton(title: "Start the plan", enabled: !weekdays.isEmpty) {
                let start = startNextWeek
                    ? Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: .now)!.end
                    : calendar.startOfDay(for: .now)
                enrolment = PlanStore.enrol(plan, weekdays: weekdays, start: start)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 22)
    }

    private var daysNote: String {
        let n = weekdays.count, most = plan.sessionsPerWeek
        guard n < most else {
            return "\(most) sessions a week on those days; a missed one moves to your next ride day that week."
        }
        let days = "With \(n) day\(n == 1 ? "" : "s") a week, "
        // A catalog plan's sessions are in the order they're written, not by importance (D156).
        return plan.isZmash
            ? days + "the most important \(n == 1 ? "session is" : "sessions are") kept."
            : days + "you ride the first \(n) of each week's sessions; its weeks have up to \(most)."
    }

    /// The days you rode your last plan on; otherwise as many as the plan has sessions a week, resting on Monday and
    /// Friday first.
    static func defaultDays(for plan: TrainingPlan) -> Set<Int> {
        if let last = PlanStore.all.first(where: { $0.riderID == Riders.currentID }) { return last.weekdays }
        return switch plan.sessionsPerWeek {
        case ...1: [7]
        case 2: [3, 7]
        case 3: [3, 5, 7]
        case 4: [3, 5, 7, 1]
        case 5: [3, 4, 5, 7, 1]
        case 6: [2, 3, 4, 5, 7, 1]
        default: Set(1...7)
        }
    }

    /// Weekdays in the plan's order, Monday first.
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func dayPicker(_ days: Binding<Set<Int>>) -> some View {
        HStack(spacing: 8) {
            ForEach(orderedWeekdays, id: \.self) { d in
                let on = days.wrappedValue.contains(d)
                Button {
                    if on { days.wrappedValue.remove(d) } else { days.wrappedValue.insert(d) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[d - 1])
                        .font(Design.Font.label)
                        .foregroundStyle(on ? Design.Palette.background : Design.Palette.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(on ? Design.Palette.primary : Design.Palette.surfaceSunk))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[d - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// Starting today, mid-week: what week 1 loses when fewer of your ride days are left than it has sessions.
    private var shortFirstWeek: String? {
        guard let first = plan.weeks.first, !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: .now)
        let end = calendar.dateInterval(of: .weekOfYear, for: today)!.end
        let left = stride(from: 0, to: 7, by: 1)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter { $0 < end && weekdays.contains(calendar.component(.weekday, from: $0)) }.count
        let wanted = min(first.count, weekdays.count)
        guard left < wanted else { return nil }
        return "Only \(left) of your ride days \(left == 1 ? "is" : "are") left this week, so week 1 keeps \(left) of its \(first.count) sessions. Start next Monday to ride them all."
    }

    // MARK: On the plan

    /// The plan's week that today falls in, counted from its first (before 0 when it starts next week; past the last
    /// once it's over).
    private func calendarWeek(_ e: PlanEnrolment) -> Int {
        let first = calendar.dateInterval(of: .weekOfYear, for: e.start)!.start
        let now = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        return calendar.dateComponents([.weekOfYear], from: first, to: now).weekOfYear ?? 0
    }

    private func weekStart(_ e: PlanEnrolment, _ week: Int) -> Date {
        let first = calendar.dateInterval(of: .weekOfYear, for: e.start)!.start
        return calendar.date(byAdding: .weekOfYear, value: week, to: first)!
    }

    private func onPlan(_ e: PlanEnrolment, schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)]) -> some View {
        let next = PlanStore.upNext(e)
        let week = next?.slot.week ?? (plan.weeks.count - 1)
        return VStack(alignment: .leading, spacing: compact ? 20 : 28) {
            pair {
                if let next { nextCard(e, next) } else { completeCard }
            } side: {
                progressCard(e, schedule: schedule, week: week)
            }
            thisWeek(e, schedule: schedule, week: week, next: next?.slot)
        }
    }

    /// The session to ride next, as the hero: when, what, its shape and figures, and Ride this.
    private func nextCard(_ e: PlanEnrolment, _ next: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)) -> some View {
        let slot = next.slot
        let session = plan.weeks[slot.week][slot.index]
        let workout = PlanStore.workout(id: PlanStore.workoutID(e, week: slot.week, index: slot.index))
        // " · 3 % harder after your last threshold sessions" → "3 % harder after your last threshold sessions."
        let change = String(PlanStore.notchNote(e, session).dropFirst(3))
        let sentence = [workout?.summary ?? "", change.isEmpty ? "" : change + "."].filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Text(next.status == .today ? "Today" : "Next · " + slot.day.formatted(.dateTime.weekday(.wide)))
                .monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
            Text(PlanStore.name(session)).textStyle(.display, size: compact ? 30 : 40).foregroundStyle(Design.Palette.fgOnHero)
                .lineLimit(2).minimumScaleFactor(0.7)
                .padding(.top, 8)
            if !sentence.isEmpty {
                Text(sentence).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fgOnHeroBody)
                    .lineSpacing(3).lineLimit(3)
                    .frame(maxWidth: 520, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            Spacer(minLength: 20)
            shape(slot.week, slot.index, hero: true).frame(maxWidth: .infinity).frame(height: compact ? 80 : 120)
            Spacer(minLength: 20)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    figures(session, workout)
                    Spacer(minLength: 12)
                    rideButton(e, slot)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 24) { figures(session, workout) }
                    rideButton(e, slot)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: compact ? 22 : 28, hero: true)
        .environment(\.onTarmac, true)
    }

    @ViewBuilder
    private func figures(_ session: TrainingPlan.Session, _ workout: Workout?) -> some View {
        if case .route(let id) = session, let route = RaceStore.climb(id: id)?.route {
            HeroFigure(value: String(format: "%.1f", prefs.units.distance(route.distanceM)), unit: prefs.units.distanceUnit)
            HeroFigure(value: String(format: "%.0f", prefs.units.elevation(route.ascentM)), unit: prefs.units.elevationUnit)
        } else if let workout {
            HeroFigure(value: "\(PlanStore.minutes(session))", unit: "min")
            HeroFigure(value: "\(Int(workout.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))", unit: "TSS")
        }
    }

    private func rideButton(_ e: PlanEnrolment, _ slot: TrainingPlan.Slot) -> some View {
        PillButton(title: "Ride this", icon: "play", style: .primary) {
            // Starts the session (home waits a moment for the trainer, or sets it up there without one).
            if let p = PlanStore.rideablePlan(e, week: slot.week, index: slot.index, prefs: prefs) {
                close()
                try? IntentRouter.shared.ride(p)
            }
        }
        .fixedSize()
    }

    /// Every session ridden or missed: pick the next plan.
    private var completeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan done").monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
            Text("That's \(plan.name).").textStyle(.display, size: compact ? 30 : 40).foregroundStyle(Design.Palette.fgOnHero)
            Spacer(minLength: 20)
            if let changePlan {
                PillButton(title: "Pick the next one", icon: "calendar", style: .primary, action: changePlan).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: compact ? 22 : 28, hero: true)
    }

    /// Where you are: the plan, its weeks with yours in vermilion, the figures, and what you can change.
    private func progressCard(_ e: PlanEnrolment, schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)],
                              week: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(PlanPage.source(plan)).monoLabel().foregroundStyle(Design.Palette.fg3).lineLimit(1)
                Text(plan.name).textStyle(.h1, size: compact ? 26 : 30).foregroundStyle(Design.Palette.fg1)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            PlanBars(plan: plan, week: calendarWeek(e)).frame(height: 56)
            HStack(alignment: .top, spacing: 12) {
                StatTile(label: "Week", value: "\(week + 1)", unit: "of \(plan.weeks.count)", size: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatTile(label: "Done", value: "\(e.done.count)", unit: "of \(schedule.count)", size: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatTile(label: "Missed", value: "\(schedule.filter { $0.status == .missed }.count)", size: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if let days = newDays {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Your ride days")
                    dayPicker(Binding(get: { newDays ?? days }, set: { newDays = $0 }))
                    HStack(spacing: 8) {
                        PillButton(title: "Save days", style: .invert, compact: true, enabled: !days.isEmpty) {
                            var changed = e
                            changed.weekdays = days
                            PlanStore.save(changed)
                            enrolment = changed
                            newDays = nil
                        }
                        .fixedSize()
                        PillButton(title: "Cancel", compact: true) { newDays = nil }.fixedSize()
                    }
                }
            } else {
                actions(e)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 22)
    }

    private func actions(_ e: PlanEnrolment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let changePlan {
                    PillButton(title: "Change plan", icon: "refresh-cw", compact: true, action: changePlan).fixedSize()
                }
                PillButton(title: "Ride days", icon: "calendar-days", compact: true) { newDays = e.weekdays }.fixedSize()
            }
            Button("Leave the plan", role: .destructive) { confirmLeave = true }
                .font(Design.Font.small).buttonStyle(.plain).frame(minHeight: 44)
        }
    }

    /// The week of the next session, as a card per session: its day, name, length and shape, and how it stands.
    private func thisWeek(_ e: PlanEnrolment, schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)], week: Int,
                          next: TrainingPlan.Slot?) -> some View {
        let now = week == calendarWeek(e)
        let title = now ? "This week · week \(week + 1)"
            : "Week \(week + 1) · from " + weekStart(e, week).formatted(.dateTime.weekday(.wide).day().month(.wide))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 200), spacing: 14)], spacing: 14) {
                ForEach(schedule.filter { $0.slot.week == week }, id: \.slot.index) { entry in
                    sessionCard(e, entry, next: entry.slot == next)
                        .frame(height: compact ? 160 : 184)
                }
            }
        }
    }

    private func sessionCard(_ e: PlanEnrolment, _ entry: (slot: TrainingPlan.Slot, status: TrainingPlan.Status), next: Bool) -> some View {
        let session = plan.weeks[entry.slot.week][entry.slot.index]
        let missed = entry.status == .missed
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(missed ? "Missed" : entry.slot.day.formatted(.dateTime.weekday(.wide))).monoLabel()
                    .foregroundStyle(Design.Palette.fg3)
                    .lineLimit(1)
                Spacer(minLength: 0)
                statusTag(entry.status)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(PlanStore.name(session)).font(Design.Font.sans(17, weight: 700))
                    .foregroundStyle(missed ? Design.Palette.fg3 : Design.Palette.fg1)
                    .strikethrough(missed)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("\(PlanStore.minutes(session)) min" + PlanStore.notchNote(e, session, short: true))
                    .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3).lineLimit(1)
            }
            Spacer(minLength: 0)
            shape(entry.slot.week, entry.slot.index)
                .frame(maxWidth: .infinity).frame(minHeight: 28, maxHeight: 60)
                .opacity(missed ? 0.4 : 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground(selected: next))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusTag(_ status: TrainingPlan.Status) -> some View {
        switch status {
        case .done: Tag(title: "Done", color: Design.Status.go)
        case .today: Tag(title: "Today", fill: Design.Accent.vermilion)
        case .missed, .upcoming: EmptyView()
        }
    }

    // MARK: Every week

    /// Every week as a card: its sessions with their shapes and lengths. On the plan, their days and how they stand,
    /// the week you're in ringed, and the sessions your days leave out dimmed.
    private func weeks(schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)]) -> some View {
        let slots = Dictionary(schedule.map { ([$0.slot.week, $0.slot.index], $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("The plan · \(plan.weeks.count) week\(plan.weeks.count == 1 ? "" : "s")")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 260 : 280), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                // A plan's weeks are fixed: keyed by week number.
                ForEach(0..<plan.weeks.count, id: \.self) { w in
                    weekCard(w, slots: slots)
                }
            }
        }
    }

    private func weekCard(_ w: Int, slots: [[Int]: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)]) -> some View {
        let sessions = plan.weeks[w]
        let minutes = sessions.map(PlanStore.minutes).reduce(0, +)
        let current = enrolment.map { calendarWeek($0) == w } ?? false
        let rowHeight: CGFloat = 30, spacing: CGFloat = 8
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Week \(w + 1)").font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Palette.fg1)
                Text(String(format: "%d:%02d h", minutes / 60, minutes % 60)).font(Design.Font.mono(12))
                    .foregroundStyle(Design.Palette.fg3)
                Spacer(minLength: 0)
                if let e = enrolment { weekTag(e, w, slots: slots) }
            }
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(sessions.indices, id: \.self) { i in
                    sessionRow(w, i, entry: slots[[w, i]])
                        .frame(height: rowHeight)
                }
            }
            // As tall as the fullest week, so a row of cards lines up.
            .frame(minHeight: CGFloat(plan.sessionsPerWeek) * (rowHeight + spacing) - spacing, alignment: .top)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(selected: current))
    }

    /// Past weeks: how many were ridden; this one: This week; later ones: when they start.
    @ViewBuilder
    private func weekTag(_ e: PlanEnrolment, _ w: Int, slots: [[Int]: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)]) -> some View {
        let now = calendarWeek(e)
        if w == now {
            Tag(title: "This week", fill: Design.Accent.vermilion)
        } else if w < now {
            let kept = slots.values.filter { $0.slot.week == w }
            Tag(title: "\(kept.filter { $0.status == .done }.count) of \(kept.count) done")
        } else {
            Text(weekStart(e, w).formatted(.dateTime.day().month(.abbreviated))).font(Design.Font.mono(12))
                .foregroundStyle(Design.Palette.fg3)
        }
    }

    private func sessionRow(_ w: Int, _ i: Int, entry: (slot: TrainingPlan.Slot, status: TrainingPlan.Status)?) -> some View {
        let session = plan.weeks[w][i]
        let missed = entry?.status == .missed
        // On the plan, a session with no slot is one your days leave out.
        let left = enrolment != nil && entry == nil
        return HStack(spacing: 10) {
            if enrolment != nil {
                // A missed session has no day of its own any more (the schedule parks it on the week's last past one).
                Text(missed ? "" : entry?.slot.day.formatted(.dateTime.weekday(.abbreviated)) ?? "").font(Design.Font.mono(11))
                    .foregroundStyle(Design.Palette.fg3)
                    .frame(width: 32, alignment: .leading)
            }
            shape(w, i).frame(width: 52, height: 22)
            Text(PlanStore.name(session)).font(Design.Font.sans(14, weight: 600))
                .foregroundStyle(missed ? Design.Palette.fg3 : Design.Palette.fg1)
                .strikethrough(missed)
                .lineLimit(1)
            Spacer(minLength: 4)
            if entry?.status == .done {
                Icon("check", size: 14).foregroundStyle(Design.Status.go)
            } else {
                Text("\(PlanStore.minutes(session))′").font(Design.Font.mono(11)).foregroundStyle(Design.Palette.fg3)
            }
        }
        .opacity(left ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint(left ? "Not on your ride days" : "")
    }

    // MARK: Shapes

    /// A session's shape: the climb's profile, or the workout's blocks at its notch.
    @ViewBuilder
    private func shape(_ w: Int, _ i: Int, hero: Bool = false) -> some View {
        if case .route(let id) = plan.weeks[w][i], let route = RaceStore.climb(id: id)?.route {
            RouteStrip(route: route, color: hero ? Design.Palette.fgOnHero : Design.Palette.fg1,
                       fill: hero ? Design.Accent.teamBlue.opacity(0.38) : Design.Palette.terrainFill)
        } else if let workout = PlanStore.workout(id: "plan/\(plan.id)/\(w)-\(i)") {
            WorkoutStrip(workout: workout.drawable)
        }
    }
}
