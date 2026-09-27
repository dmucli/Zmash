import Foundation
import ZmashKit

/// The bundled workout catalog (D154, D155): about 2,500 Zwift and Sufferfest workouts in some 135 collections, built by
/// `make workouts` into Resources/Workouts/catalog.json. Read once (launch warms it up off the main thread).
/// Collections that are training plans are kept apart: their workouts are sessions, listed in order on the Plan page and
/// never among the standalone workouts.
enum WorkoutCatalog {
    /// A catalog plan: a collection whose workouts are the sessions of a programme.
    struct Plan: Identifiable, Sendable {
        var id: String { collection }
        let collection: String
        let goal: TrainingPlan.Goal
        /// In order: by week, then session number, then name.
        let sessions: [WorkoutCatalogFile.Entry]
        /// Weeks, when the session names give them.
        let weeks: Int?
        /// Who it's from, as the files say ("Zwift"), when they agree.
        let author: String?

        var totalSeconds: Int { sessions.reduce(0) { $0 + $1.seconds } }
    }

    private static let file: WorkoutCatalogFile? = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutCatalogFile.self, from: data)
    }()

    private static let planGoals: [String: TrainingPlan.Goal] = Dictionary(
        (file?.plans ?? []).map { ($0.collection, TrainingPlan.Goal(rawValue: $0.goal) ?? .build) }, uniquingKeysWith: { a, _ in a })

    /// Every entry, plans' sessions included (for finding one by id).
    private static let all: [WorkoutCatalogFile.Entry] = file?.workouts ?? []

    private static let byID: [String: WorkoutCatalogFile.Entry] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// The standalone workouts, by collection then name.
    static let entries: [WorkoutCatalogFile.Entry] = all.filter { planGoals[$0.collection] == nil }.sorted { a, b in
        if a.collection != b.collection { return a.collection.localizedStandardCompare(b.collection) == .orderedAscending }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// The standalone workouts' collections, A to Z.
    static let collections: [String] = Array(Set(entries.map(\.collection))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    /// The plans, A to Z.
    static let plans: [Plan] = {
        let grouped = Dictionary(grouping: all.filter { planGoals[$0.collection] != nil }, by: \.collection)
        return grouped.map { collection, sessions in
            let ordered = sessions.map { ($0, WorkoutCatalogFile.sessionOrder($0.name)) }.sorted { a, b in
                let wa = a.1.week ?? 0, wb = b.1.week ?? 0
                if wa != wb { return wa < wb }
                let ia = a.1.index ?? .max, ib = b.1.index ?? .max
                if ia != ib { return ia < ib }
                return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
            }
            let weeks = ordered.compactMap(\.1.week).max()
            let authors = Set(sessions.compactMap { $0.author?.replacingOccurrences(of: " (via whatsonzwift.com)", with: "") })
            return Plan(collection: collection, goal: planGoals[collection] ?? .build, sessions: ordered.map(\.0),
                        weeks: weeks.map { max($0, 1) }, author: authors.count == 1 ? authors.first : nil)
        }
        .sorted { $0.collection.localizedStandardCompare($1.collection) == .orderedAscending }
    }()

    static func plan(_ collection: String) -> Plan? { plans.first { $0.collection == collection } }

    static func entry(id: String) -> WorkoutCatalogFile.Entry? { byID[id] }

    static func workout(id: String) -> Workout? { byID[id]?.workout }

    /// Which catalog plan a session belongs to, if any.
    static func planCollection(of id: String) -> String? {
        byID[id].flatMap { planGoals[$0.collection] == nil ? nil : $0.collection }
    }
}
