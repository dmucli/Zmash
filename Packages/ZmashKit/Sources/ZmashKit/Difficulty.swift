import Foundation

/// How hard a ride will be, 1 (easy) to 5 (very hard), at your own pace: its length, and whether it has steep
/// climbing in it; for a workout, the training load it asks for.
public enum Difficulty {
    /// A ride of `minutes` at your pace. Steep ground (a kilometre at 8 % or more, or 600 m or more of climbing an hour)
    /// makes it one step harder.
    public static func ride(minutes: Double, steepestPercent: Double = 0, climbingPerHourM: Double = 0) -> Int {
        let base = minutes < 20 ? 1 : minutes < 45 ? 2 : minutes < 90 ? 3 : minutes < 180 ? 4 : 5
        let steep = steepestPercent >= 8 || climbingPerHourM >= 600
        return min(base + (steep ? 1 : 0), 5)
    }

    /// A route at the estimate pace.
    public static func route(_ route: Route, estimatedSeconds: Double) -> Int {
        let hours = max(estimatedSeconds / 3600, 1.0 / 60)
        return ride(minutes: estimatedSeconds / 60, steepestPercent: route.steepestKmGrade, climbingPerHourM: route.ascentM / hours)
    }

    /// A workout, from the training load (TSS) it asks for.
    public static func workout(tss: Double) -> Int {
        tss < 25 ? 1 : tss < 45 ? 2 : tss < 65 ? 3 : tss < 90 ? 4 : 5
    }

    public static func label(_ level: Int) -> String {
        switch level {
        case ...1: "Easy"
        case 2: "Steady"
        case 3: "Moderate"
        case 4: "Hard"
        default: "Very hard"
        }
    }
}
