import Foundation
import ZmashKit

/// The bundled workout catalog (D154, D155): about 2,500 Zwift and Sufferfest workouts in some 135 collections, built by
/// `make workouts` into Resources/Workouts/catalog.json. Read once (launch warms it up off the main thread).
/// Collections that are training plans are kept apart: their workouts are sessions, and the plans are on the Plan page,
/// to enrol in like Zmash's (D156), never among the standalone workouts.
/// Only in your own builds (D166): the content isn't ours to publish, so a Release build has no catalog, and everything
/// here is empty.
enum WorkoutCatalog {
    private static let file: WorkoutCatalogFile? = {
        #if !ZMASH_CATALOG
        return nil
        #else
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutCatalogFile.self, from: data)
        #endif
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

    /// The plans as training plans (D156), A to Z: ids "zc-<collection>", sessions `.workout` of their `zc/` ids.
    static let plans: [TrainingPlan] = Dictionary(grouping: all.filter { planGoals[$0.collection] != nil }, by: \.collection)
        .map { collection, sessions in
            WorkoutCatalogFile.trainingPlan(collection: collection, goal: planGoals[collection] ?? .build, sessions: sessions)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private static let plansByID: [String: TrainingPlan] = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func plan(id: String) -> TrainingPlan? { plansByID[id] }

    /// Whether this build has the catalog: a Debug build on a Mac where `make workouts` ran (D166, D169).
    static var isBuilt: Bool { file != nil }

    static func entry(id: String) -> WorkoutCatalogFile.Entry? { byID[id] }

    static func workout(id: String) -> Workout? { byID[id]?.workout }
}
