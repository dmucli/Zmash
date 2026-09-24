import SwiftData
import SwiftUI
import ZmashKit

@main
struct ZmashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub = DeviceHub()
    @State private var prefs = Preferences.shared

    init() {
        Design.applyAppearance()
        #if DEBUG
        // Before any view reads it: home picks up the last plan when it's first built.
        if let plan = DebugLaunch.homePlan { Preferences.shared.lastPlan = plan }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if let width = DebugLaunch.compactWidth {
            content
                .environment(\.horizontalSizeClass, .compact)
                .frame(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.3))
        } else if DebugLaunch.landscapePreview {
            GeometryReader { geo in
                content
                    // A turned phone is short: say so, as a real rotation would.
                    .environment(\.verticalSizeClass, geo.size.width < 500 ? .compact : .regular)
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(-90))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .ignoresSafeArea()
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        RootView(hub: hub)
                .environment(prefs)
                .modelContainer(RideStore.container)
                .tint(Design.Accent.vermilion) // no system blue or green: the system's one accent
                .preferredColorScheme(prefs.theme == .system ? nil : prefs.theme == .dark ? .dark : .light)
    }
}

/// setup ⇄ ride → summary. History and settings open from setup only.
struct RootView: View {
    let hub: DeviceHub
    @Environment(Preferences.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase

    @State private var engine: SessionEngine?
    @State private var finished: FinishedRide?
    @State private var recoverable: RideSession?
    @State private var storeRecovered = false
    /// The setup flow was opened from Settings rather than on first launch.
    @State private var setupAgain = false
    @State private var sheet: Sheet?
    @State private var showProbe = false
    @State private var showFaces = false
    @State private var showSetup = false
    @State private var pip = PiPOverlay()
    @State private var idleDisconnect: Task<Void, Never>?
    @State private var watchLoop: Task<Void, Never>?

    enum Sheet: String, Identifiable {
        case history, settings, devices, riders
        case display, buttons, routes, workouts, race, stage, climb, recap, campaign, plan, builder // debug entry points for screenshots
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if let engine {
                RideView(engine: engine, hub: hub, pip: pip)
                    .transition(.opacity)
            } else {
                SetupView(hub: hub, start: start,
                          openHistory: { sheet = .history },
                          openSettings: { sheet = .settings },
                          openRiders: { sheet = .riders },
                          openDevices: { sheet = .devices })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: engine == nil)
        .sheet(item: $sheet) { which in
            if which == .routes {
                #if DEBUG
                RoutePicker(routeID: .constant(nil))
                    .environment(prefs)
                    .presentationSizing(.page)
                #endif
            } else if which == .workouts {
                #if DEBUG
                WorkoutPicker(workoutID: .constant("threshold-4x8"))
                    .environment(prefs)
                    .presentationSizing(.page)
                #endif
            } else if which == .builder {
                #if DEBUG
                WorkoutBuilder(editing: WorkoutLibrary.all.first { $0.id == "threshold-4x8" }) { _ in }.environment(prefs)
                    .presentationSizing(.page)
                #endif
            } else if which == .recap {
                #if DEBUG
                if let s = Recaps.summary(Recap.previousMonth(of: .now)) {
                    RecapSheet(summary: s, yearly: false).environment(prefs)
                }
                #endif
            } else {
            NavigationStack {
                switch which {
                case .history:
                    HistoryView(rideAgain: { plan in
                        sheet = nil
                        start(plan)
                    })
                    .toolbar { closeButton }
                case .settings:
                    SettingsView(hub: hub, openFaces: {
                        sheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            showFaces = true
                        }
                    }, openProbe: {
                        sheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450)) // let the sheet finish dismissing
                            showProbe = true
                        }
                    })
                    .toolbar { closeButton }
                case .devices:
                    DevicesView(hub: hub).toolbar { closeButton }
                case .riders:
                    RidersView().toolbar { closeButton }
                case .display:
                    FaceStyleEditor(face: .classic).toolbar { closeButton }
                case .buttons:
                    ButtonMapView().toolbar { closeButton }
                case .routes, .workouts, .recap, .builder:
                    EmptyView()
                case .climb:
                    #if DEBUG
                    // -ZmashScreen climb -ZmashRoute climb/mont-ventoux-bedoin
                    if let climb = RaceStore.climb(id: UserDefaults.standard.string(forKey: "ZmashRoute") ?? "") ?? RaceStore.climbs.first {
                        StageView(climb: climb, choose: { _ in sheet = nil }).toolbar { closeButton }
                    }
                    #endif
                case .plan:
                    #if DEBUG
                    if let plan = TrainingPlans.plan(id: DebugLaunch.plan) {
                        PlanView(plan: plan) { sheet = nil }.toolbar { closeButton }
                    }
                    #endif
                case .campaign:
                    #if DEBUG
                    if let race = RaceStore.races.first(where: { $0.id == DebugLaunch.race }) {
                        CampaignView(race: race, choose: { _ in sheet = nil }).toolbar { closeButton }
                    }
                    #endif
                case .race, .stage:
                    #if DEBUG
                    if let race = RaceStore.races.first(where: { $0.id == DebugLaunch.race }) {
                        if which == .stage, let stage = race.stages.first(where: { $0.number == DebugLaunch.stage }) ?? race.stages.first {
                            StageView(race: race, stage: stage, choose: { _ in sheet = nil }).toolbar { closeButton }
                        } else {
                            RaceView(race: race, choose: { _ in sheet = nil }).toolbar { closeButton }
                        }
                    }
                    #endif
                }
            }
            .environment(prefs)
            .modelContainer(RideStore.container)
            .presentationSizing(.page)
            }
        }
        .fullScreenCover(item: $finished) { ride in
            SummaryView(ride: ride) { finished = nil }
                .environment(prefs)
        }
        .fullScreenCover(isPresented: $showSetup) {
            SetupFlow(hub: hub, done: { showSetup = false }, canClose: setupAgain)
                .environment(prefs)
        }
        .onChange(of: prefs.hasCompletedSetup) { _, done in
            // "Set up again" in Settings: close the sheet first, then open the flow.
            guard !done else { return }
            setupAgain = true
            sheet = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                showSetup = true
            }
        }
        .fullScreenCover(isPresented: $showFaces) {
            FaceGalleryView(close: { showFaces = false })
                .environment(prefs)
        }
        .fullScreenCover(isPresented: $showProbe) {
            ProbeView(onClose: { showProbe = false })
                // The probe opens its own Bluetooth connections; release ours meanwhile.
                .onAppear { hub.ble?.suspend() }
                .onDisappear { hub.ble?.resume() }
        }
        .alert("Your rides couldn't be opened", isPresented: $storeRecovered) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Zmash started a new ride history. The old one was kept in Files → On My \(UIDevice.current.model) → Zmash → \(RideStore.recoveredFolder?.lastPathComponent ?? "Recovered rides"), with the diagnostics log to explain why.")
        }
        .alert("Unfinished ride", isPresented: Binding(get: { recoverable != nil }, set: { if !$0 { recoverable = nil } })) {
            Button("Recover") {
                finished = recoverable?.finished
                recoverable = nil
            }
            Button("Discard", role: .destructive) {
                if let r = recoverable { RideStore.delete(r) }
                recoverable = nil
            }
        } message: {
            if let r = recoverable {
                Text("\(TimeFormat.clock(r.activeSeconds)) on \(r.startedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .onAppear {
            WatchLink.shared.setUp()
            if engine == nil {
                recoverable = RideStore.unfinished()
                RideActivity.shared.endLeftovers()
            }
            UploadCenter.shared.startRetrying()
            // The race catalog (about 1 MB of JSON) loads off the main thread, before home first asks for it.
            Task.detached(priority: .userInitiated) {
                let loaded = !RaceStore.races.isEmpty
                if !loaded { await Diagnostics.log("races", "the race catalog didn't load") }
            }
            if RideStore.recoveredFolder != nil {
                // An alert presented during the first appear is dropped: a moment later.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    storeRecovered = true
                }
            }
            showSetup = !prefs.hasCompletedSetup
            #if DEBUG
            // Screenshot runs skip it, unless it's what they're for.
            if DebugLaunch.scripted { showSetup = DebugLaunch.screen == "setup" }
            #endif
            #if DEBUG
            DebugLaunch.addRiderIfRequested(prefs)
            DebugLaunch.seedHistoryIfRequested()
            DebugLaunch.backupCheckIfRequested()
            DebugLaunch.seedRouteAttemptIfRequested()
            DebugLaunch.seedCampaignIfRequested()
            DebugLaunch.enrolPlanIfRequested()
            DebugLaunch.applyPaletteIfRequested(prefs)
            // Screenshot runs kill the app mid-ride; their leftovers shouldn't greet the next run.
            if DebugLaunch.scripted, let r = recoverable { RideStore.delete(r); recoverable = nil }
            if let plan = DebugLaunch.autostart {
                start(plan)
                if DebugLaunch.startPiP {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(8))
                        pip.toggle()
                    }
                }
                if let after = DebugLaunch.endAfter {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(after))
                        engine?.finish()
                    }
                }
            }
            if let face = DebugLaunch.face { prefs.face = face }
            if let screen = DebugLaunch.screen {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600)) // presenting during the first appear is dropped
                    if screen == "faces" { showFaces = true } else { sheet = Sheet(rawValue: screen) }
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                engine?.autosaveNow()
                pip.refresh()
            }
            // Brief §11: backgrounded while not riding (or paused) for 10 min → release the devices
            // to save their batteries; reconnect on return.
            idleDisconnect?.cancel()
            if phase == .background {
                idleDisconnect = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(600))
                    guard !Task.isCancelled, engine == nil || engine?.isPaused == true else { return }
                    hub.ble?.suspend()
                }
            } else if phase == .active, !showProbe {
                hub.ble?.resume()
            }
            if phase == .active { Task { await UploadCenter.shared.retryDue() } }
        }
        // Siri and Shortcuts (D100).
        // `initial`: on a cold launch, Siri's request can arrive before this view first draws.
        .onChange(of: IntentRouter.shared.pending, initial: true) { _, action in
            guard let action else { return }
            IntentRouter.shared.pending = nil
            switch action {
            case .ride(let plan):
                guard engine == nil else { return }
                sheet = nil
                prefs.lastPlan = plan
                Task { @MainActor in
                    // Opened cold by Siri, the trainer is still connecting: give it a moment.
                    for _ in 0..<40 where !(hub.isDemo || hub.trainer.link == .ready) {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard engine == nil else { return }
                    if hub.isDemo || hub.trainer.link == .ready {
                        start(plan)
                    } else {
                        // No trainer: set the ride up on home, where Start says what's missing.
                        IntentRouter.shared.prepared = plan
                    }
                }
            case .endRide:
                engine?.handle(.endSession)
            }
        }
        .onChange(of: engine == nil, initial: true) { _, idle in
            // Keep the screen on only while a ride is live.
            UIApplication.shared.isIdleTimerDisabled = !idle
            IntentRouter.shared.riding = !idle
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { sheet = nil } label: { Icon("x", size: 20) }
                .accessibilityLabel("Close")
        }
    }

    private func start(_ plan: SessionPlan) {
        let e = SessionEngine(plan: plan, hub: hub)
        e.onFinish = { [weak e] ride in
            RideActivity.shared.end(engine: e, units: prefs.units)
            // The Watch keeps its own workout unless this ride can really go to Health from here.
            WatchLink.shared.rideEnded(savedToHealth: prefs.saveToHealth && HealthExport.canSave)
            watchLoop?.cancel()
            pip.deactivate()
            engine = nil
            if e?.skipReview == true {
                RideSaver.saveWithoutReview(ride, prefs: prefs)
            } else {
                finished = ride
            }
        }
        e.onCancel = {
            RideActivity.shared.end(engine: nil, units: prefs.units)
            WatchLink.shared.rideEnded(savedToHealth: true)
            watchLoop?.cancel()
            pip.deactivate()
            engine = nil
        }
        e.onToggleTheme = { prefs.toggleTheme() }
        e.onCycleFace = { prefs.cycleFace($0) }
        e.onZoom = { prefs.courseZoom = prefs.courseZoom.step($0) }
        engine = e
        e.start()
        pip.activate(engine: e, units: prefs.units, autoStart: prefs.pipOnLeave)
        RideActivity.shared.start(engine: e, units: prefs.units)
        WatchLink.shared.rideStarted()
        // The ride on the wrist, once a second.
        watchLoop = Task { @MainActor [weak e] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let e else { return }
                WatchLink.shared.send(WatchMessage.Ride(
                    title: e.route?.name ?? e.workout?.name ?? "Free ride", powerW: e.powerW ?? 0, elapsed: Int(e.elapsed),
                    gear: "\(e.controls.gear)/\(e.controls.gears.count)", gradePercent: e.terrainGrade.displayGrade,
                    paused: e.isPaused || !e.clockStarted))
            }
        }
    }
}
