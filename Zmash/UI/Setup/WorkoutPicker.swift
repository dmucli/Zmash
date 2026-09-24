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
    @State private var deleting: Workout?

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
                                            Button("Delete…", role: .destructive) { deleting = w }
                                        }
                                        .confirmationDialog("Delete \(w.name)?",
                                                            isPresented: Binding(get: { deleting?.id == w.id }, set: { if !$0 { deleting = nil } }),
                                                            titleVisibility: .visible) {
                                            Button("Delete", role: .destructive) {
                                                delete(w.id)
                                                deleting = nil
                                            }
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

    /// Plans by what they're for (D143), each with its length, rides and hours a week, and how it went before.
    private var plans: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(TrainingPlan.Goal.allCases, id: \.self) { goal in
                let list = TrainingPlans.all.filter { $0.goal == goal }
                if !list.isEmpty {
                    section("Plans · \(goal.title)") {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, plan in
                            NavigationLink {
                                PlanView(plan: plan) { dismiss() }
                            } label: {
                                let on = PlanStore.current?.planID == plan.id
                                PickCard(index: i + 1, title: plan.name, subtitle: plan.summary, meta: Self.planMeta(plan),
                                         selected: on) {
                                    if on {
                                        Tag(title: "You're on it", fill: Design.Accent.vermilion)
                                    } else if let before = Self.doneBefore(plan) {
                                        Tag(title: before)
                                    }
                                }
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
    }

    /// "6 weeks · 3 rides a week · ≈ 3 h 30 a week".
    private static func planMeta(_ plan: TrainingPlan) -> String {
        let minutes = plan.weeks.map { $0.map(PlanStore.minutes).reduce(0, +) }
        let perWeek = minutes.reduce(0, +) / max(plan.weeks.count, 1)
        let hours = perWeek >= 60 ? "\(perWeek / 60) h \(String(format: "%02d", perWeek % 60))" : "\(perWeek) min"
        return "\(plan.weeks.count) weeks · \(plan.sessionsPerWeek) rides a week · ≈ \(hours) a week"
    }

    /// "Done before · 16 of 18": the last time this rider finished or left the plan.
    private static func doneBefore(_ plan: TrainingPlan) -> String? {
        let rider = Riders.currentID
        guard let last = PlanStore.all.first(where: { $0.riderID == rider && $0.planID == plan.id && ($0.left || PlanStore.isFinished($0)) })
        else { return nil }
        let total = plan.weeks.map(\.count).reduce(0, +)
        return "Done before · \(last.done.count) of \(total)"
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
