import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Choose a route: a real race or stage, a famous climb as it was raced, or one imported from a GPX or FIT file.
struct RoutePicker: View {
    @Binding var routeID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs
    @State private var imported = RouteStore.imported
    @State private var importing = false
    @State private var importFailed = false

    /// nil = everything; otherwise one kind of race, the climbs, or your imports.
    @State private var filter: String?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let compact = geo.size.width < 700
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(title: "Routes", kicker: "Real roads, as raced", compact: compact) {
                            PillButton(title: "Import", icon: "plus", compact: true) { importing = true }
                            PillButton(title: "Done", style: .invert, compact: true) { dismiss() }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Chip(title: "All", selected: filter == nil) { pick(nil) }
                                ForEach(Race.Kind.allCases, id: \.self) { kind in
                                    if !RaceStore.races(kind).isEmpty {
                                        Chip(title: kind.title, selected: filter == kind.rawValue) { pick(kind.rawValue) }
                                    }
                                }
                                Chip(title: "Climbs", selected: filter == "climbs") { pick("climbs") }
                                Chip(title: "Imported", selected: filter == "imported") { pick("imported") }
                            }
                        }
                        ForEach(Race.Kind.allCases, id: \.self) { kind in
                            let races = RaceStore.races(kind)
                            if !races.isEmpty, filter == nil || filter == kind.rawValue {
                                section(kind.title) {
                                    ForEach(Array(races.enumerated()), id: \.element.id) { i, race in
                                        NavigationLink {
                                            if race.isOneDay, let stage = race.stages.first {
                                                StageView(race: race, stage: stage, choose: choose)
                                            } else {
                                                RaceView(race: race, choose: choose)
                                            }
                                        } label: {
                                            RaceRow(race: race, index: i + 1, units: prefs.units,
                                                    selected: routeID.map { RouteStore.split($0).base.hasPrefix(race.id) } ?? false)
                                        }
                                        .buttonStyle(PressStyle())
                                    }
                                }
                            }
                        }
                        if filter == nil || filter == "climbs" {
                            ForEach(climbCountries, id: \.self) { country in
                                section("Climbs · " + (Locale.current.localizedString(forRegionCode: country) ?? country)) {
                                    ForEach(Array(RaceStore.climbs.filter { $0.country == country }.enumerated()), id: \.element.id) { i, climb in
                                        NavigationLink {
                                            StageView(climb: climb, choose: choose)
                                        } label: {
                                            ClimbRow(climb: climb, index: i + 1,
                                                     selected: routeID.map { RouteStore.split($0).base } == climb.id, units: prefs.units)
                                        }
                                        .buttonStyle(PressStyle())
                                    }
                                }
                            }
                        }
                        if filter == nil || filter == "imported" {
                            section("Imported") {
                                if imported.isEmpty {
                                    Text("Bring in a GPX or FIT file from Files, Komoot, Strava or RideWithGPS. Zmash keeps the elevation profile and rides it by distance.")
                                        .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .sunkTile()
                                }
                                ForEach(Array(imported.enumerated()), id: \.element.id) { i, route in
                                    row(route, index: i + 1)
                                }
                            }
                        }
                    }
                    .pagePadding(compact)
                }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml,
                                                UTType(filenameExtension: "fit") ?? .data, .xml, .data],
                          allowsMultipleSelection: true) { result in
                let urls = (try? result.get()) ?? []
                let added = urls.compactMap(RouteStore.importFile)
                imported = RouteStore.imported
                if let last = added.last { routeID = last.id }
                importFailed = !urls.isEmpty && added.isEmpty
            }
            .alert("No profile in that file", isPresented: $importFailed) {} message: {
                Text("Zmash needs a GPX or FIT file with elevation, at least 500 m long.")
            }
        }
    }

    private func pick(_ f: String?) { withAnimation(Design.Motion.base) { filter = f } }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            CardGrid { content() }
        }
    }

    private var climbCountries: [String] {
        RaceStore.climbs.map(\.country).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// A pick from anywhere in the picker (a race, a stage, a segment) closes the whole sheet.
    private func choose(_ id: String) {
        routeID = id
        dismiss()
    }

    private func row(_ route: Route, index: Int) -> some View {
        Button {
            routeID = route.id
            dismiss()
        } label: {
            PickCard(index: index, title: route.name, subtitle: route.place, meta: detail(route), selected: routeID == route.id) {
                RouteStrip(route: route).frame(height: 44)
            }
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            Button("Delete", role: .destructive) {
                RouteStore.delete(id: route.id)
                if routeID == route.id { routeID = nil }
                imported = RouteStore.imported
            }
        }
    }

    private func detail(_ route: Route) -> String {
        let units = prefs.units
        let distance = String(format: "%.1f %@", units.distance(route.distanceM), units.distanceUnit)
        let climb = String(format: "%.0f %@", units.elevation(route.ascentM), units.elevationUnit)
        return "\(distance) · \(climb) · \(String(format: "%.1f", route.averageGrade)) % avg"
    }
}
