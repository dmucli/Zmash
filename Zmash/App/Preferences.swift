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
    /// What setup, Settings and a new rider all accept.
    static let ftpRange = 60...500
    static let riderKgRange = 30.0...200.0

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
    /// A basic (non-smart) trainer's power curve; nil for a smart trainer. Its power comes from wheel speed.
    var basicTrainer: TrainerPowerCurve? { didSet { defaults.set(basicTrainer?.rawValue, forKey: "trainer.basic") } }
    /// Where the power numbers come from when a power meter is paired.
    var powerSource: PowerSource { didSet { defaults.set(powerSource.rawValue, forKey: "power.source") } }
    /// For wheel speed from a sensor (700×25c is 2105 mm).
    var wheelCircumferenceMM: Int { didSet { defaults.set(wheelCircumferenceMM, forKey: "wheel.circumference") } }
    /// Phase 2: speed-reactive wind streaks behind the ride screen.
    var windBackground: Bool { didSet { defaults.set(windBackground, forKey: "wind.background") } }
    /// Phase 2: metrics in a Picture-in-Picture window when leaving the app mid-ride.
    var pipOnLeave: Bool { didSet { defaults.set(pipOnLeave, forKey: "pip.leave") } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demo.mode") } }
    /// The first-run setup has been done (or skipped). Existing installs count as set up.
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: "setup.done") } }
    /// FTP was a guess at setup: the Today card leads with a ramp test until one is ridden.
    var suggestRampTest: Bool { didSet { defaults.set(suggestRampTest, forKey: "ramp.suggest") } }
    /// Gentle coaching in the band (off by default), and which kinds of message.
    var coaching: Bool { didSet { defaults.set(coaching, forKey: "coaching") } }
    /// Ride sounds (off by default), their volume, and the kilometre chime.
    var rideSound: Bool { didSet { defaults.set(rideSound, forKey: "sound") } }
    var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "sound.volume") } }
    var kilometreChime: Bool { didSet { defaults.set(kilometreChime, forKey: "sound.km") } }
    /// When the trainer last completed a spin-down calibration.
    var lastCalibration: Date? { didSet { defaults.set(lastCalibration, forKey: "calibration.last") } }
    /// iPhone: open the Apple Watch app with each ride, for heart rate and a view on the wrist (D105).
    var useWatch: Bool { didSet { defaults.set(useWatch, forKey: "watch.use") } }
    /// No calibration yet, or none for a month.
    var calibrationDue: Bool { lastCalibration.map { Date.now.timeIntervalSince($0) > 30 * 86_400 } ?? true }
    var coachKinds: Set<Coach.Kind> { didSet { defaults.set(coachKinds.map(\.rawValue), forKey: "coaching.kinds") } }
    var display: DisplayConfig { didSet { defaults.set(try? JSONEncoder().encode(display), forKey: "display") } }
    /// Functional threshold power: drives the power zones and effort colours of the faces.
    var ftp: Int { didSet { defaults.set(ftp, forKey: "ftp") } }
    var face: FaceID { didSet { defaults.set(face.rawValue, forKey: "face") } }
    /// Faces left out of the mid-ride rotation (swipe or D-pad). Stored as exclusions, so every face is in by
    /// default and faces added in later versions join automatically.
    var faceRotationExcluded: Set<FaceID> {
        didSet { defaults.set(faceRotationExcluded.map(\.rawValue), forKey: "face.rotation.excluded") }
    }

    /// Faces a swipe or the D-pad cycles through mid-ride, in gallery order.
    var faceRotation: [FaceID] { FaceID.allCases.filter { !faceRotationExcluded.contains($0) } }
    var faceMotion: FaceMotion { didSet { defaults.set(faceMotion.rawValue, forKey: "face.motion") } }
    /// The whole course's elevation profile along the bottom of every face, and how far it's zoomed in.
    var courseStrip: Bool { didSet { defaults.set(courseStrip, forKey: "course.strip") } }
    var courseZoom: CourseZoom { didSet { defaults.set(courseZoom.rawValue, forKey: "course.zoom") } }
    /// Per-face palette and slots (Phase 11); a face with no entry looks as it was designed.
    var faceStyles: [String: FaceStyle] { didSet { defaults.set(try? JSONEncoder().encode(faceStyles), forKey: "face.styles") } }
    var buttonMap: ButtonMap { didSet { defaults.set(try? JSONEncoder().encode(buttonMap), forKey: "button.map") } }
    var lastPlan: SessionPlan { didSet { defaults.set(try? JSONEncoder().encode(lastPlan), forKey: "last.plan") } }
    /// Who's riding (D112): "" is the first rider. Their numbers and faces are the settings above.
    var riderID: String { didSet { defaults.set(riderID, forKey: Riders.currentKey) } }
    /// Every rider's profile as last saved (the current one's live values are the settings themselves).
    var riderList: [RiderProfile] { didSet { defaults.set(try? JSONEncoder().encode(riderList), forKey: "riders") } }

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
        basicTrainer = defaults.string(forKey: "trainer.basic").flatMap(TrainerPowerCurve.init)
        hasCompletedSetup = defaults.object(forKey: "setup.done") as? Bool ?? (defaults.object(forKey: "last.plan") != nil)
        suggestRampTest = defaults.bool(forKey: "ramp.suggest")
        coaching = defaults.bool(forKey: "coaching")
        rideSound = defaults.bool(forKey: "sound")
        soundVolume = defaults.object(forKey: "sound.volume") as? Double ?? 0.7
        kilometreChime = defaults.object(forKey: "sound.km") as? Bool ?? true
        lastCalibration = defaults.object(forKey: "calibration.last") as? Date
        useWatch = defaults.bool(forKey: "watch.use")
        coachKinds = (defaults.stringArray(forKey: "coaching.kinds")?.compactMap(Coach.Kind.init)).map(Set.init) ?? Set(Coach.Kind.allCases)
        powerSource = defaults.string(forKey: "power.source").flatMap(PowerSource.init) ?? .trainer
        wheelCircumferenceMM = defaults.object(forKey: "wheel.circumference") as? Int ?? 2105
        windBackground = defaults.object(forKey: "wind.background") as? Bool ?? true
        pipOnLeave = defaults.object(forKey: "pip.leave") as? Bool ?? true
        #if targetEnvironment(simulator)
        demoMode = true // CoreBluetooth doesn't work in the Simulator.
        #else
        demoMode = defaults.bool(forKey: "demo.mode")
        #endif
        var loadedDisplay = defaults.data(forKey: "display").flatMap { try? JSONDecoder().decode(DisplayConfig.self, from: $0) } ?? .standard
        // Classic became the Live ride (D118): the old default font (rounded) moves to the bib numerals, once.
        if !defaults.bool(forKey: "display.bib-migrated") {
            if loadedDisplay.style == .rounded { loadedDisplay.style = .bib }
            defaults.set(true, forKey: "display.bib-migrated")
            defaults.set(try? JSONEncoder().encode(loadedDisplay), forKey: "display")
        }
        display = loadedDisplay
        ftp = defaults.object(forKey: "ftp") as? Int ?? 200
        face = defaults.string(forKey: "face").flatMap(FaceID.init) ?? .paper
        // The old "face.rotation" shortlist (three faces by default) is no longer read: every face is in now.
        defaults.removeObject(forKey: "face.rotation")
        faceRotationExcluded = Set((defaults.stringArray(forKey: "face.rotation.excluded") ?? []).compactMap(FaceID.init))
        faceMotion = defaults.string(forKey: "face.motion").flatMap(FaceMotion.init) ?? .full
        courseStrip = defaults.object(forKey: "course.strip") as? Bool ?? true
        courseZoom = defaults.string(forKey: "course.zoom").flatMap(CourseZoom.init) ?? .whole
        faceStyles = defaults.data(forKey: "face.styles").flatMap { try? JSONDecoder().decode([String: FaceStyle].self, from: $0) } ?? [:]
        var map = defaults.data(forKey: "button.map").flatMap { try? JSONDecoder().decode(ButtonMap.self, from: $0) } ?? .standard
        // D108: A now opens the control panel. A map saved with A on its old default (pause) moves over.
        if !defaults.bool(forKey: "button.map.a-controls") {
            if map[.a] == .pauseToggle { map[.a] = .toggleControls }
            defaults.set(true, forKey: "button.map.a-controls")
            defaults.set(try? JSONEncoder().encode(map), forKey: "button.map")
        }
        buttonMap = map
        riderID = defaults.string(forKey: Riders.currentKey) ?? ""
        lastPlan = defaults.data(forKey: "last.plan").flatMap { try? JSONDecoder().decode(SessionPlan.self, from: $0) } ?? SessionPlan()
        // Before profiles: one rider, "", with today's settings.
        riderList = []
        riderList = defaults.data(forKey: "riders").flatMap { try? JSONDecoder().decode([RiderProfile].self, from: $0) }
            ?? [RiderProfile(id: "", name: "Rider 1", riderKg: riderKg, bikeKg: bikeKg, ftp: ftp, face: face, faceStyles: faceStyles,
                             display: display, saveToHealth: saveToHealth, suggestRampTest: suggestRampTest)]
    }

    var rider: RiderModel { RiderModel(riderKg: riderKg, bikeKg: bikeKg) }

    func style(_ face: FaceID) -> FaceStyle { faceStyles[face.rawValue] ?? .default(face) }

    func setStyle(_ style: FaceStyle, for face: FaceID) { faceStyles[face.rawValue] = style }

    func resetStyle(_ face: FaceID) { faceStyles[face.rawValue] = nil }

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
    /// Structured workout (replaces duration and terrain when set).
    var workoutID: String?
    /// Workout targets held by the trainer in ERG (default), or turned into gradients.
    var workoutERG: Bool?
    /// A route ridden by distance (replaces duration and terrain, like a workout).
    var routeID: String?
    /// Auto terrain from a finger drawing instead of the generator. The drawing is kept when
    /// switching away, so coming back to Draw finds it where you left it.
    var drawn: Bool?
    var drawing: [Double]?

    var workout: Workout? { workoutID.flatMap(WorkoutStore.workout) }
    var isDrawn: Bool { terrainMode == .auto && drawn == true && drawing != nil }
    var route: Route? { routeID.flatMap(RouteStore.route) }
    var usesERG: Bool { workoutERG ?? true }

    /// Timed rides and workouts end on schedule; free rides, routes and the ramp test run until stopped.
    var plannedSeconds: Double? {
        if routeID != nil { return nil }
        if let workout { return workout.isRampTest ? nil : Double(workout.duration) }
        return plannedMinutes.map { Double($0 * 60) }
    }

    static let durations: [Int?] = [15, 30, 45, 60, 90, nil]
    /// How long one pass of a drawing lasts on an open-ended ride.
    static let drawnLap: Double = 1800

    /// More terrain for an open-ended ride, block by block: the drawing again, or more generated terrain.
    func profileBlock(index: Int) -> TerrainProfile {
        if isDrawn, let drawing { return DrawnCourse.profile(drawing, duration: Self.drawnLap, effort: effort) }
        return TerrainGenerator.block(index: index, type: terrainType, effort: effort, seed: seed)
    }

    func profile() -> TerrainProfile? {
        guard terrainMode == .auto, workoutID == nil, routeID == nil else { return nil }
        if isDrawn, let drawing {
            // The drawing spans the ride; an open-ended ride repeats it every half hour.
            return DrawnCourse.profile(drawing, duration: plannedSeconds ?? Self.drawnLap, effort: effort)
        }
        if let plannedSeconds {
            return TerrainGenerator.generate(duration: plannedSeconds, type: terrainType, effort: effort, seed: seed)
        }
        return TerrainGenerator.block(index: 0, type: terrainType, effort: effort, seed: seed)
    }
}


/// Where the ride's power comes from when both a trainer and a power meter are paired.
enum PowerSource: String, CaseIterable {
    case trainer
    case powerMeter
}
