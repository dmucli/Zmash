import Foundation
import Observation
import ZmashKit

/// The next week's workouts planned on intervals.icu (D153), read with the same athlete ID and API key as uploads.
/// Each is downloaded as a `.zwo` and kept on the iPad under "icu/<event>", so a ride on one can be ridden again from
/// History, and it's still there offline.
@MainActor @Observable
final class PlannedWorkouts {
    static let shared = PlannedWorkouts()

    struct Entry: Identifiable, Equatable {
        /// The workout's id: "icu/<event id>".
        let id: String
        let day: Date
        let workout: Workout
    }

    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var entries: [Entry] = []
    private(set) var state = State.idle
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var fetchedFor: String?

    var connected: Bool { UploadSettings.intervalsConnected }

    /// Today's, if one is planned.
    var today: Entry? { entries.first { Calendar.current.isDateInToday($0.day) } }

    /// Fetches again unless it did less than 10 minutes ago for this rider.
    func refreshIfStale() async {
        let rider = Riders.currentID
        if fetchedFor == rider, let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 600 { return }
        await refresh()
    }

    func refresh() async {
        #if DEBUG
        if DebugLaunch.intervalsFixture { loadFixture(); return }
        #endif
        let rider = Riders.currentID
        guard connected else {
            entries = []
            state = .idle
            return
        }
        state = .loading
        let athlete = UploadSettings.intervalsAthleteID, key = UploadSettings.intervalsKey
        do {
            let today = Calendar.current.startOfDay(for: .now)
            let events = try IntervalsCalendar.events(
                try await get(IntervalsCalendar.eventsURL(athlete: athlete, from: today,
                                                          to: Calendar.current.date(byAdding: .day, value: 6, to: today)!), key: key))
            var found: [Entry] = []
            for e in events {
                let id = "icu/\(e.id)"
                // A file already kept is used as is: a planned workout doesn't change often, and it saves a request.
                if let kept = Self.workout(id: id), kept.name == e.name || e.name == "Planned workout" {
                    found.append(Entry(id: id, day: e.day, workout: kept))
                    continue
                }
                guard let data = try? await get(IntervalsCalendar.downloadURL(athlete: athlete, event: e.id), key: key),
                      var w = ZWOParser.parse(data, id: id) else { continue }
                w.name = e.name
                if let d = e.description, !d.isEmpty { w.summary = d }
                Self.keep(w)
                found.append(Entry(id: id, day: e.day, workout: w))
            }
            guard Riders.currentID == rider else { return }
            entries = found
            state = .loaded
            fetchedAt = .now
            fetchedFor = rider
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// When the rider changes or disconnects: forget what was shown.
    func reset() {
        entries = []
        state = .idle
        fetchedAt = nil
        fetchedFor = nil
    }

    private func get(_ url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw UploadError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    private static func describe(_ error: Error) -> String {
        if case UploadError.http(let code, _) = error {
            return code == 401 || code == 403 ? "intervals.icu didn't accept the API key. Check it in Settings → Uploads."
                                               : "intervals.icu answered with an error (\(code))."
        }
        return "Couldn't reach intervals.icu. Check the connection."
    }

    // MARK: Kept files

    private static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Planned", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ id: String) -> URL {
        directory.appending(path: id.replacingOccurrences(of: "/", with: "-") + ".json")
    }

    /// A kept planned workout, by its "icu/…" id.
    nonisolated static func workout(id: String) -> Workout? {
        let url = URL.applicationSupportDirectory.appending(path: "Planned", directoryHint: .isDirectory)
            .appending(path: id.replacingOccurrences(of: "/", with: "-") + ".json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Workout.self, from: $0) }
    }

    private static func keep(_ w: Workout) {
        try? JSONEncoder().encode(w).write(to: file(w.id), options: .atomic)
    }

    #if DEBUG
    /// -ZmashIntervalsFixture YES: three planned workouts made from the library, no network.
    private func loadFixture() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let picks: [(Int, String, String)] = [(0, "threshold-3x12", "Threshold 3 × 12 (coach)"),
                                              (2, "vo2-30-30", "30/30s, 3 sets"),
                                              (4, "endurance-90", "Long Z2")]
        entries = picks.compactMap { offset, lib, name in
            guard var w = WorkoutLibrary.all.first(where: { $0.id == lib }) else { return nil }
            w.id = "icu/\(9000 + offset)"
            w.name = name
            w.category = nil
            Self.keep(w)
            return Entry(id: w.id, day: cal.date(byAdding: .day, value: offset, to: today)!, workout: w)
        }
        state = .loaded
    }
    #endif
}
