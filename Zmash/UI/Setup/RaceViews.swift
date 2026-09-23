import SwiftUI
import ZmashKit

// MARK: - Race list

/// One race in the Route picker: name, year and country, and how big it is, as a card.
struct RaceRow: View {
    let race: Race
    var index: Int? = nil
    let units: Units
    var selected = false

    var body: some View {
        let routes = race.stages.map(race.route)
        let distance = routes.map(\.distanceM).reduce(0, +)
        let ascent = routes.map(\.ascentM).reduce(0, +)
        PickCard(index: index, title: race.name, subtitle: "\(String(race.year)) · \(race.country)",
                 meta: [race.isOneDay ? nil : "\(race.stages.count) stages",
                        String(format: "%.0f %@", units.distance(distance), units.distanceUnit),
                        String(format: "%.0f %@", units.elevation(ascent), units.elevationUnit)]
                     .compactMap { $0 }.joined(separator: " · "),
                 selected: selected) {
            if race.isOneDay, let r = routes.first {
                RouteStrip(route: r).frame(height: 36)
            } else {
                StageBars(routes: routes).frame(height: 36)
            }
        }
    }
}

/// A stage race at a glance: one bar per stage, as tall as its climbing: rest-grey when flat, terrain blue when hilly,
/// vermilion for the mountain stages.
struct StageBars: View {
    let routes: [Route]

    var body: some View {
        Canvas { ctx, size in
            guard !routes.isEmpty else { return }
            let peak = max(routes.map(\.ascentM).max() ?? 1, 1)
            let w = size.width / CGFloat(routes.count)
            for (i, r) in routes.enumerated() {
                let h = max(3, CGFloat(r.ascentM / peak) * size.height)
                let rect = CGRect(x: CGFloat(i) * w, y: size.height - h, width: max(w - 2, 1), height: h)
                let tint = r.ascentM > 3000 ? Design.Accent.vermilion : r.ascentM > 1500 ? Design.Zone.z2 : Design.Palette.blockRest
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, w / 3)), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Race page

/// A stage race: every stage with its profile and what it'll take.
struct RaceView: View {
    let race: Race
    let choose: (String) -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        // One height scale across the race, as in a race book, so flat stages look flatter than mountain ones.
        // Each stage keeps its own baseline, and the scale never drops below 40 % of the race's biggest relief,
        // so a flat stage still shows its texture.
        let biggestRelief = race.stages.map { Double(($0.elevations.max() ?? 0) - ($0.elevations.min() ?? 0)) }.max() ?? 200
        GeometryReader { geo in
            let compact = geo.size.width < 700
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: race.name, kicker: "\(String(race.year)) · \(race.country) · \(race.stages.count) stages", compact: compact)
                    NavigationLink {
                        CampaignView(race: race, choose: choose)
                    } label: {
                        let active = CampaignStore.active(raceID: race.id)
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Campaign").monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
                                Text(active == nil ? "Ride it as a campaign" : "Your campaign · stage \(active.flatMap(CampaignStore.nextStage)?.number ?? race.stages.count) next")
                                    .textStyle(.h2, size: compact ? 20 : 26).foregroundStyle(Design.Palette.fgOnHero)
                                Text("Stage by stage against 20 rivals, with a general classification and mountains points.")
                                    .font(Design.Font.small).foregroundStyle(Color(hex: 0xC9C4B8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Icon("chevron-right", size: 20).foregroundStyle(Design.Palette.fgOnHero)
                        }
                        .card(padding: 22, hero: true)
                    }
                    .buttonStyle(PressStyle())
                    SectionHeader("Stages")
                    CardGrid {
                        ForEach(race.stages, id: \.number) { stage in
                            NavigationLink {
                                StageView(race: race, stage: stage, choose: choose)
                            } label: {
                                StageRow(route: race.route(stage), number: stage.number, units: prefs.units, raceRelief: biggestRelief)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .pagePadding(compact)
            }
        }
        .screenBackground(stripe: false)
        .navigationTitle(race.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A famous climb in the Route picker: the name and side, where the profile comes from, and what it'll take.
struct ClimbRow: View {
    let climb: FamousClimb
    var index: Int? = nil
    let selected: Bool
    let units: Units

    var body: some View {
        let route = climb.route
        let stats = RouteStats.of(route)
        PickCard(index: index, title: climb.name, subtitle: "\(climb.side) · as in \(climb.source)",
                 meta: String(format: "%.1f %@ · %.0f %@ · %.1f %% · ", units.distance(stats.distanceM), units.distanceUnit,
                              units.elevation(stats.ascentM), units.elevationUnit, route.averageGrade)
                     + TimeFormat.estimate(stats.estimatedSeconds),
                 selected: selected) {
            RouteStrip(route: route).frame(height: 44)
        }
    }
}

private struct StageRow: View {
    let route: Route
    let number: Int
    let units: Units
    let raceRelief: Double

    var body: some View {
        let stats = RouteStats.of(route)
        let span = max(route.maxElevationM - route.minElevationM, raceRelief * 0.4, 60)
        PickCard(index: number, title: "Stage \(number)", subtitle: TimeFormat.estimate(stats.estimatedSeconds) + " at your pace",
                 meta: summary(stats)) {
            RouteStrip(route: route, range: route.minElevationM...(route.minElevationM + span)).frame(height: 48)
        }
    }

    private func summary(_ s: RouteStats) -> String {
        var parts = [String(format: "%.0f %@", units.distance(s.distanceM), units.distanceUnit),
                     String(format: "%.0f %@", units.elevation(s.ascentM), units.elevationUnit)]
        if !s.climbs.isEmpty {
            let hardest = s.climbs.compactMap(\.category).min { Climb.Category.allCases.firstIndex(of: $0)! < Climb.Category.allCases.firstIndex(of: $1)! }
            parts.append("\(s.climbs.count) climb\(s.climbs.count == 1 ? "" : "s")" + (hardest.map { $0 == .hc ? " · HC" : " · cat \($0.rawValue)" } ?? ""))
        } else {
            parts.append("flat")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stage page

/// One stage, one-day race or famous climb: the profile with its climbs, the numbers, and which part to ride.
struct StageView: View {
    let route: Route
    /// The id chosen for the whole thing; a segment adds its window to it.
    let baseID: String
    let title: String
    let subtitle: String
    let navigationTitle: String
    let noun: String
    let choose: (String) -> Void
    @Environment(Preferences.self) private var prefs

    /// nil = the whole stage.
    @State private var length: Double?
    @State private var fromM: Double = 0
    @State private var didSetDefault = false

    init(race: Race, stage: Stage, choose: @escaping (String) -> Void) {
        route = race.route(stage)
        baseID = race.routeID(stage)
        title = race.isOneDay ? race.name : "Stage \(stage.number)"
        subtitle = race.isOneDay ? "\(String(race.year)) · \(race.country)" : "\(race.name) · \(String(race.year)) · \(race.country)"
        navigationTitle = race.isOneDay ? race.name : "\(race.name) · Stage \(stage.number)"
        noun = race.isOneDay ? "race" : "stage"
        self.choose = choose
    }

    init(climb: FamousClimb, choose: @escaping (String) -> Void) {
        route = climb.route
        baseID = climb.id
        title = climb.name
        subtitle = "\(climb.side) · as ridden in \(climb.source)"
        navigationTitle = climb.name
        noun = "climb"
        self.choose = choose
    }

    private static let lengths: [(Double?, String)] = [(nil, "Full"), (1800, "30 min"), (2700, "45 min"),
                                                       (3600, "1 h"), (5400, "1 h 30"), (7200, "2 h")]

    var body: some View {
        let route = route
        let stats = RouteStats.of(route)
        let units = prefs.units
        let options = Self.lengths.filter { $0.0 == nil || $0.0! < stats.estimatedSeconds * 0.9 }
        let window = segment(stats)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: title, kicker: subtitle)

                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ElevationProfile(route: route, climbs: stats.climbs, window: length == nil ? nil : window,
                                 units: units, drag: length == nil ? nil : { dx in drag(dx, stats: stats) })
                        .frame(height: 240)
                    if length != nil {
                        Text("Drag the window along the \(noun).")
                            .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    }
                }

                HStack(spacing: 28) {
                    Fact(value: String(format: "%.1f", units.distance(stats.distanceM)), label: units.distanceUnit)
                    Fact(value: String(format: "%.0f", units.elevation(stats.ascentM)), label: units.elevationUnit + " climbing")
                    Fact(value: TimeFormat.estimate(stats.estimatedSeconds), label: "at \(stats.paceW) W")
                    Fact(value: String(format: "%.0f", units.elevation(stats.highestM)), label: "highest " + units.elevationUnit)
                    Fact(value: String(format: "%.1f %%", stats.steepestKm), label: "steepest km")
                }
                }
                .card(padding: 22)

                // A climb page lists its own climb only if the road has more than one.
                if !stats.climbs.isEmpty, noun != "climb" || stats.climbs.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Climbs")
                        ClimbList(climbs: stats.climbs, units: units).padding(.horizontal, 18).card(padding: 0)
                    }
                }

                // Short roads only ride whole: no choice to show.
                if options.count > 1 {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Ride")
                    Segmented(options: options, selection: Binding(get: { length }, set: { pick($0, stats: stats) }))
                    if let length {
                        HStack(spacing: 8) {
                            preset("Start") { fromM = 0 }
                            preset("Hardest") { fromM = stats.timing.hardestStart(for: length, elevations: route.elevations) }
                            preset("Finale") { fromM = stats.timing.latestStart(for: length) }
                        }
                        let part = route.slice(fromM: window.lowerBound, toM: window.upperBound)
                        HStack(spacing: 28) {
                            Fact(value: String(format: "%.0f–%.0f", units.distance(window.lowerBound), units.distance(window.upperBound)),
                                 label: "segment · " + units.distanceUnit)
                            Fact(value: String(format: "%.1f", units.distance(part.distanceM)), label: units.distanceUnit)
                            Fact(value: String(format: "%.0f", units.elevation(part.ascentM)), label: units.elevationUnit + " climbing")
                            Fact(value: TimeFormat.estimate(stats.timing.times[index(window.upperBound, stats)] - stats.timing.times[index(window.lowerBound, stats)]),
                                 label: "at \(stats.paceW) W")
                        }
                    }
                }
                }

                PrimaryButton(title: length == nil ? "Ride the whole \(noun)" : "Ride this segment") {
                    choose(length == nil ? baseID : RouteStore.segmentID(baseID, fromM: window.lowerBound, toM: window.upperBound))
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .screenBackground(stripe: false)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSetDefault else { return }
            didSetDefault = true
            // A long stage opens on its last hour: races are decided in the finale. A climb opens whole.
            if noun != "climb", stats.estimatedSeconds > 4500 { pick(3600, stats: stats) }
        }
    }

    private func pick(_ newLength: Double?, stats: RouteStats) {
        length = newLength
        if let newLength { fromM = stats.timing.latestStart(for: newLength) }
    }

    /// The window: from the start point, as far as the chosen time takes you.
    private func segment(_ stats: RouteStats) -> ClosedRange<Double> {
        guard let length else { return 0...stats.distanceM }
        let from = min(fromM, stats.timing.latestStart(for: length))
        return from...max(from + Route.step, stats.timing.end(after: length, from: from))
    }

    private func drag(_ dxFraction: Double, stats: RouteStats) {
        guard let length else { return }
        fromM = min(max(fromM + dxFraction * stats.distanceM, 0), stats.timing.latestStart(for: length))
    }

    private func index(_ m: Double, _ stats: RouteStats) -> Int {
        min(max(Int((m / Route.step).rounded()), 0), stats.timing.times.count - 1)
    }

    private func preset(_ title: String, action: @escaping () -> Void) -> some View {
        Chip(title: title) { withAnimation(Design.Motion.base) { action() } }
    }
}

// MARK: - Profile

/// An elevation profile in real metres, with its climbs picked out, distance marks, and a segment window if there
/// is one. Used for race stages and for the home screen's generated course.
struct ElevationProfile: View {
    let route: Route
    let climbs: [Climb]
    var window: ClosedRange<Double>? = nil
    let units: Units
    /// Called with the drag's horizontal movement as a fraction of the profile's width.
    var drag: ((Double) -> Void)? = nil
    /// The smallest height range drawn, so gentle roads look gentle instead of being stretched to fill the card.
    var minRelief: Double = 60

    @State private var lastX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(in: &ctx, size: size)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard let drag else { return }
                    let dx = v.location.x - (lastX ?? v.location.x)
                    lastX = v.location.x
                    drag(Double(dx / max(geo.size.width, 1)))
                }
                .onEnded { _ in lastX = nil },
                including: drag == nil ? .subviews : .all)
        }
        .accessibilityElement()
        .accessibilityLabel("Elevation profile")
        .accessibilityValue(window.map { String(format: "Segment from km %.0f to %.0f", $0.lowerBound / 1000, $0.upperBound / 1000) } ?? "")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let e = route.elevations
        guard e.count > 1 else { return }
        let top: CGFloat = 26, bottom: CGFloat = 22
        let plotH = size.height - top - bottom
        let lo = route.minElevationM, hi = route.maxElevationM
        let span = max(hi - lo, minRelief)
        let x = { (m: Double) in CGFloat(m / max(route.distanceM, 1)) * size.width }
        let y = { (v: Double) in top + plotH - CGFloat((v - lo) / span) * plotH }
        let point = { (i: Int) in CGPoint(x: x(Double(i) * Route.step), y: y(e[i])) }

        var outline = Path()
        outline.move(to: point(0))
        for i in 1..<e.count { outline.addLine(to: point(i)) }
        var fill = outline
        fill.addLine(to: CGPoint(x: size.width, y: top + plotH))
        fill.addLine(to: CGPoint(x: 0, y: top + plotH))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(Design.Palette.terrainFill))

        // Climbs: filled darker, with their category above the summit.
        for climb in climbs {
            let a = Int(climb.startM / Route.step), b = min(Int((climb.startM + climb.lengthM) / Route.step), e.count - 1)
            guard b > a else { continue }
            var p = Path()
            p.move(to: CGPoint(x: point(a).x, y: top + plotH))
            for i in a...b { p.addLine(to: point(i)) }
            p.addLine(to: CGPoint(x: point(b).x, y: top + plotH))
            p.closeSubpath()
            ctx.fill(p, with: .color(Design.Palette.terrain.opacity(0.3)))
            if let category = climb.category {
                let label = ctx.resolve(Text(category == .hc ? "HC" : category.rawValue)
                    .font(Design.Font.mono(11, weight: 700)).foregroundStyle(Design.Palette.fg1))
                ctx.draw(label, at: CGPoint(x: min(max(point(b).x, 10), size.width - 10), y: point(b).y - 10), anchor: .bottom)
            }
        }
        ctx.stroke(outline, with: .color(Design.Palette.fg1), lineWidth: 1.5)

        // Distance marks.
        let unitM = units == .metric ? 1000.0 : 1609.344
        let total = route.distanceM / unitM
        let step: Double = total > 150 ? 50 : total > 60 ? 20 : total > 25 ? 10 : 5
        var mark = step
        while mark < total {
            let px = x(mark * unitM)
            let label = ctx.resolve(Text("\(Int(mark))").font(Design.Font.mono(10)).foregroundStyle(Design.Palette.fg3))
            // A mark at the very end sits inside the edge rather than half off it.
            let half = label.measure(in: size).width / 2
            ctx.draw(label, at: CGPoint(x: min(max(px, half), size.width - half), y: size.height - 2), anchor: .bottom)
            ctx.fill(Path(CGRect(x: px - 0.5, y: top + plotH, width: 1, height: 4)), with: .color(Design.Palette.secondary))
            mark += step
        }

        // The segment: everything outside it dims, and its edges are marked.
        if let window {
            let a = x(window.lowerBound), b = x(window.upperBound)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: a, height: size.height - bottom)), with: .color(Design.Palette.background.opacity(0.6)))
            ctx.fill(Path(CGRect(x: b, y: 0, width: size.width - b, height: size.height - bottom)), with: .color(Design.Palette.background.opacity(0.6)))
            for edge in [a, b] {
                ctx.fill(Path(CGRect(x: edge - 1, y: 0, width: 2, height: size.height - bottom)), with: .color(Design.Accent.vermilion))
            }
            ctx.fill(Path(roundedRect: CGRect(x: a, y: 0, width: b - a, height: 4), cornerRadius: 2), with: .color(Design.Accent.vermilion))
        }
    }
}

// MARK: - Climbs

private struct ClimbList: View {
    let climbs: [Climb]
    let units: Units

    var body: some View {
        VStack(spacing: 0) {
            ForEach(climbs, id: \.startM) { climb in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(climb.category.map { $0 == .hc ? "HC" : "Cat \($0.rawValue)" } ?? "")
                        .font(Design.Font.mono(12, weight: 700))
                        .foregroundStyle(Design.Palette.primary)
                        .frame(width: 48, alignment: .leading)
                    Text(String(format: "%@ %.0f", units.distanceUnit, units.distance(climb.startM)))
                        .frame(width: 70, alignment: .leading)
                    Text(String(format: "%.1f %@ at %.1f %%", units.distance(climb.lengthM), units.distanceUnit, climb.averageGrade))
                    Spacer()
                    Text(String(format: "+%.0f %@ · top %.0f %@", units.elevation(climb.gainM), units.elevationUnit,
                                units.elevation(climb.summitElevationM), units.elevationUnit))
                        .foregroundStyle(Design.Palette.secondary)
                }
                .font(Design.Font.small.monospacedDigit())
                .foregroundStyle(Design.Palette.primary)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    if climb.startM != climbs.last?.startM { Divider().overlay(Design.Palette.hairline) }
                }
            }
        }
    }
}
