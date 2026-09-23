import SwiftUI
import ZmashKit

/// Pair, forget and inspect controllers, the trainer and a heart-rate strap. Also hosts advanced device settings.
struct DevicesView: View {
    let hub: DeviceHub
    @Environment(Preferences.self) private var prefs
    @State private var pairing: DeviceRole?
    @State private var calibrating = false

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            if let ble = hub.ble, ble.state == .poweredOff || ble.state == .unauthorized {
                Section {
                    Text(ble.state == .unauthorized ? "Bluetooth access is off for Zmash." : "Bluetooth is off.")
                    if ble.state == .unauthorized, let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            }

            Section {
                if let group = hub.ble?.controllers, !group.clients.isEmpty {
                    ForEach(group.clients, id: \.self) { client in
                        DeviceRow(title: client.kind.displayName, link: client.link, detail: detail(client))
                    }
                    if group.firmwareSupported == false {
                        Text("Ride firmware is newer than 1.2.0. Buttons may stop working; the on-screen controls always work.")
                            .font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    }
                } else {
                    DeviceRow(title: "Controller", link: hub.ride.link, detail: hub.isDemo ? "demo" : nil)
                }
                if let ble = hub.ble { pairButtons(.ride, ble: ble) }
            } header: {
                SectionHeader("Controller")
            } footer: {
                Text("Zwift Ride, Zwift Play (pair both sides) or Zwift Click. Close Zwift and Zwift Companion first. For the Ride, turn on the left controller, then the right.")
            }

            Section {
                if !hub.isDemo {
                Picker("Type", selection: Binding(get: { prefs.basicTrainer == nil ? "smart" : "basic" }, set: { kind in
                    prefs.basicTrainer = kind == "smart" ? nil : prefs.basicTrainer ?? .genericFluid
                    hub.refreshTrainer()
                })) {
                    Text("Smart (Bluetooth control)").tag("smart")
                    Text("Basic (wheel-on, no control)").tag("basic")
                }
                }
                if let curve = prefs.basicTrainer {
                    Picker("Model", selection: Binding(get: { curve }, set: { prefs.basicTrainer = $0; hub.refreshTrainer() })) {
                        ForEach(TrainerPowerCurve.allCases) { Text($0.name).tag($0) }
                    }
                    Stepper("Wheel \(prefs.wheelCircumferenceMM) mm", value: $prefs.wheelCircumferenceMM, in: 1800...2400, step: 5)
                    DeviceRow(title: "Speed from sensor", link: hub.trainer.link, detail: nil)
                } else {
                    DeviceRow(title: "Trainer", link: hub.trainer.link, detail: trainerDetail)
                    if let ble = hub.ble { pairButtons(.trainer, ble: ble) }
                    if hub.ble != nil, hub.trainer.link == .ready {
                        Button("Calibrate (spin-down)") { calibrating = true }
                        Text(prefs.lastCalibration.map { "Last calibrated " + $0.formatted(.relative(presentation: .named)) } ?? "Not calibrated yet")
                            .font(Design.Font.small).foregroundStyle(prefs.calibrationDue ? Design.Status.caution : Design.Palette.fg3)
                    }
                }
                if let note = hub.trainer.statusNote { Text(note).font(Design.Font.small).foregroundStyle(Design.Palette.fg3) }
            } header: {
                SectionHeader("Trainer")
            } footer: {
                if prefs.basicTrainer != nil {
                    Text("A basic trainer needs a speed sensor on the rear wheel (or a power meter that counts wheel turns). Power is worked out from its maker's power curve; a power meter, if paired, is used instead. Wheel size: 700×25c is 2105 mm, 700×28c 2136 mm.")
                }
            }

            Section {
                DeviceRow(title: "Power meter", link: hub.ble?.powerMeter.link ?? .unpaired,
                          detail: hub.ble?.powerMeter.freshPower.map { "\($0) W" })
                if let ble = hub.ble { pairButtons(.powerMeter, ble: ble) }
                if powerMeterPaired, prefs.basicTrainer == nil {
                    Picker("Power numbers from", selection: $prefs.powerSource) {
                        Text("Trainer").tag(PowerSource.trainer)
                        Text("Power meter").tag(PowerSource.powerMeter)
                    }
                    if let ratio = hub.powerMeterRatio, abs(ratio - 1) >= 0.01 {
                        Text(String(format: "The trainer reads %.0f %% %@ than your power meter.", abs(ratio - 1) * 100, ratio > 1 ? "lower" : "higher"))
                            .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    }
                }
            } header: {
                SectionHeader("Power meter")
            } footer: {
                Text("Optional. Pedals, cranks or a hub. With \"Power meter\" chosen, the ride uses its numbers, and ERG targets are adjusted so the power meter, not the trainer, reads the target.")
            }

            Section {
                DeviceRow(title: "Speed / cadence", link: hub.ble?.speedCadence.link ?? .unpaired,
                          detail: sensorDetail)
                if let ble = hub.ble { pairButtons(.speedCadence, ble: ble) }
            } header: {
                SectionHeader("Speed and cadence")
            } footer: {
                Text("Optional. Cadence fills in when the trainer doesn't report it; wheel speed drives a basic trainer.")
            }

            Section {
                DeviceRow(title: "Heart rate", link: hub.isDemo ? .ready : hub.ble?.heartRate.link ?? .unpaired,
                          detail: hub.heartRateBpm.map { "\($0) bpm" + (hub.isDemo ? " · demo" : "") })
                if let ble = hub.ble { pairButtons(.heartRate, ble: ble) }
                if WatchLink.available {
                    Toggle("Heart rate from Apple Watch", isOn: $prefs.useWatch)
                }
            } header: {
                SectionHeader("Heart rate")
            } footer: {
                Text(WatchLink.available
                     ? "Optional. Any Bluetooth heart-rate strap, or your Apple Watch: with it on, each ride opens Zmash on the Watch, which sends heart rate and shows the ride (tap to pause, turn the crown to shift). A strap wins if both are there."
                     : "Optional. Any Bluetooth heart-rate strap.")
            }

            Section {
                Picker("Trainer protocol", selection: $prefs.trainerProtocol) {
                    Text("Auto").tag(TrainerProtocolPreference.auto)
                    Text("FTMS").tag(TrainerProtocolPreference.ftms)
                    Text("Zwift").tag(TrainerProtocolPreference.zwift)
                    Text("Wahoo (older KICKR, SNAP)").tag(TrainerProtocolPreference.wahoo)
                    Text("Tacx FE-C (older Neo, Flux)").tag(TrainerProtocolPreference.tacx)
                }
                Toggle("Shift with ERG", isOn: $prefs.ergShifting)
                    .disabled(prefs.trainerProtocol == .zwift)
                #if !targetEnvironment(simulator)
                Toggle("Demo devices", isOn: Binding(get: { hub.isDemo }, set: { hub.setDemo($0) }))
                #endif
            } header: {
                SectionHeader("Advanced")
            } footer: {
                Text("Protocol changes apply on the next connection. ERG holds the power your gear needs instead of simulating a grade: use it only if shifting feels wrong in FTMS.")
            }
        }
        .zmashForm()
        .navigationTitle("Devices")
        .sheet(isPresented: $calibrating) {
            if let trainer = hub.ble?.trainer { CalibrationView(trainer: trainer).environment(prefs) }
        }
        .sheet(item: $pairing) { role in
            if let ble = hub.ble {
                PairingSheet(ble: ble, role: role)
            }
        }
    }

    @ViewBuilder
    private func pairButtons(_ role: DeviceRole, ble: BLECentral) -> some View {
        let _ = ble.pairingRevision // re-read the registry after pair/forget
        let paired = !DeviceRegistry.ids(for: role).isEmpty
        if !paired {
            Button("Pair \(role.title.lowercased())") { pairing = role }
        } else {
            Button(role == .ride ? "Pair another controller" : "Pair a different \(role.title.lowercased())") { pairing = role }
            Button("Forget", role: .destructive) { ble.forget(role) }
        }
    }

    private func detail(_ c: ZwiftControllerClient) -> String? {
        var parts: [String] = []
        if let b = c.batteryPercent { parts.append("\(b) %") }
        if let f = c.firmware { parts.append("fw \(f)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var powerMeterPaired: Bool {
        guard let ble = hub.ble else { return false }
        _ = ble.pairingRevision // re-read the registry after pair/forget
        return !DeviceRegistry.ids(for: .powerMeter).isEmpty
    }

    private var sensorDetail: String? {
        guard let s = hub.ble?.speedCadence else { return nil }
        let parts = [s.freshCadence.map { "\(Int($0.rounded())) rpm" },
                     s.freshWheelKph.map { String(format: "%.1f km/h", $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var trainerDetail: String? {
        if hub.isDemo { return "demo" }
        guard let p = hub.trainer.activeProtocol else { return nil }
        if p == .zwift { return "Zwift protocol" }
        return prefs.ergShifting ? "\(p.name) · ERG" : p.name
    }
}

/// One device: an icon tile with its status dot, the kind as a mono label, its state, and a quiet detail.
private struct DeviceRow: View {
    let title: String
    let link: LinkState
    let detail: String?

    private var icon: String {
        switch title {
        case "Heart rate": "heart"
        case "Power meter": "zap"
        case "Speed / cadence": "gauge"
        case "Trainer", "Speed from sensor": "bike"
        default: "gamepad-2"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Icon(icon, size: 20).foregroundStyle(Design.Palette.fg1)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: Design.Radius.md).fill(Design.Palette.surfaceSunk))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(link.color).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Design.Palette.surface, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
                Text(link.label).font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                if let detail { Text(detail).font(Design.Font.small).foregroundStyle(Design.Palette.fg3) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PairingSheet: View {
    let ble: BLECentral
    let role: DeviceRole
    @Environment(\.dismiss) private var dismiss

    private var candidates: [PairingCandidate] {
        ble.candidates.values.filter { $0.roles.contains(role) }.sorted { $0.rssi > $1.rssi }
    }

    private var hint: String {
        switch role {
        case .ride: "Looking for controllers… (Zwift Ride: the left controller)"
        case .trainer: "Looking for trainers…"
        case .heartRate: "Looking for heart-rate straps… Wear it to wake it up."
        case .powerMeter: "Looking for power meters… Turn the cranks to wake it up."
        case .speedCadence: "Looking for speed and cadence sensors… Spin the wheel or the cranks to wake it up."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(hint).foregroundStyle(Design.Palette.fg3)
                    }
                }
                ForEach(candidates) { candidate in
                    Button {
                        ble.pair(candidate, as: role)
                        dismiss()
                    } label: {
                        HStack {
                            Text(candidate.name)
                            Spacer()
                            Text("\(candidate.rssi) dBm").font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                        }
                    }
                }
            }
            .zmashForm()
            .navigationTitle("Pair \(role.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .onAppear { ble.startPairingScan() }
        .onDisappear { ble.stopScan() }
    }
}

extension LinkState {
    var label: String {
        switch self {
        case .bluetoothOff: "Bluetooth off"
        case .unpaired: "Not paired"
        case .searching: "Searching"
        case .connecting: "Connecting"
        case .ready: "Connected"
        }
    }

    var color: Color {
        switch self {
        case .ready: Design.Status.go
        case .connecting, .searching: Design.Status.caution
        case .unpaired: Design.Palette.fgGhost
        case .bluetoothOff: Design.Status.stop
        }
    }
}
