import SwiftData
import SwiftUI
import ZmashKit

/// Session history (brief §13): list or month calendar, detail, delete, ride again.
struct HistoryView: View {
    let rideAgain: (SessionPlan) -> Void

    @Environment(Preferences.self) private var prefs
    /// The current rider's rides (D112), filtered by the store rather than fetching everyone's.
    @Query private var sessions: [RideSession]
    @AppStorage("history.view") private var mode = "list"

    init(rideAgain: @escaping (SessionPlan) -> Void) {
        self.rideAgain = rideAgain
        // The rider can't change while History is open (switching is on home).
        let rid = Preferences.shared.riderID
        _sessions = Query(filter: #Predicate<RideSession> { $0.isComplete && $0.riderID == rid },
                          sort: \RideSession.startedAt, order: .reverse)
    }

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: Design.Space.gutter) {
                Segmented(options: [("list", "Rides"), ("calendar", "Calendar"), ("trends", "Progress"), ("palmares", "Palmarès")],
                          selection: $mode)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Design.Space.gutter)
                if mode == "palmares" {
                    // Worth showing before the first ride: the climbs waiting to be ridden.
                    PalmaresView(rideAgain: rideAgain)
                } else if sessions.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("No rides yet").font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                        Text("Each ride you save shows here, with its charts, and in the calendar and your progress.")
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Design.Space.gutter)
                    Spacer()
                } else if mode == "list" {
                    SessionList(sessions: sessions, units: prefs.units, rideAgain: rideAgain)
                } else if mode == "trends" {
                    TrendsView(sessions: sessions)
                } else {
                    CalendarView(sessions: sessions, units: prefs.units, rideAgain: rideAgain)
                }
            }
            .padding(.top, Design.Space.gutter)
        }
        .screenBackground(stripe: false)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionList: View {
    let sessions: [RideSession]
    let units: Units
    let rideAgain: (SessionPlan) -> Void
    @State private var deleting: RideSession?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sessions) { s in
                    NavigationLink {
                        SessionDetail(session: s, units: units, rideAgain: rideAgain)
                    } label: {
                        SessionRow(session: s, units: units)
                    }
                    .buttonStyle(PressStyle())
                    .contextMenu { Button("Delete…", role: .destructive) { deleting = s } }
                }
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, Design.Space.gutter)
            .padding(.bottom, Design.Space.block)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Delete this ride?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting { RideStore.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("If it counted for a plan session or a campaign's latest stage, that's to ride again.")
        }
    }
}

struct SessionRow: View {
    let session: RideSession
    let units: Units

    var body: some View {
        // All four numbers when there's room (iPad); time and distance on a phone held upright.
        ViewThatFits(in: .horizontal) {
            row(full: true)
            row(full: false)
        }
        .card(padding: 16)
    }

    private func row(full: Bool) -> some View {
        HStack(spacing: full ? Design.Space.gutter : 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · "
                     + session.startedAt.formatted(date: .omitted, time: .shortened))
                    .monoLabel().foregroundStyle(Design.Palette.fg3)
                    .lineLimit(1).minimumScaleFactor(0.75)
                // The stored names: rebuilding the ride's plan would load its whole route for every row.
                Text(session.workoutName ?? session.routeName ?? "Free ride")
                    .font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Palette.fg1)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stat(TimeFormat.clock(session.activeSeconds), "")
            stat(String(format: "%.1f", units.distance(session.distanceM)), units.distanceUnit)
            if full {
                stat("\(session.avgPowerW)", "w")
                stat(String(format: "%.0f", session.kcal), "kcal")
            }
            Circle()
                .fill(session.rpe.map { Design.Zone.color(forFTPFraction: 0.45 + Double($0) * 0.08) } ?? Design.Palette.fgGhost)
                .frame(width: 10, height: 10)
                .accessibilityLabel(session.rpe.map { "Effort \($0)" } ?? "No effort rating")
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(Design.Font.bib(26)).foregroundStyle(Design.Palette.fg1)
            Text(unit).font(Design.Font.sans(13)).foregroundStyle(Design.Palette.fg3)
        }
        .frame(minWidth: 72, alignment: .trailing)
    }
}

// MARK: - Calendar

private struct CalendarView: View {
    let sessions: [RideSession]
    let units: Units
    let rideAgain: (SessionPlan) -> Void

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?
    private let cal = Calendar.current

    /// Days with a plan session still to ride.
    private var plannedDays: Set<Date> {
        guard let e = PlanStore.current else { return [] }
        return Set(PlanStore.schedule(e).filter { $0.status == .today || $0.status == .upcoming }.map { cal.startOfDay(for: $0.slot.day) })
    }

    var body: some View {
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
        // Worked out once per draw, not once per day cell.
        let planned = plannedDays
        // Scrolls, so a short screen (a phone on its side) still reaches the day's rides under the month.
        ScrollView {
        VStack(spacing: Design.Space.gutter) {
            HStack {
                Button { shift(-1) } label: { Icon("chevron-left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Spacer()
                Button { shift(1) } label: { Icon("chevron-right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Design.Palette.primary)

            HStack(spacing: 0) {
                // Symbols repeat ("S", "T"): keyed by weekday position, a fixed range.
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdaySymbols[i]).font(Design.Font.small).foregroundStyle(Design.Palette.secondary).frame(maxWidth: .infinity)
                }
                Text("week").font(Design.Font.small).foregroundStyle(Design.Palette.secondary).frame(width: 96)
            }

            ForEach(weeks, id: \.self) { weekStart in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        let day = cal.date(byAdding: .day, value: i, to: weekStart)!
                        DayCell(day: day, inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                rides: byDay[day] ?? [], selected: selectedDay == day, planned: planned.contains(day))
                            .onTapGesture { selectedDay = (byDay[day]?.isEmpty == false) ? day : nil }
                    }
                    WeekTotal(rides: (0..<7).flatMap { byDay[cal.date(byAdding: .day, value: $0, to: weekStart)!] ?? [] })
                        .frame(width: 96)
                }
            }

            if let selectedDay, let rides = byDay[selectedDay] {
                LazyVStack(spacing: 10) {
                    ForEach(rides) { s in
                        NavigationLink {
                            SessionDetail(session: s, units: units, rideAgain: rideAgain)
                        } label: {
                            SessionRow(session: s, units: units)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(.horizontal, Design.Space.gutter)
        .padding(.bottom, Design.Space.block)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if abs(v.translation.width) > abs(v.translation.height) { shift(v.translation.width < 0 ? 1 : -1) }
        })
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) {
            month = cal.date(byAdding: .month, value: n, to: month)!
            selectedDay = nil
        }
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private var weeks: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: month)!.start
        let end = cal.dateInterval(of: .month, for: month)!.end
        var out: [Date] = []
        var d = start
        while d < end {
            out.append(d)
            d = cal.date(byAdding: .weekOfYear, value: 1, to: d)!
        }
        return out
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let rides: [RideSession]
    let selected: Bool
    /// A training-plan session falls on this day (shown as an outline until ridden).
    var planned = false

    var body: some View {
        let minutes = Double(rides.map(\.activeSeconds).reduce(0, +)) / 60
        VStack(spacing: 6) {
            Text(day.formatted(.dateTime.day()))
                .font(Design.Font.number(15, weight: .medium))
                .foregroundStyle(inMonth ? Design.Palette.primary : Design.Palette.fg3)
            ZStack {
                Circle()
                    .fill(Design.Accent.vermilion)
                    .frame(width: rides.isEmpty ? 0 : min(22, 6 + minutes / 6), height: rides.isEmpty ? 0 : min(22, 6 + minutes / 6))
                if planned, rides.isEmpty {
                    Circle().stroke(Design.Accent.vermilion, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 14, height: 14)
                }
            }
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            if selected { CardBackground(selected: true, radius: Design.Radius.md) }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(rides.count) rides" + (planned && rides.isEmpty ? ", plan session" : ""))
    }
}

private struct WeekTotal: View {
    let rides: [RideSession]

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if !rides.isEmpty {
                Text(TimeFormat.clock(rides.map(\.activeSeconds).reduce(0, +)))
                    .font(Design.Font.number(15, weight: .medium)).foregroundStyle(Design.Palette.primary)
                Text("\(Int(rides.map(\.kcal).reduce(0, +))) kcal")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Detail

struct SessionDetail: View {
    let session: RideSession
    let units: Units
    let rideAgain: (SessionPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var fitURL: URL?
    @State private var postcardURL: URL?

    var body: some View {
        ZStack {
            Color.clear
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.block) {
                    RideHeader(index: nil, meta: RideTitle.meta(session.startedAt, plan: session.plan),
                               title: session.workoutName ?? RideTitle.title(session.plan), compact: true) { EmptyView() }
                    SummaryGrid(summary: session.summary, units: units, columns: 3)

                    let samples = session.samples
                    if samples.count > 10 {
                        let grades = samples.map(\.gradePercent)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("The ride")
                            ElevationStrip(grades: stride(from: 0, to: grades.count, by: max(1, grades.count / 200)).map { grades[$0] })
                                .frame(height: 64)
                            SessionCharts(samples: samples, units: units)
                        }
                        .card(padding: 20)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        line("Terrain", setupText)
                        if let w = session.workoutName { line("Workout", w) }
                        if let tss = session.tss {
                            line("Load", "\(Int(tss.rounded())) tss" + (session.normalizedPowerW.map { " · \($0) w np" } ?? ""))
                        }
                        if let rpe = session.rpe { line("Effort", "\(rpe) / 10") }
                        if let note = session.note { line("Note", note) }
                    }

                    UploadRow(id: session.id) { session.finished }

                    HStack(spacing: 12) {
                        PrimaryButton(title: "Ride this again") { rideAgain(session.plan) }
                        if let postcardURL {
                            ShareLink(item: postcardURL, preview: SharePreview("Ride", image: postcardURL)) {
                                Icon("image", size: 20).foregroundStyle(Design.Palette.fg1)
                                    .frame(width: 54, height: 54)
                                    .background(Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1))
                            }
                            .accessibilityLabel("Share a card")
                        }
                        if let fitURL {
                            ShareLink(item: fitURL) {
                                Icon("share", size: 20).foregroundStyle(Design.Palette.fg1)
                                    .frame(width: 54, height: 54)
                                    .background(Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1))
                            }
                            .accessibilityLabel("Export FIT file")
                        }
                        Button { confirmDelete = true } label: {
                            Icon("trash-2", size: 20).foregroundStyle(Design.Palette.fg1)
                                .frame(width: 54, height: 54)
                                .background(Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete ride")
                    }
                }
                .frame(maxWidth: 820)
                .padding(Design.Space.gutter * 1.5)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Delete this ride?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                RideStore.delete(session)
                dismiss()
            }
        }
        .task {
            fitURL = writeFIT()
            postcardURL = PostcardRenderer.write(
                RidePostcard(startedAt: session.startedAt, summary: session.summary, samples: session.samples,
                             units: units, title: session.workoutName ?? session.routeName, tss: session.tss),
                name: "Zmash ride")
        }
    }

    /// FIT file for Strava, Garmin Connect, TrainingPeaks… written to a temp file for the share sheet.
    private func writeFIT() -> URL? {
        let samples = session.samples
        guard !samples.isEmpty else { return nil }
        let name = "Zmash " + session.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + ".fit"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = FITWriter.encode(startedAt: session.startedAt, samples: samples, summary: session.summary)
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private var setupText: String {
        let duration = session.plannedSeconds.map { "\($0 / 60) min" } ?? "free ride"
        guard session.terrainMode == RideControls.TerrainMode.auto.rawValue else { return "manual · \(duration)" }
        if session.drawing != nil { return ["drawn", session.effort, duration].compactMap { $0 }.joined(separator: " · ") }
        return [session.terrainType, session.effort, duration].compactMap { $0 }.joined(separator: " · ")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Design.Font.small).foregroundStyle(Design.Palette.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
        }
    }
}
