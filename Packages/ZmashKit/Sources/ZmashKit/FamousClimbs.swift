import Foundation

/// A famous climb as ridden in a real race: its real profile, cut from that race's GPX (plan part A).
public struct FamousClimb: Codable, Equatable, Identifiable, Sendable {
    /// "climb/alpe-d-huez-bourg-d-oisans"
    public var id: String
    public var name: String
    /// The side it's climbed from: a town ("Bédoin") or a direction ("from the north").
    public var side: String
    public var country: String
    /// Where the profile comes from, e.g. "Tour de France 2025 · stage 16".
    public var source: String
    /// Elevation every `Route.step` metres, whole metres, foot to summit.
    public var elevations: [Int]
    /// Where the climb starts, to tell sides apart.
    public var footLat: Double
    public var footLon: Double

    public init(id: String, name: String, side: String, country: String, source: String, elevations: [Int],
                footLat: Double = 0, footLon: Double = 0) {
        self.id = id
        self.name = name
        self.side = side
        self.country = country
        self.source = source
        self.elevations = elevations
        self.footLat = footLat
        self.footLon = footLon
    }

    /// Same climb from the same side: the feet are within 3 km.
    public func sameSide(as other: FamousClimb) -> Bool {
        name == other.name && RouteBuilder.distance(lat1: footLat, lon1: footLon, lat2: other.footLat, lon2: other.footLon) < 3000
    }

    public var route: Route {
        Route(id: id, name: name, place: "\(side) · \(country)", elevations: elevations.map(Double.init))
    }
}

/// A summit to look for: where it is, how high, and the towns its sides start from.
public struct ClimbSummit: Sendable {
    public struct Side: Sendable {
        public let name: String
        public let lat: Double
        public let lon: Double
    }

    public let name: String
    public let country: String
    public let lat: Double
    public let lon: Double
    public let altitudeM: Double
    public let sides: [Side]

    public init(_ name: String, _ country: String, _ lat: Double, _ lon: Double, _ altitudeM: Double, sides: [(String, Double, Double)] = []) {
        self.name = name
        self.country = country
        self.lat = lat
        self.lon = lon
        self.altitudeM = altitudeM
        self.sides = sides.map { Side(name: $0.0, lat: $0.1, lon: $0.2) }
    }
}

public enum FamousClimbs {
    /// A track counts as crossing a summit if it passes within this distance of it (a mountain's top is broad;
    /// a Flemish berg's is a few hundred metres from the next one)…
    static func searchRadiusM(_ s: ClimbSummit) -> Double { s.altitudeM < 500 ? 700 : 3000 }
    /// …and its highest point there is within this much of the summit's altitude (GPX heights come from
    /// terrain models, and neighbouring cols can be close together: Glandon and Croix de Fer are 2 km apart).
    public static let altitudeToleranceM = 90.0

    /// The summits looked for. Coordinates and altitudes from public maps; sides by their starting towns.
    public static let summits: [ClimbSummit] = [
        ClimbSummit("Alpe d'Huez", "FR", 45.0917, 6.0705, 1850, sides: [("Bourg-d'Oisans", 45.0547, 6.0300)]),
        ClimbSummit("Mont Ventoux", "FR", 44.1741, 5.2786, 1910,
                    sides: [("Bédoin", 44.1246, 5.1797), ("Malaucène", 44.1735, 5.1325), ("Sault", 44.0906, 5.4088)]),
        ClimbSummit("Col du Tourmalet", "FR", 42.9086, 0.1450, 2115,
                    sides: [("Luz-Saint-Sauveur", 42.8718, -0.0037), ("Sainte-Marie-de-Campan", 42.9838, 0.2276)]),
        ClimbSummit("Col du Galibier", "FR", 45.0643, 6.4079, 2642,
                    sides: [("Valloire", 45.1640, 6.4285), ("Col du Lautaret", 45.0350, 6.4040)]),
        ClimbSummit("Col du Télégraphe", "FR", 45.2023, 6.4447, 1566, sides: [("Saint-Michel-de-Maurienne", 45.2195, 6.4696)]),
        ClimbSummit("Col de la Loze", "FR", 45.4037, 6.6027, 2304, sides: [("Brides-les-Bains", 45.4527, 6.5684), ("Méribel", 45.3970, 6.5660)]),
        ClimbSummit("Col de la Madeleine", "FR", 45.4343, 6.3705, 2000,
                    sides: [("La Chambre", 45.3583, 6.3000), ("Feissons-sur-Isère", 45.5500, 6.4700)]),
        ClimbSummit("Col d'Izoard", "FR", 44.8203, 6.7351, 2360, sides: [("Briançon", 44.8978, 6.6429), ("Guillestre", 44.6600, 6.6490)]),
        ClimbSummit("Hautacam", "FR", 42.9745, -0.0099, 1520, sides: [("Argelès-Gazost", 43.0030, -0.0990)]),
        ClimbSummit("Col d'Aubisque", "FR", 42.9744, -0.3388, 1709, sides: [("Laruns", 42.9885, -0.4260)]),
        ClimbSummit("Col de Peyresourde", "FR", 42.7965, 0.4535, 1569,
                    sides: [("Bagnères-de-Luchon", 42.7900, 0.5937), ("Arreau", 42.9060, 0.3570)]),
        ClimbSummit("Superbagnères", "FR", 42.7590, 0.5760, 1800, sides: [("Bagnères-de-Luchon", 42.7900, 0.5937)]),
        ClimbSummit("Col du Portet", "FR", 42.8185, 0.3313, 2215, sides: [("Saint-Lary-Soulan", 42.8170, 0.3230)]),
        ClimbSummit("Col de la Croix de Fer", "FR", 45.2270, 6.2025, 2067,
                    sides: [("Saint-Jean-de-Maurienne", 45.2765, 6.3460), ("Allemont", 45.1320, 6.0400)]),
        ClimbSummit("Col du Glandon", "FR", 45.2395, 6.1795, 1924, sides: [("La Chambre", 45.3583, 6.3000)]),
        ClimbSummit("Grand Colombier", "FR", 45.9022, 5.7612, 1501, sides: [("Culoz", 45.8470, 5.7850)]),
        ClimbSummit("La Planche des Belles Filles", "FR", 47.7725, 6.7775, 1140, sides: [("Plancher-les-Mines", 47.7610, 6.7440)]),
        ClimbSummit("Puy de Dôme", "FR", 45.7720, 2.9640, 1415),
        ClimbSummit("Monte Zoncolan", "IT", 46.5009, 12.9266, 1750, sides: [("Ovaro", 46.4830, 12.8660), ("Sutrio", 46.5130, 12.9960)]),
        ClimbSummit("Passo Giau", "IT", 46.4823, 12.0533, 2236, sides: [("Selva di Cadore", 46.4500, 12.0100), ("Pocol", 46.5270, 12.1030)]),
        ClimbSummit("Passo Pordoi", "IT", 46.4875, 11.8125, 2239, sides: [("Arabba", 46.4960, 11.8750), ("Canazei", 46.4770, 11.7700)]),
        ClimbSummit("Passo Gavia", "IT", 46.3442, 10.4880, 2621, sides: [("Ponte di Legno", 46.2590, 10.5100), ("Santa Caterina", 46.4120, 10.4940)]),
        ClimbSummit("Tre Cime di Lavaredo", "IT", 46.6123, 12.2958, 2304, sides: [("Misurina", 46.5820, 12.2530)]),
        ClimbSummit("Colle delle Finestre", "IT", 45.0717, 7.0540, 2178, sides: [("Meana di Susa", 45.1220, 7.0640), ("Fenestrelle", 45.0350, 7.0500)]),
        ClimbSummit("Sestriere", "IT", 44.9580, 6.8790, 2035),
        ClimbSummit("Monte Grappa", "IT", 45.8700, 11.8020, 1745, sides: [("Romano d'Ezzelino", 45.7870, 11.7720)]),
        ClimbSummit("Etna", "IT", 37.6995, 14.9990, 1900, sides: [("Nicolosi", 37.6150, 15.0200)]),
        ClimbSummit("Campo Imperatore", "IT", 42.4430, 13.5590, 2130),
        ClimbSummit("Cipressa", "IT", 43.8516, 7.9314, 243),
        ClimbSummit("Poggio di Sanremo", "IT", 43.8283, 7.8150, 162),
        ClimbSummit("Alto de l'Angliru", "ES", 43.2214, -5.9396, 1570, sides: [("La Vega", 43.2380, -5.9020)]),
        ClimbSummit("Lagos de Covadonga", "ES", 43.2714, -4.9850, 1134, sides: [("Cangas de Onís", 43.3510, -5.1290)]),
        ClimbSummit("Oude Kwaremont", "BE", 50.7746, 3.6624, 115),
        ClimbSummit("Paterberg", "BE", 50.7829, 3.5488, 73),
        ClimbSummit("Koppenberg", "BE", 50.8106, 3.5833, 75),
        ClimbSummit("Muur van Geraardsbergen", "BE", 50.7721, 3.8896, 104),
        ClimbSummit("La Redoute", "BE", 50.4935, 5.7085, 290),
        ClimbSummit("Cauberg", "NL", 50.8568, 5.8177, 140),
    ]

    /// Every famous climb this track rides, cut from its profile.
    /// `source` names the race and stage, e.g. "Tour de France 2025 · stage 16".
    public static func extract(track: [(lat: Double, lon: Double, ele: Double)], source: String) -> [FamousClimb] {
        guard track.count > 1 else { return [] }
        var distance = [0.0]
        for (a, b) in zip(track, track.dropFirst()) {
            distance.append(distance.last! + RouteBuilder.distance(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon))
        }
        guard let route = RouteBuilder.make(id: "x", name: "", points: zip(distance, track).map { ($0, $1.ele) }) else { return [] }
        let climbs = Climbs.find(route, categorisedOnly: false)

        // Where the track tops out near each summit: a mountain's highest point near it, a small hill's closest
        // point (the road often keeps rising gently past a berg's top onto the plateau).
        var matches: [(summit: ClimbSummit, atM: Double, error: Double)] = []
        for summit in summits {
            var best: (index: Int, ele: Double, near: Double)?
            for (i, p) in track.enumerated() {
                let near = RouteBuilder.distance(lat1: p.lat, lon1: p.lon, lat2: summit.lat, lon2: summit.lon)
                guard near < searchRadiusM(summit) else { continue }
                let better = summit.altitudeM < 500 ? near < (best?.near ?? .infinity) : p.ele > (best?.ele ?? -.infinity)
                if better { best = (i, p.ele, near) }
            }
            guard let best, abs(best.ele - summit.altitudeM) <= altitudeToleranceM else { continue }
            matches.append((summit, distance[best.index], abs(best.ele - summit.altitudeM) + best.near / 20))
        }
        // Neighbouring summits can claim the same top: keep the closest match for each.
        matches.sort { $0.error < $1.error }
        var claimed: [Double] = []
        var out: [FamousClimb] = []
        for match in matches where !claimed.contains(where: { abs($0 - match.atM) < 1000 }) {
            // The climb that ends there. Its top may stop short of the summit when the last stretch is a flat
            // plateau (trimmed as not part of the climb), so allow more room before than after.
            guard let climb = climbs.min(by: { abs($0.startM + $0.lengthM - match.atM) < abs($1.startM + $1.lengthM - match.atM) }),
                  (-1500..<800).contains(climb.startM + climb.lengthM - match.atM) else { continue }
            // A mountain pass seen only in passing (a stage crossing near its top) isn't the climb.
            guard match.summit.altitudeM < 1000 || climb.gainM >= 500 else { continue }
            claimed.append(match.atM)
            let piece = route.slice(fromM: climb.startM, toM: climb.startM + climb.lengthM)
            let foot = track[distance.firstIndex { $0 >= climb.startM } ?? 0]
            let side = sideName(match.summit, footLat: foot.lat, footLon: foot.lon)
            out.append(FamousClimb(id: "climb/" + slug("\(match.summit.name) \(side)"), name: match.summit.name, side: side,
                                   country: match.summit.country, source: source,
                                   elevations: piece.elevations.map { Int($0.rounded()) }, footLat: foot.lat, footLon: foot.lon))
        }
        return out
    }

    /// The side by its town if the foot is within 10 km of a known one, otherwise by compass direction.
    static func sideName(_ summit: ClimbSummit, footLat: Double, footLon: Double) -> String {
        let nearest = summit.sides.min {
            RouteBuilder.distance(lat1: footLat, lon1: footLon, lat2: $0.lat, lon2: $0.lon)
                < RouteBuilder.distance(lat1: footLat, lon1: footLon, lat2: $1.lat, lon2: $1.lon)
        }
        if let nearest, RouteBuilder.distance(lat1: footLat, lon1: footLon, lat2: nearest.lat, lon2: nearest.lon) < 10_000 {
            return nearest.name
        }
        // Bearing from the summit to the foot: the side of the mountain you start on.
        let dLon = (footLon - summit.lon) * .pi / 180
        let la1 = summit.lat * .pi / 180, la2 = footLat * .pi / 180
        let y = sin(dLon) * cos(la2), x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return "from the " + names[Int((bearing + 22.5) / 45) % 8]
    }

    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        return folded.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { out, c in if !(c == "-" && out.last == "-") { out.append(c) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

public extension GPXParser {
    /// The track's points with coordinates, for finding climbs by where they are.
    static func track(_ data: Data) -> [(lat: Double, lon: Double, ele: Double)] {
        let p = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() else { return [] }
        return p.points
    }
}
