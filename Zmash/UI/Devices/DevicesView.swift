import SwiftUI
import ZmashKit

/// Pair, forget and inspect controllers, the trainer and a heart-rate strap. Also hosts advanced device settings.
struct DevicesView: View {
    let hub: DeviceHub
    @Environment(Preferences.self) private var prefs
    @State private var pairing: DeviceRole?

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
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } else {
                    DeviceRow(title: "Controller", link: hub.ride.link, detail: hub.isDemo ? "demo" : nil)
                }
                if let ble = hub.ble { pairButtons(.ride, ble: ble) }
            } header: {
                Text("Controller")
            } footer: {
                Text("Zwift Ride, Zwift Play (pair both sides) or Zwift Click. Close Zwift and Zwift Companion first. For the Ride, turn on the left controller, then the right.")
            }

            Section("Trainer") {
                DeviceRow(title: "Trainer", link: hub.trainer.link, detail: trainerDetail)
                if let note = hub.trainer.statusNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if let ble = hub.ble { pairButtons(.trainer, ble: ble) }
            }

            Section {
                DeviceRow(title: "Heart rate", link: hub.isDemo ? .ready : hub.ble?.heartRate.link ?? .unpaired,
                          detail: hub.heartRateBpm.map { "\($0) bpm" + (hub.isDemo ? " · demo" : "") })
                if let ble = hub.ble { pairButtons(.heartRate, ble: ble) }
            } header: {
                Text("Heart rate")
            } footer: {
                Text("Optional. Any Bluetooth heart-rate strap.")
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
                Text("Advanced")
            } footer: {
                Text("Protocol changes apply on the next connection. ERG holds the power your gear needs instead of simulating a grade: use it only if shifting feels wrong in FTMS.")
            }
        }
        .navigationTitle("Devices")
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

    private var trainerDetail: String? {
        if hub.isDemo { return "demo" }
        guard let p = hub.trainer.activeProtocol else { return nil }
        if p == .zwift { return "Zwift protocol" }
        return prefs.ergShifting ? "\(p.name) · ERG" : p.name
    }
}

private struct DeviceRow: View {
    let title: String
    let link: LinkState
    let detail: String?

    var body: some View {
        HStack {
            Circle().fill(link.color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text(link.label).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}

private struct PairingSheet: View {
    let ble: BLECentral
    let role: DeviceRole
    @Environment(\.dismiss) private var dismiss

    private var candidates: [PairingCandidate] {
        ble.candidates.values.filter { $0.role == role }.sorted { $0.rssi > $1.rssi }
    }

    private var hint: String {
        switch role {
        case .ride: "Looking for controllers… (Zwift Ride: the left controller)"
        case .trainer: "Looking for trainers…"
        case .heartRate: "Looking for heart-rate straps… Wear it to wake it up."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(hint).foregroundStyle(.secondary)
                    }
                }
                ForEach(candidates) { candidate in
                    Button {
                        ble.pair(candidate)
                        dismiss()
                    } label: {
                        HStack {
                            Text(candidate.name)
                            Spacer()
                            Text("\(candidate.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        case .ready: .green
        case .connecting, .searching: .orange
        case .unpaired: .secondary
        case .bluetoothOff: .red
        }
    }
}
