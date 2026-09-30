import Foundation
import HealthKit
import WatchKit

/// The watch's side of a ride: an indoor-cycling workout session mirrored to the iPhone, heart rate out,
/// the ride's numbers in.
@MainActor @Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    private(set) var ride: WatchMessage.Ride?
    private(set) var heartRate: Int?
    private(set) var active = false
    /// When the iPhone last said anything: with no word for a few minutes, the ride is over (its "end" got lost).
    @ObservationIgnored private var lastHeard = Date.now
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    static let orphanAfter: TimeInterval = 180

    func start(_ config: HKWorkoutConfiguration) async {
        // A workout still running from a ride whose end never arrived: close it (kept) and start afresh.
        if session != nil { await end(keep: true) }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date.now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            try await session.startMirroringToCompanionDevice()
            active = true
            lastHeard = .now
            watchdog = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, self.active else { return }
                    if Date.now.timeIntervalSince(self.lastHeard) > Self.orphanAfter { await self.end(keep: true) }
                }
            }
        } catch {
            session = nil
            builder = nil
        }
    }

    /// Tap: pause or resume the ride; crown: shift. Sent to the iPhone, which runs the ride.
    func send(command: String) {
        send(WatchMessage(kind: .command, command: command))
    }

    private func send(_ message: WatchMessage) {
        guard let session else { return }
        let data = message.data
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    fileprivate func received(_ message: WatchMessage) {
        lastHeard = .now
        switch message.kind {
        case .ride: ride = message.ride
        case .end: Task { await end(keep: message.keepWorkout ?? false) }
        default: break
        }
    }

    /// Ends the workout; keeps it in Health only when the iPhone isn't saving the ride itself.
    func end(keep: Bool) async {
        watchdog?.cancel()
        watchdog = nil
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        if keep { _ = try? await builder.finishWorkout() } else { builder.discardWorkout() }
        self.session = nil
        self.builder = nil
        active = false
        ride = nil
        heartRate = nil
    }

    fileprivate func collected(heartRate bpm: Int) {
        heartRate = bpm
        send(WatchMessage(kind: .heartRate, heartRateBpm: bpm))
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(WatchMessage.decode)
        Task { @MainActor in messages.forEach { self.received($0) } }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let value = workoutBuilder.statistics(for: hr)?.mostRecentQuantity()?
                  .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        let bpm = Int(value.rounded())
        Task { @MainActor in self.collected(heartRate: bpm) }
    }
}
