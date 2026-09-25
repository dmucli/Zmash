import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Workouts (D148, D149): the library by kind, your favourites, and your own (built here or imported from a `.zwo`
/// file), as the design system's picker: big cards with their shape, and the bar with ERG or gradients and Start.
struct WorkoutPage: View {
    let context: RideContext
    var compact = false
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan
    @State private var tab: Tab
    /// nil: all kinds.
    @State private var category: Workout.Category?
    @State private var imported = WorkoutStore.imported
    @State private var importing = false
    @State private var importFailed = false
    /// The builder: a new workout (nil inside) or one to edit or copy.
    @State private var building: Workout??
    @State private var deleting: Workout?
    private var favourites: Favourites { .shared }

    enum Tab: String, CaseIterable { case workouts = "Workouts", favourites = "Favourites", imported = "Imported" }

    /// When nothing's been chosen yet: the workhorse.
    static let firstChoice = "sweetspot-2x20"

    init(context: RideContext, compact: Bool = false, initial: SessionPlan? = nil) {
        self.context = context
        self.compact = compact
        var p = initial ?? Preferences.shared.lastPlan
        p.routeID = nil
        let last = Preferences.shared.lastWorkoutID.flatMap { WorkoutStore.workout(id: $0) != nil ? $0 : nil }
        p.workoutID = initial?.workoutID ?? last ?? Self.firstChoice
        _plan = State(initialValue: p)
        var tab: Tab = WorkoutStore.imported.contains { $0.id == p.workoutID } ? .imported : .workouts
        #if DEBUG
        if let t = DebugLaunch.tab.flatMap({ Tab(rawValue: $0.capitalized) }) { tab = t }
        #endif
        _tab = State(initialValue: tab)
    }

    var body: some View {
        RidePage(context: context, selection: plan.workout.map(selection), compact: compact) {
            PickerTabs(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: $tab, compact: compact)
        } tools: {
            if tab == .workouts {
                FilterChips(options: [(Workout.Category?.none, "All")] + Workout.Category.allCases.map { (Optional($0), $0.short) },
                            selection: $category)
            } else {
                Spacer(minLength: 0)
            }
            AddMenu(label: "Add a workout") {
                Button("New workout") { building = .some(nil) }
                Button("Import a .zwo file") { importing = true }
            }
        } content: {
            PickerGrid(columns: compact ? 1 : 3, rowHeight: compact ? 150 : 176, scrollTo: plan.workoutID,
                       showing: tab.rawValue + (category?.rawValue ?? "")) {
                let list = shown
                if list.isEmpty {
                    PickerHint(text: tab == .favourites
                               ? "Tap ♡ on a workout to keep it here."
                               : "Your own workouts: build one with +, or import a .zwo file from Zwift, TrainerRoad or intervals.icu.")
                }
                ForEach(list, id: \.id) { w in
                    card(w)
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
        .onChange(of: plan.workoutID) { _, id in if let id { prefs.lastWorkoutID = id } }
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

    /// The cards the tab and filter show.
    private var shown: [Workout] {
        switch tab {
        case .workouts: WorkoutLibrary.all.filter { category == nil || $0.category == category }
        case .favourites: favourites.ids(.workouts).compactMap(WorkoutStore.workout)
        case .imported: imported
        }
    }

    private func card(_ w: Workout) -> some View {
        PickerCard(title: w.name, meta: meta(w), selected: plan.workoutID == w.id,
                   favourite: (favourites.contains(w.id, .workouts), { favourites.toggle(w.id, .workouts) }),
                   action: { choose(w.id) }) {
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

    /// Deleting the chosen workout chooses the workhorse, so there's always one to start.
    private func delete(_ id: String) {
        WorkoutStore.delete(id: id)
        if plan.workoutID == id { plan.workoutID = Self.firstChoice }
        if favourites.contains(id, .workouts) { favourites.toggle(id, .workouts) }
        imported = WorkoutStore.imported
        deleting = nil
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
