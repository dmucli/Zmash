import Foundation
import Observation
import ZmashKit

/// A looping sample ride for the face gallery and previews — the design prototype's simulator, ported.
@MainActor @Observable
final class FaceDemo {
    private(set) var data = FaceData()

    @ObservationIgnored private var t = 120.0
    @ObservationIgnored private var dist = 1.05 // km
    @ObservationIgnored private var climbed = 24.0
    @ObservationIgnored private var kcal = 62.0
    @ObservationIgnored private var crank = 0.0
    @ObservationIgnored private var power3 = 190.0
    @ObservationIgnored private var gear = 14
    @ObservationIgnored private var best = 0.0
    @ObservationIgnored private var km = 1
    @ObservationIgnored private var lastGrade = 0.0
    @ObservationIgnored private var event: FaceTelemetry.Event?
    @ObservationIgnored private var loop: Task<Void, Never>?

    // Previewing moments on demand (the gallery's buttons and showreel).
    /// A ride state held until a time: pause, finish, or the start countdown.
    @ObservationIgnored private var held: (state: FaceState, until: Double)?
    @ObservationIgnored private var countdownFrom: Double?
    @ObservationIgnored private var gearHoldUntil = 0.0
    @ObservationIgnored private var sprintUntil = 0.0
    @ObservationIgnored private var reel: Task<Void, Never>?
    /// The moment being previewed, for the gallery to highlight.
    private(set) var previewing: FaceMoment?
    private(set) var showreelRunning = false

    static let plan = 45.0 * 60

    let ftp: Double
    let units: Units

    init(ftp: Double, units: Units) {
        self.ftp = ftp
        self.units = units
        publish()
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            var last = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                let now = Date.now
                self.advance(min(0.1, now.timeIntervalSince(last)))
                last = now
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        stopShowreel()
    }

    // MARK: Previews

    /// Plays one moment now, whatever the sample ride is doing.
    func play(_ moment: FaceMoment) {
        previewing = moment
        held = nil
        countdownFrom = nil
        switch moment {
        case .start:
            countdownFrom = t
        case .shift:
            gear = gear >= 24 ? 23 : gear + 1
            gearHoldUntil = t + 2.5
            force(.shift, "", gear)
        case .km:
            force(.km, "Kilometre \(km + 1) · 2:07", km + 1)
        case .summit:
            force(.summit, "Summit", 0)
        case .best:
            let watts = Int(max(best, power3) + 30)
            force(.best, "Session best · \(watts) w", watts)
        case .sprint:
            sprintUntil = t + 3
            force(.sprint, "", Int(ftp * 1.7))
        case .pause:
            held = (.paused(auto: false), t + 3.4)
        case .finish:
            held = (.done, t + 4.6)
        }
        publish()
    }

    /// Every moment in turn, then back to the ride.
    func toggleShowreel() {
        if showreelRunning { stopShowreel(); return }
        showreelRunning = true
        reel = Task { @MainActor [weak self] in
            let order: [(FaceMoment, Double)] = [(.start, 4.4), (.shift, 2.4), (.km, 2.6), (.summit, 2.6),
                                                 (.best, 2.6), (.sprint, 3.2), (.pause, 3.8), (.finish, 5)]
            for (moment, hold) in order {
                guard let self, !Task.isCancelled else { return }
                self.play(moment)
                try? await Task.sleep(for: .seconds(hold))
            }
            self?.stopShowreel()
        }
    }

    private func stopShowreel() {
        reel?.cancel()
        reel = nil
        showreelRunning = false
        previewing = nil
    }

    /// Fires an event regardless of what's showing (previews always win).
    private func force(_ kind: FaceTelemetry.EventKind, _ label: String, _ n: Int) {
        event = .init(kind: kind, label: label, n: n, time: t)
    }

    // Terrain and effort curves from the prototype.
    private func gradeAt(_ x: Double) -> Double { 3.4 * sin(x * 1.55) + 1.9 * sin(x * 0.61 + 1.1) + 0.8 * sin(x * 4.1 + 0.4) }
    private func elevAt(_ x: Double) -> Double { 0.5 + 0.34 * sin(x * 1.55 - 1.571) / 1.55 + 0.2 * sin(x * 0.61 - 0.47) / 0.61 }

    private func sim(_ t: Double, _ dist: Double) -> (grade: Double, power: Double, speed: Double, cadence: Double, hr: Double) {
        let grade = gradeAt(dist)
        var power = max(70, min(470, 190 + 13 * grade + 34 * sin(t / 19) + 9 * sin(t / 3.3)))
        if t < sprintUntil { power = ftp * 1.7 + 12 * sin(t * 3) } // previewing a sprint
        let speed = max(9, min(52, 33 - 1.85 * grade + 0.055 * (power - 200)))
        let cadence = max(0, 85 + 6.5 * sin(t / 9.2) + 3 * sin(t / 2.4) - grade * 0.9)
        let hr = 116 + power * 0.115 + 7 * sin(t / 44)
        return (grade, power, speed, cadence, hr)
    }

    private func advance(_ dt: Double) {
        let cur = sim(t, dist)
        t += dt
        if t > Self.plan { t = 120; dist = 1.05; climbed = 24; kcal = 62; km = 1; best = 0 }
        dist += cur.speed / 3600 * dt
        climbed += max(0, cur.grade) / 100 * cur.speed / 3.6 * dt
        kcal += cur.power * dt / 1000
        crank = (crank + cur.cadence / 60 * 360 * dt).truncatingRemainder(dividingBy: 360)
        power3 += (cur.power - power3) * min(1, dt / 3)
        let newGear = max(1, min(24, Int((13 + 6 * sin(t / 13) - cur.grade * 0.6).rounded())))

        if let e = event, t - e.time > FaceTelemetry.eventLifetime { event = nil }
        func fire(_ kind: FaceTelemetry.EventKind, _ label: String, _ n: Int = 0) {
            if event == nil || event?.kind == .shift { event = .init(kind: kind, label: label, n: n, time: t) }
        }
        if t >= gearHoldUntil {
            if newGear != gear { fire(.shift, "") }
            gear = newGear
        }
        // The start preview: 3, 2, 1, then go.
        if let from = countdownFrom, t - from >= 3 {
            countdownFrom = nil
            force(.start, "", 0)
        }
        if let h = held, t >= h.until { held = nil }
        if previewing != nil, !showreelRunning, held == nil, countdownFrom == nil, event == nil { previewing = nil }
        let k = Int(dist)
        if k >= km + 1 { km = k; fire(.km, "Kilometre \(k) · \(TimeFormat.clock(Int(t / Double(max(1, k))))) /km", k) }
        if lastGrade > 0.6 && cur.grade <= 0.6 { fire(.summit, "Summit") }
        if cur.power > best + 6 && cur.power > 300 { fire(.best, "Session best · \(Int(cur.power)) w", Int(cur.power)) }
        best = max(best, cur.power)
        lastGrade = cur.grade
        publish()
    }

    private func publish() {
        let cur = sim(t, dist)
        let ahead = sim(t + 5, dist + cur.speed / 3600 * 5)
        let raw = (0...60).map { k in elevAt(dist + cur.speed / 3600 * (Double(k) / 60 * 300)) }
        let lo = raw.min() ?? 0, hi = raw.max() ?? 1, span = max(0.12, hi - lo)

        var d = FaceData()
        d.speedKph = cur.speed
        d.powerW = cur.power
        d.power3 = power3
        d.cadenceRpm = cur.cadence
        d.heartRateBpm = cur.hr
        d.elapsed = t
        d.remaining = max(0, Self.plan - t)
        d.distanceM = dist * 1000
        d.kcal = kcal
        d.climbedM = climbed
        d.grade = cur.grade
        d.gear = gear
        d.gearCount = 24
        d.ftp = ftp
        d.crankDegrees = crank
        d.progress = min(1, t / Self.plan)
        d.profile = raw.map { 0.08 + ($0 - lo) / span * 0.9 }
        d.event = event
        d.eventAge = event.map { min(1, (t - $0.time) / FaceTelemetry.eventLifetime) } ?? 1
        d.trendSpeed = (ahead.speed - cur.speed) / 5
        d.trendPower = (ahead.power - cur.power) / 5
        d.units = units
        if let from = countdownFrom {
            d.state = .countdown(max(1, 3 - Int(t - from)))
        } else if let h = held {
            d.state = h.state
        }
        data = d
    }
}
