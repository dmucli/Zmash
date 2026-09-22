import SwiftUI
import ZmashKit

/// Phase 3 UI customisation: what the ride screen shows and how, with a live preview.
struct DisplaySettingsView: View {
    @Environment(Preferences.self) private var prefs

    private let slotNames = ["Top left", "Bottom left", "Top right", "Bottom right"]

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                DashboardPreview(config: prefs.display, units: prefs.units)
                    .listRowInsets(EdgeInsets())
            }

            Section("Numbers") {
                Picker("Big number", selection: $prefs.display.hero) {
                    ForEach(DisplayMetric.allCases) { Text($0.label).tag($0) }
                }
                ForEach(0..<4, id: \.self) { i in
                    Picker(slotNames[i], selection: slotBinding(i)) {
                        ForEach(DisplayMetric.allCases) { Text($0.label).tag($0) }
                    }
                }
            }

            Section("Style") {
                Picker("Typeface", selection: $prefs.display.style) {
                    Text("Rounded").tag(NumberStyle.rounded)
                    Text("Standard").tag(NumberStyle.standard)
                    Text("Mono").tag(NumberStyle.mono)
                }
                .pickerStyle(.segmented)
                Picker("Weight", selection: $prefs.display.weight) {
                    Text("Regular").tag(NumberWeight.regular)
                    Text("Medium").tag(NumberWeight.medium)
                    Text("Semibold").tag(NumberWeight.semibold)
                    Text("Bold").tag(NumberWeight.bold)
                }
                .pickerStyle(.segmented)
                Picker("Big number size", selection: $prefs.display.heroScale) {
                    Text("Small").tag(0.8)
                    Text("Medium").tag(1.0)
                    Text("Large").tag(1.2)
                }
                .pickerStyle(.segmented)
                Toggle("Colour by grade", isOn: $prefs.display.gradeColor)
                Toggle("Wind background", isOn: $prefs.windBackground)
            }

            Section {
                Button("Restore defaults") { prefs.display = .standard }
                    .disabled(prefs.display == .standard)
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func slotBinding(_ i: Int) -> Binding<DisplayMetric> {
        Binding(
            get: { prefs.display.slot(i) },
            set: { value in
                var slots = (0..<4).map { prefs.display.slot($0) }
                slots[i] = value
                prefs.display.slots = slots
            })
    }
}

/// The landscape ride screen at iPad size, scaled down, with sample values.
private struct DashboardPreview: View {
    let config: DisplayConfig
    let units: Units
    private let full = CGSize(width: 1194, height: 834)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / full.width
            RideDashboard(readout: .sample, config: config, units: units, size: full, compact: false)
                .frame(width: full.width, height: full.height)
                .background(Design.Palette.background)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: full.height * scale, alignment: .topLeading)
        }
        .aspectRatio(full.width / full.height, contentMode: .fit)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
