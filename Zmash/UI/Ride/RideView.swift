import SwiftUI
import ZmashKit

/// The ride screen (brief §10): one hero number, five quiet ones, gear ladder and grade.
struct RideView: View {
    let engine: SessionEngine
    let hub: DeviceHub
    let pip: PiPOverlay
    @Environment(Preferences.self) private var prefs
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = false
    @State private var hideTask: Task<Void, Never>?
    @State private var faceTagAt: Date?
    @State private var confirmEnd = false

    var body: some View {
        GeometryReader { geo in
            // Narrow (Split View, an iPhone upright): the compact dashboard. Wide enough (an iPhone on its side
            // included), a face.
            let compact = geo.size.width < 700
            // Split View / Slide Over and the Classic face use the customisable dashboard.
            let classic = compact || prefs.face == .classic
            // Built once per frame and shared by the face and the band.
            let data = rideData
            let band = RideBand.shows(data, profile: prefs.courseStrip && !(classic && compact))
            let bandHeight = band ? RideBand.height(dense: verticalSizeClass == .compact) : 0
            ZStack {
                // PiP source layer: must be in the view hierarchy; it sits behind the opaque background.
                PiPLayerHost(layer: pip.displayLayer)
                if classic {
                    Design.Tarmac.t900.ignoresSafeArea()
                    // Classic gets the band too; in Split View it keeps the plan but drops the profile, where every
                    // point of height counts.
                    VStack(spacing: 0) {
                        RideDashboard(readout: RideReadout(engine: engine), config: prefs.display, units: prefs.units,
                                      size: CGSize(width: geo.size.width, height: geo.size.height - bandHeight),
                                      compact: compact, plan: data.plan, riderKg: prefs.riderKg, paused: engine.isPaused,
                                      actions: LiveRideActions(pause: { hub.send(.pauseToggle) },
                                                               end: { if engine.clockStarted { confirmEnd = true } else { engine.handle(.endSession) } },
                                                               shiftDown: { hub.send(.shiftDown) }, shiftUp: { hub.send(.shiftUp) }))
                        .opacity(engine.isPaused ? 0.55 : 1)
                        .animation(.easeInOut(duration: 0.3), value: engine.isPaused)
                        if band {
                            RideBand(data: data, showProfile: prefs.courseStrip && !compact,
                                     zoom: Binding(get: { prefs.courseZoom }, set: { prefs.courseZoom = $0 }))
                        }
                    }
                } else {
                    FaceView(face: prefs.face, data: data,
                             dark: scheme == .dark, calm: prefs.faceMotion == .calm || reduceMotion,
                             style: prefs.style(prefs.face))
                        .ignoresSafeArea()
                        .id(prefs.face)
                        .transition(.opacity)
                }

                // The band carries the connection dots; without one, they only appear when something's wrong.
                if !band, !(hub.ride.link.isReady && hub.trainer.link.isReady) {
                    ConnectionDots(hub: hub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(Design.Space.gutter)
                }

                FaceNameTag(name: prefs.face.name, shownAt: faceTagAt)

                if let error = pip.lastError {
                    Text(error)
                        .font(Design.Font.small)
                        .foregroundStyle(Design.Palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, bandHeight + 96)
                }

                if classic {
                    if engine.isPaused {
                        Icon("pause", size: 72).foregroundStyle(Design.Tarmac.bone)
                    }
                }

                if engine.timedDone {
                    DonePrompt(engine: engine, minimal: !classic)
                }

                if let since = hub.endHoldSince {
                    EndHoldRing(since: since)
                }

                // Above every overlay (pause, done) so there's always a way out.
                RideControlsPanel(engine: engine, hub: hub, pip: pip, visible: controlsVisible || !engine.clockStarted,
                                  narrow: geo.size.width < 760, touched: { revealControls() },
                                  close: { withAnimation(.snappy(duration: 0.3)) { controlsVisible = false } })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .animation(.linear(duration: 0.3), value: prefs.face)
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
            // Swipe left or right to change face, like the D-pad.
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 1.5 else { return }
                hub.send(dx < 0 ? .nextFace : .previousFace)
            })
        }
        .confirmationDialog("End ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
            EndRideChoices(engine: engine)
        } message: {
            Text("Stop session saves the ride and goes straight home, without the review.")
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: engine.controlsRequests) { _, _ in toggleControls() }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "ZmashShowControls") { revealControls() }
            if UserDefaults.standard.bool(forKey: "ZmashHoldRing") { hub.debugHold() }
        }
        #endif
        .onChange(of: prefs.face) { _, _ in faceTagAt = .now }
        .background {
            Button("") { hub.send(.previousFace) }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.nextFace) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.zoomIn) }.keyboardShortcut("+", modifiers: []).opacity(0)
            Button("") { hub.send(.zoomIn) }.keyboardShortcut("=", modifiers: []).opacity(0)
            Button("") { hub.send(.zoomOut) }.keyboardShortcut("-", modifiers: []).opacity(0)
        }
    }

    private var rideData: FaceData {
        var data = FaceData(engine: engine, units: prefs.units)
        data.plan.links = [hub.ride.link, hub.trainer.link]
        return data
    }

    /// Shows the panel and (re)starts its 8 s timer.
    private func revealControls() {
        withAnimation(.snappy(duration: 0.3)) { controlsVisible = true }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, engine.phase == .riding else { return }
            withAnimation(.snappy(duration: 0.35)) { controlsVisible = false }
        }
    }

    private func toggleControls() {
        if controlsVisible {
            hideTask?.cancel()
            withAnimation(.snappy(duration: 0.3)) { controlsVisible = false }
        } else {
            revealControls()
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

/// The choices when ending a ride: review it, stop straight away, or carry on.
private struct EndRideChoices: View {
    let engine: SessionEngine

    var body: some View {
        Button("End and review") { engine.handle(.endSession) }
        Button("Stop session") { engine.stop() }
        Button("Keep riding", role: .cancel) {}
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
                Text("Time's up").monoLabel().foregroundStyle(Design.Tarmac.bone2)
                Text("0:00").font(Design.Font.bib(96)).foregroundStyle(Design.Accent.vermilion)
                buttons
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.xl).fill(Design.Tarmac.t850)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.xl).strokeBorder(Design.Tarmac.t750, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 30)
            )
            .environment(\.colorScheme, .dark)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            PillButton(title: "Keep riding", style: .glass) { engine.continueAfterDone() }
            PillButton(title: "Finish", icon: "flag", style: .primary) { engine.finish() }
        }
    }
}

/// The ride's controls as a panel that slides up from the bottom (D108): gears, gradient, pause, the floating window,
/// and end. It opens with the controller's A button or a tap, closes the same way, with a swipe down, or after
/// 8 s without a touch, and stays up before the first pedal stroke so there's always a way out.
private struct RideControlsPanel: View {
    let engine: SessionEngine
    let hub: DeviceHub
    let pip: PiPOverlay
    let visible: Bool
    let narrow: Bool
    /// Any touch in the panel: keeps it up a while longer.
    let touched: () -> Void
    let close: () -> Void
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Design.Tarmac.t700).frame(width: 40, height: 5)
                .accessibilityHidden(true)
            if narrow {
                VStack(spacing: 14) {
                    HStack(spacing: 22) { gears; grade }
                    HStack(spacing: 14) { session }
                }
            } else {
                HStack(spacing: 30) {
                    gears
                    grade
                    Spacer(minLength: 0)
                    session
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 22)
        .frame(maxWidth: 980)
        .frame(maxWidth: .infinity)
        .background(
            // A tarmac sheet whatever the face or theme: xl corners, a hairline, the sheet shadow.
            UnevenRoundedRectangle(topLeadingRadius: Design.Radius.xl, topTrailingRadius: Design.Radius.xl)
                .fill(Design.Tarmac.t850)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: Design.Radius.xl, topTrailingRadius: Design.Radius.xl)
                    .stroke(Design.Tarmac.t750, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 30, y: -10)
                .ignoresSafeArea(edges: .bottom)
        )
        .environment(\.colorScheme, .dark)
        .environment(\.onTarmac, true)
        .buttonSize(narrow ? 52 : 58)
        .offset(y: visible ? 0 : 420)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height > 40 { close() }
        })
        .simultaneousGesture(TapGesture().onEnded { touched() })
        .confirmationDialog("End ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
            EndRideChoices(engine: engine)
        } message: {
            Text("Stop session saves the ride and goes straight home, without the review.")
        }
        .background {
            // Keyboard shortcuts work whether the panel is up or not.
            Button("") { hub.send(.shiftDown) }.keyboardShortcut("[", modifiers: []).opacity(0)
            Button("") { hub.send(.shiftUp) }.keyboardShortcut("]", modifiers: []).opacity(0)
            Button("") { hub.send(.gradeDown) }.keyboardShortcut(.downArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.gradeUp) }.keyboardShortcut(.upArrow, modifiers: []).opacity(0)
            Button("") { hub.send(.pauseToggle) }.keyboardShortcut(.space, modifiers: []).opacity(0)
            Button("") { endTapped() }.keyboardShortcut("e", modifiers: []).opacity(0)
            Button("") { endTapped() }.keyboardShortcut(.escape, modifiers: []).opacity(0)
            Button("") { hub.send(.toggleTheme) }.keyboardShortcut("t", modifiers: []).opacity(0)
        }
    }

    private var gears: some View {
        group("Gear", value: "\(engine.controls.gear)/\(engine.controls.gears.count)") {
            RoundIconButton(icon: "minus") { hub.send(.shiftDown); touched() }.accessibilityLabel("Easier gear")
            RoundIconButton(icon: "plus", accent: true) { hub.send(.shiftUp); touched() }.accessibilityLabel("Harder gear")
        }
    }

    private var grade: some View {
        group(engine.workout == nil && engine.route == nil && engine.controls.mode == .manual ? "Gradient" : "Gradient bias",
              value: String(format: "%+.1f %%", engine.terrainGrade)) {
            RoundIconButton(icon: "chevron-down") { hub.send(.gradeDown); touched() }.accessibilityLabel("Gradient down")
            RoundIconButton(icon: "chevron-up") { hub.send(.gradeUp); touched() }.accessibilityLabel("Gradient up")
        }
    }

    @ViewBuilder private var session: some View {
        labelled(engine.isPaused ? "Resume" : "Pause") {
            RoundIconButton(icon: engine.isPaused ? "play" : "pause") { hub.send(.pauseToggle); touched() }
        }
        .disabled(!engine.clockStarted)
        if PiPOverlay.isSupported {
            labelled("Float") {
                RoundIconButton(icon: "picture-in-picture-2") { pip.toggle(); touched() }.accessibilityLabel("Floating window")
            }
        }
        labelled(engine.clockStarted ? "End" : "Back") {
            RoundIconButton(icon: engine.clockStarted ? "flag" : "x") { endTapped() }
                .accessibilityLabel(engine.clockStarted ? "End ride" : "Back")
        }
        labelled("Hide") {
            RoundIconButton(icon: "chevron-down") { close() }.accessibilityLabel("Hide controls")
        }
    }

    /// Before the first pedal stroke there's nothing to save: just go back.
    private func endTapped() {
        if engine.clockStarted { confirmEnd = true } else { engine.handle(.endSession) }
    }

    private func group(_ title: String, value: String, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) { buttons() }
            HStack(spacing: 6) {
                Text(title).monoLabel(10).foregroundStyle(Design.Tarmac.stone)
                Text(value).font(Design.Font.mono(12, weight: 700)).foregroundStyle(Design.Tarmac.bone)
            }
        }
    }

    private func labelled(_ title: String, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: 6) {
            button()
            Text(title).monoLabel(10).foregroundStyle(Design.Tarmac.stone)
        }
    }
}

/// Holding the end button: a circle that fills clockwise over the hold, and the ride ends when it's full (D108).
private struct EndHoldRing: View {
    let since: Date

    var body: some View {
        TimelineView(.animation) { t in
            let progress = min(max(t.date.timeIntervalSince(since) / RideInputMapper.endHoldDuration, 0), 1)
            ZStack {
                Circle().stroke(Design.Tarmac.t700, lineWidth: 10)
                Circle().trim(from: 0, to: progress)
                    .stroke(Design.Accent.vermilion, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Icon("square", size: 22)
                    Text("Hold to end").monoLabel(10)
                }
                .foregroundStyle(Design.Tarmac.bone)
            }
            .frame(width: 130, height: 130)
            .padding(24)
            .background {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Design.Tarmac.glass)
            }
            .environment(\.colorScheme, .dark)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Hold to end the ride")
    }
}

extension LinkState {
    var dotColor: Color {
        switch self {
        case .ready: Design.Status.go
        case .connecting, .searching: Design.Status.caution
        case .unpaired, .bluetoothOff: Design.Status.stop
        }
    }
}
