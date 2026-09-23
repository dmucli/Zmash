import SwiftUI
import ZmashKit

/// The ride screen (brief §10): one hero number, five quiet ones, gear ladder and grade.
struct RideView: View {
    let engine: SessionEngine
    let hub: DeviceHub
    let pip: PiPOverlay
    @Environment(Preferences.self) private var prefs
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var faceTagAt: Date?

    var body: some View {
        GeometryReader { geo in
            let compact = sizeClass == .compact || geo.size.width < 700
            // Split View / Slide Over and the Classic face use the customisable dashboard.
            let classic = compact || prefs.face == .classic
            ZStack {
                // PiP source layer: must be in the view hierarchy; it sits behind the opaque background.
                PiPLayerHost(layer: pip.displayLayer)
                if classic {
                    Design.Palette.background.ignoresSafeArea()
                    if prefs.windBackground {
                        WindBackground(speedKph: engine.speedKph, paused: engine.isPaused || engine.phase == .finished)
                            .ignoresSafeArea()
                    }
                    // Classic gets the course profile too (not in Split View, where every point of height counts).
                    let road = compact || !prefs.courseStrip ? nil : engine.road
                    VStack(spacing: 0) {
                        RideDashboard(readout: RideReadout(engine: engine), config: prefs.display, units: prefs.units,
                                      size: CGSize(width: geo.size.width, height: geo.size.height - (road == nil ? 0 : CourseStrip.height)),
                                      compact: compact)
                        .opacity(engine.isPaused ? 0.4 : 1)
                        .animation(.easeInOut(duration: 0.3), value: engine.isPaused)
                        if let road {
                            let data = FaceData(engine: engine, units: prefs.units)
                            CourseStrip(route: road.route, atM: road.atM, climbs: road.known ? data.climbs : [], known: road.known,
                                        ink: Design.Palette.primary, accent: Design.accent(forGrade: engine.terrainGrade),
                                        background: Design.Palette.background, units: prefs.units,
                                        zoom: Binding(get: { prefs.courseZoom }, set: { prefs.courseZoom = $0 }))
                        }
                    }
                } else {
                    FaceView(face: prefs.face, data: FaceData(engine: engine, units: prefs.units),
                             dark: scheme == .dark, calm: prefs.faceMotion == .calm || reduceMotion,
                             style: prefs.style(prefs.face))
                        .ignoresSafeArea()
                        .id(prefs.face)
                        .transition(.opacity)
                }

                ConnectionDots(hub: hub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Design.Space.gutter)

                FaceNameTag(name: prefs.face.name, shownAt: faceTagAt)

                WorkoutLayer(engine: engine, compact: compact)
                RouteLayer(engine: engine, units: prefs.units, compact: compact)

                if let error = pip.lastError {
                    Text(error)
                        .font(Design.Font.small)
                        .foregroundStyle(Design.Palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 96)
                }

                if classic {
                    if case .countdown(let n) = engine.phase {
                        Text("\(n)")
                            .font(Design.Font.number(compact ? 120 : 220, weight: .bold))
                            .foregroundStyle(Design.Palette.primary)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: n)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Design.Palette.background.opacity(0.85))
                    }
                    if engine.isPaused {
                        Icon("pause", size: 72).foregroundStyle(Design.Palette.primary)
                    }
                }

                if engine.timedDone {
                    DonePrompt(engine: engine, minimal: !classic)
                }

                // Above every overlay (countdown, pause, done) so there's always a way out.
                CloseButton(engine: engine, visible: controlsVisible || !engine.clockStarted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Design.Space.gutter)

                OnScreenControls(engine: engine, hub: hub, pip: pip, visible: controlsVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Design.Space.gutter)
            }
            .animation(.linear(duration: 0.3), value: prefs.face)
            .contentShape(Rectangle())
            .onTapGesture { revealControls() }
            // Swipe left or right to change face, like the D-pad.
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 1.5 else { return }
                hub.send(dx < 0 ? .nextFace : .previousFace)
            })
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { revealControls() }
        .onChange(of: prefs.face) { _, _ in faceTagAt = .now }
        .background {
            Button("") { hub.send(.previousFace) }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.nextFace) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.zoomIn) }.keyboardShortcut("+", modifiers: []).opacity(0)
            Button("") { hub.send(.zoomIn) }.keyboardShortcut("=", modifiers: []).opacity(0)
            Button("") { hub.send(.zoomOut) }.keyboardShortcut("-", modifiers: []).opacity(0)
        }
    }

    private func revealControls() {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, engine.phase == .riding else { return }
            withAnimation(.easeIn(duration: 0.4)) { controlsVisible = false }
        }
    }
}

struct GearLadder: View {
    let gear: Int
    var count: Int = Gears.count
    var color: Color = Design.Palette.primary

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 5
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(1...count, id: \.self) { g in
                    RoundedRectangle(cornerRadius: width / 2)
                        .fill(g == gear ? color : Design.Palette.hairline)
                        .frame(width: min(width, 6), height: g == gear ? geo.size.height : geo.size.height * 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: gear)
        }
        .frame(maxWidth: 520)
        .accessibilityLabel("Gear \(gear) of \(count)")
    }
}

// MARK: - Overlays

private struct ConnectionDots: View {
    let hub: DeviceHub

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(hub.ride.link.dotColor).frame(width: 8, height: 8)
            Circle().fill(hub.trainer.link.dotColor).frame(width: 8, height: 8)
        }
        .accessibilityLabel("Controller \(hub.ride.link.label), trainer \(hub.trainer.link.label)")
    }
}

/// Leave the ride screen. Before the first pedal stroke it just goes back; after, it asks and saves.
private struct CloseButton: View {
    let engine: SessionEngine
    let visible: Bool
    @State private var confirm = false

    var body: some View {
        Button {
            if engine.clockStarted { confirm = true } else { engine.handle(.endSession) }
        } label: {
            Icon("x", size: 22)
                .foregroundStyle(Design.Palette.primary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityLabel(engine.clockStarted ? "End ride" : "Back")
        .keyboardShortcut(.escape, modifiers: [])
        .confirmationDialog("End ride?", isPresented: $confirm, titleVisibility: .visible) {
            Button("End and review") { engine.handle(.endSession) }
            Button("Keep riding", role: .cancel) {}
        }
    }
}

private struct DonePrompt: View {
    let engine: SessionEngine
    /// On faces, the face's own "ride complete" screen is showing: only add the two choices below it.
    var minimal = false

    var body: some View {
        if minimal {
            buttons
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 170)
        } else {
            VStack(spacing: Design.Space.gutter) {
                Text("0:00").font(Design.Font.number(72)).foregroundStyle(Design.Palette.primary)
                buttons
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 28).fill(Design.Palette.background).shadow(color: .black.opacity(0.08), radius: 30))
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { engine.continueAfterDone() } label: {
                Text("Keep riding").font(Design.Font.label).frame(minWidth: 150, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
            }
            Button { engine.finish() } label: {
                Text("Finish").font(Design.Font.label).foregroundStyle(Design.Palette.background)
                    .frame(minWidth: 150, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.primary))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Design.Palette.primary)
    }
}

private struct OnScreenControls: View {
    let engine: SessionEngine
    let hub: DeviceHub
    let pip: PiPOverlay
    let visible: Bool
    @State private var confirmEnd = false

    var body: some View {
        HStack(spacing: 14) {
            RoundIconButton(icon: "minus") { hub.send(.shiftDown) }
                .keyboardShortcut("[", modifiers: [])
            RoundIconButton(icon: "plus") { hub.send(.shiftUp) }
                .keyboardShortcut("]", modifiers: [])
            Spacer().frame(width: 20)
            RoundIconButton(icon: "chevron-down") { hub.send(.gradeDown) }
                .keyboardShortcut(.downArrow, modifiers: [])
            RoundIconButton(icon: "chevron-up") { hub.send(.gradeUp) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Spacer().frame(width: 20)
            RoundIconButton(icon: engine.isPaused ? "play" : "pause") { hub.send(.pauseToggle) }
                .keyboardShortcut(.space, modifiers: [])
            RoundIconButton(icon: "flag") { confirmEnd = true }
                .keyboardShortcut("e", modifiers: [])
            if PiPOverlay.isSupported {
                Spacer().frame(width: 20)
                RoundIconButton(icon: "picture-in-picture-2") { pip.toggle() }
                    .accessibilityLabel("Floating window")
            }
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .confirmationDialog("End ride?", isPresented: $confirmEnd) {
            Button("End ride") { hub.send(.endSession) }
        }
        .background {
            // Hidden shortcut for theme (keyboard only).
            Button("") { hub.send(.toggleTheme) }.keyboardShortcut("t", modifiers: []).opacity(0)
        }
    }
}

extension LinkState {
    var dotColor: Color {
        switch self {
        case .ready: Design.Palette.secondary
        case .connecting, .searching: .orange
        case .unpaired, .bluetoothOff: .red
        }
    }
}
