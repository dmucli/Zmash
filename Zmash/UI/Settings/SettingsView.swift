import SwiftUI
import ZmashKit

/// Settings (brief §15).
struct SettingsView: View {
    let hub: DeviceHub
    let openFaces: () -> Void
    let openProbe: () -> Void
    @Environment(Preferences.self) private var prefs
    /// Health said no when the switch was turned on: say where to allow it.
    @State private var healthDenied = false
    @State private var confirmSetUpAgain = false
    @State private var backup: (url: URL, text: String)?
    @State private var restoring = false
    @State private var restoreSettings = false
    @State private var dataMessage: String?

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 760
            ScrollView {
                if compact {
                    VStack(spacing: 16) { left; right }.pagePadding(true)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { left }.frame(maxWidth: .infinity)
                        VStack(spacing: 16) { right }.frame(maxWidth: .infinity)
                    }
                    .pagePadding(false)
                }
            }
        }
        .toggleStyle(PillToggleStyle())
        .screenBackground(stripe: false)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Columns (the prototype's Settings: rider and appearance on the left, the ride and connections on the right)

    @ViewBuilder private var left: some View {
        @Bindable var prefs = prefs
        group("Rider") {
            NavigationLink {
                RidersView()
            } label: {
                HStack(spacing: 12) {
                    RiderBadge(rider: prefs.currentRider, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prefs.currentRider.name).font(Design.Font.sans(16, weight: 600)).foregroundStyle(Design.Palette.fg1)
                        Text("\(prefs.riders.count) rider\(prefs.riders.count == 1 ? "" : "s") on this iPad · switch, add or rename")
                            .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    }
                    Spacer(minLength: 8)
                    Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                NumberTile(label: "FTP", text: "\(prefs.ftp)", unit: "W") {
                    prefs.ftp = min(Preferences.ftpRange.upperBound, max(Preferences.ftpRange.lowerBound, prefs.ftp + ($0 ? 5 : -5)))
                }
                NumberTile(label: "Weight", text: "\(Int(prefs.riderKg))", unit: "kg") {
                    let kg = Preferences.riderKgRange
                    prefs.riderKg = min(kg.upperBound, max(kg.lowerBound, prefs.riderKg + ($0 ? 1 : -1)))
                }
                NumberTile(label: "Bike", text: String(format: "%.1f", prefs.bikeKg), unit: "kg") {
                    prefs.bikeKg = min(30, max(3, prefs.bikeKg + ($0 ? 0.5 : -0.5)))
                }
            }
        }
        group("Appearance") {
            SettingRow(title: "Theme", note: "Dark is easier on the eyes in a dim pain cave.") {
                Segmented(options: [(ThemePreference.system, "Auto"), (.light, "Light"), (.dark, "Dark")], selection: $prefs.theme)
                    .frame(width: 230)
            }
            SettingRow(title: "Units") {
                Segmented(options: [(Units.metric, "km/h"), (.imperial, "mph")], selection: $prefs.units).frame(width: 160)
            }
            SettingRow(title: "Watts", note: "What the live power number shows.") {
                Segmented(options: [(0, "Now"), (3, "3 s"), (10, "10 s")], selection: $prefs.wattsWindow).frame(width: 200)
            }
        }
        group("Faces") {
            SettingRow(title: prefs.face.name, note: "Choose and customise faces: palette, main number, numbers, font, motion and the course profile. D-pad left and right switch faces mid-ride.") {
                PillButton(title: "Faces", icon: "sliders-horizontal", compact: true, action: openFaces)
            }
        }
    }

    @ViewBuilder private var right: some View {
        @Bindable var prefs = prefs
        group("Ride") {
            SettingRow(title: "Gears", note: "How many virtual gears the shifters step through.") {
                Menu {
                    Picker("Gears", selection: $prefs.gearCount) {
                        ForEach(GearSet.choices, id: \.self) { Text("\($0)").tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(prefs.gearCount)").font(Design.Font.bib(26)).foregroundStyle(Design.Palette.fg1)
                        Icon("chevron-down", size: 13).foregroundStyle(Design.Palette.fg3)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Capsule().fill(Design.Palette.surfaceSunk))
                }
            }
            Toggle(isOn: $prefs.autoPause) { rowLabel("Auto-pause", "Stops the clock when you stop pedalling.") }
            if PiPOverlay.isSupported {
                Toggle(isOn: $prefs.pipOnLeave) { rowLabel("Floating window", "Your numbers over other apps when you leave Zmash.") }
            }
            Toggle(isOn: $prefs.hapticsOnShift) { rowLabel("Buzz on shift") }
        }
        group("Sound and coaching") {
            Toggle(isOn: $prefs.rideSound) {
                rowLabel("Ride sounds", "Wind, the freewheel, a chain click on each shift, a crowd near the top, a bell at the summit. Plays under your music.")
            }
            if prefs.rideSound {
                HStack(spacing: 12) {
                    Text("Volume").font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                    Slider(value: $prefs.soundVolume, in: 0.1...1)
                }
                Toggle(isOn: $prefs.kilometreChime) { rowLabel("Chime every kilometre") }
            }
            Toggle(isOn: $prefs.coaching) {
                rowLabel("Coaching messages", "Short notes along the bottom of the ride, at most one a minute and never mid-sprint.")
            }
            if prefs.coaching {
                ForEach(Coach.Kind.allCases, id: \.self) { kind in
                    Toggle(isOn: Binding(
                        get: { prefs.coachKinds.contains(kind) },
                        set: { on in if on { prefs.coachKinds.insert(kind) } else { prefs.coachKinds.remove(kind) } })) {
                        rowLabel(kind.title)
                    }
                    .padding(.leading, 16)
                }
            }
            if HealthExport.isAvailable {
                Toggle(isOn: Binding(
                    get: { prefs.saveToHealth },
                    set: { on in
                        if on {
                            Task {
                                let allowed = await HealthExport.requestAuthorization()
                                prefs.saveToHealth = allowed
                                healthDenied = !allowed
                            }
                        } else {
                            prefs.saveToHealth = false
                        }
                    })) {
                    rowLabel("Save rides to Apple Health",
                             healthDenied ? "Health didn't allow it. Turn Zmash on in Settings → Health → Data Access & Devices."
                                          : "Indoor cycling workouts with power, cadence and heart rate.")
                }
            }
        }
        group("Your data") {
            Button { makeBackup() } label: {
                linkLabel("Back up to Files", icon: "share", note: "Every rider's rides, plans, campaigns, routes and settings.")
            }
            .buttonStyle(.plain)
            if let backup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(backup.text).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: backup.url) {
                        Text("Send it somewhere else…").font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                    }
                    .frame(minHeight: 44)
                }
                .padding(.leading, 48)
            }
            Button { restoring = true } label: {
                linkLabel("Restore from a backup", icon: "history", note: "Adds the rides and files this iPad doesn't have.")
            }
            .buttonStyle(.plain)
            Toggle(isOn: $restoreSettings) {
                rowLabel("Restore riders and settings too", "Replaces this iPad's, from the next launch.")
            }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                let counts = try Backup.restore(from: url, settings: restoreSettings)
                dataMessage = "Restored \(counts.summary)." + (counts.settings ? " Close and reopen Zmash to see the riders and settings." : "")
            } catch {
                dataMessage = error.localizedDescription
            }
        }
        .alert("Backup", isPresented: Binding(get: { dataMessage != nil }, set: { if !$0 { dataMessage = nil } })) {} message: {
            Text(dataMessage ?? "")
        }
        group("Connections") {
            link("Devices", icon: "bluetooth") { DevicesView(hub: hub) }
            link("Controller buttons", icon: "gamepad-2") { ButtonMapView() }
            link("Uploads", icon: "upload", note: "Strava or intervals.icu, with your own account.") { UploadSettingsView() }
            ShareLink(item: DiagnosticsExport(hub: hub, prefs: prefs), preview: SharePreview("Zmash diagnostics")) {
                linkLabel("Export diagnostics", icon: "share-2")
            }
            .buttonStyle(.plain)
            Button(action: openProbe) { linkLabel("Hardware probe", icon: "activity") }.buttonStyle(.plain)
            Button { confirmSetUpAgain = true } label: { linkLabel("Set up again", icon: "refresh-cw") }.buttonStyle(.plain)
                .confirmationDialog("Set up again?", isPresented: $confirmSetUpAgain, titleVisibility: .visible) {
                    Button("Set up again") { prefs.hasCompletedSetup = false }
                } message: {
                    Text("Pairing, your numbers and the controls, from the start. Your rides and settings stay.")
                }
        }
    }

    private func makeBackup() {
        do {
            let made = try Backup.make()
            backup = (made.url, "Saved \(made.counts.summary) in Files → On My iPad → Zmash → Backups → \(made.url.lastPathComponent). Upload accounts aren't included.")
        } catch {
            dataMessage = "The backup didn't work: \(error.localizedDescription)"
        }
    }

    // MARK: Pieces

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func rowLabel(_ title: String, _ note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
            if let note {
                Text(note).font(Design.Font.small).foregroundStyle(Design.Palette.fg3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func link<Destination: View>(_ title: String, icon: String, note: String? = nil,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) { linkLabel(title, icon: icon, note: note) }.buttonStyle(.plain)
    }

    private func linkLabel(_ title: String, icon: String, note: String? = nil) -> some View {
        HStack(spacing: 12) {
            Icon(icon, size: 18).foregroundStyle(Design.Palette.fg2)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Design.Radius.sm).fill(Design.Palette.surfaceSunk))
            rowLabel(title, note)
            Spacer(minLength: 8)
            Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.fg3)
        }
        .contentShape(Rectangle())
    }
}

/// A rider number as a sunk tile (the prototype's FTP / WEIGHT tiles), with − and + to change it.
private struct NumberTile: View {
    let label: String
    let text: String
    let unit: String
    let change: (_ up: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // VoiceOver lands on the number: swipe up or down to change it.
            StatTile(label: label, value: text, unit: unit, size: 34)
                .accessibilityElement(children: .combine)
                .accessibilityAdjustableAction { change($0 == .increment) }
            HStack(spacing: 6) {
                RoundIconButton(icon: "minus", size: 32) { change(false) }.accessibilityLabel("Less \(label)")
                RoundIconButton(icon: "plus", size: 32) { change(true) }.accessibilityLabel("More \(label)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunkTile(padding: 12)
        .accessibilityElement(children: .contain)
    }
}
