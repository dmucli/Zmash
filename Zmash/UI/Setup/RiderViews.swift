import SwiftData
import SwiftUI
import ZmashKit

/// Who's riding, in the home header (D112): tap to switch, add someone, or manage riders.
struct RiderMenu: View {
    let compact: Bool
    let manage: () -> Void
    @Environment(Preferences.self) private var prefs
    @State private var adding = false

    var body: some View {
        let current = prefs.currentRider
        Menu {
            Section("Who's riding?") {
                ForEach(prefs.riders) { r in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { prefs.switchRider(to: r.id) }
                    } label: {
                        if r.id == prefs.riderID { Label(r.name, systemImage: "checkmark") } else { Text(r.name) }
                    }
                }
            }
            Button("Add a rider…") { adding = true }
            Button("Manage riders…", action: manage)
        } label: {
            HStack(spacing: 8) {
                RiderBadge(rider: current, size: 28)
                if !compact { Text(current.name).font(Design.Font.sans(14, weight: 600)).lineLimit(1) }
                Icon("chevron-down", size: 13)
            }
            .foregroundStyle(Design.Palette.fg1)
            .padding(.leading, 6).padding(.trailing, 12)
            .frame(minHeight: 40)
            .background {
                Capsule().fill(Design.Palette.surfaceGlass)
                Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
            }
        }
        .accessibilityLabel("Rider: \(current.name). Switch or add a rider.")
        .sheet(isPresented: $adding) { AddRiderSheet() }
    }
}

/// A rider's initials in a circle.
struct RiderBadge: View {
    let rider: RiderProfile
    var size: CGFloat = 28

    var body: some View {
        Text(rider.initials)
            .font(Design.Font.bib(size * 0.5))
            .foregroundStyle(Design.Palette.onAccent)
            .frame(width: size, height: size)
            .background(Circle().fill(Design.Accent.vermilion))
            .accessibilityHidden(true)
    }
}

/// Someone new on this iPad: a name and the three numbers that make the ride feel right.
struct AddRiderSheet: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var riderKg = 70.0
    @State private var bikeKg = 9.0
    @State private var ftp = 200
    @State private var guessed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textContentType(.givenName)
                }
                Section {
                    Stepper(value: $riderKg, in: 30...200, step: 1) { LabeledContent("Weight", value: "\(Int(riderKg)) kg") }
                    Stepper(value: $bikeKg, in: 3...30, step: 0.5) { LabeledContent("Bike", value: String(format: "%.1f kg", bikeKg)) }
                    Stepper(value: $ftp, in: 60...500, step: 5) { LabeledContent("FTP", value: "\(ftp) W") }
                    Button(guessed ? "Starting at \(ftp) W · a ramp test is suggested" : "Not sure of the FTP? Start from a guess") {
                        ftp = Int((riderKg * 2.5 / 5).rounded()) * 5
                        guessed = true
                    }
                } footer: {
                    Text("Each rider has their own rides, records, plans, campaigns, faces and upload accounts. Devices, buttons and sounds are shared.")
                }
            }
            .navigationTitle("Add a rider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        prefs.addRider(name: name.trimmingCharacters(in: .whitespaces), riderKg: riderKg, bikeKg: bikeKg,
                                       ftp: ftp, guessedFTP: guessed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Settings → Riders: rename, switch, add or remove (removing deletes their rides, plans and campaigns).
struct RidersView: View {
    @Environment(Preferences.self) private var prefs
    @State private var adding = false
    @State private var removing: RiderProfile?
    @State private var renaming: RiderProfile?
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                ForEach(prefs.riders) { r in
                    HStack(spacing: 12) {
                        RiderBadge(rider: r, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(Design.Font.label)
                            Text("\(Int(r.riderKg)) kg · FTP \(r.ftp) W").font(Design.Font.small).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if r.id == prefs.riderID {
                            Text("Riding").font(Design.Font.small).foregroundStyle(.secondary)
                        } else {
                            Button("Switch") { prefs.switchRider(to: r.id) }.buttonStyle(.borderless)
                        }
                    }
                    .swipeActions {
                        if r.id != prefs.riderID {
                            Button("Remove", role: .destructive) { removing = r }
                        }
                        Button("Rename") { newName = r.name; renaming = r }.tint(.gray)
                    }
                    .contextMenu {
                        Button("Rename") { newName = r.name; renaming = r }
                        if r.id != prefs.riderID { Button("Remove", role: .destructive) { removing = r } }
                    }
                }
            } footer: {
                Text("Swipe or long-press a rider to rename or remove them. The rider section above edits whoever is riding.")
            }
            Section {
                Button("Add a rider") { adding = true }
            }
        }
        .navigationTitle("Riders")
        .sheet(isPresented: $adding) { AddRiderSheet() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let r = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    prefs.renameRider(r.id, to: newName.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove, with their rides", role: .destructive) {
                if let r = removing { RiderData.delete(r.id); prefs.removeRider(r.id) }
                removing = nil
            }
        } message: {
            Text("Their rides, records, plans and campaigns are deleted from this iPad. Rides already uploaded stay where they went.")
        }
    }
}

/// Everything a rider left on this iPad, for removing them.
@MainActor
enum RiderData {
    static func delete(_ riderID: String) {
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.riderID == riderID })
        for ride in (try? RideStore.context.fetch(d)) ?? [] { RideStore.context.delete(ride) }
        try? RideStore.context.save()
        PlanStore.all.filter { $0.riderID == riderID }.forEach(PlanStore.delete)
        CampaignStore.everyone.filter { $0.riderID == riderID }.forEach(CampaignStore.delete)
    }
}
