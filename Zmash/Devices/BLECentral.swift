import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// A device found while scanning to pair.
struct PairingCandidate: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    /// What it could be paired as: an older Wahoo trainer advertises only Cycling Power, like a power meter,
    /// so it's offered in both lists.
    let roles: Set<DeviceRole>
    /// Set for Zwift controllers.
    let controllerKind: ZwiftController.Kind?
}

/// Peripheral-level client driven by `BLECentral` (connection) and CoreBluetooth (GATT).
@MainActor
protocol PeripheralClient: AnyObject {
    var peripheral: CBPeripheral? { get }
    func attach(_ peripheral: CBPeripheral)
    func detach()
    func didConnect()
    func didDisconnect()
    func setBluetoothAvailable(_ available: Bool)
}

/// Owns the single `CBCentralManager`: pairing scan, remembered devices and auto-reconnect.
///
/// Reconnect strategy: `connect` requests never time out on iOS, so a remembered peripheral is kept
/// in a pending connect whenever it's not connected. It reconnects by itself when powered back on.
@MainActor @Observable
final class BLECentral: NSObject {
    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var candidates: [UUID: PairingCandidate] = [:]
    private(set) var isSuspended = false
    /// Bumped on pair/forget so views re-read the registry.
    private(set) var pairingRevision = 0

    let controllers = ControllerGroup()
    let trainer = KickrTrainerClient()
    let heartRate = HeartRateClient()
    let powerMeter = SensorClient(role: .powerMeter)
    let speedCadence = SensorClient(role: .speedCadence)

    @ObservationIgnored private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "zmash.central"])
    }

    /// The client that owns a remembered peripheral, creating controller clients on demand.
    private func client(for peripheral: CBPeripheral) -> PeripheralClient? {
        let id = peripheral.identifier
        switch DeviceRegistry.role(of: id) {
        case .trainer: return trainer
        case .heartRate: return heartRate
        case .powerMeter: return powerMeter
        case .speedCadence: return speedCadence
        case .ride:
            if let existing = controllers.client(for: id) { return existing }
            let kind = ControllerKinds.kind(for: id) ?? .ride
            let client = ZwiftControllerClient(kind: kind)
            client.attach(peripheral)
            controllers.add(client)
            return client
        case nil: return nil
        }
    }

    // MARK: Pairing

    func startPairingScan() {
        guard state == .poweredOn else { return }
        candidates.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func pair(_ candidate: PairingCandidate, as role: DeviceRole) {
        stopScan()
        Diagnostics.log("ble", "pair \(role.rawValue) \(candidate.name) kind=\(candidate.controllerKind?.rawValue ?? "-")")
        // A device serves one role: pairing it as something else takes it out of its old one.
        for other in DeviceRole.allCases where other != role && DeviceRegistry.ids(for: other).contains(candidate.id) {
            disconnect(candidate.id)
            DeviceRegistry.set(DeviceRegistry.ids(for: other).filter { $0 != candidate.id }, for: other)
        }
        var ids = DeviceRegistry.ids(for: role)
        if role == .ride, let kind = candidate.controllerKind {
            ControllerKinds.set(kind, for: candidate.id)
            // The two sides of a Play pair together; any other controller replaces what's there.
            let pairsWithOthers = kind == .playLeft || kind == .playRight
            let keep = ids.filter { id in
                guard pairsWithOthers, let other = ControllerKinds.kind(for: id) else { return false }
                return (other == .playLeft || other == .playRight) && other != kind
            }
            for id in ids where !keep.contains(id) { disconnect(id) }
            ids = keep + [candidate.id]
        } else {
            ids.forEach(disconnect)
            ids = [candidate.id]
        }
        DeviceRegistry.set(Array(ids.suffix(role.maxDevices)), for: role)
        pairingRevision += 1
        connectRemembered(role)
    }

    func forget(_ role: DeviceRole) {
        DeviceRegistry.ids(for: role).forEach(disconnect)
        DeviceRegistry.set([], for: role)
        pairingRevision += 1
    }

    private func disconnect(_ id: UUID) {
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first { central.cancelPeripheralConnection(p) }
        switch DeviceRegistry.role(of: id) {
        case .ride: controllers.remove(id)
        case .trainer: trainer.detach()
        case .heartRate: heartRate.detach()
        case .powerMeter: powerMeter.detach()
        case .speedCadence: speedCadence.detach()
        case nil: break
        }
    }

    // MARK: Suspend (the M0 probe needs the devices to itself; long background idle saves batteries)

    func suspend() {
        isSuspended = true
        stopScan()
        for role in DeviceRole.allCases {
            for id in DeviceRegistry.ids(for: role) {
                if let p = central.retrievePeripherals(withIdentifiers: [id]).first { central.cancelPeripheralConnection(p) }
            }
        }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        DeviceRole.allCases.forEach(connectRemembered)
    }

    // MARK: Connection

    private func connectRemembered(_ role: DeviceRole) {
        guard state == .poweredOn, !isSuspended else { return }
        let ids = DeviceRegistry.ids(for: role)
        for peripheral in central.retrievePeripherals(withIdentifiers: ids) {
            guard let client = client(for: peripheral) else { continue }
            if client.peripheral?.identifier != peripheral.identifier { client.attach(peripheral) }
            if peripheral.state == .connected {
                client.didConnect()
            } else if peripheral.state != .connecting {
                central.connect(peripheral)
            }
        }
    }
}

/// Remembers which kind of Zwift controller each paired peripheral is (from its advertisement at pairing time).
enum ControllerKinds {
    static func kind(for id: UUID) -> ZwiftController.Kind? {
        UserDefaults.standard.string(forKey: "controller.kind.\(id.uuidString)").flatMap(ZwiftController.Kind.init)
    }

    static func set(_ kind: ZwiftController.Kind, for id: UUID) {
        UserDefaults.standard.set(kind.rawValue, forKey: "controller.kind.\(id.uuidString)")
    }
}

extension BLECentral: @preconcurrency CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            client(for: peripheral)?.attach(peripheral)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        Diagnostics.log("ble", "central state \(central.state.rawValue)")
        let on = central.state == .poweredOn
        controllers.setBluetoothAvailable(on)
        trainer.setBluetoothAvailable(on)
        heartRate.setBluetoothAvailable(on)
        powerMeter.setBluetoothAvailable(on)
        speedCadence.setBluetoothAvailable(on)
        if on {
            DeviceRole.allCases.forEach(connectRemembered)
        } else {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map(Array.init) ?? []
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name

        var roles: Set<DeviceRole> = []
        var kind: ZwiftController.Kind?
        let company = manufacturer.count >= 3 ? UInt16(manufacturer[0]) | UInt16(manufacturer[1]) << 8 : nil
        if company == ZwiftRide.manufacturerID, let k = ZwiftController.Kind(deviceType: manufacturer[2]) {
            roles = [.ride]
            kind = k
        } else {
            if DeviceKind.classify(name: name, services: services, manufacturerData: manufacturer) == .trainer {
                roles.insert(.trainer)
            }
            // Cycling Power alone could be a power meter or an older trainer; a trainer's control service rules it out.
            if services.contains(GATT.Service.cyclingPower), !services.contains(GATT.Service.fitnessMachine),
               !services.contains(GATT.Service.tacxFEC) {
                roles.insert(.powerMeter)
            }
            if services.contains(CSC.service) { roles.insert(.speedCadence) }
            if services.contains(HeartRate.service) { roles.insert(.heartRate) }
        }
        guard !roles.isEmpty else { return }
        let role = roles.contains(.ride) ? DeviceRole.ride : roles.first!

        if var existing = candidates[peripheral.identifier] {
            existing.rssi = RSSI.intValue
            if let name { existing.name = name }
            candidates[peripheral.identifier] = existing
        } else {
            candidates[peripheral.identifier] = PairingCandidate(
                id: peripheral.identifier, peripheral: peripheral,
                name: kind?.displayName ?? name ?? role.title, rssi: RSSI.intValue, roles: roles, controllerKind: kind)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Diagnostics.log("ble", "connected \(peripheral.name ?? peripheral.identifier.uuidString)")
        client(for: peripheral)?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let role = DeviceRegistry.role(of: peripheral.identifier) else { return }
        Diagnostics.log("ble", "failed to connect \(peripheral.name ?? "?"): \(error?.localizedDescription ?? "-")")
        client(for: peripheral)?.didDisconnect()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.connectRemembered(role)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let role = DeviceRegistry.role(of: peripheral.identifier) else { return }
        Diagnostics.log("ble", "disconnected \(peripheral.name ?? "?"): \(error?.localizedDescription ?? "-")")
        client(for: peripheral)?.didDisconnect()
        // Re-arm a pending connect: it completes whenever the device comes back.
        connectRemembered(role)
    }
}
