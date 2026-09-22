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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil, name: "No workout", detail: "Ride by duration and terrain.")
                }
                Section("Library") {
                    ForEach(WorkoutLibrary.all) { w in row(w, name: w.name, detail: w.summary) }
                }
                if !imported.isEmpty {
                    Section("Imported") {
                        ForEach(imported) { w in row(w, name: w.name, detail: w.summary) }
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
                    Button("Import .zwo") { importing = true }
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

/// The chosen workout on the setup screen.
struct WorkoutCard: View {
    let plan: SessionPlan
    let action: () -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.workout?.name ?? "No workout").font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Spacer()
                    Text(plan.workout == nil ? "Choose" : "Change")
                        .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
                if let w = plan.workout {
                    WorkoutStrip(workout: w, color: Design.Palette.primary).frame(height: 40)
                    Text(detail(w)).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ w: Workout) -> String {
        if w.isRampTest { return "FTP \(prefs.ftp) W · starts at \(prefs.ftp / 2) W, +6 % every minute" }
        let load = Training.load(w.steps.flatMap { s in
            (0..<s.seconds).map { Int(((s.fraction(at: Double($0)) ?? 0.6) * Double(prefs.ftp)).rounded()) }
        }, ftp: Double(prefs.ftp))
        return "\(TimeFormat.clock(w.duration)) · FTP \(prefs.ftp) W · TSS \(Int(load.tss.rounded()))"
    }
}
