import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// All paired Zwift controllers presented as one `RideSource` (e.g. both sides of a Zwift Play).
@MainActor @Observable
final class ControllerGroup: RideSource {
    private(set) var clients: [ZwiftControllerClient] = []
    private var bluetoothOff = false

    @ObservationIgnored var onCommand: ((RideCommand) -> Void)? {
        didSet { clients.forEach { $0.onCommand = onCommand } }
    }

    var link: LinkState {
        if bluetoothOff { return .bluetoothOff }
        let links = clients.map(\.link)
        if links.isEmpty { return .unpaired }
        if links.contains(.ready) { return .ready }
        if links.contains(.connecting) { return .connecting }
        return .searching
    }

    var batteryPercent: Int? { clients.compactMap(\.batteryPercent).min() }
    var firmware: String? { clients.compactMap(\.firmware).first }
    /// False if any Zwift Ride runs firmware newer than 1.2.0.
    var firmwareSupported: Bool? {
        let values = clients.compactMap(\.firmwareSupported)
        return values.isEmpty ? nil : !values.contains(false)
    }
    var name: String {
        switch clients.count {
        case 0: "Controller"
        case 1: clients[0].kind.displayName
        default: clients.contains { $0.kind == .playLeft || $0.kind == .playRight } ? "Zwift Play" : "Controllers"
        }
    }

    func client(for id: UUID) -> ZwiftControllerClient? { clients.first { $0.peripheral?.identifier == id } }

    func add(_ client: ZwiftControllerClient) {
        client.onCommand = onCommand
        clients.append(client)
    }

    func remove(_ id: UUID) {
        clients.removeAll { client in
            guard client.peripheral?.identifier == id else { return false }
            client.detach()
            return true
        }
    }

    func removeAll() {
        clients.forEach { $0.detach() }
        clients.removeAll()
    }

    func setBluetoothAvailable(_ available: Bool) {
        bluetoothOff = !available
        clients.forEach { $0.setBluetoothAvailable(available) }
    }

    func buzz(double: Bool) {
        clients.filter { $0.link == .ready }.forEach { $0.buzz(double: double) }
    }
}

/// Bluetooth heart-rate strap (standard Heart Rate service).
@MainActor @Observable
final class HeartRateClient: NSObject, PeripheralClient {
    private(set) var link: LinkState = .unpaired
    private(set) var latest: (bpm: Int, at: Date)?
    @ObservationIgnored private(set) var peripheral: CBPeripheral?

    /// Current heart rate, nil after 5 s without data or when the strap reports 0 (no skin contact).
    var bpm: Int? {
        guard let latest, latest.bpm > 0, Date.now.timeIntervalSince(latest.at) < 5 else { return nil }
        return latest.bpm
    }

    func attach(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        link = .searching
    }

    func detach() {
        peripheral?.delegate = nil
        peripheral = nil
        latest = nil
        link = .unpaired
    }

    func didConnect() {
        link = .connecting
        peripheral?.discoverServices([CBUUID(string: HeartRate.service)])
    }

    func didDisconnect() {
        latest = nil
        if peripheral != nil { link = .searching }
    }

    func setBluetoothAvailable(_ available: Bool) {
        if !available { link = .bluetoothOff }
        else if link == .bluetoothOff { link = peripheral == nil ? .unpaired : .searching }
    }
}

extension HeartRateClient: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] where c.uuid.uuidString == HeartRate.measurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value, let bpm = try? HeartRate.parse(Array(value)) else { return }
        latest = (bpm, .now)
        link = .ready
    }
}
