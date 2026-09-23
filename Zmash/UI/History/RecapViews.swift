import SwiftData
import SwiftUI
import ZmashKit

/// Building recaps from saved rides.
@MainActor
enum Recaps {
    static func rides(since: Date) -> [Recap.Ride] {
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.startedAt >= since })
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

/// The recap as a card to share, in the ride postcard's style.
struct RecapCard: View {
    let summary: Recap.Summary
    let yearly: Bool
    let units: Units

    static let size = CGSize(width: 1200, height: 1320)
    private let paper = Color(hex: 0xF2EFE8)
    private let ink = Color(hex: 0x141414)
    private let accent = Color(hex: 0xC8341B)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ZMASH").font(FaceFont.font(.archivo, 34, weight: 600)).tracking(34 * 0.3)
                Spacer()
                Text(yearly ? "THE YEAR" : "THE MONTH").font(FaceFont.font(.archivo, 26, weight: 450)).tracking(26 * 0.2)
            }
            Rectangle().fill(ink).frame(height: 2).padding(.top, 22)
            Text(Recaps.title(summary, yearly: yearly).uppercased())
                .font(FaceFont.font(.archivo, 96, weight: 600)).tracking(96 * 0.02)
                .foregroundStyle(accent).padding(.top, 40)
                .lineLimit(1).minimumScaleFactor(0.6)

            Grid(alignment: .leading, horizontalSpacing: 60, verticalSpacing: 44) {
                GridRow {
                    big(String(format: "%.0f", Double(summary.seconds) / 3600), "hours")
                    big(String(format: "%.0f", units.distance(summary.distanceM)), units.distanceUnit)
                }
                GridRow {
                    big(String(format: "%.0f", units.elevation(summary.elevationM)), units.elevationUnit + " climbed")
                    big("\(summary.rides)", summary.rides == 1 ? "ride" : "rides")
                }
            }
            .padding(.top, 56)

            VStack(alignment: .leading, spacing: 24) {
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
            .padding(.top, 56)
            Spacer(minLength: 0)
            Rectangle().fill(ink).frame(height: 2)
        }
        .foregroundStyle(ink)
        .padding(72)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(paper)
    }

    private func big(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(FaceFont.font(.archivo, 132, weight: 400)).lineLimit(1).minimumScaleFactor(0.5)
            Text(unit.uppercased()).font(FaceFont.font(.archivo, 26, weight: 500)).tracking(26 * 0.2)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(FaceFont.font(.archivo, 42, weight: 450))
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
            .background(Design.Palette.background)
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
    @State private var loaded = false
    @State private var showing = false

    var body: some View {
        Group {
            if let recap, dismissed != key(recap.summary) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your " + Recaps.title(recap.summary, yearly: recap.yearly))
                            .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                        Text(String(format: "%.0f h · %.0f %@ · %.0f %@ climbed", Double(recap.summary.seconds) / 3600,
                                    prefs.units.distance(recap.summary.distanceM), prefs.units.distanceUnit,
                                    prefs.units.elevation(recap.summary.elevationM), prefs.units.elevationUnit))
                            .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("See the recap") { showing = true }
                        .font(Design.Font.small).buttonStyle(.plain).foregroundStyle(Design.Palette.primary)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Capsule().fill(Design.Palette.background))
                    Button { dismissed = key(recap.summary) } label: {
                        Icon("x", size: 16).foregroundStyle(Design.Palette.secondary).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Hide the recap")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
                .sheet(isPresented: $showing) { RecapSheet(summary: recap.summary, yearly: recap.yearly) }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
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
