import Foundation
import Testing
@testable import ZmashKit

@Suite struct RouteLinkTests {
    @Test func rideWithGPS() {
        #expect(RouteLink.parse("https://ridewithgps.com/routes/45129377") == .rideWithGPS(kind: "routes", id: "45129377"))
        #expect(RouteLink.parse("ridewithgps.com/routes/45129377?privacy_code=abc") == .rideWithGPS(kind: "routes", id: "45129377"))
        #expect(RouteLink.parse("https://ridewithgps.com/trips/99") == .rideWithGPS(kind: "trips", id: "99"))
        #expect(RouteLink.parse("https://ridewithgps.com/routes/45129377")?.downloadURL?.absoluteString
            == "https://ridewithgps.com/routes/45129377.gpx?sub_format=track")
    }

    @Test func komoot() {
        #expect(RouteLink.parse("https://www.komoot.com/tour/1234567890") == .komoot(id: "1234567890", shareToken: nil))
        #expect(RouteLink.parse("https://www.komoot.com/fr-fr/tour/1234567890?share_token=aBc&ref=wtd")
            == .komoot(id: "1234567890", shareToken: "aBc"))
        #expect(RouteLink.parse("Look at this: https://www.komoot.de/tour/42 !") == .komoot(id: "42", shareToken: nil))
        #expect(RouteLink.parse("https://www.komoot.com/tour/42?share_token=t")?.downloadURL?.absoluteString
            == "https://www.komoot.com/api/v007/tours/42/coordinates?share_token=t")
    }

    @Test func stravaAndFiles() {
        #expect(RouteLink.parse("https://www.strava.com/routes/3141592653589793") == .strava(id: "3141592653589793"))
        #expect(RouteLink.parse("https://example.org/rides/ventoux.GPX") != nil)
        #expect(RouteLink.parse("https://example.org/ride.fit")?.sourceName == "the link")
    }

    @Test func notARoute() {
        #expect(RouteLink.parse("hello") == nil)
        #expect(RouteLink.parse("https://www.strava.com/activities/123") == nil)
        #expect(RouteLink.parse("https://www.komoot.com/discover") == nil)
        #expect(RouteLink.parse("https://example.org/page.html") == nil)
    }

    @Test func komootCoordinates() throws {
        let json = #"{"items":[{"lat":44.17,"lng":5.27,"alt":300,"t":0},{"lat":44.18,"lng":5.28,"alt":340,"t":60},{"lat":44.19,"lng":5.29,"alt":390,"t":120}]}"#
        let track = try #require(RouteLink.komootTrack(Data(json.utf8)))
        #expect(track.count == 3)
        #expect(track[2].ele == 390)
        #expect(RouteLink.komootTrack(Data(#"{"items":[]}"#.utf8)) == nil)
    }
}
