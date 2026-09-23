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
                    rideSetup(compact: compact)
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
        guard link == .ready else { return (link.label, link.color) }
        return (hub.trainer.activeProtocol == .zwift ? "Connected · Zwift" : "Connected · FTMS", Self.ok)
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

    private func rideSetup(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your ride")
            if compact {
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
                case .manual: ManualPreview(gearCount: prefs.gearCount)
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

// MARK: - Pieces

/// History / Settings: icon and word on a wide screen, icon only when space is tight.
private struct HeaderButton: View {
    let icon: String
    let title: String
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(icon, size: 20)
                if showsTitle { Text(title).font(Design.Font.label) }
            }
            .foregroundStyle(Design.Palette.primary)
            .padding(.horizontal, showsTitle ? 16 : 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// One device: what it is, whether it's there, and a way into Devices.
private struct DeviceCard: View {
    let icon: String
    let title: String
    let status: String
    let dot: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(icon, size: 22)
                    .foregroundStyle(Design.Palette.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Design.Palette.background))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        Text(status).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Devices")
    }
}

/// The chosen workout or route, with a way to change it.
private struct ChooserRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text("Change").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Pinned to the bottom: what's about to start, and Start. Without a trainer it says so and opens Devices.
private struct StartBar: View {
    let title: String
    let detail: String
    let ready: Bool
    let compact: Bool
    let start: () -> Void
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Design.Palette.hairline).frame(height: 1)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Design.Palette.primary)
                    Text(detail).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if ready {
                    PrimaryButton(title: "Start", action: start)
                        .frame(width: compact ? 140 : 240)
                        .keyboardShortcut(.return, modifiers: [])
                } else {
                    PrimaryButton(title: "Connect trainer", action: connect)
                        .frame(width: compact ? 180 : 240)
                }
            }
            .frame(maxWidth: Design.Space.column)
            .padding(.horizontal, compact ? Design.Space.gutter : 40)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .background(Design.Palette.background.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Previews of the ride

/// A number and what it is, for the facts under a preview.
struct Fact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Design.Font.number(24)).foregroundStyle(Design.Palette.primary)
            Text(label).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
        }
    }
}

struct PreviewTitle: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Design.Palette.primary)
            if !subtitle.isEmpty {
                Text(subtitle).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Auto terrain: the generated course as the real road you'll ride — metres of climbing and kilometres at your pace,
/// on an honest scale (a flat course looks flat) — plus a way to roll another.
private struct CoursePreview: View {
    let plan: SessionPlan
    let reroll: () -> Void
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let route = course
        let stats = route.map { RouteStats.of($0) }
        let units = prefs.units
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PreviewTitle(title: "Your course", subtitle: subtitle(stats))
                Spacer()
                Button(action: reroll) {
                    HStack(spacing: 6) {
                        Icon("dices", size: 18)
                        Text("New course").font(Design.Font.small)
                    }
                    .foregroundStyle(Design.Palette.primary)
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .background(Capsule().fill(Design.Palette.background))
                }
                .buttonStyle(.plain)
            }
            if let route, let stats {
                ElevationProfile(route: route, climbs: stats.climbs, units: units, minRelief: honestRelief)
                    .frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: route.elevations)
                HStack(spacing: 28) {
                    Fact(value: plan.plannedMinutes.map { "\($0) min" } ?? "10 min", label: plan.plannedMinutes == nil ? "first block" : "length")
                    Fact(value: String(format: "≈ %.1f", units.distance(route.distanceM)), label: units.distanceUnit)
                    Fact(value: String(format: "%.0f", units.elevation(route.ascentM)), label: units.elevationUnit + " climbing")
                    Fact(value: String(format: "%.1f %%", route.steepestKmGrade), label: "steepest km")
                    Fact(value: "\(stats.climbs.count)", label: stats.climbs.count == 1 ? "climb" : "climbs")
                }
            }
        }
    }

    @MainActor private static var cache: [String: Route] = [:]

    /// The height scale: 40 % of what your pace could climb in this time (≈ P ÷ m·g per second). A mountain course
    /// fills the card at any length, and a flat one stays a gentle line, instead of every course being stretched to fit.
    private var honestRelief: Double {
        let seconds = plan.plannedSeconds ?? 600
        let climbRate = Double(prefs.ftp) * RouteStats.paceShare / (prefs.rider.massKg * RiderModel.g)
        return max(40, 0.4 * climbRate * seconds)
    }

    /// The generated course ridden at the estimate pace (70 % FTP), cached per plan and pace.
    private var course: Route? {
        let pace = Double(prefs.ftp) * RouteStats.paceShare
        let id = "course|\(plan.seed)|\(plan.terrainType.rawValue)|\(plan.effort.rawValue)|\(plan.plannedMinutes ?? 0)|\(Int(pace))|\(prefs.riderKg)|\(prefs.bikeKg)"
        if let hit = Self.cache[id] { return hit }
        guard let route = plan.profile()?.route(rider: prefs.rider, powerW: pace, id: id, name: "Your course") else { return nil }
        Self.cache[id] = route
        return route
    }

    private func subtitle(_ stats: RouteStats?) -> String {
        let what = "\(plan.terrainType.rawValue.capitalized) · \(plan.effort.rawValue.capitalized)"
        let pace = stats.map { " · ridden at \($0.paceW) W" } ?? ""
        return plan.plannedMinutes == nil ? "\(what) · the first ten minutes; more is made as you ride" : what + pace
    }
}

/// Manual gradient: nothing to preview, so say how it works.
private struct ManualPreview: View {
    let gearCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewTitle(title: "Manual gradient",
                         subtitle: "You set the gradient as you ride, with the D-pad or the on-screen controls.")
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("0.0 %").font(Design.Font.number(64, weight: .medium)).foregroundStyle(Design.Palette.primary)
                Text("where you start").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                Fact(value: String(format: "±%.1f %%", RideControls.gradeStep), label: "per press")
                Fact(value: String(format: "−%.0f to +%.0f %%", abs(RideControls.gradeRange.lowerBound), RideControls.gradeRange.upperBound),
                     label: "range")
                Fact(value: "\(gearCount)", label: "gears")
            }
        }
    }
}

/// A workout: its shape, and what it will cost.
private struct WorkoutPreview: View {
    let workout: Workout
    let ftp: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewTitle(title: workout.name, subtitle: workout.summary)
            WorkoutStrip(workout: workout.isRampTest ? rampPreview : workout, color: Design.Palette.primary)
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
            HStack(spacing: 28) {
                if workout.isRampTest {
                    Fact(value: "~20 min", label: "typical")
                    Fact(value: "\(ftp / 2) W", label: "first step")
                    Fact(value: "+6 %", label: "each minute")
                } else {
                    let load = estimatedLoad
                    Fact(value: TimeFormat.clock(workout.duration), label: "length")
                    Fact(value: "\(Int(load.tss.rounded()))", label: "tss")
                    Fact(value: String(format: "%.2f", load.intensityFactor), label: "intensity")
                }
                Fact(value: "\(ftp) W", label: "ftp")
            }
        }
    }

    /// The load the workout asks for if every target is held (free steps counted at 60 % FTP).
    private var estimatedLoad: Training.Load {
        let watts = workout.steps.flatMap { s in
            (0..<s.seconds).map { Int(((s.fraction(at: Double($0)) ?? 0.6) * Double(ftp)).rounded()) }
        }
        return Training.load(watts, ftp: Double(ftp))
    }

    /// The ramp test is open-ended; preview the part most riders reach.
    private var rampPreview: Workout {
        var p = workout
        p.steps = Array(workout.steps.prefix(16))
        return p
    }
}

/// A route: its profile and the numbers that matter on a climb.
private struct RoutePreview: View {
    let route: Route
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewTitle(title: route.name, subtitle: route.approximate ? "\(route.place) · approximate profile" : route.place)
            RouteStrip(route: route, color: Design.Palette.primary)
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
            let stats = RouteStats.of(route)
            HStack(spacing: 28) {
                Fact(value: String(format: "%.1f", units.distance(route.distanceM)), label: units.distanceUnit)
                Fact(value: String(format: "%.0f", units.elevation(route.ascentM)), label: units.elevationUnit + " climbing")
                Fact(value: TimeFormat.estimate(stats.estimatedSeconds), label: "at \(stats.paceW) W")
                Fact(value: "\(stats.climbs.count)", label: stats.climbs.count == 1 ? "climb" : "climbs")
                Fact(value: String(format: "%.1f %%", route.steepestKmGrade), label: "steepest km")
            }
        }
    }
}

/// Draw: drag a finger across the card to shape the course. The line is the hill's silhouette over the
/// whole ride; Effort sets how steep its steepest climb gets. Dragging again repaints only what you cross.
private struct DrawCoursePreview: View {
    @Binding var heights: [Double]
    let effort: Effort
    let minutes: Int?

    /// The stroke in progress, committed when the finger lifts (one write to the plan per stroke).
    @State private var live: [Double]?
    @State private var last: (index: Int, value: Double)?

    var body: some View {
        let shown = live ?? heights
        let grades = DrawnCourse.grades(shown, effort: effort)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PreviewTitle(title: "Draw your course",
                             subtitle: "Drag across the card to shape the hill. Effort sets how steep it gets.")
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.25)) { heights = DrawnCourse.blank }
                } label: {
                    Text("Clear").font(Design.Font.small)
                        .foregroundStyle(Design.Palette.primary)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Capsule().fill(Design.Palette.background))
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                DrawnSilhouette(heights: shown, drawing: live != nil)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { paint(at: $0.location, in: geo.size) }
                            .onEnded { _ in
                                if let live { heights = live }
                                live = nil
                                last = nil
                            })
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
            .accessibilityLabel("Course drawing")
            .accessibilityHint("Drag across to shape the course")
            HStack(spacing: 28) {
                Fact(value: minutes.map { "\($0) min" } ?? "30 min", label: minutes == nil ? "per lap" : "length")
                Fact(value: String(format: "%+.1f %%", grades.max() ?? 0), label: "steepest")
                Fact(value: String(format: "−%.1f %%", abs(min(grades.min() ?? 0, 0))), label: "fastest descent")
            }
        }
    }

    /// Sets the heights under the finger, filling any points a fast stroke skipped.
    private func paint(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        var h = live ?? DrawnCourse.resample(heights, count: DrawnCourse.points)
        let n = h.count
        let index = min(max(Int((point.x / size.width * Double(n - 1)).rounded()), 0), n - 1)
        let value = min(max(1 - point.y / size.height, 0.02), 0.98)
        if let last, last.index != index {
            let step = index > last.index ? 1 : -1
            for i in stride(from: last.index, through: index, by: step) {
                let t = Double(i - last.index) / Double(index - last.index)
                h[i] = last.value + (value - last.value) * t
            }
        } else {
            h[index] = value
        }
        live = h
        last = (index, value)
    }
}

/// The drawing as a filled hill with its outline, over a quiet baseline grid.
private struct DrawnSilhouette: View {
    let heights: [Double]
    let drawing: Bool

    var body: some View {
        Canvas { ctx, size in
            for f in [0.25, 0.5, 0.75] {
                let y = size.height * f
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(Design.Palette.hairline), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            }
            guard heights.count > 1 else { return }
            let point = { (i: Int) in
                CGPoint(x: size.width * Double(i) / Double(heights.count - 1), y: size.height * (1 - heights[i]))
            }
            var outline = Path()
            outline.move(to: point(0))
            for i in 1..<heights.count { outline.addLine(to: point(i)) }
            var fill = outline
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Design.Palette.primary.opacity(drawing ? 0.24 : 0.18)))
            ctx.stroke(outline, with: .color(Design.Palette.primary.opacity(drawing ? 1 : 0.7)),
                       style: StrokeStyle(lineWidth: drawing ? 3 : 2, lineCap: .round, lineJoin: .round))
        }
    }
}
