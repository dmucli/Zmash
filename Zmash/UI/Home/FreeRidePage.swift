import SwiftUI
import ZmashKit

/// Free ride (D148, D149): Manual, Auto or Draw, as the design system's two-card layout: the few settings beside the
/// course (or the gears), and the bar with Start.
struct FreeRidePage: View {
    let context: RideContext
    var compact = false
    @Environment(Preferences.self) private var prefs
    @State private var plan: SessionPlan

    /// Set by hand as you ride, generated, or drawn with a finger.
    enum Terrain: Hashable { case manual, auto, draw }

    init(context: RideContext, compact: Bool = false, initial: SessionPlan? = nil) {
        self.context = context
        self.compact = compact
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
        RidePage(context: context,
                 selection: Selection(title: title, meta: summary, start: {
                     prefs.lastPlan = plan
                     context.start(plan)
                 }),
                 compact: compact) {
            PickerTabs(tabs: [(Terrain.manual, "Manual"), (.auto, "Auto"), (.draw, "Draw")],
                       tab: Binding(get: { terrain }, set: { t in withAnimation(Design.Motion.base) { select(t) } }), compact: compact)
        } tools: {
            EmptyView()
        } content: {
            if compact {
                ScrollView {
                    VStack(spacing: 14) {
                        settings.card(padding: 20)
                        preview.frame(minHeight: 320).card(padding: 22)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    FitOrScroll { settings }
                        .frame(width: 360)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .card(padding: 22)
                    FitOrScroll { preview }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .card(padding: 22)
                }
            }
        }
        // Kept as it's changed: leaving and coming back finds it as it was.
        .onChange(of: plan) { _, p in prefs.lastPlan = p }
    }

    private var title: String {
        switch terrain {
        case .manual: "Just pedal."
        case .auto: "\(plan.terrainType.rawValue.capitalized) roads"
        case .draw: "Your drawing"
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(hint).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
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

    private var hint: String {
        switch terrain {
        case .manual: "Shift freely. Nothing to follow: you set the gradient with the shifters as you ride."
        case .auto: "Zmash rolls a course: choose how long, how hilly and how hard."
        case .draw: "Draw the hill on the right. Effort sets how steep it gets."
        }
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
