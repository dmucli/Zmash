import SwiftUI
import ZmashKit

/// Free ride (D148): Manual, Auto or Draw, each with its few settings, and the course (or the gears) in the preview.
struct FreeRidePage: View {
    let context: RideContext
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan

    /// Set by hand as you ride, generated, or drawn with a finger.
    enum Terrain: Hashable { case manual, auto, draw }

    init(context: RideContext, initial: SessionPlan? = nil) {
        self.context = context
        var p = initial ?? Preferences.shared.lastPlan
        p.workoutID = nil
        p.routeID = nil
        _plan = State(initialValue: p)
    }

    private var terrain: Terrain { plan.terrainMode == .manual ? .manual : plan.isDrawn ? .draw : .auto }

    private func select(_ terrain: Terrain) {
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

    var body: some View {
        RidePage(title: "Free ride", context: context,
                 start: StartInfo(title: "Free ride", detail: summary, start: {
                     prefs.lastPlan = plan
                     context.start(plan)
                 })) {
            ChooseColumn(tabs: [(Terrain.manual, "Manual"), (.auto, "Auto"), (.draw, "Draw")],
                         tab: Binding(get: { terrain }, set: { t in withAnimation(Design.Motion.base) { select(t) } }),
                         hint: hint) {
                FitOrScroll { settings.padding(18) }
            }
        } preview: {
            FitOrScroll { preview.padding(22) }
        }
        // Kept as it's changed: leaving and coming back finds it as it was.
        .onChange(of: plan) { _, p in prefs.lastPlan = p }
    }

    private var hint: String {
        switch terrain {
        case .manual: "No course: you set the gradient with the shifters as you ride."
        case .auto: "Zmash rolls a course: choose how long, how hilly and how hard."
        case .draw: "Draw the hill on the right. Effort sets how steep it gets."
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            field("Duration · min") {
                Segmented(options: SessionPlan.durations.map { ($0, $0.map { "\($0)" } ?? "Open") }, selection: $plan.plannedMinutes)
            }
            if terrain == .auto {
                field("Type") {
                    Segmented(options: TerrainType.allCases.map { ($0, $0.rawValue.capitalized) }, selection: $plan.terrainType)
                }
            }
            if terrain != .manual {
                field("Effort") {
                    Segmented(options: Effort.allCases.map { ($0, $0.rawValue.capitalized) }, selection: $plan.effort)
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

    @ViewBuilder private var preview: some View {
        Group {
            switch terrain {
            case .manual: ManualPreview(gearCount: prefs.gearCount, minutes: plan.plannedMinutes)
            case .auto: CoursePreview(plan: plan) { plan.seed = UInt64.random(in: 1...UInt64(Int64.max)) }
            case .draw:
                DrawCoursePreview(heights: Binding(get: { plan.drawing ?? DrawnCourse.starter }, set: { plan.drawing = $0 }),
                                  effort: plan.effort, minutes: plan.plannedMinutes)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summary: String {
        let duration = plan.plannedMinutes.map { "\($0) min" } ?? "Open-ended"
        return switch terrain {
        case .manual: "\(duration) · Manual gradient"
        case .draw: "\(duration) · Drawn course · \(plan.effort.rawValue.capitalized)"
        case .auto: [duration, plan.terrainType.rawValue.capitalized, plan.effort.rawValue.capitalized].joined(separator: " · ")
        }
    }
}
