import CoreBluetooth
import Foundation
import Observation
import ZmashKit

enum DeviceKind: String {
    case rideLeft = "Zwift Ride (left)"
    case rideRight = "Zwift Ride (right)"
    case zwift = "Zwift device"
    case trainer = "Trainer"
    case other = "Other"

    var isRide: Bool { self == .rideLeft || self == .rideRight }

    static func classify(name: String?, services: [String], manufacturerData: [UInt8]) -> DeviceKind {
        let company = manufacturerData.count >= 2 ? UInt16(manufacturerData[0]) | UInt16(manufacturerData[1]) << 8 : nil
        if company == ZwiftRide.manufacturerID, manufacturerData.count >= 3 {
            switch ZwiftRide.DeviceType(rawValue: manufacturerData[2]) {
            case .rideLeft: return .rideLeft
            case .rideRight: return .rideRight
            case nil: break
            }
        }
        if services.contains(GATT.Service.fitnessMachine) || services.contains(GATT.Service.cyclingPower)
            || (name ?? "").localizedCaseInsensitiveContains("kickr") {
            return .trainer
        }
        if company == ZwiftRide.manufacturerID
            || services.contains(GATT.Service.zwift) || services.contains(GATT.Service.zwiftLegacy) {
            return .zwift
        }
        return .other
    }
}

@MainActor @Observable
final class DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var kind: DeviceKind
    var services: [String]
    var manufacturerData: [UInt8]
    var lastSeen = Date()

    init(peripheral: CBPeripheral, name: String, rssi: Int, kind: DeviceKind, services: [String], manufacturerData: [UInt8]) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = name
        self.rssi = rssi
        self.kind = kind
        self.services = services
        self.manufacturerData = manufacturerData
    }
}

@MainActor @Observable
final class ConnectedDevice: Identifiable {
    enum ConnectionState: Equatable {
        case connecting
        case connected
        case disconnected(String?)
    }

    struct CharacteristicInfo: Identifiable {
        var id: String { uuid }
        let uuid: String
        let serviceUUID: String
        let properties: CBCharacteristicProperties
        var notifying = false
        var lastValue: [UInt8] = []
        var updates = 0
    }

    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let kind: DeviceKind
    var state: ConnectionState = .connecting
    var characteristics: [String: CBCharacteristic] = [:]
    var info: [CharacteristicInfo] = []
    var deviceInformation: [String: String] = [:]
    var batteryPercent: Int?

    // Zwift Ride
    var rideHandshakeSent = false
    var rideOnAcknowledged = false
    var pressed: ZwiftRide.Buttons = []
    var seenButtons: ZwiftRide.Buttons = []
    var paddles: [Int: Int] = [:]
    var seenPaddles: Set<Int> = []
    var lastButtonEvent = ""
    var keypadFrames = 0
    var edges = ButtonEdgeDetector()

    // FTMS
    var features: FTMS.Features?
    var inclinationRange: (min: Double, max: Double, step: Double)?
    var bikeData: FTMS.IndoorBikeData?
    var bikeDataFrames = 0
    var controlGranted: Bool?
    var lastControlResponse = ""
    var lastStatus = ""
    var gradeAcknowledged: Double?
    var pendingGrade: Double?

    // Cycling Power (fallback)
    var cyclingPowerW: Int?
    var cyclingCadence: Double?
    var crankCadence = CrankCadence()

    // Zwift trainer protocol
    var zwiftTrainerHandshakeSent = false
    var zwiftTrainerAck = false
    var zwiftRidingData: ZwiftTrainer.RidingData?
    var zwiftRidingFrames = 0
    var zwiftConfigWrites = 0

    init(peripheral: CBPeripheral, name: String, kind: DeviceKind) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = name
        self.kind = kind
    }

    var hasFTMS: Bool { characteristics[GATT.Characteristic.fitnessMachineControlPoint] != nil }
    var hasCyclingPower: Bool { characteristics[GATT.Characteristic.cyclingPowerMeasurement] != nil }
    var hasZwiftService: Bool { characteristics[GATT.Characteristic.zwiftSyncRx] != nil }
    var isTrainer: Bool { kind == .trainer || hasFTMS || hasCyclingPower }
    var isRide: Bool { kind.isRide || (kind == .zwift && !isTrainer) }
    var firmware: String? { deviceInformation[GATT.Characteristic.firmwareRevision] }
}
