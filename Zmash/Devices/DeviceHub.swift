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
            trainer = ble.trainer
        }
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
            trainer = ble.trainer
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

    private func wire() {
        ride.onCommand = { [weak self] command in self?.send(command) }
        trainer.onMetrics = { [weak self] metrics in self?.onMetrics?(metrics) }
    }
}
