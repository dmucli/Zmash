import SwiftUI
import ZmashKit

/// First launch (or Settings → Set up again): the controller, the trainer, heart rate, your numbers, then two
/// guided minutes on the bike. Every step can be skipped; nothing here is needed to ride.
struct SetupFlow: View {
    let hub: DeviceHub
    let done: () -> Void
    @Environment(Preferences.self) private var prefs
    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome, controller, trainer, heartRate, you, spin
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step != .welcome {
                    Button("Back") { withAnimation(.snappy) { step = Step(rawValue: step.rawValue - 1)! } }
                        .buttonStyle(.plain).foregroundStyle(Design.Palette.secondary).frame(minHeight: 44)
                }
                Spacer()
                // Progress: one dot per step.
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { s in
                        Capsule().fill(s.rawValue <= step.rawValue ? Design.Palette.primary : Design.Palette.hairline)
                            .frame(width: s == step ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                Spacer()
                if step != .welcome {
                    Button("Skip") { advance() }
                        .buttonStyle(.plain).foregroundStyle(Design.Palette.secondary).frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24).padding(.top, 12)
            .frame(height: 56)

            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .controller: PairStep(hub: hub, role: .ride, title: "Your controller",
                                               note: "Turn on your Zwift Ride (the left controller first), Play or Click. Close Zwift and Zwift Companion so they let go of it. No controller? The on-screen buttons do everything.")
                    case .trainer: TrainerStep(hub: hub)
                    case .heartRate: PairStep(hub: hub, role: .heartRate, title: "Heart rate",
                                              note: "Optional. Put the strap on to wake it up. Some trainers pass heart rate on too.")
                    case .you: YouStep()
                    case .spin: SpinStep(hub: hub, finish: finish)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }

            if step != .welcome, step != .spin {
                PrimaryButton(title: "Next") { advance() }
                    .frame(maxWidth: 640)
                    .padding(24)
            }
        }
        .screenBackground()
        #if DEBUG
        // -ZmashSetupStep <n>: open on a step, for screenshots.
        .onAppear { if let n = UserDefaults.standard.object(forKey: "ZmashSetupStep") as? Int ?? Int(UserDefaults.standard.string(forKey: "ZmashSetupStep") ?? ""), let s = Step(rawValue: n) { step = s } }
        #endif
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Wordmark(size: 64)
            Text("Your trainer, your controller and a screen that rides with you: shifting, gradients, real climbs and races, workouts, and your rides kept.")
                .textStyle(.h2).foregroundStyle(Design.Palette.primary)
            Text("A few minutes to set up: pair your devices, tell it about you, and try the controls on the bike.")
                .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
            PrimaryButton(title: "Set up") { advance() }
            Button("Try the demo instead") {
                if !hub.isDemo { hub.setDemo(true) }
                finish()
            }
            .buttonStyle(.plain).font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.top, 40)
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return finish() }
        withAnimation(.snappy) { step = next }
    }

    private func finish() {
        prefs.hasCompletedSetup = true
        done()
    }
}

/// Find and pair one kind of device, right here.
private struct PairStep: View {
    let hub: DeviceHub
    let role: DeviceRole
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).textStyle(.display, size: 36).foregroundStyle(Design.Palette.primary)
            Text(note).font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
            if let ble = hub.ble {
                PairList(ble: ble, role: role)
            } else {
                Text("Demo devices are standing in, so there's nothing to pair.")
                    .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CardBackground(radius: Design.Radius.md))
            }
        }
    }
}

/// What's paired for a role, and what's nearby to pair instead. Scans while it's on screen.
struct PairList: View {
    let ble: BLECentral
    let role: DeviceRole

    private var paired: [UUID] {
        _ = ble.pairingRevision
        return DeviceRegistry.ids(for: role)
    }

    private var candidates: [PairingCandidate] {
        ble.candidates.values.filter { $0.roles.contains(role) && !paired.contains($0.id) }.sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        VStack(spacing: 10) {
            if !paired.isEmpty {
                HStack {
                    Icon("check", size: 18).foregroundStyle(Design.accent(forGrade: 8))
                    Text(role == .ride ? "\(paired.count) paired" : "Paired").font(Design.Font.label)
                    Spacer()
                }
                .foregroundStyle(Design.Palette.primary)
                .padding(16)
                .background(CardBackground(radius: Design.Radius.md))
            }
            ForEach(candidates) { c in
                Button { ble.pair(c, as: role) } label: {
                    HStack {
                        Text(c.name).font(Design.Font.label)
                        Spacer()
                        Text("Pair").font(Design.Font.small)
                    }
                    .foregroundStyle(Design.Palette.primary)
                    .padding(16).frame(minHeight: 52)
                    .background(CardBackground(radius: Design.Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if candidates.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking…").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear { ble.startPairingScan() }
        .onDisappear { ble.stopScan() }
    }
}

/// Smart or basic trainer, then pair it (or its speed sensor).
private struct TrainerStep: View {
    let hub: DeviceHub
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your trainer").textStyle(.display, size: 36).foregroundStyle(Design.Palette.primary)
            Segmented(options: [(false, "Smart"), (true, "Basic (no Bluetooth control)")],
                      selection: Binding(get: { prefs.basicTrainer != nil }, set: { basic in
                          prefs.basicTrainer = basic ? prefs.basicTrainer ?? .genericFluid : nil
                          hub.refreshTrainer()
                      }))
            if let curve = prefs.basicTrainer {
                Text("Zmash works out your power from the rear wheel's speed. Pick your trainer, then pair a speed sensor.")
                    .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                Picker("Model", selection: Binding(get: { curve }, set: { prefs.basicTrainer = $0; hub.refreshTrainer() })) {
                    ForEach(TrainerPowerCurve.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                if let ble = hub.ble { PairList(ble: ble, role: .speedCadence) }
            } else {
                Text("Wake the trainer by turning the pedals. Wahoo, Tacx, Elite, Saris and other FTMS trainers all work.")
                    .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                if let ble = hub.ble {
                    PairList(ble: ble, role: .trainer)
                } else {
                    Text("Demo devices are standing in, so there's nothing to pair.")
                        .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
                }
            }
        }
    }
}

/// Weight, bike and FTP. Not sure of your FTP? A starting guess, and a ramp test suggested for your first ride.
private struct YouStep: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 18) {
            Text("About you").textStyle(.display, size: 36).foregroundStyle(Design.Palette.primary)
            Text("Your weight and your bike's weight make climbs feel right. FTP (the power you can hold for an hour) sets workout targets and effort colours.")
                .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)
            VStack(spacing: 0) {
                row("Your weight", String(format: "%.0f kg", prefs.riderKg)) {
                    Stepper("", value: $prefs.riderKg, in: 35...160, step: 1).labelsHidden()
                }
                Divider().overlay(Design.Palette.hairline)
                row("Bike", String(format: "%.1f kg", prefs.bikeKg)) {
                    Stepper("", value: $prefs.bikeKg, in: 4...25, step: 0.5).labelsHidden()
                }
                Divider().overlay(Design.Palette.hairline)
                row("FTP", "\(prefs.ftp) W") {
                    Stepper("", value: $prefs.ftp, in: 60...500, step: 5).labelsHidden()
                }
            }
            .padding(.horizontal, 16)
            .background(CardBackground(radius: Design.Radius.md))
            Button {
                prefs.ftp = Int((prefs.riderKg * 2.5 / 5).rounded()) * 5
                prefs.suggestRampTest = true
            } label: {
                Text(prefs.suggestRampTest ? "Starting at \(prefs.ftp) W · a ramp test is on your Today card"
                                           : "Not sure? Start from a guess and take a ramp test")
                    .font(Design.Font.small).foregroundStyle(Design.Palette.primary)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ title: String, _ value: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
            Spacer()
            Text(value).font(Design.Font.number(20)).foregroundStyle(Design.Palette.primary)
            control()
        }
        .frame(minHeight: 56)
    }
}

/// Two guided minutes: shift, raise the gradient and feel it, then a hard ten seconds. Works with the controller or
/// the buttons on screen; each part moves on by itself.
private struct SpinStep: View {
    let hub: DeviceHub
    let finish: () -> Void
    @Environment(Preferences.self) private var prefs
    @State private var part = 0
    @State private var gear = Gears.startGear
    @State private var grade = 0.0
    @State private var shifts = 0
    @State private var rises = 0
    @State private var hardSeconds = 0

    private let parts = ["Shift up twice", "Now raise the gradient", "Pedal hard for ten seconds"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your first spin").textStyle(.display, size: 36).foregroundStyle(Design.Palette.primary)
            Text("Get on the bike and pedal gently. Use your controller or the buttons below.")
                .font(Design.Font.label).foregroundStyle(Design.Palette.secondary)

            ForEach(Array(parts.enumerated()), id: \.element) { i, text in
                HStack(spacing: 12) {
                    Icon(i < part ? "check" : "chevron-right", size: 18)
                        .foregroundStyle(i < part ? Design.accent(forGrade: 8) : Design.Palette.secondary)
                    Text(text + detail(i)).font(Design.Font.label)
                        .foregroundStyle(i == part ? Design.Palette.primary : Design.Palette.secondary)
                }
            }

            HStack(spacing: 28) {
                Fact(value: "\(gear)", label: "gear")
                Fact(value: String(format: "%+.1f %%", grade), label: "gradient")
                Fact(value: hub.trainer.metrics.map { "\($0.powerW)" } ?? "–", label: "watts")
            }

            HStack(spacing: 12) {
                RoundIconButton(icon: "minus", size: 52) { hub.send(.shiftDown) }
                RoundIconButton(icon: "plus", size: 52) { hub.send(.shiftUp) }
                Spacer().frame(width: 12)
                RoundIconButton(icon: "chevron-down", size: 52) { hub.send(.gradeDown) }
                RoundIconButton(icon: "chevron-up", size: 52) { hub.send(.gradeUp) }
            }

            PrimaryButton(title: part >= parts.count ? "Start riding" : "Finish") { finish() }
                .padding(.top, 8)
        }
        .onAppear { hub.onCommand = { command in handle(command) } }
        .onDisappear {
            hub.onCommand = nil
            hub.trainer.apply(gradePercent: 0, gearRatio: Gears.ratio(for: Gears.startGear))
        }
        .task {
            // The hard ten seconds: count seconds above an honest effort for this rider.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard part == 2 else { continue }
                if let w = hub.trainer.metrics?.powerW, Double(w) >= Double(prefs.ftp) * 0.9 {
                    hardSeconds += 1
                    if hardSeconds >= 10 { withAnimation(.snappy) { part = 3 } }
                }
            }
        }
    }

    private func detail(_ i: Int) -> String {
        switch i {
        case 0: part == 0 ? " · \(shifts) of 2" : ""
        case 1: part == 1 ? " · feel it get harder" : ""
        default: part == 2 ? " · \(hardSeconds) of 10 s" : ""
        }
    }

    private func handle(_ command: RideCommand) {
        switch command {
        case .shiftUp: gear = min(gear + 1, Gears.count); if part == 0 { shifts += 1 }
        case .shiftDown: gear = max(gear - 1, 1)
        case .gradeUp: grade = min(grade + 1, 8); if part == 1 { rises += 1 }
        case .gradeDown: grade = max(grade - 1, -2)
        default: return
        }
        if part == 0, shifts >= 2 { withAnimation(.snappy) { part = 1 } }
        if part == 1, rises >= 2 { withAnimation(.snappy) { part = 2 } }
        // Feel it: the gradient, with the gear folded in as the ride does (roughly), or natively on the Zwift protocol.
        let effective = hub.trainer.handlesGearing ? grade : grade + Double(gear - Gears.startGear) * 0.5
        hub.trainer.apply(gradePercent: effective, gearRatio: Gears.ratio(for: gear))
    }
}
