import Foundation
import UIKit

/// In-app diagnostic log (roadmap Phase 5): connection, protocol and ride events in a ring buffer,
/// exported from Settings as a text file so a bug found on the bike can be shared without Xcode.
@MainActor
enum Diagnostics {
    private static var lines: [String] = []
    private static let capacity = 3000
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ category: String, _ message: String) {
        lines.append("\(stamp.string(from: .now)) [\(category)] \(message)")
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        #if DEBUG
        print("[\(category)] \(message)")
        #endif
    }

    /// The full report: environment, settings, paired devices, then the log.
    static func report(hub: DeviceHub, prefs: Preferences) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        var out = [
            "Zmash diagnostics — \(stamp.string(from: .now))",
            "App \(version) · \(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "",
            "Settings: face=\(prefs.face.rawValue) protocol=\(prefs.trainerProtocol.rawValue) erg=\(prefs.ergShifting)",
            "  gears=\(prefs.gearCount) ftp=\(prefs.ftp) rider=\(prefs.riderKg)kg bike=\(prefs.bikeKg)kg units=\(prefs.units.rawValue)",
            "  demo=\(hub.isDemo) autopause=\(prefs.autoPause) pip=\(prefs.pipOnLeave) health=\(prefs.saveToHealth)",
            "",
            "Controller: \(hub.ride.link) battery=\(hub.ride.batteryPercent.map(String.init) ?? "–") fw=\(hub.ride.firmware ?? "–")",
            "Trainer: \(hub.trainer.link) protocol=\(hub.trainer.activeProtocol?.rawValue ?? "–") note=\(hub.trainer.statusNote ?? "–")",
            "Heart rate: \(hub.heartRateBpm.map { "\($0) bpm" } ?? "–")",
        ]
        if let group = hub.ble?.controllers {
            for c in group.clients {
                out.append("  \(c.kind.displayName): \(c.link) fw=\(c.firmware ?? "–") battery=\(c.batteryPercent.map(String.init) ?? "–")")
            }
        }
        out += ["", "Log (\(lines.count) lines):"] + lines
        return out.joined(separator: "\n")
    }

    /// Writes the report to a temporary file for the share sheet.
    static func exportFile(hub: DeviceHub, prefs: Preferences) -> URL? {
        let name = "Zmash diagnostics \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? report(hub: hub, prefs: prefs).write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}
