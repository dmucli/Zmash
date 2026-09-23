import Foundation
import Observation
import ZmashKit

enum DeviceRole: String, CaseIterable, Identifiable {
    /// Zwift controllers (raw value kept from when this was Ride-only, for stored pairings).
    case ride
    case trainer
    case heartRate
    case powerMeter
    /// A speed and/or cadence sensor (CSC).
    case speedCadence

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ride: "Controller"
        case .trainer: "Trainer"
        case .heartRate: "Heart rate"
        case .powerMeter: "Power meter"
        case .speedCadence: "Speed or cadence sensor"
        }
    }

    /// A Zwift Play is two peripherals; everything else is one.
    var maxDevices: Int { self == .ride ? 2 : 1 }
}

/// Where rider commands and controller status come from (real Zwift Ride or demo).
@MainActor
protocol RideSource: AnyObject, Observable {
    var link: LinkState { get }
    var batteryPercent: Int? { get }
    var firmware: String? { get }
    var onCommand: ((RideCommand) -> Void)? { get set }
    func buzz(double: Bool)
}

/// Where power/cadence come from and where resistance goes (real KICKR or demo).
@MainActor
protocol TrainerSource: AnyObject, Observable {
    var link: LinkState { get }
    var metrics: TrainerMetrics? { get }
    var activeProtocol: TrainerProtocol? { get }
    var statusNote: String? { get }
    /// True when the trainer applies the virtual gear itself (Zwift protocol, demo).
    /// Otherwise the session engine folds gearing into an effective grade (FTMS).
    var handlesGearing: Bool { get }
    /// Heart rate from the trainer itself (FTMS/demo), if it reports one.
    var heartRateBpm: Int? { get }
    /// Called on every new metrics frame; drives the session clock, also while backgrounded.
    var onMetrics: ((TrainerMetrics) -> Void)? { get set }
    /// Target terrain grade and virtual gear. The Zwift protocol applies both natively;
    /// FTMS applies the grade (the session engine folds gearing into it from M2).
    func apply(gradePercent: Double, gearRatio: Double)
    /// ERG fallback (FTMS): hold this power instead of simulating a grade.
    func applyTargetPower(_ watts: Int)
    /// True when `applyTargetPower` is honoured (FTMS, demo): workouts can run in ERG.
    var supportsERG: Bool { get }
}

extension TrainerSource {
    func applyTargetPower(_ watts: Int) {}
    var supportsERG: Bool { false }
    var heartRateBpm: Int? { nil }
}

/// Remembered peripherals per role (controllers: up to two, e.g. both sides of a Zwift Play).
enum DeviceRegistry {
    private static func key(_ role: DeviceRole) -> String { "devices.\(role.rawValue)" }

    static func ids(for role: DeviceRole) -> [UUID] {
        let defaults = UserDefaults.standard
        if let list = defaults.stringArray(forKey: key(role)) { return list.compactMap(UUID.init(uuidString:)) }
        // Migrate the single-device key from earlier builds.
        if let old = defaults.string(forKey: "device.\(role.rawValue)"), let id = UUID(uuidString: old) {
            set([id], for: role)
            defaults.removeObject(forKey: "device.\(role.rawValue)")
            return [id]
        }
        return []
    }

    static func set(_ ids: [UUID], for role: DeviceRole) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key(role))
    }

    static func role(of id: UUID) -> DeviceRole? {
        DeviceRole.allCases.first { ids(for: $0).contains(id) }
    }
}

/// Device-layer view of the user's preferences.
@MainActor
enum AppSettings {
    static var trainerProtocol: TrainerProtocolPreference {
        get { Preferences.shared.trainerProtocol }
        set { Preferences.shared.trainerProtocol = newValue }
    }
    static var riderKg: Double { Preferences.shared.riderKg }
    static var basicTrainer: TrainerPowerCurve? { Preferences.shared.basicTrainer }
    static var powerSource: PowerSource { Preferences.shared.powerSource }
    static var wheelCircumferenceM: Double { Double(Preferences.shared.wheelCircumferenceMM) / 1000 }
    static func calibrated() { Preferences.shared.lastCalibration = .now }
    static var bikeKg: Double { Preferences.shared.bikeKg }
    static var hapticsOnShift: Bool {
        get { Preferences.shared.hapticsOnShift }
        set { Preferences.shared.hapticsOnShift = newValue }
    }
    static var buttonMap: ButtonMap { Preferences.shared.buttonMap }
    static var demoMode: Bool {
        get { Preferences.shared.demoMode }
        set { Preferences.shared.demoMode = newValue }
    }
}
