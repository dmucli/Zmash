import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// Milestone-0 hardware probe: scans, connects, subscribes to everything, logs every byte,
/// and decodes the Zwift Ride, FTMS and Zwift trainer protocols.
@MainActor @Observable
final class ProbeCentral: NSObject {
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var discovered: [UUID: DiscoveredDevice] = [:]
    private(set) var connected: [UUID: ConnectedDevice] = [:]
    var showAllDevices = false
    let log = ProbeLog()

    @ObservationIgnored private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var visibleDevices: [DiscoveredDevice] {
        discovered.values
            .filter { showAllDevices || $0.kind != .other }
            .sorted { ($0.kind == .other ? 1 : 0, -$0.rssi) < ($1.kind == .other ? 1 : 0, -$1.rssi) }
    }

    var connectedDevices: [ConnectedDevice] {
        connected.values.sorted { $0.name < $1.name }
    }

    // MARK: Scanning & connection

    func startScan() {
        guard bluetoothState == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        event("central", "scan started")
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        event("central", "scan stopped")
    }

    func connect(_ device: DiscoveredDevice) {
        let session = ConnectedDevice(peripheral: device.peripheral, name: device.name, kind: device.kind)
        connected[device.id] = session
        device.peripheral.delegate = self
        central.connect(device.peripheral)
        event(device.name, "connecting (\(device.kind.rawValue))")
    }

    func disconnect(_ device: ConnectedDevice) {
        central.cancelPeripheralConnection(device.peripheral)
    }

    func forget(_ device: ConnectedDevice) {
        central.cancelPeripheralConnection(device.peripheral)
        connected[device.id] = nil
    }

    // MARK: Writes

    func write(_ bytes: [UInt8], to uuid: String, on device: ConnectedDevice, note: String? = nil) {
        guard let characteristic = device.characteristics[uuid] else {
            event(device.name, "cannot write: \(GATT.name(of: uuid) ?? uuid) not found")
            return
        }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        device.peripheral.writeValue(Data(bytes), for: characteristic, type: type)
        log.add(LogEntry(date: .now, device: device.name, direction: .tx, characteristic: uuid, bytes: bytes, decoded: note))
    }

    // Zwift Ride

    func sendRideOn(_ device: ConnectedDevice) {
        write(ZwiftRide.rideOn, to: GATT.Characteristic.zwiftSyncRx, on: device, note: "RideOn handshake")
        device.rideHandshakeSent = true
    }

    func vibrate(_ device: ConnectedDevice) {
        write(ZwiftRide.haptic, to: GATT.Characteristic.zwiftSyncRx, on: device, note: "haptic")
    }

    // FTMS

    func requestControl(_ device: ConnectedDevice) {
        write(FTMS.ControlCommand.requestControl, to: GATT.Characteristic.fitnessMachineControlPoint, on: device, note: "request control")
    }

    func start(_ device: ConnectedDevice) {
        write(FTMS.ControlCommand.start, to: GATT.Characteristic.fitnessMachineControlPoint, on: device, note: "start/resume")
    }

    func stop(_ device: ConnectedDevice) {
        write(FTMS.ControlCommand.stop, to: GATT.Characteristic.fitnessMachineControlPoint, on: device, note: "stop")
    }

    func reset(_ device: ConnectedDevice) {
        write(FTMS.ControlCommand.reset, to: GATT.Characteristic.fitnessMachineControlPoint, on: device, note: "reset")
    }

    func setGrade(_ grade: Double, on device: ConnectedDevice) {
        device.pendingGrade = grade
        write(FTMS.ControlCommand.simulation(gradePercent: grade), to: GATT.Characteristic.fitnessMachineControlPoint,
              on: device, note: String(format: "sim grade %+.1f %%", grade))
    }

    // Zwift trainer protocol

    func sendZwiftTrainerHandshake(_ device: ConnectedDevice) {
        write(ZwiftRide.rideOn, to: GATT.Characteristic.zwiftSyncRx, on: device, note: "RideOn handshake (trainer)")
        device.zwiftTrainerHandshakeSent = true
    }

    func sendZwiftTrainerConfig(grade: Double, gearRatio: Double, riderKg: Double, on device: ConnectedDevice) {
        let bytes = ZwiftTrainer.configSet(gradePercent: grade, gearRatio: gearRatio, bikeKg: 9, riderKg: riderKg)
        write(bytes, to: GATT.Characteristic.zwiftSyncRx, on: device,
              note: String(format: "zwift config grade %+.1f %% gear %.2f rider %.0f kg", grade, gearRatio, riderKg))
        device.zwiftConfigWrites += 1
    }

    // MARK: Logging

    private func event(_ device: String, _ text: String) {
        log.add(LogEntry(date: .now, device: device, direction: .event, characteristic: nil, bytes: [], decoded: text))
    }

    private func rx(_ device: ConnectedDevice, _ uuid: String, _ bytes: [UInt8], _ decoded: String?, streaming: Bool) {
        log.add(LogEntry(date: .now, device: device.name, direction: .rx, characteristic: uuid, bytes: bytes, decoded: decoded),
                streaming: streaming)
    }

    // MARK: Decoding

    private func handle(_ bytes: [UInt8], from uuid: String, on device: ConnectedDevice) {
        if let index = device.info.firstIndex(where: { $0.uuid == uuid }) {
            device.info[index].lastValue = bytes
            device.info[index].updates += 1
        }

        do {
            switch uuid {
            case GATT.Characteristic.zwiftAsync, GATT.Characteristic.zwiftSyncTx:
                if device.isTrainer {
                    try handleZwiftTrainer(bytes, uuid: uuid, device: device)
                } else {
                    try handleRide(bytes, uuid: uuid, device: device)
                }

            case GATT.Characteristic.indoorBikeData:
                let data = try FTMS.parseIndoorBikeData(bytes)
                device.bikeDataFrames += 1
                // Frames with the "More Data" bit carry no speed; merge rather than overwrite.
                var merged = device.bikeData ?? FTMS.IndoorBikeData()
                if let v = data.speedKph { merged.speedKph = v }
                if let v = data.cadenceRpm { merged.cadenceRpm = v }
                if let v = data.powerW { merged.powerW = v }
                if let v = data.heartRateBpm { merged.heartRateBpm = v }
                if let v = data.totalDistanceM { merged.totalDistanceM = v }
                if let v = data.resistanceLevel { merged.resistanceLevel = v }
                device.bikeData = merged
                rx(device, uuid, bytes, describe(data), streaming: true)

            case GATT.Characteristic.fitnessMachineControlPoint:
                let response = try FTMS.parseControlResponse(bytes)
                let op = FTMS.ControlOpcode(rawValue: response.requestOpcode).map { "\($0)" } ?? String(format: "0x%02x", response.requestOpcode)
                let result = response.result?.label ?? String(format: "0x%02x", response.rawResult)
                device.lastControlResponse = "\(op): \(result)"
                if response.requestOpcode == FTMS.ControlOpcode.requestControl.rawValue {
                    device.controlGranted = response.result == .success
                }
                if response.requestOpcode == FTMS.ControlOpcode.setIndoorBikeSimulation.rawValue, response.result == .success {
                    device.gradeAcknowledged = device.pendingGrade
                }
                if response.result == .controlNotPermitted { device.controlGranted = false }
                rx(device, uuid, bytes, device.lastControlResponse, streaming: false)

            case GATT.Characteristic.fitnessMachineStatus:
                device.lastStatus = FTMS.describeStatus(bytes)
                if bytes.first == 0xFF { device.controlGranted = false }
                rx(device, uuid, bytes, device.lastStatus, streaming: false)

            case GATT.Characteristic.fitnessMachineFeature:
                let f = try FTMS.parseFeatures(bytes)
                device.features = f
                rx(device, uuid, bytes, "sim \(f.supportsIndoorBikeSimulation) · power target \(f.supportsPowerTarget) · resistance \(f.supportsResistanceTarget)", streaming: false)

            case GATT.Characteristic.supportedInclinationRange:
                let range = try FTMS.parseInclinationRange(bytes)
                device.inclinationRange = range
                rx(device, uuid, bytes, "incline \(range.min)…\(range.max) step \(range.step)", streaming: false)

            case GATT.Characteristic.cyclingPowerMeasurement:
                let m = try CyclingPower.parse(bytes)
                device.cyclingPowerW = m.powerW
                if let revs = m.crankRevolutions, let t = m.crankEventTime,
                   let cadence = device.crankCadence.update(revolutions: revs, eventTime: t) {
                    device.cyclingCadence = cadence
                }
                rx(device, uuid, bytes, "\(m.powerW) W", streaming: true)

            case GATT.Characteristic.batteryLevel:
                device.batteryPercent = bytes.first.map(Int.init)
                rx(device, uuid, bytes, "battery \(device.batteryPercent ?? 0) %", streaming: false)

            case let dis where GATT.Characteristic.stringValued.contains(dis):
                let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
                device.deviceInformation[uuid] = text
                rx(device, uuid, bytes, text, streaming: false)

            default:
                rx(device, uuid, bytes, nil, streaming: false)
            }
        } catch {
            rx(device, uuid, bytes, "decode error: \(error)", streaming: false)
        }
    }

    private func handleRide(_ bytes: [UInt8], uuid: String, device: ConnectedDevice) throws {
        let message = try ZwiftRide.decode(bytes)
        switch message {
        case .rideOn:
            device.rideOnAcknowledged = true
            rx(device, uuid, bytes, "RideOn acknowledged", streaming: false)
        case .keypad(let keypad):
            device.keypadFrames += 1
            device.pressed = keypad.pressed
            device.seenButtons.formUnion(keypad.pressed)
            var paddleNote: [String] = []
            for paddle in keypad.paddles {
                device.paddles[paddle.location] = paddle.value
                if abs(paddle.value) >= ZwiftRide.paddleThreshold {
                    device.seenPaddles.insert(paddle.location)
                    paddleNote.append("paddle \(paddle.location)=\(paddle.value)")
                }
            }
            let (down, up) = device.edges.update(keypad.pressed)
            var parts: [String] = []
            if !down.isEmpty { parts.append("down: " + down.names.joined(separator: ", ")) }
            if !up.isEmpty { parts.append("up: " + up.names.joined(separator: ", ")) }
            parts += paddleNote
            if !down.isEmpty { device.lastButtonEvent = down.names.joined(separator: ", ") }
            rx(device, uuid, bytes, parts.isEmpty ? "keypad (no change)" : parts.joined(separator: " · "),
               streaming: parts.isEmpty)
        case .battery(let percent):
            device.batteryPercent = percent
            rx(device, uuid, bytes, "battery \(percent) %", streaming: true)
        case .empty:
            rx(device, uuid, bytes, "keep-alive", streaming: true)
        case .unknown(let opcode, _):
            rx(device, uuid, bytes, String(format: "opcode 0x%02x", opcode), streaming: false)
        }
    }

    private func handleZwiftTrainer(_ bytes: [UInt8], uuid: String, device: ConnectedDevice) throws {
        if bytes.starts(with: ZwiftRide.rideOn) {
            device.zwiftTrainerAck = true
            rx(device, uuid, bytes, "RideOn acknowledged (trainer)", streaming: false)
        } else if bytes.first == ZwiftTrainer.Opcode.ridingData.rawValue {
            let data = try ZwiftTrainer.decodeRidingData(bytes)
            device.zwiftRidingData = data
            device.zwiftRidingFrames += 1
            rx(device, uuid, bytes, String(format: "%d W · %d rpm · %.2f km/h", data.powerW, data.cadenceRpm, data.speedKph)
               + (data.realGearRatio.map { String(format: " · real gear %.3f", $0) } ?? ""), streaming: true)
        } else {
            let op = bytes.first.map { String(format: "opcode 0x%02x", $0) } ?? "empty"
            let fields = (try? ProtoWire.fields(Array(bytes.dropFirst())))?
                .map { "f\($0.number)=\($0.uint.map(String.init) ?? $0.bytes?.hex ?? "?")" }
                .joined(separator: " ") ?? ""
            rx(device, uuid, bytes, "\(op) \(fields)", streaming: false)
        }
    }

    private func describe(_ d: FTMS.IndoorBikeData) -> String {
        var parts: [String] = []
        if let v = d.speedKph { parts.append(String(format: "%.2f km/h", v)) }
        if let v = d.cadenceRpm { parts.append(String(format: "%.1f rpm", v)) }
        if let v = d.powerW { parts.append("\(v) W") }
        if let v = d.resistanceLevel { parts.append("res \(v)") }
        if let v = d.heartRateBpm { parts.append("\(v) bpm") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - CBCentralManagerDelegate

extension ProbeCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        event("central", "state \(central.state.label)")
        if central.state == .poweredOn, !isScanning { startScan() }
        if central.state != .poweredOn { isScanning = false }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map(Array.init) ?? []
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let rssi = RSSI.intValue == 127 ? -127 : RSSI.intValue

        if let existing = discovered[peripheral.identifier] {
            existing.rssi = rssi
            existing.lastSeen = .now
            if let name { existing.name = name }
            if !services.isEmpty { existing.services = services }
            if !manufacturer.isEmpty { existing.manufacturerData = manufacturer }
            let kind = DeviceKind.classify(name: existing.name, services: existing.services, manufacturerData: existing.manufacturerData)
            if kind != .other { existing.kind = kind }
            return
        }

        let kind = DeviceKind.classify(name: name, services: services, manufacturerData: manufacturer)
        let device = DiscoveredDevice(peripheral: peripheral, name: name ?? "Unnamed", rssi: rssi, kind: kind,
                                      services: services, manufacturerData: manufacturer)
        discovered[peripheral.identifier] = device
        if kind != .other {
            event(device.name, "discovered \(kind.rawValue) rssi \(rssi) services [\(services.joined(separator: ", "))] mfr \(manufacturer.hex)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let device = connected[peripheral.identifier] else { return }
        device.state = .connected
        event(device.name, "connected, discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        device.state = .disconnected(error?.localizedDescription)
        event(device.name, "failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        device.state = .disconnected(error?.localizedDescription)
        device.rideHandshakeSent = false
        device.rideOnAcknowledged = false
        device.controlGranted = nil
        event(device.name, "disconnected \(error?.localizedDescription ?? "")")
    }
}

// MARK: - CBPeripheralDelegate

extension ProbeCentral: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        let services = peripheral.services ?? []
        event(device.name, "services: " + services.map { GATT.name(of: $0.uuid.uuidString) ?? $0.uuid.uuidString }.joined(separator: ", "))
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString
            device.characteristics[uuid] = characteristic
            if !device.info.contains(where: { $0.uuid == uuid }) {
                device.info.append(.init(uuid: uuid, serviceUUID: service.uuid.uuidString, properties: characteristic.properties))
            }
            if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        let uuid = characteristic.uuid.uuidString
        if let index = device.info.firstIndex(where: { $0.uuid == uuid }) {
            device.info[index].notifying = characteristic.isNotifying
        }
        if let error {
            event(device.name, "subscribe \(GATT.name(of: uuid) ?? uuid) failed: \(error.localizedDescription)")
            return
        }
        // Handshake with the Ride once its response channel is live.
        if device.isRide, !device.rideHandshakeSent,
           uuid == GATT.Characteristic.zwiftSyncTx || uuid == GATT.Characteristic.zwiftAsync,
           device.characteristics[GATT.Characteristic.zwiftSyncRx] != nil {
            sendRideOn(device)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let device = connected[peripheral.identifier] else { return }
        let uuid = characteristic.uuid.uuidString
        if let error {
            event(device.name, "read \(GATT.name(of: uuid) ?? uuid) failed: \(error.localizedDescription)")
            return
        }
        handle(Array(characteristic.value ?? Data()), from: uuid, on: device)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let device = connected[peripheral.identifier], let error else { return }
        let uuid = characteristic.uuid.uuidString
        event(device.name, "write \(GATT.name(of: uuid) ?? uuid) failed: \(error.localizedDescription)")
    }
}

extension CBManagerState {
    var label: String {
        switch self {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}
