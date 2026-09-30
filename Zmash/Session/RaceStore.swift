import Foundation
import Synchronization
import ZmashKit

/// The bundled race catalog (Resources/Races/races.json, built from gpx/ by `make races`).
enum RaceStore {
    static let catalog: RaceCatalog = {
        guard let url = Bundle.main.url(forResource: "races", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(RaceCatalog.self, from: data) else { return RaceCatalog(races: []) }
        return catalog
    }()

    static var races: [Race] { catalog.races }

    static func races(_ kind: Race.Kind) -> [Race] { races.filter { $0.kind == kind } }

    /// "race/2026/tour-de-france/17" → the race and stage.
    static func stage(routeID: String) -> (race: Race, stage: Stage)? {
        guard routeID.hasPrefix("race/") else { return nil }
        let parts = routeID.dropFirst("race/".count).split(separator: "/")
        guard parts.count == 3, let number = Int(parts[2]) else { return nil }
        let raceID = "\(parts[0])/\(parts[1])"
        guard let race = races.first(where: { $0.id == raceID }),
              let stage = race.stages.first(where: { $0.number == number }) else { return nil }
        return (race, stage)
    }

    static func route(id: String) -> Route? {
        stage(routeID: id).map { $0.race.route($0.stage) }
    }

    /// Famous climbs cut from the races, by country (France first, where most of them are), then by name. Sorted once.
    static let climbs: [FamousClimb] = {
        let order = ["FR", "IT", "ES", "BE", "NL"]
        return catalog.climbs.sorted {
            let a = order.firstIndex(of: $0.country) ?? order.count, b = order.firstIndex(of: $1.country) ?? order.count
            return a != b ? a < b : ($0.name, $0.side) < ($1.name, $1.side)
        }
    }()

    private static let stageRoutes = Mutex<[String: [Route]]>([:])

    /// Every stage of a race as a route, built once per race (the race picker draws them all).
    static func routes(of race: Race) -> [Route] {
        if let hit = stageRoutes.withLock({ $0[race.id] }) { return hit }
        let routes = race.stages.map(race.route)
        stageRoutes.withLock { $0[race.id] = routes }
        return routes
    }

    /// "climb/mont-ventoux-bedoin" → that climb.
    static func climb(id: String) -> FamousClimb? { catalog.climbs.first { $0.id == id } }
}

/// What a route looks like from the saddle: its numbers, its climbs, and how long it takes at your pace.
/// Computed once per route and pace (a Grand Tour stage is ~2,000 points), then cached.
struct RouteStats {
    let distanceM: Double
    let ascentM: Double
    let highestM: Double
    let steepestKm: Double
    let climbs: [Climb]
    let timing: RouteTiming
    /// The pace the estimate assumes.
    let paceW: Int

    var estimatedSeconds: Double { timing.total }

    /// Estimates ride at 70 % of FTP: a pace most riders can hold for a long stage.
    static let paceShare = 0.7

    @MainActor private static var cache: [String: RouteStats] = [:]

    @MainActor
    static func of(_ route: Route, prefs: Preferences = .shared) -> RouteStats {
        let pace = Double(prefs.ftp) * paceShare
        let key = "\(route.id)|\(route.elevations.count)|\(Int(pace))|\(prefs.riderKg)|\(prefs.bikeKg)"
        if let hit = cache[key] { return hit }
        let stats = RouteStats(distanceM: route.distanceM, ascentM: route.ascentM, highestM: route.maxElevationM,
                               steepestKm: route.steepestKmGrade, climbs: Climbs.find(route),
                               timing: RouteTiming(times: route.cumulativeTimes(rider: prefs.rider, powerW: pace)),
                               paceW: Int(pace.rounded()))
        cache[key] = stats
        return stats
    }
}

extension TimeFormat {
    /// "≈ 4 h 52" / "≈ 48 min": estimates read better without seconds.
    static func estimate(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "≈ \(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "≈ \(minutes) min"
    }
}
