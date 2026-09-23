import SwiftUI
import ZmashKit

/// Home: what's connected, what you're about to ride, and a Start bar that never scrolls away.
/// Read top to bottom in the order you use it. History and Settings are reachable from here only.
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

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 700
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 28 : 36) {
                    header(compact: compact)
                    connections(compact: compact)
                    // Side by side needs room for the options and a preview wide enough for its figures.
                    rideSetup(compact: compact, stacked: geo.size.width < 1000)
                }
                .frame(maxWidth: Design.Space.column, alignment: .leading)
                .padding(.horizontal, compact ? Design.Space.gutter : 40)
                .padding(.top, compact ? Design.Space.gutter : 28)
                .padding(.bottom, Design.Space.block)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: plan.terrainMode)
                .animation(.snappy(duration: 0.25), value: plan.drawn)
                .animation(.snappy(duration: 0.25), value: plan.workoutID)
                .animation(.snappy(duration: 0.25), value: plan.routeID)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StartBar(title: summaryTitle, detail: trainerReady ? summaryDetail : "Connect a trainer to start",
                         ready: trainerReady, compact: compact,
                         start: {
                             prefs.lastPlan = plan
                             start(plan)
                         },
                         connect: openDevices)
            }
            .background(Design.Palette.background.ignoresSafeArea())
        }
        .sheet(isPresented: $pickingWorkout) { WorkoutPicker(workoutID: $plan.workoutID) }
        .sheet(isPresented: $pickingRoute) { RoutePicker(routeID: $plan.routeID) }
        .onChange(of: IntentRouter.shared.prepared) { _, prepared in
            // Set up by Siri while the trainer wasn't connected.
            guard let prepared else { return }
            withAnimation(.snappy(duration: 0.25)) { plan = prepared }
            IntentRouter.shared.prepared = nil
        }
        .task(id: prefs.riderID) { WidgetBridge.refresh(prefs: prefs) }
        .onAppear {
            // The last plan may point at a workout or route that has since been deleted.
            if plan.workoutID != nil, plan.workout == nil { plan.workoutID = nil }
            if plan.routeID != nil, plan.route == nil { plan.routeID = nil }
        }
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Text("Zmash")
                .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
                .foregroundStyle(Design.Palette.primary)
            Spacer()
            RiderMenu(compact: compact, manage: openSettings)
            HeaderButton(icon: "history", title: "History", showsTitle: !compact, action: openHistory)
            HeaderButton(icon: "settings", title: "Settings", showsTitle: !compact, action: openSettings)
        }
    }

    // MARK: Connections

    private var trainerReady: Bool { hub.trainer.link == .ready }

    private func connections(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Connections")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 1 : 3), spacing: compact ? 8 : 12) {
                let trainer = trainerStatus
                DeviceCard(icon: "bike", title: "Trainer", status: trainer.text, dot: trainer.dot, action: openDevices)
                let controller = controllerStatus
                DeviceCard(icon: "gamepad-2", title: "Controller", status: controller.text, dot: controller.dot, action: openDevices)
                let heart = heartStatus
                DeviceCard(icon: "heart", title: "Heart rate", status: heart.text, dot: heart.dot, action: openDevices)
            }
        }
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
        return battery < 15 ? ("Battery \(battery) %", .orange) : ("Connected · \(battery) %", Self.ok)
    }

    private var heartStatus: (text: String, dot: Color) {
        if let bpm = hub.heartRateBpm { return ("\(bpm) bpm", Self.ok) }
        if let strap = hub.ble?.heartRate, strap.link != .unpaired { return (strap.link.label, strap.link.color) }
        return ("Not set up", Design.Palette.hairline)
    }

    private static let ok = Color.green.opacity(0.85)

    // MARK: Your ride

    private func rideSetup(compact: Bool, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your ride")
            RecapBanner()
            TodayCard { suggested in withAnimation(.snappy(duration: 0.25)) { plan = suggested } }
                .padding(.bottom, 8)
            if stacked {
                VStack(alignment: .leading, spacing: 24) {
                    options
                    preview.frame(minHeight: 280)
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    options.frame(width: 460)
                    preview.frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 22) {
            Segmented(options: [(PlanMode.free, "Free ride"), (.workout, "Workout"), (.route, "Route")],
                      selection: Binding(get: { mode }, set: { select($0) }))
            switch mode {
            case .free:
                field("Duration") {
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
                            .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
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
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
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
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Design.Palette.surface))
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
