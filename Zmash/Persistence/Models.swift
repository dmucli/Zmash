import Foundation
import Observation
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
    /// The finger-drawn course, when the ride used one.
    var drawing: [Double]?
    /// The face on screen when the ride was saved (for the recap's favourite face).
    var face: String?
    /// Whose ride it is (D112); "" is the first rider, and every ride from before profiles.
    var riderID: String = ""
    /// Training load, computed on save with the FTP of the day (Phase 7).
    var tss: Double?
    var normalizedPowerW: Int?
    /// Best power per duration ([seconds: watts], JSON).
    var powerCurveData: Data?
    /// False while the ride is only an autosave (crash recovery).
    var isComplete: Bool
    /// Where the ride has been sent (`UploadService` raw values), so History can say so and nothing goes twice.
    var sentTo: [String]?
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
        self.drawing = plan.isDrawn ? plan.drawing : nil
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

    /// Decoded once and kept (views and summaries read them several times per draw).
    var samples: [RideSample] {
        get { DecodedCaches.samples.value(id: id, data: samplesData) ?? [] }
        set { samplesData = try? JSONEncoder().encode(newValue) }
    }

    var powerCurve: [Int: Int] {
        get { DecodedCaches.curves.value(id: id, data: powerCurveData) ?? [:] }
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
        if let drawing {
            p.terrainMode = .auto
            p.drawn = true
            p.drawing = drawing
        }
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

/// Rides' decoded blobs, by ride, while their data is unchanged (a new save changes the data, and the entry with it).
/// Small: the rides on screen and in the summaries; the oldest go first.
final class DecodedCache<Value: Decodable>: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [UUID: (data: Data, value: Value)] = [:]
    private var order: [UUID] = []
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func value(id: UUID, data: Data?) -> Value? {
        guard let data else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = entries[id], hit.data == data { return hit.value }
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else { return nil }
        if entries[id] == nil { order.append(id) }
        entries[id] = (data, value)
        while order.count > capacity { entries[order.removeFirst()] = nil }
        return value
    }
}

enum DecodedCaches {
    static let samples = DecodedCache<[RideSample]>(capacity: 12)
    static let curves = DecodedCache<[Int: Int]>(capacity: 400)
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

/// Bumped whenever a ride is saved or deleted, so screens that sum rides up (home, the Today card) recompute.
@MainActor @Observable
final class RideChanges {
    static let shared = RideChanges()
    private(set) var revision = 0
    func bump() { revision += 1 }
}

@MainActor
enum RideStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: RideSession.self)
        } catch {
            // Crashing here would crash every launch. Keep the old files aside for recovery and start afresh.
            Diagnostics.log("store", "could not open the ride store: \(error)")
            recoveredFolder = moveStoreAside()
            if let fresh = try? ModelContainer(for: RideSession.self) { return fresh }
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: RideSession.self, configurations: memory)
        }
    }()

    /// Set when the store couldn't be opened and its files were moved here (in Files, under Zmash).
    private(set) static var recoveredFolder: URL?

    private static func moveStoreAside() -> URL? {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        let files = ((try? fm.contentsOfDirectory(atPath: support.path(percentEncoded: false))) ?? [])
            .filter { $0.hasPrefix("default.store") || $0 == ".default_SUPPORT" }
        guard !files.isEmpty else { return nil }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let folder = URL.documentsDirectory.appending(path: "Recovered rides \(stamp)", directoryHint: .isDirectory)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files { try? fm.moveItem(at: support.appending(path: name), to: folder.appending(path: name)) }
        Diagnostics.log("store", "moved the unreadable store to \(folder.lastPathComponent)")
        return folder
    }

    static var context: ModelContext { container.mainContext }

    /// Saves, and says so in the diagnostics log if it didn't work (a lost ride shouldn't be silent).
    private static func commit(_ what: String) {
        do {
            try context.save()
        } catch {
            Diagnostics.log("store", "\(what) failed: \(error.localizedDescription)")
        }
    }

    /// Creates or updates the in-progress autosave for a live ride.
    static func autosave(id: UUID, startedAt: Date, plan: SessionPlan, summary: SessionSummary, samples: [RideSample]) {
        let session = find(id) ?? {
            let s = RideSession(id: id, startedAt: startedAt, plan: plan)
            s.riderID = Preferences.shared.riderID
            context.insert(s)
            return s
        }()
        session.apply(summary, endedAt: .now)
        session.samples = samples
        commit("autosave")
    }

    static func save(_ ride: FinishedRide, rpe: Int?, note: String?) {
        let session = find(ride.id) ?? {
            let s = RideSession(id: ride.id, startedAt: ride.startedAt, plan: ride.plan)
            s.riderID = Preferences.shared.riderID
            context.insert(s)
            return s
        }()
        session.apply(ride.summary, endedAt: ride.endedAt)
        session.samples = ride.samples
        session.rpe = rpe
        session.note = note?.isEmpty == true ? nil : note
        session.isComplete = true
        session.face = Preferences.shared.face.rawValue
        if ride.plan.workout?.isRampTest == true { Preferences.shared.suggestRampTest = false }
        session.computeTraining(ftp: Preferences.shared.ftp)
        commit("save")
        RideChanges.shared.bump()
    }

    /// The quickest completed attempt at a route, as a ghost to ride against.
    static func ghost(routeID: String, distanceM: Double) -> (ghost: Ghost, ride: RideSession)? {
        let minimum = distanceM * 0.95
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.routeID == routeID && $0.distanceM >= minimum },
                                             sortBy: [SortDescriptor(\.activeSeconds)])
        guard let ride = (try? context.fetch(d))?.first, let ghost = Ghost(samples: ride.samples) else { return nil }
        return (ghost, ride)
    }

    /// Rides saved before Phase 7 have no power curve or TSS yet.
    static func backfillTraining() {
        // Only the current rider's: training load uses their FTP.
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.powerCurveData == nil })
        guard let rides = try? context.fetch(d), !rides.isEmpty else { return }
        rides.forEach { $0.computeTraining(ftp: Preferences.shared.ftp) }
        commit("backfill")
    }

    /// Best power per duration across rides, optionally only since a date and excluding one ride.
    static func bestCurve(since: Date = .distantPast, excluding: UUID? = nil) -> [Int: Int] {
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.startedAt >= since })
        let rides = (try? context.fetch(d)) ?? []
        return Training.best(of: rides.filter { $0.id != excluding }.map(\.powerCurve))
    }

    static func discard(id: UUID) {
        if let s = find(id) {
            context.delete(s)
            commit("discard")
        }
    }

    /// Deletes a ride, and takes back what it counted for: its plan session and its campaign stage.
    static func delete(_ session: RideSession) {
        if session.isComplete {
            PlanStore.unrecord(rideStartedAt: session.startedAt, riderID: session.riderID)
            CampaignStore.unrecord(rideID: session.id)
        }
        context.delete(session)
        commit("delete")
        RideChanges.shared.bump()
    }

    /// Changes how a saved ride felt, and its note.
    static func update(_ session: RideSession, rpe: Int?, note: String?) {
        session.rpe = rpe
        session.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? note : nil
        commit("edit")
    }

    /// Notes that a ride went to a service (an upload, or "health").
    static func markSent(_ id: UUID, to service: String) {
        guard let s = find(id), !(s.sentTo ?? []).contains(service) else { return }
        s.sentTo = (s.sentTo ?? []) + [service]
        commit("mark sent")
    }

    /// Where a ride has been sent.
    static func sentTo(_ id: UUID) -> [String] { find(id)?.sentTo ?? [] }

    /// The current rider's autosave left behind by a crash or kill, if any.
    static func unfinished() -> RideSession? {
        let rid = Preferences.shared.riderID
        var d = FetchDescriptor<RideSession>(predicate: #Predicate { !$0.isComplete && $0.riderID == rid },
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
