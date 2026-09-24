#if DEBUG
import Foundation
import SwiftData
import UIKit
import ZmashKit

/// Debug-only launch arguments for screenshots and UI checks in the Simulator:
///   -ZmashAutostart manual|auto   start a ride straight away (demo devices)
///   -ZmashScreen history|settings open a sheet on launch
///   -ZmashSeedHistory             insert sample rides if history is empty
@MainActor
enum DebugLaunch {
    static let defaults = UserDefaults.standard

    /// Launched with any -Zmash… argument (a screenshot or UI check run).
    static var scripted: Bool { ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-Zmash") } }

    static var autostart: SessionPlan? {
        defaults.string(forKey: "ZmashAutostart").map(plan)
    }

    /// -ZmashHomePlan manual|auto|draw: show home with that plan chosen (and any -ZmashWorkout / -ZmashRoute), without starting.
    static var homePlan: SessionPlan? {
        defaults.string(forKey: "ZmashHomePlan").map(plan)
    }

    private static func plan(_ mode: String) -> SessionPlan {
        var plan = SessionPlan()
        plan.terrainMode = mode == "auto" || mode == "draw" ? .auto : .manual
        plan.terrainType = defaults.string(forKey: "ZmashTerrainType").flatMap(TerrainType.init) ?? .hilly
        plan.effort = defaults.string(forKey: "ZmashEffort").flatMap(Effort.init) ?? .medium
        plan.seed = 42
        if mode == "draw" {
            plan.drawn = true
            plan.drawing = DrawnCourse.starter
        }
        // -ZmashRoute <id>: ride a route (climb/mont-ventoux-bedoin, race/2025/tour-de-france/16, an old id like ventoux).
        if let id = defaults.string(forKey: "ZmashRoute"), RouteStore.route(id: id) != nil {
            plan.routeID = id
            return plan
        }
        // -ZmashWorkout <id>: ride a structured workout instead (e.g. threshold-4x8, ramp-test).
        if let id = defaults.string(forKey: "ZmashWorkout"), WorkoutStore.workout(id: id) != nil {
            plan.workoutID = id
            plan.workoutERG = !defaults.bool(forKey: "ZmashWorkoutGrade")
        }
        return plan
    }

    static var screen: String? { defaults.string(forKey: "ZmashScreen") }
    /// -ZmashScreen campaign, or -ZmashHomeShow campaign, with -ZmashRace 2025/tour-de-france.
    static var race: String { defaults.string(forKey: "ZmashRace") ?? "2025/tour-de-france" }
    /// -ZmashHomeShow plan|campaign: home's preview shows the plan (-ZmashPlan) or the campaign (-ZmashRace), with
    /// -ZmashHomePlan and -ZmashWorkout or -ZmashRoute to be on Workout or Route.
    static var homeShow: String? { defaults.string(forKey: "ZmashHomeShow") }
    /// -ZmashMoment start|shift|km|summit|best|sprint|pause|finish: play it in the gallery soon after opening.
    static var moment: FaceMoment? { defaults.string(forKey: "ZmashMoment").flatMap(FaceMoment.init) }
    /// -ZmashPalette <id>: draw the launch face with that palette (Phase 11 checks).
    /// Also -ZmashHero <metric> and -ZmashFont <family> for the launch face (D109 checks).
    static func applyPaletteIfRequested(_ prefs: Preferences) {
        let target = Self.face ?? prefs.face
        var style = prefs.style(target)
        if let id = defaults.string(forKey: "ZmashPalette") { style.paletteID = id }
        if let hero = defaults.string(forKey: "ZmashHero").flatMap(FaceMetric.init) { style.hero = hero }
        if let font = defaults.string(forKey: "ZmashFont").flatMap(FaceFont.Family.init) { style.font = font }
        if style != prefs.style(target) { prefs.setStyle(style, for: target) }
    }
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

    /// -ZmashPlan <id>: the plan -ZmashScreen plan opens; -ZmashEnrolPlan YES also puts you on it (Tue, Thu, Sat).
    static var plan: String { defaults.string(forKey: "ZmashPlan") ?? "ftp-build" }
    static func enrolPlanIfRequested() {
        guard defaults.bool(forKey: "ZmashEnrolPlan"), let plan = TrainingPlans.plan(id: Self.plan),
              PlanStore.current?.planID != plan.id else { return }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        var e = PlanStore.enrol(plan, weekdays: [3, 5, 7], start: start)
        e.done = [.init(week: 0, index: 0, date: start, adherence: 1.08)]
        e.notches = ["threshold": 1]
        PlanStore.save(e)
    }

    /// -ZmashAddRider <name>: add that rider if missing and ride as them (D112 checks).
    static func addRiderIfRequested(_ prefs: Preferences) {
        guard let name = defaults.string(forKey: "ZmashAddRider") else { return }
        if let r = prefs.riders.first(where: { $0.name == name }) { prefs.switchRider(to: r.id); return }
        prefs.addRider(name: name, riderKg: 58, bikeKg: 7.5, ftp: 210, guessedFTP: false)
    }

    /// -ZmashSeedCampaign <n>: a campaign on -ZmashRace with its first n stages ridden at your pace (± a few %).
    static func seedCampaignIfRequested() {
        let n = defaults.integer(forKey: "ZmashSeedCampaign")
        guard n > 0, let race = RaceStore.races.first(where: { $0.id == Self.race }),
              CampaignStore.latest(raceID: race.id) == nil else { return }
        var c = CampaignStore.start(race: race, prefs: .shared)
        for stage in race.stages.sorted(by: { $0.number < $1.number }).prefix(n) {
            let route = race.route(stage)
            let power = c.pacePowerW * Double.random(in: 0.97...1.08)
            let t = RouteTiming(times: route.cumulativeTimes(rider: c.rider, powerW: power))
            let climbs = Campaign.categorisedClimbs(route, within: 0...route.distanceM)
            let summits = climbs.map { cl -> Double? in t.times[min(Int((cl.startM + cl.lengthM) / Route.step), t.times.count - 1)] }
            c.ridden.append(Campaign.Ridden(stage: stage.number, fromM: 0, toM: route.distanceM, seconds: t.total, summitSeconds: summits))
        }
        CampaignStore.save(c)
    }

    /// -ZmashSeedRoute <id>: save a synthetic completed attempt at that route, so the next ride has a ghost.
    static func seedRouteAttemptIfRequested() {
        guard let id = defaults.string(forKey: "ZmashSeedRoute"), let route = RouteStore.route(id: id) else { return }
        guard RideStore.ghost(routeID: id, distanceM: route.distanceM) == nil else { return }
        var plan = SessionPlan()
        plan.plannedMinutes = nil
        plan.routeID = id
        var model = SpeedModel()
        var rider = DemoRider(seed: 7)
        var samples: [RideSample] = []
        var t = 0
        while model.distanceM < route.distanceM, t < 3 * 3600 {
            let grade = route.grade(atDistance: model.distanceM)
            let gear = grade > 6 ? 6 : grade > 3 ? 9 : 14
            let s = rider.step(dt: 1, gearRatio: Gears.ratio(for: gear), gradePercent: grade)
            model.step(powerW: Double(s.powerW), gradePercent: grade, dt: 1)
            samples.append(RideSample(t: t, powerW: s.powerW, cadenceRpm: Int(s.cadenceRpm),
                                      speedKph: (model.speedKph * 10).rounded() / 10, gradePercent: grade, gear: gear))
            t += 1
        }
        let start = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let summary = SessionSummary.from(samples: samples, activeSeconds: t, distanceM: model.distanceM,
                                          elevationGainM: model.elevationGainM, kcal: model.kcal)
        RideStore.save(FinishedRide(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(Double(t)),
                                    plan: plan, summary: summary, samples: samples), rpe: 8, note: nil)
    }

    /// -ZmashBackupCheck: back up, delete every ride, restore, and write the counts to Documents/backup-check.txt.
    static func backupCheckIfRequested() {
        guard defaults.bool(forKey: "ZmashBackupCheck") else { return }
        var log: [String] = []
        do {
            let before = (try? RideStore.context.fetchCount(FetchDescriptor<RideSession>())) ?? -1
            let made = try Backup.make()
            log.append("backup: \(made.counts.summary) (store had \(before))")
            for ride in (try? RideStore.context.fetch(FetchDescriptor<RideSession>())) ?? [] { RideStore.context.delete(ride) }
            try RideStore.context.save()
            let emptied = (try? RideStore.context.fetchCount(FetchDescriptor<RideSession>())) ?? -1
            let restored = try Backup.restore(from: made.url, settings: false)
            let after = (try? RideStore.context.fetchCount(FetchDescriptor<RideSession>())) ?? -1
            let again = try Backup.restore(from: made.url, settings: false)
            log.append("emptied: \(emptied); restored: \(restored.summary); store has \(after); restoring again adds \(again.rides)")
            let first = (try? RideStore.context.fetch(FetchDescriptor<RideSession>()))?.first
            log.append("a restored ride has \(first?.samples.count ?? -1) samples, \(first?.powerCurve.count ?? -1) curve points")
            let fit = try RideExport.allRides()
            let files = (try? FileManager.default.contentsOfDirectory(atPath: fit.url.path(percentEncoded: false))) ?? []
            log.append("exported \(fit.count) FIT files; the folder has \(files.count), e.g. \(files.sorted().first ?? "-")")
        } catch {
            log.append("failed: \(error)")
        }
        try? log.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "backup-check.txt"), atomically: true, encoding: .utf8)
    }

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
