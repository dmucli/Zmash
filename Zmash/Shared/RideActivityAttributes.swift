import ActivityKit
import Foundation

/// A ride as a Live Activity on iPhone (D103): shared by the app, which starts and updates it, and the widget
/// extension, which draws it on the lock screen and in the Dynamic Island.
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var powerW: Int
        /// When the clock would have started had it never paused, so the lock screen counts on its own.
        var clockStart: Date
        var elapsed: Int
        var paused: Bool
        var finished: Bool
        /// "12.4 km to go", "−23:10", or nil on an open ride.
        var toGo: String?
        var gear: String
        var gradePercent: Double
        var heartRateBpm: Int?
        /// In a workout: the step and its target.
        var step: String?
        var targetW: Int?
    }

    /// What's being ridden: a route, a workout, or "Free ride".
    var title: String
}
