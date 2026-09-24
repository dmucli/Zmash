import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

// Choosing a workout or a route happens in home's "Your ride" (D144), not in a sheet: the list on the left, the
// preview of what's chosen on the right.

/// A list's tabs and its "add" menu, over the list.
private struct BrowserHeader<Tab: Hashable, Menu: View>: View {
    let tabs: [(Tab, String)]
    @Binding var tab: Tab
    let addLabel: String
    @ViewBuilder var menu: Menu

    var body: some View {
        HStack(spacing: 8) {
            Segmented(options: tabs, selection: $tab)
            SwiftUI.Menu { menu } label: {
                Icon("plus", size: 18).foregroundStyle(Design.Palette.fg1)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Design.Palette.surfaceSunk))
                    .contentShape(Circle())
            }
            .accessibilityLabel(addLabel)
        }
        .padding(.horizontal, 14)
    }
}

/// A group's name in a list.
private struct BrowserSection: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A word in an empty list about how to fill it.
private struct BrowserHint: View {
    let text: String

    var body: some View {
        Text(text).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sunkTile()
            .padding(.top, 8)
    }
}

// MARK: - Workouts

/// Home's workouts: plans by goal, the library, and your own (built here or imported from a `.zwo` file). A workout
/// is chosen with a tap; a plan opens in the preview, where it's started.
struct WorkoutBrowser: View {
    @Binding var workoutID: String?
    /// The plan shown in the preview instead of the workout.
    @Binding var shownPlan: String?
    @Environment(Preferences.self) private var prefs
    /// Home owns it, so its plan card can open the plans.
    @Binding var tab: Tab
    @State private var imported = WorkoutStore.imported
    @State private var importing = false
    @State private var importFailed = false
    /// The builder: a new workout (nil inside) or one to edit or copy.
    @State private var building: Workout??
    @State private var deleting: Workout?

    enum Tab: String, CaseIterable { case plans = "Plans", library = "Library", mine = "Mine" }

    /// Where the list opens for a workout: a plan's session on Plans, one of yours on Mine, the rest on Library.
    static func tab(for workoutID: String?) -> Tab {
        guard let workoutID else { return .library }
        if workoutID.hasPrefix("plan/") { return .plans }
        return WorkoutStore.imported.contains { $0.id == workoutID } ? .mine : .library
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BrowserHeader(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: $tab, addLabel: "Add a workout") {
                Button("New workout") { building = .some(nil) }
                Button("Import a .zwo file") { importing = true }
            }
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch tab {
                    case .plans: plans
                    case .library:
                        ForEach(WorkoutLibrary.all, id: \.id) { w in
                            row(w).contextMenu { Button("Copy and edit") { building = .some(w) } }
                        }
                    case .mine: mine
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Opens on what's chosen, and on the plan when the plan card opens the plans.
            .onAppear { if let id = shownPlan ?? workoutID { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: tab) {
                guard let id = shownPlan ?? workoutID else { return }
                Task { @MainActor in proxy.scrollTo(id, anchor: .center) }
            }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "zwo") ?? .xml, .xml],
                      allowsMultipleSelection: true) { result in
            let urls = (try? result.get()) ?? []
            let added = urls.compactMap(WorkoutStore.importZWO)
            imported = WorkoutStore.imported
            if let last = added.last {
                tab = .mine
                choose(last.id)
            }
            importFailed = !urls.isEmpty && added.isEmpty
        }
        .sheet(isPresented: Binding(get: { building != nil }, set: { if !$0 { building = nil } })) {
            WorkoutBuilder(editing: building ?? nil) { w in
                imported = WorkoutStore.imported
                tab = .mine
                choose(w.id)
            }
            .presentationSizing(.page)
        }
        .alert("Not a Zwift workout file", isPresented: $importFailed) {} message: {
            Text("Zmash reads .zwo files with steady, ramp, interval and free-ride steps.")
        }
        .confirmationDialog("Delete \(deleting?.name ?? "the workout")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { w in
            Button("Delete", role: .destructive) { delete(w.id) }
        }
    }

    /// Plans by what they're for (D143), each with its length and hours a week, and whether you're on it.
    @ViewBuilder private var plans: some View {
        ForEach(TrainingPlan.Goal.allCases, id: \.self) { goal in
            let list = TrainingPlans.all.filter { $0.goal == goal }
            if !list.isEmpty {
                BrowserSection(goal.title)
                ForEach(list, id: \.id) { plan in
                    BrowserRow(title: plan.name, subtitle: Self.planMeta(plan), selected: shownPlan == plan.id, shapeWidth: nil,
                               action: { withAnimation(Design.Motion.base) { shownPlan = plan.id } }) {
                        if PlanStore.current?.planID == plan.id {
                            Tag(title: "You're on it", fill: Design.Accent.vermilion)
                        } else if let before = Self.doneBefore(plan) {
                            Tag(title: before)
                        }
                    }
                    .id(plan.id)
                }
            }
        }
    }

    @ViewBuilder private var mine: some View {
        if imported.isEmpty {
            BrowserHint(text: "Your own workouts: build one with +, or import a .zwo file from Zwift, TrainerRoad or intervals.icu.")
        }
        ForEach(imported, id: \.id) { w in
            row(w).contextMenu {
                Button("Edit") { building = .some(w) }
                Button("Delete…", role: .destructive) { deleting = w }
            }
        }
    }

    private func row(_ w: Workout) -> some View {
        BrowserRow(title: w.name, subtitle: meta(w), selected: workoutID == w.id && shownPlan == nil,
                   action: { choose(w.id) }) {
            WorkoutStrip(workout: w.drawable)
        }
        .id(w.id)
    }

    private func choose(_ id: String) {
        withAnimation(Design.Motion.base) {
            workoutID = id
            shownPlan = nil
        }
    }

    private func meta(_ w: Workout) -> String {
        if w.isRampTest { return "~20 min · until you stop" }
        let load = w.estimatedLoad(ftp: Double(prefs.ftp))
        return "\(TimeFormat.clock(w.duration)) · TSS \(Int(load.tss.rounded())) · IF \(String(format: "%.2f", load.intensityFactor))"
    }

    /// Deleting the chosen workout chooses the library's first, so home stays on Workout.
    private func delete(_ id: String) {
        WorkoutStore.delete(id: id)
        if workoutID == id { workoutID = WorkoutLibrary.all.first?.id }
        imported = WorkoutStore.imported
        deleting = nil
    }

    /// "6 weeks · 3 rides a week · ≈ 3 h 30 a week".
    static func planMeta(_ plan: TrainingPlan) -> String {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        let hours = perWeek >= 60 ? "\(perWeek / 60) h \(String(format: "%02d", perWeek % 60))" : "\(perWeek) min"
        return "\(plan.weeks.count) weeks · \(plan.sessionsPerWeek) rides a week · ≈ \(hours) a week"
    }

    /// "Done · 16 of 18": the last time this rider finished or left the plan.
    static func doneBefore(_ plan: TrainingPlan) -> String? {
        let rider = Riders.currentID
        guard let last = PlanStore.all.first(where: { $0.riderID == rider && $0.planID == plan.id && ($0.left || PlanStore.isFinished($0)) })
        else { return nil }
        let total = plan.weeks.map(\.count).reduce(0, +)
        return "Done · \(last.done.count) of \(total)"
    }
}

// MARK: - Routes

/// Home's routes: famous climbs by country, races (a stage race opens its stages here, and offers its campaign), and
/// routes imported from a file or a link. A route is chosen with a tap; which part to ride is chosen in the preview.
struct RouteBrowser: View {
    @Binding var routeID: String?
    /// The race whose campaign is shown in the preview instead of the route.
    @Binding var shownCampaign: String?
    @Environment(Preferences.self) private var prefs
    @State private var tab: Tab
    /// The stage race whose stages are listed.
    @State private var openRace: String?
    @State private var imported = RouteStore.imported
    @State private var importing = false
    @State private var importFailed = false
    @State private var linking = false
    @State private var deleting: Route?

    enum Tab: String, CaseIterable { case climbs = "Climbs", races = "Races", imported = "Imported" }

    init(routeID: Binding<String?>, shownCampaign: Binding<String?>) {
        _routeID = routeID
        _shownCampaign = shownCampaign
        // Opens where the chosen route is: its race's stages, the climbs, or the imports.
        let base = routeID.wrappedValue.map { RouteStore.split($0).base } ?? ""
        let race = shownCampaign.wrappedValue.flatMap { id in RaceStore.races.first { $0.id == id } } ?? RaceStore.stage(routeID: base)?.race
        let isClimb = base.isEmpty || base.hasPrefix("climb/") || RouteStore.legacyIDs[base] != nil
        _tab = State(initialValue: race != nil ? .races : isClimb ? .climbs : .imported)
        _openRace = State(initialValue: race.flatMap { $0.isOneDay ? nil : $0.id })
    }

    private var base: String { routeID.map { RouteStore.split($0).base } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BrowserHeader(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: $tab, addLabel: "Add a route") {
                Button("Import a GPX or FIT file") { importing = true }
                Button("From a link…") { linking = true }
            }
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch tab {
                    case .climbs: climbs
                    case .races:
                        if let race = openRace.flatMap({ id in RaceStore.races.first { $0.id == id } }) {
                            stages(race)
                        } else {
                            races
                        }
                    case .imported: importedList
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Opens on what's chosen.
            .onAppear { if !base.isEmpty { proxy.scrollTo(RouteStore.legacyIDs[base] ?? base, anchor: .center) } }
            }
        }
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

    // MARK: Climbs

    @ViewBuilder private var climbs: some View {
        ForEach(climbCountries, id: \.self) { country in
            BrowserSection(Locale.current.localizedString(forRegionCode: country) ?? country)
            ForEach(RaceStore.climbs.filter { $0.country == country }, id: \.id) { climb in
                let route = climb.route
                BrowserRow(title: climb.name,
                           subtitle: String(format: "%@ · %.1f %@ · %.1f %%", climb.side, prefs.units.distance(route.distanceM),
                                            prefs.units.distanceUnit, route.averageGrade),
                           selected: base == climb.id || RouteStore.legacyIDs[base] == climb.id,
                           action: { choose(climb.id) }) {
                    RouteStrip(route: route)
                }
                .id(climb.id)
            }
        }
    }

    private var climbCountries: [String] {
        RaceStore.climbs.map(\.country).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Races

    @ViewBuilder private var races: some View {
        let current = RaceStore.stage(routeID: base)?.race.id
        ForEach(Race.Kind.allCases, id: \.self) { kind in
            let list = RaceStore.races(kind)
            if !list.isEmpty {
                BrowserSection(kind.title)
                ForEach(list, id: \.id) { race in
                    let routes = RaceStore.routes(of: race)
                    BrowserRow(title: race.name,
                               subtitle: "\(String(race.year)) · \(race.country)" + (race.isOneDay ? "" : " · \(race.stages.count) stages"),
                               selected: current == race.id,
                               action: {
                                   if race.isOneDay, let stage = race.stages.first {
                                       choose(RouteSetup.chosenID(race.routeID(stage)))
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
        BrowserRow(title: active == nil ? "Ride it as a campaign" : "Your campaign",
                   subtitle: active.map { "Stage \(CampaignStore.nextStage($0)?.number ?? race.stages.count) next" } ?? "Stage by stage against 20 rivals",
                   selected: shownCampaign == race.id, shapeWidth: nil,
                   action: { withAnimation(Design.Motion.base) { shownCampaign = race.id } }) {
            Icon("trophy", size: 18).foregroundStyle(Design.Accent.vermilion)
        }
        BrowserSection("Stages")
        ForEach(Array(zip(race.stages, routes)), id: \.0.number) { stage, route in
            let stats = RouteStats.of(route)
            let span = max(route.maxElevationM - route.minElevationM, biggestRelief * 0.4, 60)
            BrowserRow(title: "Stage \(stage.number)",
                       subtitle: String(format: "%.0f %@ · %.0f %@ · ", prefs.units.distance(stats.distanceM), prefs.units.distanceUnit,
                                        prefs.units.elevation(stats.ascentM), prefs.units.elevationUnit) + TimeFormat.estimate(stats.estimatedSeconds),
                       selected: base == race.routeID(stage) && shownCampaign == nil,
                       action: { choose(RouteSetup.chosenID(race.routeID(stage))) }) {
                RouteStrip(route: route, range: route.minElevationM...(route.minElevationM + span))
            }
            .id(race.routeID(stage))
        }
    }

    // MARK: Imported

    @ViewBuilder private var importedList: some View {
        if imported.isEmpty {
            BrowserHint(text: "Bring in a route with +: a GPX or FIT file from Files, or a link from RideWithGPS, Komoot or Strava. Zmash keeps the elevation profile and rides it by distance.")
        }
        ForEach(imported, id: \.id) { route in
            BrowserRow(title: route.name,
                       subtitle: String(format: "%.1f %@ · %.0f %@ · %.1f %%", prefs.units.distance(route.distanceM), prefs.units.distanceUnit,
                                        prefs.units.elevation(route.ascentM), prefs.units.elevationUnit, route.averageGrade),
                       selected: base == route.id, action: { choose(route.id) }) {
                RouteStrip(route: route)
            }
            .id(route.id)
            .contextMenu { Button("Delete…", role: .destructive) { deleting = route } }
        }
    }

    private func choose(_ id: String) {
        withAnimation(Design.Motion.base) {
            routeID = id
            shownCampaign = nil
        }
    }

    /// Deleting the chosen route chooses the first climb, so home stays on Route.
    private func delete(_ id: String) {
        RouteStore.delete(id: id)
        if base == id { routeID = RaceStore.climbs.first?.id }
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
