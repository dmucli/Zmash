import Foundation
import HealthKit
import UIKit
import ZmashKit

/// The Apple Watch during a ride, on iPhone (D105): starts the watch app with the ride, takes heart rate and commands
/// from it over the mirrored workout session, and sends it the ride's numbers.
@MainActor @Observable
final class WatchLink: NSObject {
    static let shared = WatchLink()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    private(set) var latest: (bpm: Int, at: Date)?
    /// Commands from the watch (pause, shifts), into the device hub.
    @ObservationIgnored var onCommand: ((RideCommand) -> Void)?

    /// Only on an iPhone, with Health, and when turned on in Devices.
    static var available: Bool {
        HKHealthStore.isHealthDataAvailable() && UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Heart rate from the watch, nil after 5 s without one.
    var bpm: Int? {
        guard let latest, Date.now.timeIntervalSince(latest.at) < 5 else { return nil }
        return latest.bpm
    }

    /// Called at launch: the watch's session arrives here once it starts mirroring.
    func setUp() {
        guard Self.available else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in self?.attach(mirrored) }
        }
    }

    private func attach(_ s: HKWorkoutSession) {
        session = s
        s.delegate = self
        Diagnostics.log("watch", "mirrored workout session started")
    }

    /// A ride started: open the watch app on an indoor-cycling workout.
    func rideStarted() {
        guard Self.available, Preferences.shared.useWatch else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor
        store.startWatchApp(with: config) { ok, error in
            if !ok { Task { @MainActor in Diagnostics.log("watch", "couldn't start the watch app: \(error?.localizedDescription ?? "-")") } }
        }
    }

    func send(_ ride: WatchMessage.Ride) {
        send(WatchMessage(kind: .ride, ride: ride))
    }

    /// The ride ended. The watch keeps its own workout only when the iPhone isn't saving one to Health (no doubles).
    func rideEnded(savedToHealth: Bool) {
        send(WatchMessage(kind: .end, keepWorkout: !savedToHealth))
        latest = nil
    }

    private func send(_ message: WatchMessage) {
        guard let session else { return }
        let data = message.data
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    fileprivate func received(_ message: WatchMessage) {
        switch message.kind {
        case .heartRate:
            if let bpm = message.heartRateBpm, bpm > 0 { latest = (bpm, .now) }
        case .command:
            if let raw = message.command, let command = RideCommand(rawValue: raw) { onCommand?(command) }
        case .ride, .end:
            break
        }
    }

    fileprivate func ended() {
        session = nil
        latest = nil
    }
}

extension WatchLink: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.ended() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in Diagnostics.log("watch", "session failed: \(error.localizedDescription)") }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(WatchMessage.decode)
        Task { @MainActor in messages.forEach { self.received($0) } }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.ended() }
    }
}
