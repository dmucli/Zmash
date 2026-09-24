import SwiftUI
import ZmashKit

/// A training plan: what it is and how to start it, or, once you're on it, this week and the next session (D101).
struct PlanView: View {
    let plan: TrainingPlan
    /// Home's preview goes back to the workout once a session is set up.
    let close: () -> Void
    /// In home's preview (D144): no page background, and the card's margins.
    var embedded = false
    @Environment(Preferences.self) private var prefs
    @State private var enrolment: PlanEnrolment?
    @State private var weekdays: Set<Int> = [3, 5, 7]
    @State private var startNextWeek = false
    @State private var confirmLeave = false
    /// Changing ride days while on the plan: the days being picked, or nil when not editing.
    @State private var newDays: Set<Int>?

    /// Plan weeks run Monday to Sunday (the schedule uses the same calendar).
    private let calendar = Calendar.mondayFirst

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PreviewTitle(title: plan.name, subtitle: plan.summary)
                if let enrolment { onPlan(enrolment) } else { setUp }
                weeksOverview
            }
            .padding(embedded ? 22 : 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: embedded ? .leading : .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(embedded ? .clear : Design.Palette.background)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { enrolment = PlanStore.current.flatMap { $0.planID == plan.id ? $0 : nil } }
        .confirmationDialog("Leave the plan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                guard var e = enrolment else { return }
                e.left = true
                PlanStore.save(e)
                enrolment = nil
            }
        }
    }

    // MARK: Starting

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Your ride days")
            dayPicker($weekdays)
            Text(weekdays.count < plan.sessionsPerWeek
                 ? "With \(weekdays.count) day\(weekdays.count == 1 ? "" : "s") a week, the most important \(weekdays.count == 1 ? "session is" : "sessions are") kept."
                 : "\(plan.sessionsPerWeek) sessions a week on those days; a missed one moves to your next ride day that week.")
                .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            Segmented(options: [(false, "Start this week"), (true, "Start next Monday")], selection: $startNextWeek)
            if !startNextWeek, let short = shortFirstWeek {
                Text(short).font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Start the plan", enabled: !weekdays.isEmpty) {
                let start = startNextWeek
                    ? Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: .now)!.end
                    : calendar.startOfDay(for: .now)
                enrolment = PlanStore.enrol(plan, weekdays: weekdays, start: start)
            }
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
                        .background(Circle().fill(on ? Design.Palette.primary : Design.Palette.surface))
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

    private func onPlan(_ e: PlanEnrolment) -> some View {
        let schedule = PlanStore.schedule(e)
        let next = schedule.first { $0.status == .today || $0.status == .upcoming }
        let week = next?.slot.week ?? (plan.weeks.count - 1)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 28) {
                Fact(value: "\(week + 1) / \(plan.weeks.count)", label: "week")
                Fact(value: "\(e.done.count)", label: "sessions done")
                Fact(value: "\(schedule.filter { $0.status == .missed }.count)", label: "missed")
            }
            if let next, let session = PlanStore.session(e, week: next.slot.week, index: next.slot.index) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(next.status == .today ? "Today" : "Next · " + next.slot.day.formatted(.dateTime.weekday(.wide)))
                        .monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
                    Text(PlanStore.name(session)).textStyle(.display, size: 34)
                        .foregroundStyle(Design.Palette.fgOnHero)
                    Text("\(PlanStore.minutes(session)) min" + notchNote(e, session))
                        .font(Design.Font.body).foregroundStyle(Design.Palette.fgOnHeroBody)
                    PrimaryButton(title: "Ride this", icon: "play") {
                        // Starts the session (home waits a moment for the trainer, or sets it up there without one).
                        if let p = PlanStore.rideablePlan(e, week: next.slot.week, index: next.slot.index, prefs: prefs) {
                            close()
                            try? IntentRouter.shared.ride(p)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 24, hero: true)
            } else {
                Text("Plan complete.").font(Design.Font.label).foregroundStyle(Design.Palette.primary)
            }
            thisWeek(e, schedule: schedule, week: week)
            if let days = newDays {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Your ride days")
                    dayPicker(Binding(get: { newDays ?? days }, set: { newDays = $0 }))
                    HStack(spacing: 12) {
                        PrimaryButton(title: "Save days", enabled: !days.isEmpty) {
                            var changed = e
                            changed.weekdays = days
                            PlanStore.save(changed)
                            enrolment = changed
                            newDays = nil
                        }
                        Button("Cancel") { newDays = nil }.font(Design.Font.label).buttonStyle(.plain).frame(minHeight: 44)
                    }
                }
            }
            HStack(spacing: 24) {
                if newDays == nil {
                    Button("Change ride days") { newDays = e.weekdays }
                        .font(Design.Font.small).buttonStyle(.plain).frame(minHeight: 44)
                }
                Button("Leave the plan", role: .destructive) { confirmLeave = true }
                    .font(Design.Font.small).buttonStyle(.plain).frame(minHeight: 44)
            }
        }
    }

    private func notchNote(_ e: PlanEnrolment, _ session: TrainingPlan.Session) -> String {
        guard case .intervals(let family, _, _) = session, let n = e.notches[family.rawValue], n != 0 else { return "" }
        return " · \(abs(n) * 3) % \(n > 0 ? "harder" : "easier") after your last \(family.name.lowercased()) sessions"
    }

    private func thisWeek(_ e: PlanEnrolment, schedule: [(slot: TrainingPlan.Slot, status: TrainingPlan.Status)], week: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Week \(week + 1)")
            VStack(spacing: 0) {
                ForEach(schedule.filter { $0.slot.week == week }, id: \.slot.index) { entry in
                    HStack(spacing: 12) {
                        Icon(entry.status == .done ? "check" : entry.status == .missed ? "x" : "chevron-right", size: 16)
                            .foregroundStyle(entry.status == .done ? Design.accent(forGrade: 8) : Design.Palette.secondary)
                        Text(entry.slot.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary).frame(width: 44, alignment: .leading)
                        Text(PlanStore.session(e, week: entry.slot.week, index: entry.slot.index).map(PlanStore.name) ?? "")
                            .font(Design.Font.label).foregroundStyle(entry.status == .missed ? Design.Palette.secondary : Design.Palette.primary)
                            .strikethrough(entry.status == .missed)
                        Spacer()
                        Text(label(entry.status)).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                }
            }
            .background(CardBackground())
        }
    }

    private func label(_ s: TrainingPlan.Status) -> String {
        switch s {
        case .done: "done"
        case .missed: "missed"
        case .today: "today"
        case .upcoming: ""
        }
    }

    // MARK: Overview

    private var weeksOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("The plan")
            VStack(alignment: .leading, spacing: 0) {
                // A plan's weeks are fixed: keyed by week number.
                ForEach(0..<plan.weeks.count, id: \.self) { w in
                    let sessions = plan.weeks[w]
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Week \(w + 1)").font(Design.Font.small).foregroundStyle(Design.Palette.secondary).frame(width: 64, alignment: .leading)
                        Text(sessions.map(PlanStore.name).joined(separator: " · "))
                            .font(Design.Font.small).foregroundStyle(Design.Palette.primary)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                }
            }
            .background(CardBackground())
        }
    }
}
