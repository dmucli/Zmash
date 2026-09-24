import SwiftUI
import ZmashKit

/// Home, after the design system's prototype (D115), revisited (D144): the top bar (what's connected, who's riding), a
/// greeting with the week so far, today's suggestion as a strip, the three ways to ride as equal cards, and "Your ride",
/// where the ride is chosen and previewed with no sheet, over a Start bar. On an iPad it all fits without scrolling.
struct SetupView: View {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let navigate: (AppPage) -> Void
    let openRiders: () -> Void

    @Environment(Preferences.self) private var prefs
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var plan: SessionPlan = Preferences.shared.lastPlan
    /// A training plan or a campaign shown in the preview instead of the chosen workout or route.
    @State private var shownPlan: String?
    @State private var shownCampaign: String?
    /// What the Workout and Route cards show before they're chosen: what choosing them would pick.
    @State private var upNext: (workout: Workout?, route: Route?) = (nil, nil)

    /// A ride is one of three things: free (duration + terrain), a workout, or a route. Switching to Workout or Route
    /// always picks one, so the mode follows the plan.
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
        guard mode != self.mode else { return }
        shownPlan = nil
        shownCampaign = nil
        switch mode {
        case .free:
            plan.workoutID = nil
            plan.routeID = nil
        case .workout:
            plan.routeID = nil
            plan.workoutID = nextWorkoutID
        case .route:
            plan.workoutID = nil
            plan.routeID = nextRouteID
        }
    }

    /// What Workout and Route pick when switched to: the last one chosen, or the library's first and Mont Ventoux.
    private var nextWorkoutID: String? {
        prefs.lastWorkoutID.flatMap { WorkoutStore.workout(id: $0) != nil ? $0 : nil } ?? WorkoutLibrary.all.first?.id
    }

    private var nextRouteID: String? {
        prefs.lastRouteID.flatMap { RouteStore.route(id: $0) != nil ? $0 : nil } ?? Self.sampleRouteID
    }

    @MainActor private static let sampleRouteID = RaceStore.climbs.first { $0.name.contains("Ventoux") }?.id ?? RaceStore.climbs.first?.id

    private func refreshUpNext() {
        upNext = (nextWorkoutID.flatMap(WorkoutStore.workout), nextRouteID.flatMap(RouteStore.route))
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
            // An iPad holds home on one screen, "Your ride" taking what's left; a phone, a narrow window or large
            // text scrolls.
            let fixed = !compact && geo.size.height >= 640 && !typeSize.isAccessibilitySize
            Group {
                if fixed {
                    page(compact: false, wide: wide, fixed: true)
                } else {
                    ScrollView { page(compact: compact, wide: wide, fixed: false) }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StartBar(title: summaryTitle, detail: trainerReady ? summaryDetail : "Connect a trainer to start",
                         ready: trainerReady, compact: compact,
                         start: {
                             prefs.lastPlan = plan
                             start(plan)
                         },
                         connect: { navigate(.devices) })
            }
            .screenBackground()
        }
        .onChange(of: IntentRouter.shared.prepared) { _, prepared in
            // Set up by Siri, or a plan's "Ride this", while the trainer wasn't connected.
            guard let prepared else { return }
            withAnimation(Design.Motion.base) {
                plan = prepared
                shownPlan = nil
                shownCampaign = nil
            }
            IntentRouter.shared.prepared = nil
        }
        .onChange(of: plan.workoutID) { _, id in
            if let id { prefs.lastWorkoutID = id }
        }
        .onChange(of: plan.routeID) { _, id in
            if let id { prefs.lastRouteID = id }
        }
        // Again after a ride is saved or deleted, so "this week" and the widgets include it.
        .task(id: "\(prefs.riderID)|\(RideChanges.shared.revision)") {
            WidgetBridge.refresh(prefs: prefs)
            week = WidgetBridge.summary(prefs: prefs)
            refreshUpNext()
        }
        .onAppear {
            // The last plan may point at a workout or route that has since been deleted.
            if plan.workoutID != nil, plan.workout == nil { plan.workoutID = nil }
            if plan.routeID != nil, plan.route == nil { plan.routeID = nil }
            if let id = plan.workoutID { prefs.lastWorkoutID = id }
            if let id = plan.routeID { prefs.lastRouteID = id }
            refreshUpNext()
            #if DEBUG
            switch DebugLaunch.homeShow {
            case "plan": shownPlan = DebugLaunch.plan
            case "campaign": shownCampaign = DebugLaunch.race
            default: break
            }
            #endif
        }
    }

    private func page(compact: Bool, wide: Bool, fixed: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 16) {
            TopBar(hub: hub, page: .home, compact: compact, narrow: !wide, navigate: navigate, manageRiders: openRiders)
            greeting(compact: compact)
            RecapBanner()
            if todayShown { today(compact: compact) }
            modeRow(compact: compact)
            // Side by side needs room for the list and a preview wide enough for its figures.
            rideSetup(compact: compact, stacked: !wide, fixed: fixed)
        }
        .frame(maxWidth: Design.Space.column + 140, maxHeight: fixed ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
        .padding(.top, 5)
        .padding(.bottom, fixed ? 16 : Design.Space.block)
        .frame(maxWidth: .infinity)
        .animation(Design.Motion.base, value: plan.terrainMode)
        .animation(Design.Motion.base, value: plan.drawn)
        .animation(Design.Motion.base, value: plan.workoutID)
        .animation(Design.Motion.base, value: plan.routeID)
        .animation(Design.Motion.base, value: todayHiddenOn)
    }

    // MARK: Greeting

    @ViewBuilder
    private func greeting(compact: Bool) -> some View {
        let hello = Text("Ready when you are, \(firstName).").foregroundStyle(Design.Palette.fg1)
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateLine).monoLabel(12).foregroundStyle(Design.Palette.fg3)
                hello.textStyle(.display, size: 30).lineLimit(2).minimumScaleFactor(0.7)
            }
        } else {
            // One line: the greeting, and the day and the week so far on the right.
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                hello.textStyle(.display, size: 38).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(dateLine).monoLabel(12).foregroundStyle(Design.Palette.fg3)
                    if let week, week.weekRides > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("This week").monoLabel().foregroundStyle(Design.Palette.fg3).padding(.trailing, 4)
                            Text("\(week.weekRides)").font(Design.Font.bib(22)).foregroundStyle(Design.Palette.fg1)
                            Text(week.weekRides == 1 ? "ride ·" : "rides ·")
                            Text(String(format: "%d:%02d", week.weekSeconds / 3600, week.weekSeconds % 3600 / 60)).font(Design.Font.bib(22)).foregroundStyle(Design.Palette.fg1)
                            Text("h")
                        }
                        .font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fg3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .fixedSize()
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

    // MARK: Today and the three ways to ride

    private var todayShown: Bool { todayHiddenOn != TodayCard.hiddenKey(rider: prefs.riderID) }

    private func today(compact: Bool) -> some View {
        TodayCard(ride: { suggested in
            // Straight into the ride with a trainer; without one, set it up here, where the start bar asks to connect.
            if trainerReady {
                prefs.lastPlan = suggested
                start(suggested)
            } else {
                withAnimation(Design.Motion.base) {
                    plan = suggested
                    shownPlan = nil
                    shownCampaign = nil
                }
            }
        }, compact: compact)
    }

    @ViewBuilder
    private func modeRow(compact: Bool) -> some View {
        if compact {
            // Side by side, or one under the other when large text doesn't fit three across.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { modeCards(compact: true) }.fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) { modeCards(compact: true) }
            }
        } else if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { modeCards(compact: false) }
        } else {
            HStack(spacing: Design.Space.gap) { modeCards(compact: false) }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func modeCards(compact: Bool) -> some View {
        ModeCard(title: "Free ride", detail: freeDetail, selected: mode == .free, compact: compact,
                 action: { withAnimation(Design.Motion.base) { select(.free) } }) {
            LaneDashes(color: Design.Palette.fg1, thickness: 4)
                .opacity(mode == .free ? 1 : 0.35)
        }
        let workout = plan.workout ?? upNext.workout
        ModeCard(title: "Workout", detail: workout?.name ?? "Intervals in ERG or on gradients", selected: mode == .workout,
                 compact: compact, action: { withAnimation(Design.Motion.base) { select(.workout) } }) {
            if let workout {
                WorkoutStrip(workout: workout.drawable).opacity(mode == .workout ? 1 : 0.35)
            }
        }
        let route = plan.route ?? upNext.route
        ModeCard(title: "Route", detail: route?.name ?? "Famous climbs and Grand Tour stages", selected: mode == .route,
                 compact: compact, action: { withAnimation(Design.Motion.base) { select(.route) } }) {
            if let route {
                RouteStrip(route: route).opacity(mode == .route ? 1 : 0.35)
            }
        }
    }

    /// The free ride as it's set up, whether or not it's the one chosen.
    private var freeDetail: String {
        let duration = plan.plannedMinutes.map { "\($0) min" } ?? "Open-ended"
        return switch terrain {
        case .manual: "\(duration) · you set the gradient"
        case .auto: "\(duration) · \(plan.terrainType.rawValue.capitalized) · \(plan.effort.rawValue.capitalized)"
        case .draw: "\(duration) · your drawing"
        }
    }

    // MARK: Your ride

    /// What to ride and its preview, in one card split by a hairline: side by side when there's room. On an iPad it
    /// takes the rest of the screen and its two sides scroll inside it if they need to.
    private func rideSetup(compact: Bool, stacked: Bool, fixed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Your ride")
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 0) {
                        options(fixed: fixed)
                        Rectangle().fill(Design.Palette.border).frame(height: 1)
                        preview.frame(minHeight: fixed ? nil : 300)
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        options(fixed: fixed).frame(width: 420)
                        Rectangle().fill(Design.Palette.border).frame(width: 1)
                        preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Scrolling with the page: a height for the list to scroll in.
                    .frame(height: fixed ? nil : 480)
                }
            }
            .frame(maxHeight: fixed ? .infinity : nil, alignment: .top)
            .card(padding: 0)
        }
    }

    /// The left side: the free ride's settings, or the list of workouts or routes.
    @ViewBuilder
    private func options(fixed: Bool) -> some View {
        switch mode {
        case .free:
            FitOrScroll { freeOptions.padding(18) }
        case .workout:
            WorkoutBrowser(workoutID: $plan.workoutID, shownPlan: $shownPlan)
                .padding(.top, 14)
                .frame(maxHeight: fixed ? .infinity : 380)
        case .route:
            RouteBrowser(routeID: $plan.routeID, shownCampaign: $shownCampaign)
                .padding(.top, 14)
                .frame(maxHeight: fixed ? .infinity : 440)
        }
    }

    private var freeOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// ERG or gradients, under the workout's preview.
    private var targets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Targets").monoLabel().foregroundStyle(Design.Palette.fg3)
                Segmented(options: [(true, "ERG"), (false, "Gradient")],
                          selection: Binding(get: { plan.usesERG }, set: { plan.workoutERG = $0 }))
            }
            Text(targetsNote)
                .font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
            content()
        }
    }

    /// The right side: the ride as chosen, or a training plan or a campaign opened from the list.
    @ViewBuilder
    private var preview: some View {
        if mode == .workout, let id = shownPlan, let p = TrainingPlans.plan(id: id) {
            closable { shownPlan = nil } content: {
                PlanView(plan: p, close: { shownPlan = nil }, embedded: true).id(id)
            }
        } else if mode == .route, let id = shownCampaign, let race = RaceStore.races.first(where: { $0.id == id }) {
            closable { shownCampaign = nil } content: {
                CampaignView(race: race, choose: { routeID in
                    withAnimation(Design.Motion.base) {
                        plan.routeID = routeID
                        shownCampaign = nil
                    }
                }, embedded: true)
                .id(id)
            }
        } else {
            FitOrScroll { chosen.padding(22) }
        }
    }

    /// A plan or a campaign in the preview, with a way back to the chosen ride.
    private func closable(close: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                RoundIconButton(icon: "x", size: 40) { withAnimation(Design.Motion.base) { close() } }
                    .accessibilityLabel("Back to the ride")
                    .padding(14)
            }
    }

    @ViewBuilder
    private var chosen: some View {
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
                if let workout = plan.workout {
                    VStack(alignment: .leading, spacing: 18) {
                        WorkoutPreview(workout: workout, ftp: prefs.ftp)
                        targets
                    }
                }
            case .route:
                RouteSetup(routeID: $plan.routeID, units: prefs.units)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
