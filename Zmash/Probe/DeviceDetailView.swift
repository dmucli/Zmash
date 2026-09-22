import CoreBluetooth
import SwiftUI
import ZmashKit

struct DeviceDetailView: View {
    let probe: ProbeCentral
    let device: ConnectedDevice

    var body: some View {
        List {
            Section {
                LabeledContent("State", value: stateText)
                ForEach(device.deviceInformation.sorted(by: { $0.key < $1.key }), id: \.key) { uuid, value in
                    LabeledContent(GATT.name(of: uuid) ?? uuid, value: value)
                }
                if let battery = device.batteryPercent { LabeledContent("Battery", value: "\(battery) %") }
                HStack {
                    Button("Disconnect") { probe.disconnect(device) }
                    Button("Forget", role: .destructive) { probe.forget(device) }
                }
                .buttonStyle(.bordered)
            }

            if device.isRide { RidePanel(probe: probe, device: device) }
            if device.hasFTMS { FTMSPanel(probe: probe, device: device) }
            if device.hasCyclingPower {
                Section("Cycling Power") {
                    LabeledContent("Power", value: device.cyclingPowerW.map { "\($0) W" } ?? "—")
                    LabeledContent("Cadence", value: device.cyclingCadence.map { String(format: "%.0f rpm", $0) } ?? "—")
                }
            }
            if device.isTrainer && device.hasZwiftService { ZwiftTrainerPanel(probe: probe, device: device) }

            Section("Characteristics") {
                ForEach(device.info) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(GATT.name(of: c.uuid) ?? c.uuid).font(.callout.weight(.medium))
                            Spacer()
                            Text(c.properties.label).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Text("\(GATT.name(of: c.serviceUUID) ?? c.serviceUUID) · \(c.updates) updates\(c.notifying ? " · subscribed" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                        if !c.lastValue.isEmpty {
                            Text(c.lastValue.hex).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle(device.name)
    }

    private var stateText: String {
        switch device.state {
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnected(let reason): "disconnected" + (reason.map { " (\($0))" } ?? "")
        }
    }
}

// MARK: - Ride

private struct RidePanel: View {
    let probe: ProbeCentral
    let device: ConnectedDevice

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Section {
            LabeledContent("Handshake", value: device.rideOnAcknowledged ? "acknowledged" : device.rideHandshakeSent ? "sent" : "pending")
            LabeledContent("Keypad frames", value: "\(device.keypadFrames)")
            LabeledContent("Last press", value: device.lastButtonEvent.isEmpty ? "—" : device.lastButtonEvent)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ZwiftRide.Buttons.named, id: \.name) { item in
                    let pressed = device.pressed.contains(item.button)
                    let seen = device.seenButtons.contains(item.button)
                    Text(item.name)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(pressed ? Color.accentColor : seen ? Color.green.opacity(0.18) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(pressed ? Color.white : Color.primary)
                }
            }
            .padding(.vertical, 4)

            ForEach([0, 1], id: \.self) { location in
                let value = device.paddles[location] ?? 0
                LabeledContent(location == 0 ? "Left paddle" : "Right paddle") {
                    HStack {
                        ProgressView(value: Double(abs(value)), total: 100).frame(width: 160)
                        Text("\(value)").font(.body.monospacedDigit()).frame(width: 44, alignment: .trailing)
                    }
                }
            }

            HStack {
                Button("Send RideOn") { probe.sendRideOn(device) }
                Button("Vibrate") { probe.vibrate(device) }
            }
            .buttonStyle(.bordered)
        } header: {
            Text("Zwift Ride")
        } footer: {
            Text("Press every button once on both controllers. Seen buttons stay green. Turn on the left controller first, then the right.")
        }
    }
}

// MARK: - FTMS

private struct FTMSPanel: View {
    let probe: ProbeCentral
    let device: ConnectedDevice
    @State private var grade = 0.0
    @State private var autoSend = false

    var body: some View {
        Section {
            let d = device.bikeData
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 4) {
                GridRow {
                    Metric(value: d?.powerW.map { "\($0)" } ?? "—", unit: "w")
                    Metric(value: d?.cadenceRpm.map { String(format: "%.0f", $0) } ?? "—", unit: "rpm")
                    Metric(value: d?.speedKph.map { String(format: "%.1f", $0) } ?? "—", unit: "km/h (trainer)")
                }
            }
            .padding(.vertical, 6)

            LabeledContent("Frames", value: "\(device.bikeDataFrames)")
            LabeledContent("Sim mode supported", value: device.features.map { $0.supportsIndoorBikeSimulation ? "yes" : "no" } ?? "—")
            if let r = device.inclinationRange {
                LabeledContent("Inclination range", value: "\(r.min)…\(r.max) % (step \(r.step))")
            }
            LabeledContent("Control", value: device.controlGranted.map { $0 ? "granted" : "not granted" } ?? "not requested")
            LabeledContent("Last response", value: device.lastControlResponse.isEmpty ? "—" : device.lastControlResponse)
            LabeledContent("Status", value: device.lastStatus.isEmpty ? "—" : device.lastStatus)

            HStack {
                Button("Request control") { probe.requestControl(device) }
                Button("Start") { probe.start(device) }
                Button("Stop") { probe.stop(device) }
                Button("Reset") { probe.reset(device) }
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading) {
                HStack {
                    Text(String(format: "Grade %+.1f %%", grade)).font(.headline.monospacedDigit())
                    Spacer()
                    Text(device.gradeAcknowledged.map { String(format: "acknowledged %+.1f %%", $0) } ?? "not acknowledged")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Slider(value: $grade, in: -10...16, step: 0.5) { editing in
                    if !editing, autoSend { probe.setGrade(grade, on: device) }
                }
                HStack {
                    ForEach([-5.0, 0, 4, 8, 12], id: \.self) { preset in
                        Button(String(format: "%+.0f", preset)) {
                            grade = preset
                            probe.setGrade(preset, on: device)
                        }
                    }
                    Spacer()
                    Toggle("Send on release", isOn: $autoSend).fixedSize()
                    Button("Send") { probe.setGrade(grade, on: device) }.buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("FTMS")
        } footer: {
            Text("Order: Request control → Start → set a grade. While pedalling ~80 rpm, +8 % should feel clearly harder than 0 %.")
        }
    }
}

// MARK: - Zwift trainer protocol

private struct ZwiftTrainerPanel: View {
    let probe: ProbeCentral
    let device: ConnectedDevice
    @State private var grade = 0.0
    @State private var gearRatio = 2.4
    @State private var riderKg = 75.0

    var body: some View {
        Section {
            let d = device.zwiftRidingData
            Grid(alignment: .leading, horizontalSpacing: 32) {
                GridRow {
                    Metric(value: d.map { "\($0.powerW)" } ?? "—", unit: "w")
                    Metric(value: d.map { "\($0.cadenceRpm)" } ?? "—", unit: "rpm")
                    Metric(value: d.map { String(format: "%.1f", $0.speedKph) } ?? "—", unit: "km/h (virtual)")
                }
            }
            .padding(.vertical, 6)

            LabeledContent("Handshake", value: device.zwiftTrainerAck ? "acknowledged" : device.zwiftTrainerHandshakeSent ? "sent" : "not sent")
            LabeledContent("Riding frames", value: "\(device.zwiftRidingFrames)")
            if let real = d?.realGearRatio { LabeledContent("Trainer real gear ratio", value: String(format: "%.3f", real)) }

            Button("Send RideOn to trainer") { probe.sendZwiftTrainerHandshake(device) }.buttonStyle(.bordered)

            VStack(alignment: .leading) {
                Text(String(format: "Gear ratio %.2f", gearRatio)).font(.headline.monospacedDigit())
                Slider(value: $gearRatio, in: 0.75...5.49, step: 0.05)
                Text(String(format: "Grade %+.1f %%", grade)).font(.headline.monospacedDigit())
                Slider(value: $grade, in: -10...16, step: 0.5)
                Stepper(String(format: "Rider %.0f kg", riderKg), value: $riderKg, in: 40...150, step: 1)
                HStack {
                    ForEach([1.0, 2.4, 4.0, 5.49], id: \.self) { ratio in
                        Button(String(format: "%.2f", ratio)) {
                            gearRatio = ratio
                            probe.sendZwiftTrainerConfig(grade: grade, gearRatio: ratio, riderKg: riderKg, on: device)
                        }
                    }
                    Spacer()
                    Button("Send config") {
                        probe.sendZwiftTrainerConfig(grade: grade, gearRatio: gearRatio, riderKg: riderKg, on: device)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Zwift trainer protocol (path A)")
        } footer: {
            Text("Experimental. Send RideOn, then a config. If it works, gear 5.49 should feel far harder than 1.00 at the same cadence, and virtual speed should change with the ratio.")
        }
    }
}

private struct Metric: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension CBCharacteristicProperties {
    var label: String {
        var parts: [String] = []
        if contains(.read) { parts.append("R") }
        if contains(.write) { parts.append("W") }
        if contains(.writeWithoutResponse) { parts.append("Wn") }
        if contains(.notify) { parts.append("N") }
        if contains(.indicate) { parts.append("I") }
        return parts.joined(separator: " ")
    }
}
