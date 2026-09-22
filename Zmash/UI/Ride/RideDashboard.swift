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
    case rounded, standard, mono

    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .standard: .default
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
    var style: NumberStyle = .rounded
    var weight: NumberWeight = .semibold
    /// Hero size multiplier: 0.8 / 1.0 / 1.2.
    var heroScale: Double = 1.0
    /// Tint the gear, grade and elevation by the grade (off = ink only).
    var gradeColor = true

    static let standard = DisplayConfig()

    func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: weight.weight, design: style.design).monospacedDigit()
    }

    func accent(forGrade grade: Double) -> Color {
        gradeColor ? Design.accent(forGrade: grade) : Design.Palette.primary
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
    var bias: Double?
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
        bias = engine.plan.terrainMode == .auto && engine.controls.autoBias != 0 ? engine.controls.autoBias : nil
        gear = engine.controls.gear
        gearCount = engine.controls.gears.count
        upcomingGrades = engine.hasProfile ? engine.upcomingGrades : []
        waitingForPedal = engine.phase == .waitingForPedal
    }

    init(speedKph: Double, powerW: Int?, cadenceRpm: Int?, elapsed: Double, remaining: Double?, kcal: Double,
         distanceM: Double, climbedM: Double, grade: Double, bias: Double?, gear: Int, gearCount: Int,
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
        self.bias = bias
        self.gear = gear
        self.gearCount = gearCount
        self.upcomingGrades = upcomingGrades
        self.waitingForPedal = waitingForPedal
    }

    /// Plausible mid-ride values for the Settings preview.
    static let sample = RideReadout(
        speedKph: 31.4, powerW: 212, cadenceRpm: 88, elapsed: 1_462, remaining: 338, kcal: 301,
        distanceM: 12_480, climbedM: 146, grade: 3.5, bias: nil, gear: 14, gearCount: 24,
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
    var biasText: String? { bias.map { String(format: "%+.1f", $0) } }
}

// MARK: - Dashboard

/// The numbers part of the ride screen, in wide / portrait / compact arrangements.
struct RideDashboard: View {
    let readout: RideReadout
    let config: DisplayConfig
    let units: Units
    let size: CGSize
    let compact: Bool

    var body: some View {
        if compact {
            CompactLayout(r: readout, c: config, units: units, width: size.width)
        } else if size.height > size.width {
            PortraitLayout(r: readout, c: config, units: units)
        } else {
            WideLayout(r: readout, c: config, units: units, height: size.height)
        }
    }
}

private struct Metric: View {
    let metric: DisplayMetric
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let size: CGFloat
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        let d = r.display(metric, units: units)
        VStack(alignment: alignment, spacing: 0) {
            let text = Text(d.value)
                .font(c.font(size))
                .foregroundStyle(Design.Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // Only the waiting clock pulses; animating live numbers would crossfade every update.
            if d.pulse {
                text.phaseAnimator([1.0, 0.35]) { content, opacity in content.opacity(opacity) }
                    animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                text.transaction { $0.animation = nil }
            }
            Text(d.unit)
                .font(Design.Font.unit)
                .foregroundStyle(Design.Palette.secondary)
        }
    }
}

private struct WideLayout: View {
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let height: CGFloat

    var body: some View {
        let hero = height * 0.30 * c.heroScale
        let side = height * 0.10
        GeometryReader { geo in
            let column = geo.size.width * 0.24
            VStack(spacing: 0) {
                Spacer(minLength: Design.Space.block)
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: Design.Space.block) {
                        Metric(metric: c.slot(0), r: r, c: c, units: units, size: side)
                        Metric(metric: c.slot(1), r: r, c: c, units: units, size: side)
                    }
                    .frame(width: column, alignment: .leading)

                    Metric(metric: c.hero, r: r, c: c, units: units, size: hero, alignment: .center)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .trailing, spacing: Design.Space.block) {
                        Metric(metric: c.slot(2), r: r, c: c, units: units, size: side, alignment: .trailing)
                        Metric(metric: c.slot(3), r: r, c: c, units: units, size: side, alignment: .trailing)
                    }
                    .frame(width: column, alignment: .trailing)
                }
                Spacer(minLength: Design.Space.block)
                TerrainBar(r: r, c: c, gradeSize: side * 0.8)
                    .padding(.bottom, 96) // room for on-screen controls
            }
        }
        .padding(.horizontal, Design.Space.block * 1.5)
    }
}

private struct PortraitLayout: View {
    let r: RideReadout
    let c: DisplayConfig
    let units: Units

    var body: some View {
        VStack(spacing: Design.Space.block) {
            Spacer()
            Metric(metric: c.hero, r: r, c: c, units: units, size: 180 * c.heroScale, alignment: .center)
            Grid(horizontalSpacing: Design.Space.block * 2, verticalSpacing: Design.Space.block) {
                GridRow {
                    Metric(metric: c.slot(0), r: r, c: c, units: units, size: 64)
                    Metric(metric: c.slot(2), r: r, c: c, units: units, size: 64)
                }
                GridRow {
                    Metric(metric: c.slot(1), r: r, c: c, units: units, size: 64)
                    Metric(metric: c.slot(3), r: r, c: c, units: units, size: 64)
                }
            }
            Spacer()
            TerrainBar(r: r, c: c, gradeSize: 48).padding(.bottom, 96)
        }
        .padding(.horizontal, Design.Space.block)
    }
}

/// Split View / Slide Over / small windows: a 2×3 grid that stays readable at 320 pt.
private struct CompactLayout: View {
    let r: RideReadout
    let c: DisplayConfig
    let units: Units
    let width: CGFloat

    var body: some View {
        // Scale with the column: ~70 pt top row and ~50 pt below at a 375 pt Split View column.
        let big = min(120, width * 0.19 * c.heroScale)
        let small = min(84, width * 0.135)
        VStack(spacing: Design.Space.gutter) {
            Spacer(minLength: 24)
            Grid(alignment: .leading, horizontalSpacing: Design.Space.gutter * 2, verticalSpacing: Design.Space.gutter * 1.5) {
                GridRow {
                    Metric(metric: c.hero, r: r, c: c, units: units, size: big)
                    Metric(metric: c.slot(0), r: r, c: c, units: units, size: big)
                }
                GridRow {
                    Metric(metric: c.slot(1), r: r, c: c, units: units, size: small)
                    Metric(metric: c.slot(2), r: r, c: c, units: units, size: small)
                }
                GridRow {
                    Metric(metric: c.slot(3), r: r, c: c, units: units, size: small)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.gradeText).font(c.font(small)).foregroundStyle(Design.Palette.primary)
                        Text("%" + (r.biasText.map { "  bias \($0)" } ?? ""))
                            .font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
                    }
                }
            }
            Spacer(minLength: Design.Space.gutter)
            GearLadder(gear: r.gear, count: r.gearCount, color: c.accent(forGrade: r.grade))
                .frame(height: 28)
                .padding(.bottom, 88)
        }
        .padding(.horizontal, Design.Space.gutter)
    }
}

private struct TerrainBar: View {
    let r: RideReadout
    let c: DisplayConfig
    let gradeSize: CGFloat

    var body: some View {
        let accent = c.accent(forGrade: r.grade)
        HStack(alignment: .bottom, spacing: Design.Space.block) {
            VStack(alignment: .leading, spacing: 12) {
                if !r.upcomingGrades.isEmpty {
                    ElevationStrip(grades: r.upcomingGrades, color: accent, marker: true)
                        .frame(height: 44)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    GearLadder(gear: r.gear, count: r.gearCount, color: accent)
                        .frame(height: 28)
                    Text("\(r.gear)")
                        .font(c.font(20))
                        .foregroundStyle(Design.Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(r.gradeText)
                    .font(c.font(gradeSize))
                    .foregroundStyle(Design.Palette.primary)
                Text("%").font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
                if let bias = r.biasText {
                    Text(bias)
                        .font(Design.Font.small.monospacedDigit())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().stroke(accent.opacity(0.6)))
                }
            }
            .fixedSize()
        }
    }
}
