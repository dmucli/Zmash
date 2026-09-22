import SwiftUI
import ZmashKit

/// Pre-ride setup (brief §8). The only place History and Settings are reachable from.
struct SetupView: View {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let openHistory: () -> Void
    let openSettings: () -> Void
    let openDevices: () -> Void
    let openFaces: () -> Void

    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan = Preferences.shared.lastPlan
    @State private var pickingWorkout = false
    @State private var pickingRoute = false

    private var canStart: Bool { hub.trainer.link == .ready }

    /// A ride is one of three things: free (duration + terrain), a workout, or a route.
    enum PlanMode { case free, workout, route }

    private var mode: PlanMode { plan.workoutID != nil ? .workout : plan.routeID != nil ? .route : .free }

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
        ZStack {
            Design.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.block) {
                    header
                    section("Ride") {
                        Segmented(options: [(PlanMode.free, "Free ride"), (.workout, "Workout"), (.route, "Route")],
                                  selection: Binding(get: { mode }, set: { select($0) }))
                    }
                    if mode == .workout {
                        WorkoutCard(plan: plan) { pickingWorkout = true }
                        if plan.workout != nil {
                            section("Targets") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Segmented(options: [(true, "ERG"), (false, "Gradient")],
                                              selection: Binding(get: { plan.usesERG }, set: { plan.workoutERG = $0 }))
                                    Text(targetsNote)
                                        .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                                }
                            }
                        }
                    } else if mode == .route {
                        RouteCard(plan: plan) { pickingRoute = true }
                    } else {
                    section("Duration") {
                        Segmented(options: SessionPlan.durations.map { ($0, $0.map { "\($0)" } ?? "Free") },
                                  selection: $plan.plannedMinutes)
                    }
                    section("Terrain") {
                        Segmented(options: [(RideControls.TerrainMode.manual, "Manual"), (.auto, "Auto")],
                                  selection: $plan.terrainMode)
                    }
                    if plan.terrainMode == .auto {
                        section("Effort") {
                            Segmented(options: Effort.allCases.map { ($0, $0.rawValue.capitalized) }, selection: $plan.effort)
                        }
                        section("Type") {
                            Segmented(options: TerrainType.allCases.map { ($0, $0.rawValue.capitalized) },
                                      selection: $plan.terrainType)
                        }
                        ProfilePreview(plan: plan) { plan.seed = UInt64.random(in: 1...UInt64(Int64.max)) }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    }
                    FaceCard(action: openFaces)
                    devices
                    PrimaryButton(title: "Start", enabled: canStart) {
                        prefs.lastPlan = plan
                        start(plan)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, Design.Space.gutter * 1.5)
                .padding(.vertical, Design.Space.block)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: plan.terrainMode)
                .animation(.snappy(duration: 0.25), value: plan.workoutID)
                .animation(.snappy(duration: 0.25), value: plan.routeID)
            }
        }
        .sheet(isPresented: $pickingWorkout) { WorkoutPicker(workoutID: $plan.workoutID) }
        .sheet(isPresented: $pickingRoute) { RoutePicker(routeID: $plan.routeID) }
    }

    private var header: some View {
        HStack {
            Text("Zmash")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Design.Palette.primary)
            Spacer()
            HStack(spacing: 8) {
                iconButton("history", label: "History", action: openHistory)
                iconButton("settings", label: "Settings", action: openSettings)
            }
        }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon).foregroundStyle(Design.Palette.primary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            content()
        }
    }

    private var devices: some View {
        HStack(spacing: 10) {
            DeviceChip(title: "Controller", link: hub.ride.link, detail: hub.ride.batteryPercent.map { "\($0) %" },
                       lowBattery: (hub.ride.batteryPercent ?? 100) < 15, action: openDevices)
            DeviceChip(title: "Trainer", link: hub.trainer.link,
                       detail: hub.isDemo ? "demo" : hub.trainer.activeProtocol.map { $0 == .ftms ? "FTMS" : "Zwift" },
                       action: openDevices)
        }
    }
}

/// The selected face, previewed with sample data. Tap to open the gallery.
private struct FaceCard: View {
    let action: () -> Void
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @State private var demo: FaceDemo?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                if let demo {
                    FacePreview(face: prefs.face, data: demo.data, dark: scheme == .dark, calm: true,
                                units: prefs.units, animate: false)
                        .aspectRatio(FaceCanvas.size.width / FaceCanvas.size.height, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                }
                HStack {
                    Text(prefs.face.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    Spacer()
                    Text("Change face").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
        .onAppear { if demo == nil { demo = FaceDemo(ftp: Double(prefs.ftp), units: prefs.units) } }
    }
}

private struct DeviceChip: View {
    let title: String
    let link: LinkState
    let detail: String?
    var lowBattery = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(lowBattery ? Color.orange : link == .ready ? Color.green.opacity(0.8) : link.dotColor)
                    .frame(width: 8, height: 8)
                Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                Spacer()
                Text(detail ?? link.label).font(Design.Font.small)
                    .foregroundStyle(lowBattery ? Color.orange : Design.Palette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfilePreview: View {
    let plan: SessionPlan
    let reroll: () -> Void

    var body: some View {
        let profile = plan.profile()
        let grades = profile?.samples(step: max(5, (profile?.duration ?? 600) / 120)) ?? []
        VStack(alignment: .leading, spacing: 8) {
            ElevationStrip(grades: grades, color: Design.Palette.primary)
                .frame(height: 72)
                .animation(.easeInOut(duration: 0.3), value: grades)
            HStack {
                Text(summary(profile)).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                Spacer()
                Button(action: reroll) {
                    Icon("dices", size: 20).foregroundStyle(Design.Palette.primary).frame(width: 44, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New profile")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }

    private func summary(_ p: TerrainProfile?) -> String {
        guard let p else { return "" }
        let maxGrade = p.segments.map(\.grade).max() ?? 0
        let climbing = p.segments.filter { $0.grade > 0 }.map(\.duration).reduce(0, +)
        let share = p.duration > 0 ? Int((climbing / p.duration * 100).rounded()) : 0
        return String(format: "max %+.1f %% · %d %% climbing", maxGrade, share)
    }
}
