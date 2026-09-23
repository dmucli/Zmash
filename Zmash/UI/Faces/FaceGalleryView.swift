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

    private var faces: [FaceID] { FaceID.allCases }
    private var face: FaceID { faces[index] }

    var body: some View {
        GeometryReader { screen in
            // The face is drawn at the ride screen's full size, then scaled into a frame in the upper part, so what you
            // see is the face as it rides, whole, with the details and controls below it rather than over it.
            let full = screen.size
            VStack(spacing: 0) {
                stage(full: full)
                panel
            }
            .frame(width: full.width, height: full.height)
        }
        .ignoresSafeArea()
        .background(Design.Tarmac.t900.ignoresSafeArea())
        .overlay(alignment: .topLeading) { closeButton }
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
                if on { prefs.faceRotationExcluded.remove(face) }
                // Keep at least two faces to switch between.
                else if prefs.faceRotation.count > 2 { prefs.faceRotationExcluded.insert(face) }
            })
    }

    /// The face in a device-like frame: 22-pt corners, a hairline, the sheet shadow.
    private func stage(full: CGSize) -> some View {
        GeometryReader { box in
            let scale = min((box.size.width - 2 * 88) / max(full.width, 1), (box.size.height - 28) / max(full.height, 1))
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
        .padding(.top, 24)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if face != .classic, let demo {
                MomentBar(demo: demo, face: face)
                    .padding(.bottom, 14)
            }
            HStack(spacing: 11) {
                ForEach(Array(faces.enumerated()), id: \.element) { i, _ in
                    Circle().fill(.white).frame(width: 9, height: 9).opacity(i == index ? 1 : 0.32)
                        .onTapGesture { withAnimation(.linear(duration: 0.3)) { index = i } }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(hex: 0x060608, opacity: 0.72), in: Capsule())
            .padding(.bottom, 18)

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(Design.Font.bib(64)).foregroundStyle(Design.Accent.vermilion)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Face \(index + 1) of \(faces.count)").monoLabel(12).foregroundStyle(Design.Tarmac.bone2)
                            Text(face.name).textStyle(.display, size: 52).lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    Text(face.description).font(Design.Font.sans(20))
                        .foregroundStyle(Color(hex: 0xC9C4B8)).padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Magic moment · \(face.magic)").monoLabel(12)
                        .foregroundStyle(Design.Tarmac.bone2).padding(.top, 14)
                }
                .frame(maxWidth: 720, alignment: .leading)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) {
                    Toggle(isOn: inRotation) {
                        Text("When switching mid-ride").monoLabel().foregroundStyle(Design.Tarmac.bone2)
                    }
                    .toggleStyle(PillToggleStyle()).fixedSize()
                    HStack(spacing: 12) {
                        PillButton(title: "Customise", icon: "sliders-horizontal", style: .glass) { customising = true }
                            .fixedSize()
                        round("chevron-left") { step(-1) }
                        round("chevron-right") { step(1) }
                        PillButton(title: prefs.face == face ? "In use" : "Use this face", icon: prefs.face == face ? "check" : nil,
                                   style: prefs.face == face ? .tarmac : .primary) {
                            prefs.face = face
                            close()
                        }
                        .fixedSize()
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .foregroundStyle(Color(hex: 0xF2F0EB))
            .padding(.horizontal, 44).padding(.top, 20).padding(.bottom, 30)
            .environment(\.colorScheme, .dark)
        }
        .padding(.top, 18)
    }

    private func round(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 24).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: close) {
            Icon("x", size: 22).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(hex: 0x060608, opacity: 0.72)))
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
                  climbedM: d.climbedM, grade: d.grade, bias: nil, gear: d.gear, gearCount: d.gearCount,
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
        .background(Color(hex: 0x060608, opacity: 0.78), in: Capsule())
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .animation(.snappy(duration: 0.2), value: demo.previewing)
    }
}
