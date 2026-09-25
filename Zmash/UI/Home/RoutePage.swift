import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Routes (D148, D149): real races (a stage race opens its stages here, led by its campaign), your favourites, and
/// routes imported from a file or a link, as the design system's picker: cards with the profile edge to edge, and the
/// bar with how much of it to ride and Start.
struct RoutePage: View {
    let context: RideContext
    var compact = false
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan
    @State private var tab: Tab
    /// nil: every kind of race.
    @State private var kind: Race.Kind?
    /// The stage race whose stages are shown.
    @State private var openRace: String?
    /// The race whose campaign is shown instead of the grid.
    @State private var shownCampaign: String?
    @State private var imported = RouteStore.imported
    @State private var importing = false
    @State private var importFailed = false
    @State private var linking = false
    @State private var deleting: Route?
    private var favourites: Favourites { .shared }

    enum Tab: String, CaseIterable { case races = "Races", favourites = "Favourites", imported = "Imported" }

    init(context: RideContext, compact: Bool = false, initial: SessionPlan? = nil) {
        self.context = context
        self.compact = compact
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
        return RoutePart.chosenID(race.routeID(race.stages[i]))
    }

    private var base: String { plan.routeID.map { RouteStore.split($0).base } ?? "" }
    private var race: Race? { openRace.flatMap { id in RaceStore.races.first { $0.id == id } } }

    var body: some View {
        RidePage(context: context, selection: plan.route.map(selection), compact: compact) {
            PickerTabs(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: Binding(get: { tab }, set: { t in
                tab = t
                shownCampaign = nil
            }), compact: compact)
        } tools: {
            if tab == .races {
                if let race {
                    Chip(title: "\(race.name) \(String(race.year))", icon: "chevron-left", selected: true) {
                        withAnimation(Design.Motion.base) {
                            openRace = nil
                            shownCampaign = nil
                        }
                    }
                    .accessibilityHint("Back to the races")
                    Spacer(minLength: 0)
                } else {
                    FilterChips(options: [(Race.Kind?.none, "All")] + Race.Kind.allCases.map { (Optional($0), $0.title) }, selection: $kind)
                }
            } else {
                Spacer(minLength: 0)
            }
            AddMenu(label: "Add a route") {
                Button("Import a GPX or FIT file") { importing = true }
                Button("From a link…") { linking = true }
            }
        } content: {
            if let id = shownCampaign, let race = RaceStore.races.first(where: { $0.id == id }) {
                CampaignView(race: race, choose: { routeID in
                    withAnimation(Design.Motion.base) {
                        plan.routeID = routeID
                        shownCampaign = nil
                    }
                }, embedded: true)
                .id(id)
                .card(padding: 0)
            } else {
                PickerGrid(columns: compact ? 1 : 2, rowHeight: compact ? 170 : 196, scrollTo: base,
                           showing: tab.rawValue + (openRace ?? "") + (kind?.rawValue ?? "")) {
                    switch tab {
                    case .races:
                        if let race { stages(race) } else { races }
                    case .favourites: favouriteCards
                    case .imported: importedCards
                    }
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

    // MARK: Cards

    @ViewBuilder private var races: some View {
        let current = RaceStore.stage(routeID: base)?.race.id
        ForEach(RaceStore.races.filter { kind == nil || $0.kind == kind }, id: \.id) { race in
            let routes = RaceStore.routes(of: race)
            let oneDay = race.isOneDay ? race.stages.first.map(race.routeID) : nil
            let distance = routes.map(\.distanceM).reduce(0, +)
            PickerCard(title: race.name,
                       meta: "\(String(race.year)) · \(race.country) · "
                           + (race.isOneDay ? "" : "\(race.stages.count) stages · ")
                           + String(format: "%.0f %@", prefs.units.distance(distance), prefs.units.distanceUnit),
                       selected: current == race.id, fullBleed: race.isOneDay,
                       favourite: oneDay.map { id in (favourites.contains(id, .routes), { favourites.toggle(id, .routes) }) },
                       action: {
                           if let oneDay {
                               choose(RoutePart.chosenID(oneDay))
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
            .id(oneDay ?? race.id)
        }
    }

    /// A stage race: its campaign first, as the hero, then each stage on one height scale, as in a race book.
    @ViewBuilder private func stages(_ race: Race) -> some View {
        let routes = RaceStore.routes(of: race)
        let biggestRelief = routes.map { $0.maxElevationM - $0.minElevationM }.max() ?? 200
        let active = CampaignStore.active(raceID: race.id)
        PickerCard(title: active == nil ? "Ride it as a campaign" : "Your campaign",
                   meta: active.map { "Stage \(CampaignStore.nextStage($0)?.number ?? race.stages.count) next" }
                       ?? "Stage by stage against 20 rivals · GC and mountains",
                   hero: true, action: { withAnimation(Design.Motion.base) { shownCampaign = race.id } }) {
            StageBars(routes: routes)
        }
        ForEach(Array(zip(race.stages, routes)), id: \.0.number) { stage, route in
            let id = race.routeID(stage)
            let stats = RouteStats.of(route)
            let span = max(route.maxElevationM - route.minElevationM, biggestRelief * 0.4, 60)
            PickerCard(title: "Stage \(stage.number)",
                       meta: String(format: "%.0f %@ · %.0f %@ · ", prefs.units.distance(stats.distanceM), prefs.units.distanceUnit,
                                    prefs.units.elevation(stats.ascentM), prefs.units.elevationUnit) + TimeFormat.estimate(stats.estimatedSeconds),
                       selected: base == id, fullBleed: true,
                       favourite: (favourites.contains(id, .routes), { favourites.toggle(id, .routes) }),
                       action: { choose(RoutePart.chosenID(id)) }) {
                RouteStrip(route: route, range: route.minElevationM...(route.minElevationM + span))
            }
            .id(id)
        }
    }

    @ViewBuilder private var favouriteCards: some View {
        let list = favourites.ids(.routes).compactMap { id in RouteStore.route(id: id).map { (id, $0) } }
        if list.isEmpty {
            PickerHint(text: "Tap ♡ on a stage, a classic or one of your routes to keep it here.")
        }
        ForEach(list, id: \.0) { id, route in
            PickerCard(title: label(id, route), meta: stats(route), selected: base == id, fullBleed: true,
                       favourite: (true, { favourites.toggle(id, .routes) }),
                       action: { choose(RoutePart.chosenID(id)) }) {
                RouteStrip(route: route)
            }
            .id(id)
        }
    }

    @ViewBuilder private var importedCards: some View {
        if imported.isEmpty {
            PickerHint(text: "Bring in a route with +: a GPX or FIT file from Files, or a link from RideWithGPS, Komoot or Strava. Zmash keeps the elevation profile and rides it by distance.")
        }
        ForEach(imported, id: \.id) { route in
            PickerCard(title: route.name, meta: stats(route), selected: base == route.id, fullBleed: true,
                       favourite: (favourites.contains(route.id, .routes), { favourites.toggle(route.id, .routes) }),
                       action: { choose(route.id) }) {
                RouteStrip(route: route)
            }
            .id(route.id)
            .contextMenu { Button("Delete…", role: .destructive) { deleting = route } }
        }
    }

    // MARK: Selection

    private func selection(_ r: Route) -> Selection {
        let id = plan.routeID ?? base
        let options = RoutePart.options(id)
        return Selection(title: label(base, r), meta: summary(r),
                         favourite: (favourites.contains(base, .routes), { favourites.toggle(base, .routes) }),
                         option: options.count > 1
                             ? AnyView(Segmented(options: options, selection: Binding(get: { RoutePart.length(id) }, set: { length in
                                   withAnimation(Design.Motion.base) { plan.routeID = RoutePart.id(id, length: length) }
                               }))
                               .frame(maxWidth: CGFloat(options.count) * 62))
                             : nil,
                         start: {
                             prefs.lastPlan = plan
                             context.start(plan)
                         })
    }

    /// "Tour de France 2025 · Stage 16", or the route's own name.
    private func label(_ id: String, _ route: Route) -> String {
        guard let found = RaceStore.stage(routeID: RouteStore.split(id).base) else { return route.name }
        let race = found.race
        return race.isOneDay ? "\(race.name) \(String(race.year))" : "\(race.name) \(String(race.year)) · Stage \(found.stage.number)"
    }

    private func stats(_ route: Route) -> String {
        String(format: "%.1f %@ · %.0f %@ · %.1f %%", prefs.units.distance(route.distanceM), prefs.units.distanceUnit,
               prefs.units.elevation(route.ascentM), prefs.units.elevationUnit, route.averageGrade)
    }

    /// What's ridden: the part's length and climbing, and the time at your pace.
    private func summary(_ r: Route) -> String {
        let units = prefs.units
        return String(format: "%.1f %@ · %.0f %@ · ", units.distance(r.distanceM), units.distanceUnit,
                      units.elevation(r.ascentM), units.elevationUnit) + TimeFormat.estimate(RouteStats.of(r).estimatedSeconds)
    }

    private func choose(_ id: String) {
        withAnimation(Design.Motion.base) { plan.routeID = id }
    }

    /// Deleting the chosen route goes back to the first choice, so there's always one to start.
    private func delete(_ id: String) {
        RouteStore.delete(id: id)
        if base == id { plan.routeID = Self.firstChoice }
        if favourites.contains(id, .routes) { favourites.toggle(id, .routes) }
        imported = RouteStore.imported
        deleting = nil
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
