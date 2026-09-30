import SwiftUI
import ZmashKit

/// Renders the selected face with its state overlay, scaled to fit the space, and the ride band under it.
/// `Classic` (the customisable dashboard) is drawn by the ride screen itself.
struct FaceView: View {
    let face: FaceID
    let data: FaceData
    let dark: Bool
    let calm: Bool
    /// False in static previews (thumbnails): no continuous animation.
    var animate = true
    /// The rider's palette and slot choices for this face.
    var style: FaceStyle?

    @Environment(Preferences.self) private var prefs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// The rider's style, in the face's highest-contrast palette when Increase Contrast is on, with their main number
    /// (D160: the same on every face).
    private var s: FaceStyle {
        var s = style ?? .default(face)
        s.hero = prefs.mainNumber
        // The big number is never a small one too (D161): its small place shows speed instead (or the next number the
        // face doesn't show), and with no small place for it, speed takes the last slot.
        let shown = FaceStyle.fixedSmalls(face) + s.slots(face).filter { $0 != .empty }
        s.standIn = HeroCycle.standIn(for: s.heroMetric, designed: .speed, shown: shown, candidates: FaceMetric.standIns)
        s.heroShown = shown.contains(s.heroMetric)
        if contrast == .increased, let p = FacePalettes.highestContrast(for: face, dark: dark) { s.paletteID = p.id }
        return s
    }

    /// Ambient motion (a road scrolling, streaks, a spinning chainring) runs only while riding, and never with Reduce
    /// Motion (DESIGN §4): paused, done or waiting for the first stroke, the face holds still and costs nothing.
    private var ambient: Bool { animate && data.state == .riding && !reduceMotion }

    var body: some View {
        // The face above; the band below: the route or workout, and the whole course's profile (if on).
        VStack(spacing: 0) {
            canvas
            if band {
                RideBand(data: data, showProfile: prefs.courseStrip,
                         zoom: Binding(get: { prefs.courseZoom }, set: { prefs.courseZoom = $0 }))
            }
        }
        .background(letterbox)
        .environment(\.faceFont, s.font)
    }

    /// What VoiceOver reads for the face: the numbers, not its decoration ("weight ∝ power…").
    private var spokenSummary: String {
        "\(face.name). Main number \(s.heroMetric.name.lowercased()), \(s.heroMetric.value(data)). "
            + "\(data.speed1) \(data.speedUnit), \(data.powerI) watts, \(data.cadenceText) rpm, grade \(data.gradeText), "
            + "time \(data.elapsedText), gear \(data.gearText)"
    }

    private var canvas: some View {
        FaceCanvasView(background: letterbox) {
            ZStack {
                Group {
                    switch face {
                    case .paper: PaperFace(d: data, dark: dark, style: s)
                    case .aura: AuraFace(d: data, dark: dark, calm: calm, style: s)
                    case .night: NightFace(d: data, calm: calm, animate: ambient, style: s)
                    case .horizon: HorizonFace(d: data, dark: dark, style: s)
                    case .kinetic: KineticFace(d: data, dark: dark, style: s)
                    case .borne: BorneFace(d: data, dark: dark, style: s)
                    case .stem: StemFace(d: data, dark: dark, style: s)
                    // Piste and Tarmac have no quieter mode: calm holds them still.
                    case .piste: PisteFace(d: data, dark: dark, animate: ambient && !calm, style: s)
                    case .groupset: GroupsetFace(d: data, dark: dark, calm: calm, animate: ambient, style: s)
                    case .broadcast: BroadcastFace(d: data, calm: calm, style: s)
                    case .tarmac: TarmacFace(d: data, dark: dark, animate: ambient && !calm, style: s)
                    case .classic: Color.clear
                    }
                }
                // Paused, the face rests: colour drains and it dims a touch; pedalling brings it back.
                .saturation(resting ? 0.2 : 1)
                .brightness(resting ? -0.05 : 0)
                .animation(.easeInOut(duration: calm ? 0.2 : 0.9), value: resting)
                if animate {
                    MomentLayer(face: face, data: data, ink: momentInk, calm: calm)
                }
                FaceStateOverlay(data: data, family: s.family(stateFamily), ink: stateInk, lightScrim: lightScrim,
                                 paperDone: face == .paper, restLine: restLine)
                // With a band, events show there instead of over the face's numbers.
                if !band {
                    FaceEventToast(data: data, ink: eventInk, background: eventBackground)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityAddTraits(.updatesFrequently)
        .heroAction()
    }

    private var band: Bool { RideBand.shows(data, profile: prefs.courseStrip) }

    private var resting: Bool {
        if case .paused = data.state { return true }
        return false
    }

    /// Each face's own colours for its moments.
    private var momentInk: MomentInk {
        switch face {
        case .paper:
            let p = PaperFace.palette(dark: dark, style: s)
            return MomentInk(ink: p.ink, accent: p.ac, bg: p.bg)
        case .aura:
            // Aura's colour is the field; its light is the ink.
            let ink = s.palette(.aura).ink(dark: dark)
            return MomentInk(ink: ink, accent: ink, bg: AuraFace.background(dark: dark, style: s))
        case .night:
            return MomentInk(ink: .white, accent: NightFace.glow(s), bg: .black, additive: true)
        case .horizon:
            let p = s.palette(.horizon)
            return MomentInk(ink: p.ink(dark: dark), accent: p.accent(dark: dark),
                             bg: HorizonFace.background(progress: data.progress, style: s))
        case .kinetic:
            let p = KineticFace.palette(dark: dark, style: s)
            return MomentInk(ink: p.ink, accent: p.ac, bg: p.bg)
        case .borne, .stem, .piste, .groupset, .broadcast, .tarmac:
            let p = s.palette(face)
            return MomentInk(ink: roundThreeInk, accent: p.accent(dark: dark), bg: letterbox)
        case .classic:
            return MomentInk(ink: .primary, accent: .primary, bg: .clear)
        }
    }

    /// Broadcast and Tarmac are dark by nature (a TV graphic, a road); the others follow the theme.
    private var darkOnly: Bool { face == .broadcast || face == .tarmac || face == .night }

    private var roundThreeInk: Color { darkOnly ? .white : s.palette(face).ink(dark: dark) }

    /// How each round 3 face rests when paused (the design's own words).
    private var restLine: String? {
        switch face {
        case .borne: "the road waits"
        case .stem: "the card stays taped"
        case .piste: "riders neutralised"
        case .groupset: "the cranks stop"
        case .broadcast: "coverage paused"
        case .tarmac: "the road stops"
        default: nil
        }
    }

    private var letterbox: Color {
        switch face {
        case .paper: PaperFace.palette(dark: dark, style: s).bg
        case .aura: AuraFace.background(dark: dark, style: s)
        case .night: .black
        case .horizon: HorizonFace.background(progress: data.progress, style: s)
        case .kinetic: KineticFace.palette(dark: dark, style: s).bg
        case .borne, .stem, .piste, .groupset, .broadcast, .tarmac: s.palette(face).bg(dark: dark)
        case .classic: .clear
        }
    }

    private var stateFamily: FaceFont.Family {
        switch face {
        case .horizon: .newsreader
        case .aura: .outfit
        case .kinetic: .robotoFlex
        case .borne, .piste, .broadcast, .tarmac: .barlow
        default: .archivo
        }
    }

    private var lightScrim: Bool { !dark && !darkOnly }

    private var stateInk: Color {
        switch face {
        case .night: .white
        case .paper: PaperFace.palette(dark: dark, style: s).ink
        case .kinetic: KineticFace.palette(dark: dark, style: s).ink
        case .aura: s.palette(.aura).ink(dark: dark)
        case .horizon: s.palette(.horizon).ink(dark: dark)
        case .borne, .stem, .piste, .groupset, .broadcast, .tarmac: roundThreeInk
        case .classic: .primary
        }
    }

    private var eventInk: Color { face == .night ? NightFace.glow(s) : stateInk }
    private var eventBackground: Color {
        dark || darkOnly ? Color.black.opacity(0.35) : Color.white.opacity(0.4)
    }
}

/// The name tag shown for a second when the face changes mid-ride.
struct FaceNameTag: View {
    let name: String
    let shownAt: Date?

    var body: some View {
        if let shownAt {
            // Stops once the tag has faded (the ride screen redraws often enough to notice), rather than ticking at
            // 30 Hz for the rest of the ride.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: Date.now.timeIntervalSince(shownAt) > 1.2)) { t in
                let age = t.date.timeIntervalSince(shownAt) / 1.2
                if age < 1 {
                    Text(name)
                        .font(FaceFont.font(.archivo, 20, weight: 400)).tracking(20 * 0.34).textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color(hex: 0x0A0A0C, opacity: 0.72), in: RoundedRectangle(cornerRadius: 2))
                        .opacity(max(0, 1 - pow(age, 3)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 22)
            .allowsHitTesting(false)
        }
    }
}
