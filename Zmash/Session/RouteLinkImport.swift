import Foundation
import ZmashKit

/// Imports a route from a pasted link (D141): RideWithGPS, Komoot, Strava or a GPX/FIT file.
@MainActor
enum RouteLinkImport {
    enum Failure: LocalizedError {
        case notALink
        case notPublic(String)
        case noProfile
        case stravaNotConnected
        case stravaNeedsPermission
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notALink: "That isn't a route link Zmash knows: RideWithGPS, Komoot, Strava routes, or a link to a GPX or FIT file."
            case .notPublic(let source): "\(source) wouldn't share this route. Make it public, or share it with a link, and try again."
            case .noProfile: "There's no usable profile in this route: it needs elevation, and at least 500 m."
            case .stravaNotConnected: "Connect Strava in Settings → Uploads to import its routes."
            case .stravaNeedsPermission: "Reconnect Strava in Settings → Uploads: Zmash now also asks to read your routes."
            case .http(let code): "The download didn't work (\(code)). Try again in a moment."
            }
        }
    }

    static func route(from text: String) async throws -> Route {
        guard let link = RouteLink.parse(text), let url = link.downloadURL else { throw Failure.notALink }
        var request = URLRequest(url: url)
        if case .strava = link {
            guard UploadSettings.stravaConnected else { throw Failure.stravaNotConnected }
            request.setValue("Bearer \(try await UploadCenter.shared.stravaToken())", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401, 403, 404:
            // Strava says 401 when the account was connected without permission to read routes.
            if case .strava = link, (response as? HTTPURLResponse)?.statusCode == 401 { throw Failure.stravaNeedsPermission }
            throw Failure.notPublic(link.sourceName)
        case let code: throw Failure.http(code)
        }

        let id = "link-" + UUID().uuidString
        var route: Route?
        if case .komoot = link {
            let name = await komootName(link) ?? "Komoot tour"
            route = RouteLink.komootTrack(data).flatMap { RouteBuilder.fromTrack(id: id, name: name, track: $0) }
        } else {
            route = GPXParser.parse(data, id: id) ?? FITRouteReader.parse(data, id: id, name: "\(link.sourceName) route")
        }
        guard var route, route.distanceM >= 500 else { throw Failure.noProfile }
        if route.name.isEmpty || route.name == "Imported route" { route.name = "\(link.sourceName) route" }
        route.place = link.sourceName
        RouteStore.save(route)
        Diagnostics.log("routes", "imported \(route.name) from \(link.sourceName), \(Int(route.distanceM)) m")
        return route
    }

    /// A Komoot tour's name, from its details (the coordinates don't carry it).
    private static func komootName(_ link: RouteLink) async -> String? {
        guard let url = link.komootTourURL, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["name"] as? String
    }
}
