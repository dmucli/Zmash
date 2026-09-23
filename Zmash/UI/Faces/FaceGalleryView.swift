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
        ZStack {
            Color(hex: 0x0C0C0E).ignoresSafeArea()
            if let demo {
                FacePreview(face: face, data: demo.data, dark: scheme == .dark,
                            calm: prefs.faceMotion == .calm || reduceMotion, units: prefs.units)
                    .id(face)
                    .transition(.opacity)
                    .ignoresSafeArea()
                    .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                        if abs(v.translation.width) > abs(v.translation.height) { step(v.translation.width < 0 ? 1 : -1) }
                    })
            }
            panel
            closeButton
        }
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
            get: { prefs.faceRotation.contains(face) },
            set: { on in
                if on { if !prefs.faceRotation.contains(face) { prefs.faceRotation.append(face) } }
                else if prefs.faceRotation.count > 1 { prefs.faceRotation.removeAll { $0 == face } }
            })
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Spacer()
            if face != .classic, let demo {
                MomentBar(demo: demo, face: face)
                    .padding(.bottom, 14)
            }
            HStack(spacing: 11) {
                ForEach(faces.indices, id: \.self) { i in
                    Circle().fill(.white).frame(width: 9, height: 9).opacity(i == index ? 1 : 0.32)
                        .onTapGesture { withAnimation(.linear(duration: 0.3)) { index = i } }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(hex: 0x060608, opacity: 0.72), in: Capsule())
            .padding(.bottom, 18)

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Face \(index + 1) of \(faces.count)").faceLabel(.archivo, 15, tracking: 0.34)
                        .foregroundStyle(Color(hex: 0xD6D2CA))
                    Text(face.name).font(FaceFont.font(.archivo, 60, weight: 500)).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 6)
                    Text(face.description).font(FaceFont.font(.archivo, 23, weight: 400))
                        .foregroundStyle(Color(hex: 0xDAD6CE)).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Magic moment · \(face.magic)").faceLabel(.archivo, 15, tracking: 0.2)
                        .foregroundStyle(Color(hex: 0xC3BFB7)).padding(.top, 14)
                }
                .frame(maxWidth: 720, alignment: .leading)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) {
                    Toggle(isOn: inRotation) {
                        Text("In D-pad rotation").faceLabel(.archivo, 13, tracking: 0.18).foregroundStyle(Color(hex: 0xC3BFB7))
                    }
                    .toggleStyle(.switch).tint(Color(hex: 0xF2F0EB)).fixedSize()
                    HStack(spacing: 12) {
                        Button { customising = true } label: {
                            Text("Customise")
                                .font(FaceFont.font(.archivo, 15, weight: 500)).tracking(15 * 0.2).textCase(.uppercase)
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(Color(hex: 0xF2F0EB))
                                .padding(.horizontal, 22).padding(.vertical, 18)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        round("chevron-left") { step(-1) }
                        round("chevron-right") { step(1) }
                        Button {
                            prefs.face = face
                            close()
                        } label: {
                            Text(prefs.face == face ? "In use" : "Use")
                                .font(FaceFont.font(.archivo, 17, weight: 600)).tracking(17 * 0.22).textCase(.uppercase)
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(Color(hex: 0x101012))
                                .padding(.horizontal, 34).padding(.vertical, 18)
                                .background(Color(hex: 0xF2F0EB), in: RoundedRectangle(cornerRadius: 2))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .foregroundStyle(Color(hex: 0xF2F0EB))
            .padding(.horizontal, 44).padding(.top, 34).padding(.bottom, 30)
            .background(
                LinearGradient(stops: [.init(color: Color(hex: 0x060608, opacity: 0.96), location: 0),
                                       .init(color: Color(hex: 0x060608, opacity: 0.95), location: 0.72),
                                       .init(color: Color(hex: 0x060608, opacity: 0.72), location: 0.9),
                                       .init(color: Color(hex: 0x060608, opacity: 0), location: 1)],
                               startPoint: .bottom, endPoint: .top)
                    .ignoresSafeArea()
            )
        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                ZStack {
                    Design.Palette.background
                    RideDashboard(readout: RideReadout(face: data), config: prefs.display, units: units,
                                  size: geo.size, compact: geo.size.width < 700)
                }
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
                .font(FaceFont.font(.archivo, 13, weight: 600)).tracking(13 * 0.16).textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x101012))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(Color(hex: 0xF2F0EB)))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(demo.showreelRunning ? "Stop showreel" : "Play every moment")

            ForEach(FaceMoment.moments(for: face)) { moment in
                let on = demo.previewing == moment
                Button { demo.play(moment) } label: {
                    Text(moment.name)
                        .font(FaceFont.font(.archivo, 13, weight: 500)).tracking(13 * 0.12).textCase(.uppercase)
                        .foregroundStyle(on ? Color(hex: 0x101012) : Color(hex: 0xF2F0EB).opacity(0.85))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Capsule().fill(on ? Color(hex: 0xF2F0EB).opacity(0.85) : .clear))
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
