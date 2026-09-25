import Foundation
import ZmashKit

/// The bundled workout catalog (D154): about 2,500 Zwift and Sufferfest workouts in some 135 collections, built by
/// `make workouts` into Resources/Workouts/catalog.json. Read once (launch warms it up off the main thread), sorted by
/// collection then name; a workout is built from its entry when it's shown or ridden.
enum WorkoutCatalog {
    static let entries: [WorkoutCatalogFile.Entry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(WorkoutCatalogFile.self, from: data) else { return [] }
        return file.workouts.sorted { a, b in
            if a.collection != b.collection { return a.collection.localizedStandardCompare(b.collection) == .orderedAscending }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }()

    private static let byID: [String: WorkoutCatalogFile.Entry] = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// The collections, A to Z.
    static let collections: [String] = Array(Set(entries.map(\.collection))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    static func entry(id: String) -> WorkoutCatalogFile.Entry? { byID[id] }

    static func workout(id: String) -> Workout? { byID[id]?.workout }
}
