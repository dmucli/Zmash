import SwiftUI
import ZmashKit

/// Home, after the design system's prototype (D115): the top bar (what's connected, who's riding), a greeting with the
/// week so far, today's suggestion as the hero card beside the three ways to ride, the ride's options and preview,
/// and a Start bar that never scrolls away.
struct SetupView: View {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let openHistory: () -> Void
    let openSettings: () -> Void
    let openDevices: () -> Void

    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan = Preferences.shared.lastPlan
    @State private var pickingWorkout = false
    @State private var pickingRoute = false

    /// A ride is one of three things: free (duration + terrain), a workout, or a route.
    enum PlanMode { case free, workout, route }

    private var mode: PlanMode { plan.workoutID != nil ? .workout : plan.routeID != nil ? .route : .free }

    /// Free-ride terrain: set by hand as you ride, generated, or drawn with a finger.
    enum TerrainChoice { case manual, auto, draw }

    private var terrain: TerrainChoice {
        plan.terrainMode == .manual ? .manual : plan.isDrawn ? .draw : .auto
    }

    private func select(_ terrain: TerrainChoice) {
        switch terrain {
        case .manual:
            plan.terrainMode = .manual
        case .auto:
            plan.terrainMode = .auto
            plan.drawn = false
        case .draw:
            plan.terrainMode = .auto
            plan.drawn = true
            if plan.drawing == nil { plan.drawing = DrawnCourse.starter }
        }
    }

    private func select(_ mode: PlanMode) {
        switch mode {
        case .free:
            plan.workoutID = nil
            plan.routeID = nil
        case .workout:
            plan.routeID = nil
            if plan.workoutID == nil { pickingWorkout = true }
        case .route:
            plan.workoutID = nil
            if plan.routeID == nil { pickingRoute = true }
        }
    }

    private var targetsNote: String {
        if plan.usesERG {
            return hub.trainer.supportsERG
                ? "The trainer holds each target whatever gear you're in; the shifters change the intensity."
                : "This trainer can't hold a target, so the targets become gradients."
        }
        return "Each target becomes a gradient. You hold the power yourself, shifting as you would on a climb."
    }

    @AppStorage("today.hidden") private var todayHiddenOn = ""
    @State private var week: WidgetSummary?

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 700
            let wide = geo.size.width >= 1000
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 20 : 26) {
                    HomeTopBar(devices: deviceItems, compact: compact, narrow: !wide, openHistory: openHistory, openDevices: openDevices,
                               openSettings: openSettings, manageRiders: openSettings)
                    greeting(compact: compact)
                    RecapBanner()
                    rides(compact: compact, wide: wide)
                    // Side by side needs room for the options and a preview wide enough for its figures.
                    rideSetup(compact: compact, stacked: !wide)
                }
                .frame(maxWidth: Design.Space.column + 140, alignment: .leading)
                .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
                .padding(.top, 5)
                .padding(.bottom, Design.Space.block)
                .frame(maxWidth: .infinity)
                .animation(Design.Motion.base, value: plan.terrainMode)
                .animation(Design.Motion.base, value: plan.drawn)
                .animation(Design.Motion.base, value: plan.workoutID)
                .animation(Design.Motion.base, value: plan.routeID)
                .animation(Design.Motion.base, value: todayHiddenOn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StartBar(index: modeIndex, title: summaryTitle, detail: trainerReady ? summaryDetail : "Connect a trainer to start",
                         ready: trainerReady, compact: compact,
                         start: {
                             prefs.lastPlan = plan
                             start(plan)
                         },
                         connect: openDevices)
            }
            .screenBackground()
        }
        .sheet(isPresented: $pickingWorkout) { WorkoutPicker(workoutID: $plan.workoutID) }
        .sheet(isPresented: $pickingRoute) { RoutePicker(routeID: $plan.routeID) }
        .onChange(of: IntentRouter.shared.prepared) { _, prepared in
            // Set up by Siri while the trainer wasn't connected.
            guard let prepared else { return }
            withAnimation(Design.Motion.base) { plan = prepared }
            IntentRouter.shared.prepared = nil
        }
        .task(id: prefs.riderID) {
            WidgetBridge.refresh(prefs: prefs)
            week = WidgetBridge.summary(prefs: prefs)
        }
        .onAppear {
            // The last plan may point at a workout or route that has since been deleted.
            if plan.workoutID != nil, plan.workout == nil { plan.workoutID = nil }
            if plan.routeID != nil, plan.route == nil { plan.routeID = nil }
        }
    }

    // MARK: Greeting

    private func greeting(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateLine).monoLabel(12).foregroundStyle(Design.Palette.fg3)
                Text("Ready when you are, \(firstName).")
                    .textStyle(.display, size: compact ? 30 : 48)
                    .foregroundStyle(Design.Palette.fg1)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact, let week, week.weekRides > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("This week").monoLabel().foregroundStyle(Design.Palette.fg3)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(week.weekRides)").font(Design.Font.bib(28)).foregroundStyle(Design.Palette.fg1)
                        Text(week.weekRides == 1 ? "ride ·" : "rides ·")
                        Text(String(format: "%d:%02d", week.weekSeconds / 3600, week.weekSeconds % 3600 / 60)).font(Design.Font.bib(28)).foregroundStyle(Design.Palette.fg1)
                        Text("h")
                    }
                    .font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fg3)
                }
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var dateLine: String {
        let now = Date.now
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: now)
        return now.formatted(.dateTime.weekday(.wide)) + " · Week \(week)"
    }

    private var firstName: String {
        prefs.currentRider.name.split(separator: " ").first.map(String.init) ?? prefs.currentRider.name
    }

    // MARK: Connections

    private var trainerReady: Bool { hub.trainer.link == .ready }

    private var deviceItems: [DevicePill.Item] {
        let t = trainerStatus, c = controllerStatus, h = heartStatus
        return [.init(label: "Trainer", status: t.text, dot: t.dot), .init(label: "Controller", status: c.text, dot: c.dot),
                .init(label: "Heart", status: h.text, dot: h.dot)]
    }

    private var trainerStatus: (text: String, dot: Color) {
        if hub.isDemo { return ("Demo", Self.ok) }
        let link = hub.trainer.link
        if prefs.basicTrainer != nil { return (link == .ready ? "Basic · speed sensor" : "Basic · " + link.label.lowercased(), link == .ready ? Self.ok : link.color) }
        guard link == .ready else { return (link.label, link.color) }
        return ("Connected · " + (hub.trainer.activeProtocol?.name ?? "FTMS"), Self.ok)
    }

    private var controllerStatus: (text: String, dot: Color) {
        if hub.isDemo { return ("Demo", Self.ok) }
        let link = hub.ride.link
        guard link == .ready else { return (link.label, link.color) }
        guard let battery = hub.ride.batteryPercent else { return ("Connected", Self.ok) }
        return battery < 15 ? ("Battery \(battery) %", Design.Status.caution) : ("Connected · \(battery) %", Self.ok)
    }

    private var heartStatus: (text: String, dot: Color) {
        if let bpm = hub.heartRateBpm { return ("\(bpm) bpm", Self.ok) }
        if let strap = hub.ble?.heartRate, strap.link != .unpaired { return (strap.link.label, strap.link.color) }
        return ("Not set up", Design.Palette.fgGhost)
    }

    private static var ok: Color { Design.Status.go }

    // MARK: Today and the three ways to ride

    private var todayShown: Bool { todayHiddenOn != TodayCard.dayKey(.now) }

    @ViewBuilder
    private func rides(compact: Bool, wide: Bool) -> some View {
        let today = TodayCard(choose: { suggested in withAnimation(Design.Motion.base) { plan = suggested } }, compact: compact)
        if compact {
            VStack(spacing: Design.Space.gap) {
                today
                HStack(spacing: 10) { modeCards(compact: true) }.fixedSize(horizontal: false, vertical: true)
            }
        } else if todayShown {
            HStack(alignment: .top, spacing: 16) {
                today.frame(maxWidth: .infinity)
                VStack(spacing: Design.Space.gap) { modeCards(compact: false) }
                    .frame(width: wide ? 380 : 300)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: Design.Space.gap) { modeCards(compact: false) }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func modeCards(compact: Bool) -> some View {
        ModeCard(index: 2, kind: "Free ride", title: compact ? "Free ride" : freeTitle, detail: freeDetail,
                 selected: mode == .free, compact: compact, action: { withAnimation(Design.Motion.base) { select(.free) } }) {
            LaneDashes(color: Design.Palette.fg1, thickness: 4).padding(.top, compact ? 4 : 16)
        }
        ModeCard(index: 3, kind: "Workout", title: compact ? "Workout" : plan.workout?.name ?? "Structured sessions",
                 detail: workoutDetail, selected: mode == .workout, compact: compact,
                 action: { if mode == .workout { pickingWorkout = true } else { withAnimation(Design.Motion.base) { select(.workout) } } }) {
            if let w = plan.workout ?? Self.sampleWorkout {
                WorkoutStrip(workout: w.drawable).frame(height: compact ? 22 : 40)
                    .opacity(plan.workout == nil ? 0.35 : 1)
            }
        }
        ModeCard(index: 4, kind: "Route", title: compact ? "Route" : plan.route?.name ?? "Real climbs and stages",
                 detail: routeDetail, selected: mode == .route, compact: compact,
                 action: { if mode == .route { pickingRoute = true } else { withAnimation(Design.Motion.base) { select(.route) } } }) {
            if let r = plan.route ?? Self.sampleRoute {
                RouteStrip(route: r).frame(height: compact ? 22 : 40)
                    .opacity(plan.route == nil ? 0.35 : 1)
            }
        }
    }

    /// What the workout and route cards show before one is chosen: an interval session and a real mountain.
    private static let sampleWorkout = WorkoutLibrary.all.max { $0.steps.count < $1.steps.count }
    @MainActor private static let sampleRoute = RaceStore.climbs.first { $0.name.contains("Ventoux") }?.route ?? RaceStore.climbs.first?.route

    private var modeIndex: Int {
        switch mode {
        case .free: 2
        case .workout: 3
        case .route: 4
        }
    }

    private var freeTitle: String {
        guard mode == .free else { return "Just pedal." }
        return switch terrain {
        case .manual: "Just pedal."
        case .auto: "\(plan.terrainType.rawValue.capitalized) roads"
        case .draw: "Your drawing"
        }
    }

    private var freeDetail: String {
        guard mode == .free, terrain != .manual else { return "Shift freely. Nothing to follow." }
        return (plan.plannedMinutes.map { "\($0) min" } ?? "Open-ended") + " · " + plan.effort.rawValue.capitalized
    }

    private var workoutDetail: String {
        guard let w = plan.workout else { return "Intervals in ERG or on gradients." }
        let length = w.isRampTest ? "Until you stop" : TimeFormat.clock(w.duration)
        return w.isRampTest ? length : "\(length) · TSS \(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded()))"
    }

    private var routeDetail: String {
        guard let r = plan.route else { return "Famous climbs and Grand Tour stages." }
        let units = prefs.units
        return String(format: "%.1f %@ · %.0f %@", units.distance(r.distanceM), units.distanceUnit,
                      units.elevation(r.ascentM), units.elevationUnit)
    }

    // MARK: Your ride

    private func rideSetup(compact: Bool, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your ride")
            if stacked {
                VStack(alignment: .leading, spacing: Design.Space.gap) {
                    options.card()
                    preview.frame(minHeight: 280)
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    options.card().frame(width: 440)
                    preview.frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch mode {
            case .free:
                field("Duration · min") {
                    Segmented(options: SessionPlan.durations.map { ($0, $0.map { "\($0)" } ?? "Open") },
                              selection: $plan.plannedMinutes)
                }
                field("Terrain") {
                    Segmented(options: [(TerrainChoice.manual, "Manual"), (.auto, "Auto"), (.draw, "Draw")],
                              selection: Binding(get: { terrain }, set: { select($0) }))
                }
                if terrain != .manual {
                    field("Effort") {
                        Segmented(options: Effort.allCases.map { ($0, $0.rawValue.capitalized) }, selection: $plan.effort)
                    }
                }
                if terrain == .auto {
                    field("Type") {
                        Segmented(options: TerrainType.allCases.map { ($0, $0.rawValue.capitalized) },
                                  selection: $plan.terrainType)
                    }
                }
            case .workout:
                field("Workout") {
                    ChooserRow(title: plan.workout?.name ?? "Choose a workout",
                               subtitle: plan.workout.map { $0.isRampTest ? "Until you stop" : TimeFormat.clock($0.duration) } ?? "",
                               action: { pickingWorkout = true })
                }
                field("Targets") {
                    VStack(alignment: .leading, spacing: 8) {
                        Segmented(options: [(true, "ERG"), (false, "Gradient")],
                                  selection: Binding(get: { plan.usesERG }, set: { plan.workoutERG = $0 }))
                        Text(targetsNote)
                            .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .route:
                field("Route") {
                    ChooserRow(title: plan.route?.name ?? "Choose a route",
                               subtitle: plan.route.map { String(format: "%.1f %@ · ", prefs.units.distance($0.distanceM), prefs.units.distanceUnit)
                                   + TimeFormat.estimate(RouteStats.of($0).estimatedSeconds) } ?? "",
                               action: { pickingRoute = true })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
            content()
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            switch mode {
            case .free:
                switch terrain {
                case .manual: ManualPreview(gearCount: prefs.gearCount, minutes: plan.plannedMinutes)
                case .auto: CoursePreview(plan: plan) { plan.seed = UInt64.random(in: 1...UInt64(Int64.max)) }
                case .draw:
                    DrawCoursePreview(heights: Binding(get: { plan.drawing ?? DrawnCourse.starter },
                                                       set: { plan.drawing = $0 }),
                                      effort: plan.effort, minutes: plan.plannedMinutes)
                }
            case .workout:
                if let workout = plan.workout { WorkoutPreview(workout: workout, ftp: prefs.ftp) }
            case .route:
                if let route = plan.route { RoutePreview(route: route, units: prefs.units) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 22)
    }

    // MARK: Summary

    private var summaryTitle: String {
        switch mode {
        case .free: "Free ride"
        case .workout: plan.workout?.name ?? "Workout"
        case .route: plan.route?.name ?? "Route"
        }
    }

    private var summaryDetail: String {
        let units = prefs.units
        switch mode {
        case .free:
            let duration = plan.plannedMinutes.map { "\($0) min" } ?? "Open-ended"
            switch terrain {
            case .manual: return "\(duration) · Manual gradient"
            case .draw: return "\(duration) · Drawn course · \(plan.effort.rawValue.capitalized)"
            case .auto: return [duration, plan.terrainType.rawValue.capitalized, plan.effort.rawValue.capitalized].joined(separator: " · ")
            }
        case .workout:
            guard let w = plan.workout else { return "" }
            let length = w.isRampTest ? "Until you stop" : TimeFormat.clock(w.duration)
            let targets = plan.usesERG && hub.trainer.supportsERG ? "ERG" : "Gradient"
            return "\(length) · \(targets) · FTP \(prefs.ftp) W"
        case .route:
            guard let r = plan.route else { return "" }
            return String(format: "%.1f %@ · %.0f %@ climbing · ", units.distance(r.distanceM), units.distanceUnit,
                          units.elevation(r.ascentM), units.elevationUnit) + TimeFormat.estimate(RouteStats.of(r).estimatedSeconds)
        }
    }
}
