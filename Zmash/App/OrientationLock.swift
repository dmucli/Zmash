import UIKit

/// Which way the app may turn (D130). On an iPhone, a ride on any face but Classic is landscape: the faces are drawn
/// on their side. Everywhere else, and on the iPad, the app turns freely.
@MainActor
enum OrientationLock {
    /// What `AppDelegate` hands UIKit.
    private(set) static var mask: UIInterfaceOrientationMask = .all

    /// Locks an iPhone to landscape (and turns it there), or lets it turn freely again without forcing it back.
    static func landscape(_ on: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let wanted: UIInterfaceOrientationMask = on ? .landscape : .all
        guard wanted != mask else { return }
        mask = wanted
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            guard on else { continue }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                Task { @MainActor in Diagnostics.log("ride", "couldn't turn to landscape: \(error.localizedDescription)") }
            }
        }
    }
}

/// Only here to tell UIKit which orientations are allowed right now.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }
}
