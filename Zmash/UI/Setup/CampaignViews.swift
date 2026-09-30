import SwiftUI
import ZmashKit

/// A stage race as a campaign: the next stage to ride, the general and mountains classifications, and the stages done.
struct CampaignView: View {
    let race: Race
    let choose: (String) -> Void
    /// In home's preview (D144): no page background, and the card's margins.
    var embedded = false
    @Environment(Preferences.self) private var prefs
    @State private var campaign: CampaignState?
    @State private var length: Double? = 3600
    @State private var confirmAbandon = false

    private static let lengths: [(Double?, String)] = [(nil, "Full stage"), (1800, "Finale · 30 min"),
                                                       (2700, "45 min"), (3600, "1 h")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let campaign {
                    header(campaign)
                    if let stage = CampaignStore.nextStage(campaign) {
                        next(campaign, stage: stage)
                    } else {
                        podium(campaign)
                    }
                    let results = CampaignStore.results(campaign)
                    if !results.isEmpty {
                        let (gc, kom) = Campaign.classifications(results, rivals: campaign.rivals)
                        HStack(alignment: .top, spacing: 28) {
                            table("General classification", gc, leader: gc.first, value: { s in
                                s.name == gc.first?.name ? TimeFormat.clock(Int(s.seconds.rounded()))
                                                         : "+" + TimeFormat.clock(Int((s.seconds - gc[0].seconds).rounded()))
                            }, jersey: Color(hex: 0xF2C230))
                            table("Mountains", kom, leader: kom.first, value: { "\($0.points) pts" }, jersey: Color(hex: 0xC62B25), limit: 5)
                                .frame(maxWidth: 320)
                        }
                        stagesDone(campaign, results)
                    }
                    if CampaignStore.isFinished(campaign) {
                        Button("Start a new campaign") { self.campaign = CampaignStore.start(race: race, prefs: prefs) }
                            .font(Design.Font.label).buttonStyle(.plain).foregroundStyle(Design.Palette.primary).frame(minHeight: 44)
                    } else {
                        Button("Abandon the campaign", role: .destructive) { confirmAbandon = true }
                            .font(Design.Font.small).buttonStyle(.plain).frame(minHeight: 44)
                    }
                } else {
                    intro
                }
            }
            .padding(embedded ? 22 : 24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: embedded ? .leading : .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(embedded ? .clear : Design.Palette.background)
        .navigationTitle(race.name + " · campaign")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { campaign = CampaignStore.latest(raceID: race.id) }
        .confirmationDialog("Abandon the campaign?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Abandon", role: .destructive) {
                guard var c = campaign else { return }
                c.abandoned = true
                CampaignStore.save(c)
                campaign = nil
            }
        } message: {
            Text("Your results are kept as a DNF. You can start again from stage 1.")
        }
    }

    // MARK: Pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            PreviewTitle(title: "Ride the \(race.name) \(String(race.year))",
                         subtitle: "\(race.stages.count) stages, in order, against 20 rivals riding the same roads at 85–115 % of your pace. Ride each stage whole, or just its finale: the rest counts at your usual pace. Time makes the general classification; the first three over each categorised climb take mountains points.")
            PrimaryButton(title: "Start the campaign") {
                campaign = CampaignStore.start(race: race, prefs: prefs)
            }
            .frame(maxWidth: 360)
        }
    }

    private func header(_ c: CampaignState) -> some View {
        let results = CampaignStore.results(c)
        let (gc, _) = Campaign.classifications(results, rivals: c.rivals)
        let place = (gc.firstIndex { $0.isYou } ?? 0) + 1
        return HStack(spacing: 28) {
            Fact(value: "\(c.ridden.count) / \(race.stages.count)", label: "stages ridden")
            if !results.isEmpty {
                Fact(value: ordinal(place), label: "overall")
                Fact(value: place == 1 ? "leader" : "+" + TimeFormat.clock(Int(((gc.first { $0.isYou }?.seconds ?? 0) - gc[0].seconds).rounded())),
                     label: "to the leader")
            }
            Fact(value: "\(Int(c.pacePowerW.rounded())) W", label: "your pace")
        }
    }

    private func next(_ c: CampaignState, stage: Stage) -> some View {
        let route = race.route(stage)
        let stats = RouteStats.of(route)
        let options = Self.lengths.filter { $0.0 == nil || $0.0! < stats.estimatedSeconds * 0.9 }
        let chosen = options.contains { $0.0 == length } ? length : nil
        return VStack(alignment: .leading, spacing: 14) {
            PreviewTitle(title: "Next: stage \(stage.number)",
                         subtitle: String(format: "%.0f km · %.0f m climbing · %@ at your pace", stats.distanceM / 1000,
                                          stats.ascentM, TimeFormat.estimate(stats.estimatedSeconds)),
                         difficulty: Difficulty.route(route, estimatedSeconds: stats.estimatedSeconds))
            ElevationProfile(route: route, climbs: stats.climbs, window: window(chosen, stats: stats), units: prefs.units)
                .frame(height: 160)
            Segmented(options: options.map { ($0.0, $0.1) }, selection: Binding(get: { chosen }, set: { length = $0 }))
            PrimaryButton(title: "Ride stage \(stage.number)") {
                let base = race.routeID(stage)
                if let w = window(chosen, stats: stats) {
                    choose(RouteStore.segmentID(base, fromM: w.lowerBound, toM: w.upperBound))
                } else {
                    choose(base)
                }
            }
        }
        .padding(16)
        .background(CardBackground())
    }

    /// The finale: the last `length` seconds of the stage at your pace.
    private func window(_ length: Double?, stats: RouteStats) -> ClosedRange<Double>? {
        guard let length else { return nil }
        let from = stats.timing.latestStart(for: length)
        return from...stats.distanceM
    }

    private func table(_ title: String, _ list: [Campaign.Standing], leader: Campaign.Standing?,
                       value: @escaping (Campaign.Standing) -> String, jersey: Color, limit: Int = 10) -> some View {
        let you = list.firstIndex { $0.isYou } ?? 0
        let shown = Array(list.prefix(limit).enumerated()) + (you >= limit ? [(you, list[you])] : [])
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            VStack(spacing: 0) {
                ForEach(shown, id: \.1.name) { i, s in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                            .frame(width: 26, alignment: .trailing)
                        Circle().fill(i == 0 ? jersey : .clear).frame(width: 10, height: 10)
                        Text(s.name).font(s.isYou ? Design.Font.label.bold() : Design.Font.label)
                            .foregroundStyle(Design.Palette.primary).lineLimit(1)
                        Spacer()
                        Text(value(s)).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(s.isYou ? Design.Palette.primary.opacity(0.07) : .clear)
                }
            }
            .background(CardBackground())
        }
    }

    private func stagesDone(_ c: CampaignState, _ results: [Campaign.StageResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Your stages")
            VStack(spacing: 0) {
                ForEach(Array(zip(c.ridden, results)), id: \.0.stage) { r, result in
                    HStack {
                        Text("Stage \(r.stage)").font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                        Text(r.fromM > 0 ? "finale" : "full").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                        Spacer()
                        Text("\(ordinal(result.place)) · \(TimeFormat.clock(Int(result.seconds[0].rounded())))" + (result.points[0] > 0 ? " · \(result.points[0]) pts" : ""))
                            .font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                }
            }
            .background(CardBackground())
        }
    }

    private func podium(_ c: CampaignState) -> some View {
        let (gc, kom) = Campaign.classifications(CampaignStore.results(c), rivals: c.rivals)
        let place = (gc.firstIndex { $0.isYou } ?? 0) + 1
        let card = PodiumCard(race: race, general: gc, mountainsLeader: kom.first)
        return VStack(alignment: .leading, spacing: 14) {
            PreviewTitle(title: place == 1 ? "You won the \(race.name)" : "You finished \(ordinal(place)) overall",
                         subtitle: "Podium: " + gc.prefix(3).map(\.name).joined(separator: ", ")
                            + (kom.first?.isYou == true ? " · and the mountains jersey is yours" : ""))
            if let file = PostcardRenderer.write(card, name: "Zmash \(race.name) \(race.year)") {
                ShareLink(item: file, preview: SharePreview("Final classification", image: file)) {
                    HStack(spacing: 10) {
                        Icon("share", size: 18)
                        Text("Share the final classification").font(Design.Font.label)
                    }
                    .foregroundStyle(Design.Palette.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.background))
                }
            }
        }
        .padding(16)
        .background(CardBackground())
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// On the ride summary: what the stage did to your campaign.
struct CampaignPanel: View {
    let preview: CampaignStore.Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(preview.raceName) · stage \(preview.stage)").textCase(.uppercase)
                .monoLabel().foregroundStyle(Design.Palette.secondary)
            Text(headline).textStyle(.h2, size: 22).foregroundStyle(Design.Palette.primary)
            Text(detail).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
            if preview.tookYellow || preview.tookPolkaDot {
                HStack(spacing: 8) {
                    if preview.tookYellow { jersey("Leader's jersey", Color(hex: 0xF2C230)) }
                    if preview.tookPolkaDot { jersey("Mountains jersey", Color(hex: 0xC62B25)) }
                }
            }
            Text("Counts when you save the ride.").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var headline: String {
        if preview.finished { return preview.gcAfter == 1 ? "You won the race" : "Final: \(ordinal(preview.gcAfter)) overall" }
        return "\(ordinal(preview.stagePlace)) on the stage · \(ordinal(preview.gcAfter)) overall"
    }

    private var detail: String {
        var parts: [String] = []
        if let before = preview.gcBefore, before != preview.gcAfter {
            parts.append(before > preview.gcAfter ? "up \(before - preview.gcAfter) in the GC" : "down \(preview.gcAfter - before) in the GC")
        }
        if preview.gapToLeader > 0 { parts.append("+" + TimeFormat.clock(Int(preview.gapToLeader.rounded())) + " to the leader") }
        if preview.points > 0 { parts.append("\(preview.points) mountains points") }
        return parts.isEmpty ? "\(preview.field) riders" : parts.joined(separator: " · ")
    }

    private func jersey(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(text).font(Design.Font.small).foregroundStyle(Design.Palette.primary)
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Capsule().fill(Design.Palette.background))
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// The final classification as a card to share, in the ride postcard's style.
struct PodiumCard: View {
    let race: Race
    let general: [Campaign.Standing]
    let mountainsLeader: Campaign.Standing?

    private let paper = Color(hex: 0xF2EFE8)
    private let ink = Color(hex: 0x141414)
    private let accent = Color(hex: 0xC8341B)

    var body: some View {
        let you = (general.firstIndex { $0.isYou } ?? 0) + 1
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ZMASH").font(FaceFont.font(.archivo, 34, weight: 600)).tracking(34 * 0.3)
                Spacer()
                Text("FINAL CLASSIFICATION").font(FaceFont.font(.archivo, 26, weight: 450)).tracking(26 * 0.2)
            }
            Rectangle().fill(ink).frame(height: 2).padding(.top, 22)
            Text("\(race.name) \(String(race.year))".uppercased())
                .font(FaceFont.font(.archivo, 72, weight: 600)).foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 40)
            Text(you == 1 ? "WINNER" : "\(you)\(suffix(you)) OVERALL")
                .font(FaceFont.font(.archivo, 132, weight: 400)).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 30)
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(general.prefix(3).enumerated()), id: \.element.name) { i, s in
                    HStack {
                        Text("\(i + 1)").frame(width: 60, alignment: .leading)
                        Text(s.name).fontWeight(s.isYou ? .bold : .regular)
                        Spacer()
                        Text(i == 0 ? TimeFormat.clock(Int(s.seconds.rounded())) : "+" + TimeFormat.clock(Int((s.seconds - general[0].seconds).rounded())))
                    }
                }
                if you > 3, let s = general.first(where: \.isYou) {
                    HStack {
                        Text("\(you)").frame(width: 60, alignment: .leading)
                        Text("You").fontWeight(.bold)
                        Spacer()
                        Text("+" + TimeFormat.clock(Int((s.seconds - general[0].seconds).rounded())))
                    }
                }
            }
            .font(FaceFont.font(.archivo, 40, weight: 450)).monospacedDigit()
            .padding(.top, 56)
            if let k = mountainsLeader, k.points > 0 {
                Text("Mountains: \(k.name), \(k.points) points").font(FaceFont.font(.archivo, 34, weight: 450)).padding(.top, 40)
            }
            Spacer(minLength: 0)
            Rectangle().fill(ink).frame(height: 2)
        }
        .foregroundStyle(ink)
        .padding(72)
        .frame(width: 1200, height: 1320, alignment: .topLeading)
        .background(paper)
    }

    private func suffix(_ n: Int) -> String {
        switch (n % 10, n % 100) {
        case (1, let t) where t != 11: "st"
        case (2, let t) where t != 12: "nd"
        case (3, let t) where t != 13: "rd"
        default: "th"
        }
    }
}
