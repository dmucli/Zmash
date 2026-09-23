import SwiftUI
import WatchKit

/// The ride on the wrist: power large, heart rate, time, gear and grade. Tap to pause; turn the crown to shift.
struct RideWatchView: View {
    let manager: WorkoutManager
    @State private var crown = 0.0
    @State private var lastStep = 0

    var body: some View {
        if let ride = manager.ride {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title).brandLabel(10).foregroundStyle(Brand.bone2).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(ride.powerW)").font(Brand.bib(58)).foregroundStyle(Brand.vermilion)
                    Text("W").font(Brand.sans(14)).foregroundStyle(Brand.stone)
                }
                HStack {
                    Label("\(manager.heartRate.map(String.init) ?? "–")", systemImage: "heart.fill")
                        .font(Brand.bib(22))
                    Spacer()
                    Text(clock(ride.elapsed)).font(Brand.mono(17))
                }
                .foregroundStyle(Brand.bone)
                HStack {
                    Text("Gear \(ride.gear)")
                    Spacer()
                    Text(String(format: "%+.1f %%", ride.gradePercent))
                }
                .brandLabel(10).foregroundStyle(Brand.bone2)
                if ride.paused {
                    Text("Paused · tap to resume").brandLabel(10).foregroundStyle(Brand.caution)
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                WKInterfaceDevice.current().play(.click)
                manager.send(command: "pauseToggle")
            }
            .focusable()
            .digitalCrownRotation($crown, from: -1000, through: 1000, by: 1, sensitivity: .low,
                                  isContinuous: true, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in
                // One gear per notch of the crown, harder clockwise.
                let step = Int(value.rounded())
                guard step != lastStep else { return }
                manager.send(command: step > lastStep ? "shiftUp" : "shiftDown")
                lastStep = step
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to pause or resume. Turn the crown to shift.")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "bicycle").font(.system(size: 34))
                Text(manager.active ? "Waiting for the ride…" : "Start a ride on your iPhone")
                    .multilineTextAlignment(.center).font(Brand.sans(14)).foregroundStyle(Brand.bone2)
            }
        }
    }

    private func clock(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
