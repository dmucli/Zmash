import SwiftUI
import UniformTypeIdentifiers
import ZmashKit

/// Choose a structured workout (or none), and import `.zwo` files.
struct WorkoutPicker: View {
    @Binding var workoutID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs
    @State private var imported = WorkoutStore.imported
    @State private var importing = false
    @State private var importFailed = false
    /// The builder: a new workout (nil inside) or one to edit or copy.
    @State private var building: Workout??

    @State private var filter = Filter.all

    enum Filter: String, CaseIterable { case all = "All", plans = "Plans", library = "Library", mine = "Mine" }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let compact = geo.size.width < 700
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(title: "Workouts", kicker: "Choose a session", compact: compact) {
                            if !compact {
                                PillButton(title: "New", icon: "plus", compact: true) { building = .some(nil) }
                                PillButton(title: "Import .zwo", compact: true) { importing = true }
                            }
                            PillButton(title: "Done", style: .invert, compact: true) { dismiss() }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Filter.allCases.filter { $0 != .mine || !imported.isEmpty }, id: \.self) { f in
                                    Chip(title: f.rawValue, selected: filter == f) { withAnimation(Design.Motion.base) { filter = f } }
                                }
                                if compact {
                                    Chip(title: "New", icon: "plus") { building = .some(nil) }
                                    Chip(title: "Import .zwo") { importing = true }
                                }
                            }
                        }
                        if filter == .all {
                            Button { workoutID = nil; dismiss() } label: {
                                PickCard(title: "No workout", subtitle: "Ride by duration and terrain.", selected: workoutID == nil) {
                                    LaneDashes(color: Design.Palette.fg1, thickness: 3)
                                }
                            }
                            .buttonStyle(PressStyle())
                            .frame(maxWidth: 420)
                        }
                        if filter == .all || filter == .plans { plans }
                        if filter == .all || filter == .library {
                            section("Library") {
                                ForEach(Array(WorkoutLibrary.all.enumerated()), id: \.element.id) { i, w in
                                    card(w, index: i + 1)
                                        .contextMenu { Button("Copy and edit") { building = .some(w) } }
                                }
                            }
                        }
                        if (filter == .all || filter == .mine) && !imported.isEmpty {
                            section("My workouts") {
                                ForEach(Array(imported.enumerated()), id: \.element.id) { i, w in
                                    card(w, index: i + 1)
                                        .contextMenu {
                                            Button("Edit") { building = .some(w) }
                                            Button("Delete", role: .destructive) { delete(w.id) }
                                        }
                                }
                            }
                        }
                    }
                    .pagePadding(compact)
                }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "zwo") ?? .xml, .xml],
                          allowsMultipleSelection: true) { result in
                let urls = (try? result.get()) ?? []
                let added = urls.compactMap(WorkoutStore.importZWO)
                imported = WorkoutStore.imported
                if let last = added.last { workoutID = last.id }
                importFailed = !urls.isEmpty && added.isEmpty
            }
            .sheet(isPresented: Binding(get: { building != nil }, set: { if !$0 { building = nil } })) {
                WorkoutBuilder(editing: building ?? nil) { w in
                    imported = WorkoutStore.imported
                    workoutID = w.id
                }
                .presentationSizing(.page)
            }
            .alert("Not a Zwift workout file", isPresented: $importFailed) {} message: {
                Text("Zmash reads .zwo files with steady, ramp, interval and free-ride steps.")
            }
        }
    }

    private var plans: some View {
        section("Plans") {
            ForEach(Array(TrainingPlans.all.enumerated()), id: \.element.id) { i, plan in
                NavigationLink {
                    PlanView(plan: plan) { dismiss() }
                } label: {
                    let on = PlanStore.current?.planID == plan.id
                    PickCard(index: i + 1, title: plan.name, subtitle: plan.summary, selected: on) {
                        if on { Tag(title: "You're on it", fill: Design.Accent.vermilion) }
                    }
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            CardGrid { content() }
        }
    }

    private func card(_ w: Workout, index: Int) -> some View {
        Button {
            workoutID = w.id
            dismiss()
        } label: {
            PickCard(index: index, title: w.name, subtitle: w.summary, meta: meta(w), selected: workoutID == w.id) {
                WorkoutStrip(workout: w.drawable).frame(height: 44)
            }
        }
        .buttonStyle(PressStyle())
    }

    private func meta(_ w: Workout) -> String {
        if w.isRampTest { return "~20 min · until you stop" }
        let load = w.estimatedLoad(ftp: Double(prefs.ftp))
        return "\(TimeFormat.clock(w.duration)) · TSS \(Int(load.tss.rounded())) · IF \(String(format: "%.2f", load.intensityFactor))"
    }

    private func delete(_ id: String) {
        WorkoutStore.delete(id: id)
        if workoutID == id { workoutID = nil }
        imported = WorkoutStore.imported
    }

}
