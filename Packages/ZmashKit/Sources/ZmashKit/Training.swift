import Foundation

/// Training metrics from 1 Hz power (roadmap Phase 7).
public enum Training {
    /// Durations (s) for the power curve and personal bests.
    public static let curveDurations = [5, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600]

    /// Best average power for each duration that fits in the ride (sliding window over 1 Hz samples).
    public static func powerCurve(_ watts: [Int], durations: [Int] = curveDurations) -> [Int: Int] {
        guard !watts.isEmpty else { return [:] }
        var prefix = [0]
        prefix.reserveCapacity(watts.count + 1)
        for w in watts { prefix.append(prefix.last! + max(0, w)) }
        var out: [Int: Int] = [:]
        for d in durations where d <= watts.count {
            var best = 0
            for i in d...watts.count { best = max(best, prefix[i] - prefix[i - d]) }
            out[d] = Int((Double(best) / Double(d)).rounded())
        }
        return out
    }

    /// Merges curves keeping the best value per duration.
    public static func best(of curves: [[Int: Int]]) -> [Int: Int] {
        curves.reduce(into: [Int: Int]()) { acc, c in
            for (d, w) in c { acc[d] = max(acc[d] ?? 0, w) }
        }
    }

    /// Normalized Power: 4th-power mean of the 30 s rolling average.
    public static func normalizedPower(_ watts: [Int]) -> Double {
        guard watts.count >= 30 else { return watts.isEmpty ? 0 : Double(watts.reduce(0, +)) / Double(watts.count) }
        var sum = watts[0..<30].reduce(0, +)
        var acc = pow(Double(sum) / 30, 4)
        var n = 1.0
        for i in 30..<watts.count {
            sum += watts[i] - watts[i - 30]
            acc += pow(Double(sum) / 30, 4)
            n += 1
        }
        return pow(acc / n, 0.25)
    }

    public struct Load: Equatable, Sendable {
        public var normalizedPower: Double
        public var intensityFactor: Double
        public var tss: Double
    }

    /// TSS = seconds × NP × IF / (FTP × 3600) × 100.
    public static func load(_ watts: [Int], ftp: Double) -> Load {
        let np = normalizedPower(watts)
        let f = max(ftp, 1)
        let ifac = np / f
        return Load(normalizedPower: np, intensityFactor: ifac, tss: Double(watts.count) * np * ifac / (f * 3600) * 100)
    }

    /// FTP estimate: 95 % of the best 20-minute power (nil without a 20-minute effort).
    public static func estimateFTP(curve: [Int: Int]) -> Int? {
        curve[1200].map { Int((Double($0) * 0.95).rounded()) }
    }

    /// Ramp test FTP: 75 % of the best 1-minute power.
    public static func rampTestFTP(watts: [Int]) -> Int? {
        powerCurve(watts, durations: [60])[60].map { Int((Double($0) * 0.75).rounded()) }
    }

    /// Durations where `ride` beat `previous` (new personal bests), longest first.
    public static func newBests(ride: [Int: Int], previous: [Int: Int]) -> [(duration: Int, watts: Int)] {
        ride.filter { d, w in w > (previous[d] ?? 0) && (previous[d] ?? 0) > 0 }
            .map { (duration: $0.key, watts: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    public static func durationLabel(_ s: Int) -> String {
        s < 60 ? "\(s) s" : s < 3600 ? "\(s / 60) min" : "\(s / 3600) h"
    }
}
