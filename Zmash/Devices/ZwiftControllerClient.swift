import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// One Zwift controller peripheral (Ride, Play side, Play fw2, Click): handshake, keypad → `RideCommand`,
/// battery, firmware, haptics. Several are grouped by `ControllerGroup`.
@MainActor @Observable
final class ZwiftControllerClient: NSObject, RideSource, PeripheralClient {
    let kind: ZwiftController.Kind
    private(set) var link: LinkState = .unpaired
    private(set) var batteryPercent: Int?
    private(set) var firmware: String?
    /// `false` when a Ride's firmware is newer than 1.2.0 (third-party access may be locked).
    var firmwareSupported: Bool? { kind == .ride ? firmware.flatMap(ZwiftRide.isFirmwareSupported) : nil }

    init(kind: ZwiftController.Kind) {
        self.kind = kind
        super.init()
    }
    @ObservationIgnored var onCommand: ((RideCommand) -> Void)?

    @ObservationIgnored private(set) var peripheral: CBPeripheral?
    @ObservationIgnored private var syncRx: CBCharacteristic?
    @ObservationIgnored private var handshakeSent = false
    @ObservationIgnored private var mapper = RideInputMapper(map: .standard)
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastBuzz = Date.distantPast
    @ObservationIgnored private var lastBuzzRequest = Date.distantPast
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private let epoch = ContinuousClock.now

    private var now: Double {
        let d = clock.now - epoch
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    // MARK: PeripheralClient

    func attach(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        link = .searching
    }

    func detach() {
        reset()
        peripheral?.delegate = nil
        peripheral = nil
        link = .unpaired
        batteryPercent = nil
        firmware = nil
    }

    func didConnect() {
        link = .connecting
        peripheral?.discoverServices([CBUUID(string: GATT.Service.zwift),
                                      CBUUID(string: GATT.Service.zwiftLegacy),
                                      CBUUID(string: GATT.Service.deviceInformation)])
    }

    func didDisconnect() {
        reset()
        if peripheral != nil { link = .searching }
    }

    func setBluetoothAvailable(_ available: Bool) {
        if !available { reset(); link = .bluetoothOff }
        else if link == .bluetoothOff { link = peripheral == nil ? .unpaired : .searching }
    }

    private func reset() {
        syncRx = nil
        handshakeSent = false
        mapper = RideInputMapper(map: AppSettings.buttonMap)
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Output

    /// Rapid shifts count as one burst: only the first buzzes. Hitting a gear limit always buzzes (twice).
    static let burstWindow: TimeInterval = 0.8

    func buzz(double: Bool = false) {
        guard let peripheral, let syncRx, link == .ready else { return }
        let now = Date.now
        let inBurst = now.timeIntervalSince(lastBuzzRequest) < Self.burstWindow
        lastBuzzRequest = now
        if inBurst && !double { return }
        guard now.timeIntervalSince(lastBuzz) > 0.25 else { return }
        lastBuzz = now
        peripheral.writeValue(Data(ZwiftRide.haptic), for: syncRx, type: .withoutResponse)
        if double {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, let p = self.peripheral, let rx = self.syncRx else { return }
                p.writeValue(Data(ZwiftRide.haptic), for: rx, type: .withoutResponse)
            }
        }
    }

    // MARK: Input

    private func handle(_ bytes: [UInt8]) {
        if bytes.starts(with: ZwiftRide.rideOn) {
            link = .ready
            return
        }
        if let keypad = try? ZwiftController.keypad(bytes, kind: kind) {
            link = .ready
            mapper.map = AppSettings.buttonMap // picks up edits from Settings immediately
            dispatch(mapper.update(pressed: keypad.pressed, paddles: keypad.paddles, at: now))
            startTickingIfNeeded()
            return
        }
        if case .battery(let percent)? = try? ZwiftRide.decode(bytes) {
            batteryPercent = percent
        }
    }

    private func dispatch(_ commands: [RideCommand]) {
        for command in commands { onCommand?(command) }
    }

    /// Drives hold-repeat and long-press while a relevant button is held.
    private func startTickingIfNeeded() {
        guard mapper.needsTicks, ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.mapper.needsTicks {
                self.dispatch(self.mapper.tick(at: self.now))
                try? await Task.sleep(for: .milliseconds(50))
            }
            self?.ticker = nil
        }
    }
}

extension ZwiftControllerClient: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString {
            case GATT.Characteristic.zwiftSyncRx:
                syncRx = c
            case GATT.Characteristic.zwiftAsync, GATT.Characteristic.zwiftSyncTx:
                peripheral.setNotifyValue(true, for: c)
            case GATT.Characteristic.firmwareRevision:
                peripheral.readValue(for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        guard error == nil, !handshakeSent, let syncRx,
              uuid == GATT.Characteristic.zwiftSyncTx || uuid == GATT.Characteristic.zwiftAsync else { return }
        handshakeSent = true
        peripheral.writeValue(Data(ZwiftRide.rideOn), for: syncRx, type: .withoutResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        switch characteristic.uuid.uuidString {
        case GATT.Characteristic.firmwareRevision:
            firmware = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        default:
            handle(Array(value))
        }
    }
}
