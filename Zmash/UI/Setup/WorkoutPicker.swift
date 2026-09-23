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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil, name: "No workout", detail: "Ride by duration and terrain.")
                }
                Section("Plans") {
                    ForEach(TrainingPlans.all) { plan in
                        NavigationLink {
                            PlanView(plan: plan) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(plan.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                                    if PlanStore.current?.planID == plan.id {
                                        Text("· you're on it").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                                    }
                                }
                                Text(plan.summary).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                Section("Library") {
                    ForEach(WorkoutLibrary.all) { w in
                        row(w, name: w.name, detail: w.summary)
                            .contextMenu { Button("Copy and edit") { building = .some(w) } }
                    }
                }
                if !imported.isEmpty {
                    Section("My workouts") {
                        ForEach(imported) { w in
                            row(w, name: w.name, detail: w.summary)
                                .swipeActions(edge: .leading) { Button("Edit") { building = .some(w) } }
                                .contextMenu { Button("Edit") { building = .some(w) } }
                        }
                            .onDelete { idx in
                                idx.map { imported[$0].id }.forEach { id in
                                    WorkoutStore.delete(id: id)
                                    if workoutID == id { workoutID = nil }
                                }
                                imported = WorkoutStore.imported
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Design.Palette.background)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button("New") { building = .some(nil) }
                        Button("Import .zwo") { importing = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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

    private func row(_ w: Workout?, name: String, detail: String) -> some View {
        Button {
            workoutID = w?.id
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Spacer()
                    if let w {
                        Text(w.isRampTest ? "~20 min" : TimeFormat.clock(w.duration))
                            .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    }
                    if workoutID == w?.id {
                        Icon("check", size: 18).foregroundStyle(Design.Palette.primary)
                    }
                }
                if !detail.isEmpty {
                    Text(detail).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
                if let w {
                    WorkoutStrip(workout: w.isRampTest ? rampPreview(w) : w, color: Design.Palette.primary)
                        .frame(height: 26)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Design.Palette.surface)
    }

    /// The ramp test is open-ended; preview the part most riders reach.
    private func rampPreview(_ w: Workout) -> Workout {
        var p = w
        p.steps = Array(w.steps.prefix(16))
        return p
    }
}
