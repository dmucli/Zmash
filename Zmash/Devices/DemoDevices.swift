import Foundation
import Observation
import ZmashKit

/// Synthetic trainer for the Simulator and UI work: a scripted rider whose power follows gear and grade.
@MainActor @Observable
final class DemoTrainer: TrainerSource {
    private(set) var link: LinkState = .ready
    private(set) var metrics: TrainerMetrics? {
        didSet { if let metrics { onMetrics?(metrics) } }
    }
    let activeProtocol: TrainerProtocol? = nil
    let statusNote: String? = "Demo trainer"
    let handlesGearing = true
    let supportsERG = true
    @ObservationIgnored var onMetrics: ((TrainerMetrics) -> Void)?
    /// Simulated heart rate that follows effort with a lag.
    private(set) var heartRateBpm: Int?
    @ObservationIgnored private var hr = 72.0

    var targetCadence: Double {
        get { rider.targetCadence }
        set { rider.targetCadence = newValue }
    }

    var pedalling: Bool {
        get { rider.pedalling }
        set { rider.pedalling = newValue }
    }

    /// Simulates the trainer dropping out, to exercise reconnect UI.
    var connected = true {
        didSet {
            link = connected ? .ready : .searching
            if !connected { metrics = nil }
        }
    }

    @ObservationIgnored private var rider = DemoRider(seed: UInt64(Date.now.timeIntervalSince1970))
    @ObservationIgnored private var grade = 0.0
    @ObservationIgnored private var ergTarget: Int?
    @ObservationIgnored private var gearRatio = Gears.ratio(for: Gears.startGear)
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return } // stops once the demo trainer is released
                self.step()
            }
        }
    }

    func apply(gradePercent: Double, gearRatio: Double) {
        grade = gradePercent
        self.gearRatio = gearRatio
        ergTarget = nil
    }

    func applyTargetPower(_ watts: Int) {
        ergTarget = watts
    }

    private func step() {
        guard connected else { return }
        var s = rider.step(dt: 0.25, gearRatio: gearRatio, gradePercent: grade)
        // ERG: the demo rider holds the target (with a little wobble) whatever the gear.
        if let ergTarget, s.cadenceRpm > 0 { s.powerW = max(0, ergTarget + Int.random(in: -6...6)) }
        hr += ((70 + Double(s.powerW) * 0.42) - hr) * 0.25 / 20
        heartRateBpm = Int(hr.rounded())
        metrics = TrainerMetrics(powerW: s.powerW, cadenceRpm: s.cadenceRpm, trainerSpeedKph: s.speedKph)
    }
}

/// Demo controller: always "connected"; commands come from on-screen and keyboard input.
@MainActor @Observable
final class DemoRide: RideSource {
    let link: LinkState = .ready
    let batteryPercent: Int? = 87
    let firmware: String? = "demo"
    @ObservationIgnored var onCommand: ((RideCommand) -> Void)?
    func buzz(double: Bool) {}
}
