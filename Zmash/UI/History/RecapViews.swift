import SwiftData
import SwiftUI
import ZmashKit

/// Building recaps from saved rides.
@MainActor
enum Recaps {
    static func rides(since: Date) -> [Recap.Ride] {
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.startedAt >= since })
        return ((try? RideStore.context.fetch(d)) ?? []).map { s in
            Recap.Ride(date: s.startedAt, seconds: s.activeSeconds, distanceM: s.distanceM, elevationM: s.elevationGainM,
                       routeID: s.routeID.map { RouteStore.split($0).base }, face: s.face, best20W: s.powerCurve[1200])
        }
    }

    static func summary(_ interval: DateInterval) -> Recap.Summary? {
        Recap.summarize(rides(since: interval.start), in: interval)
    }

    /// The recap worth showing on home now: last year's in the first two weeks of January, otherwise last month's in
    /// the first week of a month.
    static func current(now: Date = .now) -> (summary: Recap.Summary, yearly: Bool)? {
        let day = Calendar.current.component(.day, from: now), month = Calendar.current.component(.month, from: now)
        if month == 1, day <= 14, let s = summary(Recap.previousYear(of: now)) { return (s, true) }
        if day <= 7, let s = summary(Recap.previousMonth(of: now)) { return (s, false) }
        return nil
    }

    static func title(_ s: Recap.Summary, yearly: Bool) -> String {
        yearly ? s.interval.start.formatted(.dateTime.year()) : s.interval.start.formatted(.dateTime.month(.wide).year())
    }
}

/// The recap as a card to share: a hero card in the design system (bar-tape hatch, tri-stripe, bib numerals).
struct RecapCard: View {
    let summary: Recap.Summary
    let yearly: Bool
    let units: Units

    static let size = CGSize(width: 1200, height: 1320)
    private let bone = Design.Tarmac.bone
    private let bone2 = Design.Palette.fgOnHeroBody

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TriStripe(height: 14, mid: bone)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Wordmark(size: 56, color: bone)
                    Spacer()
                    Text(yearly ? "The year" : "The month").font(Design.Font.mono(28)).tracking(28 * 0.14).textCase(.uppercase)
                        .foregroundStyle(Design.Tarmac.bone2)
                }
                Text(Recaps.title(summary, yearly: yearly))
                    .font(Design.Font.sans(104, weight: 700)).tracking(104 * -0.025)
                    .foregroundStyle(bone).padding(.top, 48)
                    .lineLimit(1).minimumScaleFactor(0.6)

                Grid(alignment: .leading, horizontalSpacing: 70, verticalSpacing: 40) {
                    GridRow {
                        big(String(format: "%.0f", Double(summary.seconds) / 3600), "hours", lit: true)
                        big(String(format: "%.0f", units.distance(summary.distanceM)), units.distanceUnit)
                    }
                    GridRow {
                        big(String(format: "%.0f", units.elevation(summary.elevationM)), units.elevationUnit + " climbed")
                        big("\(summary.rides)", summary.rides == 1 ? "ride" : "rides")
                    }
                }
                .padding(.top, 50)

                VStack(alignment: .leading, spacing: 22) {
                    if summary.elevationM >= 1000 {
                        line(String(format: "%.2f × Everest", summary.elevationM / Records.everestM))
                    }
                    line("Longest ride " + TimeFormat.clock(summary.longestSeconds))
                    if let w = summary.best20W { line("Best 20 minutes \(w) W") }
                    if let top = summary.topRoute, let name = RouteStore.route(id: top.id)?.name {
                        line("\(name) × \(top.count)")
                    }
                    if let face = summary.favouriteFace.flatMap(FaceID.init) { line("Favourite face: \(face.name)") }
                    if summary.weekStreak > 1 { line("\(summary.weekStreak) weeks in a row") }
                }
                .padding(.top, 50)
                Spacer(minLength: 0)
                LaneDashes(color: bone.opacity(0.5), thickness: 6)
            }
            .padding(72)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(HatchFill(raised: false))
        .environment(\.colorScheme, .dark)
    }

    private func big(_ value: String, _ unit: String, lit: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(unit).font(Design.Font.mono(26)).tracking(26 * 0.14).textCase(.uppercase).foregroundStyle(Design.Tarmac.bone2)
            Text(value).font(Design.Font.bib(170)).foregroundStyle(lit ? Design.Accent.vermilion : bone)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(Design.Font.sans(40, weight: 500)).foregroundStyle(bone2)
    }
}

/// The recap full size, scaled to the screen, with Share.
struct RecapSheet: View {
    let summary: Recap.Summary
    let yearly: Bool
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let scale = min(geo.size.width / RecapCard.size.width, geo.size.height / RecapCard.size.height)
                RecapCard(summary: summary, yearly: yearly, units: prefs.units)
                    .scaleEffect(scale)
                    .frame(width: RecapCard.size.width * scale, height: RecapCard.size.height * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Design.Space.gutter)
            .screenBackground(stripe: false)
            .navigationTitle(Recaps.title(summary, yearly: yearly))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if let file {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: file, preview: SharePreview("Recap", image: file)) { Icon("share", size: 20) }
                            .accessibilityLabel("Share")
                    }
                }
            }
        }
        .task {
            file = PostcardRenderer.write(RecapCard(summary: summary, yearly: yearly, units: prefs.units),
                                          name: "Zmash " + Recaps.title(summary, yearly: yearly))
        }
    }
}

/// On home in the first days of a month (or January): last month's (or year's) numbers, and a way into the recap.
struct RecapBanner: View {
    @Environment(Preferences.self) private var prefs
    @AppStorage("recap.dismissed") private var dismissed = ""
    @State private var recap: (summary: Recap.Summary, yearly: Bool)?
    @State private var showing = false

    var body: some View {
        Group {
            if let recap, dismissed != key(recap.summary) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your " + Recaps.title(recap.summary, yearly: recap.yearly)).monoLabel()
                            .foregroundStyle(Design.Palette.fg3)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", Double(recap.summary.seconds) / 3600)).font(Design.Font.bib(26))
                            Text("h ·").foregroundStyle(Design.Palette.fg3)
                            Text(String(format: "%.0f", prefs.units.distance(recap.summary.distanceM))).font(Design.Font.bib(26))
                            Text(prefs.units.distanceUnit + " ·").foregroundStyle(Design.Palette.fg3)
                            Text(String(format: "%.0f", prefs.units.elevation(recap.summary.elevationM))).font(Design.Font.bib(26))
                            Text(prefs.units.elevationUnit + " climbed").foregroundStyle(Design.Palette.fg3)
                        }
                        .font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fg1)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    PillButton(title: "See the recap", compact: true) { showing = true }
                    RoundIconButton(icon: "x", size: 44) { dismissed = key(recap.summary) }
                        .accessibilityLabel("Hide the recap")
                }
                .card(padding: 16)
                .sheet(isPresented: $showing) { RecapSheet(summary: recap.summary, yearly: recap.yearly) }
            }
        }
        .task(id: prefs.riderID) {
            recap = Recaps.current()
        }
    }

    private func key(_ s: Recap.Summary) -> String { "\(s.interval.start.timeIntervalSince1970)" }
}

/// In Progress: open last month's or this year's recap any time.
struct RecapLinks: View {
    @State private var month: Recap.Summary?
    @State private var year: Recap.Summary?
    @State private var showing: (summary: Recap.Summary, yearly: Bool)?

    var body: some View {
        HStack(spacing: 12) {
            if let month { link(month, yearly: false) }
            if let year { link(year, yearly: true) }
        }
        .task {
            month = Recaps.summary(Recap.previousMonth(of: .now))
            let thisYear = Calendar.current.dateInterval(of: .year, for: .now)!
            year = Recaps.summary(DateInterval(start: thisYear.start, end: .now))
        }
        .sheet(isPresented: Binding(get: { showing != nil }, set: { if !$0 { showing = nil } })) {
            if let showing { RecapSheet(summary: showing.summary, yearly: showing.yearly) }
        }
    }

    private func link(_ s: Recap.Summary, yearly: Bool) -> some View {
        Button { showing = (s, yearly) } label: {
            Text((yearly ? "Your year so far" : "Your " + Recaps.title(s, yearly: false)) + " →")
                .font(Design.Font.small).foregroundStyle(Design.Palette.primary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
    }
}
