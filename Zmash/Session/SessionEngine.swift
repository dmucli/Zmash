import Foundation
import Observation
import ZmashKit

/// Owns a live ride: countdown → wait for first pedal stroke → riding ⇄ paused → finished.
///
/// It ticks on every trainer frame (so it keeps working while backgrounded, when timers are suspended)
/// and at 10 Hz while in the foreground for smooth numbers.
@MainActor @Observable
final class SessionEngine {
    enum Phase: Equatable {
        case countdown(Int)
        case waitingForPedal
        case riding
        case paused(auto: Bool)
        case finished
    }

    let id = UUID()
    let plan: SessionPlan

    private(set) var phase: Phase = .countdown(3) {
        didSet { if oldValue != phase { Diagnostics.log("ride", "phase \(phase)") } }
    }
    private(set) var controls: RideControls
    private(set) var elapsed: Double = 0
    private(set) var speedKph: Double = 0
    private(set) var powerW: Int?
    private(set) var cadenceRpm: Int?
    private(set) var heartRateBpm: Int?
    /// Unsmoothed power, for faces that show both instant and 3 s.
    private(set) var instantPowerW: Int?
    /// Pedal phase, 3 s power, trends and magic-moment events for the faces.
    private(set) var telemetry: FaceTelemetry
    private(set) var terrainGrade: Double = 0
    /// Planned duration reached; waiting for "finish" or "keep riding".
    private(set) var timedDone = false
    private(set) var keepRiding = false
    private(set) var trainerLost = false
    private(set) var startedAt = Date.now

    var kcal: Double { model.kcal }
    var distanceM: Double { model.distanceM }
    var elevationGainM: Double { model.elevationGainM }
    var remaining: Double? {
        guard let planned = plan.plannedSeconds, !keepRiding else { return nil }
        return max(0, planned - elapsed)
    }
    var isPaused: Bool { if case .paused = phase { true } else { false } }
    var hasProfile: Bool { profile != nil }

    @ObservationIgnored var onFinish: ((FinishedRide) -> Void)?
    /// Ended before the clock started: nothing to save.
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onToggleTheme: (() -> Void)?
    /// D-pad left/right: cycle ride faces (+1 / −1).
    @ObservationIgnored var onCycleFace: ((Int) -> Void)?

    @ObservationIgnored private let hub: DeviceHub
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var model: SpeedModel
    @ObservationIgnored private var profile: TerrainProfile?
    @ObservationIgnored private var freeBlocks = 1
    @ObservationIgnored private var latest: TrainerMetrics?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var pedalSince: Date?
    @ObservationIgnored private var idleSince: Date?
    @ObservationIgnored private var lostSince: Date?
    @ObservationIgnored private var power: RollingAverage
    @ObservationIgnored private var gradeFilter = LowPass(tau: 1)
    @ObservationIgnored private var samples: [RideSample] = []
    @ObservationIgnored private var nextSampleSecond = 0
    @ObservationIgnored private var lastAutosave = Date.distantPast
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let autoPauseDelay: TimeInterval = 5
    static let staleAfter: TimeInterval = 3
    static let lostTrainerPauseAfter: TimeInterval = 60

    init(plan: SessionPlan, hub: DeviceHub, prefs: Preferences = .shared) {
        self.plan = plan
        self.hub = hub
        self.prefs = prefs
        self.model = SpeedModel(rider: prefs.rider)
        self.profile = plan.profile()
        self.controls = RideControls(gears: GearSet(count: prefs.gearCount), mode: plan.terrainMode)
        self.power = RollingAverage(window: Double(max(prefs.wattsWindow, 0)))
        let imperial = prefs.units == .imperial
        self.telemetry = FaceTelemetry(ftp: Double(prefs.ftp), unitMeters: imperial ? 1609.344 : 1000,
                                       unitName: imperial ? "Mile" : "Kilometre")
    }

    // MARK: Lifecycle

    func start() {
        hub.onCommand = { [weak self] in self?.handle($0) }
        hub.onMetrics = { [weak self] in self?.ingest($0) }
        pushResistance(dt: 0)
        loop = Task { @MainActor [weak self] in
            for n in [3, 2, 1] {
                self?.phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            // Already pedalling during the countdown: start right away.
            if (self.latestFresh?.cadenceRpm ?? 0) > 0 { self.beginRiding() } else { self.phase = .waitingForPedal }
            while !Task.isCancelled, self.phase != .finished {
                self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Ends the ride and hands the result to `onFinish`.
    func finish() {
        guard phase != .finished else { return }
        tick()
        phase = .finished
        teardown()
        onFinish?(finishedRide)
    }

    /// Leaves without a result (e.g. user backs out before the clock started).
    func cancel() {
        phase = .finished
        teardown()
        RideStore.discard(id: id)
    }

    func continueAfterDone() {
        timedDone = false
        keepRiding = true
    }

    private func teardown() {
        loop?.cancel()
        hub.onCommand = nil
        hub.onMetrics = nil
    }

    var clockStarted: Bool {
        switch phase {
        case .riding, .paused, .finished: true
        case .countdown, .waitingForPedal: false
        }
    }

    var finishedRide: FinishedRide {
        let summary = SessionSummary.from(samples: samples, activeSeconds: Int(elapsed), distanceM: model.distanceM,
                                          elevationGainM: model.elevationGainM, kcal: model.kcal)
        return FinishedRide(id: id, startedAt: startedAt, endedAt: .now, plan: plan, summary: summary, samples: samples)
    }

    func autosaveNow() {
        guard clockStarted, phase != .finished else { return }
        let r = finishedRide
        RideStore.autosave(id: id, startedAt: startedAt, plan: plan, summary: r.summary, samples: r.samples)
        lastAutosave = .now
    }

    // MARK: Input

    func handle(_ command: RideCommand) {
        guard phase != .finished else { return }
        switch command {
        case .shiftUp, .shiftDown, .gradeUp, .gradeDown:
            let outcome = controls.apply(command)
            let isShift = command == .shiftUp || command == .shiftDown
            if outcome == .atLimit || (isShift && prefs.hapticsOnShift) {
                hub.ride.buzz(double: outcome == .atLimit)
            }
            pushResistance(dt: 0)
        case .pauseToggle:
            switch phase {
            case .riding:
                phase = .paused(auto: false)
                hub.ride.buzz(double: false)
            case .paused:
                resume()
                hub.ride.buzz(double: false)
            default:
                break
            }
        case .endSession:
            hub.ride.buzz(double: false)
            if clockStarted { finish() } else { cancel(); onCancel?() }
        case .toggleTheme:
            onToggleTheme?()
        case .nextFace:
            onCycleFace?(1)
        case .previousFace:
            onCycleFace?(-1)
        }
    }

    private func ingest(_ metrics: TrainerMetrics) {
        latest = metrics
        power.add(Double(metrics.powerW), at: metrics.timestamp.timeIntervalSinceReferenceDate)
        tick()
    }

    // MARK: Tick

    private var latestFresh: TrainerMetrics? {
        guard let latest, Date.now.timeIntervalSince(latest.timestamp) < Self.staleAfter else { return nil }
        return latest
    }

    private func tick(now: Date = .now) {
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        guard dt >= 0 else { return }

        let fresh = latestFresh
        let watts = Double(fresh?.powerW ?? 0)
        let cadence = fresh?.cadenceRpm ?? 0
        let pedalling = cadence > 0 || watts > 0
        let t = now.timeIntervalSinceReferenceDate

        cadenceRpm = fresh.map { Int($0.cadenceRpm.rounded()) }
        heartRateBpm = hub.heartRateBpm
        instantPowerW = fresh?.powerW
        if prefs.wattsWindow == 0 {
            powerW = fresh?.powerW
        } else if fresh != nil {
            powerW = power.average(at: t).map { Int($0.rounded()) }
        } else {
            powerW = nil
        }

        // Trainer dropout: keep going with zero power; auto-pause after a minute.
        trainerLost = !hub.isDemo && hub.trainer.link != .ready
        if trainerLost {
            lostSince = lostSince ?? now
        } else {
            lostSince = nil
        }

        switch phase {
        case .countdown, .finished:
            break

        case .waitingForPedal:
            if pedalling {
                pedalSince = pedalSince ?? now
                if now.timeIntervalSince(pedalSince!) >= 1 { beginRiding() }
            } else {
                pedalSince = nil
            }

        case .riding:
            let step = min(dt, SpeedModel.maxStep)
            elapsed += step
            extendFreeRideProfileIfNeeded()
            terrainGrade = controls.grade(autoProfile: profile?.grade(at: elapsed) ?? 0)
            model.step(powerW: watts, gradePercent: terrainGrade, dt: step)
            speedKph = model.speedKph
            recordSamples(watts: Int(watts), cadence: Int(cadence))
            telemetry.update(t: elapsed, dt: step, speedKph: speedKph, powerW: watts, cadenceRpm: cadence,
                             gradePercent: terrainGrade, gear: controls.gear, distanceM: model.distanceM, moving: true)
            checkAutoPause(pedalling: pedalling, now: now)
            if let lostSince, now.timeIntervalSince(lostSince) > Self.lostTrainerPauseAfter { phase = .paused(auto: true) }
            if let planned = plan.plannedSeconds, elapsed >= planned, !keepRiding, !timedDone {
                timedDone = true
                hub.ride.buzz(double: true)
            }
            if now.timeIntervalSince(lastAutosave) >= 10 { autosaveNow() }

        case .paused(let auto):
            if auto, pedalling, !trainerLost { resume() }
        }
        if phase != .riding {
            telemetry.update(t: elapsed, dt: 0, speedKph: speedKph, powerW: watts, cadenceRpm: cadence,
                             gradePercent: terrainGrade, gear: controls.gear, distanceM: model.distanceM, moving: false)
        }

        pushResistance(dt: dt)
    }

    private func beginRiding() {
        startedAt = .now
        phase = .riding
        lastTick = .now
        hub.ride.buzz(double: false)
    }

    private func resume() {
        idleSince = nil
        phase = .riding
    }

    /// Auto-pause after 5 s without pedalling — but not while coasting downhill.
    private func checkAutoPause(pedalling: Bool, now: Date) {
        guard prefs.autoPause else { return }
        if pedalling {
            idleSince = nil
            return
        }
        idleSince = idleSince ?? now
        let coasting = terrainGrade < -1 && speedKph > 5
        if !coasting, now.timeIntervalSince(idleSince!) >= Self.autoPauseDelay {
            phase = .paused(auto: true)
        }
    }

    private func recordSamples(watts: Int, cadence: Int) {
        while Int(elapsed) >= nextSampleSecond {
            samples.append(RideSample(t: nextSampleSecond, powerW: watts, cadenceRpm: cadence,
                                      speedKph: (speedKph * 10).rounded() / 10, gradePercent: terrainGrade,
                                      gear: controls.gear, heartRateBpm: heartRateBpm))
            nextSampleSecond += 1
        }
    }

    private func extendFreeRideProfileIfNeeded() {
        guard plan.plannedSeconds == nil, var p = profile, elapsed > p.duration - 300 else { return }
        p.append(TerrainGenerator.block(index: freeBlocks, type: plan.terrainType, effort: plan.effort, seed: plan.seed))
        freeBlocks += 1
        profile = p
    }

    // MARK: Resistance

    private func pushResistance(dt: Double) {
        let grade = clockStarted ? terrainGrade : controls.grade(autoProfile: profile?.grade(at: 0) ?? 0)
        let trainer = hub.trainer
        if trainer.handlesGearing {
            trainer.apply(gradePercent: grade, gearRatio: controls.gearRatio)
            return
        }
        let fresh = latestFresh
        // ERG fallback: ask for the power this gear needs at this cadence on this grade.
        if prefs.ergShifting {
            let cadence = fresh?.cadenceRpm ?? 0
            guard cadence >= EffectiveGrade.minCadence else { return }
            let v = cadence / 60 * controls.gearRatio * Gears.wheelCircumferenceM
            trainer.applyTargetPower(Int(prefs.rider.steadyPower(speedMps: v, gradePercent: grade).rounded()))
            return
        }
        let effective = EffectiveGrade.compute(
            cadenceRpm: fresh?.cadenceRpm ?? 0, gearRatio: controls.gearRatio, gradePercent: grade,
            trainerSpeedMps: fresh?.trainerSpeedKph.map { $0 / 3.6 }, rider: prefs.rider)
        // A shift (dt = 0) jumps; otherwise ease towards the target so it never feels jerky.
        let smoothed = dt == 0 ? effective : gradeFilter.update(effective, dt: dt)
        if dt == 0 { _ = gradeFilter.update(effective, dt: 10) }
        trainer.apply(gradePercent: smoothed, gearRatio: controls.gearRatio)
    }

    // MARK: Display helpers

    /// 0…1 through a timed ride; free rides run their "day" over 90 minutes.
    var progress: Double {
        min(0.999, elapsed / (plan.plannedSeconds ?? 5400))
    }

    /// 61 normalised elevations for the faces: the next 5 minutes of auto terrain,
    /// or (manual grade) the last 5 minutes ridden.
    var faceProfile: [Double] {
        let speed = max(speedKph / 3.6, 5)
        if hasProfile {
            let h = FaceProfile.elevations(grades: upcomingGrades, stepSeconds: 10, speedMps: speed)
            return FaceProfile.resample(FaceProfile.normalized(h), count: 61)
        }
        var grades = samples.suffix(300).map(\.gradePercent)
        if grades.count < 2 { grades = [terrainGrade, terrainGrade] }
        let h = FaceProfile.elevations(grades: grades, stepSeconds: 1, speedMps: speed)
        return FaceProfile.resample(FaceProfile.normalized(h), count: 61)
    }

    /// Grade over the next five minutes (auto mode), sampled every 10 s, bias included.
    var upcomingGrades: [Double] {
        guard let profile else { return [] }
        let from = elapsed
        return stride(from: from, through: from + 300, by: 10).map {
            min(max(profile.grade(at: $0) + controls.autoBias, RideControls.gradeRange.lowerBound), RideControls.gradeRange.upperBound)
        }
    }
}
