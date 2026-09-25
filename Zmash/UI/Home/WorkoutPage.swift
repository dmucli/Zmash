import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Workouts (D148): the library by kind, your favourites, and your own (built here or imported from a `.zwo` file).
/// The preview shows the chosen one, with ERG or gradients, over Start. Plans have their own page.
struct WorkoutPage: View {
    let context: RideContext
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan
    @State private var tab: Tab
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

    init(context: RideContext, initial: SessionPlan? = nil) {
        self.context = context
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
        let workout = plan.workout
        RidePage(title: "Workout", context: context, start: workout.map { w in
            StartInfo(title: w.name, detail: summary(w), start: {
                prefs.lastPlan = plan
                context.start(plan)
            }, favourite: w.id.hasPrefix("plan/") ? nil : (favourites.contains(w.id, .workouts), { favourites.toggle(w.id, .workouts) }))
        }) {
            ChooseColumn(tabs: Tab.allCases.map { ($0, $0.rawValue) }, tab: $tab, hint: hint, addLabel: "Add a workout") {
                Button("New workout") { building = .some(nil) }
                Button("Import a .zwo file") { importing = true }
            } content: {
                ChooseList(scrollTo: plan.workoutID, showing: tab.rawValue) {
                    switch tab {
                    case .workouts: library
                    case .favourites: favouriteList
                    case .imported: importedList
                    }
                }
            }
        } preview: {
            FitOrScroll {
                Group {
                    if let workout {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkoutPreview(workout: workout, ftp: prefs.ftp)
                            targets
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
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

    private var hint: String {
        switch tab {
        case .workouts: "Easiest first. ♡ keeps one under Favourites."
        case .favourites: "The ones you keep coming back to, newest first."
        case .imported: "Built with + or imported from a .zwo file. Long-press one to edit or delete it."
        }
    }

    // MARK: Lists

    @ViewBuilder private var library: some View {
        ForEach(Workout.Category.allCases, id: \.self) { category in
            let list = WorkoutLibrary.all.filter { $0.category == category }
            if !list.isEmpty {
                ChooseSection(category.title)
                ForEach(list, id: \.id) { w in
                    row(w).contextMenu { Button("Copy and edit") { building = .some(w) } }
                }
            }
        }
    }

    @ViewBuilder private var favouriteList: some View {
        let list = favourites.ids(.workouts).compactMap(WorkoutStore.workout)
        if list.isEmpty {
            ChooseHint(text: "Tap ♡ on a workout, in the list or under its preview, to keep it here.")
        }
        ForEach(list, id: \.id) { w in row(w) }
    }

    @ViewBuilder private var importedList: some View {
        if imported.isEmpty {
            ChooseHint(text: "Your own workouts: build one with +, or import a .zwo file from Zwift, TrainerRoad or intervals.icu.")
        }
        ForEach(imported, id: \.id) { w in
            row(w).contextMenu {
                Button("Edit") { building = .some(w) }
                Button("Delete…", role: .destructive) { deleting = w }
            }
        }
    }

    private func row(_ w: Workout) -> some View {
        ChooseRow(title: w.name, subtitle: meta(w), selected: plan.workoutID == w.id,
                  favourite: (favourites.contains(w.id, .workouts), { favourites.toggle(w.id, .workouts) }),
                  action: { choose(w.id) }) {
            WorkoutStrip(workout: w.drawable)
        }
        .id(w.id)
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

    private func meta(_ w: Workout) -> String {
        if w.isRampTest { return "~20 min · until you stop" }
        let load = w.estimatedLoad(ftp: Double(prefs.ftp))
        return "\(TimeFormat.clock(w.duration)) · TSS \(Int(load.tss.rounded())) · IF \(String(format: "%.2f", load.intensityFactor))"
    }

    // MARK: Preview

    /// ERG or gradients, under the workout.
    private var targets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Targets").monoLabel().foregroundStyle(Design.Palette.fg3)
                Segmented(options: [(true, "ERG"), (false, "Gradient")],
                          selection: Binding(get: { plan.usesERG }, set: { plan.workoutERG = $0 }))
            }
            Text(targetsNote)
                .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetsNote: String {
        if plan.usesERG {
            return context.hub.trainer.supportsERG
                ? "The trainer holds each target whatever gear you're in; the shifters change the intensity."
                : "This trainer can't hold a target, so the targets become gradients."
        }
        return "Each target becomes a gradient. You hold the power yourself, shifting as you would on a climb."
    }

    private func summary(_ w: Workout) -> String {
        let length = w.isRampTest ? "Until you stop" : TimeFormat.clock(w.duration)
        let targets = plan.usesERG && context.hub.trainer.supportsERG ? "ERG" : "Gradient"
        return "\(length) · \(targets) · FTP \(prefs.ftp) W"
    }
}
