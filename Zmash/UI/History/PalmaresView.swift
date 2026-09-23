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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
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
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20, alignment: .leading)], alignment: .leading, spacing: 20) {
            counter(String(format: "%.0f", units.elevation(totals.elevationM)), units.elevationUnit + " climbed",
                    String(format: "%.1f × Everest · %.0f × Ventoux", totals.elevationM / Records.everestM, totals.elevationM / ventoux))
            counter(String(format: "%.0f", units.distance(totals.distanceM)), units.distanceUnit,
                    String(format: "%.2f Tours de France", totals.distanceM / tour))
            counter(String(format: "%.0f", totals.seconds / 3600), "hours", "\(totals.rides) rides")
            counter("\(ridden) of \(all)", "famous climbs", ridden == all ? "every one" : "\(all - ridden) to go")
        }
    }

    private func counter(_ value: String, _ unit: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Design.Font.number(34)).foregroundStyle(Design.Palette.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
            Text(note).font(Design.Font.small).foregroundStyle(Design.Palette.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(climb.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary).lineLimit(1)
                    Text(climb.side).font(Design.Font.small).foregroundStyle(Design.Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if best != nil {
                    Icon("check", size: 20).foregroundStyle(Design.accent(forGrade: 8))
                        .accessibilityLabel("Ridden")
                }
            }
            RouteStrip(route: route, color: Design.Palette.primary).frame(height: 36)
            if let best {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(TimeFormat.clock(best.seconds)).font(Design.Font.number(20)).foregroundStyle(Design.Palette.primary)
                    Text("\(Int(best.vam.rounded())) VAM").font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    Spacer()
                    Text(best.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                        .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
            } else {
                HStack {
                    Text(String(format: "%.1f %@ · %.0f %@", units.distance(route.distanceM), units.distanceUnit,
                                units.elevation(route.ascentM), units.elevationUnit))
                        .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    Spacer()
                    Button("Ride it", action: ride).font(Design.Font.small).buttonStyle(.plain)
                        .foregroundStyle(Design.Palette.primary)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Capsule().fill(Design.Palette.background))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
        .opacity(best == nil ? 0.72 : 1)
    }
}
