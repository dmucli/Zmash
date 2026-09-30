import Foundation

// MARK: - Zmash's library, grown (D167)

public extension WorkoutLibrary {
    /// Zmash's own workouts beyond the first ones: families of sessions from general training practice (sweet spot
    /// blocks, over-unders, 30/30s, ladders, pyramids, spin-ups, big-gear work, climbing repeats, tests), at the lengths
    /// people ride, from 30 minutes to 2 hours. Every structure, name and description is written here. A big library
    /// showed which kinds and lengths matter; none of its workouts is copied or reworked.
    static let families: [Workout] = WorkoutFamilies.endurance + WorkoutFamilies.tempo + WorkoutFamilies.threshold
        + WorkoutFamilies.vo2 + WorkoutFamilies.sprints + WorkoutFamilies.tests
}

enum WorkoutFamilies {
    typealias S = Workout.Step

    // MARK: Pieces

    static func warm(_ minutes: Int) -> S { S(minutes * 60, .ramp(0.45, 0.75), "Warm-up") }
    /// A gentler warm-up, for rides that stay easy.
    static func softWarm(_ minutes: Int) -> S { S(minutes * 60, .ramp(0.45, 0.65), "Warm-up") }
    static func cool(_ minutes: Int) -> S { S(minutes * 60, .ramp(0.6, 0.4), "Cool-down") }
    static func easy(_ seconds: Int) -> S { S(seconds, .steady(0.5), "Easy") }
    static func z2(_ seconds: Int, cadence: ClosedRange<Int>? = nil) -> S {
        S(seconds, .steady(0.66), cadence == nil ? "Endurance" : "Fast pedalling", cadence: cadence)
    }
    static func on(_ seconds: Int, _ f: Double, _ label: String, cadence: ClosedRange<Int>? = nil, grade: Double? = nil) -> S {
        S(seconds, .steady(f), label, cadence: cadence, grade: grade)
    }

    /// `n` goes at `work`, `rest` between them (not after the last). `numbered`: the first step of each says which it is
    /// ("Threshold 2/4"); off for what isn't counted (spin-ups in a steady ride, the sets around numbered efforts).
    static func reps(_ n: Int, _ work: [S], rest: [S], numbered: Bool = true) -> [S] {
        (1...n).flatMap { i in
            var unit = work
            if numbered { unit[0].label += " \(i)/\(n)" }
            return unit + (i < n ? rest : [])
        }
    }

    /// `n` efforts of `seconds` at `f`, `rest` seconds easy between.
    static func efforts(_ n: Int, _ seconds: Int, _ f: Double, _ label: String, rest: Int, cadence: ClosedRange<Int>? = nil,
                        grade: Double? = nil) -> [S] {
        reps(n, [on(seconds, f, label, cadence: cadence, grade: grade)], rest: [easy(rest)])
    }

    static func w(_ id: String, _ name: String, _ category: Workout.Category, _ summary: String, _ steps: [S]) -> Workout {
        Workout(id: id, name: name, summary: summary, steps: steps, category: category)
    }

    // MARK: Endurance

    static let endurance: [Workout] = [
        w("endurance-30", "Endurance 30", .endurance, "Half an hour of steady Z2, for a day with little time and no need to hurt.",
          [softWarm(5), z2(22 * 60), cool(3)]),
        w("endurance-60", "Endurance 60", .endurance, "An hour of steady Z2: the ride most weeks need more of.",
          [softWarm(5), z2(50 * 60), cool(5)]),
        w("endurance-120", "Endurance 2 h", .endurance, "Two hours steady. Bring a bottle, and something to watch.",
          [softWarm(10), z2(105 * 60), cool(5)]),
        w("recovery-45", "Recovery 45", .endurance,
          "Very easy, with three minutes of quick pedalling to loosen up. The day after a hard one.",
          [S(12 * 60, .steady(0.5), "Easy"), S(60, .steady(0.52), "Quick pedalling", cadence: 95...105),
           S(12 * 60, .steady(0.5), "Easy"), S(60, .steady(0.52), "Quick pedalling", cadence: 95...105),
           S(12 * 60, .steady(0.5), "Easy"), S(60, .steady(0.52), "Quick pedalling", cadence: 95...105),
           S(6 * 60, .steady(0.5), "Easy")]),
        w("spinups-45", "Endurance with spin-ups 45", .endurance,
          "Steady Z2 with a minute of fast pedalling every five. It smooths your stroke without adding load.",
          [softWarm(8)] + reps(6, [z2(4 * 60), z2(60, cadence: 110...120)], rest: [], numbered: false) + [cool(5)]),
        w("spinups-60", "Endurance with spin-ups 60", .endurance,
          "An hour of Z2, a minute of 110–120 rpm every five. Stay seated and keep the hips still.",
          [softWarm(10)] + reps(8, [z2(4 * 60), z2(60, cadence: 110...120)], rest: [], numbered: false) + [z2(5 * 60), cool(5)]),
        w("endurance-tempo-60", "Endurance with tempo 60", .endurance,
          "Z2 with three 6-minute touches of tempo: base work that doesn't feel like nothing.",
          [softWarm(10), z2(10 * 60)] + reps(3, [on(6 * 60, 0.82, "Tempo")], rest: [z2(4 * 60)]) + [z2(9 * 60), cool(5)]),
        w("endurance-tempo-90", "Endurance with tempo 90", .endurance,
          "Ninety minutes of Z2 with four 8-minute tempo blocks. Eat something halfway.",
          [softWarm(10), z2(15 * 60)] + reps(4, [on(8 * 60, 0.82, "Tempo")], rest: [z2(6 * 60)]) + [z2(10 * 60), cool(5)]),
        w("endurance-tempo-120", "Endurance with tempo 2 h", .endurance,
          "Two hours, four of them tempo blocks of 12 minutes. A long Sunday, indoors.",
          [softWarm(10), z2(20 * 60)] + reps(4, [on(12 * 60, 0.82, "Tempo")], rest: [z2(8 * 60)]) + [z2(13 * 60), cool(5)]),
        w("rolling-60", "Rolling roads 60", .endurance,
          "Easy and brisk by turns, three minutes and two, like a road that never quite flattens.",
          [softWarm(10)] + reps(9, [on(3 * 60, 0.62, "Easy roads"), on(2 * 60, 0.78, "Brisk")], rest: [], numbered: false) + [cool(5)]),
        w("rolling-90", "Rolling roads 90", .endurance,
          "An hour and a half of easy and brisk by turns. Shift for the brisk bits as you would for a rise.",
          [softWarm(10)] + reps(15, [on(3 * 60, 0.62, "Easy roads"), on(2 * 60, 0.78, "Brisk")], rest: [], numbered: false) + [cool(5)]),
        w("endurance-finish-90", "Endurance with a strong finish", .endurance,
          "Steady Z2, then 20 minutes of tempo on tired legs: the end of a long ride, without the long ride.",
          [softWarm(10), z2(55 * 60), on(20 * 60, 0.84, "Strong finish"), cool(5)]),
    ]

    // MARK: Tempo and sweet spot

    static let tempo: [Workout] = [
        w("tempo-30", "Tempo 30", .tempo, "Two 8-minute tempo blocks in half an hour. Short, and still worth it.",
          [warm(6)] + efforts(2, 8 * 60, 0.85, "Tempo", rest: 3 * 60) + [cool(3)]),
        w("sweetspot-30", "Sweet spot 30", .tempo, "Two 9-minute blocks at 90 %, for when half an hour is all there is.",
          [warm(6)] + efforts(2, 9 * 60, 0.9, "Sweet spot", rest: 2 * 60) + [cool(4)]),
        w("tempo-4x10", "Tempo 4 × 10", .tempo, "Four 10-minute blocks at 85 %. Steady breathing, a gear you can turn.",
          [warm(10)] + efforts(4, 10 * 60, 0.85, "Tempo", rest: 3 * 60) + [cool(5)]),
        w("tempo-40", "Tempo 40", .tempo, "Forty minutes of tempo in one go. It's about staying there, not going harder.",
          [warm(10), on(40 * 60, 0.82, "Tempo"), cool(5)]),
        w("tempo-2x30", "Tempo 2 × 30", .tempo, "Two half hours at tempo. Long-ride fitness, in less time than a long ride.",
          [warm(10)] + efforts(2, 30 * 60, 0.83, "Tempo", rest: 5 * 60) + [cool(5)]),
        w("sweetspot-4x8", "Sweet spot 4 × 8", .tempo, "Four 8-minute blocks at 90 %: a first taste of sweet spot.",
          [warm(8)] + efforts(4, 8 * 60, 0.9, "Sweet spot", rest: 2 * 60) + [cool(4)]),
        w("sweetspot-3x10", "Sweet spot 3 × 10", .tempo, "Three 10-minute blocks at 90 %. Hard enough to count, easy enough to finish.",
          [warm(8)] + efforts(3, 10 * 60, 0.9, "Sweet spot", rest: 3 * 60) + [cool(4)]),
        w("sweetspot-4x10", "Sweet spot 4 × 10", .tempo, "Forty minutes of sweet spot in four pieces. A good hour's work.",
          [warm(10)] + efforts(4, 10 * 60, 0.9, "Sweet spot", rest: 4 * 60) + [cool(5)]),
        w("sweetspot-5x10", "Sweet spot 5 × 10", .tempo, "Fifty minutes at 90 %, in five. The fifth is the one that does it.",
          [warm(10)] + efforts(5, 10 * 60, 0.9, "Sweet spot", rest: 4 * 60) + [cool(5)]),
        w("sweetspot-3x20", "Sweet spot 3 × 20", .tempo, "An hour at sweet spot in three blocks. For when 2 × 20 has become easy.",
          [warm(10)] + efforts(3, 20 * 60, 0.89, "Sweet spot", rest: 5 * 60) + [cool(5)]),
        w("sweetspot-2x30", "Sweet spot 2 × 30", .tempo, "Two half hours at 88 %. Steady nerves, steady power.",
          [warm(10)] + efforts(2, 30 * 60, 0.88, "Sweet spot", rest: 8 * 60) + [cool(5)]),
        w("sweetspot-kicks-2x15", "Sweet spot with kicks 2 × 15", .tempo,
          "Sweet spot with a 15-second kick every three minutes, like holding a wheel that keeps surging.",
          [warm(10)] + reps(2, reps(5, [on(165, 0.88, "Sweet spot"), on(15, 1.2, "Kick")], rest: [], numbered: false), rest: [easy(5 * 60)]) + [cool(5)]),
        w("sweetspot-kicks-3x12", "Sweet spot with kicks 3 × 12", .tempo,
          "Three sweet spot blocks, each with a kick every three minutes. Settle straight back after each one.",
          [warm(10)] + reps(3, reps(4, [on(165, 0.88, "Sweet spot"), on(15, 1.2, "Kick")], rest: [], numbered: false), rest: [easy(4 * 60)]) + [cool(5)]),
        w("sweetspot-ladder-45", "Sweet spot ladder 6-8-10", .tempo,
          "Blocks of 6, 8 and 10 minutes at 90 %: each longer than the last, all the same power.",
          [warm(8), on(6 * 60, 0.9, "Sweet spot 6′"), easy(3 * 60), on(8 * 60, 0.9, "Sweet spot 8′"), easy(3 * 60),
           on(10 * 60, 0.9, "Sweet spot 10′"), cool(5)]),
        w("sweetspot-ladder-75", "Sweet spot ladder 8-10-12-14", .tempo,
          "Four blocks at 90 %, two minutes longer each time. Start as if the last one is the first.",
          [warm(10), on(8 * 60, 0.9, "Sweet spot 8′"), easy(4 * 60), on(10 * 60, 0.9, "Sweet spot 10′"), easy(4 * 60),
           on(12 * 60, 0.9, "Sweet spot 12′"), easy(4 * 60), on(14 * 60, 0.9, "Sweet spot 14′"), cool(5)]),
        w("buildups-3x12", "Build-ups 3 × 12", .tempo,
          "Each block climbs from tempo through sweet spot to just under threshold. Pace the start, finish strong.",
          [warm(10)] + reps(3, [on(4 * 60, 0.85, "Tempo"), on(4 * 60, 0.9, "Sweet spot"), on(4 * 60, 0.95, "Near threshold")],
                            rest: [easy(4 * 60)]) + [cool(5)]),
        w("big-gear-5x5", "Big gear 5 × 5", .tempo,
          "Five minutes at tempo in a big gear, 55–65 rpm. Strength on the bike, easy on the heart.",
          [warm(10)] + efforts(5, 5 * 60, 0.82, "Big gear", rest: 3 * 60, cadence: 55...65) + [cool(5)]),
        w("big-gear-sweetspot-4x8", "Big gear sweet spot 4 × 8", .tempo,
          "Sweet spot at 60–70 rpm. Keep the upper body quiet and push through the whole stroke.",
          [warm(10)] + efforts(4, 8 * 60, 0.88, "Big gear", rest: 4 * 60, cadence: 60...70) + [cool(5)]),
        w("tempo-cadence-3x12", "Tempo cadence changes 3 × 12", .tempo,
          "Tempo that switches every two minutes between a heavy gear and a quick spin, at the same power.",
          [warm(10)] + reps(3, reps(3, [on(120, 0.8, "Heavy gear", cadence: 70...75), on(120, 0.8, "Quick spin", cadence: 95...100)],
                                    rest: [], numbered: false), rest: [easy(4 * 60)]) + [cool(5)]),
        w("long-climbs-2x20", "Two long climbs", .tempo,
          "Twenty minutes up a steady 4 % slope, twice. The trainer rides the road; you find the rhythm.",
          [warm(10)] + efforts(2, 20 * 60, 0.88, "Climb", rest: 8 * 60, grade: 4) + [cool(5)]),
    ]

    // MARK: Threshold

    static let threshold: [Workout] = [
        w("threshold-3x5", "Threshold 3 × 5", .threshold, "Three 5-minute efforts at FTP in half an hour. Quick, and honest.",
          [warm(6)] + efforts(3, 5 * 60, 1.0, "Threshold", rest: 2 * 60) + [cool(3)]),
        w("threshold-5x6", "Threshold 5 × 6", .threshold, "Five 6-minute efforts at FTP, two minutes between. The rests are short on purpose.",
          [warm(8)] + efforts(5, 6 * 60, 1.0, "Threshold", rest: 2 * 60) + [cool(4)]),
        w("threshold-30", "Threshold 30", .threshold, "Thirty minutes at 95 % of FTP, in one piece. Settle in, and don't start too fast.",
          [warm(10), on(30 * 60, 0.95, "Threshold"), cool(5)]),
        w("threshold-3x10", "Threshold 3 × 10", .threshold, "Three 10-minute efforts at FTP. The classic, and for good reason.",
          [warm(10)] + efforts(3, 10 * 60, 1.0, "Threshold", rest: 5 * 60) + [cool(5)]),
        w("threshold-2x20", "Threshold 2 × 20", .threshold, "Two 20-minute efforts at 97 %. Long enough that pacing is the whole game.",
          [warm(10)] + efforts(2, 20 * 60, 0.97, "Threshold", rest: 8 * 60) + [cool(5)]),
        w("threshold-4x10", "Threshold 4 × 10", .threshold, "Forty minutes at FTP in four. A big session: come to it rested.",
          [warm(10)] + efforts(4, 10 * 60, 1.0, "Threshold", rest: 5 * 60) + [cool(5)]),
        w("threshold-5x8", "Threshold 5 × 8", .threshold, "Five 8-minute efforts at FTP, four minutes between.",
          [warm(10)] + efforts(5, 8 * 60, 1.0, "Threshold", rest: 4 * 60) + [cool(5)]),
        w("threshold-3x15", "Threshold 3 × 15", .threshold, "Forty-five minutes at 97 % in three. The middle one is where it's won.",
          [warm(10)] + efforts(3, 15 * 60, 0.97, "Threshold", rest: 6 * 60) + [cool(5)]),
        w("threshold-3x20", "Threshold 3 × 20", .threshold, "An hour at 95 % in three blocks. For a long climb or a time trial ahead.",
          [warm(10)] + efforts(3, 20 * 60, 0.95, "Threshold", rest: 8 * 60) + [cool(5)]),
        w("over-under-4x6", "Over-unders 4 × 6", .threshold,
          "Two minutes just under threshold, one just over, twice in each block. Learn to recover while still working.",
          [warm(10)] + reps(4, reps(2, [on(120, 0.95, "Under"), on(60, 1.08, "Over")], rest: [], numbered: false), rest: [easy(4 * 60)]) + [cool(5)]),
        w("over-under-3x12", "Over-unders 3 × 12", .threshold,
          "Twelve-minute blocks of 2 minutes under, 1 over. The overs get harder; the unders don't get easier.",
          [warm(10)] + reps(3, reps(4, [on(120, 0.92, "Under"), on(60, 1.08, "Over")], rest: [], numbered: false), rest: [easy(5 * 60)]) + [cool(5)]),
        w("over-under-2x20", "Over-unders 2 × 20", .threshold,
          "Two 20-minute blocks of 3 minutes under threshold and 1 over. The race-pace session.",
          [warm(10)] + reps(2, reps(5, [on(180, 0.93, "Under"), on(60, 1.07, "Over")], rest: [], numbered: false), rest: [easy(8 * 60)]) + [cool(5)]),
        w("over-under-4x12", "Over-unders 4 × 12", .threshold,
          "Four blocks of 2 under, 1 over. A lot of time near threshold, and the changes keep it honest.",
          [warm(10)] + reps(4, reps(4, [on(120, 0.92, "Under"), on(60, 1.08, "Over")], rest: [], numbered: false), rest: [easy(5 * 60)]) + [cool(5)]),
        w("surges-2x16", "Threshold with surges 2 × 16", .threshold,
          "Threshold with 30 seconds at 125 % every four minutes. Close the gap, then keep the pace.",
          [warm(10)] + reps(2, reps(4, [on(210, 0.95, "Threshold"), on(30, 1.25, "Surge")], rest: [], numbered: false), rest: [easy(6 * 60)]) + [cool(5)]),
        w("threshold-pyramid-3", "Threshold pyramid 3-6-9-6-3", .threshold,
          "Up to nine minutes at FTP and back down. The way down is easier on the head than the way up.",
          [warm(10), on(3 * 60, 1.0, "Threshold 3′"), easy(3 * 60), on(6 * 60, 1.0, "Threshold 6′"), easy(3 * 60),
           on(9 * 60, 1.0, "Threshold 9′"), easy(3 * 60), on(6 * 60, 1.0, "Threshold 6′"), easy(3 * 60),
           on(3 * 60, 1.0, "Threshold 3′"), cool(5)]),
        w("threshold-pyramid-4", "Threshold pyramid 4-8-12-8-4", .threshold,
          "A bigger pyramid at FTP: twelve minutes at the top, four on either side.",
          [warm(10), on(4 * 60, 1.0, "Threshold 4′"), easy(4 * 60), on(8 * 60, 1.0, "Threshold 8′"), easy(4 * 60),
           on(12 * 60, 1.0, "Threshold 12′"), easy(4 * 60), on(8 * 60, 1.0, "Threshold 8′"), easy(4 * 60),
           on(4 * 60, 1.0, "Threshold 4′"), cool(5)]),
        w("hard-starts-4x8", "Hard starts 4 × 8", .threshold,
          "Each effort opens with 30 seconds at 150 %, then settles at threshold. A race start, four times.",
          [warm(10)] + reps(4, [on(30, 1.5, "Hard start"), on(450, 0.98, "Threshold")], rest: [easy(4 * 60)]) + [cool(5)]),
        w("threshold-descending", "Descending threshold 12-10-8-6", .threshold,
          "Each effort shorter and a little harder than the last, from 97 % to 105 %.",
          [warm(10), on(12 * 60, 0.97, "Threshold 12′"), easy(4 * 60), on(10 * 60, 1.0, "Threshold 10′"), easy(4 * 60),
           on(8 * 60, 1.02, "Threshold 8′"), easy(4 * 60), on(6 * 60, 1.05, "Threshold 6′"), cool(5)]),
        w("long-climbs-3x10", "Long climbs 3 × 10", .threshold,
          "Three 10-minute climbs at 5 %, around threshold. The trainer rides the slope: pick a gear and hold it.",
          [warm(10)] + efforts(3, 10 * 60, 0.95, "Climb", rest: 5 * 60, grade: 5) + [cool(5)]),
    ]

    // MARK: VO₂max

    static let vo2: [Workout] = [
        w("vo2-30", "VO₂max 30", .vo2, "Five 2-minute efforts at 115 % in half an hour. Hard, and over quickly.",
          [warm(6)] + efforts(5, 2 * 60, 1.15, "VO₂max", rest: 2 * 60) + [cool(4)]),
        w("vo2-40-20-short", "40/20s 30", .vo2, "Two sets of six: 40 seconds at 120 %, 20 easy. A short, sharp half hour.",
          [warm(6)] + reps(2, reps(6, [on(40, 1.2, "40/20"), easy(20)], rest: []), rest: [easy(3 * 60)], numbered: false) + [cool(4)]),
        w("vo2-5x4", "VO₂max 5 × 4", .vo2, "Five 4-minute efforts at 112 %, as long again easy between.",
          [warm(10)] + efforts(5, 4 * 60, 1.12, "VO₂max", rest: 4 * 60) + [cool(5)]),
        w("vo2-6x3", "VO₂max 6 × 3", .vo2, "Six 3-minute efforts at 115 %. Count them down, not up.",
          [warm(10)] + efforts(6, 3 * 60, 1.15, "VO₂max", rest: 3 * 60) + [cool(5)]),
        w("vo2-4x5", "VO₂max 4 × 5", .vo2, "Four 5-minute efforts at 110 %. Longer, a touch lower: time at your ceiling.",
          [warm(10)] + efforts(4, 5 * 60, 1.1, "VO₂max", rest: 5 * 60) + [cool(5)]),
        w("vo2-5x5", "VO₂max 5 × 5", .vo2, "Five 5-minute efforts at 108 %. A big one: eat well the day before.",
          [warm(10)] + efforts(5, 5 * 60, 1.08, "VO₂max", rest: 5 * 60) + [cool(5)]),
        w("vo2-3x6", "VO₂max 3 × 6", .vo2, "Three 6-minute efforts at 108 %. The last two minutes of each are the point.",
          [warm(10)] + efforts(3, 6 * 60, 1.08, "VO₂max", rest: 6 * 60) + [cool(5)]),
        w("vo2-30-30-2x10", "30/30s 2 × 10", .vo2, "Two sets of ten: 30 seconds at 120 %, 30 easy. Keep the easy ones truly easy.",
          [warm(10)] + reps(2, reps(10, [on(30, 1.2, "30/30"), easy(30)], rest: []), rest: [easy(5 * 60)], numbered: false) + [cool(5)]),
        w("vo2-30-30-3x12", "30/30s 3 × 12", .vo2, "Three sets of twelve 30/30s. The third set is the one that counts.",
          [warm(10)] + reps(3, reps(12, [on(30, 1.2, "30/30"), easy(30)], rest: []), rest: [easy(5 * 60)], numbered: false) + [cool(5)]),
        w("vo2-40-20-4x6", "40/20s 4 × 6", .vo2, "Four sets of six: 40 seconds at 120 %, 20 to breathe. The short rests are the work.",
          [warm(10)] + reps(4, reps(6, [on(40, 1.2, "40/20"), easy(20)], rest: []), rest: [easy(4 * 60)], numbered: false) + [cool(5)]),
        w("vo2-30-15", "30/15s 3 × 13", .vo2, "Three sets of thirteen: 30 seconds at 115 %, 15 easy. Your breathing never quite settles.",
          [warm(10)] + reps(3, reps(13, [on(30, 1.15, "30/15"), easy(15)], rest: []), rest: [easy(3 * 60)], numbered: false) + [cool(5)]),
        w("vo2-pyramid", "VO₂max pyramid 1-2-3-4-3-2-1", .vo2,
          "From one minute to four and back, as long again easy after each. Harder at the ends, longer in the middle.",
          [warm(10), on(60, 1.2, "VO₂max 1′"), easy(60), on(120, 1.15, "VO₂max 2′"), easy(120), on(180, 1.12, "VO₂max 3′"),
           easy(180), on(240, 1.1, "VO₂max 4′"), easy(240), on(180, 1.12, "VO₂max 3′"), easy(180),
           on(120, 1.15, "VO₂max 2′"), easy(120), on(60, 1.2, "VO₂max 1′"), cool(5)]),
        w("vo2-descending", "Descending VO₂max 5-4-3-2-1", .vo2,
          "Each effort a minute shorter and a little harder, from 108 % to 120 %.",
          [warm(10), on(300, 1.08, "VO₂max 5′"), easy(180), on(240, 1.1, "VO₂max 4′"), easy(180), on(180, 1.12, "VO₂max 3′"),
           easy(180), on(120, 1.15, "VO₂max 2′"), easy(180), on(60, 1.2, "VO₂max 1′"), cool(5)]),
        w("microbursts-3x10", "Microbursts 3 × 10", .vo2,
          "Ten minutes of 15 seconds on, 15 off, three times. Snappy, then easy; never quite either.",
          [warm(10)] + reps(3, reps(20, [on(15, 1.4, "Burst"), easy(15)], rest: []), rest: [easy(5 * 60)], numbered: false) + [cool(5)]),
        w("steep-repeats-6x3", "Steep repeats 6 × 3′", .vo2,
          "Six 3-minute climbs at 8 %, around 115 % of FTP. Stay seated if you can; stand if you must.",
          [warm(10)] + efforts(6, 3 * 60, 1.15, "Steep climb", rest: 3 * 60, grade: 8) + [cool(5)]),
        w("vo2-6x5-long", "VO₂max 6 × 5 with endurance", .vo2,
          "Six 5-minute efforts at 108 %, then a quarter of an hour of Z2 to finish the job.",
          [warm(15)] + efforts(6, 5 * 60, 1.08, "VO₂max", rest: 5 * 60) + [easy(5 * 60), z2(15 * 60), cool(5)]),
    ]

    // MARK: Sprints and anaerobic

    static let sprints: [Workout] = [
        w("anaerobic-4x2", "2-minute efforts 4 × 2", .sprints, "Four 2-minute efforts at 125 %. They hurt by the end, as they should.",
          [warm(10)] + efforts(4, 2 * 60, 1.25, "Effort", rest: 4 * 60) + [cool(5)]),
        w("anaerobic-8x1", "1-minute efforts 8 × 1", .sprints, "Eight minutes at 135 %, three minutes easy between. Leave nothing for the last one.",
          [warm(10)] + efforts(8, 60, 1.35, "Effort", rest: 3 * 60) + [cool(5)]),
        w("standing-starts-6", "Standing starts 6 × 15 s", .sprints,
          "From almost stopped, in a heavy gear, 15 seconds all out. Power off the line.",
          [warm(10)] + efforts(6, 15, 2.0, "Standing start", rest: 225, cadence: 50...90) + [cool(5)]),
        w("sprint-sets-3x4", "Sprint sets 3 × 4", .sprints,
          "Three sets of four 15-second sprints, nearly two minutes easy after each. Snap, then spin.",
          [warm(10)] + reps(3, reps(4, [on(15, 1.8, "Sprint"), easy(105)], rest: []), rest: [easy(5 * 60)], numbered: false) + [cool(5)]),
        w("lead-outs-5", "Lead-outs 5 × 1′15", .sprints,
          "A minute on the front at 105 %, then 15 seconds all out: a lead-out, then the sprint.",
          [warm(10)] + reps(5, [on(60, 1.05, "Lead-out"), on(15, 1.8, "Sprint")], rest: [easy(4 * 60)]) + [cool(5)]),
        w("race-attacks", "Race attacks", .sprints,
          "Steady riding broken by 20-second attacks, then two hard efforts to finish. A race, in an hour.",
          [warm(10)] + reps(5, [on(220, 0.75, "Steady"), on(20, 1.5, "Attack")], rest: [], numbered: false) + [easy(5 * 60)]
              + efforts(2, 5 * 60, 1.05, "Final effort", rest: 3 * 60) + [z2(5 * 60), cool(5)]),
        w("sprints-long-ride", "Sprints in a long ride", .sprints,
          "Eighty minutes of Z2 with a 12-second sprint every seven. Sprint fresh, ride easy.",
          [softWarm(10)] + reps(10, [z2(408), on(12, 1.8, "Sprint")], rest: [], numbered: false) + [z2(8 * 60), cool(5)]),
    ]

    // MARK: Tests

    static let tests: [Workout] = [
        w("ftp-test-20", "20-minute FTP test", .tests,
          "Twenty minutes as hard as you can hold, after a warm-up that opens the legs. Your FTP is 95 % of it.",
          [warm(10), on(5 * 60, 1.05, "Opener"), easy(10 * 60),
           S(20 * 60, .free, "Test: as hard as you can hold for 20 minutes"), cool(10)]),
    ]
}
