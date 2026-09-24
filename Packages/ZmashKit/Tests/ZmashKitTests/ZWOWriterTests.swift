import Foundation
import Testing
@testable import ZmashKit

@Suite struct ZWOWriterTests {
    private let workout = Workout(id: "w", name: "Over & under <3>", summary: "Hard \"stuff\".", steps: [
        .init(600, .ramp(0.45, 0.75), "Warm-up"),
        .init(300, .steady(1.05), "Over"),
        .init(120, .free, "Spin"),
        .init(300, .ramp(0.6, 0.4), "Cool-down"),
    ])

    @Test func roundTrip() throws {
        let data = ZWOWriter.write(workout)
        let back = try #require(ZWOParser.parse(data, id: "w"))
        #expect(back == workout)
    }

    @Test func cadenceTargetsRoundTrip() throws {
        var w = workout
        w.steps[1].cadence = 85...95
        let back = try #require(ZWOParser.parse(ZWOWriter.write(w), id: "w"))
        #expect(back.steps[1].cadence == 85...95)
        #expect(back.steps[0].cadence == nil)
    }

    @Test func zwiftCadenceAttributes() throws {
        let xml = """
        <workout_file><name>C</name><workout>
          <SteadyState Duration="60" Power="0.9" Cadence="90"/>
          <IntervalsT Repeat="2" OnDuration="30" OffDuration="30" OnPower="1.2" OffPower="0.5" Cadence="100" CadenceResting="85"/>
        </workout></workout_file>
        """
        let w = try #require(ZWOParser.parse(Data(xml.utf8), id: "c"))
        #expect(w.steps[0].cadence == 85...95)
        #expect(w.steps[1].cadence == 95...105)
        #expect(w.steps[2].cadence == 80...90)
    }

    @Test func libraryWorkoutsRoundTrip() throws {
        for w in WorkoutLibrary.all where !w.isRampTest {
            let back = try #require(ZWOParser.parse(ZWOWriter.write(w), id: w.id))
            #expect(back.steps == w.steps, "\(w.id)")
        }
    }

    @Test func repeating() {
        let r = workout.repeating(from: 1, count: 2, times: 3)
        #expect(r.steps.count == 8)
        #expect(r.steps[1...6].map(\.label) == ["Over", "Spin", "Over", "Spin", "Over", "Spin"])
        #expect(workout.repeating(from: 3, count: 2, times: 3) == workout)
    }
}
