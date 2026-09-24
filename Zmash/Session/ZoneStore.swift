import Foundation
import ZmashKit

/// Each ride's time in zones (D140), worked out once from its samples and kept in a small file, so Progress doesn't
/// decode every ride. Worked out again if FTP or maximum heart rate has changed since.
@MainActor
enum ZoneStore {
    struct Entry: Codable, Equatable {
        var ftp: Int
        var maxHR: Int?
        /// Seconds in power zones 1–7.
        var power: [Int]
        /// Seconds in heart-rate zones 1–5; nil without heart rate or a maximum.
        var heart: [Int]?
        /// The highest heart rate held for 5 s, for suggesting a maximum.
        var peakHR: Int?
    }

    private static var url: URL { URL.applicationSupportDirectory.appending(path: "zones.json") }
    private static var cache: [UUID: Entry] = {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([UUID: Entry].self, from: $0) } ?? [:]
    }()

    static func zones(_ session: RideSession, prefs: Preferences = .shared) -> Entry {
        zones(id: session.id, prefs: prefs) { session.samples }
    }

    static func zones(_ ride: FinishedRide, prefs: Preferences = .shared) -> Entry {
        zones(id: ride.id, prefs: prefs) { ride.samples }
    }

    private static func zones(id: UUID, prefs: Preferences, samples: () -> [RideSample]) -> Entry {
        if let hit = cache[id], hit.ftp == prefs.ftp, hit.maxHR == prefs.maxHeartRate { return hit }
        let s = samples()
        let entry = Entry(ftp: prefs.ftp, maxHR: prefs.maxHeartRate,
                          power: Zones.powerSeconds(s, ftp: Double(prefs.ftp)),
                          heart: prefs.maxHeartRate.flatMap { Zones.heartSeconds(s, maxHR: Double($0)) },
                          peakHR: Zones.peakHeartRate(s))
        cache[id] = entry
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
        return entry
    }

    /// A deleted ride's entry goes too.
    static func forget(_ id: UUID) {
        guard cache.removeValue(forKey: id) != nil else { return }
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }

    /// A maximum heart rate to suggest: the highest held for 5 s over these rides (the last 90 days').
    static func suggestedMaxHR(_ sessions: [RideSession], prefs: Preferences = .shared) -> Int? {
        sessions.compactMap { zones($0, prefs: prefs).peakHR }.max()
    }
}
