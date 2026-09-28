import Foundation
import ZmashKit

/// One person riding on this iPad (D112): their numbers and their faces. Devices, buttons, units and sounds are
/// the iPad's and shared.
struct RiderProfile: Codable, Identifiable, Equatable {
    /// "" for the first rider (every ride saved before profiles existed is theirs).
    var id: String
    var name: String
    var riderKg: Double
    var bikeKg: Double
    var ftp: Int
    var face: FaceID
    var faceStyles: [String: FaceStyle]
    var display: DisplayConfig
    var saveToHealth: Bool
    var suggestRampTest: Bool
    /// For heart-rate zones (D140); nil until set.
    var maxHeartRate: Int? = nil
    /// The cadence the coach keeps you to (D142), rpm.
    var cadenceLow: Int? = nil
    var cadenceHigh: Int? = nil
    /// The big number on their faces (D159); nil: speed.
    var mainNumber: FaceMetric? = nil

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// The current rider's id, readable anywhere (plan and campaign files, upload keys).
enum Riders {
    static let currentKey = "rider.current"
    nonisolated static var currentID: String { UserDefaults.standard.string(forKey: currentKey) ?? "" }
}

extension Preferences {
    /// Everyone on this iPad, the current rider's entry refreshed from the live settings.
    var riders: [RiderProfile] {
        riderList.map { $0.id == riderID ? snapshot(named: $0.name) : $0 }
    }

    var currentRider: RiderProfile { riders.first { $0.id == riderID } ?? snapshot(named: "Rider") }

    /// The live settings as the current rider's profile.
    private func snapshot(named name: String) -> RiderProfile {
        RiderProfile(id: riderID, name: name, riderKg: riderKg, bikeKg: bikeKg, ftp: ftp, face: face,
                     faceStyles: faceStyles, display: display, saveToHealth: saveToHealth, suggestRampTest: suggestRampTest,
                     maxHeartRate: maxHeartRate, cadenceLow: cadenceBand.lowerBound, cadenceHigh: cadenceBand.upperBound,
                     mainNumber: mainNumber)
    }

    /// Makes someone else the rider: their numbers and faces come in, the outgoing rider's are kept.
    func switchRider(to id: String) {
        guard id != riderID, let next = riderList.first(where: { $0.id == id }) else { return }
        riderList = riders
        riderKg = next.riderKg
        bikeKg = next.bikeKg
        ftp = next.ftp
        face = next.face
        faceStyles = next.faceStyles
        display = next.display
        saveToHealth = next.saveToHealth
        suggestRampTest = next.suggestRampTest
        maxHeartRate = next.maxHeartRate
        cadenceBand = (next.cadenceLow ?? Preferences.defaultCadence.lowerBound)...(next.cadenceHigh ?? Preferences.defaultCadence.upperBound)
        mainNumber = next.mainNumber ?? .speed
        riderID = id
    }

    /// Adds a rider (as the designs look out of the box) and switches to them.
    @discardableResult
    func addRider(name: String, riderKg: Double, bikeKg: Double, ftp: Int, guessedFTP: Bool) -> String {
        let id = UUID().uuidString
        riderList = riders + [RiderProfile(id: id, name: name, riderKg: riderKg, bikeKg: bikeKg, ftp: ftp, face: .paper,
                                           faceStyles: [:], display: .standard, saveToHealth: false, suggestRampTest: guessedFTP)]
        switchRider(to: id)
        return id
    }

    func renameRider(_ id: String, to name: String) {
        riderList = riders.map { var r = $0; if r.id == id { r.name = name }; return r }
    }

    /// Removes a rider who isn't the current one (their rides are deleted by the caller).
    func removeRider(_ id: String) {
        guard id != riderID else { return }
        riderList = riders.filter { $0.id != id }
    }
}
