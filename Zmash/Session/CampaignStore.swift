import Foundation
import ZmashKit

/// A campaign in progress or done: the race, the rivals, and what you've ridden (D96).
struct CampaignState: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Whose campaign (D112); "" is the first rider.
    var riderID = Riders.currentID
    var raceID: String
    var seed: UInt64
    var startedAt = Date.now
    /// Your pace and weights when it started; the rivals are set against them for the whole race.
    var pacePowerW: Double
    var riderKg: Double
    var bikeKg: Double
    var rivals: [Campaign.Rival]
    var ridden: [Campaign.Ridden] = []
    var abandoned = false

    var rider: RiderModel { RiderModel(riderKg: riderKg, bikeKg: bikeKg) }

    init(raceID: String, seed: UInt64, pacePowerW: Double, riderKg: Double, bikeKg: Double, rivals: [Campaign.Rival]) {
        self.raceID = raceID
        self.seed = seed
        self.pacePowerW = pacePowerW
        self.riderKg = riderKg
        self.bikeKg = bikeKg
        self.rivals = rivals
    }

    /// Campaigns saved before riders had profiles belong to the first rider.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        riderID = try c.decodeIfPresent(String.self, forKey: .riderID) ?? ""
        raceID = try c.decode(String.self, forKey: .raceID)
        seed = try c.decode(UInt64.self, forKey: .seed)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        pacePowerW = try c.decode(Double.self, forKey: .pacePowerW)
        riderKg = try c.decode(Double.self, forKey: .riderKg)
        bikeKg = try c.decode(Double.self, forKey: .bikeKg)
        rivals = try c.decode([Campaign.Rival].self, forKey: .rivals)
        ridden = try c.decodeIfPresent([Campaign.Ridden].self, forKey: .ridden) ?? []
        abandoned = try c.decodeIfPresent(Bool.self, forKey: .abandoned) ?? false
    }
}

/// Campaigns as JSON files in Application Support (a handful of small files; no need for the ride database).
@MainActor
enum CampaignStore {
    private static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Campaigns", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The current rider's campaigns, newest first.
    static var all: [CampaignState] { everyone.filter { $0.riderID == Riders.currentID } }

    /// Read once, then kept until a change (home and the pickers ask several times per draw).
    private static var stored: [CampaignState]?

    /// Every rider's (for deleting a rider).
    static var everyone: [CampaignState] {
        if let stored { return stored }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let list = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(CampaignState.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
        stored = list
        return list
    }

    static func delete(_ c: CampaignState) {
        try? FileManager.default.removeItem(at: directory.appending(path: c.id.uuidString + ".json"))
        stored = nil
    }

    static func save(_ c: CampaignState) {
        try? JSONEncoder().encode(c).write(to: directory.appending(path: c.id.uuidString + ".json"), options: .atomic)
        stored = nil
    }

    static func start(race: Race, prefs: Preferences) -> CampaignState {
        // One campaign per race at a time: starting again abandons the old one.
        for var old in all where old.raceID == race.id && !old.abandoned && !isFinished(old) {
            old.abandoned = true
            save(old)
        }
        let seed = UInt64.random(in: 1...UInt64(Int64.max))
        let c = CampaignState(raceID: race.id, seed: seed, pacePowerW: Double(prefs.ftp) * RouteStats.paceShare,
                              riderKg: prefs.riderKg, bikeKg: prefs.bikeKg, rivals: Campaign.rivals(seed: seed))
        save(c)
        return c
    }

    /// The campaign to show on a race's page: the one in progress, or the last one finished (not abandoned ones).
    static func latest(raceID: String) -> CampaignState? {
        all.first { $0.raceID == raceID && !$0.abandoned }
    }

    static func active(raceID: String) -> CampaignState? {
        all.first { $0.raceID == raceID && !$0.abandoned && !isFinished($0) }
    }

    /// The campaign ridden most recently that still has stages to go.
    static var current: CampaignState? { all.filter { !$0.abandoned && !isFinished($0) && race($0) != nil }.first }

    static func race(_ c: CampaignState) -> Race? { RaceStore.races.first { $0.id == c.raceID } }

    /// A campaign whose race can't be found (the catalog didn't load, or was rebuilt with other ids) isn't finished:
    /// it's on hold, and comes back as it was once the race is there again.
    static func isFinished(_ c: CampaignState) -> Bool {
        guard let race = race(c) else { return false }
        return c.ridden.count >= race.stages.count
    }

    /// The next stage to ride.
    static func nextStage(_ c: CampaignState) -> Stage? {
        guard let race = race(c), c.ridden.count < race.stages.count else { return nil }
        return race.stages.sorted { $0.number < $1.number }[c.ridden.count]
    }

    // MARK: Results

    @MainActor private static var cache: [String: [Campaign.StageResult]] = [:]

    static func results(_ c: CampaignState) -> [Campaign.StageResult] {
        let key = "\(c.id)|\(c.ridden.count)"
        if let hit = cache[key] { return hit }
        guard let race = race(c) else { return [] }
        let out = c.ridden.compactMap { r -> Campaign.StageResult? in
            guard let stage = race.stages.first(where: { $0.number == r.stage }) else { return nil }
            return Campaign.result(route: race.route(stage), ridden: r, rivals: c.rivals, seed: c.seed,
                                   rider: c.rider, pacePowerW: c.pacePowerW)
        }
        cache[key] = out
        return out
    }

    // MARK: Counting a ride

    /// What a finished ride does to a campaign, if it rode the next stage: the stage as ridden, or nil.
    static func ridden(by ride: FinishedRide) -> (campaign: CampaignState, ridden: Campaign.Ridden)? {
        guard let id = ride.plan.routeID else { return nil }
        let (base, window) = RouteStore.split(id)
        guard let (race, stage) = RaceStore.stage(routeID: base), let c = active(raceID: race.id),
              nextStage(c)?.number == stage.number else { return nil }
        let route = race.route(stage)
        let part = window ?? 0...route.distanceM
        // Finished the part (allowing for the last few metres).
        guard ride.summary.distanceM >= (part.upperBound - part.lowerBound) * 0.97 else { return nil }
        let climbs = Campaign.categorisedClimbs(route, within: part)
        let along = alongDistance(ride, from: part.lowerBound)
        let summits = climbs.map { c -> Double? in
            let top = c.startM + c.lengthM
            return along.firstIndex { $0 >= top - 1 }.map(Double.init)
        }
        // The part's time: the ride's clock up to the end of the part (a ride can run on past it).
        let end = along.firstIndex { $0 >= part.upperBound - 1 }.map(Double.init) ?? Double(ride.summary.activeSeconds)
        return (c, Campaign.Ridden(stage: stage.number, fromM: part.lowerBound, toM: part.upperBound,
                                   seconds: end, summitSeconds: summits))
    }

    /// Where the rider was along the stage at each second, from the samples' speeds, scaled to the ride's distance.
    private static func alongDistance(_ ride: FinishedRide, from start: Double) -> [Double] {
        var m = 0.0
        var out = ride.samples.map { s -> Double in m += max(s.speedKph, 0) / 3.6; return m }
        if m > 0, ride.summary.distanceM > 0 {
            let k = ride.summary.distanceM / m
            out = out.map { $0 * k }
        }
        return out.map { start + $0 }
    }

    /// Records a saved ride against its campaign, if it rode the next stage.
    static func record(_ ride: FinishedRide) {
        guard let found = ridden(by: ride) else { return }
        var c = found.campaign
        var r = found.ridden
        r.rideID = ride.id
        c.ridden.append(r)
        save(c)
    }

    /// A deleted ride no longer counts: if it was a campaign's latest stage, that stage is to ride again.
    /// (Stages go in order, so an earlier one stays: removing it would shift every stage after it.)
    static func unrecord(rideID: UUID) {
        for var c in everyone where c.ridden.last?.rideID == rideID {
            c.ridden.removeLast()
            save(c)
        }
    }

    // MARK: Summary

    /// For the ride summary: the stage result and how the classifications move, as if the ride were saved.
    struct Preview {
        let raceName: String
        let stage: Int
        let stagePlace: Int
        let field: Int
        let gcBefore: Int?
        let gcAfter: Int
        let gapToLeader: Double
        let points: Int
        let yellow: Bool
        let polkaDot: Bool
        let tookYellow: Bool
        let tookPolkaDot: Bool
        let finished: Bool
    }

    static func preview(_ ride: FinishedRide) -> Preview? {
        guard let (c, r) = ridden(by: ride), let race = race(c) else { return nil }
        let before = results(c)
        var after = c
        after.ridden.append(r)
        let now = results(after)
        guard let stageResult = now.last else { return nil }
        let (gc0, kom0) = Campaign.classifications(before, rivals: c.rivals)
        let (gc1, kom1) = Campaign.classifications(now, rivals: c.rivals)
        let place = { (list: [Campaign.Standing]) in (list.firstIndex { $0.isYou } ?? 0) + 1 }
        let yellow = gc1.first?.isYou == true, polka = kom1.first?.isYou == true && (kom1.first?.points ?? 0) > 0
        return Preview(raceName: race.name, stage: r.stage, stagePlace: stageResult.place, field: c.rivals.count + 1,
                       gcBefore: before.isEmpty ? nil : place(gc0), gcAfter: place(gc1),
                       gapToLeader: (gc1.first { $0.isYou }?.seconds ?? 0) - (gc1.first?.seconds ?? 0),
                       points: stageResult.points[0], yellow: yellow, polkaDot: polka,
                       tookYellow: yellow && (before.isEmpty || gc0.first?.isYou != true),
                       tookPolkaDot: polka && kom0.first?.isYou != true,
                       finished: after.ridden.count >= race.stages.count)
    }
}
