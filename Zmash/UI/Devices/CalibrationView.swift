import SwiftUI
import ZmashKit

/// Spin-down calibration, one step at a time, with the trainer's speed live (D99).
struct CalibrationView: View {
    let trainer: KickrTrainerClient
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Design.Palette.primary)
                Text(explanation).font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsSpeed {
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Fact(value: String(format: "%.1f", prefs.units.speed(trainer.metrics?.trainerSpeedKph ?? 0)),
                             label: prefs.units.speedUnit + " now")
                        if case .speedUp(let target?) = trainer.calibration {
                            Fact(value: String(format: "%.0f", prefs.units.speed(target)), label: prefs.units.speedUnit + " to reach")
                        }
                    }
                }

                Spacer(minLength: 0)
                switch trainer.calibration {
                case .idle, .failed:
                    PrimaryButton(title: trainer.calibration == .idle ? "Start" : "Try again") { trainer.startCalibration() }
                case .success, .unsupported:
                    PrimaryButton(title: "Done") { dismiss() }
                default:
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Design.Palette.background)
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
        .onDisappear { trainer.resetCalibration() }
    }

    private var showsSpeed: Bool {
        switch trainer.calibration {
        case .speedUp, .coast: true
        default: false
        }
    }

    private var title: String {
        switch trainer.calibration {
        case .idle: "Calibrate the trainer"
        case .starting: "Asking the trainer…"
        case .speedUp: "Speed up"
        case .coast: "Stop pedalling"
        case .success: "Calibrated"
        case .failed: "That didn't work"
        case .unsupported: "Not needed here"
        }
    }

    private var explanation: String {
        switch trainer.calibration {
        case .idle: "A spin-down measures the trainer's own friction, so its power stays accurate. Ride ten minutes first so it's warm. Then speed up when asked, and stop pedalling when told, letting the wheel coast to a stop."
        case .starting: "Keep pedalling gently."
        case .speedUp(let target): target.map { String(format: "Pedal up to %.0f %@, then hold it until told to stop.", prefs.units.speed($0), prefs.units.speedUnit) }
            ?? "Pedal up to about 35 km/h and hold it until told to stop."
        case .coast: "Stop pedalling and let the flywheel coast to a stop. Don't touch the pedals."
        case .success(let detail): detail + " Next time: in a month, or if power looks off."
        case .failed(let reason): reason
        case .unsupported(let reason): reason
        }
    }
}
