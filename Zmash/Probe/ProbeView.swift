import CoreBluetooth
import SwiftUI
import ZmashKit

enum ProbeSelection: Hashable {
    case checklist
    case log
    case device(UUID)
}

struct ProbeView: View {
    var onClose: (() -> Void)?
    @State private var probe = ProbeCentral()
    @State private var selection: ProbeSelection? = .checklist

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("M0 checklist", systemImage: "checklist").tag(ProbeSelection.checklist)
                    Label("Log", systemImage: "text.alignleft").tag(ProbeSelection.log)
                }

                if !probe.connectedDevices.isEmpty {
                    Section("Connected") {
                        ForEach(probe.connectedDevices) { device in
                            ConnectedRow(device: device).tag(ProbeSelection.device(device.id))
                        }
                    }
                }

                Section {
                    ForEach(probe.visibleDevices) { device in
                        DiscoveredRow(device: device, isConnected: probe.connected[device.id] != nil) {
                            probe.connect(device)
                            selection = .device(device.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby")
                        Spacer()
                        Toggle("All", isOn: $probe.showAllDevices).toggleStyle(.button).font(.caption)
                    }
                }
            }
            .navigationTitle("Zmash probe")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) }
                }
                ToolbarItem {
                    Button(probe.isScanning ? "Stop" : "Scan") {
                        probe.isScanning ? probe.stopScan() : probe.startScan()
                    }
                    .disabled(probe.bluetoothState != .poweredOn)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Bluetooth \(probe.bluetoothState.label)")
                    .font(.caption)
                    .foregroundStyle(probe.bluetoothState == .poweredOn ? Color.secondary : Color.red)
                    .padding(8)
            }
        } detail: {
            switch selection {
            case .checklist, nil:
                ChecklistView(probe: probe)
            case .log:
                LogView(log: probe.log)
            case .device(let id):
                if let device = probe.connected[id] {
                    DeviceDetailView(probe: probe, device: device)
                } else {
                    ContentUnavailableView("Not connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            }
        }
    }
}

private struct DiscoveredRow: View {
    let device: DiscoveredDevice
    let isConnected: Bool
    let connect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.medium))
                Text("\(device.kind.rawValue) · \(device.rssi) dBm")
                    .font(.caption).foregroundStyle(.secondary)
                if !device.manufacturerData.isEmpty {
                    Text(device.manufacturerData.prefix(8).hex).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !isConnected {
                Button("Connect", action: connect).buttonStyle(.bordered)
            }
        }
    }
}

private struct ConnectedRow: View {
    let device: ConnectedDevice

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = device.batteryPercent {
                Text("\(battery) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch device.state {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .red
        }
    }
}

// MARK: - Checklist

struct ChecklistView: View {
    let probe: ProbeCentral

    private var ride: ConnectedDevice? { probe.connectedDevices.first { $0.isRide } }
    private var trainer: ConnectedDevice? { probe.connectedDevices.first { $0.isTrainer } }

    var body: some View {
        List {
            Section("Zwift Ride") {
                Check("Left controller connected", ride?.state == .connected)
                Check("RideOn handshake acknowledged", ride?.rideOnAcknowledged == true)
                Check("Firmware read: \(ride?.firmware ?? "—")", ride?.firmware != nil)
                Check("Battery reported: \(ride?.batteryPercent.map { "\($0) %" } ?? "—")", ride?.batteryPercent != nil)
                let seen = ride?.seenButtons ?? []
                Check("All 16 buttons seen (\(ZwiftRide.Buttons.named.filter { seen.contains($0.button) }.count)/16)",
                      seen == .known)
                Check("Both paddles seen", ride?.seenPaddles.isSuperset(of: [0, 1]) == true)
            }
            Section("KICKR CORE 2 — FTMS") {
                Check("Trainer connected", trainer?.state == .connected)
                Check("Firmware read: \(trainer?.firmware ?? "—")", trainer?.firmware != nil)
                Check("Indoor Bike Data streaming (\(trainer?.bikeDataFrames ?? 0) frames)", (trainer?.bikeDataFrames ?? 0) > 5)
                Check("Power and cadence non-zero while pedalling",
                      (trainer?.bikeData?.powerW ?? 0) > 0 && (trainer?.bikeData?.cadenceRpm ?? 0) > 0)
                Check("Simulation mode advertised", trainer?.features?.supportsIndoorBikeSimulation == true)
                Check("Control granted", trainer?.controlGranted == true)
                Check("Grade change acknowledged", trainer?.gradeAcknowledged != nil)
                Text("Felt on the pedals? Set +8 % then −2 % while riding and confirm by feel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("KICKR CORE 2 — Zwift protocol (path A)") {
                Check("Zwift service present on trainer", trainer?.hasZwiftService == true)
                Check("RideOn acknowledged by trainer", trainer?.zwiftTrainerAck == true)
                Check("Riding data (0x03) received (\(trainer?.zwiftRidingFrames ?? 0) frames)", (trainer?.zwiftRidingFrames ?? 0) > 0)
                Check("Config writes sent (\(trainer?.zwiftConfigWrites ?? 0))", (trainer?.zwiftConfigWrites ?? 0) > 0)
                Text("Go/no-go for path A is by feel: a higher gear ratio should be clearly harder at the same cadence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ShareLink(item: probe.log.exportText, preview: SharePreview("zmash-probe-log.txt")) {
                    Label("Export full log", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Milestone 0")
    }
}

private struct Check: View {
    let title: String
    let ok: Bool
    init(_ title: String, _ ok: Bool) { self.title = title; self.ok = ok }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}
