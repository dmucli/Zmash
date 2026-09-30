import Foundation
import Testing
@testable import ZmashKit

/// The race catalog the app ships (Zmash/Resources/Races/races.json, built by `make races`). Campaigns, plans,
/// palmarès and saved rides refer to its ids, so a rebuild must keep them.
@Suite struct BundledCatalogTests {
    private static let url = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Zmash/Resources/Races/races.json")

    private func catalog() throws -> RaceCatalog {
        try JSONDecoder().decode(RaceCatalog.self, from: Data(contentsOf: Self.url))
    }

    @Test func decodes() throws {
        let c = try catalog()
        #expect(!c.races.isEmpty)
        #expect(c.climbs.count == 20)
        #expect(c.races.allSatisfy { !$0.stages.isEmpty })
    }

    @Test func idsAreUnique() throws {
        let c = try catalog()
        #expect(Set(c.races.map(\.id)).count == c.races.count)
        #expect(Set(c.climbs.map(\.id)).count == c.climbs.count)
    }

    @Test func idsTheAppUsesAreThere() throws {
        let climbs = Set(try catalog().climbs.map(\.id))
        #expect(climbs.contains("climb/mont-ventoux-bedoin"))
        for plan in TrainingPlans.all {
            for case .route(let id) in plan.weeks.joined() { #expect(climbs.contains(id), "\(plan.id) rides \(id)") }
        }
    }
}
