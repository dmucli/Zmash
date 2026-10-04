import SwiftUI
import ZmashKit

/// Home (D148, D149, D158), after the design system's prototype: the top bar, the greeting with the week so far, and the
/// training plan as the glass hero (D176) beside Free ride, Workout and Route. Each opens its page in place, under the same
/// top bar, where the ride is chosen and started. On a phone, or with large text, the cards stack and the page scrolls.
struct HomeView: View {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let navigate: (AppPage) -> Void
    let openRiders: () -> Void

    @Environment(Preferences.self) private var prefs
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The ride page open in place of the cards; nil: home.
    @State private var page: RideKind?
    @State private var week: WidgetSummary?
    /// A ride set up elsewhere (Siri, the plan's Ride this without a trainer), for the page it opens.
    @State private var prepared: SessionPlan?

    enum RideKind: Hashable { case plan, free, workout, route }

    private var trainerReady: Bool { hub.trainer.link == .ready }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 700
            let fixed = !compact && geo.size.height >= 600 && !typeSize.isAccessibilitySize
            VStack(alignment: .leading, spacing: 0) {
                TopBar(hub: hub, page: .home, compact: compact, narrow: geo.size.width < 1000, navigate: { p in
                    if p == .home { go(nil) } else { navigate(p) }
                }, manageRiders: openRiders)
                if let page {
                    ridePage(page, compact: compact)
                        .padding(.top, compact ? 4 : 6)
                        .padding(.bottom, compact ? 12 : 24)
                        .transition(.opacity)
                } else if fixed {
                    home(compact: false, portrait: geo.size.height > geo.size.width)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                } else {
                    ScrollView { home(compact: compact, portrait: true).padding(.bottom, Design.Space.block) }
                        .scrollBounceBehavior(.basedOnSize)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: Design.Space.column + 140, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .onChange(of: IntentRouter.shared.prepared, initial: true) { _, plan in
            // Set up by Siri, or a plan's Ride this, while the trainer wasn't connected: open it on its page.
            guard let plan else { return }
            IntentRouter.shared.prepared = nil
            open(plan)
        }
        // Again after a ride is saved or deleted, so "this week" and the widgets include it.
        .task(id: "\(prefs.riderID)|\(RideChanges.shared.revision)") {
            WidgetBridge.refresh(prefs: prefs)
            week = WidgetBridge.summary(prefs: prefs)
            // What's planned on intervals.icu, for the hero and the Planned tab (D153).
            await PlannedWorkouts.shared.refreshIfStale()
        }
        #if DEBUG
        .onAppear {
            // -ZmashOpen plan|free|workout|route: open that page (with -ZmashTab for its tab).
            let kinds: [String: RideKind] = ["plan": .plan, "free": .free, "workout": .workout, "route": .route]
            if let kind = DebugLaunch.open.flatMap({ kinds[$0] }), page == nil { page = kind }
        }
        #endif
    }

    private func go(_ kind: RideKind?) {
        if kind != .workout && kind != .route && kind != .free { prepared = nil }
        withAnimation(Design.Motion.base) { page = kind }
    }

    /// A ride to start on its page: the Workout page for a workout (a plan's session too), Route for a route,
    /// Free ride otherwise.
    private func open(_ plan: SessionPlan) {
        prepared = plan
        withAnimation(Design.Motion.base) { page = plan.workoutID != nil ? .workout : plan.routeID != nil ? .route : .free }
    }

    @ViewBuilder
    private func ridePage(_ kind: RideKind, compact: Bool) -> some View {
        let context = RideContext(hub: hub, start: start, openDevices: { navigate(.devices) }, back: {
            prepared = nil
            go(nil)
        })
        switch kind {
        case .plan: PlanPage(context: context, compact: compact)
        case .free: FreeRidePage(context: context, compact: compact, initial: prepared)
        // Home's Workout card opens on the chosen workout's details (D163).
        case .workout: WorkoutPage(context: context, compact: compact, initial: prepared, details: true)
        case .route: RoutePage(context: context, compact: compact, initial: prepared)
        }
    }

    private func home(compact: Bool, portrait: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 26) {
            greeting(compact: compact).padding(.top, compact ? 0 : 6)
            cards(compact: compact, portrait: portrait)
        }
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
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateLine).monoLabel(12).foregroundStyle(Design.Palette.fg3)
                    hello.textStyle(.display, size: 48).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let week, week.weekRides > 0 {
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
                    .fixedSize()
                }
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

    // MARK: The cards

    /// On its side, the prototype's grid: the hero on the left, the three others stacked on the right, Free ride on top
    /// (D158). Upright, the hero on top, Free ride across under it, and the other two side by side. On a phone, one
    /// column. Free ride is only its heading (D174), so it's short. Without a plan, the hero is only an invitation and as
    /// tall as its words (D181): the others take the room, Workout under it on its side.
    @ViewBuilder
    private func cards(compact: Bool, portrait: Bool) -> some View {
        // Follows plans started, finished or left.
        let _ = PlanChanges.shared.revision
        let invites = PlanHero.invites
        if compact {
            VStack(spacing: 12) {
                if invites {
                    hero(compact: true).fixedSize(horizontal: false, vertical: true)
                } else {
                    hero(compact: true).frame(minHeight: 360)
                }
                freeTile(compact: true).frame(height: HomeBar.height(compact: true))
                workoutTile(compact: true).frame(height: 220)
                routeTile(compact: true).frame(height: 220)
            }
        } else if portrait {
            VStack(spacing: 16) {
                if invites {
                    hero(compact: false).fixedSize(horizontal: false, vertical: true)
                } else {
                    hero(compact: false).frame(maxHeight: .infinity)
                }
                freeTile(compact: false).frame(height: HomeBar.height(compact: false))
                HStack(spacing: 16) {
                    workoutTile(compact: false)
                    routeTile(compact: false)
                }
                .frame(minHeight: 290, maxHeight: invites ? .infinity : 290)
            }
        } else {
            GeometryReader { geo in
                let left = (geo.size.width - 16) * 1.55 / 2.55
                HStack(spacing: 16) {
                    if invites {
                        VStack(spacing: 16) {
                            hero(compact: false).fixedSize(horizontal: false, vertical: true)
                            workoutTile(compact: false)
                        }
                        .frame(width: left)
                        VStack(spacing: 16) {
                            freeTile(compact: false).frame(height: HomeBar.height(compact: false))
                            routeTile(compact: false)
                        }
                    } else {
                        hero(compact: false).frame(width: left)
                        VStack(spacing: 16) {
                            freeTile(compact: false).frame(height: HomeBar.height(compact: false))
                            workoutTile(compact: false)
                            routeTile(compact: false)
                        }
                    }
                }
            }
        }
    }

    private func hero(compact: Bool) -> some View {
        PlanHero(compact: compact, open: { go(.plan) }, ride: { session in
            // Straight into the ride with a trainer; without one, on its page, where Start asks to connect.
            if trainerReady {
                prefs.lastPlan = session
                start(session)
            } else {
                open(session)
            }
        }, openWorkout: { open($0) })
    }

    private func workoutTile(compact: Bool) -> some View {
        let workout = prefs.lastWorkoutID.flatMap(WorkoutStore.workout) ?? WorkoutStore.workout(id: WorkoutPage.firstChoice)
        let line = workout.map { w -> String in
            if w.isRampTest { return "~20 min · until you stop" }
            let erg = prefs.lastPlan.usesERG && hub.trainer.supportsERG ? "ERG" : "Gradient"
            return "\(TimeFormat.clock(w.duration)) · TSS \(Int(w.estimatedLoad(ftp: Double(prefs.ftp)).tss.rounded())) · \(erg)"
        } ?? ""
        return HomeTile(kind: "Workout", icon: "activity", title: workout?.name ?? "Workouts", line: line, description: workout?.summary ?? "",
                        compact: compact, action: { go(.workout) }) {
            if let workout { WorkoutStrip(workout: workout.drawable) }
        }
    }

    private func routeTile(compact: Bool) -> some View {
        let id = prefs.lastRouteID ?? RoutePage.firstChoice
        let route = id.flatMap { RouteStore.route(id: RouteStore.split($0).base) }
        let units = prefs.units
        let line = route.map { String(format: "%.0f %@ · %.0f %@", units.distance($0.distanceM), units.distanceUnit,
                                      units.elevation($0.ascentM), units.elevationUnit) } ?? ""
        return HomeTile(kind: "Route", icon: "route", title: route?.name ?? "Routes", line: line, description: route.map(routeSentence) ?? "",
                        fullBleed: true, compact: compact, action: { go(.route) }) {
            if let route { RouteStrip(route: route) }
        }
    }

    /// "3 climbs, the steepest kilometre at 9.8 %. About 5:10 h at your pace."
    private func routeSentence(_ route: Route) -> String {
        let stats = RouteStats.of(route, prefs: prefs)
        let n = stats.climbs.count
        let climbs = n == 0 ? "No climbs to speak of." : "\(n) climb\(n == 1 ? "" : "s"), the steepest kilometre at "
            + String(format: "%.1f %%.", stats.steepestKm)
        let s = Int(stats.estimatedSeconds)
        return climbs + String(format: " About %d:%02d h at your pace.", s / 3600, s % 3600 / 60)
    }

    private func freeTile(compact: Bool) -> some View {
        HomeBar(kind: "Free ride", icon: "bike", compact: compact, action: { go(.free) })
    }
}
