import CoreBluetooth
import Foundation
import Observation
import ZmashKit

/// Any smart trainer (KICKR CORE 2 first): metrics in, grade/gear out.
///
/// Four control paths, chosen from what the trainer offers in the order FTMS > Zwift > Wahoo > Tacx (brief §5.2, D86):
/// - **FTMS**: Request Control → Start → Set Indoor Bike Simulation (grade). One control-point op in flight at a time.
/// - **Zwift protocol**: RideOn handshake → TRAINER_CONFIG_SET with grade + gear ratio. Chosen by preference, or
///   in `.auto` when the trainer answers the handshake and streams riding data within a few seconds.
/// - **Wahoo** (before FTMS): unlock → sim mode (mass, rolling and wind resistance) → grade, or ERG. Power and
///   cadence from the Cycling Power measurement.
/// - **Tacx FE-C** (older Tacx): ANT pages over Bluetooth: user configuration, wind, then track resistance (grade)
///   or target power. Power, cadence and speed from the trainer's pages.
@MainActor @Observable
final class KickrTrainerClient: NSObject, TrainerSource, PeripheralClient {
    enum Control: Equatable {
        case none
        case requested
        case granted
        case denied
    }

    private(set) var link: LinkState = .unpaired
    private(set) var metrics: TrainerMetrics? {
        didSet { if let metrics { onMetrics?(metrics) } }
    }
    private(set) var activeProtocol: TrainerProtocol?
    private(set) var control: Control = .none
    private(set) var features: FTMS.Features?
    private(set) var firmware: String?
    private(set) var statusNote: String?
    @ObservationIgnored var onMetrics: ((TrainerMetrics) -> Void)?
    var handlesGearing: Bool { activeProtocol == .zwift }
    var supportsERG: Bool { activeProtocol != nil && activeProtocol != .zwift }
    /// Heart rate relayed by the trainer (FTMS Indoor Bike Data), if a strap is paired to it.
    private(set) var heartRateBpm: Int?

    /// Spin-down calibration (D99): where it's got to.
    enum Calibration: Equatable {
        case idle, starting
        case speedUp(targetKph: Double?)
        case coast
        case success(String)
        case failed(String)
        case unsupported(String)
    }
    private(set) var calibration: Calibration = .idle
    @ObservationIgnored private var calibrationTimeout: Task<Void, Never>?

    @ObservationIgnored private(set) var peripheral: CBPeripheral?
    @ObservationIgnored private var chars: [String: CBCharacteristic] = [:]

    // Target & throttling
    @ObservationIgnored private var target: (grade: Double, gear: Double) = (0, Gears.ratio(for: Gears.startGear))
    @ObservationIgnored private var lastSent: (grade: Double, gear: Double)?
    @ObservationIgnored private var lastSendTime = Date.distantPast
    @ObservationIgnored private var ergTarget: Int?
    @ObservationIgnored private var lastErgSent: Int?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    static let minSendInterval: TimeInterval = 0.25

    // FTMS control-point queue
    @ObservationIgnored private var cpQueue: [[UInt8]] = []
    @ObservationIgnored private var cpInFlight: [UInt8]?
    @ObservationIgnored private var cpTimeout: Task<Void, Never>?
    @ObservationIgnored private var controlRetry: Task<Void, Never>?

    // Wahoo and Tacx: vendor commands, one at a time (Wahoo answers each; Tacx writes are paced).
    @ObservationIgnored private var vendorQueue: [[UInt8]] = []
    @ObservationIgnored private var vendorInFlight = false
    @ObservationIgnored private var vendorTimeout: Task<Void, Never>?
    /// Wahoo: which mode the trainer is in, so leaving ERG re-sends sim mode.
    @ObservationIgnored private var wahooSimMode = false

    // Zwift protocol negotiation
    @ObservationIgnored private var zwiftHandshakeSent = false
    @ObservationIgnored private var negotiation: Task<Void, Never>?

    // Discovery bookkeeping
    @ObservationIgnored private var pendingServices = 0
    @ObservationIgnored private var awaitingSubscriptions = false
    @ObservationIgnored private var readinessTimeout: Task<Void, Never>?

    @ObservationIgnored private var lastBikeData = Date.distantPast
    @ObservationIgnored private var crank = CrankCadence()
    @ObservationIgnored private var merged = FTMS.IndoorBikeData()

    private var preference: TrainerProtocolPreference { AppSettings.trainerProtocol }

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
        firmware = nil
        features = nil
    }

    func didConnect() {
        link = .connecting
        peripheral?.discoverServices(nil)
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
        chars.removeAll()
        activeProtocol = nil
        control = .none
        metrics = nil
        statusNote = nil
        lastSent = nil
        lastErgSent = nil
        heartRateBpm = nil
        cpQueue.removeAll()
        cpInFlight = nil
        vendorQueue.removeAll()
        vendorInFlight = false
        wahooSimMode = false
        [sendTask, cpTimeout, controlRetry, negotiation, readinessTimeout, vendorTimeout].forEach { $0?.cancel() }
        sendTask = nil
        pendingServices = 0
        awaitingSubscriptions = false
        zwiftHandshakeSent = false
        merged = FTMS.IndoorBikeData()
        crank = CrankCadence()
    }

    // MARK: Target

    func apply(gradePercent: Double, gearRatio: Double) {
        target = (gradePercent, gearRatio)
        ergTarget = nil
        scheduleSend()
    }

    /// ERG fallback: hold a power instead of a grade (FTMS only).
    func applyTargetPower(_ watts: Int) {
        ergTarget = min(max(watts, 0), 1500)
        scheduleSend()
    }

    private func scheduleSend() {
        guard sendTask == nil else { return }
        let wait = max(0, Self.minSendInterval - Date.now.timeIntervalSince(lastSendTime))
        sendTask = Task { @MainActor [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            self.sendTask = nil
            self.sendTarget()
        }
    }

    private func sendTarget(force: Bool = false) {
        guard link == .ready, let active = activeProtocol else { return }
        let t = target
        switch active {
        case .ftms:
            guard control == .granted else { return }
            if let watts = ergTarget {
                if !force, let last = lastErgSent, abs(last - watts) < 3 { return }
                enqueueControl(FTMS.ControlCommand.targetPower(watts))
                lastErgSent = watts
                lastSent = nil
                lastSendTime = .now
                return
            }
            if !force, let last = lastSent, abs(last.grade - t.grade) < 0.1 { return }
            lastErgSent = nil
            enqueueControl(FTMS.ControlCommand.simulation(gradePercent: t.grade))
        case .wahoo, .tacx:
            if let watts = ergTarget {
                if !force, let last = lastErgSent, abs(last - watts) < 3 { return }
                enqueueVendor(active == .wahoo ? WahooTrainer.erg(watts: watts) : TacxFEC.targetPower(watts: watts))
                if active == .wahoo { wahooSimMode = false }
                lastErgSent = watts
                lastSent = nil
                lastSendTime = .now
                return
            }
            if !force, let last = lastSent, abs(last.grade - t.grade) < 0.1 { return }
            if active == .wahoo, !wahooSimMode {
                enqueueVendor(WahooTrainer.simMode(totalKg: AppSettings.riderKg + AppSettings.bikeKg))
                wahooSimMode = true
            }
            lastErgSent = nil
            enqueueVendor(active == .wahoo ? WahooTrainer.grade(percent: t.grade) : TacxFEC.trackResistance(gradePercent: t.grade))
        case .zwift:
            if !force, let last = lastSent, abs(last.grade - t.grade) < 0.1, abs(last.gear - t.gear) < 0.001 { return }
            guard let rx = chars[GATT.Characteristic.zwiftSyncRx], let p = peripheral else { return }
            let bytes = ZwiftTrainer.configSet(gradePercent: t.grade, gearRatio: t.gear,
                                               bikeKg: AppSettings.bikeKg, riderKg: AppSettings.riderKg)
            p.writeValue(Data(bytes), for: rx, type: rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        }
        lastSent = t
        lastSendTime = .now
    }

    // MARK: Calibration

    /// Starts a spin-down: FTMS (Spin Down Control) or Tacx FE-C (calibration request page).
    func startCalibration() {
        guard link == .ready, let active = activeProtocol else { calibration = .unsupported("Connect the trainer first."); return }
        switch active {
        case .ftms:
            calibration = .starting
            if control != .granted { requestControl() }
            enqueueControl(FTMS.ControlCommand.startSpinDown)
        case .tacx:
            calibration = .starting
            enqueueVendor(TacxFEC.spinDownRequest)
        case .wahoo:
            calibration = .unsupported("Older Wahoo trainers calibrate in the Wahoo app (Settings → Spindown).")
            return
        case .zwift:
            calibration = .unsupported("This trainer calibrates itself; nothing to do.")
            return
        }
        Diagnostics.log("trainer", "calibration requested over \(active.name)")
        calibrationTimeout?.cancel()
        calibrationTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard let self, !Task.isCancelled else { return }
            switch self.calibration {
            case .starting, .speedUp, .coast: self.calibration = .failed("No result from the trainer. Try again after a few minutes of riding.")
            default: break
            }
        }
    }

    func resetCalibration() {
        calibrationTimeout?.cancel()
        calibration = .idle
    }

    private func calibrationFinished(success: Bool, detail: String) {
        calibrationTimeout?.cancel()
        calibration = success ? .success(detail) : .failed(detail)
        if success { AppSettings.calibrated() }
        Diagnostics.log("trainer", "calibration \(success ? "done" : "failed"): \(detail)")
    }

    // MARK: Protocol selection

    private func characteristicsReady() {
        let offered = TrainerProtocolChoice.Offered(
            ftms: chars[GATT.Characteristic.fitnessMachineControlPoint] != nil,
            zwift: chars[GATT.Characteristic.zwiftSyncRx] != nil,
            wahoo: chars[GATT.Characteristic.wahooTrainerControl] != nil,
            tacx: chars[GATT.Characteristic.tacxFECWrite] != nil)
        Diagnostics.log("trainer", "offers ftms=\(offered.ftms) zwift=\(offered.zwift) wahoo=\(offered.wahoo) tacx=\(offered.tacx); preference \(preference.rawValue)")

        // Auto tries the Zwift protocol first when it's there, falling back to FTMS if it doesn't answer.
        if preference == .auto, offered.zwift {
            startZwiftNegotiation(fallbackToFTMS: offered.ftms)
            return
        }
        switch TrainerProtocolChoice.choose(offered, preference: preference) {
        case .ftms: useFTMS()
        case .zwift: startZwiftNegotiation(fallbackToFTMS: false)
        case .wahoo: useVendor(.wahoo)
        case .tacx: useVendor(.tacx)
        case nil: statusNote = "No controllable service found"
        }
    }

    /// Wahoo or Tacx: set the trainer up, then send the current target.
    private func useVendor(_ proto: TrainerProtocol) {
        Diagnostics.log("trainer", "using \(proto.name)")
        activeProtocol = proto
        link = .ready
        statusNote = nil
        if proto == .wahoo {
            enqueueVendor(WahooTrainer.unlock)
        } else {
            enqueueVendor(TacxFEC.userConfiguration(riderKg: AppSettings.riderKg, bikeKg: AppSettings.bikeKg))
            enqueueVendor(TacxFEC.windResistance())
        }
        sendTarget(force: true)
    }

    // MARK: Wahoo / Tacx writes

    private var vendorCharacteristic: CBCharacteristic? {
        chars[activeProtocol == .wahoo ? GATT.Characteristic.wahooTrainerControl : GATT.Characteristic.tacxFECWrite]
    }

    private func enqueueVendor(_ bytes: [UInt8]) {
        // Only the latest target matters: replace a queued grade or power instead of piling up.
        let targets: Set<[UInt8]> = [[WahooTrainer.Opcode.setErgMode.rawValue], [WahooTrainer.Opcode.setSimGrade.rawValue]]
        let kind = { (b: [UInt8]) -> UInt8? in
            if self.activeProtocol == .tacx { return b.count > 4 ? b[4] : nil }
            return b.first
        }
        let isTarget = { (b: [UInt8]) -> Bool in
            guard let k = kind(b) else { return false }
            return self.activeProtocol == .tacx
                ? k == TacxFEC.Page.targetPower.rawValue || k == TacxFEC.Page.trackResistance.rawValue
                : targets.contains([k])
        }
        if isTarget(bytes), let i = vendorQueue.firstIndex(where: isTarget) {
            vendorQueue[i] = bytes
        } else {
            vendorQueue.append(bytes)
        }
        pumpVendor()
    }

    private func pumpVendor() {
        guard !vendorInFlight, !vendorQueue.isEmpty, let c = vendorCharacteristic, let p = peripheral else { return }
        let next = vendorQueue.removeFirst()
        let withResponse = !c.properties.contains(.writeWithoutResponse) || activeProtocol == .wahoo
        vendorInFlight = true
        p.writeValue(Data(next), for: c, type: withResponse ? .withResponse : .withoutResponse)
        // With a response, the write callback moves on; without, pace writes (and never wait forever).
        vendorTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(withResponse ? 1500 : 60))
            guard let self, !Task.isCancelled else { return }
            self.vendorInFlight = false
            self.pumpVendor()
        }
    }

    fileprivate func vendorWriteDone(_ uuid: String, error: Error?) {
        guard uuid == GATT.Characteristic.wahooTrainerControl || uuid == GATT.Characteristic.tacxFECWrite else { return }
        if let error { Diagnostics.log("trainer", "\(activeProtocol?.name ?? "vendor") write failed: \(error.localizedDescription)") }
        vendorTimeout?.cancel()
        vendorInFlight = false
        pumpVendor()
    }

    private func useFTMS() {
        Diagnostics.log("trainer", "using FTMS")
        negotiation?.cancel()
        activeProtocol = .ftms
        link = .ready
        requestControl()
    }

    private func startZwiftNegotiation(fallbackToFTMS: Bool) {
        guard let rx = chars[GATT.Characteristic.zwiftSyncRx], let p = peripheral else { return }
        zwiftHandshakeSent = true
        p.writeValue(Data(ZwiftRide.rideOn), for: rx, type: rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        negotiation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.activeProtocol == nil else { return }
            if fallbackToFTMS {
                self.statusNote = "Zwift protocol didn't answer; using FTMS"
                self.useFTMS()
            } else {
                self.statusNote = "Zwift protocol didn't answer"
            }
        }
    }

    private func zwiftConfirmed() {
        guard activeProtocol == nil else { return }
        Diagnostics.log("trainer", "using Zwift protocol")
        negotiation?.cancel()
        activeProtocol = .zwift
        link = .ready
        statusNote = nil
        sendTarget(force: true)
    }

    // MARK: FTMS control point

    private func requestControl() {
        control = .requested
        cpQueue.removeAll()
        enqueueControl(FTMS.ControlCommand.requestControl)
        enqueueControl(FTMS.ControlCommand.start)
    }

    private func enqueueControl(_ bytes: [UInt8]) {
        // Only the latest target matters: replace a queued one instead of piling up.
        let targets: Set<UInt8> = [FTMS.ControlOpcode.setIndoorBikeSimulation.rawValue, FTMS.ControlOpcode.setTargetPower.rawValue]
        if let op = bytes.first, targets.contains(op),
           let i = cpQueue.firstIndex(where: { $0.first.map(targets.contains) == true }) {
            cpQueue[i] = bytes
        } else {
            cpQueue.append(bytes)
        }
        pumpControl()
    }

    private func pumpControl() {
        guard cpInFlight == nil, !cpQueue.isEmpty,
              let cp = chars[GATT.Characteristic.fitnessMachineControlPoint], let p = peripheral else { return }
        let next = cpQueue.removeFirst()
        cpInFlight = next
        p.writeValue(Data(next), for: cp, type: .withResponse)
        cpTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.cpInFlight = nil
            self.pumpControl()
        }
    }

    private func handleControlResponse(_ bytes: [UInt8]) {
        guard let response = try? FTMS.parseControlResponse(bytes) else { return }
        if response.result != .success || response.requestOpcode != FTMS.ControlOpcode.setIndoorBikeSimulation.rawValue {
            Diagnostics.log("trainer", String(format: "control 0x%02x → %@", response.requestOpcode, response.result?.label ?? "\(response.rawResult)"))
        }
        cpTimeout?.cancel()
        cpInFlight = nil

        if response.requestOpcode == FTMS.ControlOpcode.spinDownControl.rawValue {
            if response.result == .success {
                calibration = .speedUp(targetKph: FTMS.spinDownTargets(bytes)?.highKph)
            } else {
                calibrationFinished(success: false, detail: "The trainer won't spin down over FTMS (\(response.result?.label ?? "code \(response.rawResult)")).")
            }
        }
        switch (FTMS.ControlOpcode(rawValue: response.requestOpcode), response.result) {
        case (.requestControl, .success):
            control = .granted
            statusNote = nil
        case (.startOrResume, .success):
            sendTarget(force: true)
        case (_, .controlNotPermitted):
            control = .denied
            statusNote = "Trainer is controlled by another app"
            cpQueue.removeAll()
            retryControl()
        case (.setIndoorBikeSimulation, .some(let result)) where result != .success:
            statusNote = "Grade rejected: \(result.label)"
        default:
            break
        }
        pumpControl()
    }

    private func retryControl() {
        controlRetry?.cancel()
        controlRetry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.control != .granted, self.activeProtocol == .ftms else { return }
            self.requestControl()
        }
    }

    // MARK: Metrics

    private func handleBikeData(_ bytes: [UInt8]) {
        guard let d = try? FTMS.parseIndoorBikeData(bytes) else { return }
        // "More Data" frames split fields across notifications; merge them.
        if let v = d.speedKph { merged.speedKph = v }
        if let v = d.cadenceRpm { merged.cadenceRpm = v }
        if let v = d.powerW { merged.powerW = v }
        if let v = d.heartRateBpm { heartRateBpm = v > 0 ? v : nil }
        lastBikeData = .now
        guard activeProtocol != .zwift else { return }
        metrics = TrainerMetrics(powerW: merged.powerW ?? 0, cadenceRpm: merged.cadenceRpm ?? 0,
                                 trainerSpeedKph: merged.speedKph).sanitized
    }

    private func handleCyclingPower(_ bytes: [UInt8]) {
        guard let m = try? CyclingPower.parse(bytes) else { return }
        // Fallback only: Indoor Bike Data wins when it's flowing.
        guard Date.now.timeIntervalSince(lastBikeData) > 3, activeProtocol != .zwift else { return }
        var cadence = metrics?.cadenceRpm ?? 0
        if let revs = m.crankRevolutions, let t = m.crankEventTime, let c = crank.update(revolutions: revs, eventTime: t) {
            cadence = c
        }
        metrics = TrainerMetrics(powerW: m.powerW, cadenceRpm: cadence, trainerSpeedKph: nil).sanitized
    }

    private func handleTacx(_ bytes: [UInt8]) {
        guard let (_, r) = TacxFEC.parse(bytes) else { return }
        switch r.calibration {
        case .inProgress(let target, let ok)?:
            calibration = ok == true ? .coast : .speedUp(targetKph: target)
        case .result(let success, let ms)?:
            calibrationFinished(success: success, detail: success ? (ms.map { String(format: "Spin-down took %.1f s.", Double($0) / 1000) } ?? "Calibrated.")
                                                              : "The spin-down didn't take. Try again.")
        case nil:
            break
        }
        if let v = r.speedKph { merged.speedKph = v }
        if let v = r.cadenceRpm { merged.cadenceRpm = Double(v) }
        if let v = r.powerW { merged.powerW = v }
        if let v = r.heartRateBpm { heartRateBpm = v }
        // Counts as the trainer's own data: the Cycling Power fallback stays quiet while pages flow.
        lastBikeData = .now
        guard activeProtocol != .zwift else { return }
        metrics = TrainerMetrics(powerW: merged.powerW ?? 0, cadenceRpm: merged.cadenceRpm ?? 0,
                                 trainerSpeedKph: merged.speedKph).sanitized
    }

    private func handleWahooResponse(_ bytes: [UInt8]) {
        guard bytes.count >= 3, bytes[0] == 0x01, bytes[2] != 0x01 else { return }
        Diagnostics.log("trainer", "Wahoo command \(bytes.hex) not accepted")
    }

    private func handleZwift(_ bytes: [UInt8]) {
        if bytes.starts(with: ZwiftRide.rideOn) { return } // ack; riding data confirms the path
        guard bytes.first == ZwiftTrainer.Opcode.ridingData.rawValue,
              let d = try? ZwiftTrainer.decodeRidingData(bytes) else { return }
        if zwiftHandshakeSent { zwiftConfirmed() }
        guard activeProtocol == .zwift else { return }
        metrics = TrainerMetrics(powerW: d.powerW, cadenceRpm: Double(d.cadenceRpm), trainerSpeedKph: d.speedKph).sanitized
    }
}

extension KickrTrainerClient: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let wanted: Set<String> = [GATT.Service.fitnessMachine, GATT.Service.cyclingPower, GATT.Service.zwift,
                                   GATT.Service.zwiftLegacy, GATT.Service.tacxFEC, GATT.Service.deviceInformation]
        let services = (peripheral.services ?? []).filter { wanted.contains($0.uuid.uuidString) }
        pendingServices = services.count
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            let uuid = c.uuid.uuidString
            chars[uuid] = c
            switch uuid {
            case GATT.Characteristic.indoorBikeData, GATT.Characteristic.fitnessMachineControlPoint,
                 GATT.Characteristic.fitnessMachineStatus, GATT.Characteristic.cyclingPowerMeasurement,
                 GATT.Characteristic.zwiftAsync, GATT.Characteristic.zwiftSyncTx,
                 GATT.Characteristic.wahooTrainerControl, GATT.Characteristic.tacxFECNotify:
                peripheral.setNotifyValue(true, for: c)
            case GATT.Characteristic.fitnessMachineFeature, GATT.Characteristic.firmwareRevision:
                peripheral.readValue(for: c)
            default:
                break
            }
        }
        pendingServices -= 1
        guard pendingServices == 0 else { return }
        awaitingSubscriptions = true
        // If a subscription never confirms, decide anyway with what we have.
        readinessTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.awaitingSubscriptions else { return }
            self.awaitingSubscriptions = false
            self.characteristicsReady()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Wait for the control point (FTMS) or sync TX (Zwift) to be live before choosing a path.
        let uuid = characteristic.uuid.uuidString
        guard awaitingSubscriptions, error == nil,
              uuid == GATT.Characteristic.fitnessMachineControlPoint || uuid == GATT.Characteristic.zwiftSyncTx
              || uuid == GATT.Characteristic.zwiftAsync else { return }
        let cpLive = chars[GATT.Characteristic.fitnessMachineControlPoint]?.isNotifying ?? true
        let zwiftLive = (chars[GATT.Characteristic.zwiftAsync]?.isNotifying ?? true)
        guard cpLive, zwiftLive else { return }
        awaitingSubscriptions = false
        readinessTimeout?.cancel()
        characteristicsReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let bytes = Array(value)
        switch characteristic.uuid.uuidString {
        case GATT.Characteristic.indoorBikeData: handleBikeData(bytes)
        case GATT.Characteristic.cyclingPowerMeasurement: handleCyclingPower(bytes)
        case GATT.Characteristic.fitnessMachineControlPoint: handleControlResponse(bytes)
        case GATT.Characteristic.fitnessMachineStatus:
            if let status = FTMS.spinDownStatus(bytes) {
                switch status {
                case .requested: if case .speedUp = calibration {} else { calibration = .speedUp(targetKph: nil) }
                case .stopPedalling: calibration = .coast
                case .success: calibrationFinished(success: true, detail: "Calibrated.")
                case .error: calibrationFinished(success: false, detail: "Stopped pedalling too early or too late. Try again.")
                }
            }
            if bytes.first == 0xFF, activeProtocol == .ftms {
                control = .none
                requestControl()
            }
        case GATT.Characteristic.fitnessMachineFeature:
            features = try? FTMS.parseFeatures(bytes)
            Diagnostics.log("trainer", "features sim=\(features?.supportsIndoorBikeSimulation ?? false) erg=\(features?.supportsPowerTarget ?? false)")
        case GATT.Characteristic.firmwareRevision:
            firmware = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
            Diagnostics.log("trainer", "firmware \(firmware ?? "-")")
        case GATT.Characteristic.zwiftAsync, GATT.Characteristic.zwiftSyncTx: handleZwift(bytes)
        case GATT.Characteristic.tacxFECNotify: handleTacx(bytes)
        case GATT.Characteristic.wahooTrainerControl: handleWahooResponse(bytes)
        default: break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        vendorWriteDone(characteristic.uuid.uuidString, error: error)
    }
}
