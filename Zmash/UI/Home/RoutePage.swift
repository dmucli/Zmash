import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Routes (D148): real races (a stage race opens its stages here, and offers its campaign), your favourites, and
/// routes imported from a file or a link. The preview shows the profile and which part to ride, over Start.
struct RoutePage: View {
    let context: RideContext
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan
    @State private var tab: Tab
    /// The stage race whose stages are listed.
    @State private var openRace: String?
    /// The race whose campaign is in the preview instead of the route.
    @State private var shownCampaign: String?
    @State private var imported = RouteStore.imported
    @State private var importing = false
    @State private var importFailed = false
    @State private var linking = false
    @State private var deleting: Route?
    private var favourites: Favourites { .shared }

    enum Tab: String, CaseIterable { case races = "Races", favourites = "Favourites", imported = "Imported" }

    init(context: RideContext, initial: SessionPlan? = nil) {
        self.context = context
        var p = initial ?? Preferences.shared.lastPlan
        p.workoutID = nil
        let last = Preferences.shared.lastRouteID.flatMap { RouteStore.route(id: $0) != nil ? $0 : nil }
        p.routeID = initial?.routeID ?? last ?? Self.firstChoice
        _plan = State(initialValue: p)
        // Opens where the chosen route is: its race's stages, or the imports.
        let base = p.routeID.map { RouteStore.split($0).base } ?? ""
        var race = RaceStore.stage(routeID: base)?.race
        var campaign: String?
        #if DEBUG
        if DebugLaunch.homeShow == "campaign" {
            race = RaceStore.races.first { $0.id == DebugLaunch.race }
            campaign = race?.id
        }
        #endif
        var tab: Tab = base.hasPrefix("race/") || base.hasPrefix("climb/") || base.isEmpty || RouteStore.legacyIDs[base] != nil
            ? .races : .imported
        #if DEBUG
        if let t = DebugLaunch.tab.flatMap({ Tab(rawValue: $0.capitalized) }) { tab = t }
        #endif
        _tab = State(initialValue: tab)
        _openRace = State(initialValue: race.flatMap { $0.isOneDay ? nil : $0.id })
        _shownCampaign = State(initialValue: campaign)
    }

    /// When nothing's been chosen yet: the biggest mountain stage of the first Grand Tour, from its finale.
    @MainActor static var firstChoice: String? {
        guard let race = RaceStore.races.first(where: { !$0.isOneDay }) else { return nil }
        let routes = RaceStore.routes(of: race)
        guard let i = routes.indices.max(by: { routes[$0].ascentM < routes[$1].ascentM }) else { return nil }
        return RouteSetup.chosenID(race.routeID(race.stages[i]))
    }

    private var base: String { plan.routeID.map { RouteStore.split($0).base } ?? "" }

    var body: some View {
        let route = plan.route
        RidePage(title: "Route", context: context, start: route.map { r in
            StartInfo(title: r.name, detail: summary(r), start: {
                prefs.lastPlan = plan
                context.start(plan)
            }, favourite: (favourites.contains(base, .routes), { favourites.toggle(base, .routes) }))
        }) {
            ChooseColumn(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: $tab, hint: hint, addLabel: "Add a route") {
                Button("Import a GPX or FIT file") { importing = true }
                Button("From a link…") { linking = true }
            } content: {
                ChooseList(scrollTo: base, showing: tab.rawValue + (openRace ?? "")) {
                    switch tab {
                    case .races:
                        if let race = openRace.flatMap({ id in RaceStore.races.first { $0.id == id } }) {
                            stages(race)
                        } else {
                            races
                        }
                    case .favourites: favouriteList
                    case .imported: importedList
                    }
                }
            }
        } preview: {
            if let id = shownCampaign, let race = RaceStore.races.first(where: { $0.id == id }) {
                Closable(close: { shownCampaign = nil }) {
                    CampaignView(race: race, choose: { routeID in
                        withAnimation(Design.Motion.base) {
                            plan.routeID = routeID
                            shownCampaign = nil
                        }
                    }, embedded: true)
                    .id(id)
                }
            } else {
                FitOrScroll {
                    RouteSetup(routeID: $plan.routeID, units: prefs.units)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(22)
                }
            }
        }
        .onChange(of: plan.routeID) { _, id in if let id { prefs.lastRouteID = id } }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml,
                                            UTType(filenameExtension: "fit") ?? .data, .xml, .data],
                      allowsMultipleSelection: true) { result in
            let urls = (try? result.get()) ?? []
            let added = urls.compactMap(RouteStore.importFile)
            imported = RouteStore.imported
            if let last = added.last {
                tab = .imported
                choose(last.id)
            }
            importFailed = !urls.isEmpty && added.isEmpty
        }
        .alert("No profile in that file", isPresented: $importFailed) {} message: {
            Text("Zmash needs a GPX or FIT file with elevation, at least 500 m long.")
        }
        .sheet(isPresented: $linking) {
            RouteLinkSheet { route in
                imported = RouteStore.imported
                tab = .imported
                choose(route.id)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Delete \(deleting?.name ?? "the route")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { route in
            Button("Delete", role: .destructive) { delete(route.id) }
        } message: { _ in
            Text("Rides on it stay in History.")
        }
    }

    private var hint: String {
        switch tab {
        case .races: openRace == nil ? "Grand Tours, stage races and classics, on their real roads." : "Each stage as raced. Choose one, then how much of it to ride."
        case .favourites: "The roads you keep coming back to, newest first."
        case .imported: "From a GPX or FIT file, or a RideWithGPS, Komoot or Strava link. Long-press one to delete it."
        }
    }

    // MARK: Races

    @ViewBuilder private var races: some View {
        let current = RaceStore.stage(routeID: base)?.race.id
        ForEach(Race.Kind.allCases, id: \.self) { kind in
            let list = RaceStore.races(kind)
            if !list.isEmpty {
                ChooseSection(kind.title)
                ForEach(list, id: \.id) { race in
                    let routes = RaceStore.routes(of: race)
                    let oneDay = race.isOneDay ? race.stages.first.map(race.routeID) : nil
                    ChooseRow(title: race.name,
                              subtitle: "\(String(race.year)) · \(race.country)" + (race.isOneDay ? "" : " · \(race.stages.count) stages"),
                              selected: current == race.id,
                              favourite: oneDay.map { id in (favourites.contains(id, .routes), { favourites.toggle(id, .routes) }) },
                              action: {
                                  if let oneDay {
                                      choose(RouteSetup.chosenID(oneDay))
                                  } else {
                                      withAnimation(Design.Motion.base) { openRace = race.id }
                                  }
                              }) {
                        if race.isOneDay, let r = routes.first {
                            RouteStrip(route: r)
                        } else {
                            StageBars(routes: routes)
                        }
                    }
                    .id(race.isOneDay ? oneDay ?? race.id : race.id)
                }
            }
        }
    }

    /// A stage race's stages, on one height scale as in a race book (flat stages look flatter than mountain ones),
    /// after its campaign.
    @ViewBuilder private func stages(_ race: Race) -> some View {
        let routes = RaceStore.routes(of: race)
        let biggestRelief = routes.map { $0.maxElevationM - $0.minElevationM }.max() ?? 200
        Button {
            withAnimation(Design.Motion.base) {
                openRace = nil
                shownCampaign = nil
            }
        } label: {
            HStack(spacing: 8) {
                Icon("chevron-left", size: 18)
                Text("\(race.name) \(String(race.year))").font(Design.Font.label).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Design.Palette.fg1)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Back to the races")
        let active = CampaignStore.active(raceID: race.id)
        ChooseRow(title: active == nil ? "Ride it as a campaign" : "Your campaign",
                  subtitle: active.map { "Stage \(CampaignStore.nextStage($0)?.number ?? race.stages.count) next" } ?? "Stage by stage against 20 rivals",
                  selected: shownCampaign == race.id, shapeWidth: nil,
                  action: { withAnimation(Design.Motion.base) { shownCampaign = race.id } }) {
            Icon("trophy", size: 18).foregroundStyle(Design.Accent.vermilion)
        }
        ChooseSection("Stages")
        ForEach(Array(zip(race.stages, routes)), id: \.0.number) { stage, route in
            let id = race.routeID(stage)
            let stats = RouteStats.of(route)
            let span = max(route.maxElevationM - route.minElevationM, biggestRelief * 0.4, 60)
            ChooseRow(title: "Stage \(stage.number)",
                      subtitle: String(format: "%.0f %@ · %.0f %@ · ", prefs.units.distance(stats.distanceM), prefs.units.distanceUnit,
                                       prefs.units.elevation(stats.ascentM), prefs.units.elevationUnit) + TimeFormat.estimate(stats.estimatedSeconds),
                      selected: base == id && shownCampaign == nil,
                      favourite: (favourites.contains(id, .routes), { favourites.toggle(id, .routes) }),
                      action: { choose(RouteSetup.chosenID(id)) }) {
                RouteStrip(route: route, range: route.minElevationM...(route.minElevationM + span))
            }
            .id(id)
        }
    }

    // MARK: Favourites and imports

    @ViewBuilder private var favouriteList: some View {
        let list = favourites.ids(.routes).compactMap { id in RouteStore.route(id: id).map { (id, $0) } }
        if list.isEmpty {
            ChooseHint(text: "Tap ♡ on a stage, a classic or one of your routes to keep it here.")
        }
        ForEach(list, id: \.0) { id, route in
            ChooseRow(title: label(id, route), subtitle: stats(route), selected: base == id,
                      favourite: (true, { favourites.toggle(id, .routes) }),
                      action: { choose(RouteSetup.chosenID(id)) }) {
                RouteStrip(route: route)
            }
            .id(id)
        }
    }

    @ViewBuilder private var importedList: some View {
        if imported.isEmpty {
            ChooseHint(text: "Bring in a route with +: a GPX or FIT file from Files, or a link from RideWithGPS, Komoot or Strava. Zmash keeps the elevation profile and rides it by distance.")
        }
        ForEach(imported, id: \.id) { route in
            ChooseRow(title: route.name, subtitle: stats(route), selected: base == route.id,
                      favourite: (favourites.contains(route.id, .routes), { favourites.toggle(route.id, .routes) }),
                      action: { choose(route.id) }) {
                RouteStrip(route: route)
            }
            .id(route.id)
            .contextMenu { Button("Delete…", role: .destructive) { deleting = route } }
        }
    }

    /// "Tour de France 2025 · Stage 16", or the route's own name.
    private func label(_ id: String, _ route: Route) -> String {
        guard let found = RaceStore.stage(routeID: id) else { return route.name }
        let race = found.race
        return race.isOneDay ? "\(race.name) \(String(race.year))" : "\(race.name) \(String(race.year)) · Stage \(found.stage.number)"
    }

    private func stats(_ route: Route) -> String {
        String(format: "%.1f %@ · %.0f %@ · %.1f %%", prefs.units.distance(route.distanceM), prefs.units.distanceUnit,
               prefs.units.elevation(route.ascentM), prefs.units.elevationUnit, route.averageGrade)
    }

    private func choose(_ id: String) {
        withAnimation(Design.Motion.base) {
            plan.routeID = id
            shownCampaign = nil
        }
    }

    /// Deleting the chosen route goes back to the first choice, so there's always one to start.
    private func delete(_ id: String) {
        RouteStore.delete(id: id)
        if base == id { plan.routeID = Self.firstChoice }
        if favourites.contains(id, .routes) { favourites.toggle(id, .routes) }
        imported = RouteStore.imported
        deleting = nil
    }

    private func summary(_ r: Route) -> String {
        let units = prefs.units
        return String(format: "%.1f %@ · %.0f %@ climbing · ", units.distance(r.distanceM), units.distanceUnit,
                      units.elevation(r.ascentM), units.elevationUnit) + TimeFormat.estimate(RouteStats.of(r).estimatedSeconds)
    }
}

/// "From a link": paste a RideWithGPS, Komoot or Strava route link (or a GPX/FIT file's), and it's imported (D141).
private struct RouteLinkSheet: View {
    let imported: (Route) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("A route from RideWithGPS, Komoot or Strava, or a link to a GPX or FIT file.")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("https://…", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .font(Design.Font.body)
                        .sunkTile()
                        .onSubmit(load)
                    // No "allow paste" prompt: iOS hands over the clipboard only when this is tapped.
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { text = s; load() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
                if let failure {
                    Text(failure).font(Design.Font.small).foregroundStyle(Design.Status.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: working ? "Importing…" : "Import", enabled: !working && RouteLink.parse(text) != nil, action: load)
                Spacer()
            }
            .padding(Design.Space.gutter * 1.5)
            .background(Design.Palette.background)
            .navigationTitle("From a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func load() {
        guard !working else { return }
        working = true
        failure = nil
        Task {
            do {
                let route = try await RouteLinkImport.route(from: text)
                imported(route)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}
