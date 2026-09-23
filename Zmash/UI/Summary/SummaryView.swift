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
    @State private var training: TrainingResult?
    @State private var palmares: Palmares.Result?
    @State private var campaign: CampaignStore.Preview?
    @State private var postcard: URL?

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

                    if let training {
                        TrainingPanel(result: training, ftp: prefs.ftp) { prefs.ftp = $0 }
                    }

                    if let campaign {
                        CampaignPanel(preview: campaign)
                    }

                    if let palmares, !palmares.isEmpty {
                        PalmaresPanel(result: palmares)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Effort").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        RPEPicker(value: $rpe)
                    }

                    TextField("Note", text: $note)
                        .font(Design.Font.label)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))

                    UploadRow(ride: ride)

                    if let postcard {
                        ShareLink(item: postcard, preview: SharePreview("Ride", image: postcard)) {
                            HStack(spacing: 10) {
                                Icon("share", size: 18)
                                Text("Share a card").font(Design.Font.label)
                            }
                            .foregroundStyle(Design.Palette.primary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
                        }
                    }

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
        .task {
            training = TrainingResult(ride: ride, ftp: prefs.ftp)
            palmares = Palmares.result(for: ride)
            campaign = CampaignStore.preview(ride)
            postcard = PostcardRenderer.write(
                RidePostcard(startedAt: ride.startedAt, summary: ride.summary, samples: ride.samples,
                             units: prefs.units, title: ride.plan.workout?.name, tss: training?.load.tss),
                name: "Zmash ride")
        }
    }

    private func save() {
        RideSaver.save(ride, rpe: rpe, note: note, prefs: prefs)
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


/// What this ride did for your training: load, new bests and an FTP estimate.
struct TrainingResult {
    var load: Training.Load
    var bests: [(duration: Int, watts: Int)]
    /// An FTP worth adopting (ramp test result, or 95 % of a new best 20 minutes).
    var suggestedFTP: Int?
    var fromRampTest: Bool

    @MainActor
    init(ride: FinishedRide, ftp: Int) {
        let watts = ride.samples.map(\.powerW)
        load = Training.load(watts, ftp: Double(ftp))
        let curve = Training.powerCurve(watts)
        bests = Training.newBests(ride: curve, previous: RideStore.bestCurve(excluding: ride.id))
        fromRampTest = ride.plan.workout?.isRampTest == true
        let estimate = fromRampTest ? Training.rampTestFTP(watts: watts) : Training.estimateFTP(curve: curve)
        // Only offer a change worth making.
        suggestedFTP = estimate.flatMap { abs(Double($0 - ftp)) / Double(ftp) > 0.03 ? $0 : nil }
    }
}

private struct TrainingPanel: View {
    let result: TrainingResult
    let ftp: Int
    let setFTP: (Int) -> Void
    @State private var updated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                stat("\(Int(result.load.tss.rounded()))", "tss")
                stat("\(Int(result.load.normalizedPower.rounded()))", "np")
                stat(String(format: "%.2f", result.load.intensityFactor), "intensity")
            }
            if !result.bests.isEmpty {
                Text(result.bests.prefix(3).map { "\(Training.durationLabel($0.duration)) · \($0.watts) W" }
                        .joined(separator: "   "))
                    .font(Design.Font.small).foregroundStyle(Design.Palette.primary)
                Text(result.bests.count == 1 ? "new best" : "new bests")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
            if let suggested = result.suggestedFTP, !updated {
                Button {
                    setFTP(suggested)
                    updated = true
                } label: {
                    HStack {
                        Text(result.fromRampTest ? "Ramp test FTP \(suggested) W" : "This ride suggests FTP \(suggested) W")
                            .font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                        Spacer()
                        Text("Update").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Design.Palette.background))
                }
                .buttonStyle(.plain)
            } else if updated {
                Text("FTP updated").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Design.Font.number(28)).foregroundStyle(Design.Palette.primary)
            Text(label).font(Design.Font.unit).foregroundStyle(Design.Palette.secondary)
        }
    }
}

/// Climbs this ride went up (a first time, a new best, or how far off your best) and milestones it crossed.
private struct PalmaresPanel: View {
    let result: Palmares.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(result.climbs, id: \.climb.id) { c in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Icon(c.isBest ? "mountain" : "check", size: 18).foregroundStyle(Design.accent(forGrade: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(c)).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                        Text("\(TimeFormat.clock(c.effort.seconds)) · \(Int(c.effort.vam.rounded())) VAM" + detail(c))
                            .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    }
                }
            }
            ForEach(result.milestones.map(\.title), id: \.self) { title in
                HStack(spacing: 12) {
                    Icon("flag", size: 18).foregroundStyle(Design.accent(forGrade: 8))
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }

    private func title(_ c: Palmares.Result.Climb) -> String {
        c.previousBest == nil ? "First time up \(c.climb.name)" : c.isBest ? "New best on \(c.climb.name)" : c.climb.name
    }

    private func detail(_ c: Palmares.Result.Climb) -> String {
        guard let previous = c.previousBest else { return "" }
        let diff = c.effort.seconds - previous
        return diff < 0 ? " · \(TimeFormat.clock(-diff)) quicker" : " · \(TimeFormat.clock(diff)) off your best"
    }
}

/// Saving a finished ride: the store, then uploads and Apple Health when they're on. Used by the review screen and by
/// "Stop session", which saves without it.
@MainActor
enum RideSaver {
    static func save(_ ride: FinishedRide, rpe: Int?, note: String?, prefs: Preferences) {
        RideStore.save(ride, rpe: rpe, note: note)
        CampaignStore.record(ride)
        PlanStore.record(ride)
        WidgetBridge.refresh(prefs: prefs)
        if UploadSettings.autoUpload {
            Task { await UploadCenter.shared.uploadToConfigured(ride) }
        }
        if prefs.saveToHealth {
            Task { try? await HealthExport.save(ride) }
        }
    }

    /// "Stop session": keep the ride if it's worth keeping (a minute or more), then go home.
    static func saveWithoutReview(_ ride: FinishedRide, prefs: Preferences) {
        if ride.summary.activeSeconds >= 60 {
            save(ride, rpe: nil, note: nil, prefs: prefs)
        } else {
            RideStore.discard(id: ride.id)
        }
    }
}
