import SwiftUI
import ZmashKit

/// End-of-session modal (brief §12): summary, perceived effort, note, save or discard.
struct SummaryView: View {
    let ride: FinishedRide
    let done: () -> Void

    @Environment(Preferences.self) private var prefs
    @State private var rpe: Int?
    @State private var note = ""
    @State private var confirmDiscard = false

    private var isShort: Bool { ride.summary.activeSeconds < 60 }

    var body: some View {
        ZStack {
            Design.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.block) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.startedAt.formatted(date: .complete, time: .shortened))
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        Text(TimeFormat.clock(ride.summary.activeSeconds))
                            .font(Design.Font.number(64)).foregroundStyle(Design.Palette.primary)
                    }

                    SummaryGrid(summary: ride.summary, units: prefs.units)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Effort").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        RPEPicker(value: $rpe)
                    }

                    TextField("Note", text: $note)
                        .font(Design.Font.label)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))

                    VStack(spacing: 10) {
                        if isShort {
                            PrimaryButton(title: "Discard") { discard() }
                            Button("Save anyway") { save() }.buttonStyle(.plain)
                                .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            PrimaryButton(title: "Save") { save() }
                            Button("Discard") { confirmDiscard = true }.buttonStyle(.plain)
                                .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .padding(Design.Space.gutter * 1.5)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Discard this ride?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { discard() }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        RideStore.save(ride, rpe: rpe, note: note)
        if prefs.saveToHealth {
            let ride = ride
            Task { try? await HealthExport.save(ride) }
        }
        done()
    }

    private func discard() {
        RideStore.discard(id: ride.id)
        done()
    }
}

struct SummaryGrid: View {
    let summary: SessionSummary
    let units: Units

    private var items: [(String, String)] {
        var items: [(String, String)] = [
            (String(format: "%.1f", units.distance(summary.distanceM)), units.distanceUnit),
            (String(format: "%.1f", units.speed(summary.avgSpeedKph)), "avg " + units.speedUnit),
            ("\(summary.avgPowerW)", "avg w"),
            ("\(summary.maxPowerW)", "max w"),
            ("\(summary.avgCadenceRpm)", "avg rpm"),
            (String(format: "%.0f", summary.kcal), "kcal"),
            (String(format: "%.0f", units.elevation(summary.elevationGainM)), units.elevationUnit + " climbed"),
        ]
        if let avg = summary.avgHeartRateBpm { items.append(("\(avg)", "avg bpm")) }
        if let max = summary.maxHeartRateBpm { items.append(("\(max)", "max bpm")) }
        return items
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 20, alignment: .leading)],
                  alignment: .leading, spacing: 20) {
            ForEach(items, id: \.1) { value, unit in
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(Design.Font.number(34)).foregroundStyle(Design.Palette.primary)
                    Text(unit).font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
                }
            }
        }
    }
}

/// 1–10 perceived effort as ten segments, labelled only at the ends.
struct RPEPicker: View {
    @Binding var value: Int?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { n in
                    let on = (value ?? 0) >= n
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { value = value == n ? nil : n }
                    } label: {
                        Text("\(n)")
                            .font(Design.Font.number(17, weight: .medium))
                            .foregroundStyle(on ? Design.Palette.background : Design.Palette.secondary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(on ? Design.accent(forGrade: Double(n) - 1).mix(with: Design.Palette.primary, by: 0.35)
                                         : Design.Palette.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effort \(n) of 10")
                }
            }
            HStack {
                Text("easy"); Spacer(); Text("max")
            }
            .font(Design.Font.small)
            .foregroundStyle(Design.Palette.secondary)
        }
    }
}
