import Foundation

// MARK: - More of Zmash's own plans (D168)

/// Plans for the goals a big library's plans cover (an FTP build, a season, racing, a time trial, a first 100 km, long
/// days, a triathlon, the mountains, starting out, busy weeks, the off-season), built from Zmash's own sessions: its
/// adaptive intervals for the key sessions, so they get harder or easier as you ride, and its library for the rest.
/// Sessions come in order of importance: with fewer ride days, the first ones are kept.
extension TrainingPlans {
    typealias Session = TrainingPlan.Session

    private static func sst(_ sets: Int, _ minutes: Int) -> Session { .intervals(.sweetspot, sets: sets, minutes: minutes) }
    private static func tempo(_ sets: Int, _ minutes: Int) -> Session { .intervals(.tempo, sets: sets, minutes: minutes) }
    private static func thr(_ sets: Int, _ minutes: Int) -> Session { .intervals(.threshold, sets: sets, minutes: minutes) }
    private static func vo2(_ sets: Int, _ minutes: Int) -> Session { .intervals(.vo2, sets: sets, minutes: minutes) }
    private static func e(_ minutes: Int) -> Session { .endurance(minutes: minutes) }
    private static func w(_ id: String) -> Session { .workout(id) }

    static let more: [TrainingPlan] = [ftp8, seasonBuild, vo2Block, crit, timeTrial, century, longDays, triathlon,
                                       mountains, firstMonth, busyWeeks, offSeason]

    // MARK: Build

    static let ftp8 = TrainingPlan(
        id: "ftp-8", name: "FTP in 8 weeks",
        summary: "8 weeks, 4 rides a week: sweet spot, then threshold and VO₂max, a lighter 4th week and a 20-minute test to finish.",
        weeks: [
            [sst(3, 10), thr(3, 8), e(60), w("spinups-45")],
            [sst(3, 12), thr(4, 8), e(75), w("over-under-4x6")],
            [sst(2, 20), thr(3, 12), e(90), w("vo2-6x3")],
            [sst(2, 12), w("recovery-45"), e(60)],
            [thr(3, 15), vo2(5, 4), e(90), w("over-under-3x12")],
            [thr(2, 20), w("vo2-30-30-2x10"), e(105), w("sweetspot-kicks-3x12")],
            [thr(2, 25), vo2(5, 5), e(90), w("threshold-descending")],
            [sst(2, 10), w("recovery-45"), w("ftp-test-20")],
        ])

    static let seasonBuild = TrainingPlan(
        id: "season-build", name: "Season build",
        summary: "12 weeks in three blocks, base, build and peak, each ending with a lighter week, and a 20-minute test to finish.",
        weeks: [
            // Base
            [sst(3, 10), tempo(2, 15), e(75), w("spinups-45")],
            [sst(3, 12), w("big-gear-5x5"), e(90), w("rolling-60")],
            [sst(2, 20), tempo(3, 15), e(105), w("spinups-60")],
            [sst(2, 12), w("recovery-45"), e(60)],
            // Build
            [thr(3, 10), vo2(5, 3), e(90), w("sweetspot-kicks-3x12")],
            [thr(3, 12), w("over-under-3x12"), e(105), w("vo2-30-30-2x10")],
            [thr(2, 20), vo2(5, 4), e(120), w("surges-2x16")],
            [sst(2, 15), w("recovery-45"), e(75)],
            // Peak
            [thr(3, 15), w("vo2-40-20-4x6"), e(105), w("race-attacks")],
            [w("over-under-2x20"), vo2(5, 5), e(120), w("sprint-sets-3x4")],
            [thr(2, 20), w("vo2-30-15"), e(90), w("lead-outs-5")],
            [sst(2, 10), w("recovery-45"), w("ftp-test-20")],
        ])

    static let vo2Block = TrainingPlan(
        id: "vo2-block", name: "VO₂max block",
        summary: "3 weeks at the top end: two VO₂max sessions and an easy ride each week. It raises the ceiling before a build.",
        weeks: [
            [vo2(5, 3), w("vo2-30-30-2x10"), e(60)],
            [vo2(5, 4), w("vo2-30-15"), e(75)],
            [vo2(6, 3), w("vo2-40-20-4x6"), e(60)],
        ])

    static let crit = TrainingPlan(
        id: "crit", name: "Crit ready",
        summary: "6 weeks for racing in a bunch: sprints, attacks, 30/30s and over-unders, with a lighter 4th week.",
        weeks: [
            [w("sprint-sets-3x4"), thr(3, 10), e(60), w("vo2-30-30-2x10")],
            [w("race-attacks"), vo2(5, 3), e(60), w("over-under-4x6")],
            [w("microbursts-3x10"), thr(3, 12), e(75), w("lead-outs-5")],
            [w("standing-starts-6"), w("recovery-45"), e(60)],
            [w("race-attacks"), w("vo2-40-20-4x6"), e(75), w("surges-2x16")],
            [w("lead-outs-5"), w("anaerobic-4x2"), w("recovery-45")],
        ])

    static let timeTrial = TrainingPlan(
        id: "time-trial", name: "Time trial",
        summary: "6 weeks of long efforts just under and at threshold, for a time trial or a long solo break.",
        weeks: [
            [thr(3, 10), sst(2, 20), e(60)],
            [thr(3, 12), w("big-gear-sweetspot-4x8"), e(75)],
            [thr(2, 20), sst(3, 15), e(75)],
            [sst(2, 15), w("recovery-45"), e(60)],
            [thr(3, 15), w("threshold-descending"), e(90)],
            [thr(2, 15), w("hard-starts-4x8"), w("recovery-45")],
        ])

    // MARK: Endurance

    static let century = TrainingPlan(
        id: "century", name: "First 100 km",
        summary: "8 weeks to a first 100 km: the long ride grows to three hours, with tempo and sweet spot midweek.",
        weeks: [
            [e(90), tempo(2, 15), w("spinups-45")],
            [e(105), sst(2, 12), w("rolling-60")],
            [e(120), tempo(3, 15), w("endurance-tempo-60")],
            [e(90), w("recovery-45"), sst(2, 10)],
            [w("endurance-tempo-120"), sst(3, 12), w("rolling-60")],
            [e(150), sst(2, 20), w("endurance-finish-90")],
            [e(180), tempo(2, 20), w("spinups-60")],
            [w("endurance-tempo-90"), tempo(2, 10), w("recovery-45")],
        ], goal: .endurance)

    static let longDays = TrainingPlan(
        id: "long-days", name: "Long days out",
        summary: "6 weeks for long, changing days, gravel or a sportive: long rides with tempo, climbs, surges and rolling roads.",
        weeks: [
            [w("rolling-90"), w("big-gear-5x5"), w("spinups-45")],
            [w("endurance-tempo-90"), w("long-climbs-2x20"), e(60)],
            [e(150), w("race-attacks"), w("rolling-60")],
            [e(90), w("recovery-45"), w("tempo-30")],
            [w("endurance-tempo-120"), w("long-climbs-3x10"), w("spinups-60")],
            [w("endurance-finish-90"), w("sweetspot-kicks-2x15"), w("recovery-45")],
        ], goal: .endurance)

    static let triathlon = TrainingPlan(
        id: "tri-bike", name: "Triathlon bike",
        summary: "6 weeks of steady, strong riding for the bike leg: sweet spot, long tempo and big-gear work, and nothing that leaves your legs empty for the run.",
        weeks: [
            [sst(3, 10), e(75), w("big-gear-5x5")],
            [sst(3, 12), e(90), w("tempo-40")],
            [sst(2, 20), w("endurance-tempo-90"), w("big-gear-sweetspot-4x8")],
            [tempo(2, 15), w("recovery-45"), e(60)],
            [w("sweetspot-2x30"), w("endurance-tempo-120"), w("tempo-cadence-3x12")],
            [sst(2, 15), e(60), w("recovery-45")],
        ], goal: .endurance)

    // MARK: Climb

    static let mountains = TrainingPlan(
        id: "mountains", name: "Mountain legs",
        summary: "6 weeks of climbing strength: long climbs, big gears and steep repeats, and an Alpine or Pyrenean col each weekend, the Madeleine to finish.",
        weeks: [
            [w("long-climbs-3x10"), .route("climb/col-du-telegraphe-saint-michel-de-maurienne"), w("big-gear-5x5")],
            [w("long-climbs-2x20"), .route("climb/col-de-peyresourde-from-the-north-west"), w("steep-repeats-6x3")],
            [thr(2, 20), .route("climb/alpe-d-huez-bourg-d-oisans"), w("big-gear-sweetspot-4x8")],
            [sst(2, 12), w("recovery-45"), e(60)],
            [w("steep-repeats-6x3"), .route("climb/col-du-galibier-valloire"), w("over-under-3x12")],
            [w("long-climbs-3x10"), .route("climb/col-de-la-madeleine-la-chambre"), w("recovery-45")],
        ], goal: .climb)

    // MARK: Maintain

    static let firstMonth = TrainingPlan(
        id: "first-month", name: "First month indoors",
        summary: "4 gentle weeks to settle into indoor riding: short, steady rides that grow a little, and a ramp test at the end to set your zones.",
        weeks: [
            [w("endurance-30"), w("spinups-45"), w("recovery-30")],
            [w("tempo-30"), w("endurance-60"), w("spinups-45")],
            [w("sweetspot-30"), w("rolling-60"), w("endurance-30")],
            [w("sweetspot-4x8"), w("endurance-60"), w("ramp-test")],
        ], goal: .maintain)

    static let busyWeeks = TrainingPlan(
        id: "busy", name: "Busy weeks",
        summary: "6 weeks of two rides, one long block and one short and sharp: enough to keep moving forward when the week is full.",
        weeks: [
            [sst(2, 15), w("vo2-30")],
            [thr(3, 8), w("endurance-tempo-60")],
            [sst(3, 12), w("vo2-30-30-2x10")],
            [tempo(2, 12), w("endurance-60")],
            [thr(3, 10), w("microbursts-3x10")],
            [sst(2, 20), w("threshold-3x5")],
        ], goal: .maintain)

    static let offSeason = TrainingPlan(
        id: "off-season", name: "Off-season",
        summary: "4 relaxed weeks between seasons: strength in big gears, fast pedalling, a few sprints for fun, and no long intervals.",
        weeks: [
            [w("big-gear-5x5"), w("spinups-45"), e(60)],
            [w("tempo-cadence-3x12"), w("rolling-60"), w("sprints-10x10")],
            [w("big-gear-sweetspot-4x8"), w("spinups-60"), w("sprint-sets-3x4")],
            [w("endurance-60"), w("recovery-45"), w("standing-starts-6")],
        ], goal: .maintain)
}
