import Testing
@testable import ZmashKit

@Suite struct WahooTrainerTests {
    @Test func unlock() {
        #expect(WahooTrainer.unlock == [0x20, 0xEE, 0xFC])
    }

    @Test func erg() {
        // 250 W = 0x00FA, little-endian.
        #expect(WahooTrainer.erg(watts: 250) == [0x42, 0xFA, 0x00])
        #expect(WahooTrainer.erg(watts: -5) == [0x42, 0x00, 0x00])
    }

    @Test func simMode() {
        // 84 kg → 8400 = 0x20D0; Crr 0.004 → 40 = 0x28; 0.51 kg/m → 510 = 0x01FE.
        #expect(WahooTrainer.simMode(totalKg: 84) == [0x43, 0xD0, 0x20, 0x28, 0x00, 0xFE, 0x01])
    }

    @Test func grade() {
        // Flat sits at the middle of the range; ±100 % at the ends.
        #expect(WahooTrainer.grade(percent: 0) == [0x46, 0xFF, 0x7F])
        #expect(WahooTrainer.grade(percent: 100) == [0x46, 0xFF, 0xFF])
        #expect(WahooTrainer.grade(percent: -100) == [0x46, 0x00, 0x00])
        // 5 %: (0.05 + 1) × 65535 / 2 = 34405.875 → 34405 = 0x8665.
        #expect(WahooTrainer.grade(percent: 5) == [0x46, 0x65, 0x86])
        // Clamped beyond ±100 %.
        #expect(WahooTrainer.grade(percent: 250) == WahooTrainer.grade(percent: 100))
    }

    @Test func windSpeed() {
        // Still air: 32.768 × 1000 = 32768 = 0x8000.
        #expect(WahooTrainer.windSpeed(metresPerSecond: 0) == [0x47, 0x00, 0x80])
    }

    @Test func responses() {
        #expect(WahooTrainer.isSuccess([0x01, 0x42, 0x01], for: .setErgMode) == true)
        #expect(WahooTrainer.isSuccess([0x01, 0x42, 0x02], for: .setErgMode) == false)
        #expect(WahooTrainer.isSuccess([0x01, 0x46, 0x01], for: .setErgMode) == nil)
    }
}

@Suite struct TacxFECTests {
    /// An ANT broadcast carrying `page`, with its checksum.
    private func broadcast(_ page: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [0xA4, 0x09, 0x4E, 0x05] + page
        return body + [body.reduce(0, ^)]
    }

    @Test func framingAndChecksum() {
        let m = TacxFEC.targetPower(watts: 200)
        #expect(m.count == 13)
        #expect(Array(m[0..<4]) == [0xA4, 0x09, 0x4F, 0x05])
        #expect(m[12] == m[0..<12].reduce(0, ^))
    }

    @Test func targetPower() {
        // 200 W in 0.25 W steps = 800 = 0x0320.
        #expect(Array(TacxFEC.targetPower(watts: 200)[4..<12]) == [0x31, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x20, 0x03])
    }

    @Test func trackResistance() {
        // 5 %: (5 + 200) / 0.01 = 20500 = 0x5014; Crr 0.004 / 0.00005 = 80 = 0x50.
        #expect(Array(TacxFEC.trackResistance(gradePercent: 5)[4..<12]) == [0x33, 0xFF, 0xFF, 0xFF, 0xFF, 0x14, 0x50, 0x50])
        // −3.5 %: 19650 = 0x4CC2.
        #expect(Array(TacxFEC.trackResistance(gradePercent: -3.5)[9..<11]) == [0xC2, 0x4C])
    }

    @Test func windResistance() {
        #expect(Array(TacxFEC.windResistance()[4..<12]) == [0x32, 0xFF, 0xFF, 0xFF, 0xFF, 51, 127, 100])
    }

    @Test func userConfiguration() {
        // 75 kg → 7500 = 0x1D4C; 9 kg / 0.05 = 180 = 0x0B4 → nibble 4 in byte 4, 0x0B in byte 5; 0.70 m → 70.
        #expect(Array(TacxFEC.userConfiguration(riderKg: 75, bikeKg: 9)[4..<12]) == [0x37, 0x4C, 0x1D, 0xFF, 0x4F, 0x0B, 70, 0x00])
    }

    @Test func trainerDataPage() throws {
        // Cadence 90, instantaneous power 0x12C = 300 W (low byte 0x2C, high nibble 0x1 with status bits above).
        let (page, r) = try #require(TacxFEC.parse(broadcast([0x19, 0x07, 90, 0x00, 0x00, 0x2C, 0x31, 0x20])))
        #expect(page == 0x19)
        #expect(r.cadenceRpm == 90)
        #expect(r.powerW == 300)
    }

    @Test func generalPage() throws {
        // Speed 8333 × 0.001 m/s = 8.333 m/s = 30 km/h; heart rate 142.
        let (_, r) = try #require(TacxFEC.parse(broadcast([0x10, 0x19, 0x00, 0x00, 0x8D, 0x20, 142, 0x00])))
        #expect(abs(r.speedKph! - 30) < 0.01)
        #expect(r.heartRateBpm == 142)
    }

    @Test func rejectsBadChecksumAndOtherMessages() {
        var m = broadcast([0x19, 0, 90, 0, 0, 0x2C, 0x01, 0])
        m[12] ^= 0xFF
        #expect(TacxFEC.parse(m) == nil)
        #expect(TacxFEC.parse([0xA4, 0x03, 0x40, 0x05, 0x01, 0x00, 0xE3]) == nil)
    }
}

@Suite struct TrainerProtocolChoiceTests {
    @Test func ordersByProtocol() {
        typealias O = TrainerProtocolChoice.Offered
        #expect(TrainerProtocolChoice.choose(O(ftms: true, zwift: true, wahoo: true, tacx: true), preference: .ftms) == .ftms)
        #expect(TrainerProtocolChoice.choose(O(zwift: true, wahoo: true), preference: .ftms) == .zwift)
        #expect(TrainerProtocolChoice.choose(O(wahoo: true, tacx: true), preference: .ftms) == .wahoo)
        #expect(TrainerProtocolChoice.choose(O(tacx: true), preference: .ftms) == .tacx)
        #expect(TrainerProtocolChoice.choose(O(), preference: .auto) == nil)
    }

    @Test func preferenceWinsWhenOffered() {
        typealias O = TrainerProtocolChoice.Offered
        #expect(TrainerProtocolChoice.choose(O(ftms: true, tacx: true), preference: .tacx) == .tacx)
        #expect(TrainerProtocolChoice.choose(O(ftms: true, wahoo: true), preference: .wahoo) == .wahoo)
        // A preference the trainer can't honour falls back to the order.
        #expect(TrainerProtocolChoice.choose(O(ftms: true), preference: .wahoo) == .ftms)
    }
}

@Suite struct CalibrationCodecTests {
    @Test func ftmsSpinDown() {
        #expect(FTMS.ControlCommand.startSpinDown == [0x13, 0x01])
        // Success, target speeds 30.00 and 35.00 km/h.
        let t = FTMS.spinDownTargets([0x80, 0x13, 0x01, 0xB8, 0x0B, 0xAC, 0x0D])
        #expect(t?.lowKph == 30 && t?.highKph == 35)
        #expect(FTMS.spinDownTargets([0x80, 0x13, 0x04]) == nil)
        #expect(FTMS.spinDownStatus([0x14, 0x04]) == .stopPedalling)
        #expect(FTMS.spinDownStatus([0x14, 0x02]) == .success)
        #expect(FTMS.spinDownStatus([0x12, 0x02]) == nil)
    }

    private func broadcast(_ page: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [0xA4, 0x09, 0x4E, 0x05] + page
        return body + [body.reduce(0, ^)]
    }

    @Test func tacxSpinDown() throws {
        #expect(Array(TacxFEC.spinDownRequest[4..<12]) == [0x01, 0x80, 0, 0, 0, 0, 0, 0])
        // In progress: speed OK (condition 2 in bits 6-7), target 9.722 m/s = 35 km/h.
        let (_, p) = try #require(TacxFEC.parse(broadcast([0x02, 0x80, 0x80, 0x5A, 0xFA, 0x25, 0xFF, 0xFF])))
        guard case .inProgress(let kph, let ok) = p.calibration else { Issue.record("no progress"); return }
        #expect(abs(kph! - 35) < 0.01)
        #expect(ok == true)
        let (_, r) = try #require(TacxFEC.parse(broadcast([0x01, 0x80, 0x5A, 0xFF, 0xFF, 0xD0, 0x07, 0xFF])))
        #expect(r.calibration == .result(success: true, spinDownMs: 2000))
    }
}
