import Foundation

/// The bundled workout catalog (D154): thousands of `.zwo` workouts turned by `make workouts` into one compact file,
/// so the app never parses XML at launch. Each step is a short array instead of a keyed object:
/// `[seconds, kind, from, to]`, then `cadenceLow, cadenceHigh` when it has a cadence, then `grade` when it has one
/// (`cadenceLow` 0 when there's a grade but no cadence). Kinds: 0 steady, 1 ramp, 2 free.
public struct WorkoutCatalogFile: Codable, Sendable {
    public var version = 1
    public var workouts: [Entry]

    public init(workouts: [Entry]) { self.workouts = workouts }

    public struct Entry: Codable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Where it comes from: a Zwift collection or plan ("FTP Builder"), "The Sufferfest", "Community".
        public var collection: String
        public var author: String?
        public var summary: String
        /// `Workout.Category` raw value.
        public var category: String
        public var steps: [[Double]]

        public init(workout w: Workout, collection: String, author: String?, category: Workout.Category) {
            id = w.id
            name = w.name
            self.collection = collection
            self.author = author
            summary = w.summary
            self.category = category.rawValue
            steps = w.steps.map(Self.encode)
        }

        public var workout: Workout {
            var w = Workout(id: id, name: name, summary: summary, steps: steps.compactMap(Self.decode),
                            category: Workout.Category(rawValue: category))
            if w.steps.isEmpty { w.steps = [.init(60, .free)] }
            // Labels aren't stored: plain ones from the steps (the ride screen names the step it's on).
            let last = w.steps.count - 1
            for i in w.steps.indices {
                w.steps[i].label = switch w.steps[i].target {
                case .ramp(let a, let b) where i == 0 && b >= a: "Warm-up"
                case .ramp(let a, let b) where i == last && b < a: "Cool-down"
                case .ramp(let a, let b): b >= a ? "Ramp up" : "Ramp down"
                case .free: "Free ride"
                case .steady(let f): f >= 0.76 ? "On" : "Easy"
                }
            }
            return w
        }

        /// Length in seconds, without building the workout.
        public var seconds: Int { steps.reduce(0) { $0 + Int($1.first ?? 0) } }

        static func r(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

        static func encode(_ s: Workout.Step) -> [Double] {
            var a: [Double] = switch s.target {
            case .steady(let f): [Double(s.seconds), 0, r(f), r(f)]
            case .ramp(let from, let to): [Double(s.seconds), 1, r(from), r(to)]
            case .free: [Double(s.seconds), 2, 0, 0]
            }
            if s.cadence != nil || s.grade != nil {
                a += [Double(s.cadence?.lowerBound ?? 0), Double(s.cadence?.upperBound ?? 0)]
            }
            if let g = s.grade { a.append(r(g)) }
            return a
        }

        static func decode(_ a: [Double]) -> Workout.Step? {
            guard a.count >= 4, a[0] > 0 else { return nil }
            let target: Workout.Step.Target = switch Int(a[1]) {
            case 1: .ramp(a[2], a[3])
            case 2: .free
            default: .steady(a[2])
            }
            let cadence: ClosedRange<Int>? = a.count >= 6 && a[4] > 0 && a[5] >= a[4] ? Int(a[4])...Int(a[5]) : nil
            return Workout.Step(Int(a[0]), target, "", cadence: cadence, grade: a.count >= 7 ? a[6] : nil)
        }
    }

    /// A file's `<category>` as one of the six kinds, when it names one ("Sweet Spot", "VO2 Max", "FTP Tests"…).
    public static func category(named raw: String?) -> Workout.Category? {
        guard let n = raw?.lowercased(), !n.isEmpty else { return nil }
        if n.contains("test") { return .tests }
        if n.contains("sprint") || n.contains("anaerobic") { return .sprints }
        if n.contains("vo2") || n.contains("vo₂") { return .vo2 }
        if n.contains("threshold") { return .threshold }
        if n.contains("tempo") || n.contains("sweet") { return .tempo }
        if n.contains("endurance") || n.contains("recovery") { return .endurance }
        return nil
    }

    /// "Zwift Academy 2018" → "zwift-academy-2018", for stable ids.
    public static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.lowercased().split { !($0.isLetter || $0.isNumber) }
        return parts.joined(separator: "-")
    }
}

/// How long a workout is, for the length filter (D154). Each counts as the nearest length, so a 1:03 workout is "1 h"
/// and a 40-minute one "45′": up to 37½ min is 30′, then 45′ to 52½, 1 h to 75, 1 h 30 to 105, and Longer after.
public enum WorkoutLength: String, CaseIterable, Hashable, Sendable {
    case any, m30, m45, h1, h90, longer

    public var title: String {
        switch self {
        case .any: "Any length"
        case .m30: "30′"
        case .m45: "45′"
        case .h1: "1 h"
        case .h90: "1 h 30"
        case .longer: "Longer"
        }
    }

    public static func of(seconds: Int) -> WorkoutLength {
        let m = Double(seconds) / 60
        return m <= 37.5 ? .m30 : m <= 52.5 ? .m45 : m <= 75 ? .h1 : m <= 105 ? .h90 : .longer
    }

    public func contains(seconds: Int) -> Bool { self == .any || Self.of(seconds: seconds) == self }
}
