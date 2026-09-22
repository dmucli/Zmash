import Foundation
import UIKit
import Observation
import ZmashKit

enum ThemePreference: String, CaseIterable {
    case system, light, dark
}

/// User settings (brief §15), persisted in UserDefaults and observable so the UI reacts live
/// (e.g. the Ride's Y button toggling the theme).
@MainActor @Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var riderKg: Double { didSet { defaults.set(riderKg, forKey: "rider.kg") } }
    var bikeKg: Double { didSet { defaults.set(bikeKg, forKey: "bike.kg") } }
    var units: Units { didSet { defaults.set(units.rawValue, forKey: "units") } }
    var theme: ThemePreference { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var hapticsOnShift: Bool { didSet { defaults.set(hapticsOnShift, forKey: "haptics.shift") } }
    /// Number of virtual gears (fewer = bigger steps).
    var gearCount: Int { didSet { defaults.set(gearCount, forKey: "gear.count") } }
    /// FTMS fallback: virtual shifting through ERG target power instead of an effective grade.
    var ergShifting: Bool { didSet { defaults.set(ergShifting, forKey: "erg.shifting") } }
    /// Phase 3: save finished rides to Apple Health.
    var saveToHealth: Bool { didSet { defaults.set(saveToHealth, forKey: "health.save") } }
    var autoPause: Bool { didSet { defaults.set(autoPause, forKey: "autopause") } }
    /// Watts smoothing window in seconds (0 = instant).
    var wattsWindow: Int { didSet { defaults.set(wattsWindow, forKey: "watts.window") } }
    var trainerProtocol: TrainerProtocolPreference { didSet { defaults.set(trainerProtocol.rawValue, forKey: "trainer.protocol") } }
    /// Phase 2: speed-reactive wind streaks behind the ride screen.
    var windBackground: Bool { didSet { defaults.set(windBackground, forKey: "wind.background") } }
    /// Phase 2: metrics in a Picture-in-Picture window when leaving the app mid-ride.
    var pipOnLeave: Bool { didSet { defaults.set(pipOnLeave, forKey: "pip.leave") } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demo.mode") } }
    var display: DisplayConfig { didSet { defaults.set(try? JSONEncoder().encode(display), forKey: "display") } }
    /// Functional threshold power: drives the power zones and effort colours of the faces.
    var ftp: Int { didSet { defaults.set(ftp, forKey: "ftp") } }
    var face: FaceID { didSet { defaults.set(face.rawValue, forKey: "face") } }
    /// Faces the D-pad cycles through mid-ride.
    var faceRotation: [FaceID] { didSet { defaults.set(faceRotation.map(\.rawValue), forKey: "face.rotation") } }
    var faceMotion: FaceMotion { didSet { defaults.set(faceMotion.rawValue, forKey: "face.motion") } }
    var buttonMap: ButtonMap { didSet { defaults.set(try? JSONEncoder().encode(buttonMap), forKey: "button.map") } }
    var lastPlan: SessionPlan { didSet { defaults.set(try? JSONEncoder().encode(lastPlan), forKey: "last.plan") } }

    private init() {
        riderKg = defaults.object(forKey: "rider.kg") as? Double ?? 75
        bikeKg = defaults.object(forKey: "bike.kg") as? Double ?? 9
        units = defaults.string(forKey: "units").flatMap(Units.init) ?? .metric
        theme = defaults.string(forKey: "theme").flatMap(ThemePreference.init) ?? .system
        hapticsOnShift = defaults.object(forKey: "haptics.shift") as? Bool ?? true
        autoPause = defaults.object(forKey: "autopause") as? Bool ?? true
        gearCount = defaults.object(forKey: "gear.count") as? Int ?? 24
        ergShifting = defaults.bool(forKey: "erg.shifting")
        saveToHealth = defaults.bool(forKey: "health.save")
        wattsWindow = defaults.object(forKey: "watts.window") as? Int ?? 3
        trainerProtocol = defaults.string(forKey: "trainer.protocol").flatMap(TrainerProtocolPreference.init) ?? .ftms
        windBackground = defaults.object(forKey: "wind.background") as? Bool ?? true
        pipOnLeave = defaults.object(forKey: "pip.leave") as? Bool ?? true
        #if targetEnvironment(simulator)
        demoMode = true // CoreBluetooth doesn't work in the Simulator.
        #else
        demoMode = defaults.bool(forKey: "demo.mode")
        #endif
        display = defaults.data(forKey: "display").flatMap { try? JSONDecoder().decode(DisplayConfig.self, from: $0) } ?? .standard
        ftp = defaults.object(forKey: "ftp") as? Int ?? 200
        face = defaults.string(forKey: "face").flatMap(FaceID.init) ?? .paper
        let rotation = (defaults.stringArray(forKey: "face.rotation") ?? []).compactMap(FaceID.init)
        faceRotation = rotation.isEmpty ? FaceID.defaultRotation : rotation
        faceMotion = defaults.string(forKey: "face.motion").flatMap(FaceMotion.init) ?? .full
        buttonMap = defaults.data(forKey: "button.map").flatMap { try? JSONDecoder().decode(ButtonMap.self, from: $0) } ?? .standard
        lastPlan = defaults.data(forKey: "last.plan").flatMap { try? JSONDecoder().decode(SessionPlan.self, from: $0) } ?? SessionPlan()
    }

    var rider: RiderModel { RiderModel(riderKg: riderKg, bikeKg: bikeKg) }

    /// Next face in the D-pad rotation (the current face is always part of it).
    func cycleFace(_ step: Int) {
        var ring = faceRotation
        if !ring.contains(face) { ring.append(face) }
        guard let i = ring.firstIndex(of: face), ring.count > 1 else { return }
        face = ring[(i + step + ring.count) % ring.count]
    }

    /// Y button: flip between light and dark (from "system", flip away from the current appearance).
    func toggleTheme() {
        switch theme {
        case .dark: theme = .light
        case .light: theme = .dark
        case .system:
            let style = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.traitCollection.userInterfaceStyle }.first
            theme = style == .dark ? .light : .dark
        }
    }
}

/// What the rider chose on the setup screen.
struct SessionPlan: Codable, Equatable {
    /// nil = free ride.
    var plannedMinutes: Int? = 30
    var terrainMode: RideControls.TerrainMode = .manual
    var effort: Effort = .medium
    var terrainType: TerrainType = .rolling
    var seed: UInt64 = UInt64.random(in: 1...UInt64(Int64.max))

    var plannedSeconds: Double? { plannedMinutes.map { Double($0 * 60) } }

    static let durations: [Int?] = [15, 30, 45, 60, 90, nil]

    func profile() -> TerrainProfile? {
        guard terrainMode == .auto else { return nil }
        if let plannedSeconds {
            return TerrainGenerator.generate(duration: plannedSeconds, type: terrainType, effort: effort, seed: seed)
        }
        return TerrainGenerator.block(index: 0, type: terrainType, effort: effort, seed: seed)
    }
}

