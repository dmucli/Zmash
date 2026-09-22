import Foundation
import Testing
@testable import ZmashKit

@Suite struct RouteTests {
    /// 5 km at a steady 5 %.
    private var ramp: Route {
        Route(id: "r", name: "Ramp", place: "", elevations: (0...50).map { Double($0) * 5 })
    }

    @Test func geometry() {
        let r = ramp
        #expect(r.distanceM == 5000)
        #expect(abs(r.ascentM - 250) < 0.001)
        #expect(abs(r.averageGrade - 5) < 0.001)
        #expect(abs(r.grade(atDistance: 2050) - 5) < 0.001)
        #expect(abs(r.elevation(atDistance: 2050) - 102.5) < 0.001)
        #expect(r.summitDistanceM == 5000)
        // Past the end it holds the last point rather than extrapolating.
        #expect(r.elevation(atDistance: 99_999) == 250)
    }

    @Test func gradesAreClampedToWhatTheTrainerCanDo() {
        let cliff = Route(id: "c", name: "Cliff", place: "", elevations: [0, 100, 0])
        #expect(cliff.grade(atDistance: 0) == 16)
        #expect(cliff.grade(atDistance: 150) == -10)
    }

    @Test func buildResamplesAndSmooths() throws {
        let points: [(distanceM: Double, elevationM: Double)] = [(0, 0), (250, 25), (1000, 50), (2000, 120)]
        let r = try #require(RouteBuilder.make(id: "b", name: "B", points: points))
        #expect(r.elevations.count == 21)
        #expect(r.distanceM == 2000)
        #expect(r.elevations.first! < r.elevations.last!)
        // Smoothing keeps the ends and never introduces a gradient the raw data doesn't have.
        #expect(abs(r.elevations.last! - 120) < 5)
    }

    @Test func trackUsesHaversineDistance() throws {
        // A degree of latitude is ~111 km.
        let d = RouteBuilder.distance(lat1: 45, lon1: 6, lat2: 45.01, lon2: 6)
        #expect(abs(d - 1112) < 5)
        let track = (0...20).map { (lat: 45 + Double($0) * 0.001, lon: 6.0, ele: Double($0) * 10) }
        let r = try #require(RouteBuilder.fromTrack(id: "t", name: "T", track: track))
        #expect(abs(r.distanceM - 2200) < 120)
    }

    @Test func gpxImport() throws {
        let gpx = """
        <gpx><trk><name>Col de Test</name><trkseg>
        \((0...30).map { "<trkpt lat=\"45.\(String(format: "%04d", $0 * 10))\" lon=\"6.0\"><ele>\(100 + $0 * 12)</ele></trkpt>" }.joined())
        </trkseg></trk></gpx>
        """
        let r = try #require(GPXParser.parse(Data(gpx.utf8), id: "g"))
        #expect(r.name == "Col de Test")
        #expect(r.distanceM > 2000)
        #expect(r.ascentM > 300)
        #expect(GPXParser.parse(Data("<gpx></gpx>".utf8), id: "x") == nil)
    }

    @Test func fitRouteReaderReadsWhatTheWriterWrote() throws {
        // A ride whose speed is constant: distance grows, and the FIT writer stores it.
        let samples = (0..<600).map { RideSample(t: $0, powerW: 200, cadenceRpm: 85, speedKph: 30, gradePercent: 4, gear: 12) }
        let summary = SessionSummary.from(samples: samples, activeSeconds: 600, distanceM: 5000, elevationGainM: 200, kcal: 120)
        let data = FITWriter.encode(startedAt: .now, samples: samples, summary: summary)
        // Our own writer stores no altitude, so there's no profile to build: it must decline, not crash.
        #expect(FITRouteReader.parse(data, id: "f") == nil)
        #expect(FITRouteReader.parse(Data([0, 1, 2, 3]), id: "f") == nil)
    }

    @Test func ghostFromSamplesAndDelta() throws {
        // 36 km/h = 10 m/s: 100 m every 10 s.
        let samples = (0..<300).map { RideSample(t: $0, powerW: 200, cadenceRpm: 85, speedKph: 36, gradePercent: 0, gear: 12) }
        let ghost = try #require(Ghost(samples: samples))
        #expect(abs(ghost.totalSeconds - 299) < 2)
        // Level with the ghost at 1 km after 100 s.
        let delta = try #require(ghost.delta(elapsed: 100, distanceM: 1000))
        #expect(abs(delta) < 2)
        // Ten seconds quicker to the same point.
        #expect(ghost.delta(elapsed: 90, distanceM: 1000)! > 8)
        #expect(ghost.delta(elapsed: 100, distanceM: 99_000) == nil)
    }

    @Test func climbLibraryIsCloseToPublishedProfiles() throws {
        let alpe = try #require(ClimbLibrary.route(id: "alpe-dhuez"))
        #expect(abs(alpe.distanceM - 14_000) < 200)
        #expect(abs(alpe.ascentM - 1071) < 60)       // published: 1071 m over 13.8 km
        #expect((7.5...8.6).contains(alpe.averageGrade))
        let ventoux = try #require(ClimbLibrary.route(id: "ventoux"))
        #expect(abs(ventoux.ascentM - 1610) < 80)
        for route in ClimbLibrary.all {
            #expect(route.approximate)
            #expect(route.elevations.count > 10)
            #expect(Route.gradeRange.contains(route.grade(atDistance: route.distanceM / 2)))
        }
    }
}
