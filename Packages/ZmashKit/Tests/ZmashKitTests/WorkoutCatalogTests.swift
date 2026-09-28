import Foundation
import Testing
@testable import ZmashKit

/// The bundled workout catalog (D154): what's read from each `.zwo`, what's left out, and the compact format.
@Suite struct WorkoutCatalogTests {
    @Test func fileDetailsAndCleanDescription() throws {
        let xml = """
        <workout_file>
            <author>Zwift (via whatsonzwift.com)</author>
            <name>Recipe for Grit</name>
            <description>Duration : 54m

        Stress points : 54

        Z1 : 16m

        Z6 : -

        Having grit is a key trait.</description>
            <sportType>bike</sportType>
            <category>Sweet Spot</category>
            <workout>
                <Warmup Duration="180" PowerLow="0.45" PowerHigh="0.6" />
                <SteadyState Duration="600" Power="0.88"><textevent timeoffset="10" message="Go"/></SteadyState>
            </workout>
        </workout_file>
        """
        let f = try #require(ZWOParser.parseFile(Data(xml.utf8), id: "x"))
        #expect(f.author == "Zwift (via whatsonzwift.com)")
        #expect(f.category == "Sweet Spot")
        #expect(f.sportType == "bike" && f.isRideable)
        #expect(f.workout.steps.count == 2)
        #expect(ZWOParser.cleanDescription(f.workout.summary) == "Having grit is a key trait.")
        #expect(WorkoutCatalogFile.category(named: f.category) == .tempo)
    }

    @Test func runsAndDistanceAreNotRideable() throws {
        let run = #"<workout_file><name>R</name><sportType>run</sportType><workout><SteadyState Duration="60" Power="1"/></workout></workout_file>"#
        #expect(try #require(ZWOParser.parseFile(Data(run.utf8), id: "r")).isRideable == false)
        let dist = #"<workout_file><name>D</name><durationType>distance</durationType><workout><SteadyState Duration="400" Power="1"/></workout></workout_file>"#
        let d = try #require(ZWOParser.parseFile(Data(dist.utf8), id: "d"))
        #expect(d.distanceBased && !d.isRideable)
    }

    /// Older files: Windows-1252 bytes, a bare ampersand, and a steady step with PowerLow/PowerHigh instead of Power.
    @Test func messyFilesStillRead() throws {
        var bytes = Array(#"<workout_file><name>Don"#.utf8)
        bytes.append(0x92)   // ’ in Windows-1252, invalid UTF-8
        bytes += Array(#"t stop & go</name><workout><SteadyState Duration="64.2" PowerHigh="1.240" PowerLow="1.240"/></workout></workout_file>"#.utf8)
        let f = try #require(ZWOParser.parseFile(Data(bytes), id: "m"))
        #expect(f.workout.name == "Don’t stop & go")
        #expect(f.workout.steps.first?.target == .steady(1.24))
        #expect(f.workout.steps.first?.seconds == 64)
    }

    @Test func compactStepsRoundTrip() {
        let w = Workout(id: "zc/a/b", name: "B", summary: "s", steps: [
            .init(300, .ramp(0.45, 0.75)),
            .init(120, .steady(1.05), cadence: 95...105),
            .init(180, .steady(0.9), grade: 6),
            .init(60, .free),
            .init(240, .ramp(0.6, 0.4)),
        ])
        let entry = WorkoutCatalogFile.Entry(workout: w, collection: "A", author: nil, category: .threshold)
        let back = entry.workout
        #expect(back.steps.map(\.target) == w.steps.map(\.target))
        #expect(back.steps.map(\.cadence) == w.steps.map(\.cadence))
        #expect(back.steps.map(\.grade) == w.steps.map(\.grade))
        #expect(back.steps.map(\.label) == ["Warm-up", "On", "On", "Free ride", "Cool-down"])
        #expect(back.category == .threshold)
        #expect(entry.seconds == w.duration)
    }

    @Test func kindsFromTheSteps() {
        func w(_ name: String, _ steps: [Workout.Step]) -> Workout { Workout(id: "", name: name, summary: "", steps: steps) }
        let warm = Workout.Step(600, .steady(0.55))
        #expect(w("Easy", [warm, .init(3000, .steady(0.65))]).inferredCategory == .endurance)
        #expect(w("SST", [warm, .init(1200, .steady(0.9)), .init(1200, .steady(0.9))]).inferredCategory == .tempo)
        #expect(w("FTP", [warm, .init(1200, .steady(1.0)), .init(300, .steady(0.5))]).inferredCategory == .threshold)
        #expect(w("VO2", [warm] + Array(repeating: [Workout.Step(180, .steady(1.15)), .init(180, .steady(0.5))], count: 5).flatMap { $0 })
            .inferredCategory == .vo2)
        #expect(w("Kicks", [warm, .init(1200, .steady(0.8))] + Array(repeating: [Workout.Step(20, .steady(1.8)), .init(100, .steady(0.5))], count: 10).flatMap { $0 })
            .inferredCategory == .sprints)
        #expect(w("FTP Test", [warm, .init(1200, .steady(1.05))]).inferredCategory == .tests)
    }

    @Test func lengthsAreTheNearest() {
        #expect(WorkoutLength.of(seconds: 20 * 60) == .m30)
        #expect(WorkoutLength.of(seconds: 37 * 60) == .m30)
        #expect(WorkoutLength.of(seconds: 40 * 60) == .m45)
        #expect(WorkoutLength.of(seconds: 59 * 60) == .h1)
        #expect(WorkoutLength.of(seconds: 63 * 60) == .h1)
        #expect(WorkoutLength.of(seconds: 90 * 60) == .h90)
        #expect(WorkoutLength.of(seconds: 106 * 60) == .longer)
        #expect(WorkoutLength.any.contains(seconds: 5000))
        #expect(!WorkoutLength.m30.contains(seconds: 3600))
    }

    /// Collections that are plans (D155) go to the Plan page: by their name, or by numbered sessions.
    @Test func plansAmongTheCollections() {
        #expect(WorkoutCatalogFile.isPlan(collection: "FTP Builder", names: ["Foundation"]))
        #expect(WorkoutCatalogFile.isPlan(collection: "Zwift Academy 2019", names: ["Threshold Development"]))
        #expect(WorkoutCatalogFile.isPlan(collection: "Singletrack Slayer", names: ["1. Low 30's", "5. Low 60's", "Three Three's"]))
        #expect(WorkoutCatalogFile.isPlan(collection: "ZF18 Direct Power Coaching Phase 9", names: ["#100-DPC FTP"]))
        #expect(!WorkoutCatalogFile.isPlan(collection: "30 minutes to burn", names: ["2 by 2", "Alpha", "Bravo"]))
        #expect(!WorkoutCatalogFile.isPlan(collection: "Sweet Spot", names: ["Big Gear SST - 3x5", "15min varied tempo #2"]))
        #expect(!WorkoutCatalogFile.isPlan(collection: "Best of Zwift Academy", names: ["70.3 Development"]))
        #expect(!WorkoutCatalogFile.isPlan(collection: "The Sufferfest", names: ["Revolver", "Angels"]))
        #expect(WorkoutCatalogFile.goal(forPlan: "L'Etape du Tour Training Club") == .climb)
        #expect(WorkoutCatalogFile.goal(forPlan: "Your First Century") == .endurance)
        #expect(WorkoutCatalogFile.goal(forPlan: "Back To Fitness") == .maintain)
        #expect(WorkoutCatalogFile.goal(forPlan: "4wk FTP Booster") == .build)
    }

    @Test func sessionOrderFromTheName() {
        #expect(WorkoutCatalogFile.sessionOrder("Week 3 - Day 6 - Threshold block #1") == (3, 6))
        #expect(WorkoutCatalogFile.sessionOrder("Week 1 - 2. Fast and Easy") == (1, 2))
        #expect(WorkoutCatalogFile.sessionOrder("Month 1 - Session 3: Low Cadence") == (1, 3))
        #expect(WorkoutCatalogFile.sessionOrder("#100-DPC 2x (4 x 2.5') FTP") == (nil, 100))
        #expect(WorkoutCatalogFile.sessionOrder("Stage 11") == (nil, 11))
        #expect(WorkoutCatalogFile.sessionOrder("10. Tabata - Set 2") == (nil, 10))
        #expect(WorkoutCatalogFile.sessionOrder("Red Unicorn") == (nil, nil))
    }

    /// A catalog plan's weeks (D156): the files' own when every session names one, otherwise its sessions in order, in
    /// weeks of its usual count.
    @Test func catalogPlanWeeks() {
        #expect(WorkoutCatalogFile.planWeeks(["Week 1 - Day 1 - A", "Week 1 - Day 3 - B", "Week 2 - Day 1 - C", "Week 4 - Day 2 - D"])
                == [[0, 1], [2], [3]])
        // One names no week: in order, 2 a week, as most of its weeks have.
        #expect(WorkoutCatalogFile.planWeeks(["Odd", "Week 1 - A", "Week 1 - B", "Week 2 - C", "Week 2 - D", "Week 3 - E"])
                == [[0, 1], [2, 3], [4, 5]])
        // None does: 3 a week.
        #expect(WorkoutCatalogFile.planWeeks(["1. A", "2. B", "3. C", "4. D"]) == [[0, 1, 2], [3]])
        // A month isn't a week.
        #expect(WorkoutCatalogFile.planWeeks(["Month 1 - Session 1: A", "Month 1 - Session 2: B"]) == [[0, 1]])
    }

    /// A catalog plan to enrol in like Zmash's (D156): its sessions in order and in weeks, and who it's from.
    @Test func catalogPlanAsATrainingPlan() {
        func entry(_ name: String) -> WorkoutCatalogFile.Entry {
            let w = Workout(id: "zc/ftp-builder/" + WorkoutCatalogFile.slug(name), name: name, summary: "", steps: [.init(1800, .steady(0.7))])
            return .init(workout: w, collection: "FTP Builder", author: "Zwift (via whatsonzwift.com)", category: .endurance)
        }
        let plan = WorkoutCatalogFile.trainingPlan(collection: "FTP Builder", goal: .build, sessions: [
            entry("Week 2 - Day 1 - C"), entry("Week 1 - Day 3 - B"), entry("Week 1 - Day 1 - A"),
        ])
        #expect(plan.id == "zc-ftp-builder")
        #expect(plan.weeks == [[.workout("zc/ftp-builder/week-1-day-1-a"), .workout("zc/ftp-builder/week-1-day-3-b")],
                               [.workout("zc/ftp-builder/week-2-day-1-c")]])
        #expect(plan.author == "Zwift" && !plan.isZmash)
        #expect(plan.summary.hasPrefix("2 weeks, 2 rides a week, from Zwift."))
        #expect(TrainingPlans.all.allSatisfy { $0.isZmash })
    }

    @Test func sessionTitlesDropTheWeekAndDay() {
        #expect(WorkoutCatalogFile.sessionTitle("Week 1 - Day 2 - HIT 45sec #1") == "HIT 45sec #1")
        #expect(WorkoutCatalogFile.sessionTitle("Week 0 Prep - 1. No Nonsense") == "No Nonsense")
        #expect(WorkoutCatalogFile.sessionTitle("Month 1 - Session 3: Low Cadence Zone 3 Steps") == "Low Cadence Zone 3 Steps")
        #expect(WorkoutCatalogFile.sessionTitle("Day 5 - 40/20's #1") == "40/20's #1")
        #expect(WorkoutCatalogFile.sessionTitle("#01-DPC Spin Ups") == "DPC Spin Ups")
        #expect(WorkoutCatalogFile.sessionTitle("10. Tabata - Set 2") == "Tabata - Set 2")
        #expect(WorkoutCatalogFile.sessionTitle("20-20-20") == "20-20-20")
        #expect(WorkoutCatalogFile.sessionTitle("Stage 11") == "Stage 11")
        #expect(WorkoutCatalogFile.sessionTitle("Red Unicorn") == "Red Unicorn")
    }

    @Test func slugs() {
        #expect(WorkoutCatalogFile.slug("Zwift Academy 2018") == "zwift-academy-2018")
        #expect(WorkoutCatalogFile.slug("Leandro Messineo's Poison Dart Frog Intervals") == "leandro-messineo-s-poison-dart-frog-intervals")
        #expect(WorkoutCatalogFile.slug("L'Étape du Tour") == "l-etape-du-tour")
    }
}
