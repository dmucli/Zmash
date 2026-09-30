import Foundation
import Testing
@testable import ZmashKit

/// intervals.icu's planned workouts (D153), from a response shaped like the API's.
@Suite struct IntervalsCalendarTests {
    private let json = """
    [
      {"id": 42, "category": "WORKOUT", "type": "Ride", "name": "Threshold 3x12", "start_date_local": "2026-09-26T00:00:00",
       "moving_time": 3600, "icu_training_load": 78, "description": "Hold it."},
      {"id": 41, "category": "WORKOUT", "type": "VirtualRide", "name": "", "start_date_local": "2026-09-25T00:00:00"},
      {"id": 43, "category": "WORKOUT", "type": "Run", "name": "Tempo run", "start_date_local": "2026-09-25T00:00:00"},
      {"id": 44, "category": "NOTE", "name": "Rest", "start_date_local": "2026-09-27T00:00:00"},
      {"category": "WORKOUT", "name": "No id", "start_date_local": "2026-09-27T00:00:00"}
    ]
    """

    @Test func ridesOnlySoonestFirst() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let events = try IntervalsCalendar.events(Data(json.utf8), calendar: cal)
        #expect(events.map(\.id) == [41, 42])
        #expect(events[0].name == "Planned workout")
        #expect(events[1].movingSeconds == 3600 && events[1].load == 78)
        #expect(cal.component(.day, from: events[1].day) == 26)
    }

    @Test func urls() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let from = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21
        let url = IntervalsCalendar.eventsURL(athlete: "123456", from: from, to: from.addingTimeInterval(6 * 86_400), calendar: cal)
        #expect(url.absoluteString == "https://intervals.icu/api/v1/athlete/i123456/events?oldest=2026-09-21&newest=2026-09-27&category=WORKOUT")
        #expect(IntervalsCalendar.downloadURL(athlete: "i9", event: 42).absoluteString
                == "https://intervals.icu/api/v1/athlete/i9/events/42/download.zwo")
    }
}
