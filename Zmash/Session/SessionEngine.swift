import Foundation
import Observation
import ZmashKit

/// Owns a live ride: wait for the first pedal stroke → riding ⇄ paused → finished (no countdown, D106).
///
/// It ticks on every trainer frame (so it keeps working while backgrounded, when timers are suspended)
/// and at 10 Hz while in the foreground for smooth numbers.
@MainActor @Observable
final class SessionEngine {
    enum Phase: Equatable {
        case waitingForPedal
        case riding
        case paused(auto: Bool)
        case finished
    }

    let id = UUID()
    let plan: SessionPlan
    let workout: Workout?
    let route: Route?
    /// The quickest previous attempt at this route, if there is one.
    let ghost: Ghost?
    /// The road ahead, when it's known (a route, or generated terrain at your pace): climbs and the whole card
    /// for the round 3 faces.
    @ObservationIgnored private(set) var course: RideCourse?
    /// With no known road: the elevation ridden so far, every 100 m, for the course profile.
    @ObservationIgnored private var ridden: [Double] = [0]
    @ObservationIgnored private var altitude = 0.0
    @ObservationIgnored private var lastDistanceM = 0.0

    /// The road for the course profile: the course if it's known, otherwise what has been ridden.
    var road: (route: Route, atM: Double, known: Bool)? {
        if let course { return (course.route, courseAtM, true) }
        guard ridden.count > 1 else { return nil }
        return (Route(id: "ridden", name: "", place: "", elevations: ridden), distanceM, false)
    }
    /// Metres along the course: distance on a route, the clock on generated terrain.
    var courseAtM: Double {
        guard let course else { return 0 }
        return course.timing == nil ? distanceM : course.position(elapsed: elapsed, distanceM: distanceM)
    }

    private(set) var phase: Phase = .waitingForPedal {
        didSet {
            guard oldValue != phase else { return }
            Diagnostics.log("ride", "phase \(phase)")
            // A pause is a stop: the ride picks up again from standstill, not at the speed it paused at.
            if oldValue == .riding, isPaused {
                model.halt()
                speedKph = 0
                pausedAt = .now
            }
            // Back on the bike: the pause goes on the next second's sample, so exports keep the wall clock.
            if phase == .riding, let pausedAt {
                pendingPause += Date.now.timeIntervalSince(pausedAt)
                self.pausedAt = nil
            }
        }
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
    /// Workout intensity (ERG): the shift buttons scale every target by ±5 %.
    private(set) var intensity: Double = 1

    // Mirrored from the speed model each tick, so views observing the engine redraw as they change.
    private(set) var kcal: Double = 0
    private(set) var distanceM: Double = 0
    private(set) var elevationGainM: Double = 0
    var remaining: Double? {
        if let route, !keepRiding {
            // On a route the clock counts down an estimate: distance left at the pace of the last minute.
            let pace = max(paceFilter.value ?? speedKph / 3.6, 2)
            return max(0, (route.distanceM - distanceM) / pace)
        }
        guard let planned = plan.plannedSeconds, !keepRiding else { return nil }
        return max(0, planned - plannedClock)
    }

    var routeRemainingM: Double? { route.map { max(0, $0.distanceM - distanceM) } }
    var altitudeM: Double? { route?.elevation(atDistance: distanceM) }
    /// Metres to the high point, or nil once it's behind.
    var toSummitM: Double? {
        guard let route, route.summitDistanceM > distanceM, route.ascentM > 50 else { return nil }
        return route.summitDistanceM - distanceM
    }

    /// Seconds ahead (+) or behind (−) the ghost, once both are on the route.
    var ghostDelta: Double? {
        guard let ghost, clockStarted, distanceM > 50 else { return nil }
        return ghost.delta(elapsed: elapsed, distanceM: distanceM)
    }
    var isPaused: Bool { if case .paused = phase { true } else { false } }
    var hasProfile: Bool { profile != nil || route != nil }

    /// Where the rider is in the workout (nil without one, or once it's over and they keep riding).
    var workoutPosition: Workout.Position? {
        guard let p = workout?.position(at: elapsed + workoutShift), !p.finished else { return nil }
        return p
    }

    /// Seconds the workout has been moved on (skipped, +) or back (repeated, −) against the ride clock (D151).
    private(set) var workoutShift: Double = 0
    /// A repeated interval starts a new lap even though it's the same step.
    @ObservationIgnored private var lapPending = false
    @ObservationIgnored private var lapStep: Int?

    /// The clock the plan's length is measured on: a workout's own, with skips and repeats in it.
    private var plannedClock: Double { workout == nil ? elapsed : elapsed + workoutShift }

    /// Current workout target in watts (nil on free steps).
    var targetW: Int? { watts(forFraction: workoutPosition?.fraction) }

    func watts(forFraction f: Double?) -> Int? {
        f.map { Int(($0 * Double(prefs.ftp) * intensity).rounded()) }
    }

    /// The trainer holds the workout target itself; not on a gradient step, which rides the slope (D152).
    var ergActive: Bool {
        workout != nil && plan.usesERG && hub.trainer.supportsERG && workoutPosition?.step.grade == nil
    }

    @ObservationIgnored var onFinish: ((FinishedRide) -> Void)?
    /// Ended before the clock started: nothing to save.
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onToggleTheme: (() -> Void)?
    /// D-pad left/right: cycle ride faces (+1 / −1).
    @ObservationIgnored var onCycleFace: ((Int) -> Void)?
    /// Zoom the course profile in (+1) or out (−1).
    @ObservationIgnored var onZoom: ((Int) -> Void)?

    @ObservationIgnored private let hub: DeviceHub
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private var model: SpeedModel
    @ObservationIgnored private var profile: TerrainProfile?
    @ObservationIgnored private var freeBlocks = 1
    @ObservationIgnored private var latest: TrainerMetrics?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var idleSince: Date?
    @ObservationIgnored private var lostSince: Date?
    @ObservationIgnored private var power: RollingAverage
    @ObservationIgnored private var gradeFilter = LowPass(tau: 1)
    /// Speed over about the last minute, for the time left on a route.
    @ObservationIgnored private var paceFilter = LowPass(tau: 30)
    /// Workout gradients ease in over a few seconds rather than stepping.
    @ObservationIgnored private var workoutGradeFilter = LowPass(tau: 3)
    /// Gentle coaching (D97), when it's on; its latest message and when (ride seconds) it was said.
    @ObservationIgnored private var coach: Coach?
    @ObservationIgnored private var lastHardStep: Int?
    private(set) var coachMessage: (text: String, at: Double)?
    /// Ride sounds (D98), when they're on.
    @ObservationIgnored private var sound: RideSound?
    @ObservationIgnored private var cues = SoundCues()
    @ObservationIgnored private var soundGear: Int?
    @ObservationIgnored private var soundEventAt = -1.0
    @ObservationIgnored private var samples: [RideSample] = []
    @ObservationIgnored private var nextSampleSecond = 0
    /// When the current pause began, and pause time not yet put on a sample.
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pendingPause = 0.0
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
        self.workout = plan.workout
        let route = plan.route
        self.route = route
        let previous = route.flatMap { RideStore.ghost(routeID: $0.id, distanceM: $0.distanceM) }
        self.ghost = previous?.ghost
        self.course = Self.makeCourse(route: route, profile: plan.profile(), prefs: prefs)
        // Workouts and routes both supply the gradient; the D-pad biases it, as in auto terrain.
        self.controls = RideControls(gears: GearSet(count: prefs.gearCount),
                                     mode: plan.workout == nil && plan.route == nil ? plan.terrainMode : .auto)
        self.power = RollingAverage(window: Double(max(prefs.wattsWindow, 0)))
        let imperial = prefs.units == .imperial
        self.telemetry = FaceTelemetry(ftp: Double(prefs.ftp), unitMeters: imperial ? 1609.344 : 1000,
                                       unitName: imperial ? "Mile" : "Kilometre")
        if prefs.coaching, prefs.faceMotion != .calm, !prefs.coachKinds.isEmpty {
            coach = Coach(kinds: prefs.coachKinds, famous: Self.famousClimbs(on: plan.routeID),
                          unitM: imperial ? 1609.344 : 1000, unitName: imperial ? "mi" : "km")
        }
        lastHardStep = plan.workout?.steps.lastIndex { step in
            switch step.target {
            case .steady(let f): f >= 0.88
            case .ramp(let a, let b): max(a, b) >= 0.88
            case .free: false
            }
        }
    }

    // MARK: Lifecycle

    func start() {
        if prefs.rideSound {
            cues = SoundCues(kilometreChime: prefs.kilometreChime)
            sound = RideSound(volume: prefs.soundVolume)
            sound?.start()
        }
        hub.onCommand = { [weak self] in self?.handle($0) }
        hub.onMetrics = { [weak self] in self?.ingest($0) }
        pushResistance(dt: 0)
        loop = Task { @MainActor [weak self] in
            guard let self else { return }
            // No countdown: the ride starts the moment the pedals turn (tick() watches for it).
            while !Task.isCancelled, self.phase != .finished {
                self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Set by `stop()`: the ride is saved straight away, without the review screen.
    private(set) var skipReview = false

    /// Ends the ride and saves it without the review ("Stop session").
    func stop() {
        guard clockStarted else { cancel(); onCancel?(); return }
        skipReview = true
        finish()
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
        sound?.stop()
        sound = nil
        loop?.cancel()
        hub.onCommand = nil
        hub.onMetrics = nil
        // Let go of the trainer: out of ERG, onto the flat, so the cool-down isn't against the last target.
        hub.trainer.apply(gradePercent: 0, gearRatio: controls.gearRatio)
    }

    var clockStarted: Bool {
        switch phase {
        case .riding, .paused, .finished: true
        case .waitingForPedal: false
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
            let isShift = command == .shiftUp || command == .shiftDown
            if isShift, ergActive, targetW != nil {
                // ERG: the trainer ignores gears, so the shifters nudge the workout's intensity instead.
                let next = (min(1.5, max(0.5, intensity + (command == .shiftUp ? 0.05 : -0.05))) * 100).rounded() / 100
                if next == intensity { hub.ride.buzz(double: true) } else if prefs.hapticsOnShift { hub.ride.buzz(double: false) }
                intensity = next
                pushResistance(dt: 0)
                return
            }
            let outcome = controls.apply(command)
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
        case .zoomIn:
            onZoom?(1)
        case .zoomOut:
            onZoom?(-1)
        case .toggleControls:
            controlsRequests += 1
        case .skipInterval:
            // On to the next interval now; not past the last (Finish does that), nor in the open-ended ramp test.
            guard let p = workoutPosition, p.next != nil, workout?.isRampTest == false else {
                hub.ride.buzz(double: true)
                return
            }
            workoutShift += p.remainingInStep
            hub.ride.buzz(double: false)
            pushResistance(dt: 0)
        case .repeatInterval:
            // This interval again from its start: the ride gets longer by what was already done of it.
            guard let p = workoutPosition, workout?.isRampTest == false, p.inStep >= 1 else {
                hub.ride.buzz(double: true)
                return
            }
            workoutShift -= p.inStep
            lapPending = true
            hub.ride.buzz(double: false)
            pushResistance(dt: 0)
        }
    }

    /// Bumped by the controller's "Show controls" button; the ride screen slides its panel up or down (D108).
    private(set) var controlsRequests = 0

    private func ingest(_ metrics: TrainerMetrics) {
        latest = metrics
        power.add(Double(metrics.powerW), at: metrics.timestamp.timeIntervalSinceReferenceDate)
        // The 10 Hz loop ticks anyway in the foreground; a frame that lands just after it adds a redraw and nothing
        // else. Backgrounded (the loop's sleeps stretch), frames drive the clock.
        if let lastTick, Date.now.timeIntervalSince(lastTick) < 0.08 { return }
        tick()
    }

    /// Sets an observed property only when it changes, so views reading it don't redraw for the same value.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<SessionEngine, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
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

        update(\.cadenceRpm, fresh.map { Int($0.cadenceRpm.rounded()) })
        update(\.heartRateBpm, hub.heartRateBpm)
        update(\.instantPowerW, fresh?.powerW)
        if prefs.wattsWindow == 0 {
            update(\.powerW, fresh?.powerW)
        } else if fresh != nil {
            update(\.powerW, power.average(at: t).map { Int($0.rounded()) })
        } else {
            update(\.powerW, nil)
        }

        // Trainer dropout: keep going with zero power; auto-pause after a minute.
        update(\.trainerLost, !hub.isDemo && hub.trainer.link != .ready)
        if trainerLost {
            lostSince = lostSince ?? now
        } else {
            lostSince = nil
        }

        switch phase {
        case .finished:
            break

        case .waitingForPedal:
            if pedalling { beginRiding() }

        case .riding:
            let step = min(dt, SpeedModel.maxStep)
            elapsed += step
            extendFreeRideProfileIfNeeded()
            terrainGrade = controls.grade(autoProfile: autoGrade(dt: step))
            model.step(powerW: watts, gradePercent: terrainGrade, dt: step)
            speedKph = model.speedKph
            _ = paceFilter.update(model.speedMps, dt: step)
            distanceM = model.distanceM
            elevationGainM = model.elevationGainM
            altitude += (distanceM - lastDistanceM) * terrainGrade / 100
            lastDistanceM = distanceM
            if course == nil, distanceM >= Double(ridden.count) * Route.step { ridden.append(altitude) }
            kcal = model.kcal
            recordSamples(watts: Int(watts), cadence: Int(cadence))
            telemetry.update(t: elapsed, dt: step, speedKph: speedKph, powerW: watts, cadenceRpm: cadence,
                             gradePercent: terrainGrade, gear: controls.gear, distanceM: model.distanceM, moving: true)
            checkAutoPause(pedalling: pedalling, now: now)
            if var c = coach {
                let pos = workoutPosition
                let lastEffort = pos.flatMap { $0.index == lastHardStep ? $0.remainingInStep : nil }
                let message = c.update(Coach.Input(t: elapsed, cadenceRpm: cadence, powerW: watts, ftp: Double(prefs.ftp),
                                                   erg: ergActive, lastEffortLeft: lastEffort,
                                                   atM: course == nil ? nil : courseAtM, climbs: course?.climbs ?? [],
                                                   ghostDelta: ghostDelta,
                                                   cadenceBand: pos?.step.cadence ?? prefs.cadenceBand,
                                                   stepAge: pos?.inStep))
                coach = c
                if let message { coachMessage = (message, elapsed) }
            }
            if let lostSince, now.timeIntervalSince(lostSince) > Self.lostTrainerPauseAfter { phase = .paused(auto: true) }
            let finishedRoute = route.map { model.distanceM >= $0.distanceM } ?? false
            if let planned = plan.plannedSeconds, plannedClock >= planned, !keepRiding, !timedDone {
                timedDone = true
                hub.ride.buzz(double: true)
            } else if finishedRoute, !keepRiding, !timedDone {
                timedDone = true
                hub.ride.buzz(double: true)
            }
            // Every 30 s (each one encodes the whole ride so far); leaving the app saves straight away too.
            if now.timeIntervalSince(lastAutosave) >= 30 { autosaveNow() }

        case .paused(let auto):
            // Beats while stopped aren't part of the ride's HRV.
            _ = hub.takeRRIntervals()
            if auto, pedalling, !trainerLost { resume() }
        }
        if phase != .riding, telemetry.needsIdleUpdate(gear: controls.gear) {
            telemetry.update(t: elapsed, dt: 0, speedKph: speedKph, powerW: watts, cadenceRpm: cadence,
                             gradePercent: terrainGrade, gear: controls.gear, distanceM: model.distanceM, moving: false)
        }

        updateSound()
        pushResistance(dt: dt)
    }

    /// Tells the synthesiser what the ride sounds like now.
    private func updateSound() {
        guard let sound else { return }
        let shifted = soundGear.map { controls.gear - $0 } ?? 0
        soundGear = controls.gear
        var event: FaceTelemetry.EventKind?
        if let e = telemetry.event, e.time != soundEventAt {
            soundEventAt = e.time
            event = e.kind
        }
        let info = course?.climbInfo(at: courseAtM)
        let finalKm = info.flatMap { $0.inClimb && $0.toSummitM <= 1000 ? $0.category : nil }
        let step = workoutPosition.flatMap { p in p.next == nil ? nil : (p.index, p.remainingInStep) }
        sound.apply(cues.update(SoundCues.Input(speedKph: speedKph, cadenceRpm: Double(cadenceRpm ?? 0),
                                                paused: phase != .riding, shifted: shifted, event: event,
                                                finalKmOf: finalKm, stepEnding: step, finished: timedDone)))
    }

    /// The gradient the terrain wants right now: a route by distance, a workout by target, else the profile.
    private func autoGrade(dt: Double) -> Double {
        if let route {
            // Past the finish ("keep riding"), the road goes on flat.
            return model.distanceM < route.distanceM ? route.grade(atDistance: model.distanceM) : 0
        }
        if workout != nil { return workoutGrade(dt: dt) }
        return profile?.grade(at: elapsed) ?? 0
    }

    /// A gradient step's own slope (D152); otherwise the gradient that asks for the workout target at ~20 km/h (0 % on
    /// free steps). Eased in either way.
    private func workoutGrade(dt: Double) -> Double {
        let target = workoutPosition?.step.grade ?? targetW.map { WorkoutGrade.grade(forWatts: Double($0), rider: prefs.rider) } ?? 0
        return workoutGradeFilter.update(target, dt: dt)
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
            // The strap's RR intervals go with the second they arrived in (D150).
            let rr = hub.takeRRIntervals()
            // A workout's next interval, or one started again, starts a lap (D151).
            let step = workoutPosition?.index
            let newLap = !samples.isEmpty && step != nil && (step != lapStep || lapPending)
            lapStep = step ?? lapStep
            lapPending = false
            samples.append(RideSample(t: nextSampleSecond, powerW: watts, cadenceRpm: cadence,
                                      speedKph: (speedKph * 10).rounded() / 10, gradePercent: terrainGrade,
                                      gear: controls.gear, heartRateBpm: heartRateBpm,
                                      pausedBefore: pendingPause >= 1 ? pendingPause.rounded() : nil,
                                      rrMs: rr.isEmpty ? nil : rr, lapStart: newLap ? true : nil))
            pendingPause = 0
            nextSampleSecond += 1
        }
    }

    private func extendFreeRideProfileIfNeeded() {
        guard plan.plannedSeconds == nil, var p = profile, elapsed > p.duration - 300 else { return }
        p.append(plan.profileBlock(index: freeBlocks))
        freeBlocks += 1
        profile = p
        course = Self.makeCourse(route: route, profile: p, prefs: prefs)
    }

    // MARK: Resistance

    private func pushResistance(dt: Double) {
        let grade = clockStarted ? terrainGrade : controls.grade(autoProfile: profile?.grade(at: 0) ?? 0)
        let trainer = hub.trainer
        if ergActive, let targetW {
            trainer.applyTargetPower(hub.trainerTarget(targetW))
            return
        }
        if trainer.handlesGearing {
            trainer.apply(gradePercent: grade, gearRatio: controls.gearRatio)
            return
        }
        let fresh = latestFresh
        // ERG fallback: ask for the power this gear needs at this cadence on this grade.
        if prefs.ergShifting {
            let cadence = fresh?.cadenceRpm ?? 0
            // Stopped or barely turning: no target to hold, so the restart isn't against the last one.
            guard cadence >= EffectiveGrade.minCadence else {
                trainer.applyTargetPower(0)
                return
            }
            let v = cadence / 60 * controls.gearRatio * Gears.wheelCircumferenceM
            trainer.applyTargetPower(hub.trainerTarget(Int(prefs.rider.steadyPower(speedMps: v, gradePercent: grade).rounded())))
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

    /// The famous climbs on a route, in the route's own metres (a window starts at 0), with your best on each.
    private static func famousClimbs(on routeID: String?) -> [Coach.FamousClimb] {
        guard let routeID else { return [] }
        let (base, window) = RouteStore.split(routeID)
        let places = Palmares.places(routeID: RouteStore.legacyIDs[base] ?? base)
        guard !places.isEmpty else { return [] }
        let bests = Records.bests(Palmares.allEfforts())
        let offset = window?.lowerBound ?? 0
        return places.compactMap { p in
            guard p.startM >= offset, let climb = RaceStore.climb(id: p.climbID) else { return nil }
            return Coach.FamousClimb(name: climb.name, startM: p.startM - offset, endM: p.startM + p.lengthM - offset,
                                     bestSeconds: bests[p.climbID]?.seconds)
        }
    }

    private static func makeCourse(route: Route?, profile: TerrainProfile?, prefs: Preferences) -> RideCourse? {
        if let route { return RideCourse(route: route) }
        guard let profile else { return nil }
        return RideCourse.generated(profile, rider: prefs.rider, powerW: Double(prefs.ftp) * RouteStats.paceShare)
    }

    // MARK: Display helpers

    /// 0…1 through the ride: distance on a route, otherwise time (free rides run their "day" over 90 minutes).
    var progress: Double {
        if let route, route.distanceM > 0 { return min(0.999, distanceM / route.distanceM) }
        return min(0.999, plannedClock / (plan.plannedSeconds ?? 5400))
    }

    /// 61 normalised elevations for the faces: the next 5 minutes of auto terrain,
    /// or (manual grade) the last 5 minutes ridden.
    var faceProfile: [Double] {
        let speed = max(speedKph / 3.6, 5)
        if let route {
            // The road ahead: the next 3 km of the real profile.
            let from = distanceM
            let heights = stride(from: from, through: from + 3000, by: 50).map { route.elevation(atDistance: $0) }
            return FaceProfile.resample(FaceProfile.normalized(heights), count: 61)
        }
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
        if let route {
            return route.grades(from: distanceM, spanM: 3000, stepM: 50)
        }
        guard let profile else { return [] }
        let from = elapsed
        return stride(from: from, through: from + 300, by: 10).map {
            min(max(profile.grade(at: $0) + controls.autoBias, RideControls.gradeRange.lowerBound), RideControls.gradeRange.upperBound)
        }
    }
}
