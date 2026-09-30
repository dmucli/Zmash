import Foundation
import SwiftData
import ZmashKit

/// A ride as a FIT file, the same wherever it goes: the share sheet, an upload, or every ride at once (D134).
@MainActor
enum RideExport {
    /// Where exports of every ride go: Files → On My iPad (or iPhone) → Zmash → Exports.
    static var folder: URL { URL.documentsDirectory.appending(path: "Exports", directoryHint: .isDirectory) }

    static func fit(_ ride: FinishedRide) -> Data {
        FITWriter.encode(startedAt: ride.startedAt, samples: ride.samples, summary: ride.summary,
                         startAltitudeM: ride.plan.route?.elevation(atDistance: 0) ?? 0, endedAt: ride.endedAt)
    }

    /// "2026-09-24 1830 Mont Ventoux.fit": sorts by date, says what it was.
    static func fileName(_ session: RideSession) -> String {
        let date = session.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let time = session.startedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            .replacingOccurrences(of: ":", with: "")
        let name = (session.workoutName ?? session.routeName ?? "Free ride")
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return "\(date) \(time) \(name).fit"
    }

    /// One ride's FIT in the temporary folder, for the share sheet.
    static func temporaryFile(_ session: RideSession) -> URL? {
        let ride = session.finished
        guard !ride.samples.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName(session))
        return (try? fit(ride).write(to: url)) != nil ? url : nil
    }

    /// Every one of the current rider's rides as FIT files, in a new folder; returns it and how many went in.
    static func allRides() throws -> (url: URL, count: Int) {
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid },
                                             sortBy: [SortDescriptor(\.startedAt)])
        let rides = (try? RideStore.context.fetch(d)) ?? []
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = folder.appending(path: "Zmash FIT \(stamp) \(Preferences.shared.currentRider.name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var count = 0
        for session in rides {
            let ride = session.finished
            guard !ride.samples.isEmpty else { continue }
            try fit(ride).write(to: url.appending(path: fileName(session)), options: .atomic)
            count += 1
        }
        Diagnostics.log("export", "wrote \(count) FIT files to \(url.lastPathComponent)")
        return (url, count)
    }
}
