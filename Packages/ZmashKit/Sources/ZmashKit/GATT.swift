/// Service and characteristic UUIDs, as strings so this module stays free of CoreBluetooth.
/// Short (16-bit) SIG UUIDs are upper-case, matching `CBUUID.uuidString`.
public enum GATT {
    public enum Service {
        /// Zwift custom service, 16-bit form (Ride firmware ≥ Jan 2025, Zwift trainers).
        public static let zwift = "FC82"
        /// Zwift custom service, legacy 128-bit form.
        public static let zwiftLegacy = "00000001-19CA-4651-86E5-FA29DCDD09D1"
        public static let fitnessMachine = "1826"
        public static let cyclingPower = "1818"
        public static let deviceInformation = "180A"
        public static let battery = "180F"
    }

    public enum Characteristic {
        public static let zwiftAsync = "00000002-19CA-4651-86E5-FA29DCDD09D1"   // notify
        public static let zwiftSyncRx = "00000003-19CA-4651-86E5-FA29DCDD09D1"  // write w/o response
        public static let zwiftSyncTx = "00000004-19CA-4651-86E5-FA29DCDD09D1"  // indicate

        public static let fitnessMachineFeature = "2ACC"
        public static let indoorBikeData = "2AD2"
        public static let supportedInclinationRange = "2AD5"
        public static let fitnessMachineControlPoint = "2AD9"
        public static let fitnessMachineStatus = "2ADA"
        public static let cyclingPowerMeasurement = "2A63"

        public static let batteryLevel = "2A19"
        public static let modelNumber = "2A24"
        public static let serialNumber = "2A25"
        public static let firmwareRevision = "2A26"
        public static let hardwareRevision = "2A27"
        public static let softwareRevision = "2A28"
        public static let manufacturerName = "2A29"

        /// DIS characteristics whose value is a UTF-8 string.
        public static let stringValued: Set<String> = [
            modelNumber, serialNumber, firmwareRevision, hardwareRevision, softwareRevision, manufacturerName,
        ]
    }

    public static func name(of uuid: String) -> String? {
        switch uuid.uppercased() {
        case Service.zwift, Service.zwiftLegacy: "Zwift"
        case Service.fitnessMachine: "Fitness Machine"
        case Service.cyclingPower: "Cycling Power"
        case Service.deviceInformation: "Device Information"
        case Service.battery: "Battery"
        case Characteristic.zwiftAsync: "Zwift async"
        case Characteristic.zwiftSyncRx: "Zwift sync RX"
        case Characteristic.zwiftSyncTx: "Zwift sync TX"
        case Characteristic.fitnessMachineFeature: "FM Feature"
        case Characteristic.indoorBikeData: "Indoor Bike Data"
        case Characteristic.supportedInclinationRange: "Inclination Range"
        case Characteristic.fitnessMachineControlPoint: "FM Control Point"
        case Characteristic.fitnessMachineStatus: "FM Status"
        case Characteristic.cyclingPowerMeasurement: "CP Measurement"
        case Characteristic.batteryLevel: "Battery Level"
        case Characteristic.modelNumber: "Model"
        case Characteristic.serialNumber: "Serial"
        case Characteristic.firmwareRevision: "Firmware"
        case Characteristic.hardwareRevision: "Hardware"
        case Characteristic.softwareRevision: "Software"
        case Characteristic.manufacturerName: "Manufacturer"
        default: nil
        }
    }
}
