import Foundation

/// What the widgets show, written by the app into the shared App Group container (D104).
struct WidgetSummary: Codable, Equatable {
    static let appGroup = "group.com.davidmucelli.zmash"

    /// Monday-first: training load per day this week.
    var weekDays: [Double] = Array(repeating: 0, count: 7)
    var weekSeconds = 0
    var weekTSS = 0.0
    var weekRides = 0
    var form = 0.0
    /// "Fresh", "OK", "Tired".
    var formWord = "OK"
    /// The next thing to ride: "Threshold 3 × 10" and why ("Plan · today", "Your Tour · stage 7").
    var nextTitle: String?
    var nextDetail: String?
    var updated = Date.distantPast

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "widgets.json")
    }

    static func load() -> WidgetSummary? {
        url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetSummary.self, from: $0) }
    }

    func save() {
        guard let url = Self.url else { return }
        try? JSONEncoder().encode(self).write(to: url)
    }

    /// A placeholder for the widget gallery.
    static let sample = WidgetSummary(weekDays: [0, 62, 0, 88, 0, 45, 0], weekSeconds: 3 * 3600 + 20 * 60, weekTSS: 195,
                                      weekRides: 3, form: 6, formWord: "Fresh", nextTitle: "Threshold 3 × 10",
                                      nextDetail: "Plan · today", updated: .now)
}
