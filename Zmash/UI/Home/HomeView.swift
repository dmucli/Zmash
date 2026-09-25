import SwiftUI
import ZmashKit

/// Home (D148): the top bar, a greeting with the week so far, and four cards: the training plan, Free ride, Workout
/// and Route. Each card opens its page, where the ride is chosen, previewed and started. On an iPad the cards fill the
/// screen two by two; on a phone, or with large text, they stack and the page scrolls.
struct HomeView: View {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let navigate: (AppPage) -> Void
    let openRiders: () -> Void

    @Environment(Preferences.self) private var prefs
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [RideKind] = []
    @State private var week: WidgetSummary?
    /// A ride set up elsewhere (Siri, the plan's Ride this without a trainer), for the page it opens.
    @State private var prepared: SessionPlan?

    enum RideKind: Hashable { case plan, free, workout, route }

    private var context: RideContext { RideContext(hub: hub, start: start, openDevices: { navigate(.devices) }) }
    private var trainerReady: Bool { hub.trainer.link == .ready }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let compact = geo.size.width < 700
                let fixed = !compact && geo.size.height >= 600 && !typeSize.isAccessibilitySize
                Group {
                    if fixed {
                        page(compact: false, fixed: true)
                    } else {
                        ScrollView { page(compact: compact, fixed: false) }.scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
            .screenBackground()
            // Hidden here; it names the pages' back button "Home".
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RideKind.self) { kind in
                switch kind {
                case .plan: PlanPage(context: context)
                case .free: FreeRidePage(context: context, initial: prepared)
                case .workout: WorkoutPage(context: context, initial: prepared)
                case .route: RoutePage(context: context, initial: prepared)
                }
            }
        }
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
        }
        #if DEBUG
        .onAppear {
            // -ZmashOpen plan|free|workout|route: open that page (with -ZmashTab for its tab).
            let kinds: [String: RideKind] = ["plan": .plan, "free": .free, "workout": .workout, "route": .route]
            if let kind = DebugLaunch.open.flatMap({ kinds[$0] }), path.isEmpty { path = [kind] }
        }
        #endif
    }

    /// A ride to start on its page: the Workout page for a workout (a plan's session too), Route for a route,
    /// Free ride otherwise.
    private func open(_ plan: SessionPlan) {
        prepared = plan
        path = [plan.workoutID != nil ? .workout : plan.routeID != nil ? .route : .free]
    }

    private func page(compact: Bool, fixed: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 18) {
            TopBar(hub: hub, page: .home, compact: compact, narrow: !compact && !fixed, navigate: navigate, manageRiders: openRiders)
            greeting(compact: compact)
            cards(compact: compact, fixed: fixed)
        }
        .frame(maxWidth: Design.Space.column + 140, maxHeight: fixed ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
        .padding(.top, 5)
        .padding(.bottom, fixed ? 20 : Design.Space.block)
        .frame(maxWidth: .infinity)
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

    // MARK: The four cards

    @ViewBuilder
    private func cards(compact: Bool, fixed: Bool) -> some View {
        if fixed {
            VStack(spacing: Design.Space.gap) {
                HStack(spacing: Design.Space.gap) { planCard(compact: false); freeCard(compact: false) }
                HStack(spacing: Design.Space.gap) { workoutCard(compact: false); routeCard(compact: false) }
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: compact ? 12 : Design.Space.gap) {
                planCard(compact: compact).frame(minHeight: compact ? 190 : 240)
                freeCard(compact: compact).frame(minHeight: compact ? 170 : 220)
                workoutCard(compact: compact).frame(minHeight: compact ? 170 : 220)
                routeCard(compact: compact).frame(minHeight: compact ? 170 : 220)
            }
        }
    }

    private func planCard(compact: Bool) -> some View {
        PlanHomeCard(compact: compact, open: { path = [.plan] }, ride: { session in
            // Straight into the ride with a trainer; without one, on its page, where Start asks to connect.
            if trainerReady {
                prefs.lastPlan = session
                start(session)
            } else {
                open(session)
            }
        })
    }

    private func freeCard(compact: Bool) -> some View {
        HomeCard(title: "Free ride", description: "Just ride. Set the gradient yourself, roll a course, or draw your own hill.",
                 compact: compact, action: { prepared = nil; path = [.free] }) {
            DrawnSilhouette(heights: prefs.lastPlan.drawing ?? DrawnCourse.starter, drawing: false)
        }
    }

    private func workoutCard(compact: Bool) -> some View {
        let workout = prefs.lastWorkoutID.flatMap(WorkoutStore.workout) ?? WorkoutStore.workout(id: WorkoutPage.firstChoice)
        return HomeCard(title: "Workout", description: "Structured intervals, held in ERG or ridden on gradients.",
                        compact: compact, action: { prepared = nil; path = [.workout] }) {
            if let workout { WorkoutStrip(workout: workout.drawable) }
        }
    }

    private func routeCard(compact: Bool) -> some View {
        let route = (prefs.lastRouteID ?? RoutePage.firstChoice).flatMap { RouteStore.route(id: RouteStore.split($0).base) }
        return HomeCard(title: "Route", description: "Real stages from the Grand Tours and classics, or your own roads.",
                        compact: compact, action: { prepared = nil; path = [.route] }) {
            if let route { RouteStrip(route: route) }
        }
    }
}
