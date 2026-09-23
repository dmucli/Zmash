import SwiftUI
import ZmashKit

// MARK: - Race list

/// One race in the Route picker: name, year and country, and how big it is.
struct RaceRow: View {
    let race: Race
    let units: Units

    var body: some View {
        let routes = race.stages.map(race.route)
        let distance = routes.map(\.distanceM).reduce(0, +)
        let ascent = routes.map(\.ascentM).reduce(0, +)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(race.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Text("\(String(race.year)) · \(race.country)").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
            Spacer()
            Text([race.isOneDay ? nil : "\(race.stages.count) stages",
                  String(format: "%.0f %@", units.distance(distance), units.distanceUnit),
                  String(format: "%.0f %@", units.elevation(ascent), units.elevationUnit)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
        }
        .padding(.vertical, 6)
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
        List {
            Section {
                ForEach(race.stages, id: \.number) { stage in
                    NavigationLink {
                        StageView(race: race, stage: stage, choose: choose)
                    } label: {
                        StageRow(route: race.route(stage), number: stage.number, units: prefs.units, raceRelief: biggestRelief)
                    }
                    .listRowBackground(Design.Palette.surface)
                }
            } header: {
                Text("\(String(race.year)) · \(race.country) · \(race.stages.count) stages")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Design.Palette.background)
        .navigationTitle(race.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A famous climb in the Route picker: the name and side, where the profile comes from, and what it'll take.
struct ClimbRow: View {
    let climb: FamousClimb
    let selected: Bool
    let units: Units

    var body: some View {
        let route = climb.route
        let stats = RouteStats.of(route)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(climb.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Text("\(climb.side) · as in \(climb.source)").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
                Spacer()
                if selected { Icon("check", size: 18).foregroundStyle(Design.Palette.primary) }
                Text(TimeFormat.estimate(stats.estimatedSeconds))
                    .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
            }
            RouteStrip(route: route, color: Design.Palette.primary).frame(height: 40)
            Text(String(format: "%.1f %@ · %.0f %@ · %.1f %% avg", units.distance(stats.distanceM), units.distanceUnit,
                        units.elevation(stats.ascentM), units.elevationUnit, route.averageGrade))
                .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct StageRow: View {
    let route: Route
    let number: Int
    let units: Units
    let raceRelief: Double

    var body: some View {
        let stats = RouteStats.of(route)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stage \(number)").font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Spacer()
                Text(TimeFormat.estimate(stats.estimatedSeconds))
                    .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
            }
            let span = max(route.maxElevationM - route.minElevationM, raceRelief * 0.4, 60)
            RouteStrip(route: route, color: Design.Palette.primary, range: route.minElevationM...(route.minElevationM + span))
                .frame(height: 44)
            Text(summary(stats)).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
        }
        .padding(.vertical, 6)
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
                PreviewTitle(title: title, subtitle: subtitle)

                VStack(alignment: .leading, spacing: 10) {
                    ElevationProfile(route: route, climbs: stats.climbs, window: length == nil ? nil : window,
                                 units: units, drag: length == nil ? nil : { dx in drag(dx, stats: stats) })
                        .frame(height: 240)
                    if length != nil {
                        Text("Drag the window along the \(noun).")
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                }

                HStack(spacing: 28) {
                    Fact(value: String(format: "%.1f", units.distance(stats.distanceM)), label: units.distanceUnit)
                    Fact(value: String(format: "%.0f", units.elevation(stats.ascentM)), label: units.elevationUnit + " climbing")
                    Fact(value: TimeFormat.estimate(stats.estimatedSeconds), label: "at \(stats.paceW) W")
                    Fact(value: String(format: "%.0f", units.elevation(stats.highestM)), label: "highest " + units.elevationUnit)
                    Fact(value: String(format: "%.1f %%", stats.steepestKm), label: "steepest km")
                }

                // A climb page lists its own climb only if the road has more than one.
                if !stats.climbs.isEmpty, noun != "climb" || stats.climbs.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Climbs")
                        ClimbList(climbs: stats.climbs, units: units)
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
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Design.Palette.background)
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
        Button { withAnimation(.snappy(duration: 0.3)) { action() } } label: {
            Text(title).font(Design.Font.small).foregroundStyle(Design.Palette.primary)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
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
        ctx.fill(fill, with: .color(Design.Palette.primary.opacity(0.14)))

        // Climbs: filled darker, with their category above the summit.
        for climb in climbs {
            let a = Int(climb.startM / Route.step), b = min(Int((climb.startM + climb.lengthM) / Route.step), e.count - 1)
            guard b > a else { continue }
            var p = Path()
            p.move(to: CGPoint(x: point(a).x, y: top + plotH))
            for i in a...b { p.addLine(to: point(i)) }
            p.addLine(to: CGPoint(x: point(b).x, y: top + plotH))
            p.closeSubpath()
            ctx.fill(p, with: .color(Design.Palette.primary.opacity(0.28)))
            if let category = climb.category {
                let label = ctx.resolve(Text(category == .hc ? "HC" : category.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Design.Palette.primary))
                ctx.draw(label, at: CGPoint(x: min(max(point(b).x, 10), size.width - 10), y: point(b).y - 10), anchor: .bottom)
            }
        }
        ctx.stroke(outline, with: .color(Design.Palette.primary.opacity(0.8)), lineWidth: 1.5)

        // Distance marks.
        let unitM = units == .metric ? 1000.0 : 1609.344
        let total = route.distanceM / unitM
        let step: Double = total > 150 ? 50 : total > 60 ? 20 : total > 25 ? 10 : 5
        var mark = step
        while mark < total {
            let px = x(mark * unitM)
            let label = ctx.resolve(Text("\(Int(mark))").font(.system(size: 10, weight: .medium)).foregroundStyle(Design.Palette.secondary))
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
                ctx.fill(Path(CGRect(x: edge - 1, y: 0, width: 2, height: size.height - bottom)), with: .color(Design.Palette.primary))
            }
            ctx.fill(Path(roundedRect: CGRect(x: a, y: 0, width: b - a, height: 4), cornerRadius: 2), with: .color(Design.Palette.primary))
        }
    }
}

// MARK: - Climbs

private struct ClimbList: View {
    let climbs: [Climb]
    let units: Units

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(climbs.enumerated()), id: \.offset) { i, climb in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(climb.category.map { $0 == .hc ? "HC" : "Cat \($0.rawValue)" } ?? "")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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
                if i < climbs.count - 1 { Divider().overlay(Design.Palette.hairline) }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }
}
