import SwiftUI
import ZmashKit

/// Your palmarès: lifetime totals told in cycling terms, and every famous climb, ticked once you've been up it,
/// with your best time and VAM. Climbs not yet ridden are faded, with a way to ride them.
struct PalmaresView: View {
    let rideAgain: (SessionPlan) -> Void
    @Environment(Preferences.self) private var prefs
    @State private var bests: [String: Records.Effort] = [:]
    @State private var totals = Records.Totals()
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                counters
                ForEach(countries, id: \.self) { country in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(Locale.current.localizedString(forRegionCode: country) ?? country)
                        CardGrid(minimum: 250) {
                            ForEach(RaceStore.climbs.filter { $0.country == country }) { climb in
                                ClimbTile(climb: climb, best: bests[climb.id], units: prefs.units) {
                                    var plan = prefs.lastPlan
                                    plan.workoutID = nil
                                    plan.routeID = climb.id
                                    rideAgain(plan)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 1000)
            .padding(Design.Space.gutter * 1.5)
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !loaded else { return }
            loaded = true
            bests = Records.bests(Palmares.allEfforts())
            totals = Palmares.totals()
        }
    }

    private var countries: [String] {
        RaceStore.climbs.map(\.country).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private var counters: some View {
        let units = prefs.units
        let ventoux = RaceStore.climb(id: "climb/mont-ventoux-bedoin")?.route.ascentM ?? 1600
        let tour = RaceStore.races.first { $0.id == "2025/tour-de-france" }
            .map { r in r.stages.map { r.route($0).distanceM }.reduce(0, +) } ?? 3_300_000
        let ridden = bests.count, all = RaceStore.climbs.count
        return VStack(alignment: .leading, spacing: 14) {
            // The climbing total is the hero: it's the number cyclists tell each other.
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Climbed, all time").monoLabel().foregroundStyle(Design.Palette.fgOnHero2)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", units.elevation(totals.elevationM))).font(Design.Font.bib(96))
                            .foregroundStyle(Design.Palette.fgOnHero)
                        Text(units.elevationUnit).font(Design.Font.sans(18)).foregroundStyle(Design.Palette.fgOnHero2)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    Text(String(format: "%.1f × Everest · %.0f × Ventoux", totals.elevationM / Records.everestM, totals.elevationM / ventoux))
                        .font(Design.Font.body).foregroundStyle(Color(hex: 0xC9C4B8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RouteStrip(route: RaceStore.climb(id: "climb/mont-ventoux-bedoin")?.route ?? RaceStore.climbs[0].route,
                           color: Design.Palette.fgOnHero, fill: Design.Accent.teamBlue.opacity(0.38))
                    .frame(width: 260, height: 90)
                    .accessibilityHidden(true)
            }
            .card(padding: 24, hero: true)
            .accessibilityElement(children: .combine)
            StatStrip(stats: [
                (label: "Distance", value: String(format: "%.0f", units.distance(totals.distanceM)), unit: units.distanceUnit),
                (label: "Tours de France", value: String(format: "%.2f", totals.distanceM / tour), unit: ""),
                (label: "Hours", value: String(format: "%.0f", totals.seconds / 3600), unit: "\(totals.rides) rides"),
                (label: "Famous climbs", value: "\(ridden)/\(all)", unit: ridden == all ? "every one" : "\(all - ridden) to go"),
            ], size: 36)
        }
    }
}

/// One climb on the wall: its profile, and your best time and VAM (or a way to ride it).
private struct ClimbTile: View {
    let climb: FamousClimb
    let best: Records.Effort?
    let units: Units
    let ride: () -> Void

    var body: some View {
        let route = climb.route
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(climb.name).font(Design.Font.sans(16, weight: 700))
                        .foregroundStyle(best == nil ? Design.Palette.fg3 : Design.Palette.fg1).lineLimit(1)
                    Text(climb.side).font(Design.Font.small).foregroundStyle(Design.Palette.fg3).lineLimit(1)
                }
                Spacer(minLength: 4)
                if best != nil {
                    Tag(title: "Ridden", fill: Design.Accent.vermilion).accessibilityLabel("Ridden")
                }
            }
            RouteStrip(route: route, fill: best == nil ? Design.Palette.surfaceSunk : Design.Palette.terrainFill)
                .frame(height: 40)
                .opacity(best == nil ? 0.6 : 1)
            if let best {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(TimeFormat.clock(best.seconds)).font(Design.Font.bib(28)).foregroundStyle(Design.Palette.fg1)
                    Text("\(Int(best.vam.rounded())) VAM").font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                    Spacer()
                    Text(best.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                        .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                }
            } else {
                HStack {
                    Text(String(format: "%.1f %@ · %.0f %@", units.distance(route.distanceM), units.distanceUnit,
                                units.elevation(route.ascentM), units.elevationUnit))
                        .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                    Spacer()
                    PillButton(title: "Ride it", icon: "play", compact: true, action: ride)
                }
            }
        }
        .card(padding: 16)
    }
}
