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

    /// Any route by id: a race stage ("race/…"), a bundled climb or an import, optionally cut to a
    /// segment ("…#fromM-toM"). The segment lives in the id, so history and the ghost follow it for free.
    static func route(id: String) -> Route? {
        let (base, segment) = split(id)
        let found = base.hasPrefix("race/") ? RaceStore.route(id: base)
            : ClimbLibrary.route(id: base) ?? importedRoute(id: base)
        guard let route = found else { return nil }
        guard let segment else { return route }
        return route.slice(fromM: segment.lowerBound, toM: segment.upperBound, id: id,
                           name: "\(route.name) · km \(Int(segment.lowerBound / 1000))–\(Int((segment.upperBound / 1000).rounded()))")
    }

    /// The id of part of a route.
    static func segmentID(_ base: String, fromM: Double, toM: Double) -> String {
        "\(split(base).base)#\(Int(fromM.rounded()))-\(Int(toM.rounded()))"
    }

    static func split(_ id: String) -> (base: String, segment: ClosedRange<Double>?) {
        let parts = id.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else { return (id, nil) }
        let bounds = parts[1].split(separator: "-").compactMap { Double($0) }
        guard bounds.count == 2, bounds[1] > bounds[0] else { return (String(parts[0]), nil) }
        return (String(parts[0]), bounds[0]...bounds[1])
    }

    /// One imported route, read straight from its file (no need to load them all).
    private static func importedRoute(id: String) -> Route? {
        (try? Data(contentsOf: directory.appending(path: id + ".json"))).flatMap { try? JSONDecoder().decode(Route.self, from: $0) }
    }

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
