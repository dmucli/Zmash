import SwiftUI
import ZmashKit

/// A workout's details (D163), opened from its card in place of the grid: what it is (its kind, where it's from, its
/// name, description, shape and figures) as the hero, beside what it's for and how to ride it; then what you'll do,
/// step by step in words, and its time in each zone. The page's bar below starts it.
struct WorkoutDetail: View {
    let workout: Workout
    /// Where it's from: "Zmash", "Zwift · FTP Builder", "intervals.icu", "Your workout".
    let source: String
    var compact = false
    @Environment(Preferences.self) private var prefs

    private var kind: Workout.Category { workout.inferredCategory }
    private var ftp: Double { Double(prefs.ftp) }

    var body: some View {
        ScrollView {
            // Two columns, each as long as it needs: what it is and what you'll do; what it's for and its zones.
            // Stacked on a phone.
            Group {
                if compact {
                    VStack(spacing: 14) {
                        hero
                        purpose
                        steps
                        zones
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            hero
                            steps
                        }
                        VStack(spacing: 14) {
                            purpose
                            zones
                        }
                        .frame(width: 400)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: What it is

    private var hero: some View {
        let load = workout.estimatedLoad(ftp: ftp)
        let zones = WorkoutOutline.zoneSeconds(workout)
        // Time at tempo or harder (zone 3 up): the work in it.
        let work = zones.dropFirst(2).reduce(0, +)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Tag(title: kind.title, color: Design.Palette.fg1)
                Text(source).monoLabel().foregroundStyle(Design.Palette.fg3).lineLimit(1)
            }
            Text(workout.name).textStyle(.display, size: compact ? 30 : 40).foregroundStyle(Design.Palette.fg1)
                .lineLimit(2).minimumScaleFactor(0.7)
                .padding(.top, 12)
            if !workout.summary.isEmpty {
                Text(workout.summary).font(Design.Font.sans(15)).foregroundStyle(Design.Palette.fg2)
                    .lineSpacing(3).lineLimit(8)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            WorkoutStrip(workout: workout.drawable).frame(maxWidth: .infinity).frame(height: compact ? 90 : 130)
                .padding(.top, 24)
            if !workout.isRampTest { ticks.padding(.top, 6) }
            // The work's minutes give way first when the figures don't fit (a phone).
            ViewThatFits(in: .horizontal) {
                figures(load: load, work: work)
                figures(load: load, work: 0)
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(compact ? 22 : 28)
        .glassCard()
    }

    private func figures(load: Training.Load, work: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 24) {
            if workout.isRampTest {
                HeroFigure(value: "~20", unit: "min, until you stop", hero: false)
            } else {
                HeroFigure(value: "\(workout.duration / 60)", unit: "min", hero: false)
                HeroFigure(value: "\(Int(load.tss.rounded()))", unit: "TSS", hero: false)
                HeroFigure(value: String(format: "%.2f", load.intensityFactor).replacingOccurrences(of: "0.", with: "."), unit: "IF", hero: false)
                if work >= 60 { HeroFigure(value: "\(work / 60)", unit: "min of work", hero: false) }
            }
        }
    }

    /// The strip's time: the start, the middle and the end.
    private var ticks: some View {
        let d = workout.duration
        return HStack {
            Text("0")
            Spacer()
            Text(TimeFormat.clock(d / 2))
            Spacer()
            Text(TimeFormat.clock(d))
        }
        .font(Design.Font.mono(11)).foregroundStyle(Design.Palette.fg3)
        .accessibilityHidden(true)
    }

    // MARK: What it's for

    private var purpose: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("What it's for")
            Text(kind.purpose).font(Design.Font.sans(17, weight: 500)).foregroundStyle(Design.Palette.fg1)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            SectionHeader("How to ride it").padding(.top, 12)
            Text(kind.advice).font(Design.Font.body).foregroundStyle(Design.Palette.fg2)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if !notes.isEmpty {
                SectionHeader("On the trainer").padding(.top, 12)
                ForEach(notes, id: \.self) { note in
                    Text(note).font(Design.Font.body).foregroundStyle(Design.Palette.fg2)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 22)
    }

    /// What the trainer will do differently: climbs in the workout, cadences asked for, steps with no target.
    private var notes: [String] {
        let climbs = workout.steps.filter { $0.grade != nil }.count
        let cadences = workout.steps.contains { $0.cadence != nil }
        let free = workout.steps.filter { $0.target == .free }.count
        var out: [String] = []
        if climbs > 0 {
            out.append("\(climbs == 1 ? "One step is a climb" : "\(climbs) steps are climbs"): the trainer rides the slope, even in ERG, and you shift as you would outside.")
        }
        if cadences { out.append("Some steps ask for a cadence, as the outline shows.") }
        if free > 0 { out.append("\(free == 1 ? "One step has" : "\(free) steps have") no target: ride \(free == 1 ? "it" : "them") as you feel.") }
        return out
    }

    // MARK: What you'll do

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What you'll do")
            ForEach(Array(WorkoutOutline.outline(workout, ftp: ftp).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(Design.Zone.color(forFTPFraction: line.intensity)).frame(width: 10, height: 10)
                    Text(line.text).font(Design.Font.body).foregroundStyle(Design.Palette.fg1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if workout.isRampTest {
                Text("Until you can't hold the step. Your FTP is 75 % of your best minute.")
                    .font(Design.Font.body).foregroundStyle(Design.Palette.fg2)
            }
            Text("Watts at your FTP of \(prefs.ftp) W.").font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 22)
    }

    @ViewBuilder
    private var zones: some View {
        // A ramp test's steps run until you stop, so its zones would be a guess.
        if !workout.isRampTest {
            ZonesCard(entry: ZoneStore.Entry(ftp: prefs.ftp, maxHR: nil, power: WorkoutOutline.zoneSeconds(workout), heart: nil))
        }
    }
}

extension Workout.Category {
    /// What a kind of workout trains (D163), for its details.
    var purpose: String {
        switch self {
        case .endurance: "Your aerobic base: the engine everything else runs on. Long, easy riding makes harder efforts cost less, and you recover from it quickly."
        case .tempo: "Long, steady blocks just under your threshold. They raise your FTP and your staying power, and give a lot of training for the fatigue they cost."
        case .threshold: "Efforts at your FTP, the power you can hold for about an hour. They raise it, and ready you for long climbs and time trials."
        case .vo2: "Short, very hard efforts near your maximum aerobic power. They raise the ceiling your threshold sits under."
        case .sprints: "Efforts from a few seconds to a minute, with long rests: the snap for attacks, sprints and short, steep hills."
        case .tests: "Measures your FTP, so your zones, targets and plans fit you."
        }
    }

    /// How it should feel, and where it goes in a week.
    var advice: String {
        switch self {
        case .endurance: "Easy enough to hold a conversation. Good on any day, and between hard ones."
        case .tempo: "Hard but sustainable: breathing deep, still in control. Two or three a week at most, with an easy day after."
        case .threshold: "Steady and focused: the last minutes of each effort should feel hard. Come to it rested, and take an easy day after."
        case .vo2: "Close to all out by the end of each effort. Only when you're fresh, and rest the day after."
        case .sprints: "All out on every one, and recover fully between. Stop when you can't match the first ones."
        case .tests: "Ride it rested, after an easy day. When it's done, Zmash offers you the new FTP."
        }
    }
}
