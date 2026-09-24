import Foundation

/// A route shared as a link (D141): which service it's from, and where its profile can be downloaded.
public enum RouteLink: Equatable, Sendable {
    /// A RideWithGPS route or trip; public ones download as GPX.
    case rideWithGPS(kind: String, id: String)
    /// A Komoot tour; a private one shared with a link carries its share token.
    case komoot(id: String, shareToken: String?)
    /// A Strava route; downloaded through the API with the rider's own account.
    case strava(id: String)
    /// A link straight to a GPX or FIT file.
    case file(URL)

    /// The link in some text (a pasted link, a line with a link in it), or nil if it isn't one this knows.
    public static func parse(_ text: String) -> RouteLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.split(whereSeparator: \.isWhitespace).first { $0.contains("://") || $0.contains(".com/") }
            .map(String.init) ?? trimmed
        guard var components = URLComponents(string: candidate.contains("://") ? candidate : "https://" + candidate),
              let host = components.host?.lowercased() else { return nil }
        components.scheme = components.scheme?.lowercased()
        let path = components.path.split(separator: "/").map(String.init)
        func id(after key: String) -> String? {
            guard let i = path.firstIndex(of: key), i + 1 < path.count else { return nil }
            let digits = path[i + 1].prefix { $0.isNumber }
            return digits.isEmpty ? nil : String(digits)
        }
        if host.hasSuffix("ridewithgps.com") {
            if let n = id(after: "routes") { return .rideWithGPS(kind: "routes", id: n) }
            if let n = id(after: "trips") { return .rideWithGPS(kind: "trips", id: n) }
            return nil
        }
        if host.contains("komoot.") {
            guard let n = id(after: "tour") else { return nil }
            let token = components.queryItems?.first { $0.name == "share_token" }?.value
            return .komoot(id: n, shareToken: token)
        }
        if host.hasSuffix("strava.com") {
            return id(after: "routes").map { .strava(id: $0) }
        }
        let ext = (components.path as NSString).pathExtension.lowercased()
        if ext == "gpx" || ext == "fit", let url = components.url { return .file(url) }
        return nil
    }

    /// Where the profile downloads from (for Strava, the API endpoint, which needs the rider's token).
    public var downloadURL: URL? {
        switch self {
        case .rideWithGPS(let kind, let id):
            URL(string: "https://ridewithgps.com/\(kind)/\(id).gpx?sub_format=track")
        case .komoot(let id, let token):
            URL(string: "https://www.komoot.com/api/v007/tours/\(id)/coordinates" + (token.map { "?share_token=\($0)" } ?? ""))
        case .strava(let id):
            URL(string: "https://www.strava.com/api/v3/routes/\(id)/export_gpx")
        case .file(let url):
            url
        }
    }

    /// Komoot's tour details (for its name).
    public var komootTourURL: URL? {
        guard case .komoot(let id, let token) = self else { return nil }
        return URL(string: "https://www.komoot.com/api/v007/tours/\(id)" + (token.map { "?share_token=\($0)" } ?? ""))
    }

    /// The service's name, for messages.
    public var sourceName: String {
        switch self {
        case .rideWithGPS: "RideWithGPS"
        case .komoot: "Komoot"
        case .strava: "Strava"
        case .file: "the link"
        }
    }

    /// Komoot's tour coordinates (`{"items": [{"lat", "lng", "alt"}, …]}`) as a track, or nil.
    public static func komootTrack(_ data: Data) -> [(lat: Double, lon: Double, ele: Double)]? {
        struct Coordinates: Decodable {
            struct Item: Decodable { let lat: Double; let lng: Double; let alt: Double? }
            let items: [Item]
        }
        guard let c = try? JSONDecoder().decode(Coordinates.self, from: data), c.items.count > 1,
              c.items.contains(where: { $0.alt != nil }) else { return nil }
        return c.items.compactMap { i in i.alt.map { (i.lat, i.lng, $0) } }
    }
}
