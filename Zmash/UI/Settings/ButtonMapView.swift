import SwiftUI
import ZmashKit

/// Choose what each Zwift Ride control does. On/off only offers press actions (holding it powers the controller off).
struct ButtonMapView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            section("Left controller", RideControl.allCases.filter(\.isLeft))
            section("Right controller", RideControl.allCases.filter { !$0.isLeft })
            Section {
                Button("Restore defaults") { prefs.buttonMap = .standard }
                    .disabled(prefs.buttonMap == .standard)
            } footer: {
                Text("Hold actions fire after one second. Grade actions repeat while held.")
            }
        }
        .navigationTitle("Controller buttons")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ controls: [RideControl]) -> some View {
        Section(title) {
            ForEach(controls, id: \.self) { control in
                Picker(control.name, selection: binding(for: control)) {
                    Text("Nothing").tag(RideCommand?.none)
                    ForEach(control.allowedCommands, id: \.self) { command in
                        Text(command.label).tag(RideCommand?.some(command))
                    }
                }
            }
        }
    }

    private func binding(for control: RideControl) -> Binding<RideCommand?> {
        Binding(get: { prefs.buttonMap[control] }, set: { prefs.buttonMap[control] = $0 })
    }
}

extension RideCommand {
    var label: String {
        switch self {
        case .shiftUp: "Harder gear"
        case .shiftDown: "Easier gear"
        case .gradeUp: "Grade up"
        case .gradeDown: "Grade down"
        case .pauseToggle: "Pause / resume"
        case .endSession: "End ride (hold 3 s)"
        case .toggleTheme: "Light / dark"
        case .nextFace: "Next face"
        case .zoomIn: "Zoom profile in"
        case .zoomOut: "Zoom profile out"
        case .previousFace: "Previous face"
        case .toggleControls: "Show controls"
        }
    }
}
