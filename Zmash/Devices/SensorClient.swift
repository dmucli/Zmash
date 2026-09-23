import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// A power meter (Cycling Power) or a speed/cadence sensor (CSC): readings only, nothing to control.
/// Each reading carries its time; after 3 s without a new one it no longer counts.
@MainActor @Observable
final class SensorClient: NSObject, PeripheralClient {
    let role: DeviceRole
    private(set) var link: LinkState = .unpaired
    private(set) var power: (watts: Int, at: Date)?
    private(set) var cadence: (rpm: Double, at: Date)?
    private(set) var wheel: (kph: Double, at: Date)?
    @ObservationIgnored private(set) var peripheral: CBPeripheral?
    /// Called on every new reading (drives a basic trainer's metrics).
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private var crank = CrankCadence()
    @ObservationIgnored private var cscWheel = WheelSpeed(ticksPerSecond: 1024)
    @ObservationIgnored private var cpsWheel = WheelSpeed(ticksPerSecond: 2048)

    init(role: DeviceRole) {
        self.role = role
    }

    static let freshFor: TimeInterval = 3

    var freshPower: Int? { power.flatMap { Date.now.timeIntervalSince($0.at) < Self.freshFor ? $0.watts : nil } }
    var freshCadence: Double? { cadence.flatMap { Date.now.timeIntervalSince($0.at) < Self.freshFor ? $0.rpm : nil } }
    var freshWheelKph: Double? { wheel.flatMap { Date.now.timeIntervalSince($0.at) < Self.freshFor ? $0.kph : nil } }

    func attach(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        link = .searching
    }

    func detach() {
        peripheral?.delegate = nil
        peripheral = nil
        clear()
        link = .unpaired
    }

    func didConnect() {
        link = .connecting
        peripheral?.discoverServices([CBUUID(string: GATT.Service.cyclingPower), CBUUID(string: CSC.service)])
    }

    func didDisconnect() {
        clear()
        if peripheral != nil { link = .searching }
    }

    func setBluetoothAvailable(_ available: Bool) {
        if !available { link = .bluetoothOff }
        else if link == .bluetoothOff { link = peripheral == nil ? .unpaired : .searching }
    }

    private func clear() {
        power = nil
        cadence = nil
        wheel = nil
        crank = CrankCadence()
        cscWheel = WheelSpeed(ticksPerSecond: 1024)
        cpsWheel = WheelSpeed(ticksPerSecond: 2048)
    }

    fileprivate func handle(_ uuid: String, _ bytes: [UInt8]) {
        let now = Date.now
        switch uuid {
        case GATT.Characteristic.cyclingPowerMeasurement:
            guard let m = try? CyclingPower.parse(bytes) else { return }
            power = (max(m.powerW, 0), now)
            if let revs = m.crankRevolutions, let t = m.crankEventTime, let c = crank.update(revolutions: revs, eventTime: t) {
                cadence = (c, now)
            }
            if let revs = m.wheelRevolutions, let t = m.wheelEventTime,
               let v = cpsWheel.update(revolutions: revs, eventTime: t, circumferenceM: AppSettings.wheelCircumferenceM) {
                wheel = (v, now)
            }
        case CSC.measurement:
            guard let m = try? CSC.parse(bytes) else { return }
            if let revs = m.crankRevolutions, let t = m.crankEventTime, let c = crank.update(revolutions: revs, eventTime: t) {
                cadence = (c, now)
            }
            if let revs = m.wheelRevolutions, let t = m.wheelEventTime,
               let v = cscWheel.update(revolutions: revs, eventTime: t, circumferenceM: AppSettings.wheelCircumferenceM) {
                wheel = (v, now)
            }
        default:
            return
        }
        link = .ready
        onUpdate?()
    }
}

extension SensorClient: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? []
        where c.uuid.uuidString == GATT.Characteristic.cyclingPowerMeasurement || c.uuid.uuidString == CSC.measurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        handle(characteristic.uuid.uuidString, Array(value))
    }
}

/// A basic (non-smart) trainer: power worked out from wheel speed through its power curve. It can't be steered,
/// so gradient and gears show on screen but aren't felt; the app says so.
@MainActor @Observable
final class VirtualTrainer: TrainerSource {
    let curve: TrainerPowerCurve
    /// Where wheel speed and cadence come from: a speed/cadence sensor first, else a power meter that counts wheel turns.
    private let sensors: [SensorClient]
    private(set) var metrics: TrainerMetrics? {
        didSet { if let metrics { onMetrics?(metrics) } }
    }
    @ObservationIgnored var onMetrics: ((TrainerMetrics) -> Void)?

    init(curve: TrainerPowerCurve, sensors: [SensorClient]) {
        self.curve = curve
        self.sensors = sensors
        // The basic trainer is the sensors' only listener; a new one (after a settings change) takes over.
        for sensor in sensors {
            sensor.onUpdate = { [weak self] in self?.update() }
        }
    }

    var link: LinkState {
        sensors.first(where: { $0.link == .ready })?.link ?? sensors.first(where: { $0.peripheral != nil })?.link ?? .unpaired
    }
    var activeProtocol: TrainerProtocol? { nil }
    var statusNote: String? {
        "Basic trainer: power is worked out from wheel speed (\(curve.name)). Gradient and gears show but can't change the resistance."
    }
    var handlesGearing: Bool { false }

    func apply(gradePercent: Double, gearRatio: Double) {}

    private func update() {
        guard let kph = sensors.lazy.compactMap(\.freshWheelKph).first else { return }
        let cadence = sensors.lazy.compactMap(\.freshCadence).first ?? 0
        metrics = TrainerMetrics(powerW: Int(curve.watts(speedKph: kph).rounded()), cadenceRpm: cadence,
                                 trainerSpeedKph: kph).sanitized
    }
}
