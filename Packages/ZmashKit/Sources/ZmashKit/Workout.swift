import Foundation

/// Structured workouts (roadmap Phase 7): steps of fixed or ramped power (as a fraction of FTP) or free riding.
public struct Workout: Codable, Equatable, Identifiable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public enum Target: Codable, Equatable, Sendable {
            /// Fraction of FTP, e.g. 0.9.
            case steady(Double)
            /// Linear from → to, fractions of FTP.
            case ramp(Double, Double)
            /// No target (free ride).
            case free
        }

        public var seconds: Int
        public var target: Target
        public var label: String
        /// The cadence this step asks for, rpm (from a `.zwo` file or the builder); nil: the rider's own band (D142).
        public var cadence: ClosedRange<Int>?

        public init(_ seconds: Int, _ target: Target, _ label: String = "", cadence: ClosedRange<Int>? = nil) {
            self.seconds = seconds
            self.target = target
            self.label = label
            self.cadence = cadence
        }

        public func fraction(at t: Double) -> Double? {
            switch target {
            case .steady(let f): return f
            case .ramp(let a, let b): return a + (b - a) * min(1, max(0, t / Double(max(seconds, 1))))
            case .free: return nil
            }
        }
    }

    public var id: String
    public var name: String
    public var summary: String
    public var steps: [Step]
    /// Open-ended ramp test: repeats its last step pattern until the rider can't hold it.
    public var isRampTest = false

    public init(id: String, name: String, summary: String, steps: [Step], isRampTest: Bool = false) {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.isRampTest = isRampTest
    }

    public var duration: Int { steps.reduce(0) { $0 + $1.seconds } }

    /// Where the rider is at ride time `t`.
    public struct Position: Equatable, Sendable {
        public var index: Int
        public var step: Step
        /// Seconds into this step.
        public var inStep: Double
        public var remainingInStep: Double
        /// Target as a fraction of FTP (nil for free steps).
        public var fraction: Double?
        public var next: Step?
        public var finished: Bool
    }

    public func position(at t: Double) -> Position? {
        guard !steps.isEmpty else { return nil }
        var start = 0.0
        for (i, s) in steps.enumerated() {
            let end = start + Double(s.seconds)
            if t < end {
                let inStep = max(0, t - start)
                return Position(index: i, step: s, inStep: inStep, remainingInStep: end - t, fraction: s.fraction(at: inStep),
                                next: i + 1 < steps.count ? steps[i + 1] : nil, finished: false)
            }
            start = end
        }
        let last = steps[steps.count - 1]
        return Position(index: steps.count - 1, step: last, inStep: Double(last.seconds), remainingInStep: 0,
                        fraction: last.fraction(at: Double(last.seconds)), next: nil, finished: true)
    }

    /// Target watts at `t` for `ftp`.
    public func targetWatts(at t: Double, ftp: Double) -> Int? {
        position(at: t)?.fraction.map { Int(($0 * ftp).rounded()) }
    }
}

// MARK: - Grade-driven workouts

public enum WorkoutGrade {
    /// Reference speed for turning a power target into a hill: at 20 km/h the target power needs this grade.
    public static let referenceSpeedMps = 20 / 3.6

    /// The grade on which holding `watts` at the reference speed is steady-state (−2…12 %).
    public static func grade(forWatts watts: Double, rider: RiderModel) -> Double {
        let v = referenceSpeedMps
        let aero = 0.5 * rider.airDensity * rider.cdA * v * v
        let slope = (watts / v - aero) / (rider.massKg * RiderModel.g) - rider.crr
        return min(12, max(-2, slope * 100))
    }
}

// MARK: - Library

public enum WorkoutLibrary {
    typealias S = Workout.Step

    public static let rampTest = Workout(
        id: "ramp-test", name: "Ramp test",
        summary: "Power rises every minute until you can't hold it. FTP = 75 % of your best minute.",
        steps: [S(300, .steady(0.5), "Warm-up")] + (0..<30).map { S(60, .steady(0.5 + Double($0) * 0.06), "Step \($0 + 1)") },
        isRampTest: true)

    public static let all: [Workout] = [
        Workout(id: "endurance-45", name: "Endurance", summary: "45 min steady Z2. Aerobic base.",
                steps: [S(300, .ramp(0.45, 0.65), "Warm-up"), S(2100, .steady(0.68), "Endurance"), S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "tempo-3x10", name: "Tempo 3 × 10", summary: "Three 10-minute tempo blocks at 85 %.",
                steps: [S(480, .ramp(0.45, 0.7), "Warm-up")] + rep(3, on: (600, 0.85, "Tempo"), off: (300, 0.55, "Easy")) + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "sweetspot-2x20", name: "Sweet spot 2 × 20", summary: "Two 20-minute blocks at 90 %. The workhorse.",
                steps: [S(600, .ramp(0.45, 0.75), "Warm-up")] + rep(2, on: (1200, 0.9, "Sweet spot"), off: (300, 0.55, "Easy")) + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "threshold-4x8", name: "Threshold 4 × 8", summary: "Four 8-minute efforts at 100 % FTP.",
                steps: [S(600, .ramp(0.45, 0.75), "Warm-up")] + rep(4, on: (480, 1.0, "Threshold"), off: (240, 0.5, "Easy")) + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "vo2-5x3", name: "VO₂max 5 × 3", summary: "Five 3-minute efforts at 115 %. Hard.",
                steps: [S(600, .ramp(0.45, 0.75), "Warm-up")] + rep(5, on: (180, 1.15, "VO₂max"), off: (180, 0.5, "Easy")) + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "over-under-3x9", name: "Over-unders 3 × 9", summary: "Alternate 95 % and 105 % in 1.5-minute blocks.",
                steps: [S(600, .ramp(0.45, 0.75), "Warm-up")]
                    + (0..<3).flatMap { _ in (0..<3).flatMap { _ in [S(90, .steady(0.95), "Under"), S(90, .steady(1.05), "Over")] } + [S(300, .steady(0.5), "Easy")] }
                    + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "sprints-8x20", name: "Sprints 8 × 20 s", summary: "Eight all-out 20-second sprints with long recovery.",
                steps: [S(600, .ramp(0.45, 0.75), "Warm-up")] + rep(8, on: (20, 1.8, "Sprint"), off: (160, 0.5, "Easy")) + [S(300, .ramp(0.6, 0.4), "Cool-down")]),
        Workout(id: "recovery-30", name: "Recovery", summary: "30 easy minutes. Spin the legs.",
                steps: [S(1800, .steady(0.5), "Easy")]),
        rampTest,
    ]

    static func rep(_ n: Int, on: (Int, Double, String), off: (Int, Double, String)) -> [Workout.Step] {
        (0..<n).flatMap { i in
            [S(on.0, .steady(on.1), "\(on.2) \(i + 1)/\(n)")] + (i < n - 1 ? [S(off.0, .steady(off.1), off.2)] : [])
        }
    }
}

// MARK: - .zwo import (Zwift workout XML)

/// Parses Zwift `.zwo` workouts: SteadyState, Warmup, Cooldown, Ramp, IntervalsT, FreeRide (MaxEffort as a free step).
public final class ZWOParser: NSObject, XMLParserDelegate {
    private var steps: [Workout.Step] = []
    private var name = ""
    private var summaryText = ""
    private var text = ""
    private var inWorkout = false

    public static func parse(_ data: Data, id: String) -> Workout? {
        let p = ZWOParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse(), !p.steps.isEmpty else { return nil }
        return Workout(id: id, name: p.name.isEmpty ? "Imported workout" : p.name,
                       summary: p.summaryText.trimmingCharacters(in: .whitespacesAndNewlines), steps: p.steps)
    }

    private func num(_ a: [String: String], _ keys: String...) -> Double? {
        for k in keys { if let v = a[k] ?? a[k.lowercased()], let d = Double(v) { return d } }
        return nil
    }

    /// A step's cadence: `CadenceLow`…`CadenceHigh`, or `Cadence` (or `resting`'s) ± 5 rpm.
    private func cadence(_ a: [String: String], resting: Bool = false) -> ClosedRange<Int>? {
        if !resting, let lo = num(a, "CadenceLow"), let hi = num(a, "CadenceHigh"), hi >= lo { return Int(lo)...Int(hi) }
        guard let c = resting ? num(a, "CadenceResting") : num(a, "Cadence"), c > 0 else { return nil }
        return Int(c) - 5...Int(c) + 5
    }

    public func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                       qualifiedName: String?, attributes a: [String: String]) {
        text = ""
        if element.lowercased() == "workout" { inWorkout = true; return }
        guard inWorkout else { return }
        let dur = Int(num(a, "Duration") ?? 0)
        // Zmash's own files keep each step's label in an attribute Zwift ignores.
        let label = a["zmashLabel"]
        switch element.lowercased() {
        case "steadystate":
            steps.append(.init(dur, .steady(num(a, "Power") ?? 0.6), label ?? "Steady", cadence: cadence(a)))
        case "warmup":
            steps.append(.init(dur, .ramp(num(a, "PowerLow") ?? 0.4, num(a, "PowerHigh") ?? 0.7), "Warm-up", cadence: cadence(a)))
        case "cooldown":
            steps.append(.init(dur, .ramp(num(a, "PowerLow") ?? 0.7, num(a, "PowerHigh") ?? 0.4), "Cool-down", cadence: cadence(a)))
        case "ramp":
            steps.append(.init(dur, .ramp(num(a, "PowerLow") ?? 0.5, num(a, "PowerHigh") ?? 0.8), label ?? "Ramp", cadence: cadence(a)))
        case "intervalst":
            let n = Int(num(a, "Repeat") ?? 1)
            let on = Int(num(a, "OnDuration") ?? 0), off = Int(num(a, "OffDuration") ?? 0)
            for i in 0..<max(n, 1) {
                steps.append(.init(on, .steady(num(a, "OnPower") ?? 1), "On \(i + 1)/\(n)", cadence: cadence(a)))
                steps.append(.init(off, .steady(num(a, "OffPower") ?? 0.5), "Off", cadence: cadence(a, resting: true)))
            }
        case "freeride", "maxeffort":
            steps.append(.init(dur, .free, label ?? (element.lowercased() == "maxeffort" ? "Max effort" : "Free ride"),
                               cadence: cadence(a)))
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element.lowercased() {
        case "name" where !inWorkout: name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "description" where !inWorkout: summaryText = text
        case "workout": inWorkout = false
        default: break
        }
    }
}

/// Writes a workout as a Zwift `.zwo` file (steady, ramp and free-ride steps), readable by Zwift, TrainerRoad and
/// others, and by `ZWOParser` (labels included).
public enum ZWOWriter {
    public static func write(_ w: Workout, author: String = "Zmash") -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func num(_ v: Double) -> String { String(format: "%.3f", v) }
        var lines = ["<workout_file>", "    <author>\(esc(author))</author>", "    <name>\(esc(w.name))</name>",
                     "    <description>\(esc(w.summary))</description>", "    <sportType>bike</sportType>", "    <workout>"]
        for s in w.steps {
            // A cadence band goes in as Zwift's single Cadence (its middle) and as low/high for readers that take them.
            let cadence = s.cadence.map { c in
                " Cadence=\"\((c.lowerBound + c.upperBound) / 2)\" CadenceLow=\"\(c.lowerBound)\" CadenceHigh=\"\(c.upperBound)\""
            } ?? ""
            let label = "zmashLabel=\"\(esc(s.label))\"" + cadence
            switch s.target {
            case .steady(let f):
                lines.append("        <SteadyState Duration=\"\(s.seconds)\" Power=\"\(num(f))\" \(label)/>")
            case .ramp(let a, let b):
                lines.append("        <Ramp Duration=\"\(s.seconds)\" PowerLow=\"\(num(a))\" PowerHigh=\"\(num(b))\" \(label)/>")
            case .free:
                lines.append("        <FreeRide Duration=\"\(s.seconds)\" \(label)/>")
            }
        }
        lines += ["    </workout>", "</workout_file>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }
}

public extension Workout {
    /// Repeats `count` steps starting at `index` (an effort and its recovery, say) so they appear `times` times in all.
    func repeating(from index: Int, count: Int, times: Int) -> Workout {
        guard index >= 0, count > 0, index + count <= steps.count, times > 1 else { return self }
        var w = self
        let block = Array(steps[index..<(index + count)])
        w.steps.insert(contentsOf: Array(repeating: block, count: times - 1).flatMap { $0 }, at: index + count)
        return w
    }
}
