import SwiftUI
import ZmashKit

/// Settings (brief §15).
struct SettingsView: View {
    let hub: DeviceHub
    let openFaces: () -> Void
    let openProbe: () -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section("Rider") {
                Stepper(value: $prefs.riderKg, in: 30...200, step: 1) {
                    LabeledContent("Rider weight", value: "\(Int(prefs.riderKg)) kg")
                }
                Stepper(value: $prefs.bikeKg, in: 3...30, step: 0.5) {
                    LabeledContent("Bike weight", value: String(format: "%.1f kg", prefs.bikeKg))
                }
                Stepper(value: $prefs.ftp, in: 80...500, step: 5) {
                    LabeledContent("FTP", value: "\(prefs.ftp) W")
                }
            }

            Section {
                Button("Faces") { openFaces() }
                LabeledContent("Current face", value: prefs.face.name)
                Picker("Face motion", selection: $prefs.faceMotion) {
                    Text("Full").tag(FaceMotion.full)
                    Text("Calm").tag(FaceMotion.calm)
                }
                Toggle("Course profile along the bottom", isOn: $prefs.courseStrip)
            } header: {
                Text("Faces")
            } footer: {
                Text("FTP sets the power zones behind the effort colours. D-pad left/right switches faces mid-ride.")
            }

            Section("Display") {
                Picker("Units", selection: $prefs.units) {
                    Text("km/h").tag(Units.metric)
                    Text("mph").tag(Units.imperial)
                }
                Picker("Theme", selection: $prefs.theme) {
                    Text("System").tag(ThemePreference.system)
                    Text("Light").tag(ThemePreference.light)
                    Text("Dark").tag(ThemePreference.dark)
                }
                NavigationLink("Classic face") { DisplaySettingsView() }
                Picker("Watts", selection: $prefs.wattsWindow) {
                    Text("Instant").tag(0)
                    Text("3 s average").tag(3)
                    Text("10 s average").tag(10)
                }
            }

            Section("Ride") {
                Picker("Gears", selection: $prefs.gearCount) {
                    ForEach(GearSet.choices, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Auto-pause", isOn: $prefs.autoPause)
                if PiPOverlay.isSupported {
                    Toggle("Floating window when leaving the app", isOn: $prefs.pipOnLeave)
                }
                Toggle("Buzz on shift", isOn: $prefs.hapticsOnShift)
            }

            Section {
                Toggle("Coaching messages", isOn: $prefs.coaching)
                if prefs.coaching {
                    ForEach(Coach.Kind.allCases, id: \.self) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { prefs.coachKinds.contains(kind) },
                            set: { on in if on { prefs.coachKinds.insert(kind) } else { prefs.coachKinds.remove(kind) } }))
                    }
                }
            } footer: {
                Text("Short notes along the bottom of the ride screen, at most one a minute and never mid-sprint. Off with Calm motion.")
            }

            if HealthExport.isAvailable {
                Section {
                    Toggle("Save rides to Apple Health", isOn: Binding(
                        get: { prefs.saveToHealth },
                        set: { on in
                            if on {
                                Task { prefs.saveToHealth = await HealthExport.requestAuthorization() }
                            } else {
                                prefs.saveToHealth = false
                            }
                        }))
                } footer: {
                    Text("Saved rides appear in Health and Fitness as indoor cycling workouts, with power, cadence and heart rate.")
                }
            }

            Section {
                NavigationLink("Uploads") { UploadSettingsView() }
            } footer: {
                Text("Send rides to Strava or intervals.icu with your own account.")
            }

            Section {
                NavigationLink("Devices") { DevicesView(hub: hub) }
                if let url = Diagnostics.exportFile(hub: hub, prefs: prefs) {
                    ShareLink("Export diagnostics", item: url)
                }
                NavigationLink("Controller buttons") { ButtonMapView() }
                Button("Hardware probe", action: openProbe)
                Button("Set up again") { prefs.hasCompletedSetup = false }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
