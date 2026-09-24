import SwiftUI
import ZmashKit

/// Full-screen face browser, like choosing a watch face: live sample ride, swipe or ◀ ▶, Use.
struct FaceGalleryView: View {
    let close: () -> Void
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var demo: FaceDemo?
    @State private var customising = false
    /// Tried to take the second-to-last face out of rotation.
    @State private var rotationRefused = false
    /// On a phone, the face's description shows when asked (ⓘ), not taking half the screen.
    @State private var showInfo = false

    private var faces: [FaceID] { FaceID.allCases }
    private var face: FaceID { faces[index] }

    var body: some View {
        GeometryReader { screen in
            // The face is drawn as it rides, on its side at this screen's size (an iPhone turns to landscape for
            // faces), then scaled into a frame, whole, with the details and controls beside or below it.
            let full = screen.size
            let ride = CGSize(width: max(full.width, full.height), height: min(full.width, full.height))
            let phone = UIDevice.current.userInterfaceIdiom == .phone
            // A phone on its side: the face on the left, the controls in a column on the right.
            let side = full.height < 560 && full.width > full.height
            // An iPhone upright or a narrow Split View: controls stacked, less padding.
            let compact = full.width < 760
            Group {
                if side {
                    HStack(spacing: 0) {
                        stage(ride: ride, compact: true, top: 16, leading: 76)
                            .frame(width: full.width * 0.62)
                        sidePanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.trailing, 44)
                    }
                } else {
                    VStack(spacing: 0) {
                        stage(ride: ride, compact: compact, top: compact ? 60 : 24, leading: 0)
                        panel(compact: compact, brief: phone)
                    }
                }
            }
            .frame(width: full.width, height: full.height)
        }
        .ignoresSafeArea()
        .background(Design.Tarmac.t900.ignoresSafeArea())
        .overlay(alignment: .topLeading) { closeButton }
        // A showroom of the ride screen: its type stays at the design sizes too.
        .environment(\.fixedType, true)
        .statusBarHidden()
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
        }
    }

    private func step(_ n: Int) {
        withAnimation(.linear(duration: 0.3)) { index = (index + n + faces.count) % faces.count }
    }

    private var inRotation: Binding<Bool> {
        Binding(
            get: { !prefs.faceRotationExcluded.contains(face) },
            set: { on in
                rotationRefused = false
                if on { prefs.faceRotationExcluded.remove(face) }
                // Keep at least two faces to switch between.
                else if prefs.faceRotation.count > 2 { prefs.faceRotationExcluded.insert(face) }
                else { rotationRefused = true }
            })
    }

    /// The face in a device-like frame: 22-pt corners, a hairline, the sheet shadow.
    private func stage(ride full: CGSize, compact: Bool, top: CGFloat, leading: CGFloat) -> some View {
        GeometryReader { box in
            let margin: CGFloat = compact ? 16 : 88
            // Never zero or negative: on a short screen the panel can take most of the height.
            let scale = max(0.05, min((box.size.width - 2 * margin) / max(full.width, 1), (box.size.height - 28) / max(full.height, 1)))
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
        HStack(spacing: 11) {
            ForEach(Array(faces.enumerated()), id: \.element) { i, f in
                Circle().fill(.white).frame(width: 9, height: 9).opacity(i == index ? 1 : 0.32)
                    .frame(width: 22, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.linear(duration: 0.3)) { index = i } }
                    .accessibilityLabel(f.name)
                    .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .background(Design.Tarmac.glass, in: Capsule())
    }

    private var rotationToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: inRotation) {
                Text("When switching mid-ride").monoLabel().foregroundStyle(Design.Tarmac.bone2)
            }
            .toggleStyle(PillToggleStyle()).fixedSize()
            if rotationRefused {
                Text("Keep at least two faces to switch between.").monoLabel(12).foregroundStyle(Design.Tarmac.bone2)
            }
        }
    }

    private var useButton: some View {
        PillButton(title: prefs.face == face ? "In use" : "Use this face", icon: prefs.face == face ? "check" : nil,
                   style: prefs.face == face ? .tarmac : .primary) {
            prefs.face = face
            close()
        }
        .fixedSize()
        .keyboardShortcut(.return, modifiers: [])
    }

    /// A phone on its side: name, moment, dots and the buttons in a column beside the face.
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(String(format: "%02d", index + 1)).font(Design.Font.bib(34)).foregroundStyle(Design.Accent.vermilion)
                Text(face.name).textStyle(.display, size: 28).lineLimit(1).minimumScaleFactor(0.5)
            }
            Text("Magic moment · \(face.magic)").monoLabel(11).foregroundStyle(Design.Tarmac.bone2).lineLimit(2)
            dots.scaleEffect(0.85, anchor: .leading)
            rotationToggle
            HStack(spacing: 10) {
                PillButton(title: "Customise", icon: "sliders-horizontal", style: .glass, compact: true) { customising = true }
                    .fixedSize()
                useButton
            }
        }
        .foregroundStyle(Design.Tarmac.bone)
        .environment(\.colorScheme, .dark)
        .onChange(of: index) { _, _ in rotationRefused = false }
    }

    private func panel(compact: Bool, brief: Bool) -> some View {
        VStack(spacing: 0) {
            if face != .classic, let demo, !brief {
                MomentBar(demo: demo, face: face)
                    .padding(.bottom, 14)
            }
            dots.padding(.bottom, compact ? 8 : 18)

            let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                 : AnyLayout(HStackLayout(alignment: .bottom, spacing: 30))
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(Design.Font.bib(compact ? 44 : 64)).foregroundStyle(Design.Accent.vermilion)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Face \(index + 1) of \(faces.count)").monoLabel(12).foregroundStyle(Design.Tarmac.bone2)
                            Text(face.name).textStyle(.display, size: compact ? 34 : 52).lineLimit(1).minimumScaleFactor(0.5)
                        }
                        if brief {
                            Spacer(minLength: 0)
                            Button { withAnimation(Design.Motion.fast) { showInfo.toggle() } } label: {
                                Text("i").font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Tarmac.bone)
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(Design.Tarmac.bone2, lineWidth: 1))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showInfo ? "Hide the description" : "About this face")
                        }
                    }
                    if !brief || showInfo {
                        Text(face.description).font(Design.Font.sans(compact ? 16 : 20))
                            .foregroundStyle(Design.Palette.fg2).padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Magic moment · \(face.magic)").monoLabel(12)
                            .foregroundStyle(Design.Tarmac.bone2).padding(.top, 14)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                if !compact { Spacer(minLength: 0) }
                VStack(alignment: compact ? .leading : .trailing, spacing: 14) {
                    rotationToggle
                    HStack(spacing: 12) {
                        PillButton(title: "Customise", icon: "sliders-horizontal", style: .glass) { customising = true }
                            .fixedSize()
                        // On a phone, swiping the face does this.
                        if !compact {
                            round("chevron-left", label: "Previous face") { step(-1) }
                            round("chevron-right", label: "Next face") { step(1) }
                        }
                        useButton
                    }
                }
            }
            .foregroundStyle(Design.Tarmac.bone)
            .padding(.horizontal, compact ? 16 : 44).padding(.top, compact ? 8 : 20).padding(.bottom, compact ? 16 : 30)
            .environment(\.colorScheme, .dark)
        }
        .padding(.top, compact ? 8 : 18)
        .onChange(of: index) { _, _ in rotationRefused = false }
    }

    private func round(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 24).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var closeButton: some View {
        Button(action: close) {
            Icon("x", size: 22).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Design.Tarmac.glass))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .keyboardShortcut(.escape, modifiers: [])
        .padding(20)
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
                RideDashboard(readout: RideReadout(face: data), config: prefs.display, units: units,
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
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(Design.Accent.vermilion))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(demo.showreelRunning ? "Stop showreel" : "Play every moment")

            ForEach(FaceMoment.moments(for: face)) { moment in
                let on = demo.previewing == moment
                Button { demo.play(moment) } label: {
                    Text(moment.name)
                        .monoLabel()
                        .foregroundStyle(on ? Design.Tarmac.t900 : Design.Tarmac.bone.opacity(0.85))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Capsule().fill(on ? Design.Tarmac.bone : .clear))
                        .fixedSize()
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(demo.showreelRunning)
                .accessibilityLabel("Play \(moment.name)")
            }
        }
        .padding(6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 1100)
        .background(Design.Tarmac.glass, in: Capsule())
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .animation(.snappy(duration: 0.2), value: demo.previewing)
    }
}
