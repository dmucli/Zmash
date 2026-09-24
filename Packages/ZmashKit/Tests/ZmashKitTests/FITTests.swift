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

    /// Data messages as (global message, field number → value), for fields up to 4 bytes (all ours).
    func messages(_ f: [UInt8]) -> [(global: UInt16, fields: [UInt8: UInt64])] {
        var i = Int(f[0])
        let end = i + (Int(f[4]) | Int(f[5]) << 8 | Int(f[6]) << 16 | Int(f[7]) << 24)
        var defs: [UInt8: (global: UInt16, fields: [(UInt8, Int)])] = [:]
        var out: [(UInt16, [UInt8: UInt64])] = []
        while i < end {
            let header = f[i]
            i += 1
            let local = header & 0x0F
            if header & 0x40 != 0 {
                let global = UInt16(f[i + 2]) | UInt16(f[i + 3]) << 8
                let count = Int(f[i + 4])
                i += 5
                defs[local] = (global, (0..<count).map { k in (f[i + 3 * k], Int(f[i + 3 * k + 1])) })
                i += 3 * count
            } else if let def = defs[local] {
                var values: [UInt8: UInt64] = [:]
                for (number, size) in def.fields {
                    values[number] = (0..<size).reduce(UInt64(0)) { $0 | UInt64(f[i + $1]) << (8 * UInt64($1)) }
                    i += size
                }
                out.append((def.global, values))
            }
        }
        return out
    }

    @Test func pausesKeepTheWallClock() {
        // 10 min, a 5-min pause, 10 min more; the ride ends 30 s after the last second.
        let samples = (0..<1200).map { t in
            RideSample(t: t, powerW: 200, cadenceRpm: 90, speedKph: 30, gradePercent: 0, gear: 12,
                       pausedBefore: t == 600 ? 300 : nil)
        }
        let summary = SessionSummary(activeSeconds: 1200, distanceM: 10_000, elevationGainM: 0, kcal: 240,
                                     avgPowerW: 200, maxPowerW: 200, avgCadenceRpm: 90, avgSpeedKph: 30)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let f = Array(FITWriter.encode(startedAt: started, samples: samples, summary: summary,
                                       endedAt: started.addingTimeInterval(1200 + 300 + 30)))
        let all = messages(f)
        let start = UInt64(FITWriter.fitTime(started))
        let records = all.filter { $0.global == 20 }
        #expect(records.count == 1200)
        #expect(records[599].fields[253] == start + 599)
        #expect(records[600].fields[253] == start + 900)   // resumed after the 5 minutes
        #expect(records[1199].fields[253] == start + 1499)
        // The timer: started, stopped at the pause, started again.
        let timer = all.filter { $0.global == 21 }.map { ($0.fields[253]!, $0.fields[1]!) }
        #expect(timer.map(\.0) == [start, start + 600, start + 900])
        #expect(timer.map(\.1) == [0, 4, 0])
        // Elapsed runs to the real end; the timer counts only the riding.
        let session = all.first { $0.global == 18 }!
        #expect(session.fields[7] == 1_530_000)
        #expect(session.fields[8] == 1_200_000)
    }

    @Test func noPausesNoChange() {
        let t = RideTimeline(samples: (0..<10).map { RideSample(t: $0, powerW: 0, cadenceRpm: 0, speedKph: 0, gradePercent: 0, gear: 1) })
        #expect(t.pauses.isEmpty)
        #expect(t.wall(active: 9) == 9)
    }

    @Test func fitEpoch() {
        #expect(FITWriter.fitTime(Date(timeIntervalSince1970: 631_065_600)) == 0)
    }
}
