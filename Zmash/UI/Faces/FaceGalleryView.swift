import SwiftUI
import ZmashKit

/// The faces, like choosing a watch face: a live sample ride, swipe or ◀ ▶, Use. A page opened from Settings (D146),
/// with a slim bar under the face: its moments and the dots, then its name and line, and the buttons.
struct FaceGalleryView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var demo: FaceDemo?
    @State private var customising = false
    /// On a phone, the face's description shows when asked (ⓘ).
    @State private var showInfo = false

    private var faces: [FaceID] { FaceID.allCases }
    private var face: FaceID { faces[index] }

    var body: some View {
        GeometryReader { screen in
            // The face is drawn as it rides, on its side at about this screen's size (an iPhone turns to landscape
            // for faces), then scaled into a frame, whole, with the bar beside or below it.
            let full = screen.size
            let ride = CGSize(width: max(full.width, full.height), height: min(full.width, full.height))
            let phone = UIDevice.current.userInterfaceIdiom == .phone
            // A phone on its side: the face on the left, the controls in a column on the right.
            let side = full.height < 560 && full.width > full.height
            // An iPhone upright or a narrow Split View: the bar stacked, less padding.
            let compact = full.width < 760
            Group {
                if side {
                    HStack(spacing: 0) {
                        stage(ride: ride, compact: true, top: 8, leading: 16)
                            .frame(width: full.width * 0.62)
                        sidePanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.trailing, 24)
                    }
                } else {
                    VStack(spacing: 0) {
                        stage(ride: ride, compact: compact, top: compact ? 8 : 16, leading: 0)
                        panel(compact: compact, brief: phone)
                    }
                }
            }
            .frame(width: full.width, height: full.height)
        }
        .background(Design.Tarmac.t900.ignoresSafeArea())
        .navigationTitle("Faces")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Design.Tarmac.t900, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // A showroom of the ride screen: its type stays at the design sizes too.
        .environment(\.fixedType, true)
        .sheet(isPresented: $customising) {
            FaceStyleEditor(face: face)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            index = faces.firstIndex(of: prefs.face) ?? 0
            let d = FaceDemo(ftp: Double(prefs.ftp), units: prefs.units)
            d.start()
            demo = d
            #if DEBUG
            // -ZmashTurn YES: turn an iPhone to landscape, to check the side-by-side layout.
            if UserDefaults.standard.bool(forKey: "ZmashTurn") { OrientationLock.landscape(true) }
            if let moment = DebugLaunch.moment {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    d.play(moment)
                }
            }
            #endif
        }
        .onDisappear { demo?.stop() }
        .background {
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { dismiss() }.keyboardShortcut(.escape, modifiers: []).opacity(0)
        }
    }

    private func step(_ n: Int) {
        withAnimation(.linear(duration: 0.3)) { index = (index + n + faces.count) % faces.count }
    }

    /// The face in a device-like frame: 22-pt corners, a hairline, the sheet shadow.
    private func stage(ride full: CGSize, compact: Bool, top: CGFloat, leading: CGFloat) -> some View {
        GeometryReader { box in
            let margin: CGFloat = compact ? 16 : 44
            // Never zero or negative: on a short screen the bar can take most of the height.
            let scale = max(0.05, min((box.size.width - 2 * margin) / max(full.width, 1), (box.size.height - 20) / max(full.height, 1)))
            let size = CGSize(width: full.width * scale, height: full.height * scale)
            ZStack {
                if let demo {
                    FacePreview(face: face, data: demo.data, dark: scheme == .dark,
                                calm: prefs.faceMotion == .calm || reduceMotion, units: prefs.units)
                        .frame(width: full.width, height: full.height)
                        .scaleEffect(scale)
                        .frame(width: size.width, height: size.height)
                        .id(face)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous).strokeBorder(Design.Tarmac.t700, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 30)
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.xl))
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if abs(v.translation.width) > abs(v.translation.height) { step(v.translation.width < 0 ? 1 : -1) }
            })
            .frame(width: box.size.width, height: box.size.height)
        }
        .padding(.top, top)
        .padding(.leading, leading)
    }

    /// The faces as dots, one per face; tap one to go there.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Array(faces.enumerated()), id: \.element) { i, f in
                Circle().fill(.white).frame(width: 7, height: 7).opacity(i == index ? 1 : 0.3)
                    .frame(width: 18, height: 36)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.linear(duration: 0.3)) { index = i } }
                    .accessibilityLabel(f.name)
                    .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .fixedSize()
    }

    private var useButton: some View {
        PillButton(title: prefs.face == face ? "In use" : "Use this face", icon: prefs.face == face ? "check" : nil,
                   style: prefs.face == face ? .tarmac : .primary, compact: true) {
            prefs.face = face
            dismiss()
        }
        .fixedSize()
        .keyboardShortcut(.return, modifiers: [])
    }

    private var customiseButton: some View {
        PillButton(title: "Customise", icon: "sliders-horizontal", style: .glass, compact: true) { customising = true }
            .fixedSize()
    }

    /// The face's name, which of how many, and its magic moment, on one line.
    private func title(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(face.name).textStyle(.display, size: size).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(index + 1) of \(faces.count) · magic moment · \(face.magic)").monoLabel(11)
                .foregroundStyle(Design.Tarmac.bone2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// A phone on its side: name, dots and the buttons in a column beside the face.
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(face.name).textStyle(.display, size: 26).lineLimit(1).minimumScaleFactor(0.5)
            Text("Magic moment · \(face.magic)").monoLabel(11).foregroundStyle(Design.Tarmac.bone2).lineLimit(2)
            dots.scaleEffect(0.85, anchor: .leading)
            HStack(spacing: 10) {
                customiseButton
                useButton
            }
        }
        .foregroundStyle(Design.Tarmac.bone)
        .environment(\.colorScheme, .dark)
    }

    /// Under the face: the sample ride's moments and the dots, then the face's name and line beside the buttons.
    private func panel(compact: Bool, brief: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if face != .classic, let demo, !brief {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        MomentBar(demo: demo, face: face).fixedSize()
                        Spacer(minLength: 0)
                        dots
                    }
                    VStack(spacing: 8) {
                        MomentBar(demo: demo, face: face)
                        dots
                    }
                }
            } else {
                dots.frame(maxWidth: .infinity)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    // Asks for little width, so the buttons stay beside it and the line wraps instead.
                    words(compact: compact, brief: brief)
                        .frame(minWidth: 0, idealWidth: 300, maxWidth: .infinity, alignment: .leading)
                    buttons(arrows: !compact)
                }
                VStack(alignment: .leading, spacing: 10) {
                    words(compact: compact, brief: brief)
                    buttons(arrows: false)
                }
            }
        }
        .foregroundStyle(Design.Tarmac.bone)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, compact ? 16 : 44).padding(.top, compact ? 12 : 20).padding(.bottom, compact ? 12 : 20)
    }

    private func words(compact: Bool, brief: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                title(size: compact ? 22 : 26)
                if brief {
                    Button { withAnimation(Design.Motion.fast) { showInfo.toggle() } } label: {
                        Text("i").font(Design.Font.sans(14, weight: 700)).foregroundStyle(Design.Tarmac.bone)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Design.Tarmac.bone2, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showInfo ? "Hide the description" : "About this face")
                }
            }
            if !brief || showInfo {
                Text(face.description).font(Design.Font.sans(15))
                    .foregroundStyle(Design.Tarmac.bone2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buttons(arrows: Bool) -> some View {
        HStack(spacing: 10) {
            // On a phone, swiping the face does this.
            if arrows {
                round("chevron-left", label: "Previous face") { step(-1) }
                round("chevron-right", label: "Next face") { step(1) }
            }
            customiseButton
            useButton
        }
        .fixedSize()
    }

    private func round(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 20).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Any face (including Classic) drawn from `FaceData` — used by the gallery and the setup preview.
struct FacePreview: View {
    let face: FaceID
    let data: FaceData
    let dark: Bool
    let calm: Bool
    let units: Units
    var animate = true
    @Environment(Preferences.self) private var prefs

    var body: some View {
        if face == .classic {
            GeometryReader { geo in
                RideDashboard(readout: RideReadout(face: data), config: prefs.classicDisplay, units: units,
                              size: geo.size, compact: geo.size.width < 700, plan: data.plan, riderKg: prefs.riderKg)
            }
        } else {
            FaceView(face: face, data: data, dark: dark, calm: calm, animate: animate, style: prefs.style(face))
        }
    }
}

extension RideReadout {
    /// The Classic dashboard fed from face data (gallery and previews).
    init(face d: FaceData) {
        self.init(speedKph: d.speedKph, powerW: Int(d.powerW.rounded()), cadenceRpm: Int(d.cadenceRpm.rounded()),
                  elapsed: d.elapsed, remaining: d.remaining, kcal: d.kcal, distanceM: d.distanceM,
                  climbedM: d.climbedM, grade: d.grade, gear: d.gear, gearCount: d.gearCount,
                  upcomingGrades: [], waitingForPedal: d.state == .waiting)
        heartRateBpm = d.heartRateBpm.map { Int($0.rounded()) }
    }
}

/// Plays any of the face's moments on the sample ride, or all of them in turn.
private struct MomentBar: View {
    let demo: FaceDemo
    let face: FaceID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            Button { demo.toggleShowreel(face: face) } label: {
                HStack(spacing: 6) {
                    Icon(demo.showreelRunning ? "square" : "play", size: 12)
                    Text(demo.showreelRunning ? "Stop" : "Showreel")
                }
                .font(Design.Font.sans(13, weight: 700))
                .foregroundStyle(Design.Palette.onAccent)
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(Capsule().fill(Design.Accent.vermilion))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(demo.showreelRunning ? "Stop showreel" : "Play every moment")

            ForEach(FaceMoment.moments(for: face)) { moment in
                let on = demo.previewing == moment
                Button { demo.play(moment) } label: {
                    Text(moment.name)
                        .monoLabel(11)
                        .foregroundStyle(on ? Design.Tarmac.t900 : Design.Tarmac.bone.opacity(0.85))
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background(Capsule().fill(on ? Design.Tarmac.bone : .clear))
                        .fixedSize()
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(demo.showreelRunning)
                .accessibilityLabel("Play \(moment.name)")
            }
        }
        .padding(4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Design.Tarmac.glass, in: Capsule())
        .clipShape(Capsule())
        .animation(.snappy(duration: 0.2), value: demo.previewing)
    }
}
