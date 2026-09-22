import Foundation
import ZmashKit

/// The built-in workout library plus workouts imported from `.zwo` files (kept in UserDefaults; they're tiny).
enum WorkoutStore {
    private static let key = "workouts.imported"

    static var imported: [Workout] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Workout].self, from: $0) } ?? []
    }

    static var all: [Workout] { WorkoutLibrary.all + imported }

    static func workout(id: String) -> Workout? { all.first { $0.id == id } }

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

    static func delete(id: String) {
        save(imported.filter { $0.id != id })
    }

    private static func save(_ list: [Workout]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
