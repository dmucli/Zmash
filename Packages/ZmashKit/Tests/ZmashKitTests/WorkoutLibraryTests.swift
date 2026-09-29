import Testing
@testable import ZmashKit

/// Zmash's own library (D167): the first 19 as they were, then families covering every kind at the lengths people
/// ride, each workout readable and in the app's voice.
@Suite struct WorkoutLibraryTests {
    private let classics = ["recovery-30", "endurance-45", "endurance-90", "tempo-3x10", "tempo-2x20", "sweetspot-3x15",
                            "sweetspot-2x20", "threshold-4x8", "threshold-3x12", "threshold-2x15", "hills-6x3", "over-under-3x9",
                            "vo2-4x4", "vo2-5x3", "vo2-30-30", "vo2-40-20", "anaerobic-6x1", "sprints-8x20", "sprints-10x10",
                            "ramp-test"]

    @Test func theFirstOnesStayAsTheyWere() {
        // Plans and saved rides refer to them by id.
        #expect(WorkoutLibrary.all.prefix(classics.count).map(\.id) == classics)
    }

    @Test func idsAndNamesAreUnique() {
        let all = WorkoutLibrary.all
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map { $0.name.lowercased() }).count == all.count)
        #expect(WorkoutLibrary.families.count >= 70)
    }

    @Test func everyKindAtEveryLength() {
        for kind in Workout.Category.allCases where kind != .tests {
            for length in [WorkoutLength.m30, .m45, .h1, .h90] {
                let n = WorkoutLibrary.all.filter { $0.category == kind && length.contains(seconds: $0.duration) }.count
                #expect(n >= 1, "\(kind.title) at \(length.title)")
            }
        }
        #expect(WorkoutLibrary.all.filter { $0.category == .tests }.count >= 2)
    }

    @Test func eachReadsWell() {
        for w in WorkoutLibrary.families {
            #expect(w.category != nil, "\(w.id)")
            #expect(!w.summary.isEmpty && !w.summary.contains("!"), "\(w.id)")
            #expect(w.duration >= 25 * 60 && w.duration <= 125 * 60, "\(w.id): \(w.duration / 60) min")
            // A few lines in the details, not a wall of steps.
            #expect(WorkoutOutline.lines(w, ftp: 250).count <= 9, "\(w.id): \(WorkoutOutline.lines(w, ftp: 250))")
            // One number per label at most ("Sweet spot 2/4", never "Sweet spot 1/5 1/2").
            #expect(w.steps.allSatisfy { $0.label.filter { $0 == "/" }.count <= 1 || $0.label.hasPrefix("30/") || $0.label.hasPrefix("40/") }, "\(w.id)")
        }
    }
}
