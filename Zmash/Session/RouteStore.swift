import Foundation
import ZmashKit

/// The bundled climbs plus routes imported from GPX or FIT files.
/// Imported routes are JSON files in Application Support (a long route is too big for UserDefaults).
enum RouteStore {
    private static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Routes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var imported: [Route] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Route.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    static var all: [Route] { ClimbLibrary.all + imported }

    static func route(id: String) -> Route? { all.first { $0.id == id } }

    /// Imports a GPX or FIT file; returns the route, or nil if it holds no usable profile.
    @discardableResult
    static func importFile(from url: URL) -> Route? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let id = "file-" + UUID().uuidString
        let name = url.deletingPathExtension().lastPathComponent
        var route = url.pathExtension.lowercased() == "fit"
            ? FITRouteReader.parse(data, id: id, name: name)
            : GPXParser.parse(data, id: id)
        // Either format can turn up under the other's extension; try the other one before giving up.
        if route == nil { route = FITRouteReader.parse(data, id: id, name: name) ?? GPXParser.parse(data, id: id) }
        guard var route, route.distanceM >= 500 else { return nil }
        if route.name.isEmpty || route.name == "Imported route" { route.name = name }
        route.place = "Imported"
        save(route)
        return route
    }

    static func save(_ route: Route) {
        try? JSONEncoder().encode(route).write(to: directory.appending(path: route.id + ".json"))
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: id + ".json"))
    }
}
