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

    var body: some View {
        FaceCanvasView(background: letterbox) {
            ZStack {
                switch face {
                case .paper: PaperFace(d: data, dark: dark)
                case .aura: AuraFace(d: data, dark: dark, calm: calm)
                case .night: NightFace(d: data, calm: calm, animate: animate)
                case .horizon: HorizonFace(d: data, dark: dark)
                case .kinetic: KineticFace(d: data, dark: dark)
                case .classic: Color.clear
                }
                FaceStateOverlay(data: data, family: stateFamily, ink: stateInk, lightScrim: lightScrim,
                                 paperDone: face == .paper)
                FaceEventToast(data: data, ink: eventInk, background: eventBackground)
            }
        }
    }

    private var letterbox: Color {
        switch face {
        case .paper: PaperFace.palette(dark: dark).bg
        case .aura: AuraFace.background(dark: dark)
        case .night: .black
        case .horizon: HorizonFace.background(progress: data.progress)
        case .kinetic: KineticFace.palette(dark: dark).bg
        case .classic: .clear
        }
    }

    private var stateFamily: FaceFont.Family {
        switch face {
        case .horizon: .newsreader
        case .aura: .outfit
        case .kinetic: .robotoFlex
        default: .archivo
        }
    }

    private var lightScrim: Bool { !dark && face != .night }

    private var stateInk: Color {
        switch face {
        case .night: .white
        case .paper: PaperFace.palette(dark: dark).ink
        case .kinetic: KineticFace.palette(dark: dark).ink
        case .aura: dark ? .white : Color(hex: 0x14141A)
        case .horizon: dark ? Color(hex: 0xEDF0F4) : Color(hex: 0x1A2230)
        case .classic: .primary
        }
    }

    private var eventInk: Color { face == .night ? Color(hex: 0x9FE8FF) : stateInk }
    private var eventBackground: Color {
        dark || face == .night ? Color.black.opacity(0.35) : Color.white.opacity(0.4)
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
