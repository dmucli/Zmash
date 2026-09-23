import ActivityKit
import Foundation
import ZmashKit

/// Keeps the ride's Live Activity up to date on iPhone (D103). On iPad, where there are none, it does nothing.
@MainActor
final class RideActivity {
    static let shared = RideActivity()

    /// Only the id is kept: `Activity` isn't Sendable, so it's looked up inside the tasks that talk to it.
    private var activityID: String?
    private var loop: Task<Void, Never>?

    func start(engine: SessionEngine, units: Units) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(engine: nil, units: units)
        let title = engine.route?.name ?? engine.workout?.name ?? "Free ride"
        activityID = (try? Activity.request(attributes: RideActivityAttributes(title: title),
                                            content: .init(state: Self.state(engine, units: units), staleDate: nil)))?.id
        loop = Task { @MainActor [weak self, weak engine] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let engine, let id = self.activityID else { return }
                let content = ActivityContent(state: Self.state(engine, units: units), staleDate: .now.addingTimeInterval(30))
                Task.detached { await Self.find(id)?.update(content) }
            }
        }
    }

    /// Ends it, showing the final numbers for 15 minutes.
    func end(engine: SessionEngine?, units: Units) {
        loop?.cancel()
        loop = nil
        guard let id = activityID else { return }
        activityID = nil
        var final = engine.map { Self.state($0, units: units) }
        final?.finished = true
        let content = final.map { ActivityContent(state: $0, staleDate: nil) }
        Task.detached { await Self.find(id)?.end(content, dismissalPolicy: .after(.now.addingTimeInterval(900))) }
    }

    nonisolated private static func find(_ id: String) -> Activity<RideActivityAttributes>? {
        Activity<RideActivityAttributes>.activities.first { $0.id == id }
    }

    private static func state(_ e: SessionEngine, units: Units) -> RideActivityAttributes.ContentState {
        let toGo: String? = if let left = e.routeRemainingM {
            String(format: "%.1f %@ to go", units.distance(left), units.distanceUnit)
        } else {
            e.remaining.map { "−" + TimeFormat.clock(Int($0.rounded(.up))) }
        }
        let pos = e.workoutPosition
        return .init(powerW: e.powerW ?? 0, clockStart: .now.addingTimeInterval(-e.elapsed), elapsed: Int(e.elapsed),
                     paused: e.isPaused || !e.clockStarted, finished: e.phase == .finished, toGo: toGo,
                     gear: "\(e.controls.gear)/\(e.controls.gears.count)", gradePercent: e.terrainGrade,
                     heartRateBpm: e.heartRateBpm, step: pos.map { $0.step.label.isEmpty ? "Step \($0.index + 1)" : $0.step.label },
                     targetW: e.targetW)
    }
}
