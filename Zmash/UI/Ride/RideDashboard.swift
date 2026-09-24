import SwiftUI
import ZmashKit

// MARK: - Configuration (phase 3: UI customisation)

enum DisplayMetric: String, Codable, CaseIterable, Identifiable {
    case speed, power, cadence, time, kcal, distance, climbed, heartRate

    var id: String { rawValue }
    var label: String {
        switch self {
        case .speed: "Speed"
        case .power: "Power"
        case .cadence: "Cadence"
        case .time: "Time"
        case .kcal: "Calories"
        case .distance: "Distance"
        case .climbed: "Climbed"
        case .heartRate: "Heart rate"
        }
    }
}

enum NumberStyle: String, Codable, CaseIterable {
    /// The design system's race-bib numerals: Archivo at 62 % width (D118).
    case bib
    case rounded, standard, mono

    var design: Font.Design {
        switch self {
        case .bib, .standard: .default
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

enum NumberWeight: String, Codable, CaseIterable {
    case regular, medium, semibold, bold

    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// What the ride screen shows and how (Settings → Display).
struct DisplayConfig: Codable, Equatable {
    var hero: DisplayMetric = .speed
    /// Top-left, bottom-left, top-right, bottom-right.
    var slots: [DisplayMetric] = [.power, .cadence, .time, .kcal]
    var style: NumberStyle = .bib
    var weight: NumberWeight = .semibold
    /// Hero size multiplier: 0.8 / 1.0 / 1.2.
    var heroScale: Double = 1.0
    /// Tint the gear, grade and elevation by the grade (off = ink only).
    var gradeColor = true

    static let standard = DisplayConfig()

    @MainActor
    func font(_ size: CGFloat) -> Font {
        guard style == .bib else { return .system(size: size, weight: weight.weight, design: style.design).monospacedDigit() }
        let w: Double = switch weight {
        case .regular: 500
        case .medium: 650
        case .semibold: 800
        case .bold: 900
        }
        return Design.Font.bib(size, weight: w)
    }

    func slot(_ i: Int) -> DisplayMetric { i < slots.count ? slots[i] : DisplayConfig.standard.slots[i] }
}

// MARK: - Snapshot of what's on screen

/// Everything the ride screen draws, decoupled from the live engine so Settings can preview it.
struct RideReadout {
    var speedKph: Double
    var powerW: Int?
    var cadenceRpm: Int?
    var heartRateBpm: Int? = nil
    var elapsed: Double
    var remaining: Double?
    var kcal: Double
    var distanceM: Double
    var climbedM: Double
    var grade: Double
    var gear: Int
    var gearCount: Int
    var upcomingGrades: [Double]
    var waitingForPedal: Bool

    @MainActor
    init(engine: SessionEngine) {
        speedKph = engine.speedKph
        powerW = engine.powerW
        cadenceRpm = engine.cadenceRpm
        heartRateBpm = engine.heartRateBpm
        elapsed = engine.elapsed
        remaining = engine.remaining
        kcal = engine.kcal
        distanceM = engine.distanceM
        climbedM = engine.elevationGainM
        grade = engine.terrainGrade
        gear = engine.controls.gear
        gearCount = engine.controls.gears.count
        upcomingGrades = engine.hasProfile ? engine.upcomingGrades : []
        waitingForPedal = engine.phase == .waitingForPedal
    }

    init(speedKph: Double, powerW: Int?, cadenceRpm: Int?, elapsed: Double, remaining: Double?, kcal: Double,
         distanceM: Double, climbedM: Double, grade: Double, gear: Int, gearCount: Int,
         upcomingGrades: [Double], waitingForPedal: Bool) {
        self.speedKph = speedKph
        self.powerW = powerW
        self.cadenceRpm = cadenceRpm
        self.elapsed = elapsed
        self.remaining = remaining
        self.kcal = kcal
        self.distanceM = distanceM
        self.climbedM = climbedM
        self.grade = grade
        self.gear = gear
        self.gearCount = gearCount
        self.upcomingGrades = upcomingGrades
        self.waitingForPedal = waitingForPedal
    }

    /// Plausible mid-ride values for the Settings preview.
    static let sample = RideReadout(
        speedKph: 31.4, powerW: 212, cadenceRpm: 88, elapsed: 1_462, remaining: 338, kcal: 301,
        distanceM: 12_480, climbedM: 146, grade: 3.5, gear: 14, gearCount: 24,
        upcomingGrades: TerrainGenerator.generate(duration: 1800, type: .hilly, effort: .medium, seed: 4)
            .samples(from: 1_462, to: 1_762, step: 10),
        waitingForPedal: false)

    /// (value, unit, pulses) for a metric.
    func display(_ metric: DisplayMetric, units: Units) -> (value: String, unit: String, pulse: Bool) {
        switch metric {
        case .speed:
            let v = units.speed(speedKph)
            return (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v), units.speedUnit, false)
        case .power:
            return (powerW.map(String.init) ?? "—", "w", false)
        case .cadence:
            return (cadenceRpm.map(String.init) ?? "—", "rpm", false)
        case .time:
            let unit = remaining.map { "−" + TimeFormat.clock(Int($0.rounded(.up))) } ?? "time"
            return (TimeFormat.clock(Int(elapsed)), unit, waitingForPedal)
        case .kcal:
            return (String(format: "%.0f", kcal), "kcal", false)
        case .distance:
            return (String(format: "%.1f", units.distance(distanceM)), units.distanceUnit, false)
        case .climbed:
            return (String(format: "%.0f", units.elevation(climbedM)), units.elevationUnit + " up", false)
        case .heartRate:
            return (heartRateBpm.map(String.init) ?? "—", "bpm", false)
        }
    }

    var gradeText: String { abs(grade) < 0.05 ? "0.0" : String(format: "%+.1f", grade) }
}

// MARK: - Dashboard: the Live ride (Classic, after the design system's prototype, D118)

/// What the Live ride can do when touched: pause, end, shift. Nil in previews.
struct LiveRideActions {
    var pause: () -> Void
    var end: () -> Void
    var shiftDown: () -> Void
    var shiftUp: () -> Void
}

/// Classic, as the prototype's Live ride. Always tarmac. On top, the hatch with the road ahead drawn across it and HUD
/// chips (the ride, the step or the summit, grade and time); below, the main number, three more, and the gear.
struct RideDashboard: View {
    let readout: RideReadout
    let config: DisplayConfig
    let units: Units
    let size: CGSize
    let compact: Bool
    /// The route or workout (from the band's data), for the chips.
    var plan = BandPlan()
    var riderKg: Double? = nil
    var paused = false
    var actions: LiveRideActions? = nil

    private var portrait: Bool { size.height > size.width }

    var body: some View {
        let topShare: CGFloat = compact ? 0.24 : portrait ? 0.34 : 0.38
        VStack(spacing: 0) {
            LiveTop(r: readout, c: config, units: units, plan: plan, compact: compact, tight: size.width < 1000,
                    paused: paused, actions: actions)
                .frame(height: max(150, size.height * topShare))
                .clipped()
            Rectangle().fill(Design.Tarmac.t800).frame(height: 1)
            if compact || portrait {
                stacked
            } else {
                wide
            }
        }
        .background(Design.Tarmac.t900)
        .environment(\.colorScheme, .dark)
        .environment(\.onTarmac, true)
    }

    /// Numbers beside each other, bottom-aligned, split by hairlines (landscape): 1.6 : 1 : 1 : 1 and the gear.
    private var wide: some View {
        let metricsH = size.height * 0.62
        let gearW = min(230, size.width * 0.2)
        let unit = (size.width - gearW) / (1.6 + CGFloat(sideMetrics.count))
        let hero = min(metricsH * 0.66, unit * 1.6 * 0.62) * config.heroScale
        let side = min(hero * 0.5, unit * 0.45)
        return HStack(alignment: .bottom, spacing: 0) {
            HeroCell(metric: config.hero, r: readout, c: config, units: units, size: hero, riderKg: riderKg)
                .padding(.horizontal, 32)
                .frame(width: unit * 1.6, alignment: .bottomLeading)
                .frame(maxHeight: .infinity, alignment: .bottom)
            ForEach(Array(sideMetrics.enumerated()), id: \.offset) { _, m in
                hairline
                MetricCell(metric: m, r: readout, c: config, units: units, size: side)
                    .padding(.horizontal, 22)
                    .frame(width: unit - 1, alignment: .bottomLeading)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            hairline
            GearCell(r: readout, c: config, size: side * 0.92, actions: actions, button: gearW < 220 ? 44 : 52)
                .padding(.horizontal, gearW < 220 ? 8 : 18)
                .frame(width: gearW - 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.bottom, 24)
    }

    /// Upright or narrow: the main number across, then the others in a grid, then the gear.
    private var stacked: some View {
        let hero = min(size.width * (compact ? 0.3 : 0.24), size.height * 0.2) * config.heroScale
        let side = hero * 0.5
        return VStack(alignment: .leading, spacing: compact ? 14 : 22) {
            Spacer(minLength: 0)
            HeroCell(metric: config.hero, r: readout, c: config, units: units, size: hero, riderKg: riderKg)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: compact ? 12 : 18) {
                GridRow {
                    ForEach(Array(sideMetrics.enumerated()), id: \.offset) { _, m in
                        MetricCell(metric: m, r: readout, c: config, units: units, size: side)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            GearCell(r: readout, c: config, size: side, actions: actions, horizontal: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
        .padding(.bottom, compact ? 90 : 24)
    }

    /// Three numbers beside the main one. Time is in the HUD, so it's skipped here.
    private var sideMetrics: [DisplayMetric] {
        let chosen = (0..<4).map { config.slot($0) }.filter { $0 != .time && $0 != config.hero }
        return Array(chosen.prefix(3))
    }

    private var hairline: some View { Rectangle().fill(Design.Tarmac.t800).frame(width: 1) }
}

/// The hatch with the road ahead and the HUD chips.
private struct LiveTop: View {
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let plan: BandPlan
    let compact: Bool
    /// Under 1000 pt (an iPhone on its side): chips drop their labels so they fit in one row.
    var tight = false
    let paused: Bool
    let actions: LiveRideActions?
    @Environment(Preferences.self) private var prefs

    var body: some View {
        ZStack {
            HatchFill(raised: false)
            if prefs.windBackground {
                WindBackground(speedKph: r.speedKph, paused: paused).opacity(0.6)
            }
            // The road ahead: the next few minutes of gradient as a skyline, or lane dashes on a manual ride.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if r.upcomingGrades.count > 1 {
                    ElevationStrip(grades: r.upcomingGrades, color: Design.Tarmac.bone.opacity(0.6),
                                   marker: true, fill: Design.Accent.teamBlue.opacity(0.16))
                        .frame(maxHeight: .infinity)
                        .padding(.top, compact ? 60 : 90)
                } else {
                    LaneDashes(color: Design.Tarmac.bone.opacity(0.22), thickness: 5)
                        .padding(.bottom, compact ? 30 : 60)
                }
            }
            VStack(spacing: 0) {
                chips
                Spacer(minLength: 0)
                if let actions, !compact {
                    HStack(spacing: 8) {
                        Spacer()
                        PillButton(title: paused ? "Resume" : "Pause", icon: paused ? "play" : "pause", style: .glass, action: actions.pause)
                        PillButton(title: "End ride", icon: "square", style: .tarmac, action: actions.end)
                    }
                }
            }
            .padding(.horizontal, compact ? Design.Space.gutter : 28)
            .padding(.top, compact ? 12 : 24)
            .padding(.bottom, compact ? 12 : 22)
        }
    }

    private var chips: some View {
        HStack(alignment: .top, spacing: 8) {
            rideChip
            if !compact {
                Spacer(minLength: 8)
                if let w = plan.workout { stepChip(w) } else if !tight, let route = plan.route, let summit = route.toSummitM { summitChip(route, summit) }
            }
            Spacer(minLength: 8)
            HUDChip {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !compact, !tight { Text("Grade").monoLabel().foregroundStyle(Design.Tarmac.bone2) }
                    Text(r.gradeText).font(Design.Font.bib(compact ? 26 : 32))
                        .foregroundStyle(c.gradeColor ? Design.accent(forGrade: r.grade, base: Design.Tarmac.bone) : Design.Accent.vermilion)
                }
            }
            .accessibilityElement(children: .combine)
            HUDChip {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !compact, !tight { Text("Time").monoLabel().foregroundStyle(Design.Tarmac.bone2) }
                        timeText
                    }
                    if let left = r.remaining {
                        Text("−" + TimeFormat.clock(Int(left.rounded(.up)))).font(Design.Font.mono(12)).foregroundStyle(Design.Tarmac.bone2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var timeText: some View {
        let t = Text(TimeFormat.clock(Int(r.elapsed))).font(Design.Font.mono(compact ? 18 : 22))
        // Only the waiting clock pulses; live numbers never animate.
        if r.waitingForPedal {
            t.phaseAnimator([1.0, 0.35]) { content, opacity in content.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.9) }
        } else {
            t
        }
    }

    private var rideChip: some View {
        let (n, name, detail): (Int, String, String) =
            if let route = plan.route {
                (4, route.name, route.toGoM.map { String(format: "%.1f %@ to go", units.distance($0), units.distanceUnit) } ?? "")
            } else if let w = plan.workout {
                (3, w.workout.name, w.next)
            } else {
                (2, "Free ride", String(format: "%.1f %@", units.distance(r.distanceM), units.distanceUnit))
            }
        return HUDChip(horizontal: 16) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", n)).font(Design.Font.bib(compact ? 30 : 40)).foregroundStyle(Design.Accent.vermilion)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Design.Font.sans(compact ? 15 : 17, weight: 700)).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(Design.Font.mono(12)).foregroundStyle(Design.Tarmac.bone2).lineLimit(1) }
                }
            }
        }
        .frame(maxWidth: compact ? 220 : tight ? 250 : 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func stepChip(_ w: BandPlan.WorkoutPart) -> some View {
        HUDChip {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.step + (w.intensity.map { " · \($0) %" } ?? "")).monoLabel().foregroundStyle(Design.Tarmac.bone2).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let target = w.targetW {
                            Text("Hold").font(Design.Font.sans(15, weight: 600))
                            Text("\(target)").font(Design.Font.bib(24))
                            Text("W").font(Design.Font.sans(15, weight: 600))
                        } else {
                            Text("Free").font(Design.Font.sans(15, weight: 600))
                        }
                        if let hint = w.hint, hint != .onTarget {
                            Text(hint.rawValue).monoLabel(10).foregroundStyle(Design.Accent.vermilion).padding(.leading, 4)
                        }
                    }
                }
                if let left = w.stepLeft {
                    Rectangle().fill(Design.Tarmac.t700).frame(width: 1, height: 36)
                    Text(TimeFormat.clock(Int(left.rounded(.up)))).font(Design.Font.mono(24)).foregroundStyle(Design.Accent.vermilion)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summitChip(_ route: BandPlan.RoutePart, _ summitM: Double) -> some View {
        HUDChip {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summit in").monoLabel().foregroundStyle(Design.Tarmac.bone2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", units.distance(summitM))).font(Design.Font.bib(24))
                        Text(units.distanceUnit).font(Design.Font.sans(15, weight: 600))
                    }
                }
                if let ghost = route.ghost {
                    Rectangle().fill(Design.Tarmac.t700).frame(width: 1, height: 36)
                    Text(TimeFormat.clock(Int(abs(ghost).rounded())) + (ghost >= 0 ? " ahead" : " behind"))
                        .font(Design.Font.mono(16, weight: 700))
                        .foregroundStyle(ghost >= 0 ? Design.Status.go : Design.Accent.vermilion)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The main number: mono label, bib numerals, a quiet unit (and W/kg for power).
private struct HeroCell: View {
    let metric: DisplayMetric
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let size: CGFloat
    let riderKg: Double?

    var body: some View {
        let d = r.display(metric, units: units)
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.label).monoLabel().foregroundStyle(Design.Tarmac.stone)
                Text(d.value)
                    .font(c.font(size)).tracking(size * -0.02)
                    .foregroundStyle(Design.Tarmac.bone)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .transaction { $0.animation = nil }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(d.unit).font(Design.Font.sans(20)).foregroundStyle(Design.Tarmac.stone)
                if metric == .power, let w = r.powerW, let kg = riderKg, kg > 0 {
                    Text(String(format: "%.1f W/kg", Double(w) / kg)).font(Design.Font.mono(12)).foregroundStyle(Design.Tarmac.stone)
                }
            }
            .padding(.bottom, size * 0.06)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One of the three other numbers.
private struct MetricCell: View {
    let metric: DisplayMetric
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let size: CGFloat

    var body: some View {
        let d = r.display(metric, units: units)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if metric == .heartRate { Icon("heart", size: 12) }
                Text(metric == .speed ? d.unit : metric.label).monoLabel().lineLimit(1)
            }
            .foregroundStyle(Design.Tarmac.stone)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(d.value).font(c.font(size)).foregroundStyle(Design.Tarmac.bone)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .transaction { $0.animation = nil }
                if metric != .speed, metric != .time {
                    Text(d.unit).font(Design.Font.sans(14)).foregroundStyle(Design.Tarmac.stone).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The gear: its number between − and + (+ in vermilion), with the position on the ladder.
private struct GearCell: View {
    let r: RideReadout
    let c: DisplayConfig
    let size: CGFloat
    let actions: LiveRideActions?
    var horizontal = false
    var button: CGFloat = 52

    var body: some View {
        let label = Text("Gear · \(r.gear)/\(r.gearCount)").monoLabel().foregroundStyle(Design.Tarmac.stone).lineLimit(1)
        let controls = HStack(spacing: button < 50 ? 8 : 14) {
            button("minus", filled: false, action: actions?.shiftDown).accessibilityLabel("Easier gear")
            Text("\(r.gear)").font(c.font(size)).foregroundStyle(Design.Tarmac.bone)
                .fixedSize()
                .frame(minWidth: size * 0.8)
                .transaction { $0.animation = nil }
            button("plus", filled: true, action: actions?.shiftUp).accessibilityLabel("Harder gear")
        }
        Group {
            if horizontal {
                HStack(spacing: 16) {
                    label
                    Spacer(minLength: 0)
                    controls
                }
            } else {
                VStack(spacing: 10) {
                    label
                    controls
                    GearLadder(gear: r.gear, count: r.gearCount, color: Design.Accent.vermilion).frame(height: 16)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gear \(r.gear) of \(r.gearCount)")
    }

    private func button(_ icon: String, filled: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Icon(icon, size: 20)
                .foregroundStyle(filled ? Design.Palette.onAccent : Design.Tarmac.bone)
                .frame(width: button, height: button)
                .background {
                    if filled { Circle().fill(Design.Accent.vermilion) } else { Circle().strokeBorder(Design.Tarmac.t700, lineWidth: 1) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(action == nil)
    }
}
