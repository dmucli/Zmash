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

    @State private var index: Int?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RideHeader(index: index, meta: RideTitle.meta(ride.startedAt, plan: ride.plan), title: RideTitle.title(ride.plan),
                               compact: !wide) {
                        if let postcard {
                            ShareLink(item: postcard, preview: SharePreview("Ride", image: postcard)) {
                                PillLabel(title: "Share", icon: "share-2")
                            }
                            .buttonStyle(PressStyle())
                        }
                        if isShort {
                            PillButton(title: "Save anyway") { save() }
                            PillButton(title: "Discard", style: .primary) { discard() }
                        } else {
                            PillButton(title: "Discard") { confirmDiscard = true }
                            PillButton(title: "Save", icon: "check", style: .primary) { save() }
                        }
                    }
                    SummaryGrid(summary: ride.summary, units: prefs.units, columns: wide ? 6 : 3)
                    if wide {
                        HStack(alignment: .top, spacing: 16) {
                            charts.frame(maxWidth: .infinity)
                            side.frame(width: min(420, geo.size.width * 0.36))
                        }
                    } else {
                        side
                        charts
                    }
                }
                .frame(maxWidth: 1240)
                .padding(.horizontal, wide ? Design.Space.screen : Design.Space.gutter)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .screenBackground()
        .confirmationDialog("Discard this ride?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { discard() }
        }
        .interactiveDismissDisabled()
        .task {
            index = WidgetBridge.summary(prefs: prefs).weekRides + 1
            training = TrainingResult(ride: ride, ftp: prefs.ftp)
            palmares = Palmares.result(for: ride)
            campaign = CampaignStore.preview(ride)
            postcard = PostcardRenderer.write(
                RidePostcard(startedAt: ride.startedAt, summary: ride.summary, samples: ride.samples,
                             units: prefs.units, title: ride.plan.workout?.name ?? ride.plan.route?.name, tss: training?.load.tss),
                name: "Zmash ride")
        }
    }

    @ViewBuilder private var charts: some View {
        if ride.samples.count > 10 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("The ride")
                SessionCharts(samples: ride.samples, units: prefs.units)
            }
            .card(padding: 22)
        }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let training {
                TrainingPanel(result: training, ftp: prefs.ftp) { prefs.ftp = $0 }
            }
            if let campaign {
                CampaignPanel(preview: campaign)
            }
            if ride.samples.count >= 60 {
                ZonesCard(entry: ZoneStore.zones(ride, prefs: prefs))
            }
            if let palmares, !palmares.isEmpty {
                PalmaresPanel(result: palmares)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("How hard did it feel?")
                RPEPicker(value: $rpe)
                TextField("Note", text: $note)
                    .font(Design.Font.body)
                    .frame(minHeight: 24)
                    .sunkTile()
            }
            .card(padding: 20)
            UploadRow(id: ride.id) { ride }
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

/// A ride's numbers as the system's stat strip: mono labels over bib numerals, split by hairlines.
struct SummaryGrid: View {
    let summary: SessionSummary
    let units: Units
    var columns = 6

    private var items: [(label: String, value: String, unit: String)] {
        var items: [(label: String, value: String, unit: String)] = [
            ("Time", TimeFormat.clock(summary.activeSeconds), ""),
            ("Distance", String(format: "%.1f", units.distance(summary.distanceM)), units.distanceUnit),
            ("Avg power", "\(summary.avgPowerW)", "W"),
            ("Max power", "\(summary.maxPowerW)", "W"),
            ("Avg speed", String(format: "%.1f", units.speed(summary.avgSpeedKph)), units.speedUnit),
            ("Climbed", String(format: "%.0f", units.elevation(summary.elevationGainM)), units.elevationUnit),
            ("Cadence", "\(summary.avgCadenceRpm)", "rpm"),
            ("Energy", String(format: "%.0f", summary.kcal), "kcal"),
        ]
        if let avg = summary.avgHeartRateBpm { items.append(("Avg heart", "\(avg)", "bpm")) }
        if let max = summary.maxHeartRateBpm { items.append(("Max heart", "\(max)", "bpm")) }
        return items
    }

    var body: some View {
        StatStrip(stats: items, size: 36, columns: columns)
    }
}

/// A ride's heading: a vermilion bib, a mono date line, the ride's name large, and its actions.
struct RideHeader<Actions: View>: View {
    let index: Int?
    let meta: String
    let title: String
    var compact = false
    @ViewBuilder var actions: Actions

    var body: some View {
        let heading = HStack(alignment: .bottom, spacing: 18) {
            if let index { BibIndex(n: index, size: compact ? 56 : 84, lit: true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(meta).monoLabel(12).foregroundStyle(Design.Palette.fg3)
                Text(title).textStyle(.display, size: compact ? 28 : 40).foregroundStyle(Design.Palette.fg1)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
        }
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                heading
                HStack(spacing: 8) { actions }
            }
        } else {
            HStack(alignment: .bottom, spacing: 16) {
                heading.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { actions }
            }
        }
    }
}

enum RideTitle {
    /// "TUE 23 SEP · 18:42 · WORKOUT"
    static func meta(_ date: Date, plan: SessionPlan) -> String {
        let kind = plan.workout != nil ? (plan.usesERG ? "Workout · ERG" : "Workout") : plan.route != nil ? "Route" : "Free ride"
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · "
            + date.formatted(date: .omitted, time: .shortened) + " · " + kind
    }

    static func title(_ plan: SessionPlan) -> String {
        plan.workout?.name ?? plan.route?.name ?? "Free ride"
    }
}

/// A pill's look for things that aren't Buttons (ShareLink, NavigationLink).
struct PillLabel: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Icon(icon, size: 15) }
            Text(title).font(Design.Font.sans(14, weight: 600))
        }
        .foregroundStyle(Design.Palette.fg1)
        .padding(.horizontal, 18).frame(minHeight: 44)
        .background {
            Capsule().fill(Design.Palette.surfaceGlass)
            Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
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
                            .font(Design.Font.bib(22))
                            .foregroundStyle(on ? Design.Palette.onAccent : Design.Palette.fg3)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: Design.Radius.sm)
                                .fill(on ? Design.Zone.color(forFTPFraction: 0.45 + Double(n) * 0.08) : Design.Palette.surfaceSunk))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effort \(n) of 10")
                }
            }
            HStack {
                Text("easy"); Spacer(); Text("max")
            }
            .monoLabel()
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
                    .frame(minHeight: 24)
                    .sunkTile()
                }
                .buttonStyle(.plain)
            } else if updated {
                Text("FTP updated").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private func stat(_ value: String, _ label: String) -> some View {
        StatTile(label: label, value: value, size: 32)
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
        .background(CardBackground())
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
            Task {
                do {
                    try await HealthExport.save(ride)
                    RideStore.markSent(ride.id, to: HealthExport.sentKey)
                } catch {
                    Diagnostics.log("health", "save failed: \(error.localizedDescription)")
                }
            }
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
