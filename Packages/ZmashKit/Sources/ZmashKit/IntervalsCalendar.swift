import Foundation

/// The workouts planned on an intervals.icu calendar (D153), as its API lists them: `GET /api/v1/athlete/{id}/events`
/// with `category=WORKOUT`, each then downloaded as a `.zwo` (`…/events/{eventId}/download.zwo`). Written from the
/// public API; the idea came from Auuki.
public enum IntervalsCalendar {
    public struct Event: Equatable, Sendable, Identifiable {
        public let id: Int
        /// The day it's planned for, at midnight local time.
        public let day: Date
        public let name: String
        public let description: String?
        /// Planned length and load, when the calendar has them.
        public let movingSeconds: Int?
        public let load: Int?
    }

    /// The events API for the days `from` … `to` (inclusive), workouts only.
    public static func eventsURL(athlete: String, from: Date, to: Date, calendar: Calendar = .current) -> URL {
        var c = URLComponents(string: "https://intervals.icu/api/v1/athlete/\(athleteID(athlete))/events")!
        c.queryItems = [URLQueryItem(name: "oldest", value: day(from, calendar)),
                        URLQueryItem(name: "newest", value: day(to, calendar)),
                        URLQueryItem(name: "category", value: "WORKOUT")]
        return c.url!
    }

    /// One planned workout's file, as Zwift's `.zwo`.
    public static func downloadURL(athlete: String, event: Int) -> URL {
        URL(string: "https://intervals.icu/api/v1/athlete/\(athleteID(athlete))/events/\(event)/download.zwo")!
    }

    /// The athlete id as the API wants it: "i123456" (people often copy just the number).
    public static func athleteID(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("i") ? t : "i" + t
    }

    /// The planned rides in an events response, soonest first: workouts only, rides only (not runs or swims).
    public static func events(_ data: Data, calendar: Calendar = .current) throws -> [Event] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let parse = DateFormatter()
        parse.calendar = Calendar(identifier: .gregorian)
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = calendar.timeZone
        parse.dateFormat = "yyyy-MM-dd"
        return list.compactMap { e -> Event? in
            guard let id = e["id"] as? Int,
                  (e["category"] as? String ?? "WORKOUT") == "WORKOUT",
                  let start = e["start_date_local"] as? String,
                  let day = parse.date(from: String(start.prefix(10))) else { return nil }
            let type = (e["type"] as? String ?? "Ride").lowercased()
            guard type.contains("ride") else { return nil }
            let name = (e["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Planned workout"
            return Event(id: id, day: day, name: name, description: e["description"] as? String,
                         movingSeconds: e["moving_time"] as? Int, load: e["icu_training_load"] as? Int)
        }
        .sorted { ($0.day, $0.id) < ($1.day, $1.id) }
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
