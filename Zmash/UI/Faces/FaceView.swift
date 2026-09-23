import SwiftUI
import ZmashKit

/// Renders the selected face with its state overlay and event toast, scaled to fit the space.
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

    private var s: FaceStyle { style ?? .default(face) }

    var body: some View {
        FaceCanvasView(background: letterbox) {
            ZStack {
                Group {
                    switch face {
                    case .paper: PaperFace(d: data, dark: dark, style: s)
                    case .aura: AuraFace(d: data, dark: dark, calm: calm, style: s)
                    case .night: NightFace(d: data, calm: calm, animate: animate, style: s)
                    case .horizon: HorizonFace(d: data, dark: dark, style: s)
                    case .kinetic: KineticFace(d: data, dark: dark, style: s)
                    case .borne: BorneFace(d: data, dark: dark, style: s)
                    case .stem: StemFace(d: data, dark: dark, style: s)
                    case .piste: PisteFace(d: data, dark: dark, animate: animate, style: s)
                    case .groupset: GroupsetFace(d: data, dark: dark, calm: calm, animate: animate, style: s)
                    case .broadcast: BroadcastFace(d: data, calm: calm, style: s)
                    case .tarmac: TarmacFace(d: data, dark: dark, animate: animate, style: s)
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
                FaceStateOverlay(data: data, family: stateFamily, ink: stateInk, lightScrim: lightScrim,
                                 paperDone: face == .paper, restLine: restLine)
                FaceEventToast(data: data, ink: eventInk, background: eventBackground)
            }
        }
    }

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
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { t in
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
