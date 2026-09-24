import Foundation
import Testing
@testable import ZmashKit

@Suite struct ZonesTests {
    private func ride(watts: [Int], hr: [Int?]? = nil) -> [RideSample] {
        watts.enumerated().map { i, w in
            RideSample(t: i, powerW: w, cadenceRpm: 90, speedKph: 30, gradePercent: 0, gear: 12, heartRateBpm: hr?[i])
        }
    }

    @Test func powerSecondsFallInTheFacesZones() {
        // FTP 200: 100 W is Z1 (< 55 %), 170 W Z3 (85 %), 200 W Z4 (100 %), 400 W Z7.
        let w = Array(repeating: 100, count: 60) + Array(repeating: 170, count: 30) + Array(repeating: 200, count: 20)
            + Array(repeating: 400, count: 10)
        let z = Zones.powerSeconds(ride(watts: w), ftp: 200)
        #expect(z == [60, 0, 30, 20, 0, 0, 10])
        #expect(z.reduce(0, +) == w.count)
    }

    @Test func heartSecondsNeedHeartRate() {
        #expect(Zones.heartSeconds(ride(watts: [200, 200]), maxHR: 190) == nil)
        // Max 200: 110 bpm is Z1, 150 Z3, 185 Z5.
        let hr: [Int?] = [110, 110, 150, nil, 185]
        #expect(Zones.heartSeconds(ride(watts: [200, 200, 200, 200, 200], hr: hr), maxHR: 200) == [2, 0, 1, 0, 1])
    }

    @Test func peakHeartRateIgnoresASpike() {
        var hr: [Int?] = Array(repeating: 170, count: 30)
        hr[10] = 230 // a strap glitch
        hr[20...24] = [181, 182, 183, 182, 181]
        #expect(Zones.peakHeartRate(ride(watts: Array(repeating: 250, count: 30), hr: hr)) == 181)
        #expect(Zones.peakHeartRate(ride(watts: [100, 100])) == nil)
    }
}
