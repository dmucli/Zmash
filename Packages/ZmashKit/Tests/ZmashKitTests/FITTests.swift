import Foundation
import Testing
@testable import ZmashKit

@Suite struct FITTests {
    @Test func crcMatchesCRC16ARC() {
        #expect(FITWriter.crc16(Array("123456789".utf8)) == 0xBB3D)
    }

    func sampleFile(seconds: Int = 120) -> [UInt8] {
        let samples = (0..<seconds).map {
            RideSample(t: $0, powerW: 200, cadenceRpm: 90, speedKph: 30, gradePercent: 1, gear: 12)
        }
        let summary = SessionSummary(activeSeconds: seconds, distanceM: 1000, elevationGainM: 10, kcal: 24,
                                     avgPowerW: 200, maxPowerW: 200, avgCadenceRpm: 90, avgSpeedKph: 30)
        return Array(FITWriter.encode(startedAt: Date(timeIntervalSince1970: 1_790_000_000), samples: samples, summary: summary))
    }

    @Test func headerAndSizes() {
        let f = sampleFile()
        #expect(f[0] == 14)
        #expect(Array(f[8..<12]) == Array(".FIT".utf8))
        let dataSize = Int(f[4]) | Int(f[5]) << 8 | Int(f[6]) << 16 | Int(f[7]) << 24
        #expect(f.count == 14 + dataSize + 2)
        // Header CRC covers the first 12 bytes.
        #expect(FITWriter.crc16(Array(f[0..<12])) == UInt16(f[12]) | UInt16(f[13]) << 8)
    }

    @Test func fileCRCValidates() {
        // CRC-16/ARC of a message followed by its own little-endian CRC is zero.
        #expect(FITWriter.crc16(sampleFile()) == 0)
    }

    @Test func recordsAreDefinedOnceAndRepeat() {
        let f = sampleFile(seconds: 10)
        // Record definition (local 2, global 20): 0x42, reserved, arch, 20, 0.
        let def: [UInt8] = [0x42, 0, 0, 20, 0]
        let defs = (0...(f.count - def.count)).filter { Array(f[$0..<$0 + def.count]) == def }
        #expect(defs.count == 1)
    }

    @Test func fitEpoch() {
        #expect(FITWriter.fitTime(Date(timeIntervalSince1970: 631_065_600)) == 0)
    }
}
