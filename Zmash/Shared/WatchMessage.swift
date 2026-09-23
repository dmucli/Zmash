import Foundation

/// What the iPhone and the Watch tell each other over the mirrored workout session (D105).
struct WatchMessage: Codable, Equatable {
    enum Kind: String, Codable {
        /// Watch → phone: heart rate.
        case heartRate
        /// Watch → phone: a rider command (pause, shift).
        case command
        /// Phone → watch: the ride now.
        case ride
        /// Phone → watch: the ride ended; keep the watch's own workout or not.
        case end
    }

    struct Ride: Codable, Equatable {
        var title: String
        var powerW: Int
        var elapsed: Int
        var gear: String
        var gradePercent: Double
        var paused: Bool
    }

    var kind: Kind
    var heartRateBpm: Int?
    /// A `RideCommand` raw value ("pauseToggle", "shiftUp", "shiftDown").
    var command: String?
    var ride: Ride?
    var keepWorkout: Bool?

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> WatchMessage? { try? JSONDecoder().decode(WatchMessage.self, from: data) }
}
