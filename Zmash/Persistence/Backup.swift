import Foundation
import SwiftData
import ZmashKit

/// Everything this iPad knows, copied to a folder in Files and read back (the only backup without iCloud).
///
/// A backup is a folder: `rides.json` (every rider's rides, samples included), the plan, campaign and route files as
/// they are, and `settings.plist` (riders, preferences, custom workouts, button map). Upload tokens and keys stay in
/// the keychain and aren't copied: connect again after restoring on another device.
@MainActor
enum Backup {
    /// Where backups go: Files → On My iPad → Zmash → Backups.
    static var folder: URL { URL.documentsDirectory.appending(path: "Backups", directoryHint: .isDirectory) }

    private static let stores = ["Plans", "Campaigns", "Routes"]

    struct Counts {
        var rides = 0
        var files = 0
        var settings = false

        var summary: String {
            var parts = ["\(rides) ride\(rides == 1 ? "" : "s")", "\(files) plan, campaign and route file\(files == 1 ? "" : "s")"]
            if settings { parts.append("riders and settings") }
            return parts.joined(separator: ", ")
        }
    }

    enum BackupError: LocalizedError {
        case notABackup

        var errorDescription: String? {
            switch self {
            case .notABackup: "That folder isn't a Zmash backup (it has no rides.json)."
            }
        }
    }

    // MARK: Backing up

    /// Writes a new backup folder and returns it.
    static func make() throws -> (url: URL, counts: Counts) {
        let fm = FileManager.default
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        let url = folder.appending(path: "Zmash backup \(stamp)", directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        var counts = Counts()

        let rides = (try? RideStore.context.fetch(FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete }))) ?? []
        try JSONEncoder().encode(rides.map(StoredRide.init)).write(to: url.appending(path: "rides.json"), options: .atomic)
        counts.rides = rides.count

        for name in stores {
            let from = URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            try fm.copyItem(at: from, to: url.appending(path: name, directoryHint: .isDirectory))
            counts.files += ((try? fm.contentsOfDirectory(atPath: from.path(percentEncoded: false))) ?? []).count
        }

        if let id = Bundle.main.bundleIdentifier, let settings = UserDefaults.standard.persistentDomain(forName: id) {
            let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
            try data.write(to: url.appending(path: "settings.plist"), options: .atomic)
            counts.settings = true
        }
        Diagnostics.log("backup", "wrote \(url.lastPathComponent): \(counts.summary)")
        return (url, counts)
    }

    // MARK: Restoring

    /// Adds what a backup has and this iPad doesn't: rides by id, plan, campaign and route files by name. With
    /// `settings`, the backup's riders and preferences replace this iPad's (they take effect on the next launch).
    static func restore(from url: URL, settings: Bool) throws -> Counts {
        let fm = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ridesURL = url.appending(path: "rides.json")
        guard fm.fileExists(atPath: ridesURL.path(percentEncoded: false)) else { throw BackupError.notABackup }
        var counts = Counts()

        let stored = try JSONDecoder().decode([StoredRide].self, from: Data(contentsOf: ridesURL))
        let existing = Set(((try? RideStore.context.fetch(FetchDescriptor<RideSession>())) ?? []).map(\.id))
        for ride in stored where !existing.contains(ride.id) {
            RideStore.context.insert(ride.session())
            counts.rides += 1
        }
        try RideStore.context.save()

        for name in stores {
            let from = url.appending(path: name, directoryHint: .isDirectory)
            let to = URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
            guard let files = try? fm.contentsOfDirectory(atPath: from.path(percentEncoded: false)) else { continue }
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            for file in files where !fm.fileExists(atPath: to.appending(path: file).path(percentEncoded: false)) {
                try fm.copyItem(at: from.appending(path: file), to: to.appending(path: file))
                counts.files += 1
            }
        }

        if settings, let data = try? Data(contentsOf: url.appending(path: "settings.plist")),
           let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
            counts.settings = true
        }
        PlanStore.reload()
        CampaignStore.reload()
        Diagnostics.log("backup", "restored from \(url.lastPathComponent): \(counts.summary)")
        RideChanges.shared.bump()
        return counts
    }
}

/// A ride as it goes into a backup: every stored field, samples and power curve as their encoded blobs.
private struct StoredRide: Codable {
    var id: UUID
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
    var drawing: [Double]?
    var face: String?
    var riderID: String
    var tss: Double?
    var normalizedPowerW: Int?
    var powerCurveData: Data?
    var sentTo: [String]?
    var samplesData: Data?

    @MainActor
    init(_ s: RideSession) {
        id = s.id; startedAt = s.startedAt; endedAt = s.endedAt; activeSeconds = s.activeSeconds
        plannedSeconds = s.plannedSeconds; terrainMode = s.terrainMode; effort = s.effort; terrainType = s.terrainType
        seed = s.seed; distanceM = s.distanceM; elevationGainM = s.elevationGainM; kcal = s.kcal
        avgPowerW = s.avgPowerW; maxPowerW = s.maxPowerW; avgCadenceRpm = s.avgCadenceRpm; avgSpeedKph = s.avgSpeedKph
        avgHeartRateBpm = s.avgHeartRateBpm; maxHeartRateBpm = s.maxHeartRateBpm; rpe = s.rpe; note = s.note
        workoutID = s.workoutID; workoutName = s.workoutName; routeID = s.routeID; routeName = s.routeName
        drawing = s.drawing; face = s.face; riderID = s.riderID; tss = s.tss; normalizedPowerW = s.normalizedPowerW
        powerCurveData = s.powerCurveData; sentTo = s.sentTo; samplesData = s.samplesData
    }

    @MainActor
    func session() -> RideSession {
        let s = RideSession(id: id, startedAt: startedAt, plan: SessionPlan())
        s.endedAt = endedAt; s.activeSeconds = activeSeconds; s.plannedSeconds = plannedSeconds
        s.terrainMode = terrainMode; s.effort = effort; s.terrainType = terrainType; s.seed = seed
        s.distanceM = distanceM; s.elevationGainM = elevationGainM; s.kcal = kcal
        s.avgPowerW = avgPowerW; s.maxPowerW = maxPowerW; s.avgCadenceRpm = avgCadenceRpm; s.avgSpeedKph = avgSpeedKph
        s.avgHeartRateBpm = avgHeartRateBpm; s.maxHeartRateBpm = maxHeartRateBpm; s.rpe = rpe; s.note = note
        s.workoutID = workoutID; s.workoutName = workoutName; s.routeID = routeID; s.routeName = routeName
        s.drawing = drawing; s.face = face; s.riderID = riderID; s.tss = tss; s.normalizedPowerW = normalizedPowerW
        s.powerCurveData = powerCurveData; s.sentTo = sentTo; s.samplesData = samplesData
        s.isComplete = true
        return s
    }
}
