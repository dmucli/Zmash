import Foundation
import ZmashKit

/// The built-in workout library plus your own: imported from `.zwo` files or made in the builder (kept in UserDefaults;
/// they're tiny).
enum WorkoutStore {
    private static let key = "workouts.imported"

    static var imported: [Workout] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Workout].self, from: $0) } ?? []
    }

    static var all: [Workout] { WorkoutLibrary.all + imported }

    static func workout(id: String) -> Workout? {
        if id.hasPrefix("plan/") { return PlanStore.workout(id: id) }
        if id.hasPrefix("icu/") { return PlannedWorkouts.workout(id: id) }
        return all.first { $0.id == id }
    }

    /// Imports a `.zwo` file; returns the workout or nil if it isn't one.
    @discardableResult
    static func importZWO(from url: URL) -> Workout? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let w = ZWOParser.parse(data, id: "zwo-" + UUID().uuidString) else { return nil }
        save(imported + [w])
        return w
    }

    /// Adds or replaces one of your workouts.
    static func save(_ w: Workout) {
        var list = imported
        if let i = list.firstIndex(where: { $0.id == w.id }) { list[i] = w } else { list.append(w) }
        save(list)
    }

    static func delete(id: String) {
        save(imported.filter { $0.id != id })
    }

    private static func save(_ list: [Workout]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
