import SwiftUI
import ZmashKit

/// Make or edit a workout (D102): the workout as blocks you can select and stretch, and an editor for the selected
/// step. Saves to My workouts; exports as `.zwo`.
struct WorkoutBuilder: View {
    let saved: (Workout) -> Void
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var workout: Workout
    @State private var selected: Int? = 1
    @State private var repeatTimes = 3
    @State private var file: URL?

    /// A new workout, or a copy of a library one, or an edit of one of yours.
    init(editing: Workout? = nil, saved: @escaping (Workout) -> Void) {
        self.saved = saved
        if let w = editing {
            var copy = w
            if !w.id.hasPrefix("zwo-"), !w.id.hasPrefix("custom-") {
                copy.id = "custom-" + UUID().uuidString
                copy.name = w.name + " (copy)"
            }
            _workout = State(initialValue: copy)
        } else {
            _workout = State(initialValue: Workout(id: "custom-" + UUID().uuidString, name: "My workout", summary: "", steps: [
                .init(600, .ramp(0.5, 0.75), "Warm-up"), .init(300, .steady(1.0), "Effort"),
                .init(180, .steady(0.5), "Recover"), .init(300, .ramp(0.6, 0.45), "Cool-down"),
            ]))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 10) {
                        TextField("Name", text: $workout.name).font(.system(size: 22, weight: .semibold, design: .rounded))
                        TextField("What it's for (optional)", text: $workout.summary).font(Design.Font.label)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))

                    BuilderStrip(workout: $workout, selected: $selected).frame(height: 150)
                    Text("Tap a block to edit it; drag a block's right edge to make it longer or shorter.")
                        .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)

                    totals

                    if let i = selected, i < workout.steps.count {
                        StepEditor(step: $workout.steps[i], ftp: prefs.ftp)
                        stepActions(i)
                    }
                    Button { addStep() } label: {
                        Label("Add a step", systemImage: "plus").font(Design.Font.label)
                    }
                    .buttonStyle(.plain).foregroundStyle(Design.Palette.primary).frame(minHeight: 44)
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(Design.Palette.background)
            .navigationTitle("Workout builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if let file {
                            ShareLink(item: file) { Icon("share", size: 20) }.accessibilityLabel("Export .zwo")
                        }
                        Button("Save") {
                            WorkoutStore.save(workout)
                            saved(workout)
                            dismiss()
                        }
                        .disabled(workout.steps.isEmpty || workout.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .task(id: workout) { file = exportFile() }
        }
    }

    private var totals: some View {
        let load = workout.estimatedLoad(ftp: Double(prefs.ftp))
        return HStack(alignment: .top, spacing: 28) {
            Fact(value: TimeFormat.clock(workout.duration), label: "length")
            Fact(value: "\(Int(load.tss.rounded()))", label: "tss")
            Fact(value: String(format: "%.2f", load.intensityFactor), label: "intensity")
            Spacer()
            DifficultyGauge(level: Difficulty.workout(tss: load.tss))
        }
    }

    private func stepActions(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                action("Earlier", enabled: i > 0) { workout.steps.swapAt(i, i - 1); selected = i - 1 }
                action("Later", enabled: i < workout.steps.count - 1) { workout.steps.swapAt(i, i + 1); selected = i + 1 }
                action("Duplicate") { workout.steps.insert(workout.steps[i], at: i + 1); selected = i + 1 }
                action("Delete", enabled: workout.steps.count > 1) {
                    workout.steps.remove(at: i)
                    selected = min(i, workout.steps.count - 1)
                }
            }
            if i < workout.steps.count - 1 {
                HStack(spacing: 12) {
                    Stepper("Repeat this step and the next × \(repeatTimes)", value: $repeatTimes, in: 2...12)
                        .font(Design.Font.small)
                    action("Repeat") { workout = workout.repeating(from: i, count: 2, times: repeatTimes) }
                }
            }
        }
    }

    private func action(_ title: String, enabled: Bool = true, run: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { run() } } label: {
            Text(title).font(Design.Font.small).foregroundStyle(enabled ? Design.Palette.primary : Design.Palette.hairline)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func addStep() {
        let at = (selected ?? workout.steps.count - 1) + 1
        withAnimation(.snappy(duration: 0.2)) {
            workout.steps.insert(.init(300, .steady(0.75), "Step"), at: min(at, workout.steps.count))
            selected = min(at, workout.steps.count - 1)
        }
    }

    private func exportFile() -> URL? {
        let safe = workout.name.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let url = FileManager.default.temporaryDirectory.appending(path: (safe.isEmpty ? "Workout" : safe) + ".zwo")
        return (try? ZWOWriter.write(workout).write(to: url)) != nil ? url : nil
    }
}

/// The workout as blocks: height is the target, a selected block is outlined, and each block's right edge drags.
private struct BuilderStrip: View {
    @Binding var workout: Workout
    @Binding var selected: Int?
    @State private var resizing: (index: Int, seconds: Int, total: Double)?

    var body: some View {
        GeometryReader { geo in
            let total = Double(max(workout.duration, 1))
            let peak = max(1.3, workout.steps.map { top($0) }.max() ?? 1)
            Canvas { ctx, size in
                var x = 0.0
                for (i, step) in workout.steps.enumerated() {
                    let w = Double(step.seconds) / total * size.width
                    let (a, b) = heights(step)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: size.height * (1 - a / peak)))
                    path.addLine(to: CGPoint(x: x + w, y: size.height * (1 - b / peak)))
                    path.addLine(to: CGPoint(x: x + w, y: size.height))
                    path.closeSubpath()
                    let isSel = i == selected
                    ctx.fill(path, with: .color(Design.accent(forGrade: max(a, b) * 8 - 3).opacity(isSel ? 1 : 0.75)))
                    if isSel { ctx.stroke(path, with: .color(Design.Palette.primary), lineWidth: 2.5) }
                    ctx.fill(Path(CGRect(x: x + w - 1, y: 0, width: 2, height: size.height)), with: .color(Design.Palette.background))
                    x += w
                }
                // FTP line.
                let y = size.height * (1 - 1 / peak)
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(Design.Palette.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if resizing == nil, let edge = edge(near: v.startLocation.x, width: geo.size.width, total: total),
                       abs(v.translation.width) > 3 {
                        resizing = (edge, workout.steps[edge].seconds, total)
                        selected = edge
                    }
                    if let r = resizing {
                        let delta = Double(v.translation.width) / geo.size.width * r.total
                        workout.steps[r.index].seconds = max(15, Int(((Double(r.seconds) + delta) / 15).rounded()) * 15)
                    }
                }
                .onEnded { v in
                    if resizing == nil { selected = step(at: v.location.x, width: geo.size.width, total: total) }
                    resizing = nil
                })
            .accessibilityElement()
            .accessibilityLabel("Workout blocks, \(workout.steps.count) steps")
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func heights(_ s: Workout.Step) -> (Double, Double) {
        switch s.target {
        case .steady(let f): (f, f)
        case .ramp(let a, let b): (a, b)
        case .free: (0.5, 0.5)
        }
    }

    private func top(_ s: Workout.Step) -> Double { let (a, b) = heights(s); return max(a, b) }

    private func step(at x: CGFloat, width: CGFloat, total: Double) -> Int? {
        var end = 0.0
        for (i, s) in workout.steps.enumerated() {
            end += Double(s.seconds) / total * width
            if Double(x) <= end { return i }
        }
        return workout.steps.indices.last
    }

    /// The step whose right edge is within reach of x.
    private func edge(near x: CGFloat, width: CGFloat, total: Double) -> Int? {
        var end = 0.0
        for (i, s) in workout.steps.enumerated() {
            end += Double(s.seconds) / total * width
            if abs(Double(x) - end) < 16 { return i }
        }
        return nil
    }
}

/// One step: steady, ramp or free; its length; its target(s) in % of FTP (with watts); its label.
private struct StepEditor: View {
    @Binding var step: Workout.Step
    let ftp: Int

    private enum Kind { case steady, ramp, free }

    private var kind: Kind {
        switch step.target {
        case .steady: .steady
        case .ramp: .ramp
        case .free: .free
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Label", text: $step.label).font(Design.Font.label)
            Segmented(options: [(Kind.steady, "Steady"), (.ramp, "Ramp"), (.free, "Free ride")],
                      selection: Binding(get: { kind }, set: { set($0) }))
            row("Length", TimeFormat.clock(step.seconds)) {
                Stepper("", onIncrement: { step.seconds += 15 }, onDecrement: { step.seconds = max(15, step.seconds - 15) }).labelsHidden()
            }
            switch step.target {
            case .steady(let f):
                row("Target", percent(f)) { stepper(f) { step.target = .steady($0) } }
            case .ramp(let a, let b):
                row("From", percent(a)) { stepper(a) { step.target = .ramp($0, b) } }
                row("To", percent(b)) { stepper(b) { step.target = .ramp(a, $0) } }
            case .free:
                Text("No target: ride as you like.").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }

    private func set(_ k: Kind) {
        let f: Double = switch step.target {
        case .steady(let f): f
        case .ramp(let a, let b): (a + b) / 2
        case .free: 0.6
        }
        step.target = switch k {
        case .steady: .steady(f)
        case .ramp: .ramp(max(f - 0.2, 0.3), f)
        case .free: .free
        }
    }

    private func percent(_ f: Double) -> String { "\(Int((f * 100).rounded())) % · \(Int((f * Double(ftp)).rounded())) W" }

    private func stepper(_ f: Double, _ set: @escaping (Double) -> Void) -> some View {
        Stepper("", onIncrement: { set(min(((f * 100).rounded() + 1) / 100, 2.0)) },
                onDecrement: { set(max(((f * 100).rounded() - 1) / 100, 0.3)) }).labelsHidden()
    }

    private func row(_ title: String, _ value: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
            Spacer()
            Text(value).font(Design.Font.number(18)).foregroundStyle(Design.Palette.primary)
            control()
        }
        .frame(minHeight: 44)
    }
}
