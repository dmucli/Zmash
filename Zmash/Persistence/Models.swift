import Foundation
import SwiftData
import ZmashKit

/// A ride. Samples are stored as one encoded blob (~3.6k per hour) rather than one row each:
/// they're only ever read whole, and it keeps saves and autosaves cheap.
@Model
final class RideSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var activeSeconds: Int
    var plannedSeconds: Int?
    var terrainMode: String
    var effort: String?
    var terrainType: String?
    var seed: Int64?
    var distanceM: Double
    var elevationGainM: Double
    var kcal: Double
    var avgPowerW: Int
    var maxPowerW: Int
    var avgCadenceRpm: Int
    var avgSpeedKph: Double
    var avgHeartRateBpm: Int?
    var maxHeartRateBpm: Int?
    var rpe: Int?
    var note: String?
    var workoutID: String?
    var workoutName: String?
    var routeID: String?
    var routeName: String?
    /// Training load, computed on save with the FTP of the day (Phase 7).
    var tss: Double?
    var normalizedPowerW: Int?
    /// Best power per duration ([seconds: watts], JSON).
    var powerCurveData: Data?
    /// False while the ride is only an autosave (crash recovery).
    var isComplete: Bool
    @Attribute(.externalStorage) var samplesData: Data?

    init(id: UUID = UUID(), startedAt: Date, plan: SessionPlan) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = startedAt
        self.activeSeconds = 0
        self.plannedSeconds = plan.plannedSeconds.map { Int($0) }
        self.workoutID = plan.workoutID
        self.workoutName = plan.workout?.name
        self.routeID = plan.routeID
        self.routeName = plan.route?.name
        self.terrainMode = plan.terrainMode.rawValue
        self.effort = plan.terrainMode == .auto ? plan.effort.rawValue : nil
        self.terrainType = plan.terrainMode == .auto ? plan.terrainType.rawValue : nil
        self.seed = plan.terrainMode == .auto ? Int64(bitPattern: plan.seed) : nil
        self.distanceM = 0
        self.elevationGainM = 0
        self.kcal = 0
        self.avgPowerW = 0
        self.maxPowerW = 0
        self.avgCadenceRpm = 0
        self.avgSpeedKph = 0
        self.isComplete = false
    }

    var samples: [RideSample] {
        get { samplesData.flatMap { try? JSONDecoder().decode([RideSample].self, from: $0) } ?? [] }
        set { samplesData = try? JSONEncoder().encode(newValue) }
    }

    var powerCurve: [Int: Int] {
        get { powerCurveData.flatMap { try? JSONDecoder().decode([Int: Int].self, from: $0) } ?? [:] }
        set { powerCurveData = try? JSONEncoder().encode(newValue) }
    }

    /// Fills in the training metrics from the samples.
    func computeTraining(ftp: Int) {
        let watts = samples.map(\.powerW)
        powerCurve = Training.powerCurve(watts)
        let load = Training.load(watts, ftp: Double(ftp))
        tss = load.tss
        normalizedPowerW = Int(load.normalizedPower.rounded())
    }

    var summary: SessionSummary {
        SessionSummary(activeSeconds: activeSeconds, distanceM: distanceM, elevationGainM: elevationGainM, kcal: kcal,
                       avgPowerW: avgPowerW, maxPowerW: maxPowerW, avgCadenceRpm: avgCadenceRpm, avgSpeedKph: avgSpeedKph,
                       avgHeartRateBpm: avgHeartRateBpm, maxHeartRateBpm: maxHeartRateBpm)
    }

    func apply(_ s: SessionSummary, endedAt: Date) {
        self.endedAt = endedAt
        activeSeconds = s.activeSeconds
        distanceM = s.distanceM
        elevationGainM = s.elevationGainM
        kcal = s.kcal
        avgPowerW = s.avgPowerW
        maxPowerW = s.maxPowerW
        avgCadenceRpm = s.avgCadenceRpm
        avgSpeedKph = s.avgSpeedKph
        avgHeartRateBpm = s.avgHeartRateBpm
        maxHeartRateBpm = s.maxHeartRateBpm
    }

    /// The plan this ride used, for "ride this again".
    var plan: SessionPlan {
        var p = SessionPlan()
        p.plannedMinutes = plannedSeconds.map { $0 / 60 }
        p.terrainMode = RideControls.TerrainMode(rawValue: terrainMode) ?? .manual
        if let effort, let e = Effort(rawValue: effort) { p.effort = e }
        if let terrainType, let t = TerrainType(rawValue: terrainType) { p.terrainType = t }
        if let seed { p.seed = UInt64(bitPattern: seed) }
        if let workoutID, WorkoutStore.workout(id: workoutID) != nil {
            p.workoutID = workoutID
            p.plannedMinutes = nil
        }
        if let routeID, RouteStore.route(id: routeID) != nil {
            p.routeID = routeID
            p.plannedMinutes = nil
        }
        return p
    }
}

/// Everything the end-of-session modal needs, whether from a live ride or a recovered autosave.
struct FinishedRide: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let plan: SessionPlan
    let summary: SessionSummary
    let samples: [RideSample]
}

@MainActor
enum RideStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: RideSession.self)
        } catch {
            fatalError("Could not open the ride store: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    /// Creates or updates the in-progress autosave for a live ride.
    static func autosave(id: UUID, startedAt: Date, plan: SessionPlan, summary: SessionSummary, samples: [RideSample]) {
        let session = find(id) ?? {
            let s = RideSession(id: id, startedAt: startedAt, plan: plan)
            context.insert(s)
            return s
        }()
        session.apply(summary, endedAt: .now)
        session.samples = samples
        try? context.save()
    }

    static func save(_ ride: FinishedRide, rpe: Int?, note: String?) {
        let session = find(ride.id) ?? {
            let s = RideSession(id: ride.id, startedAt: ride.startedAt, plan: ride.plan)
            context.insert(s)
            return s
        }()
        session.apply(ride.summary, endedAt: ride.endedAt)
        session.samples = ride.samples
        session.rpe = rpe
        session.note = note?.isEmpty == true ? nil : note
        session.isComplete = true
        session.computeTraining(ftp: Preferences.shared.ftp)
        try? context.save()
    }

    /// The quickest completed attempt at a route, as a ghost to ride against.
    static func ghost(routeID: String, distanceM: Double) -> (ghost: Ghost, ride: RideSession)? {
        let minimum = distanceM * 0.95
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.routeID == routeID && $0.distanceM >= minimum },
                                             sortBy: [SortDescriptor(\.activeSeconds)])
        guard let ride = (try? context.fetch(d))?.first, let ghost = Ghost(samples: ride.samples) else { return nil }
        return (ghost, ride)
    }

    /// Rides saved before Phase 7 have no power curve or TSS yet.
    static func backfillTraining() {
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.powerCurveData == nil })
        guard let rides = try? context.fetch(d), !rides.isEmpty else { return }
        rides.forEach { $0.computeTraining(ftp: Preferences.shared.ftp) }
        try? context.save()
    }

    /// Best power per duration across rides, optionally only since a date and excluding one ride.
    static func bestCurve(since: Date = .distantPast, excluding: UUID? = nil) -> [Int: Int] {
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.startedAt >= since })
        let rides = (try? context.fetch(d)) ?? []
        return Training.best(of: rides.filter { $0.id != excluding }.map(\.powerCurve))
    }

    static func discard(id: UUID) {
        if let s = find(id) {
            context.delete(s)
            try? context.save()
        }
    }

    static func delete(_ session: RideSession) {
        context.delete(session)
        try? context.save()
    }

    /// An autosave left behind by a crash or kill, if any.
    static func unfinished() -> RideSession? {
        var d = FetchDescriptor<RideSession>(predicate: #Predicate { !$0.isComplete },
                                             sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private static func find(_ id: UUID) -> RideSession? {
        var d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}

extension RideSession {
    var finished: FinishedRide {
        FinishedRide(id: id, startedAt: startedAt, endedAt: endedAt, plan: plan, summary: summary, samples: samples)
    }
}
