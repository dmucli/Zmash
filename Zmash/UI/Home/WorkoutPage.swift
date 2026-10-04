import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Workouts (D148, D149, D154): Zmash's library and the bundled catalog of Zwift and Sufferfest workouts, your planned,
/// favourite and own ones; filtered by kind, length, collection and a search; as the design system's picker: big cards
/// with their shape, and the bar with ERG or gradients and Start. A card opens the workout's details in place of the
/// grid (D163), as home's Workout card does for the one chosen.
struct WorkoutPage: View {
    let context: RideContext
    var compact = false
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan
    @State private var tab: Tab
    /// nil: all kinds.
    @State private var category: Workout.Category?
    /// The length filter (D154), on every tab.
    @State private var length = WorkoutLength.any
    /// A collection of the catalog, or Zmash's own; nil: all.
    @State private var collection: String?
    @State private var search = ""
    @State private var imported = WorkoutStore.imported
    @State private var importing = false
    @State private var importFailed = false
    /// The builder: a new workout (nil inside) or one to edit or copy.
    @State private var building: Workout??
    @State private var deleting: Workout?
    /// The workout whose details are shown in place of the grid (D163); nil: the grid.
    @State private var open: String?
    private var favourites: Favourites { .shared }

    enum Tab: String, CaseIterable { case workouts = "Workouts", planned = "Planned", favourites = "Favourites", imported = "Imported" }

    /// The tabs shown: Planned only with intervals.icu connected (D153).
    private var tabs: [Tab] {
        Tab.allCases.filter { $0 != .planned || planned.connected || planned.state == .loaded }
    }
    private var planned: PlannedWorkouts { .shared }

    /// When nothing's been chosen yet: the workhorse.
    static let firstChoice = "sweetspot-2x20"
    /// Zmash's own library, as a collection beside the catalog's.
    static let zmash = "Zmash"

    /// A workout in the grid: what the filters need, and the workout itself built only when its card is drawn (the
    /// catalog has about 2,500).
    struct Listed: Identifiable {
        let id: String
        let name: String
        let seconds: Int
        let category: Workout.Category?
        let collection: String?
        let make: () -> Workout?

        init(_ w: Workout, collection: String?) {
            id = w.id
            name = w.name
            seconds = w.isRampTest ? 20 * 60 : w.duration
            category = w.category
            self.collection = collection
            make = { w }
        }

        init(entry e: WorkoutCatalogFile.Entry) {
            id = e.id
            name = e.name
            seconds = e.seconds
            category = Workout.Category(rawValue: e.category)
            collection = e.collection
            make = { e.workout }
        }
    }

    /// `details`: open on the chosen workout's details (from home's card) rather than the grid.
    init(context: RideContext, compact: Bool = false, initial: SessionPlan? = nil, details: Bool = false) {
        self.context = context
        self.compact = compact
        var p = initial ?? Preferences.shared.lastPlan
        p.routeID = nil
        let last = Preferences.shared.lastWorkoutID.flatMap { WorkoutStore.workout(id: $0) != nil ? $0 : nil }
        p.workoutID = initial?.workoutID ?? last ?? Self.firstChoice
        _plan = State(initialValue: p)
        var tab: Tab = p.workoutID?.hasPrefix("icu/") == true ? .planned
            : WorkoutStore.imported.contains { $0.id == p.workoutID } ? .imported : .workouts
        var open = details ? p.workoutID : nil
        #if DEBUG
        if let t = DebugLaunch.tab.flatMap({ Tab(rawValue: $0.capitalized) }) { tab = t; open = nil }
        // -ZmashLength h1, -ZmashKind threshold, -ZmashCollection "The Sufferfest", -ZmashSearch text (D154 checks).
        let d = UserDefaults.standard
        if let l = d.string(forKey: "ZmashLength").flatMap(WorkoutLength.init) { _length = State(initialValue: l) }
        if let k = d.string(forKey: "ZmashKind").flatMap(Workout.Category.init) { _category = State(initialValue: k) }
        if let c = d.string(forKey: "ZmashCollection") { _collection = State(initialValue: c) }
        if let q = d.string(forKey: "ZmashSearch") { _search = State(initialValue: q) }
        #endif
        _tab = State(initialValue: tab)
        _open = State(initialValue: open)
    }

    var body: some View {
        RidePage(context: context, selection: plan.workout.map(selection), compact: compact, filters: open == nil ? filterRow : nil) {
            if open != nil {
                Chip(title: "All workouts", icon: "chevron-left", selected: false) {
                    withAnimation(Design.Motion.base) { open = nil }
                }
            } else {
                PickerTabs(tabs: tabs.map { ($0, $0.rawValue) }, tab: $tab, compact: compact)
            }
        } tools: {
            Spacer(minLength: 0)
            if open == nil {
                SearchField(text: $search, prompt: tab == .workouts ? "Search \(WorkoutCatalog.entries.count + WorkoutLibrary.all.count) workouts" : "Search")
                    .frame(maxWidth: compact ? .infinity : 280)
                AddMenu(label: "Add a workout") {
                    Button("New workout") { building = .some(nil) }
                    Button("Import a .zwo file") { importing = true }
                }
            }
        } content: {
            if let id = open, let w = WorkoutStore.workout(id: id) {
                WorkoutDetail(workout: w, source: source(w), compact: compact)
                    .id(w.id)
            } else {
                grid
            }
        }
        .onChange(of: plan.workoutID) { _, id in if let id { prefs.lastWorkoutID = id } }
        .task(id: tab) { if tab == .planned { await planned.refreshIfStale() } }
        .onChange(of: plan.workoutERG) { _, erg in prefs.lastPlan.workoutERG = erg }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "zwo") ?? .xml, .xml],
                      allowsMultipleSelection: true) { result in
            let urls = (try? result.get()) ?? []
            let added = urls.compactMap(WorkoutStore.importZWO)
            imported = WorkoutStore.imported
            if let last = added.last {
                tab = .imported
                choose(last.id)
            }
            importFailed = !urls.isEmpty && added.isEmpty
        }
        .sheet(isPresented: Binding(get: { building != nil }, set: { if !$0 { building = nil } })) {
            WorkoutBuilder(editing: building ?? nil) { w in
                imported = WorkoutStore.imported
                tab = .imported
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

    /// The cards, three to a row (one on a phone), opening on the chosen one.
    private var grid: some View {
        PickerGrid(columns: compact ? 1 : 3, rowHeight: compact ? 160 : 186, scrollTo: plan.workoutID,
                   showing: [tab.rawValue, category?.rawValue ?? "", length.rawValue, collection ?? "", search].joined(separator: "|")) {
            let list = shown
            if list.isEmpty {
                PickerHint(text: emptyHint)
            }
            ForEach(list) { item in
                if let w = item.make() {
                    // Without a catalog (D166) every card is Zmash's: no need to say so.
                    card(w, collection: tab == .workouts && collection == nil && !WorkoutCatalog.entries.isEmpty ? item.collection : nil,
                         day: tab == .planned ? planned.entries.first { $0.id == w.id }?.day : nil)
                        .contextMenu {
                            if tab == .imported {
                                Button("Edit") { building = .some(w) }
                                Button("Delete…", role: .destructive) { deleting = w }
                            } else if w.category != nil {
                                Button("Copy and edit") { building = .some(w) }
                            }
                        }
                }
            }
        }
    }

    /// The cards the tab and filters show: kind (Workouts tab), length, collection (Workouts tab) and the search.
    private var shown: [Listed] {
        let base: [Listed] = switch tab {
        case .workouts:
            (collection == nil || collection == Self.zmash ? WorkoutLibrary.all.map { Listed($0, collection: Self.zmash) } : [])
                + (collection == Self.zmash ? [] : WorkoutCatalog.entries.lazy
                    .filter { collection == nil || $0.collection == collection }.map(Listed.init(entry:)))
        case .planned: planned.entries.map { Listed($0.workout, collection: nil) }
        case .favourites: favourites.ids(.workouts).compactMap { id in
            WorkoutCatalog.entry(id: id).map(Listed.init(entry:)) ?? WorkoutStore.workout(id: id).map { Listed($0, collection: nil) }
        }
        case .imported: imported.map { Listed($0, collection: nil) }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        return base.filter { item in
            (tab != .workouts || category == nil || item.category == category)
                && length.contains(seconds: item.seconds)
                && (query.isEmpty || item.name.localizedStandardContains(query)
                    || (item.collection?.localizedStandardContains(query) ?? false))
        }
    }

    /// Kinds, lengths and the collection, on one row that scrolls sideways when it doesn't fit.
    private var filterRow: AnyView {
        AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if tab == .workouts {
                        ForEach([(Workout.Category?.none, "All")] + Workout.Category.allCases.map { (Optional($0), $0.short) }, id: \.0) { value, title in
                            Chip(title: title, selected: value == category) { withAnimation(Design.Motion.fast) { category = value } }
                        }
                        Rectangle().fill(Design.Palette.border).frame(width: 1, height: 24).padding(.horizontal, 6)
                    }
                    ForEach(WorkoutLength.allCases, id: \.self) { l in
                        Chip(title: l.title, selected: l == length) { withAnimation(Design.Motion.fast) { length = l } }
                    }
                    // A collection menu only with the catalog's collections to choose from (D166).
                    if tab == .workouts, !WorkoutCatalog.collections.isEmpty {
                        Rectangle().fill(Design.Palette.border).frame(width: 1, height: 24).padding(.horizontal, 6)
                        Menu {
                            Button("All collections") { collection = nil }
                            Button(Self.zmash) { collection = Self.zmash }
                            Divider()
                            ForEach(WorkoutCatalog.collections, id: \.self) { c in Button(c) { collection = c } }
                        } label: {
                            HStack(spacing: 6) {
                                Text(collection ?? "All collections").lineLimit(1)
                                Icon("chevron-down", size: 13)
                            }
                            .font(Design.Font.sans(13, weight: 600))
                            .foregroundStyle(collection == nil ? Design.Palette.fg2 : Design.Palette.invertFg)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background {
                                if collection == nil {
                                    Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
                                } else {
                                    Capsule().fill(Design.Palette.invertBg)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .accessibilityLabel("Collection")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        )
    }

    private var emptyHint: String {
        let filtered = length != .any || !search.isEmpty || (tab == .workouts && (category != nil || collection != nil))
        if filtered { return "Nothing matches. Try another length, kind or collection, or clear the search." }
        return switch tab {
        case .planned:
            switch planned.state {
            case .loading, .idle: "Getting your intervals.icu calendar…"
            case .failed(let message): message
            case .loaded: "Nothing planned on intervals.icu for the next 7 days. Workouts you (or your coach) add to its calendar show here."
            }
        case .favourites: "Tap ♡ on a workout to keep it here."
        default: "Your own workouts: build one with +, or import a .zwo file from Zwift, TrainerRoad or intervals.icu."
        }
    }

    private func card(_ w: Workout, collection: String? = nil, day: Date? = nil) -> some View {
        PickerCard(title: w.name, meta: (day.map { Self.dayLabel($0) + " · " } ?? "") + meta(w), selected: plan.workoutID == w.id,
                   caption: collection,
                   favourite: (favourites.contains(w.id, .workouts), { favourites.toggle(w.id, .workouts) }),
                   action: {
                       choose(w.id)
                       withAnimation(Design.Motion.base) { open = w.id }
                   }) {
            WorkoutStrip(workout: w.drawable)
        }
        .id(w.id)
    }

    private func selection(_ w: Workout) -> Selection {
        Selection(title: w.name, meta: summary(w),
                  favourite: w.id.hasPrefix("plan/") ? nil : (favourites.contains(w.id, .workouts), { favourites.toggle(w.id, .workouts) }),
                  option: AnyView(Segmented(options: [(true, "ERG"), (false, "Gradient")],
                                            selection: Binding(get: { plan.usesERG }, set: { plan.workoutERG = $0 }))
                                    .frame(width: 200)),
                  start: {
                      prefs.lastPlan = plan
                      context.start(plan)
                  })
    }

    private func choose(_ id: String) {
        withAnimation(Design.Motion.base) { plan.workoutID = id }
    }

    /// Where a workout is from, for its details: the catalog's author and collection, intervals.icu, a plan, or yours.
    /// Zmash's own say nothing (D181): without the catalog built in, every workout in the library is.
    private func source(_ w: Workout) -> String {
        if let e = WorkoutCatalog.entry(id: w.id) {
            let author = e.author?.replacingOccurrences(of: " (via whatsonzwift.com)", with: "") ?? ""
            return author.isEmpty || author == e.collection ? e.collection : "\(author) · \(e.collection)"
        }
        if w.id.hasPrefix("icu/") { return "intervals.icu" }
        if w.id.hasPrefix("plan/") {
            let planID = w.id.split(separator: "/").dropFirst().first.map(String.init) ?? ""
            return PlanStore.plan(id: planID).map { "Training plan · \($0.name)" } ?? "Training plan"
        }
        if WorkoutLibrary.all.contains(where: { $0.id == w.id }) { return "" }
        return "Your workout"
    }

    /// Deleting the chosen workout chooses the workhorse, so there's always one to start.
    private func delete(_ id: String) {
        WorkoutStore.delete(id: id)
        if plan.workoutID == id { plan.workoutID = Self.firstChoice }
        if favourites.contains(id, .workouts) { favourites.toggle(id, .workouts) }
        imported = WorkoutStore.imported
        deleting = nil
    }

    /// "Today", "Tomorrow", or the weekday.
    static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    /// "59:00 · TSS 75 · IF .87".
    private func meta(_ w: Workout) -> String {
        if w.isRampTest { return "~20 min · until you stop" }
        let load = w.estimatedLoad(ftp: Double(prefs.ftp))
        return "\(TimeFormat.clock(w.duration)) · TSS \(Int(load.tss.rounded())) · IF " + String(format: "%.2f", load.intensityFactor).replacingOccurrences(of: "0.", with: ".")
    }

    private func summary(_ w: Workout) -> String {
        let length = w.isRampTest ? "Until you stop" : TimeFormat.clock(w.duration)
        let erg = plan.usesERG && context.hub.trainer.supportsERG
        let load = w.isRampTest ? "" : " · TSS \(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))"
        return "\(length)\(load) · \(erg ? "ERG" : "Gradient") · FTP \(prefs.ftp) W"
    }
}

extension Workout.Category {
    /// For a filter chip.
    var short: String {
        switch self {
        case .tempo: "Tempo"
        default: title
        }
    }
}
