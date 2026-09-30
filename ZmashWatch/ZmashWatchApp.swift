import HealthKit
import SwiftUI
import WatchKit

/// Zmash on the Watch (D105): opened by the iPhone when a ride starts; sends heart rate, shows the ride,
/// tap to pause, turn the crown to shift.
@main
struct ZmashWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RideWatchView(manager: WorkoutManager.shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// The iPhone started a ride (HKHealthStore.startWatchApp).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WorkoutManager.shared.start(workoutConfiguration) }
    }
}
