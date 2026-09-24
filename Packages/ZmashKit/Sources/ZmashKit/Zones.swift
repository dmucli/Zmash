import Foundation

/// Where a ride's effort went (D140): seconds in each power zone (from FTP, the faces' seven zones) and each
/// heart-rate zone (five, from maximum heart rate).
public enum Zones {
    /// Upper bounds of heart-rate zones 1–4 as a fraction of maximum; zone 5 is everything above.
    public static let heartCuts = [0.6, 0.7, 0.8, 0.9]
    public static let heartNames = ["Z1 easy", "Z2 endurance", "Z3 tempo", "Z4 threshold", "Z5 maximum"]

    /// Seconds in each power zone (7), one sample a second. Freewheeling counts as zone 1.
    public static func powerSeconds(_ samples: [RideSample], ftp: Double) -> [Int] {
        var out = Array(repeating: 0, count: PowerZones.names.count)
        for s in samples { out[PowerZones.zone(powerW: Double(s.powerW), ftp: ftp) - 1] += 1 }
        return out
    }

    public static func heartZone(bpm: Double, max: Double) -> Int {
        let r = bpm / Swift.max(max, 1)
        for (i, c) in heartCuts.enumerated() where r < c { return i + 1 }
        return heartCuts.count + 1
    }

    /// Seconds in each heart-rate zone (5), or nil when the ride has no heart rate.
    public static func heartSeconds(_ samples: [RideSample], maxHR: Double) -> [Int]? {
        var out = Array(repeating: 0, count: heartNames.count)
        var any = false
        for s in samples {
            guard let bpm = s.heartRateBpm, bpm > 0 else { continue }
            out[heartZone(bpm: Double(bpm), max: maxHR) - 1] += 1
            any = true
        }
        return any ? out : nil
    }

    /// The highest heart rate held for 5 s (a lone spike from a strap doesn't count), or nil without heart rate.
    public static func peakHeartRate(_ samples: [RideSample]) -> Int? {
        let hr = samples.map { $0.heartRateBpm ?? 0 }
        guard hr.count >= 5, hr.contains(where: { $0 > 0 }) else { return nil }
        var best = 0
        for i in 0...(hr.count - 5) {
            let window = hr[i..<(i + 5)]
            guard !window.contains(0) else { continue }
            best = Swift.max(best, window.min()!)
        }
        return best > 0 ? best : nil
    }
}
