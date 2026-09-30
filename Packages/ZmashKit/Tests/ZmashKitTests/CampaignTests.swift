import Foundation
import Testing
@testable import ZmashKit

@Suite struct CampaignTests {
    /// 20 km flat, then 10 km at 8 % (an HC climb: 800 m at 8 %), then 5 km flat.
    private var stage: Route {
        var e = Array(repeating: 100.0, count: 201)
        for i in 1...100 { e.append(100 + Double(i) * 8) }
        e += Array(repeating: 900.0, count: 50)
        return Route(id: "s", name: "", place: "", elevations: e)
    }
    private let rider = RiderModel()

    @Test func rivalsAreStableAndSpread() {
        let a = Campaign.rivals(seed: 42), b = Campaign.rivals(seed: 42)
        #expect(a == b)
        #expect(a.count == 20)
        #expect(Set(a.map(\.name)).count == 20)
        #expect((a.map(\.factor).min() ?? 0) < 0.87 && (a.map(\.factor).max() ?? 0) > 1.13)
        #expect(Campaign.rivals(seed: 7).map(\.name) != a.map(\.name))
    }

    @Test func strongerRivalsAreQuicker() {
        let rivals = [Campaign.Rival(name: "Weak", factor: 0.85), Campaign.Rival(name: "Strong", factor: 1.15)]
        let full = Campaign.Ridden(stage: 1, fromM: 0, toM: stage.distanceM, seconds: 4000, summitSeconds: [])
        let r = Campaign.result(route: stage, ridden: full, rivals: rivals, seed: 1, rider: rider, pacePowerW: 200)
        #expect(r.seconds[2] < r.seconds[1])
        #expect(r.handicap == 0)
    }

    @Test func aFinaleAddsTheSkippedPartAtYourPace() {
        let pace = RouteTiming(times: stage.cumulativeTimes(rider: rider, powerW: 200))
        let from = 20_000.0
        let finale = Campaign.Ridden(stage: 1, fromM: from, toM: stage.distanceM, seconds: 3000, summitSeconds: [nil])
        let r = Campaign.result(route: stage, ridden: finale, rivals: [], seed: 1, rider: rider, pacePowerW: 200)
        #expect(abs(r.handicap - pace.times[200]) < 0.001)
        #expect(abs(r.seconds[0] - (3000 + pace.times[200])) < 0.001)
    }

    @Test func mountainPointsGoToTheFirstThreeOverTheTop() throws {
        let climbs = Campaign.categorisedClimbs(stage, within: 0...stage.distanceM)
        let climb = try #require(climbs.first)
        #expect(climb.category == .hc)
        let rivals = (0..<4).map { Campaign.Rival(name: "R\($0)", factor: 0.9 + Double($0) * 0.05) }
        // You crest in no time at all: first over the top.
        let ridden = Campaign.Ridden(stage: 1, fromM: 0, toM: stage.distanceM, seconds: 5000, summitSeconds: [1])
        let r = Campaign.result(route: stage, ridden: ridden, rivals: rivals, seed: 3, rider: rider, pacePowerW: 200)
        #expect(r.points[0] == 20)
        let total = r.points.reduce(0, +)
        #expect(total == 47)   // 20 + 15 + 12
        // Climbs outside the part ridden don't count.
        #expect(Campaign.categorisedClimbs(stage, within: 31_000...stage.distanceM).isEmpty)
    }

    @Test func classificationsSumAcrossStages() {
        let rivals = [Campaign.Rival(name: "A", factor: 1), Campaign.Rival(name: "B", factor: 1)]
        let s1 = Campaign.StageResult(stage: 1, seconds: [100, 90, 120], points: [0, 5, 0], handicap: 0)
        let s2 = Campaign.StageResult(stage: 2, seconds: [100, 130, 90], points: [3, 0, 3], handicap: 0)
        let (gc, kom) = Campaign.classifications([s1, s2], rivals: rivals)
        #expect(gc.map(\.name) == ["You", "B", "A"])
        #expect(gc[0].seconds == 200)
        #expect(kom.first?.name == "A")
        #expect(s1.place == 2)
    }
}
