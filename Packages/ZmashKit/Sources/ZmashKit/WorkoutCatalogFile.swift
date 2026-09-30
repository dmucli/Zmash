import Foundation

/// The bundled workout catalog (D154): thousands of `.zwo` workouts turned by `make workouts` into one compact file,
/// so the app never parses XML at launch. Each step is a short array instead of a keyed object:
/// `[seconds, kind, from, to]`, then `cadenceLow, cadenceHigh` when it has a cadence, then `grade` when it has one
/// (`cadenceLow` 0 when there's a grade but no cadence). Kinds: 0 steady, 1 ramp, 2 free.
public struct WorkoutCatalogFile: Codable, Sendable {
    public var version = 2
    public var workouts: [Entry]
    /// The collections that are training plans (D155): their workouts are sessions of a programme, shown on the Plan
    /// page in order, never among the standalone workouts. nil in a version-1 file.
    public var plans: [Plan]?

    public init(workouts: [Entry], plans: [Plan] = []) {
        self.workouts = workouts
        self.plans = plans
    }

    /// A collection that's a plan, and what it's for (one of Zmash's plan goals).
    public struct Plan: Codable, Sendable, Hashable {
        public var collection: String
        /// `TrainingPlan.Goal` raw value.
        public var goal: String

        public init(collection: String, goal: TrainingPlan.Goal) {
            self.collection = collection
            self.goal = goal.rawValue
        }
    }

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

// MARK: - Plans among the collections (D155)

public extension WorkoutCatalogFile {
    /// Collections that name a programme, and a few that don't but are one.
    private static let planWords = ["plan", "program", "prep", "builder", "booster", "academy", "challenge", "century",
                                    "camp", "tune up", "tuneup", "lockdown", "club", "phase", "stage ", " wk", "wk ",
                                    "week", "spring training", "long haul", "mission"]
    /// Collections of standalone workouts that the rules above would take for plans.
    private static let notPlans = ["best of zwift academy", "pro training camp", "individual power profile", "ftp tests"]

    /// Whether a collection is a training plan: its name says so, or most of its workouts are numbered sessions.
    static func isPlan(collection: String, names: [String]) -> Bool {
        let c = collection.lowercased()
        if notPlans.contains(where: { c.hasPrefix($0) }) { return false }
        if planWords.contains(where: { c.contains($0) }) { return true }
        guard !names.isEmpty else { return false }
        // A session's name as a plan numbers it: "Week 1 - Day 2", "#100-DPC …", "Stage 3", "1. Aerobic Power".
        let sessionName = /(?i)\b(week|wk|day|stage|session|phase|month|lesson|workout)\s*#?\d|^#\d|^\d+\s*[-.:]/
        let numbered = names.filter { $0.contains(sessionName) }.count
        return Double(numbered) / Double(names.count) >= 0.5
    }

    /// What a plan is for, from its name.
    static func goal(forPlan collection: String) -> TrainingPlan.Goal {
        let c = collection.lowercased()
        if ["climb", "etape", "alpe"].contains(where: { c.contains($0) }) { return .climb }
        if ["fondo", "century", "prl", "unbound", "gravel", "pebble", "dirt", "singletrack", "mountain", "ironteam", "tri",
            "multisport", "long haul", "endurance"].contains(where: { c.contains($0) }) { return .endurance }
        if ["offseason", "back to fitness", "baby", "jumpstart", "tune up", "101", "fast track", "lockdown",
            "recreation"].contains(where: { c.contains($0) }) { return .maintain }
        return .build
    }

    /// Where a session falls in its plan, from its name: the week ("Week 2", "Wk 2", "Month 2") and its number in it
    /// ("Day 3", "3.", "#31", "Stage 3"), when the name gives them.
    static func sessionOrder(_ name: String) -> (week: Int?, index: Int?) {
        func number(after pattern: Regex<(Substring, Substring)>) -> Int? {
            (try? pattern.firstMatch(in: name)).flatMap { Int($0.1) }
        }
        let week = number(after: /(?i)\b(?:week|wk|month)\s*(\d+)/)
        let index = number(after: /(?i)\b(?:day|stage|session|workout|lesson)\s*#?(\d+)/)
            ?? number(after: /(?:^|-\s)#?(\d+)[.\-:\s]/)
        return (week, index)
    }
}

// MARK: - Plans to enrol in (D156)

public extension WorkoutCatalogFile {
    /// A catalog plan's id among the training plans: "zc-ftp-builder". No slash, so its sessions can be
    /// "plan/zc-ftp-builder/<week>-<index>" like any plan's.
    static func planID(collection: String) -> String { "zc-" + slug(collection) }

    /// A catalog plan as a training plan, to enrol in like Zmash's: its sessions in order, in weeks.
    static func trainingPlan(collection: String, goal: TrainingPlan.Goal, sessions: [Entry]) -> TrainingPlan {
        let ordered = orderedSessions(sessions)
        let weeks = planWeeks(ordered.map(\.name)).map { $0.map { TrainingPlan.Session.workout(ordered[$0].id) } }
        let authors = Set(sessions.compactMap { $0.author?.replacingOccurrences(of: " (via whatsonzwift.com)", with: "") })
        let author = authors.count == 1 ? authors.first! : ""
        let perWeek = weeks.map(\.count).max() ?? 0
        let summary = "\(weeks.count) week\(weeks.count == 1 ? "" : "s"), \(perWeek) ride\(perWeek == 1 ? "" : "s") a week"
            + (author.isEmpty ? "" : ", from \(author)") + ". You ride its sessions as written: they don't adapt like Zmash's plans."
        return TrainingPlan(id: planID(collection: collection), name: collection, summary: summary, weeks: weeks, goal: goal,
                            author: author)
    }

    /// A plan's sessions in order: by week, then day or number, then name (sessions that name no week come first).
    static func orderedSessions(_ sessions: [Entry]) -> [Entry] {
        sessions.map { ($0, sessionOrder($0.name)) }.sorted { a, b in
            let wa = a.1.week ?? 0, wb = b.1.week ?? 0
            if wa != wb { return wa < wb }
            let ia = a.1.index ?? .max, ib = b.1.index ?? .max
            if ia != ib { return ia < ib }
            return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
        }
        .map(\.0)
    }

    /// Sessions (by position, in order) grouped into weeks. When every name gives its week, those weeks, in order (a
    /// gap closes up). Otherwise the files' weeks can't be trusted: the sessions keep their order, in weeks of the
    /// plan's usual count (the median of the weeks its names do give, 3 when none do).
    static func planWeeks(_ names: [String]) -> [[Int]] {
        let weeks = names.map(namedWeek)
        if !weeks.isEmpty, weeks.allSatisfy({ $0 != nil }) {
            var out: [[Int]] = []
            for (i, w) in weeks.enumerated() {
                if i > 0, w == weeks[i - 1] { out[out.count - 1].append(i) } else { out.append([i]) }
            }
            return out
        }
        let counts = Dictionary(grouping: weeks.compactMap { $0 }, by: { $0 }).values.map(\.count).sorted()
        let perWeek = min(max(counts.isEmpty ? 3 : counts[counts.count / 2], 1), 7)
        return stride(from: 0, to: names.count, by: perWeek).map { Array($0..<min($0 + perWeek, names.count)) }
    }

    /// The week a session's name gives ("Week 2", "Wk 2"); a month isn't one.
    private static func namedWeek(_ name: String) -> Int? {
        (try? /(?i)\b(?:week|wk)\s*(\d+)/.firstMatch(in: name)).flatMap { Int($0.1) }
    }

    /// A session's name without the week and day the plan already shows: "Week 1 - Day 2 - HIT 45sec #1" →
    /// "HIT 45sec #1", "Week 0 Prep - 1. No Nonsense" → "No Nonsense". A name that's only a number stays whole.
    static func sessionTitle(_ name: String) -> String {
        // A bare number only before a word, so "20-20-20" stays.
        let prefix = /(?i)^\s*(?:(?:week|wk|month|day|stage|session|workout|lesson)\s*#?\d+(?:\s*prep)?\s*[-.:]\s*|#?\d+\s*[-.:]\s*(?=\D))/
        var rest = Substring(name)
        while let m = rest.prefixMatch(of: prefix) { rest = rest[m.range.upperBound...] }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? name : title
    }
}
