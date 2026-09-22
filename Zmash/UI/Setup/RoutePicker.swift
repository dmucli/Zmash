import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Choose a route: a bundled climb, or one imported from a GPX or FIT file.
struct RoutePicker: View {
    @Binding var routeID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs
    @State private var imported = RouteStore.imported
    @State private var importing = false
    @State private var importFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section("Climbs") {
                    ForEach(ClimbLibrary.all) { row($0) }
                }
                Section("Imported") {
                    if imported.isEmpty {
                        Text("Bring in a GPX or FIT file from Files, Komoot, Strava or RideWithGPS. Zmash keeps the elevation profile and rides it by distance.")
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                            .listRowBackground(Design.Palette.surface)
                    }
                    ForEach(imported) { row($0) }
                        .onDelete { idx in
                            idx.map { imported[$0].id }.forEach { id in
                                RouteStore.delete(id: id)
                                if routeID == id { routeID = nil }
                            }
                            imported = RouteStore.imported
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Palette.background)
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Import") { importing = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
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

    private func row(_ route: Route) -> some View {
        Button {
            routeID = route.id
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(route.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Spacer()
                    if routeID == route.id { Icon("check", size: 18).foregroundStyle(Design.Palette.primary) }
                }
                Text(route.place).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                RouteStrip(route: route, color: Design.Palette.primary).frame(height: 40)
                Text(detail(route)).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Design.Palette.surface)
    }

    private func detail(_ route: Route) -> String {
        let units = prefs.units
        let distance = String(format: "%.1f %@", units.distance(route.distanceM), units.distanceUnit)
        let climb = String(format: "%.0f %@", units.elevation(route.ascentM), units.elevationUnit)
        return "\(distance) · \(climb) · \(String(format: "%.1f", route.averageGrade)) % avg · steepest km \(String(format: "%.1f", route.steepestKmGrade)) %"
    }
}

/// The chosen route on the setup screen.
struct RouteCard: View {
    let plan: SessionPlan
    let action: () -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.route?.name ?? "Choose a route")
                        .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Spacer()
                    Text(plan.route == nil ? "Choose" : "Change")
                        .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
                if let route = plan.route {
                    RouteStrip(route: route, color: Design.Palette.primary).frame(height: 52)
                    HStack {
                        Text(String(format: "%.1f %@ · %.0f %@ · %.1f %% avg", prefs.units.distance(route.distanceM),
                                    prefs.units.distanceUnit, prefs.units.elevation(route.ascentM),
                                    prefs.units.elevationUnit, route.averageGrade))
                        Spacer()
                        if route.approximate { Text("approximate profile") }
                    }
                    .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
    }
}
