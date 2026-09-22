#if DEBUG
import Foundation
import UIKit
import ZmashKit

/// Debug-only launch arguments for screenshots and UI checks in the Simulator:
///   -ZmashAutostart manual|auto   start a ride straight away (demo devices)
///   -ZmashScreen history|settings open a sheet on launch
///   -ZmashSeedHistory             insert sample rides if history is empty
@MainActor
enum DebugLaunch {
    static let defaults = UserDefaults.standard

    static var autostart: SessionPlan? {
        guard let mode = defaults.string(forKey: "ZmashAutostart") else { return nil }
        var plan = SessionPlan()
        plan.terrainMode = mode == "auto" ? .auto : .manual
        plan.terrainType = .hilly
        plan.seed = 42
        // -ZmashWorkout <id>: ride a structured workout instead (e.g. threshold-4x8, ramp-test).
        if let id = defaults.string(forKey: "ZmashWorkout"), WorkoutStore.workout(id: id) != nil {
            plan.workoutID = id
            plan.workoutERG = !defaults.bool(forKey: "ZmashWorkoutGrade")
        }
        return plan
    }

    static var screen: String? { defaults.string(forKey: "ZmashScreen") }
    /// -ZmashFace paper|aura|night|horizon|kinetic|classic
    static var face: FaceID? { defaults.string(forKey: "ZmashFace").flatMap(FaceID.init) }
    /// -ZmashEndAfter <seconds>: finish the auto-started ride after that long (shows the save modal).
    /// -ZmashPiP YES: start Picture-in-Picture a few seconds into the auto-started ride.
    static var startPiP: Bool { defaults.bool(forKey: "ZmashPiP") }
    static var endAfter: Double? { defaults.object(forKey: "ZmashEndAfter").flatMap { Double("\($0)") } }

    /// -ZmashLandscape YES: lay the app out in landscape, turned 90° on the portrait screen.
    /// The headless Simulator can't be rotated, and iPadOS refuses programmatic rotation.
    static var landscapePreview: Bool { defaults.bool(forKey: "ZmashLandscape") }
    /// -ZmashCompactWidth <points>: render in a narrow column, like Split View / Slide Over.
    static var compactWidth: CGFloat? { defaults.object(forKey: "ZmashCompactWidth").flatMap { Double("\($0)") }.map { CGFloat($0) } }

    static func seedHistoryIfRequested() {
        guard defaults.bool(forKey: "ZmashSeedHistory") else { return }
        let existing = (try? RideStore.context.fetchCount(.init(predicate: #Predicate<RideSession> { $0.isComplete }))) ?? 0
        guard existing == 0 else { return }
        let cal = Calendar.current
        for (daysAgo, minutes, type) in [(1, 45, TerrainType.hilly), (3, 30, .rolling), (6, 60, .mountain),
                                           (9, 30, .flat), (13, 90, .hilly), (16, 45, .rolling),
                                           (20, 60, .hilly), (24, 45, .flat), (27, 90, .mountain),
                                           (34, 60, .rolling), (41, 45, .hilly), (48, 30, .flat),
                                           (55, 75, .mountain), (62, 45, .rolling)] {
            var plan = SessionPlan()
            plan.plannedMinutes = minutes
            plan.terrainMode = .auto
            plan.terrainType = type
            plan.seed = UInt64(daysAgo * 7919)
            let profile = plan.profile()!
            var model = SpeedModel()
            var rider = DemoRider(seed: plan.seed)
            var samples: [RideSample] = []
            for t in 0..<(minutes * 60) {
                let grade = profile.grade(at: Double(t))
                let gear = grade > 4 ? 8 : grade < -2 ? 18 : 13
                let s = rider.step(dt: 1, gearRatio: Gears.ratio(for: gear), gradePercent: grade)
                model.step(powerW: Double(s.powerW), gradePercent: grade, dt: 1)
                samples.append(RideSample(t: t, powerW: s.powerW, cadenceRpm: Int(s.cadenceRpm),
                                          speedKph: (model.speedKph * 10).rounded() / 10, gradePercent: grade, gear: gear))
            }
            let start = cal.date(byAdding: .day, value: -daysAgo, to: cal.date(bySettingHour: 18, minute: 30, second: 0, of: .now)!)!
            let summary = SessionSummary.from(samples: samples, activeSeconds: minutes * 60, distanceM: model.distanceM,
                                              elevationGainM: model.elevationGainM, kcal: model.kcal)
            let ride = FinishedRide(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)),
                                    plan: plan, summary: summary, samples: samples)
            RideStore.save(ride, rpe: [5, 7, 8, 4, 9, 6][daysAgo % 6], note: nil)
        }
    }
}
#endif
