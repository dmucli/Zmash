import Foundation
import Observation
import ZmashKit

/// The app's single entry point to hardware. Picks live or demo devices and funnels every
/// rider command (Ride buttons, touch, keyboard) through `onCommand`.
@MainActor @Observable
final class DeviceHub {
    private(set) var isDemo: Bool
    private(set) var ride: any RideSource
    private(set) var trainer: any TrainerSource
    /// Live Bluetooth stack; nil in demo mode.
    private(set) var ble: BLECentral?
    private(set) var lastCommand: (command: RideCommand, at: Date)?

    @ObservationIgnored var onCommand: ((RideCommand) -> Void)?
    @ObservationIgnored var onMetrics: ((TrainerMetrics) -> Void)?
    /// How the power meter reads against the trainer, for ERG targets the pedals agree with.
    @ObservationIgnored private var match = PowerMatch()

    init(demo: Bool? = nil) {
        let demo = demo ?? AppSettings.demoMode
        isDemo = demo
        if demo {
            ride = DemoRide()
            trainer = DemoTrainer()
        } else {
            let ble = BLECentral()
            self.ble = ble
            ride = ble.controllers
            trainer = Self.trainer(for: ble)
        }
        wire()
    }

    /// The smart trainer, or a basic one worked out from wheel speed.
    private static func trainer(for ble: BLECentral) -> any TrainerSource {
        guard let curve = AppSettings.basicTrainer else { return ble.trainer }
        return VirtualTrainer(curve: curve, sensors: [ble.speedCadence, ble.powerMeter])
    }

    /// Call after changing the trainer type in Devices.
    func refreshTrainer() {
        guard let ble else { return }
        trainer.onMetrics = nil
        trainer = Self.trainer(for: ble)
        match = PowerMatch()
        wire()
    }

    func setDemo(_ demo: Bool) {
        guard demo != isDemo else { return }
        AppSettings.demoMode = demo
        ble?.suspend()
        self.ble = nil
        isDemo = demo
        if demo {
            ride = DemoRide()
            trainer = DemoTrainer()
        } else {
            let ble = BLECentral()
            self.ble = ble
            ride = ble.controllers
            trainer = Self.trainer(for: ble)
        }
        wire()
    }

    /// Heart rate: a paired strap wins over what the trainer reports.
    var heartRateBpm: Int? { ble?.heartRate.bpm ?? trainer.heartRateBpm }

    /// Commands from touch or keyboard enter here, exactly like Ride buttons.
    func send(_ command: RideCommand) {
        lastCommand = (command, .now)
        onCommand?(command)
    }

    /// The power meter's power, when it's the chosen source and reading.
    private var meterPower: Int? {
        AppSettings.powerSource == .powerMeter ? ble?.powerMeter.freshPower : nil
    }

    /// An ERG target as the trainer should hold it: corrected so the power meter reads `watts`, when it's the source.
    func trainerTarget(_ watts: Int) -> Int {
        meterPower == nil ? watts : match.trainerTarget(for: watts)
    }

    /// The trainer's reading with the other devices folded in: power from the power meter when that's the source
    /// (a basic trainer's estimate always gives way to it), cadence from a sensor when the trainer has none.
    private func mixed(_ m: TrainerMetrics) -> TrainerMetrics {
        var m = m
        if let ble {
            let meter = ble.powerMeter.freshPower
            if let meter, AppSettings.basicTrainer == nil { match.add(powerMeterW: Double(meter), trainerW: Double(m.powerW)) }
            if let meter, AppSettings.powerSource == .powerMeter || AppSettings.basicTrainer != nil { m.powerW = meter }
            if m.cadenceRpm == 0, let c = ble.speedCadence.freshCadence ?? ble.powerMeter.freshCadence { m.cadenceRpm = c }
        }
        return m.sanitized
    }

    private func wire() {
        ride.onCommand = { [weak self] command in self?.send(command) }
        trainer.onMetrics = { [weak self] metrics in
            guard let self else { return }
            self.onMetrics?(self.mixed(metrics))
        }
    }
}
