import Foundation
import Testing
@testable import ZmashKit

@Suite struct FamousClimbTests {
    /// A straight track from (lat, lon) to (lat2, lon2), a point every ~50 m, elevation from `ele` to `ele2`.
    private func line(_ lat: Double, _ lon: Double, _ ele: Double,
                      to lat2: Double, _ lon2: Double, _ ele2: Double) -> [(lat: Double, lon: Double, ele: Double)] {
        let n = max(Int(RouteBuilder.distance(lat1: lat, lon1: lon, lat2: lat2, lon2: lon2) / 50), 2)
        return (0...n).map { i in
            let t = Double(i) / Double(n)
            return (lat + (lat2 - lat) * t, lon + (lon2 - lon) * t, ele + (ele2 - ele) * t)
        }
    }

    /// Flat from the west into Bédoin, up to the top of the Ventoux, then down the other side.
    private var ventoux: [(lat: Double, lon: Double, ele: Double)] {
        line(44.1246, 5.10, 300, to: 44.1246, 5.1797, 300)
            + line(44.1246, 5.1797, 300, to: 44.1741, 5.2786, 1905).dropFirst()
            + line(44.1741, 5.2786, 1905, to: 44.1735, 5.1325, 380).dropFirst()
    }

    @Test func findsTheClimbByItsSummitAndNamesTheSide() throws {
        let found = FamousClimbs.extract(track: ventoux, source: "Test race · stage 1")
        #expect(found.count == 1)
        let climb = try #require(found.first)
        #expect(climb.name == "Mont Ventoux")
        #expect(climb.side == "Bédoin")
        #expect(climb.id == "climb/mont-ventoux-bedoin")
        #expect(climb.source == "Test race · stage 1")
        // Foot to summit only: the flat approach and the descent are not part of it.
        let route = climb.route
        #expect(abs(route.ascentM - 1605) < 60)
        #expect((9_000...11_500).contains(route.distanceM))
        #expect(route.place == "Bédoin · FR")
    }

    @Test func aTrackThatMissesTheSummitFindsNothing() {
        // The same climb shape, 20 km further south: no summit there.
        let shifted = ventoux.map { ($0.lat - 0.2, $0.lon, $0.ele) }
        #expect(FamousClimbs.extract(track: shifted, source: "x").isEmpty)
    }

    @Test func crossingAPassNearItsTopIsNotTheClimb() {
        // A stage that reaches the Tourmalet's height from a high valley: 300 m of climbing, not the climb.
        let track = line(42.93, 0.20, 1810, to: 42.9086, 0.1450, 2112) + line(42.9086, 0.1450, 2112, to: 42.8718, -0.0037, 700).dropFirst()
        #expect(FamousClimbs.extract(track: track, source: "x").isEmpty)
    }

    @Test func unknownSidesAreNamedByDirection() {
        let summit = FamousClimbs.summits.first { $0.name == "Mont Ventoux" }!
        #expect(FamousClimbs.sideName(summit, footLat: 44.30, footLon: 5.2786) == "from the north")
        #expect(FamousClimbs.sideName(summit, footLat: 44.1741, footLon: 5.55) == "from the east")
        #expect(FamousClimbs.sideName(summit, footLat: 44.1300, footLon: 5.1800) == "Bédoin")
    }

    @Test func slugs() {
        #expect(FamousClimbs.slug("Alpe d'Huez Bourg-d'Oisans") == "alpe-d-huez-bourg-d-oisans")
        #expect(FamousClimbs.slug("Superbagnères Bagnères-de-Luchon") == "superbagneres-bagneres-de-luchon")
    }

    @Test func sameSideMeansFeetClose() {
        let a = FamousClimb(id: "a", name: "X", side: "s", country: "FR", source: "", elevations: [], footLat: 45, footLon: 6)
        #expect(a.sameSide(as: FamousClimb(id: "b", name: "X", side: "t", country: "FR", source: "", elevations: [], footLat: 45.01, footLon: 6)))
        #expect(!a.sameSide(as: FamousClimb(id: "c", name: "X", side: "u", country: "FR", source: "", elevations: [], footLat: 45.1, footLon: 6)))
        #expect(!a.sameSide(as: FamousClimb(id: "d", name: "Y", side: "s", country: "FR", source: "", elevations: [], footLat: 45, footLon: 6)))
    }

    @Test func catalogWithoutClimbsStillDecodes() throws {
        let json = #"{"races":[]}"#.data(using: .utf8)!
        let catalog = try JSONDecoder().decode(RaceCatalog.self, from: json)
        #expect(catalog.climbs.isEmpty)
    }

    @Test func smallUncategorisedClimbsOnRequest() {
        // 400 m at 8 %: too small for a category, but a Flemish berg all the same.
        let e: [Double] = Array(repeating: 20, count: 20) + (1...4).map { 20 + Double($0) * 8 } + Array(repeating: 52, count: 20)
        let route = Route(id: "b", name: "", place: "", elevations: e)
        #expect(Climbs.find(route).isEmpty)
        #expect(Climbs.find(route, categorisedOnly: false).count == 1)
    }
}
