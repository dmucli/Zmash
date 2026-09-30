import Foundation

/// A workout told in words, for its details (D163): the steps folded into what a rider reads ("2 × 20 min at 90 %
/// (180 W), 5 min easy between"), and the time its targets spend in each power zone.
public enum WorkoutOutline {
    /// A piece of the outline.
    public indirect enum Part: Equatable, Sendable {
        case step(Workout.Step)
        /// `work` done `count` times, with `rest` between.
        case repeated(count: Int, work: [Part], rest: Part?)
        /// Steps of the same length whose power climbs (or drops) by the same amount each time: a ramp test, a pyramid.
        case stairs(count: Int, seconds: Int, from: Double, to: Double)
        /// A run of short, uneven efforts (a Sufferfest video's), told as one: how long, and from what to what.
        case efforts(seconds: Int, low: Double, high: Double)
        /// Efforts of different lengths or powers with recoveries between: a ladder, a pyramid, a descending set.
        case ladder(works: [Workout.Step], rests: [Workout.Step])
    }

    // MARK: Folding

    /// The steps folded: same-target neighbours merged, runs of equal steps rising together as stairs, runs of the same
    /// unit (1–4 parts, alike within a few seconds and 2 % of FTP) as repeats with the recovery between them apart, then
    /// the same again over those repeats (sets). Last, four or more short efforts in a row become one.
    public static func parts(_ steps: [Workout.Step]) -> [Part] {
        var parts = stairs(merged(steps))
        for _ in 0..<3 {
            let folded = fold(parts)
            if folded == parts { break }
            parts = folded
        }
        return efforts(parts)
    }

    /// Four or more short efforts in a row (each under 3 minutes, none easy) told as one stretch.
    static func efforts(_ parts: [Part]) -> [Part] {
        func short(_ p: Part) -> Bool {
            guard seconds(p) < 180, low(p) >= 0.6 else { return false }
            if case .step(let s) = p { return s.grade == nil && s.target != .free }
            return true
        }
        var out: [Part] = []
        var i = 0
        while i < parts.count {
            var j = i
            while j < parts.count, short(parts[j]) { j += 1 }
            if j - i >= 4 {
                let run = parts[i..<j]
                out.append(.efforts(seconds: run.map(seconds).reduce(0, +), low: run.map(low).min()!, high: run.map(intensity).max()!))
                i = j
            } else {
                out.append(parts[i])
                i += 1
            }
        }
        return out
    }

    /// How long a part lasts.
    static func seconds(_ p: Part) -> Int {
        switch p {
        case .step(let s): s.seconds
        case .repeated(let n, let work, let rest): n * work.map(seconds).reduce(0, +) + (n - 1) * (rest.map(seconds) ?? 0)
        case .stairs(let n, let s, _, _): n * s
        case .efforts(let s, _, _): s
        case .ladder(let works, let rests): (works + rests).map(\.seconds).reduce(0, +)
        }
    }

    /// A part at its easiest, as a fraction of FTP.
    static func low(_ p: Part) -> Double {
        switch p {
        case .step(let s):
            switch s.target {
            case .steady(let f): f
            case .ramp(let a, let b): min(a, b)
            case .free: 0.5
            }
        case .repeated(_, let work, let rest): (work + (rest.map { [$0] } ?? [])).map(low).min() ?? 0
        case .stairs(_, _, let from, let to): min(from, to)
        case .efforts(_, let l, _): l
        case .ladder(let works, let rests): (works + rests).compactMap { $0.fraction(at: 0) }.min() ?? 0
        }
    }

    /// Neighbouring work steps with the same target, gradient and cadence are one step. Easy ones stay apart: the
    /// recovery after the last interval of a set and the rest between sets read better as two.
    static func merged(_ steps: [Workout.Step]) -> [Workout.Step] {
        var out: [Workout.Step] = []
        for s in steps {
            if let last = out.last, last.target == s.target, last.grade == s.grade, last.cadence == s.cadence,
               case .steady(let f) = s.target, f >= 0.6 {
                out[out.count - 1].seconds += s.seconds
            } else {
                out.append(s)
            }
        }
        return out
    }

    /// Four or more steady steps of one length, each the same step up or down from the last, become stairs.
    static func stairs(_ steps: [Workout.Step]) -> [Part] {
        var out: [Part] = []
        var i = 0
        while i < steps.count {
            var j = i + 1
            if case .steady(let a) = steps[i].target, steps[i].grade == nil, i + 1 < steps.count,
               case .steady(let b) = steps[i + 1].target, abs(b - a) > 0.004 {
                let step = b - a
                var previous = a
                j = i
                while j < steps.count, steps[j].seconds == steps[i].seconds, steps[j].grade == nil,
                      case .steady(let f) = steps[j].target, j == i || abs(f - previous - step) < 0.006 {
                    previous = f
                    j += 1
                }
                if j - i >= 4, case .steady(let last) = steps[j - 1].target {
                    out.append(.stairs(count: j - i, seconds: steps[i].seconds, from: a, to: last))
                    i = j
                    continue
                }
            }
            out.append(.step(steps[i]))
            i += 1
        }
        return out
    }

    /// Runs of a repeated unit folded into repeats: the longest run first, a shorter unit on a tie.
    static func fold(_ p: [Part]) -> [Part] {
        var out: [Part] = []
        var i = 0
        while i < p.count {
            var best: (part: Part, covered: Int)?
            for length in 1...min(4, p.count - i) {
                let unit = Array(p[i..<i + length])
                var k = 1
                while i + (k + 1) * length <= p.count, same(Array(p[i + k * length..<i + (k + 1) * length]), unit) { k += 1 }
                // (work, rest) × k, then the work once more without its rest: the usual intervals.
                let work = Array(unit.dropLast()), rest = unit.last!
                // A recovery is below tempo and easier than the work: 105 % after 114 % isn't one, nor is sweet spot
                // between kicks.
                let easier = length >= 2 && isRecovery(rest, after: work)
                let after = i + k * length
                var candidate: (Part, Int)?
                if easier, after + work.count <= p.count, same(Array(p[after..<after + work.count]), work) {
                    candidate = (.repeated(count: k + 1, work: work, rest: rest), k * length + work.count)
                } else if k >= 2 {
                    // A run that starts on its recovery (after an odd step) is the same intervals, the recovery first.
                    let first = unit[0], tail = Array(unit.dropFirst())
                    let restFirst = length >= 2 && isRecovery(first, after: tail)
                    candidate = easier ? (.repeated(count: k, work: work, rest: rest), k * length)
                        : restFirst ? (.repeated(count: k, work: tail, rest: first), k * length)
                        : (.repeated(count: k, work: unit, rest: nil), k * length)
                }
                if let (part, covered) = candidate, covered > (best?.covered ?? 1) { best = (part, covered) }
            }
            if let ladder = ladder(p, at: i), ladder.covered > (best?.covered ?? 1) { best = ladder }
            if let best {
                out.append(best.part)
                i += best.covered
            } else {
                out.append(p[i])
                i += 1
            }
        }
        return out
    }

    /// Below tempo (under 76 %) and easier than the work: a recovery, not more work.
    static func isRecovery(_ p: Part, after work: [Part]) -> Bool {
        intensity(p) < 0.76 && intensity(p) < intensity(work)
    }

    /// Three or more steady efforts that differ in length or power, each followed by a recovery: one ladder.
    static func ladder(_ p: [Part], at i: Int) -> (part: Part, covered: Int)? {
        var works: [Workout.Step] = [], rests: [Workout.Step] = []
        var j = i
        while j < p.count, case .step(let w) = p[j], case .steady(let f) = w.target, f >= 0.76, w.grade == nil {
            works.append(w)
            guard j + 2 < p.count, case .step(let r) = p[j + 1], isRecovery(p[j + 1], after: [p[j]]),
                  case .step(let next) = p[j + 2], case .steady(let g) = next.target, g >= 0.76 else { j += 1; break }
            rests.append(r)
            j += 2
        }
        guard works.count >= 3 else { return nil }
        return (.ladder(works: works, rests: Array(rests.prefix(works.count - 1))), works.count + min(rests.count, works.count - 1))
    }

    /// Alike for folding: labels aside ("Threshold 1/4", "Threshold 2/4"), a few seconds either way (video-timed
    /// intervals of 59 s, 1:01, 1:03) and within 2 % of FTP.
    static func same(_ a: [Part], _ b: [Part]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { alike($0, $1) }
    }

    static func alike(_ a: Part, _ b: Part) -> Bool {
        switch (a, b) {
        case (.step(let x), .step(let y)):
            let close = abs(x.seconds - y.seconds) <= max(5, x.seconds * 8 / 100)
            let target: Bool = switch (x.target, y.target) {
            case (.steady(let f), .steady(let g)): abs(f - g) <= 0.02
            case (.ramp(let f1, let t1), .ramp(let f2, let t2)): abs(f1 - f2) <= 0.02 && abs(t1 - t2) <= 0.02
            case (.free, .free): true
            default: false
            }
            return close && target && x.grade == y.grade && x.cadence == y.cadence
        case (.repeated(let n, let w1, let r1), .repeated(let m, let w2, let r2)):
            let rests = switch (r1, r2) {
            case (nil, nil): true
            case (let p?, let q?): alike(p, q)
            default: false
            }
            return n == m && same(w1, w2) && rests
        default:
            return a == b
        }
    }

    /// How hard a part is at its hardest, as a fraction of FTP (free riding counts as easy).
    static func intensity(_ p: Part) -> Double {
        switch p {
        case .step(let s):
            switch s.target {
            case .steady(let f): f
            case .ramp(let a, let b): max(a, b)
            case .free: 0.5
            }
        case .repeated(_, let work, _): intensity(work)
        case .stairs(_, _, let from, let to): max(from, to)
        case .efforts(_, _, let high): high
        case .ladder(let works, _): works.compactMap { $0.fraction(at: 0) }.max() ?? 0
        }
    }

    static func intensity(_ parts: [Part]) -> Double { parts.map(intensity).max() ?? 0 }

    // MARK: Words

    /// The outline as lines: "10 min warm-up, 50 → 75 %", "2 × 20 min at 90 % (180 W), 5 min easy between",
    /// "3 sets of 8 × (30 s at 120 % (300 W), 30 s easy), 5 min easy between sets".
    public static func lines(_ w: Workout, ftp: Double) -> [String] {
        outline(w, ftp: ftp).map(\.text)
    }

    /// The lines with how hard each is at its hardest (a fraction of FTP), to colour them by zone.
    public static func outline(_ w: Workout, ftp: Double) -> [(text: String, intensity: Double)] {
        parts(w.steps).map { (text($0, ftp: ftp), intensity($0)) }
    }

    static func text(_ p: Part, ftp: Double) -> String {
        switch p {
        case .step(let s):
            return text(s, ftp: ftp)
        case .stairs(let n, let seconds, let from, let to):
            return "\(n) × \(duration(seconds)), \(to > from ? "rising" : "dropping") from \(pct(from)) to \(pct(to)) %"
        case .ladder(let works, let rests):
            // "3, 6, 9, 6 and 3 min at 100 % (250 W)" when the power holds; each with its own power when it doesn't.
            let fractions = works.compactMap { $0.fraction(at: 0) }
            let body: String
            if let f = fractions.first, fractions.allSatisfy({ abs($0 - f) < 0.005 }),
               works.allSatisfy({ $0.seconds % 60 == 0 }) {
                body = list(works.map { "\($0.seconds / 60)" }) + " min at \(pct(f)) % (\(Int((f * ftp).rounded())) W)"
            } else {
                body = list(works.map { "\(duration($0.seconds)) at \(pct($0.fraction(at: 0) ?? 0)) %" })
            }
            let restsAlike = rests.dropFirst().allSatisfy { alike(.step($0), .step(rests[0])) }
            return body + (restsAlike ? ", \(text(rests[0], ftp: ftp)) between" : ", easy between")
        case .efforts(let seconds, let low, let high):
            return "\(duration(seconds)) of efforts between \(pct(low)) and \(pct(high)) % (\(Int((low * ftp).rounded()))–\(Int((high * ftp).rounded())) W)"
        case .repeated(let n, let work, let rest):
            let isSet = work.count == 1 && { if case .repeated = work[0] { true } else { false } }()
            let body = work.count == 1 ? text(work[0], ftp: ftp) : "(" + work.map { text($0, ftp: ftp) }.joined(separator: ", ") + ")"
            let head = isSet ? "\(n) sets of \(body)" : "\(n) × \(body)"
            guard let rest else { return head }
            return head + ", \(text(rest, ftp: ftp)) between" + (isSet ? " sets" : "")
        }
    }

    static func text(_ s: Workout.Step, ftp: Double) -> String {
        let time = duration(s.seconds)
        let label = s.label.lowercased()
        let cadence = s.cadence.map { " at \($0.lowerBound)–\($0.upperBound) rpm" } ?? ""
        if let grade = s.grade {
            let target = s.fraction(at: 0).map { ", around \(pct($0)) %" } ?? ""
            return "\(time) climbing at \(String(format: "%g", grade)) %\(target)\(cadence)"
        }
        switch s.target {
        case .free:
            return "\(time) free riding, no target\(cadence)"
        case .ramp(let a, let b):
            let name = label.contains("warm") ? " warm-up" : label.contains("cool") ? " cool-down" : ""
            return "\(time)\(name), \(pct(a)) → \(pct(b)) %\(cadence)"
        case .steady(let f):
            if label.contains("warm") || label.contains("cool") {
                return "\(time) \(label.contains("warm") ? "warm-up" : "cool-down") at \(pct(f)) %\(cadence)"
            }
            if f < 0.6 { return "\(time) easy\(cadence)" }
            return "\(time) at \(pct(f)) % (\(Int((f * ftp).rounded())) W)\(cadence)"
        }
    }

    /// "3, 6 and 9".
    static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// "30 s", "1:30", "20 min", "1 h 30"; past a minute, to the nearest 5 s.
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let s = Int((Double(seconds) / 5).rounded()) * 5
        if s % 60 != 0 { return String(format: "%d:%02d", s / 60, s % 60) }
        let m = s / 60
        return m >= 90 && m % 60 != 0 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : m >= 60 && m % 60 == 0 ? "\(m / 60) h" : "\(m) min"
    }

    static func pct(_ f: Double) -> Int { Int((f * 100).rounded()) }

    // MARK: Zones

    /// Seconds the targets spend in each of the seven power zones; free riding counts as zone 1.
    public static func zoneSeconds(_ w: Workout) -> [Int] {
        var out = Array(repeating: 0, count: PowerZones.names.count)
        for s in w.steps {
            for t in 0..<s.seconds {
                let f = s.fraction(at: Double(t) + 0.5) ?? 0.5
                out[PowerZones.zone(powerW: f * 100, ftp: 100) - 1] += 1
            }
        }
        return out
    }
}
