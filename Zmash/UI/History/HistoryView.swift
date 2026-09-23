import SwiftData
import SwiftUI
import ZmashKit

/// Session history (brief §13): list or month calendar, detail, delete, ride again.
struct HistoryView: View {
    let rideAgain: (SessionPlan) -> Void

    @Environment(Preferences.self) private var prefs
    @Query(filter: #Predicate<RideSession> { $0.isComplete }, sort: \RideSession.startedAt, order: .reverse)
    private var sessions: [RideSession]
    @AppStorage("history.view") private var mode = "list"

    var body: some View {
        ZStack {
            Design.Palette.background.ignoresSafeArea()
            VStack(spacing: Design.Space.gutter) {
                Segmented(options: [("list", "List"), ("calendar", "Calendar"), ("trends", "Progress"), ("palmares", "Palmarès")],
                          selection: $mode)
                    .frame(maxWidth: 560)
                if mode == "palmares" {
                    // Worth showing before the first ride: the climbs waiting to be ridden.
                    PalmaresView(rideAgain: rideAgain)
                } else if sessions.isEmpty {
                    Spacer()
                    Text("No rides yet").font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
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
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionList: View {
    let sessions: [RideSession]
    let units: Units
    let rideAgain: (SessionPlan) -> Void

    var body: some View {
        List {
            ForEach(sessions) { s in
                NavigationLink {
                    SessionDetail(session: s, units: units, rideAgain: rideAgain)
                } label: {
                    SessionRow(session: s, units: units)
                }
                .listRowBackground(Design.Palette.background)
            }
            .onDelete { idx in idx.map { sessions[$0] }.forEach(RideStore.delete) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct SessionRow: View {
    let session: RideSession
    let units: Units

    var body: some View {
        HStack(spacing: Design.Space.gutter) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
            .frame(width: 110, alignment: .leading)
            Spacer()
            stat(TimeFormat.clock(session.activeSeconds), "time")
            stat(String(format: "%.1f", units.distance(session.distanceM)), units.distanceUnit)
            stat("\(session.avgPowerW)", "w")
            stat(String(format: "%.0f", session.kcal), "kcal")
            Circle()
                .fill(session.rpe.map { Design.accent(forGrade: Double($0) - 1) } ?? Design.Palette.hairline)
                .frame(width: 10, height: 10)
                .accessibilityLabel(session.rpe.map { "Effort \($0)" } ?? "No effort rating")
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Design.Font.number(18, weight: .medium)).foregroundStyle(Design.Palette.primary)
            Text(unit).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
        }
        .frame(minWidth: 64, alignment: .trailing)
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

    var body: some View {
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
        VStack(spacing: Design.Space.gutter) {
            HStack {
                Button { shift(-1) } label: { Icon("chevron-left").frame(width: 44, height: 44) }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Spacer()
                Button { shift(1) } label: { Icon("chevron-right").frame(width: 44, height: 44) }
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
                                rides: byDay[day] ?? [], selected: selectedDay == day)
                            .onTapGesture { selectedDay = (byDay[day]?.isEmpty == false) ? day : nil }
                    }
                    WeekTotal(rides: (0..<7).flatMap { byDay[cal.date(byAdding: .day, value: $0, to: weekStart)!] ?? [] })
                        .frame(width: 96)
                }
            }

            if let selectedDay, let rides = byDay[selectedDay] {
                List(rides) { s in
                    NavigationLink {
                        SessionDetail(session: s, units: units, rideAgain: rideAgain)
                    } label: {
                        SessionRow(session: s, units: units)
                    }
                    .listRowBackground(Design.Palette.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, Design.Space.gutter)
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

    var body: some View {
        let minutes = Double(rides.map(\.activeSeconds).reduce(0, +)) / 60
        VStack(spacing: 6) {
            Text(day.formatted(.dateTime.day()))
                .font(Design.Font.number(15, weight: .medium))
                .foregroundStyle(inMonth ? Design.Palette.primary : Design.Palette.hairline)
            Circle()
                .fill(Design.Palette.primary)
                .frame(width: rides.isEmpty ? 0 : min(22, 6 + minutes / 6), height: rides.isEmpty ? 0 : min(22, 6 + minutes / 6))
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Design.Palette.surface : .clear))
        .contentShape(Rectangle())
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(rides.count) rides")
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
            Design.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.block) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.startedAt.formatted(date: .complete, time: .shortened))
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        Text(TimeFormat.clock(session.activeSeconds))
                            .font(Design.Font.number(56)).foregroundStyle(Design.Palette.primary)
                    }
                    SummaryGrid(summary: session.summary, units: units)

                    let samples = session.samples
                    if samples.count > 10 {
                        let grades = samples.map(\.gradePercent)
                        ElevationStrip(grades: stride(from: 0, to: grades.count, by: max(1, grades.count / 200)).map { grades[$0] })
                            .frame(height: 64)
                        SessionCharts(samples: samples, units: units)
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

                    UploadRow(ride: session.finished)

                    HStack(spacing: 12) {
                        PrimaryButton(title: "Ride this again") { rideAgain(session.plan) }
                        if let postcardURL {
                            ShareLink(item: postcardURL, preview: SharePreview("Ride", image: postcardURL)) {
                                Icon("image", size: 22).foregroundStyle(Design.Palette.primary)
                                    .frame(width: 56, height: 56)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
                            }
                            .accessibilityLabel("Share a card")
                        }
                        if let fitURL {
                            ShareLink(item: fitURL) {
                                Icon("share").foregroundStyle(Design.Palette.primary)
                                    .frame(width: 56, height: 56)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
                            }
                            .accessibilityLabel("Export FIT file")
                        }
                        Button { confirmDelete = true } label: {
                            Icon("trash-2").foregroundStyle(Design.Palette.primary)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete ride")
                    }
                }
                .frame(maxWidth: 640)
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
                             units: units, title: session.workoutName, tss: session.tss),
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
